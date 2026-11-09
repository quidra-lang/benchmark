import { div, isqrt, S } from './fixed_point.ts';
import type { BoundedObject, SceneObject } from './scene.ts';
import { add, dot, length, norm, scale, sub, type Vec3 } from './vector3.ts';

export interface Ray {
  origin: Vec3;
  direction: Vec3;
}
export interface Bounds {
  lo: Vec3;
  hi: Vec3;
}
export interface Slab {
  near: number;
  nearAxis: number;
  far: number;
  farAxis: number;
}
export interface Hit {
  object: SceneObject;
  t: number;
  axis?: number;
  entering?: boolean;
}
export function bounds(object: BoundedObject, pad: number): Bounds {
  if (object.kind === 'sphere') {
    return {
      lo: [
        object.center[0] - object.radius - pad,
        object.center[1] - object.radius - pad,
        object.center[2] - object.radius - pad,
      ],
      hi: [
        object.center[0] + object.radius + pad,
        object.center[1] + object.radius + pad,
        object.center[2] + object.radius + pad,
      ],
    };
  }
  return {
    lo: [object.lo[0] - pad, object.lo[1] - pad, object.lo[2] - pad],
    hi: [object.hi[0] + pad, object.hi[1] + pad, object.hi[2] + pad],
  };
}
export function slab(box: Bounds, ray: Ray): Slab | undefined {
  let near = -Infinity;
  let far = Infinity;
  let nearAxis = -1;
  let farAxis = -1;
  for (let a = 0; a < 3; a++) {
    const o = ray.origin[a];
    const d = ray.direction[a];
    if (d === 0) {
      if (o < box.lo[a] || o > box.hi[a]) return undefined;
      continue;
    }
    const first = div((box.lo[a] - o) * S, d);
    const second = div((box.hi[a] - o) * S, d);
    const entry = Math.min(first, second);
    const exit = Math.max(first, second);
    if (entry > near) {
      near = entry;
      nearAxis = a;
    }
    if (exit < far) {
      far = exit;
      farAxis = a;
    }
  }
  return near > far ? undefined : { near, nearAxis, far, farAxis };
}
export function intersect(object: SceneObject, ray: Ray, epsilon: number): Hit | undefined {
  const { origin: o, direction: d } = ray;
  if (object.kind === 'sphere') {
    const oc = sub(o, object.center);
    const b = dot(oc, d);
    const tc = div(-b * S, dot(d, d));
    const h = add(oc, scale(d, tc));
    const q = div(object.radius * object.radius, S) - dot(h, h);
    if (q < 0) return undefined;
    const w = div(isqrt(q * S) * S, length(d));
    const t1 = tc - w;
    const t2 = tc + w;
    return t1 > epsilon ? { object, t: t1 } : t2 > epsilon ? { object, t: t2 } : undefined;
  }
  if (object.kind === 'plane') {
    const den = dot(d, object.normal);
    if (den === 0) return undefined;
    const t = div(dot(sub(object.point, o), object.normal) * S, den);
    return t > epsilon ? { object, t } : undefined;
  }
  const result = slab(object, ray);
  if (!result) return undefined;
  return result.near > epsilon
    ? { object, t: result.near, axis: result.nearAxis, entering: true }
    : result.far > epsilon
      ? { object, t: result.far, axis: result.farAxis, entering: false }
      : undefined;
}
export function outwardNormal(hit: Hit, point: Vec3, direction: Vec3): Vec3 {
  if (hit.object.kind === 'sphere') return norm(sub(point, hit.object.center));
  if (hit.object.kind === 'plane') return hit.object.normal;
  const axis = hit.axis;
  if (axis === undefined) throw new Error('Missing box face');
  const normal: Vec3 = [0, 0, 0];
  normal[axis] = (hit.entering ? (direction[axis] > 0 ? -1 : 1) : direction[axis] > 0 ? 1 : -1) * S;
  return normal;
}
