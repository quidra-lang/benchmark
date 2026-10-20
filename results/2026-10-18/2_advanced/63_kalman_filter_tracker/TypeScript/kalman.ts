import {
  zeros,
  identity,
  diagonal,
  product,
  transpose,
  vectorProduct,
  add,
  subtract,
  vectorAdd,
  vectorSubtract,
  inverse,
  quadratic2,
  determinant2,
} from './matrix.ts';
import type { Matrix } from './matrix.ts';
export type MotionModel = 'CV' | 'CA';
export type Position = [number, number];
export interface Initialization {
  sigma: number;
  velocityVariance: number;
  accelerationVariance: number;
}
export interface Estimate {
  x: number[];
  P: Matrix;
}
export interface Prediction extends Estimate {
  F: Matrix;
}
export interface HistoryEntry {
  estimate: Estimate;
  prediction: Prediction | null;
}
export function motion(kind: MotionModel, T: number, q: number) {
  const n = kind === 'CV' ? 4 : 6;
  const F = identity(n);
  const Q = zeros(n);
  F[0][2] = T;
  F[1][3] = T;
  let entries: [number, number, number][];
  if (kind === 'CV') {
    entries = [
      [0, 0, (q * T * T * T) / 3],
      [0, 2, (q * T * T) / 2],
      [2, 2, q * T],
    ];
  } else {
    F[0][4] = (T * T) / 2;
    F[1][5] = (T * T) / 2;
    F[2][4] = T;
    F[3][5] = T;
    entries = [
      [0, 0, (q * T * T * T * T * T) / 20],
      [0, 2, (q * T * T * T * T) / 8],
      [0, 4, (q * T * T * T) / 6],
      [2, 2, (q * T * T * T) / 3],
      [2, 4, (q * T * T) / 2],
      [4, 4, q * T],
    ];
  }
  for (let axis = 0; axis < 2; axis++) {
    for (const [i, j, value] of entries) {
      Q[i + axis][j + axis] = value;
      Q[j + axis][i + axis] = value;
    }
  }
  return { F, Q };
}
export function measurementModel(size: number, sigma: number) {
  const H = zeros(2, size);
  H[0][0] = 1;
  H[1][1] = 1;
  return { H, R: diagonal([sigma * sigma, sigma * sigma]) };
}
export function initialize(kind: MotionModel, measurement: Position, p: Initialization): Estimate {
  const x = [...measurement, 0, 0];
  const variances = [p.sigma * p.sigma, p.sigma * p.sigma, p.velocityVariance, p.velocityVariance];
  if (kind === 'CA') {
    x.push(0, 0);
    variances.push(p.accelerationVariance, p.accelerationVariance);
  }
  return { x, P: diagonal(variances) };
}
export function predict(estimate: Estimate, kind: MotionModel, T: number, q: number): Prediction {
  const { F, Q } = motion(kind, T, q);
  return {
    x: vectorProduct(F, estimate.x),
    P: add(product(product(F, estimate.P), transpose(F)), Q),
    F,
  };
}
export function innovation(prediction: Estimate, measurement: Position, sigma: number) {
  const { H, R } = measurementModel(prediction.x.length, sigma);
  const nu = vectorSubtract(measurement, vectorProduct(H, prediction.x));
  const S = add(product(product(H, prediction.P), transpose(H)), R);
  const Si = inverse(S);
  return { nu, S, Si, H, R, d2: quadratic2(nu, Si) };
}
export function update(prediction: Estimate, residual: ReturnType<typeof innovation>) {
  const { H, R, Si, nu, S, d2 } = residual;
  const K = product(product(prediction.P, transpose(H)), Si);
  const J = subtract(identity(prediction.x.length), product(K, H));
  const x = vectorAdd(prediction.x, vectorProduct(K, nu));
  const P = add(
    product(product(J, prediction.P), transpose(J)),
    product(product(K, R), transpose(K)),
  );
  const logLikelihood = -Math.log(2 * Math.PI) - Math.log(determinant2(S)) / 2 - d2 / 2;
  return { x, P, logLikelihood };
}
export function smooth(history: HistoryEntry[]): number[][] {
  const states: number[][] = [];
  states[history.length - 1] = history[history.length - 1].estimate.x.slice();
  for (let i = history.length - 2; i >= 0; i--) {
    const current = history[i].estimate;
    const next = history[i + 1].prediction!;
    const gain = product(product(current.P, transpose(next.F)), inverse(next.P));
    states[i] = vectorAdd(current.x, vectorProduct(gain, vectorSubtract(states[i + 1], next.x)));
  }
  return states;
}
