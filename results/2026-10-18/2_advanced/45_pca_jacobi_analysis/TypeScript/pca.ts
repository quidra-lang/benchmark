import * as matrix from './matrix.ts';
import type { Scaling } from './dataset.ts';
export function standardize(
  values: (number | null)[],
  means: number[],
  scales: number[],
): number[] {
  return values.map((v, j) => (v === null ? 0 : (v - means[j]) / scales[j]));
}
export function prepare(rows: number[][], scaling: Scaling) {
  const p = rows[0].length;
  const n = rows.length;
  const means: number[] = [];
  for (let j = 0; j < p; j++) {
    let total = 0;
    for (const row of rows) total += row[j];
    means.push(total / n);
  }
  const covariance = matrix.zeros(p);
  for (let j = 0; j < p; j++) {
    for (let k = j; k < p; k++) {
      let total = 0;
      for (const row of rows) total += (row[j] - means[j]) * (row[k] - means[k]);
      covariance[j][k] = covariance[k][j] = total / (n - 1);
    }
  }
  const deviations = covariance.map((row, j) => Math.sqrt(row[j]));
  const correlation = covariance.map((row, j) =>
    row.map((v, k) => (j === k ? 1 : v / (deviations[j] * deviations[k]))),
  );
  const scales: number[] = scaling === 'covariance' ? Array(p).fill(1) : [...deviations];
  return {
    means,
    covariance,
    deviations,
    correlation,
    scales,
    matrix: scaling === 'covariance' ? covariance : correlation,
    standardized: rows.map((row) => standardize(row, means, scales)),
  };
}
export function scores(z: number[], vectors: number[][]): number[] {
  return vectors.map((v) => matrix.dot(z, v));
}
export function residuals(
  z: number[],
  scores: number[],
  vectors: number[][],
  retained: number,
): number[] {
  return z.map((v, j) => {
    let fitted = 0;
    for (let k = 0; k < retained; k++) fitted += scores[k] * vectors[k][j];
    return v - fitted;
  });
}
export function tSquared(scores: number[], values: number[], retained: number): number {
  let total = 0;
  for (let k = 0; k < retained; k++) total += (scores[k] * scores[k]) / values[k];
  return total;
}
