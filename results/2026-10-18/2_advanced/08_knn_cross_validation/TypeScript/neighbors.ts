import type { Metric, TrainingRow, Weighting } from './dataset.ts';
export interface Reference { row: TrainingRow; vector: number[] }
export interface Neighbor { row: TrainingRow; distance: number }
export interface Prediction { label: string; share: number; runnerUp: string | null; runnerShare: number; estimate: number; neighbors: Neighbor[] }
interface VoteGroup { label: string; count: number; distance: number; weight: number }
export const compareText = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
export function distance(a: number[], b: number[], metric: Metric): number {
  let total = 0, dot = 0, aa = 0, bb = 0;
  for (let j = 0; j < a.length; j++) {
    const delta = a[j] - b[j];
    if (metric === 'squared_euclidean') total += delta * delta;
    else if (metric === 'manhattan') total += Math.abs(delta);
    else if (metric === 'chebyshev') total = Math.max(total, Math.abs(delta));
    else { dot += a[j] * b[j]; aa += a[j] * a[j]; bb += b[j] * b[j]; }
  }
  if (metric !== 'cosine') return total;
  const na = Math.sqrt(aa), nb = Math.sqrt(bb);
  return na === 0 || nb === 0 ? 1 : 1 - dot / (na * nb);
}
export function neighborOrder(reference: Reference[], query: number[], metric: Metric): Neighbor[] {
  return reference.map(({ row, vector }) => ({ row, distance: distance(query, vector, metric) }))
    .sort((a, b) => a.distance - b.distance || compareText(a.row.id, b.row.id));
}
export function vote(order: Neighbor[], k: number, weighting: Weighting): Prediction {
  const neighbors = order.slice(0, k), groups = new Map<string, VoteGroup>();
  let weightTotal = 0, targetTotal = 0, weightedTarget = 0;
  for (const { row, distance } of neighbors) {
    const weight = 1 / (distance + 0.000000001);
    let group = groups.get(row.label);
    if (!group) { group = { label: row.label, count: 0, distance: 0, weight: 0 }; groups.set(row.label, group); }
    group.count++; group.distance += distance; group.weight += weight;
    weightTotal += weight; targetTotal += row.target; weightedTarget += weight * row.target;
  }
  const ranked = [...groups.values()].sort((a, b) => (weighting === 'uniform' ? b.count - a.count : b.weight - a.weight)
    || a.distance - b.distance || compareText(a.label, b.label));
  const share = (group: VoteGroup) => weighting === 'uniform' ? group.count / neighbors.length : group.weight / weightTotal;
  return { label: ranked[0].label, share: share(ranked[0]), runnerUp: ranked[1]?.label ?? null,
    runnerShare: ranked[1] ? share(ranked[1]) : 0,
    estimate: weighting === 'uniform' ? targetTotal / neighbors.length : weightedTarget / weightTotal, neighbors };
}
