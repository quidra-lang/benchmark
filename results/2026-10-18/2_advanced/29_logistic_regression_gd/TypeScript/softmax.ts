import { score } from './logistic.ts';

export function rowValues(weights: number[][], vector: number[], label = 0) {
  const scores = weights.map((row) => score(row, vector));
  const maximum = Math.max(...scores);
  const shifted = scores.map((value) => value - maximum);
  const exponentials = shifted.map((value) => Math.exp(value));
  let total = 0;
  for (const value of exponentials) total += value;
  const probabilities = exponentials.map((value) => value / total);
  let predicted = 0;
  for (let k = 1; k < probabilities.length; k++) {
    if (probabilities[k] > probabilities[predicted]) predicted = k;
  }
  return { probabilities, predicted, loss: Math.log(total) - shifted[label] };
}
export function evaluate(weights: number[][], vectors: number[][], labels: number[], lambda = 0) {
  const rows = vectors.map((vector, i) => rowValues(weights, vector, labels[i]));
  let total = 0;
  let squared = 0;
  for (const row of rows) total += row.loss;
  for (const row of weights) for (let j = 1; j < row.length; j++) squared += row[j] * row[j];
  const average = total / vectors.length;
  return { rows, loss: average, objective: average + (lambda * squared) / 2 };
}
export function gradient(
  weights: number[][],
  vectors: number[][],
  labels: number[],
  lambda: number,
): number[][] {
  const probabilities = vectors.map((vector) => rowValues(weights, vector).probabilities);
  return weights.map((row, k) =>
    row.map((weight, j) => {
      let total = 0;
      for (let i = 0; i < vectors.length; i++) {
        total += (probabilities[i][k] - Number(labels[i] === k)) * vectors[i][j];
      }
      const value = total / vectors.length;
      return j === 0 ? value : value + lambda * weight;
    }),
  );
}
export function train(
  vectors: number[][],
  labels: number[],
  classes: number,
  lambda: number,
  rate: number,
  iterations: number,
) {
  let weights: number[][] = Array.from({ length: classes }, () => Array(vectors[0].length).fill(0));
  const checkpoints = [{ iteration: 0, weights: weights.map((row) => row.slice()) }];
  for (let t = 1; t <= iterations; t++) {
    const g = gradient(weights, vectors, labels, lambda);
    weights = weights.map((row, k) => row.map((w, j) => w - rate * g[k][j]));
    if (t % 100 === 0) {
      checkpoints.push({ iteration: t, weights: weights.map((row) => row.slice()) });
    }
  }
  return { weights, checkpoints };
}
