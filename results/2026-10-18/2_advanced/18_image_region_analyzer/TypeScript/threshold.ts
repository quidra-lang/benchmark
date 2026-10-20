import type { Image } from './pgm_reader.ts';
import { floorRatio } from './report.ts';

export interface Histogram {
  counts: number[];
  cumulativeCounts: number[];
  cumulativeSums: number[];
  count: number;
  sum: number;
  minimum: number;
  maximum: number;
  median: number;
  mode: number;
  levels: number;
  binWidth: number;
  bins: number[];
}
export interface Candidate {
  threshold: number;
  below: number;
  above: number;
  sumBelow: number;
  sumAbove: number;
  denominator: number;
  quotient: number;
  remainder: number;
}
export function histogram(image: Image): Histogram {
  const counts: number[] = Array(image.maxval + 1).fill(0);
  for (const value of image.pixels) counts[value]++;
  const cumulativeCounts: number[] = [];
  const cumulativeSums: number[] = [];
  let count = 0;
  let sum = 0;
  let minimum = -1;
  let maximum = 0;
  let median = -1;
  let mode = 0;
  let levels = 0;
  for (let value = 0; value <= image.maxval; value++) {
    count += counts[value];
    sum += value * counts[value];
    cumulativeCounts.push(count);
    cumulativeSums.push(sum);
    if (counts[value]) {
      if (minimum < 0) minimum = value;
      maximum = value;
      levels++;
    }
    if (median < 0 && 2 * count >= image.pixels.length) median = value;
    if (counts[value] > counts[mode]) mode = value;
  }
  const binWidth = floorRatio(image.maxval + 8, 8);
  const bins: number[] = [];
  for (let first = 0; first <= image.maxval; first += binWidth) {
    bins.push(counts.slice(first, first + binWidth).reduce((a, b) => a + b, 0));
  }
  return {
    counts,
    cumulativeCounts,
    cumulativeSums,
    count,
    sum,
    minimum,
    maximum,
    median,
    mode,
    levels,
    binWidth,
    bins,
  };
}
export function compareScores(a: Candidate, b: Candidate): number {
  if (a.quotient !== b.quotient) return a.quotient < b.quotient ? -1 : 1;
  const left = a.remainder * b.denominator;
  const right = b.remainder * a.denominator;
  return left < right ? -1 : left > right ? 1 : 0;
}
export function otsu(stats: Histogram): {
  threshold: number;
  upper: number;
  candidates: Candidate[];
} {
  const candidates: Candidate[] = [];
  for (let threshold = 0; threshold + 1 < stats.counts.length; threshold++) {
    const below = stats.cumulativeCounts[threshold];
    const above = stats.count - below;
    if (!stats.counts[threshold] || !above) continue;
    const sumBelow = stats.cumulativeSums[threshold];
    const sumAbove = stats.sum - sumBelow;
    const numerator = sumBelow * sumBelow * above + sumAbove * sumAbove * below;
    const denominator = below * above;
    const quotient = floorRatio(numerator, denominator);
    const remainder = numerator - quotient * denominator;
    candidates.push({
      threshold,
      below,
      above,
      sumBelow,
      sumAbove,
      denominator,
      quotient,
      remainder,
    });
  }
  candidates.sort((a, b) => -compareScores(a, b) || a.threshold - b.threshold);
  if (!candidates.length) return { threshold: stats.minimum, upper: stats.minimum, candidates };
  const threshold = candidates[0].threshold;
  let next = threshold + 1;
  while (!stats.counts[next]) next++;
  return { threshold, upper: next - 1, candidates };
}
export function isodata(stats: Histogram): { threshold: number; iterations: number } {
  let threshold = floorRatio(stats.sum, stats.count);
  let iterations = 0;
  while (true) {
    const below = stats.cumulativeCounts[threshold];
    const above = stats.count - below;
    if (!below || !above) break;
    const s0 = stats.cumulativeSums[threshold];
    const s1 = stats.sum - s0;
    const next = floorRatio(s0 * above + s1 * below, 2 * below * above);
    iterations++;
    if (next === threshold) break;
    threshold = next;
    if (iterations === 100) break;
  }
  return { threshold, iterations };
}
