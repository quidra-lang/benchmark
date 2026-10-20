'use strict';

const { S, div, isqrt } = require('./fixed_point');
const { add, sub, dot, scale, length, normalize } = require('./vector3');

function slab(lo, hi, origin, direction) {
  let near = -Infinity, far = Infinity, nearAxis = -1, farAxis = -1;
  for (let axis = 0; axis < 3; axis++) {
    if (direction[axis] === 0) {
      if (origin[axis] < lo[axis] || origin[axis] > hi[axis]) return null;
      continue;
    }
    const a = div((lo[axis] - origin[axis]) * S, direction[axis]);
    const b = div((hi[axis] - origin[axis]) * S, direction[axis]);
    const entry = Math.min(a, b), exit = Math.max(a, b);
    if (entry > near) { near = entry; nearAxis = axis; }
    if (exit < far) { far = exit; farAxis = axis; }
  }
  return near > far ? null : { near, far, nearAxis, farAxis };
}

function candidate(object, origin, direction, epsilon) {
  if (object.kind === 'sphere') {
    const oc = sub(origin, object.center), b = dot(oc, direction);
    const center = div(-b * S, dot(direction, direction));
    const h = add(oc, scale(direction, center));
    const q = div(object.radius * object.radius, S) - dot(h, h);
    if (q < 0) return null;
    const half = div(isqrt(q * S) * S, length(direction));
    const first = center - half, second = center + half;
    if (first > epsilon) return { t: first };
    return second > epsilon ? { t: second } : null;
  }
  if (object.kind === 'plane') {
    const denominator = dot(direction, object.normal);
    if (denominator === 0) return null;
    const t = div(dot(sub(object.point, origin), object.normal) * S, denominator);
    return t > epsilon ? { t } : null;
  }
  const hit = slab(object.lo, object.hi, origin, direction);
  if (!hit) return null;
  if (hit.near > epsilon) return { t: hit.near, entering: true, axis: hit.nearAxis };
  return hit.far > epsilon ? { t: hit.far, entering: false, axis: hit.farAxis } : null;
}

function outwardNormal(object, point, direction, hit) {
  if (object.kind === 'sphere') return normalize(sub(point, object.center));
  if (object.kind === 'plane') return object.normal;
  const normal = [0, 0, 0];
  const sign = direction[hit.axis] > 0 ? 1 : -1;
  normal[hit.axis] = (hit.entering ? -sign : sign) * S;
  return normal;
}

function bounds(object, margin) {
  if (object.kind === 'plane') return null;
  if (object.kind === 'sphere') return {
    lo: object.center.map(value => value - object.radius - margin),
    hi: object.center.map(value => value + object.radius + margin)
  };
  return { lo: object.lo.map(value => value - margin), hi: object.hi.map(value => value + margin) };
}

module.exports = { slab, candidate, outwardNormal, bounds };
