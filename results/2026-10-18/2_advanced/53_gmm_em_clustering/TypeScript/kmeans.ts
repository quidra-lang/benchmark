import type { Position, Component } from './dataset.ts';
export function squaredDistance(a: Position, b: Position): number { const dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy; }
export function distance(a: Position, b: Position): number { return Math.sqrt(squaredDistance(a, b)); }
export function assign(points: Position[], centers: Position[]): number[] {
  return points.map(p => { let cluster = 0, best = squaredDistance(p, centers[0]); for (let k = 1; k < centers.length; k++) { const d = squaredDistance(p, centers[k]); if (d < best) { best = d; cluster = k; } } return cluster; });
}
export function update(points: Position[], assignment: number[], centers: Position[]): Position[] {
  const sums = centers.map(() => ({ x: 0, y: 0, count: 0 }));
  points.forEach((p, i) => { const s = sums[assignment[i]]; s.x += p.x; s.y += p.y; s.count++; });
  return sums.map((s, k) => s.count ? { x: s.x / s.count, y: s.y / s.count } : centers[k]);
}
export function fit(points: Position[], initial: Component[], maximum: number) {
  let centers = initial.map(c => ({ x: c.mx, y: c.my })), assignment = assign(points, centers), iterations = 0;
  for (let t = 1; t <= maximum; t++) { centers = update(points, assignment, centers); const next = assign(points, centers), stable = next.every((k, i) => k === assignment[i]); assignment = next; iterations = t; if (stable) break; }
  let inertia = 0; const sizes = centers.map(() => 0);
  points.forEach((p, i) => { sizes[assignment[i]]++; inertia += squaredDistance(p, centers[assignment[i]]); });
  return { centers, assignment, iterations, inertia, sizes };
}
