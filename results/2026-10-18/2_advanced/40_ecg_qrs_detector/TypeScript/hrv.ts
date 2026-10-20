import { div, rdiv } from './report.ts';

export const sum = (values: readonly number[]): number => values.reduce((a, b) => a + b, 0);
export function isqrt(value: number): number {
  let low = 0, high = 1;
  while (high * high <= value) high *= 2;
  while (low + 1 < high) {
    const middle = div(low + high, 2);
    if (middle * middle <= value) low = middle; else high = middle;
  }
  return low;
}
export const root = (p: number, q: number): number => div(isqrt(div(40000 * p, q)) + 1, 2);
export function statistics(rr: number[], nn: number[], pairs: [number, number][]) {
  const e = nn.length, k = pairs.length, differences = pairs.map(([a, b]) => b - a), additions = pairs.map(([a, b]) => a + b);
  const squared = (values: number[]) => sum(values.map(v => v * v));
  const variance = (values: number[]) => values.length * squared(values) - sum(values) ** 2;
  const nn50 = differences.filter(d => Math.abs(d) > 50).length;
  return { meanRR: rr.length ? rdiv(100 * sum(rr), rr.length) : null,
    meanHR: rr.length ? rdiv(6000000 * rr.length, sum(rr)) : null,
    meanNN: e ? rdiv(100 * sum(nn), e) : null, sdnn: e >= 2 ? root(variance(nn), e * (e - 1)) : null,
    rmssd: k ? root(squared(differences), k) : null, sdsd: k >= 2 ? root(variance(differences), k * (k - 1)) : null,
    nn50, pnn50: k ? rdiv(10000 * nn50, k) : null,
    sd1: k >= 2 ? root(variance(differences), 2 * k * (k - 1)) : null,
    sd2: k >= 2 ? root(variance(additions), 2 * k * (k - 1)) : null };
}
export function histogram(values: number[]): [number, number][] {
  const bins = new Map<number, number>();
  for (const value of values) { const bin = div(16 * value, 125); bins.set(bin, (bins.get(bin) ?? 0) + 1); }
  return [...bins].sort((a, b) => a[0] - b[0]);
}
export function ranges<T>(values: readonly T[], accepts: (value: T, index: number) => boolean): { start: number; end: number }[] {
  const result: { start: number; end: number }[] = [];
  for (let i = 0; i < values.length;) {
    if (!accepts(values[i], i)) { i++; continue; }
    const start = i++;
    while (i < values.length && accepts(values[i], i)) i++;
    result.push({ start, end: i - 1 });
  }
  return result;
}
