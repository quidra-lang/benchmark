import { div, isqrt, mul, S } from './fixed_point.ts';
import type { Color, Material } from './scene.ts';
import { add, dot, norm, scale, sub, type Vec3 } from './vector3.ts';

export function baseColor(material: Material, point: Vec3): Color {
  const checker = material.checker;
  return checker &&
    (div(point[0], checker.size) + div(point[1], checker.size) + div(point[2], checker.size)) %
      2 !==
      0
    ? checker.color
    : material.color;
}
export function components(
  material: Material,
  normal: Vec3,
  light: Vec3,
  view: Vec3,
  intensity: number,
  ndl: number,
): { diffuse: number; specular: number } {
  const diffuse = mul(mul(material.kd, ndl), intensity);
  const reflected = sub(scale(normal, 2 * ndl), light);
  const rv = dot(reflected, view);
  let specular = 0;
  if (rv > 0) {
    let p = S;
    for (let i = 0; i < material.exponent; i++) p = mul(p, rv);
    specular = mul(mul(material.ks, p), intensity);
  }
  return { diffuse, specular };
}
export const reflection = (direction: Vec3, normal: Vec3) =>
  norm(sub(direction, scale(normal, 2 * dot(direction, normal))));
export function transmission(
  material: Material,
  direction: Vec3,
  normal: Vec3,
  front: boolean,
): { reflected: number; transmitted: number; direction?: Vec3; tir: boolean } {
  let reflected = material.kr;
  let transmitted = material.kt;
  let refracted: Vec3 | undefined;
  let tir = false;
  if (material.kt > 0) {
    const eta = front ? div(S * S, material.ior) : material.ior;
    const cn = -dot(direction, normal);
    const disc = S * S - div(mul(eta, eta) * (S * S - cn * cn), S);
    if (disc < 0) {
      reflected = material.kr + material.kt;
      transmitted = 0;
      tir = true;
    } else {
      refracted = norm(add(scale(direction, eta), scale(normal, mul(eta, cn) - isqrt(disc))));
      const r0 = div((material.ior - S) * S, material.ior + S);
      const capitalR0 = mul(r0, r0);
      const x = S - Math.min(cn, S);
      let p = S;
      for (let i = 0; i < 5; i++) p = mul(p, x);
      const fresnel = capitalR0 + mul(S - capitalR0, p);
      const fr = mul(material.kt, fresnel);
      reflected = material.kr + fr;
      transmitted = material.kt - fr;
    }
  }
  return { reflected, transmitted, direction: refracted, tir };
}
export function mix(entries: { color: Color; weight: number }[]): Color {
  const color: Color = [0, 0, 0];
  for (const entry of entries) {
    for (let c = 0; c < 3; c++) color[c] += div(entry.color[c] * entry.weight, S);
  }
  return color;
}
