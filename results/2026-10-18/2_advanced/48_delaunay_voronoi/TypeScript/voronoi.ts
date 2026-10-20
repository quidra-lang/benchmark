import { d2, direction } from './predicates.ts';
import type { Point, RationalPoint } from './predicates.ts';
import { key } from './triangulation.ts';
import type { Triangulation } from './triangulation.ts';
export type Position = 'inside' | 'on' | 'outside';
export interface Vertex extends RationalPoint {
  number: number;
  radius2: number;
  position: Position;
}
export function radiusSquared(a: Point, b: Point, c: Point, area2: number): number {
  const first = d2(a, b);
  const second = d2(b, c);
  const third = d2(c, a);
  return (first * second * third) / (4 * area2 * area2);
}
export function position(vertex: RationalPoint, hull: number[], points: Point[]): Position {
  let on = false;
  for (let i = 0; i < hull.length; i++) {
    const a = points[hull[i]];
    const b = points[hull[(i + 1) % hull.length]];
    const value =
      (b.x - a.x) * (vertex.Y - a.y * vertex.D) - (b.y - a.y) * (vertex.X - a.x * vertex.D);
    if (value < 0) return 'outside';
    if (value === 0) on = true;
  }
  return on ? 'on' : 'inside';
}
export function neighborOrder(
  site: number,
  neighbors: number[],
  next: Map<number, number>,
  mesh: Triangulation,
): number[] {
  const first = next.get(site) ?? Math.min(...neighbors);
  const order: number[] = [];
  let current = first;
  while (true) {
    order.push(current);
    const following = mesh.directed.get(key(site, current));
    if (following === undefined || following === first) break;
    current = following;
  }
  return order;
}
export const outward = (u: number, v: number, points: Point[]) => direction(points[u], points[v]);
export function boundedArea(site: Point, sequence: number[], vertices: Vertex[]): number {
  const local = sequence.map((n) => ({
    x: vertices[n - 1].X / vertices[n - 1].D - site.x,
    y: vertices[n - 1].Y / vertices[n - 1].D - site.y,
  }));
  let twice = 0;
  for (let i = 0; i < local.length; i++) {
    const a = local[i];
    const b = local[(i + 1) % local.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return twice / 2;
}
export function clippedArea(site: Point, neighbors: number[], points: Point[]): number {
  let polygon: Point[] = [
    { x: 0, y: 0 },
    { x: 1000, y: 0 },
    { x: 1000, y: 1000 },
    { x: 0, y: 1000 },
  ];
  for (const n of neighbors) {
    const other = points[n];
    const c1 = 2 * (other.x - site.x);
    const c2 = 2 * (other.y - site.y);
    const c3 = other.x * other.x + other.y * other.y - site.x * site.x - site.y * site.y;
    const f = (p: Point) => c1 * p.x + c2 * p.y - c3;
    const next: Point[] = [];
    for (let i = 0; i < polygon.length; i++) {
      const p = polygon[i];
      const q = polygon[(i + 1) % polygon.length];
      const fp = f(p);
      const fq = f(q);
      if (fp <= 0) next.push(p);
      if ((fp < 0 && fq > 0) || (fq < 0 && fp > 0)) {
        const t = fp / (fp - fq);
        next.push({ x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t });
      }
    }
    polygon = next;
  }
  let twice = 0;
  for (let i = 0; i < polygon.length; i++) {
    const p = polygon[i];
    const q = polygon[(i + 1) % polygon.length];
    twice += p.x * q.y - q.x * p.y;
  }
  return twice / 2;
}
