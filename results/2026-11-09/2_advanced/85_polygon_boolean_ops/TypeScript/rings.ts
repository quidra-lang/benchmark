import { cross, pointOrder } from './rational.ts';
import { onSegment } from './intersections.ts';
import type { Point } from './rational.ts';
import type { Ring, Region } from './types.ts';

export function inside(p: Point, ring: Ring): boolean {
  let parity = false;
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i], b = ring[(i + 1) % ring.length];
    if ((a.y.compare(p.y) > 0) === (b.y.compare(p.y) > 0)) continue;
    const [low, high] = a.y.compare(b.y) < 0 ? [a, b] : [b, a];
    if (cross(low, high, p).sign() > 0) parity = !parity;
  }
  return parity;
}

export function interior(p: Point, rings: Ring[]): boolean {
  let parity = false;
  for (const ring of rings) if (inside(p, ring)) parity = !parity;
  return parity;
}

export const boundary = (p: Point, ring: Ring): boolean => ring.some((vertex, i) => onSegment(p, vertex, ring[(i + 1) % ring.length]));
export const counterclockwise = (ring: Ring): boolean => cross(ring[ring.length - 1], ring[0], ring[1]).sign() > 0;
export const reverse = (ring: Ring): Ring => [ring[0], ...ring.slice(1).reverse()];

export function rotate(ring: Ring): Ring {
  let first = 0;
  for (let i = 1; i < ring.length; i++) if (pointOrder(ring[i], ring[first]) < 0) first = i;
  return ring.slice(first).concat(ring.slice(0, first));
}

export function assemble(resultRings: Ring[]): Region[] {
  const records = resultRings.map(ring => ({ ring: rotate(ring), depth: 0 }));
  for (const record of records) {
    for (const other of records) if (other !== record && inside(record.ring[0], other.ring)) record.depth++;
    if (counterclockwise(record.ring) !== (record.depth % 2 === 0)) record.ring = reverse(record.ring);
  }
  const outers = records.filter(record => record.depth % 2 === 0).sort((a, b) => pointOrder(a.ring[0], b.ring[0]));
  return outers.map(outer => ({ outer: outer.ring, holes: records
    .filter(record => record.depth === outer.depth + 1 && inside(record.ring[0], outer.ring))
    .sort((a, b) => pointOrder(a.ring[0], b.ring[0])).map(record => record.ring) }));
}

export function area(ring: Ring): number {
  let sum = 0.0;
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i], b = ring[(i + 1) % ring.length];
    const x1 = a.x.value(), y1 = a.y.value(), x2 = b.x.value(), y2 = b.y.value();
    sum += x1 * y2 - x2 * y1;
  }
  return sum / 2;
}

export function perimeter(ring: Ring): number {
  let sum = 0.0;
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i], b = ring[(i + 1) % ring.length];
    const dx = b.x.value() - a.x.value(), dy = b.y.value() - a.y.value();
    sum += Math.sqrt(dx * dx + dy * dy);
  }
  return sum;
}

export const flatten = (result: Region[]): Ring[] => result.flatMap(polygon => [polygon.outer, ...polygon.holes]);
