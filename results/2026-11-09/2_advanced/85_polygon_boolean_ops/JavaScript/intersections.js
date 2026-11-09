'use strict';

const { ONE, add, subtract, scale, determinant, cross } = require('./rational');
const minimum = (a, b) => a.compare(b) <= 0 ? a : b;
const maximum = (a, b) => a.compare(b) >= 0 ? a : b;

function onSegment(p, a, b) {
  return cross(a, b, p).sign() === 0 && p.x.compare(minimum(a.x, b.x)) >= 0 && p.x.compare(maximum(a.x, b.x)) <= 0
    && p.y.compare(minimum(a.y, b.y)) >= 0 && p.y.compare(maximum(a.y, b.y)) <= 0;
}

function touch(a, b, c, d) {
  const first = cross(a, b, c).sign() * cross(a, b, d).sign();
  const second = cross(c, d, a).sign() * cross(c, d, b).sign();
  return (first < 0 && second < 0) || onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d);
}

function overlap(a, b, c, d) {
  if (cross(a, b, c).sign() !== 0 || cross(a, b, d).sign() !== 0) return false;
  const coordinate = a.x.compare(b.x) === 0 ? 'y' : 'x';
  const low = maximum(minimum(a[coordinate], b[coordinate]), minimum(c[coordinate], d[coordinate]));
  const high = minimum(maximum(a[coordinate], b[coordinate]), maximum(c[coordinate], d[coordinate]));
  return low.compare(high) < 0;
}

function crossing(p1, p2, q1, q2) {
  const r = subtract(p2, p1), s = subtract(q2, q1), denominator = determinant(r, s);
  if (denominator.sign() === 0) return null;
  const g = subtract(q1, p1), t = determinant(g, s).div(denominator), u = determinant(g, r).div(denominator);
  if (t.sign() <= 0 || t.compare(ONE) >= 0 || u.sign() <= 0 || u.compare(ONE) >= 0) return null;
  return { point: add(p1, scale(r, t)), t, u };
}

function lineIntersection(prev, cur, first, second) {
  const a = cross(first, second, prev), b = cross(first, second, cur);
  return add(prev, scale(subtract(cur, prev), a.div(a.sub(b))));
}

module.exports = { onSegment, touch, overlap, crossing, lineIntersection };
