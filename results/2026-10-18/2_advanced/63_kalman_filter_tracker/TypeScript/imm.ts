import * as kalman from './kalman.ts';
import type { Position, Estimate, Initialization } from './kalman.ts';
import { determinant2 } from './matrix.ts';
export interface ImmParameters extends Initialization {
  immQ: number[];
  immTransition: number[][];
  immInitial: number[];
}
export interface ImmState {
  models: Estimate[];
  probabilities: number[];
}
export function initialize(measurement: Position, params: ImmParameters): ImmState {
  return {
    models: [
      kalman.initialize('CV', measurement, params),
      kalman.initialize('CV', measurement, params),
    ],
    probabilities: params.immInitial.slice(),
  };
}
export function advance(
  previous: ImmState,
  T: number,
  measurement: Position | null,
  p: ImmParameters,
): ImmState {
  const [first, second] = previous.models;
  const [mu1, mu2] = previous.probabilities;
  const transition = p.immTransition;
  const predicted: number[] = [];
  const models: Estimate[] = [];
  const likelihoods: number[] = [];
  for (let j = 0; j < 2; j++) {
    const c = transition[0][j] * mu1 + transition[1][j] * mu2;
    predicted.push(c);
    const w1 = (transition[0][j] * mu1) / c;
    const w2 = (transition[1][j] * mu2) / c;
    const x = first.x.map((v, r) => w1 * v + w2 * second.x[r]);
    const P = first.P.map((row, r) =>
      row.map(
        (v, s) =>
          w1 * (v + (first.x[r] - x[r]) * (first.x[s] - x[s])) +
          w2 * (second.P[r][s] + (second.x[r] - x[r]) * (second.x[s] - x[s])),
      ),
    );
    const prediction = kalman.predict({ x, P }, 'CV', T, p.immQ[j]);
    if (measurement === null) {
      models.push(prediction);
      likelihoods.push(1);
    } else {
      const residual = kalman.innovation(prediction, measurement, p.sigma);
      models.push(kalman.update(prediction, residual));
      likelihoods.push(
        Math.exp(-residual.d2 / 2) / (2 * Math.PI * Math.sqrt(determinant2(residual.S))),
      );
    }
  }
  const denominator = likelihoods[0] * predicted[0] + likelihoods[1] * predicted[1];
  return { models, probabilities: likelihoods.map((L, j) => (L * predicted[j]) / denominator) };
}
export function estimate(state: ImmState): number[] {
  return state.models[0].x.map(
    (v, r) => state.probabilities[0] * v + state.probabilities[1] * state.models[1].x[r],
  );
}
