import { sum, mean } from './resampling.ts';

export function* choices(size: number, count: number): Generator<number[]> {
  const positions = Array.from({ length: count }, (_, i) => i);
  for (;;) {
    yield positions.slice();
    let i = count - 1;
    while (i >= 0 && positions[i] === size - count + i) i--;
    if (i < 0) return;
    positions[i]++;
    for (let j = i + 1; j < count; j++) positions[j] = positions[j - 1] + 1;
  }
}
export function reduced(numerator: number, denominator: number): [number, number] {
  let a = numerator;
  let b = denominator;
  while (b !== 0) [a, b] = [b, a % b];
  return [numerator / a, denominator / a];
}
export function contrast(x: number[], y: number[]): number {
  return y.length * sum(x) - x.length * sum(y);
}
export function doubledRanks(values: number[]): number[] {
  const order = values.map((value, i) => ({ value, i })).sort((a, b) => a.value - b.value);
  const ranks: number[] = Array(values.length);
  let start = 0;
  while (start < order.length) {
    let end = start + 1;
    while (end < order.length && order[end].value === order[start].value) end++;
    const rank = 2 * start + (end - start) + 1;
    for (let j = start; j < end; j++) ranks[order[j].i] = rank;
    start = end;
  }
  return ranks;
}
export function tieCounts(values: number[]) {
  const counts = new Map<number, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  let groups = 0;
  let correction = 0;
  for (const count of counts.values()) {
    if (count >= 2) {
      groups++;
      correction += count * count * count - count;
    }
  }
  return { groups, correction };
}
export function divide<T>(values: T[], sizes: number[]): T[][] {
  let start = 0;
  return sizes.map((size) => {
    const part = values.slice(start, start + size);
    start += size;
    return part;
  });
}
export function anova(samples: number[][]) {
  const sizes = samples.map((sample) => sample.length);
  const count = sum(sizes);
  const grand = sum(samples.map(sum)) / (100 * count);
  const means = samples.map(mean);
  let ssb = 0;
  let ssw = 0;
  for (let g = 0; g < samples.length; g++) {
    const difference = means[g] - grand;
    ssb += sizes[g] * (difference * difference);
    let within = 0;
    for (const value of samples[g]) {
      const e = value / 100 - means[g];
      within += e * e;
    }
    ssw += within;
  }
  return {
    count,
    means,
    ssb,
    ssw,
    f: ssb / (samples.length - 1) / (ssw / (count - samples.length)),
  };
}
export function kruskal(rankGroups: number[][], correction: number): number {
  let total = 0;
  let count = 0;
  for (const ranks of rankGroups) {
    const rankSum = sum(ranks);
    total += (rankSum * rankSum) / (4 * ranks.length);
    count += ranks.length;
  }
  return ((12 * total) / (count * (count + 1)) - 3 * (count + 1)) / correction;
}
