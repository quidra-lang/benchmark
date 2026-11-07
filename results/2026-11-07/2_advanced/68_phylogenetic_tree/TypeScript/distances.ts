import { bases } from './alignment.ts';
export const models = ['P', 'JC', 'K2P'] as const;
export type DistanceModel = (typeof models)[number];
export interface Pair {
  i: number;
  j: number;
  n: number;
  s: number;
  v: number;
}
export function pair(first: string, second: string, weights: number[]) {
  let n = 0;
  let s = 0;
  let v = 0;
  for (let c = 0; c < first.length; c++) {
    const a = first[c];
    const b = second[c];
    if (!bases.includes(a) || !bases.includes(b)) continue;
    n += weights[c];
    if (a !== b) {
      if (
        (a === 'A' && b === 'G') ||
        (a === 'G' && b === 'A') ||
        (a === 'C' && b === 'T') ||
        (a === 'T' && b === 'C')
      ) {
        s += weights[c];
      } else v += weights[c];
    }
  }
  return { n, s, v };
}
export function distance(
  { n, s, v }: Pick<Pair, 'n' | 's' | 'v'>,
  model: DistanceModel,
  replacement: number,
) {
  const saturated =
    n === 0 ||
    (model === 'JC' && 4 * (s + v) >= 3 * n) ||
    (model === 'K2P' && (2 * s + v >= n || 2 * v >= n));
  const value = saturated
    ? replacement
    : model === 'P'
      ? (s + v) / n
      : model === 'JC'
        ? -(3 / 4) * Math.log(1 - (4 * (s + v)) / (3 * n))
        : -(1 / 2) * Math.log(1 - (2 * s) / n - v / n) - (1 / 4) * Math.log(1 - (2 * v) / n);
  return { saturated, value };
}
export function tally(sequences: string[], weights: number[]): Pair[] {
  const pairs: Pair[] = [];
  for (let i = 0; i < sequences.length; i++) {
    for (let j = i + 1; j < sequences.length; j++) {
      pairs.push({ i, j, ...pair(sequences[i], sequences[j], weights) });
    }
  }
  return pairs;
}
export function matrix(
  count: number,
  pairs: Pair[],
  model: DistanceModel,
  replacement: number,
): number[][] {
  const values = Array.from({ length: count }, () => Array<number>(count).fill(0));
  for (const p of pairs) {
    values[p.i][p.j] = values[p.j][p.i] = distance(p, model, replacement).value;
  }
  return values;
}
