import { count, type Counts } from './dfg.ts';
import type { Fraction } from './report.ts';

export function dependency(counts: Counts, first: string, second: string): Fraction {
  const a = count(counts, first, second);
  const b = count(counts, second, first);
  return [BigInt(a - b), BigInt(a + b + 1)];
}
export const loopMeasure = (observations: number): Fraction => [
  BigInt(observations),
  BigInt(observations + 1),
];
export function routingMeasure(
  counts: Counts,
  activity: string,
  a: string,
  b: string,
  split: boolean,
): Fraction {
  return [
    BigInt(count(counts, a, b) + count(counts, b, a)),
    BigInt(
      split
        ? count(counts, activity, a) + count(counts, activity, b) + 1
        : count(counts, a, activity) + count(counts, b, activity) + 1,
    ),
  ];
}
export function compareFractions(a: Fraction, b: Fraction): number {
  const d = a[0] * b[1] - b[0] * a[1];
  return d < 0n ? -1 : d > 0n ? 1 : 0;
}
export const subtractFractions = (a: Fraction, b: Fraction): Fraction => [
  a[0] * b[1] - b[0] * a[1],
  a[1] * b[1],
];
