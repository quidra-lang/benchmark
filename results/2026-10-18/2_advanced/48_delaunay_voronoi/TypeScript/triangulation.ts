import { orient, incircle } from './predicates.ts';
import type { Point, Pair, TriangleSites } from './predicates.ts';
export const key = (a: number, b: number): string => `${a},${b}`;
export function canonical(triangle: TriangleSites): TriangleSites {
  const start = triangle.indexOf(Math.min(...triangle));
  return [triangle[start], triangle[(start + 1) % 3], triangle[(start + 2) % 3]];
}
export const directedEdges = ([a, b, c]: TriangleSites): Pair[] => [
  [a, b],
  [b, c],
  [c, a],
];
export interface Insertion {
  site: number;
  kind: 'inside' | 'outside';
  containing: TriangleSites | undefined;
  visible: number;
  flips: number;
  triangles: number;
  hull: number;
}
export class Triangulation {
  readonly directed = new Map<string, number>();
  readonly initial: TriangleSites;
  constructor(readonly points: Point[]) {
    this.initial = orient(points[1], points[2], points[3]) > 0 ? [1, 2, 3] : [1, 3, 2];
    this.add(...this.initial);
  }
  add(a: number, b: number, c: number): void {
    this.directed.set(key(a, b), c);
    this.directed.set(key(b, c), a);
    this.directed.set(key(c, a), b);
  }
  remove(a: number, b: number, c: number): void {
    this.directed.delete(key(a, b));
    this.directed.delete(key(b, c));
    this.directed.delete(key(c, a));
  }
  triangles(): TriangleSites[] {
    const result: TriangleSites[] = [];
    for (const [edge, c] of this.directed) {
      const [a, b] = edge.split(',').map(Number);
      if (a < b && a < c) result.push([a, b, c]);
    }
    return result.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);
  }
  hullEdges(): Pair[] {
    const result: Pair[] = [];
    for (const edge of this.directed.keys()) {
      const [a, b] = edge.split(',').map(Number);
      if (!this.directed.has(key(b, a))) result.push([a, b]);
    }
    return result.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  }
  insert(site: number): Insertion {
    const p = this.points;
    const containing = this.triangles().find(
      ([a, b, c]) =>
        orient(p[a], p[b], p[site]) > 0 &&
        orient(p[b], p[c], p[site]) > 0 &&
        orient(p[c], p[a], p[site]) > 0,
    );
    const pending = new Set<string>();
    let visible = 0;
    if (containing) {
      this.remove(...containing);
      for (const [u, v] of directedEdges(containing)) {
        this.add(u, v, site);
        pending.add(key(u, v));
      }
    } else {
      for (const [u, v] of this.hullEdges()) {
        if (orient(p[u], p[v], p[site]) >= 0) continue;
        visible++;
        this.add(v, u, site);
        pending.add(key(v, u));
      }
    }
    let flips = 0;
    while (pending.size) {
      const edge = pending.values().next().value!;
      pending.delete(edge);
      const [a, b] = edge.split(',').map(Number);
      if (this.directed.get(edge) !== site) continue;
      const q = this.directed.get(key(b, a));
      if (q === undefined || incircle(p[a], p[b], p[site], p[q]) <= 0) continue;
      this.remove(a, b, site);
      this.remove(b, a, q);
      this.add(a, q, site);
      this.add(q, b, site);
      pending.add(key(a, q));
      pending.add(key(q, b));
      flips++;
    }
    return {
      site,
      kind: containing ? 'inside' : 'outside',
      containing,
      visible,
      flips,
      triangles: this.directed.size / 3,
      hull: this.hullEdges().length,
    };
  }
  walk(
    point: Point,
    triangles: { sites: TriangleSites }[],
    numbers: Map<string, number>,
  ): { path: number[]; triangle: number | null; outside: Pair | null } {
    let current = triangles[0].sites;
    const path = [1];
    while (true) {
      const crossed = directedEdges(current).find(
        ([u, v]) => orient(this.points[u], this.points[v], point) < 0,
      );
      if (!crossed) return { path, triangle: path[path.length - 1], outside: null };
      const [u, v] = crossed;
      const third = this.directed.get(key(v, u));
      if (third === undefined) {
        return { path, triangle: null, outside: [Math.min(u, v), Math.max(u, v)] };
      }
      current = canonical([v, u, third]);
      path.push(numbers.get(current.join(','))!);
    }
  }
}
