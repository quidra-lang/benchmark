import { gradient, hessian } from './logistic.ts';

export interface Checkpoint {
  iteration: number;
  weights: number[];
}
export interface Fit {
  weights: number[];
  checkpoints: Checkpoint[];
}
export interface NewtonFit extends Fit {
  steps: { gradient: number[]; delta: number[] }[];
}
export class Minstd {
  constructor(private state: number) {}
  draw(): number {
    this.state = (48271 * this.state) % 2147483647;
    return this.state;
  }
}
export function shuffle<T>(values: T[], generator: Minstd): void {
  for (let i = values.length - 1; i >= 1; i--) {
    const other = generator.draw() % (i + 1);
    [values[i], values[other]] = [values[other], values[i]];
  }
}
export function cholesky(matrix: number[][]): number[][] {
  const factor: number[][] = matrix.map(() => Array(matrix.length).fill(0));
  for (let j = 0; j < matrix.length; j++) {
    for (let i = j; i < matrix.length; i++) {
      let total = 0;
      for (let k = 0; k < j; k++) total += factor[i][k] * factor[j][k];
      const remainder = matrix[i][j] - total;
      factor[i][j] = i === j ? Math.sqrt(remainder) : remainder / factor[j][j];
    }
  }
  return factor;
}
export function solveFactor(factor: number[][], right: number[]): number[] {
  const forward: number[] = [];
  const solution: number[] = [];
  for (let i = 0; i < right.length; i++) {
    let total = 0;
    for (let k = 0; k < i; k++) total += factor[i][k] * forward[k];
    forward[i] = (right[i] - total) / factor[i][i];
  }
  for (let i = right.length - 1; i >= 0; i--) {
    let total = 0;
    for (let k = i + 1; k < right.length; k++) total += factor[k][i] * solution[k];
    solution[i] = (forward[i] - total) / factor[i][i];
  }
  return solution;
}
export function gradientDescent(
  vectors: number[][],
  targets: number[],
  lambda: number,
  rate: number,
  iterations: number,
): Fit {
  let weights: number[] = Array(vectors[0].length).fill(0);
  const checkpoints = [{ iteration: 0, weights: weights.slice() }];
  for (let t = 1; t <= iterations; t++) {
    const g = gradient(weights, vectors, targets, lambda);
    weights = weights.map((w, j) => w - rate * g[j]);
    if (t % 100 === 0) checkpoints.push({ iteration: t, weights: weights.slice() });
  }
  return { weights, checkpoints };
}
export function stochasticDescent(
  vectors: number[][],
  targets: number[],
  lambda: number,
  rate: number,
  batchSize: number,
  epochs: number,
  seed: number,
): Fit {
  let weights: number[] = Array(vectors[0].length).fill(0);
  const checkpoints = [{ iteration: 0, weights: weights.slice() }];
  const generator = new Minstd(seed);
  const order = vectors.map((_, i) => i);
  for (let epoch = 1; epoch <= epochs; epoch++) {
    shuffle(order, generator);
    for (let start = 0; start < order.length; start += batchSize) {
      const batch = order.slice(start, start + batchSize);
      const g = gradient(
        weights,
        batch.map((i) => vectors[i]),
        batch.map((i) => targets[i]),
        lambda,
      );
      weights = weights.map((w, j) => w - rate * g[j]);
    }
    checkpoints.push({ iteration: epoch, weights: weights.slice() });
  }
  return { weights, checkpoints };
}
export function newton(vectors: number[][], targets: number[], lambda: number): NewtonFit {
  let weights: number[] = Array(vectors[0].length).fill(0);
  const checkpoints = [{ iteration: 0, weights: weights.slice() }];
  const steps: NewtonFit['steps'] = [];
  for (let t = 1; t <= 10; t++) {
    const g = gradient(weights, vectors, targets, lambda);
    const delta = solveFactor(cholesky(hessian(weights, vectors, lambda)), g);
    steps.push({ gradient: g, delta });
    weights = weights.map((w, j) => w - delta[j]);
    checkpoints.push({ iteration: t, weights: weights.slice() });
  }
  return { weights, checkpoints, steps };
}
