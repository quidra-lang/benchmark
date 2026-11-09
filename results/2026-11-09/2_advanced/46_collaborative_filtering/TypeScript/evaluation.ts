import type { Rating } from './ratings.ts';
export function clip(v: number): number {
  return v < 1 ? 1 : v > 5 ? 5 : v;
}
export function errorMetrics(errors: number[]) {
  if (!errors.length) return { rmse: null, mae: null };
  let squared = 0;
  let absolute = 0;
  for (const e of errors) {
    squared += e * e;
    absolute += Math.abs(e);
  }
  return { rmse: Math.sqrt(squared / errors.length), mae: absolute / errors.length };
}
export function trainingRmse(ratings: Rating[], predict: (u: number, i: number) => number): number {
  let total = 0;
  for (const r of ratings) {
    const e = r.rating - predict(r.u, r.i);
    total += e * e;
  }
  return Math.sqrt(total / ratings.length);
}
export function rankWeight(rank: number): number {
  return 1 / Math.log2(rank + 1);
}
export function rankingMetrics(items: number[], relevant: Set<number>, cutoff: number) {
  let hits = 0;
  let dcg = 0;
  let ap = 0;
  let rr = 0;
  for (let i = 0; i < cutoff; i++) {
    if (relevant.has(items[i])) {
      hits++;
      dcg += rankWeight(i + 1);
      ap += hits / (i + 1);
      if (!rr) rr = 1 / (i + 1);
    }
  }
  const idealCount = Math.min(cutoff, relevant.size);
  let ideal = 0;
  for (let rank = 1; rank <= idealCount; rank++) ideal += rankWeight(rank);
  return { hits, recall: hits / relevant.size, ndcg: dcg / ideal, ap: ap / idealCount, rr };
}
