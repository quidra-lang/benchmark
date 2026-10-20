'use strict';

class SmoothingSpline {
    constructor(points, lambda) {
        this.positions = points.map(point => point.X);
        this.x = points.map(point => point.x);
        this.lambda = lambda;
        this.h = this.x.slice(1).map((value, i) => value - this.x[i]);
        const count = points.length - 2;
        const a = Array.from({ length: count }, (_, k) => 1 / this.h[k]);
        const c = Array.from({ length: count }, (_, k) => 1 / this.h[k + 1]);
        const b = a.map((value, k) => -(value + c[k]));
        const diagonal = a.map((value, k) => (this.h[k] + this.h[k + 1]) / 3
            + lambda * (value * value + b[k] * b[k] + c[k] * c[k]));
        const first = Array.from({ length: count - 1 }, (_, k) => this.h[k + 1] / 6 + lambda * c[k] * (b[k] + b[k + 1]));
        const second = Array.from({ length: count - 2 }, (_, k) => lambda * c[k] * c[k + 1]);
        this.lower1 = [];
        this.lower2 = [];
        this.diagonal = [];
        for (let k = 0; k < count; k++) {
            const d1 = this.diagonal[k - 1] ?? 0;
            const d2 = this.diagonal[k - 2] ?? 0;
            const l2 = k >= 2 ? second[k - 2] / d2 : 0;
            const l1 = k >= 1 ? (first[k - 1] - l2 * d2 * this.lower1[k - 1]) / d1 : 0;
            this.lower1.push(l1);
            this.lower2.push(l2);
            this.diagonal.push(diagonal[k] - l1 * l1 * d1 - l2 * l2 * d2);
        }
    }

    fit(values) {
        const z = [];
        for (let k = 0; k < values.length - 2; k++) {
            const phi = (values[k + 2] - values[k + 1]) / this.h[k + 1] - (values[k + 1] - values[k]) / this.h[k];
            z.push(phi - this.lower1[k] * (z[k - 1] ?? 0) - this.lower2[k] * (z[k - 2] ?? 0));
        }
        const gamma = Array(values.length).fill(0);
        for (let k = z.length - 1; k >= 0; k--) {
            gamma[k + 1] = z[k] / this.diagonal[k] - (this.lower1[k + 1] ?? 0) * gamma[k + 2]
                - (this.lower2[k + 2] ?? 0) * (gamma[k + 3] ?? 0);
        }
        const g = values.map((value, i) => {
            let omega;
            if (i === 0) omega = (gamma[1] - gamma[0]) / this.h[0];
            else if (i === values.length - 1) omega = 0 - (gamma[i] - gamma[i - 1]) / this.h[i - 1];
            else omega = (gamma[i + 1] - gamma[i]) / this.h[i] - (gamma[i] - gamma[i - 1]) / this.h[i - 1];
            return value - this.lambda * omega;
        });
        return { g, gamma };
    }

    evaluate(curve, position) {
        const { g, gamma } = curve;
        const value = position / 100;
        const last = this.x.length - 1;
        if (position < this.positions[0]) {
            const slope = (g[1] - g[0]) / this.h[0] - this.h[0] * gamma[1] / 6;
            return g[0] - (this.x[0] - value) * slope;
        }
        if (position > this.positions[last]) {
            const slope = (g[last] - g[last - 1]) / this.h[last - 1] + this.h[last - 1] * gamma[last - 1] / 6;
            return g[last] + (value - this.x[last]) * slope;
        }
        let low = 0;
        let high = this.positions.length;
        while (low < high) {
            const middle = Math.floor((low + high) / 2);
            if (this.positions[middle] < position) low = middle + 1;
            else high = middle;
        }
        if (this.positions[low] === position) return g[low];
        const i = low - 1;
        const pl = value - this.x[i];
        const pr = this.x[i + 1] - value;
        return (pl * g[i + 1] + pr * g[i]) / this.h[i]
            - pl * pr * ((1 + pl / this.h[i]) * gamma[i + 1] + (1 + pr / this.h[i]) * gamma[i]) / 6;
    }

    unitFits() {
        return this.positions.map((_, index) => {
            const values = this.positions.map(() => 0);
            values[index] = 1;
            return this.fit(values);
        });
    }
}

function fit(points, lambda, withWeights = true) {
    const system = new SmoothingSpline(points, lambda);
    const curve = system.fit(points.map(point => point.y));
    const units = withWeights ? system.unitFits() : null;
    const lev = units === null ? null : units.map((unit, i) => unit.g[i]);
    let edf = null;
    if (lev !== null) { edf = 0; for (const value of lev) edf += value; }
    return { system, curve, yhat: curve.g, lev, edf, at: position => ({ value: system.evaluate(curve, position),
        weights: units === null ? null : units.map(unit => system.evaluate(unit, position)) }) };
}

module.exports = { SmoothingSpline, fit };
