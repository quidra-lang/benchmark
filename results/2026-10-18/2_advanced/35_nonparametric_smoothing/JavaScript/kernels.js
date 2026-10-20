'use strict';

const constants = { epanechnikov: 0.75, biweight: 0.9375, triweight: 1.09375 };

function kernel(name, u) {
    const t = 1 - u * u;
    if (name === 'epanechnikov') return 0.75 * t;
    if (name === 'biweight') return 0.9375 * t * t;
    return 1.09375 * t * t * t;
}

function estimate(points, kind, name, bandwidth, position) {
    const x0 = position / 100;
    const h = bandwidth / 100;
    const used = [];
    let s0 = 0;
    let s1 = 0;
    let s2 = 0;
    let t0 = 0;
    let t1 = 0;
    for (let j = 0; j < points.length; j++) {
        const point = points[j];
        if (Math.abs(point.X - position) >= bandwidth) continue;
        const d = point.x - x0;
        const weight = kernel(name, d / h);
        used.push({ index: j, d, weight });
        s0 += weight;
        t0 += weight * point.y;
        if (kind === 'll') {
            s1 += weight * d;
            s2 += weight * d * d;
            t1 += weight * d * point.y;
        }
    }
    if (used.length < (kind === 'nw' ? 1 : 2)) return { value: null, weights: null, diagonal: null };
    const weights = Array(points.length).fill(0);
    if (kind === 'nw') {
        for (const point of used) weights[point.index] = point.weight / s0;
        return { value: t0 / s0, weights, diagonal: constants[name] / s0 };
    }
    const q = s0 * s2 - s1 * s1;
    for (const point of used) weights[point.index] = point.weight * (s2 - s1 * point.d) / q;
    return { value: (s2 * t0 - s1 * t1) / q, weights, diagonal: constants[name] * s2 / q };
}

function fit(points, kind, name, bandwidth) {
    const at = position => estimate(points, kind, name, bandwidth, position);
    const estimates = points.map(point => at(point.X));
    if (estimates.some(item => item.value === null)) return { yhat: null, lev: null, edf: null, at };
    const lev = estimates.map(item => item.diagonal);
    let edf = 0;
    for (const value of lev) edf += value;
    return { yhat: estimates.map(item => item.value), lev, edf, at };
}

module.exports = { kernel, estimate, fit };
