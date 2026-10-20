import { div, isqrt, S } from './fixed_point.ts';

export type Vec3 = [number, number, number];
export const triple = (values: number[], start = 0): Vec3 => [
  values[start],
  values[start + 1],
  values[start + 2],
];
export const add = (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const sub = (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export const neg = (a: Vec3): Vec3 => [-a[0], -a[1], -a[2]];
export const dot = (a: Vec3, b: Vec3) => div(a[0] * b[0] + a[1] * b[1] + a[2] * b[2], S);
export const scale = (a: Vec3, k: number): Vec3 => [
  div(a[0] * k, S),
  div(a[1] * k, S),
  div(a[2] * k, S),
];
export const length = (a: Vec3) => isqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
export function norm(a: Vec3): Vec3 {
  const size = length(a);
  return [div(a[0] * S, size), div(a[1] * S, size), div(a[2] * S, size)];
}
