import type { Point } from './dataset.ts';

export const distance = (a: Point, b: Point) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2;
export interface GridResult {
  neighborhoods: number[][];
  cells: number;
  busiest: { x: number; y: number; count: number };
  candidates: number;
  pairs: number;
  brutePairs: number;
  ok: boolean;
  occupancy: Map<number, number>;
}
export function gridIndex(points: Point[], eps: number): GridResult {
  const cells = new Map<string, { x: number; y: number; points: number[] }>();
  const key = (x: number, y: number) => `${x},${y}`;
  points.forEach((p, i) => {
    const x = Math.floor(p.x / eps);
    const y = Math.floor(p.y / eps);
    const id = key(x, y);
    let cell = cells.get(id);
    if (!cell) {
      cell = { x, y, points: [] };
      cells.set(id, cell);
    }
    cell.points.push(i);
  });
  const occupancy = new Map<number, number>();
  let busiest = { x: 0, y: 0, count: 0 };
  for (const cell of cells.values()) {
    const count = cell.points.length;
    occupancy.set(count, (occupancy.get(count) ?? 0) + 1);
    if (
      count > busiest.count ||
      (count === busiest.count &&
        (cell.y < busiest.y || (cell.y === busiest.y && cell.x < busiest.x)))
    ) {
      busiest = { x: cell.x, y: cell.y, count };
    }
  }
  let candidates = 0;
  let total = 0;
  let bruteTotal = 0;
  let ok = true;
  const neighborhoods = points.map((p) => {
    const neighborhood: number[] = [];
    const gx = Math.floor(p.x / eps);
    const gy = Math.floor(p.y / eps);
    for (let y = gy - 1; y <= gy + 1; y++) {
      for (let x = gx - 1; x <= gx + 1; x++) {
        for (const q of cells.get(key(x, y))?.points ?? []) {
          candidates++;
          if (distance(p, points[q]) <= eps * eps) neighborhood.push(q);
        }
      }
    }
    const brute = points.filter((q) => distance(p, q) <= eps * eps).length;
    if (brute !== neighborhood.length) ok = false;
    total += neighborhood.length;
    bruteTotal += brute;
    return neighborhood;
  });
  return {
    neighborhoods,
    cells: cells.size,
    busiest,
    candidates,
    pairs: (total - points.length) / 2,
    brutePairs: (bruteTotal - points.length) / 2,
    ok,
    occupancy,
  };
}
