import type { Point, Fit } from './dataset.ts';
export interface RobustRecord {
  iteration: number;
  scale: number;
  zeros: number;
  change: number;
}
export interface LoessFit extends Fit {
  kind: 'loess';
  yhat: number[];
  lev: number[];
  edf: number;
  robustness: number[];
  records: RobustRecord[];
}
export function median(values: number[]): number {
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
export function cholesky(matrix: number[][]): number[][] {
  const lower: number[][] = matrix.map(() => Array(matrix.length).fill(0));
  for (let k = 0; k < matrix.length; k++) {
    for (let l = 0; l <= k; l++) {
      let sigma = matrix[k][l];
      for (let i = 0; i < l; i++) sigma -= lower[k][i] * lower[l][i];
      lower[k][l] = l === k ? Math.sqrt(sigma) : sigma / lower[l][l];
    }
  }
  return lower;
}
export function solve(lower: number[][], right: number[]): number[] {
  const eta: number[] = [];
  const result: number[] = Array(right.length);
  for (let k = 0; k < right.length; k++) {
    let v = right[k];
    for (let j = 0; j < k; j++) v -= lower[k][j] * eta[j];
    eta.push(v / lower[k][k]);
  }
  for (let k = right.length - 1; k >= 0; k--) {
    let v = eta[k];
    for (let j = k + 1; j < right.length; j++) v -= lower[j][k] * result[j];
    result[k] = v / lower[k][k];
  }
  return result;
}
export function localFit(
  points: Point[],
  degree: number,
  span: number,
  robustness: number[],
  position: number,
) {
  const count = Math.floor((span * points.length) / 100);
  const neighbours = points
    .map((_, i) => i)
    .sort((a, b) => Math.abs(points[a].X - position) - Math.abs(points[b].X - position) || a - b)
    .slice(0, count);
  const extent = Math.abs(points[neighbours[neighbours.length - 1]].X - position);
  neighbours.sort((a, b) => a - b);
  const x0 = position / 100;
  const local = neighbours.map((i) => {
    const a = Math.abs(points[i].X - position) / extent;
    const s = 1 - a * a * a;
    const w = s * s * s;
    const d = points[i].x - x0;
    return { i, weight: w * robustness[i], basis: degree === 1 ? [1, d] : [1, d, d * d] };
  });
  const matrix: number[][] = Array.from({ length: degree + 1 }, () => Array(degree + 1).fill(0));
  const right: number[] = Array(degree + 1).fill(0);
  for (const p of local) {
    for (let k = 0; k <= degree; k++) {
      for (let l = 0; l <= degree; l++) matrix[k][l] += p.weight * p.basis[k] * p.basis[l];
      right[k] += p.weight * p.basis[k] * points[p.i].y;
    }
  }
  const lower = cholesky(matrix);
  const beta = solve(lower, right);
  const unit: number[] = Array(degree + 1).fill(0);
  unit[0] = 1;
  const zeta = solve(lower, unit);
  const weights: number[] = Array(points.length).fill(0);
  for (const p of local) {
    let total = 0;
    for (let k = 0; k <= degree; k++) total += zeta[k] * p.basis[k];
    weights[p.i] = p.weight * total;
  }
  return { value: beta[0], weights, zeta0: zeta[0] };
}
export function fit(points: Point[], degree: number, span: number, iterations: number): LoessFit {
  let robustness = points.map(() => 1);
  let estimates = points.map((p) => localFit(points, degree, span, robustness, p.X));
  const records: RobustRecord[] = [];
  for (let iteration = 1; iteration <= iterations; iteration++) {
    const errors = points.map((p, i) => p.y - estimates[i].value);
    const scale = median(errors.map(Math.abs));
    robustness = errors.map((e) => {
      const u = e / (6 * scale);
      if (Math.abs(u) >= 1) return 0;
      const v = 1 - u * u;
      return v * v;
    });
    const next = points.map((p) => localFit(points, degree, span, robustness, p.X));
    let change = 0;
    for (let i = 0; i < points.length; i++) {
      change = Math.max(change, Math.abs(next[i].value - estimates[i].value));
    }
    records.push({ iteration, scale, zeros: robustness.filter((v) => v === 0).length, change });
    estimates = next;
  }
  const lev = estimates.map((e, i) => robustness[i] * e.zeta0);
  let edf = 0;
  for (const v of lev) edf += v;
  return {
    kind: 'loess',
    yhat: estimates.map((e) => e.value),
    lev,
    edf,
    robustness,
    records,
    at: (position: number) => localFit(points, degree, span, robustness, position),
  };
}
