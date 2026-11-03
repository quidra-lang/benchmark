import { ONE, add, subtract, scale, determinant, cross } from './rational.ts';
import type { Fraction, Point } from './rational.ts';
import type { GraphCrossing } from './types.ts';
const minimum = (a: Fraction, b: Fraction): Fraction => a.compare(b) <= 0 ? a : b;
const maximum = (a: Fraction, b: Fraction): Fraction => a.compare(b) >= 0 ? a : b;

export function onSegment(p: Point, a: Point, b: Point): boolean {
  return cross(a, b, p).sign() === 0 && p.x.compare(minimum(a.x, b.x)) >= 0 && p.x.compare(maximum(a.x, b.x)) <= 0
    && p.y.compare(minimum(a.y, b.y)) >= 0 && p.y.compare(maximum(a.y, b.y)) <= 0;
}

export function touch(a: Point, b: Point, c: Point, d: Point): boolean {
  const first = cross(a, b, c).sign() * cross(a, b, d).sign();
  const second = cross(c, d, a).sign() * cross(c, d, b).sign();
  return (first < 0 && second < 0) || onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d);
}

export function overlap(a: Point, b: Point, c: Point, d: Point): boolean {
  if (cross(a, b, c).sign() !== 0 || cross(a, b, d).sign() !== 0) return false;
  const coordinate = a.x.compare(b.x) === 0 ? 'y' : 'x';
  const low = maximum(minimum(a[coordinate], b[coordinate]), minimum(c[coordinate], d[coordinate]));
  const high = minimum(maximum(a[coordinate], b[coordinate]), maximum(c[coordinate], d[coordinate]));
  return low.compare(high) < 0;
}

export function crossing(p1: Point, p2: Point, q1: Point, q2: Point): GraphCrossing | null {
  const r = subtract(p2, p1), s = subtract(q2, q1), denominator = determinant(r, s);
  if (denominator.sign() === 0) return null;
  const g = subtract(q1, p1), t = determinant(g, s).div(denominator), u = determinant(g, r).div(denominator);
  if (t.sign() <= 0 || t.compare(ONE) >= 0 || u.sign() <= 0 || u.compare(ONE) >= 0) return null;
  return { point: add(p1, scale(r, t)), t, u };
}

export function lineIntersection(prev: Point, cur: Point, first: Point, second: Point): Point {
  const a = cross(first, second, prev), b = cross(first, second, cur);
  return add(prev, scale(subtract(cur, prev), a.div(a.sub(b))));
}

