import type { Position, Covariance, Component } from './dataset.ts';
export function determinant(s: Covariance): number {
  return s.a * s.c - s.b * s.b;
}
export function quadratic(p: Position, s: Covariance & { mx: number; my: number }): number {
  const dx = p.x - s.mx;
  const dy = p.y - s.my;
  return (s.c * dx * dx - 2 * s.b * dx * dy + s.a * dy * dy) / determinant(s);
}
export function logWeighted(p: Position, s: Component): number {
  return Math.log(s.w) - Math.log(2 * Math.PI) - Math.log(determinant(s)) / 2 - quadratic(p, s) / 2;
}
export function eigen({ a, b, c }: Covariance) {
  const h = (a + c) / 2;
  const half = (a - c) / 2;
  const g = Math.sqrt(half * half + b * b);
  const lambda1 = h + g;
  const lambda2 = h - g;
  let ux: number;
  let uy: number;
  if (b === 0) [ux, uy] = a >= c ? [1, 0] : [0, 1];
  else {
    const [vx, vy] = a >= c ? [lambda1 - c, b] : [b, lambda1 - a];
    const length = Math.sqrt(vx * vx + vy * vy);
    ux = (vx < 0 ? -vx : vx) / length;
    uy = (vx < 0 ? -vy : vy) / length;
  }
  return { lambda1, lambda2, ux, uy, angle: (Math.atan2(uy, ux) * 180) / Math.PI };
}
export function bhattacharyya(first: Component, second: Component): number {
  const average = {
    mx: first.mx,
    my: first.my,
    a: (first.a + second.a) / 2,
    b: (first.b + second.b) / 2,
    c: (first.c + second.c) / 2,
  };
  return (
    quadratic({ x: second.mx, y: second.my }, average) / 8 +
    Math.log(determinant(average) / Math.sqrt(determinant(first) * determinant(second))) / 2
  );
}
