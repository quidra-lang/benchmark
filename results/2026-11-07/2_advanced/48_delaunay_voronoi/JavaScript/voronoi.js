'use strict';

const { d2, direction } = require('./predicates');
const { key } = require('./triangulation');

function radiusSquared(a, b, c, area2) {
    const first = d2(a, b), second = d2(b, c), third = d2(c, a);
    return ((first * second) * third) / ((4 * area2) * area2);
}

function position(vertex, hull, points) {
    let on = false;
    for (let i = 0; i < hull.length; i++) {
        const a = points[hull[i]], b = points[hull[(i + 1) % hull.length]];
        const value = (b.x - a.x) * (vertex.Y - a.y * vertex.D) - (b.y - a.y) * (vertex.X - a.x * vertex.D);
        if (value < 0) return 'outside';
        if (value === 0) on = true;
    }
    return on ? 'on' : 'inside';
}

function neighborOrder(site, neighbors, next, triangulation) {
    const first = next.has(site) ? next.get(site) : Math.min(...neighbors);
    const order = [];
    let current = first;
    do {
        order.push(current);
        current = triangulation.directed.get(key(site, current));
    } while (current !== undefined && current !== first);
    return order;
}

const outward = (u, v, points) => direction(points[u], points[v]);

function boundedArea(site, sequence, vertices) {
    const local = sequence.map(number => ({ x: vertices[number - 1].X / vertices[number - 1].D - site.x,
        y: vertices[number - 1].Y / vertices[number - 1].D - site.y }));
    let twice = 0;
    for (let i = 0; i < local.length; i++) {
        const a = local[i], b = local[(i + 1) % local.length];
        twice += a.x * b.y - b.x * a.y;
    }
    return twice / 2;
}

function clippedArea(site, neighbors, points) {
    let polygon = [{ x: 0, y: 0 }, { x: 1000, y: 0 }, { x: 1000, y: 1000 }, { x: 0, y: 1000 }];
    for (const number of neighbors) {
        const other = points[number];
        const c1 = 2 * (other.x - site.x), c2 = 2 * (other.y - site.y);
        const c3 = other.x * other.x + other.y * other.y - site.x * site.x - site.y * site.y;
        const f = point => c1 * point.x + c2 * point.y - c3;
        const next = [];
        for (let i = 0; i < polygon.length; i++) {
            const p = polygon[i], q = polygon[(i + 1) % polygon.length];
            const fp = f(p), fq = f(q);
            if (fp <= 0) next.push(p);
            if (fp < 0 && fq > 0 || fq < 0 && fp > 0) {
                const proportion = fp / (fp - fq);
                next.push({ x: p.x + (q.x - p.x) * proportion, y: p.y + (q.y - p.y) * proportion });
            }
        }
        polygon = next;
    }
    let twice = 0;
    for (let i = 0; i < polygon.length; i++) {
        const p = polygon[i], q = polygon[(i + 1) % polygon.length];
        twice += p.x * q.y - q.x * p.y;
    }
    return twice / 2;
}

module.exports = { radiusSquared, position, neighborOrder, outward, boundedArea, clippedArea };
