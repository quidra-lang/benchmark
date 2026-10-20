export interface Point { x: number; y: number }
export interface RationalPoint { X: number; Y: number; D: number }
export type Pair = [number, number];
export type TriangleSites = [number, number, number];
export const orient = (p: Point, q: Point, r: Point): number => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
export const d2 = (p: Point, q: Point): number => (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y);
export const dot = (o: Point, p: Point, q: Point): number => (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y);
export function incircle(a: Point, b: Point, c: Point, d: Point): number {
  const ax = a.x - d.x, ay = a.y - d.y, bx = b.x - d.x, by = b.y - d.y, cx = c.x - d.x, cy = c.y - d.y;
  const aa = ax * ax + ay * ay, bb = bx * bx + by * by, cc = cx * cx + cy * cy;
  return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx);
}
export function circumcenter(a: Point, b: Point, c: Point): RationalPoint {
  const bx = b.x - a.x, by = b.y - a.y, cx = c.x - a.x, cy = c.y - a.y;
  const bb = bx * bx + by * by, cc = cx * cx + cy * cy, D = 2 * (bx * cy - by * cx);
  return { X: a.x * D + cy * bb - by * cc, Y: a.y * D + bx * cc - cx * bb, D };
}
export function gcd(a: number, b: number): number {
  a = Math.abs(a); b = Math.abs(b);
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}
export function fraction(numerator: number, denominator: number): string {
  const divisor = gcd(numerator, denominator), top = numerator / divisor, bottom = denominator / divisor;
  return bottom === 1 ? String(top) : `${top}/${bottom}`;
}
export function direction(a: Point, b: Point): Pair {
  const dx = b.x - a.x, dy = b.y - a.y, divisor = gcd(dx, dy);
  return [dy / divisor, -dx / divisor];
}
