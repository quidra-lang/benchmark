import * as matrix from './matrix.ts';
export interface Eigensystem {
  values: number[];
  vectors: number[][];
  sweeps: number;
}
export function offDiagonal(m: number[][]): number {
  let total = 0;
  for (let p = 0; p < m.length - 1; p++) {
    for (let q = p + 1; q < m.length; q++) total += m[p][q] * m[p][q];
  }
  return total;
}
export function rotate(a: number[][], v: number[][], p: number, q: number): void {
  if (a[p][q] === 0) return;
  const theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
  let t = 1 / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
  if (theta < 0) t = -t;
  const c = 1 / Math.sqrt(t * t + 1);
  const s = t * c;
  for (let r = 0; r < a.length; r++) {
    if (r !== p && r !== q) {
      const x = a[r][p];
      const y = a[r][q];
      a[r][p] = a[p][r] = c * x - s * y;
      a[r][q] = a[q][r] = s * x + c * y;
    }
  }
  const cross = a[p][q];
  a[p][p] -= t * cross;
  a[q][q] += t * cross;
  a[p][q] = a[q][p] = 0;
  for (const row of v) {
    const x = row[p];
    const y = row[q];
    row[p] = c * x - s * y;
    row[q] = s * x + c * y;
  }
}
export function jacobi(input: number[][]): Eigensystem {
  const a = matrix.copy(input);
  const v = matrix.identity(input.length);
  const initial = offDiagonal(a);
  let sweeps = 0;
  if (initial !== 0) {
    for (let sweep = 1; sweep <= 100; sweep++) {
      for (let p = 0; p < a.length - 1; p++) {
        for (let q = p + 1; q < a.length; q++) rotate(a, v, p, q);
      }
      const off = offDiagonal(a);
      if (!sweeps && off < 1e-16 * initial) sweeps = sweep;
      if (off < 1e-22 * initial) break;
    }
  }
  const order = input.map((_, i) => i).sort((a1, b) => a[b][b] - a[a1][a1] || a1 - b);
  return {
    values: order.map((k) => a[k][k]),
    vectors: order.map((k) => matrix.orient(matrix.normalize(matrix.column(v, k)))),
    sweeps,
  };
}
export function power(input: number[][], reference: Eigensystem) {
  const remaining = matrix.copy(input);
  return reference.values.map((lambda, k) => {
    let vector: number[] = Array(input.length).fill(1);
    let agreement: number | null = null;
    const target = reference.vectors[k];
    const negative = target.map((x) => -x);
    for (let t = 1; t <= 1000; t++) {
      vector = matrix.normalize(matrix.multiply(remaining, vector));
      if (
        agreement === null &&
        Math.min(matrix.difference(vector, target), matrix.difference(vector, negative)) < 0.000001
      ) {
        agreement = t;
      }
    }
    const value = matrix.dot(vector, matrix.multiply(remaining, vector));
    const oriented = matrix.orient(matrix.normalize(vector));
    const match =
      Math.abs(value - lambda) <= 1e-8 * reference.values[0] &&
      matrix.difference(oriented, target) <= 0.000001;
    matrix.deflate(remaining, value, oriented);
    return { value, vector: oriented, agreement, match };
  });
}
