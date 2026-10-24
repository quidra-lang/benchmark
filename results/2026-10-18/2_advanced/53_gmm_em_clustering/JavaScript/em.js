'use strict';

const gaussian = require('./gaussian');

function adjust(initial, type) {
    const components = initial.map(component => ({...component}));
    if (type === 'TIED') {
        let a = 0;
        let b = 0;
        let c = 0;
        for (const component of components) {
            a += component.w * component.a;
            b += component.w * component.b;
            c += component.w * component.c;
        }
        for (const component of components) Object.assign(component, {a, b, c});
    } else if (type === 'DIAG') {
        for (const component of components) component.b = 0;
    } else if (type === 'SPHERICAL') {
        for (const component of components) {
            const v = (component.a + component.c) / 2;
            Object.assign(component, {a: v, b: 0, c: v});
        }
    }
    return components;
}

function expectation(points, components) {
    const responsibilities = [];
    const logDensities = [];
    let loglik = 0;
    for (const point of points) {
        const logs = components.map(component => gaussian.logWeighted(point, component));
        let maximum = logs[0];
        for (let k = 1; k < logs.length; k++) maximum = Math.max(maximum, logs[k]);
        const exponents = logs.map(value => Math.exp(value - maximum));
        let total = 0;
        for (const value of exponents) total += value;
        responsibilities.push(exponents.map(value => value / total));
        const lp = maximum + Math.log(total);
        logDensities.push(lp);
        loglik += lp;
    }
    return {responsibilities, logDensities, loglik};
}

function maximization(points, responsibilities, type, eps) {
    const components = [];
    const moments = [];
    const K = responsibilities[0].length;
    for (let k = 0; k < K; k++) {
        let count = 0;
        let sx = 0;
        let sy = 0;
        for (let i = 0; i < points.length; i++) {
            const r = responsibilities[i][k];
            count += r;
            sx += r * points[i].x;
            sy += r * points[i].y;
        }
        const mx = sx / count;
        const my = sy / count;
        let A = 0;
        let B = 0;
        let C = 0;
        for (let i = 0; i < points.length; i++) {
            const r = responsibilities[i][k];
            const dx = points[i].x - mx;
            const dy = points[i].y - my;
            A += r * dx * dx;
            B += r * dx * dy;
            C += r * dy * dy;
        }
        moments.push({A, B, C});
        const component = {w: count / points.length, mx, my};
        if (type === 'FULL') {
            Object.assign(component, {a: A / count + eps, b: B / count, c: C / count + eps});
        } else if (type === 'DIAG') {
            Object.assign(component, {a: A / count + eps, b: 0, c: C / count + eps});
        } else if (type === 'SPHERICAL') {
            const v = (A / count + C / count) / 2 + eps;
            Object.assign(component, {a: v, b: 0, c: v});
        }
        components.push(component);
    }
    if (type === 'TIED') {
        let A = 0;
        let B = 0;
        let C = 0;
        for (const moment of moments) {
            A += moment.A;
            B += moment.B;
            C += moment.C;
        }
        const covariance = {
            a: A / points.length + eps, b: B / points.length, c: C / points.length + eps
        };
        for (const component of components) Object.assign(component, covariance);
    }
    return components;
}

function fit(points, initial, type, iterations, eps) {
    let components = adjust(initial, type);
    let step = expectation(points, components);
    const trace = [step.loglik];
    for (let iteration = 1; iteration <= iterations; iteration++) {
        components = maximization(points, step.responsibilities, type, eps);
        step = expectation(points, components);
        trace.push(step.loglik);
    }
    return {components, trace, ...step};
}

module.exports = {adjust, expectation, maximization, fit};
