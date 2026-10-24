'use strict';

const orient = (p, q, r) => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
const d2 = (p, q) => (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y);
const dot = (o, p, q) => (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y);

function incircle(a, b, c, d) {
    const ax = a.x - d.x, ay = a.y - d.y;
    const bx = b.x - d.x, by = b.y - d.y;
    const cx = c.x - d.x, cy = c.y - d.y;
    const aa = ax * ax + ay * ay, bb = bx * bx + by * by, cc = cx * cx + cy * cy;
    return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx);
}

function circumcenter(a, b, c) {
    const bx = b.x - a.x, by = b.y - a.y;
    const cx = c.x - a.x, cy = c.y - a.y;
    const bb = bx * bx + by * by, cc = cx * cx + cy * cy;
    const D = 2 * (bx * cy - by * cx);
    return { X: a.x * D + cy * bb - by * cc, Y: a.y * D + bx * cc - cx * bb, D };
}

function gcd(a, b) {
    a = Math.abs(a);
    b = Math.abs(b);
    while (b !== 0) [a, b] = [b, a % b];
    return a;
}

function fraction(numerator, denominator) {
    const divisor = gcd(numerator, denominator);
    const top = numerator / divisor, bottom = denominator / divisor;
    return bottom === 1 ? String(top) : top + '/' + bottom;
}

function direction(a, b) {
    const dx = b.x - a.x, dy = b.y - a.y;
    const divisor = gcd(dx, dy);
    return [dy / divisor, -dx / divisor];
}

module.exports = { orient, d2, dot, incircle, circumcenter, gcd, fraction, direction };
