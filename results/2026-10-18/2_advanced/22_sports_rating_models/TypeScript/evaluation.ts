import { fraction, type Fraction } from './report.ts';
export interface Link { alpha: number; beta: number }
export type Comparison = number | Fraction;
export function sigma(v: number): number { return 1 / (1 + Math.exp(-v)); }
export function fitLink(features: number[], results: number[], iterations: number): Link {
  let alpha = 0, beta = 0;
  for (let iteration = 0; iteration < iterations; iteration++) {
    let g0 = 0, g1 = 0, h00 = 0, h01 = 0, h11 = 0;
    for (let k = 0; k < features.length; k++) {
      const z = features[k], p = sigma(alpha + beta * z), w = p * (1 - p);
      g0 += results[k] - p; g1 += (results[k] - p) * z; h00 += w; h01 += w * z; h11 += w * z * z;
    }
    const det = h00 * h11 - h01 * h01;
    alpha += (h11 * g0 - h01 * g1) / det; beta += (h00 * g1 - h01 * g0) / det;
  }
  return { alpha, beta };
}
export function logLoss(p: number, y: number): number {
  return y === 1 ? -Math.log(p) : y === 0 ? -Math.log(1 - p) : -(Math.log(p) / 2 + Math.log(1 - p) / 2);
}
export function brier(p: number, y: number): number { return (p - y) * (p - y); }
export function correctness(p: number, y: number): number {
  return y === 0.5 ? 0.5 : (p > 0.5 && y === 1) || (p < 0.5 && y === 0) ? 1 : 0;
}
export function compareValues(a: Comparison, b: Comparison): number {
  if (typeof a === 'number' && typeof b === 'number') return Math.sign(a - b);
  const x = typeof a === 'number' ? [a, 1] : a, y = typeof b === 'number' ? [b, 1] : b;
  return Math.sign(x[0] * y[1] - y[0] * x[1]);
}
export function averageRanks(values: Comparison[]): number[] {
  return values.map(v => {
    let greater = 0, equal = 0;
    for (const other of values) { const c = compareValues(other, v); if (c > 0) greater++; if (c === 0) equal++; }
    return greater + (equal + 1) / 2;
  });
}
export function kendall(a: Comparison[], b: Comparison[]): Fraction {
  let difference = 0;
  for (let i = 0; i < a.length; i++) for (let j = i + 1; j < a.length; j++) difference += compareValues(a[i], a[j]) * compareValues(b[i], b[j]);
  return fraction(difference, a.length * (a.length - 1) / 2);
}
export function spearman(first: Comparison[], second: Comparison[]): Fraction {
  const a = averageRanks(first), b = averageRanks(second);
  let squared = 0;
  for (let i = 0; i < a.length; i++) { const d = 2 * (a[i] - b[i]); squared += d * d; }
  const denominator = 4 * a.length * (a.length * a.length - 1);
  return fraction(denominator - 6 * squared, denominator);
}
