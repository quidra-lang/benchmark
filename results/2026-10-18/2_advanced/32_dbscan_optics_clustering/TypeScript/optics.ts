import type { Point } from './dataset.ts';
import { distance } from './grid_index.ts';

export interface Ordering { order: number[]; core: number[]; reach: number[]; predecessor: (number | undefined)[] }
export function optics(points: Point[], neighborhoods: number[][], minPts: number): Ordering {
  const core = neighborhoods.map((neighbors, p) => neighbors.length < minPts ? Infinity :
    neighbors.map(q => distance(points[p], points[q])).sort((a, b) => a - b)[minPts - 1]);
  const reach = Array<number>(points.length).fill(Infinity), processed = Array<boolean>(points.length).fill(false);
  const predecessor: (number | undefined)[] = Array(points.length).fill(undefined), order: number[] = [];
  for (let t = 0; t < points.length; t++) {
    if (processed[t]) continue;
    const seeds = new Set([t]);
    while (seeds.size) {
      let p = -1;
      for (const candidate of seeds) if (p < 0 || reach[candidate] < reach[p] || (reach[candidate] === reach[p] && points[candidate].id < points[p].id)) p = candidate;
      seeds.delete(p); processed[p] = true; order.push(p);
      if (core[p] === Infinity) continue;
      for (const q of neighborhoods[p]) {
        if (processed[q]) continue;
        const r = Math.max(core[p], distance(points[p], points[q]));
        if (r < reach[q]) { reach[q] = r; predecessor[q] = p; seeds.add(q); }
      }
    }
  }
  return { order, core, reach, predecessor };
}
