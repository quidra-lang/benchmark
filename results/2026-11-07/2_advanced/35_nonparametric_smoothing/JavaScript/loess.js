'use strict';

function median(values) {
    const sorted = values.slice().sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function cholesky(matrix) {
    const lower = matrix.map(() => Array(matrix.length).fill(0));
    for (let k = 0; k < matrix.length; k++) {
        for (let l = 0; l <= k; l++) {
            let sigma = matrix[k][l];
            for (let i = 0; i < l; i++) sigma -= lower[k][i] * lower[l][i];
            lower[k][l] = l === k ? Math.sqrt(sigma) : sigma / lower[l][l];
        }
    }
    return lower;
}

function solve(lower, right) {
    const eta = [];
    for (let k = 0; k < right.length; k++) {
        let value = right[k];
        for (let j = 0; j < k; j++) value -= lower[k][j] * eta[j];
        eta.push(value / lower[k][k]);
    }
    const result = Array(right.length);
    for (let k = right.length - 1; k >= 0; k--) {
        let value = eta[k];
        for (let j = k + 1; j < right.length; j++) value -= lower[j][k] * result[j];
        result[k] = value / lower[k][k];
    }
    return result;
}

function localFit(points, degree, span, robustness, position) {
    const count = Math.floor(span * points.length / 100);
    const neighbours = points.map((_, index) => index).sort((a, b) =>
        Math.abs(points[a].X - position) - Math.abs(points[b].X - position) || a - b).slice(0, count);
    const extent = Math.abs(points[neighbours.at(-1)].X - position);
    neighbours.sort((a, b) => a - b);
    const x0 = position / 100;
    const local = neighbours.map(index => {
        const distance = Math.abs(points[index].X - position) / extent;
        const s = 1 - distance * distance * distance;
        const weight = s * s * s;
        const d = points[index].x - x0;
        return { index, weight: weight * robustness[index], basis: degree === 1 ? [1, d] : [1, d, d * d] };
    });
    const matrix = Array.from({ length: degree + 1 }, () => Array(degree + 1).fill(0));
    const right = Array(degree + 1).fill(0);
    for (const point of local) {
        for (let k = 0; k <= degree; k++) {
            for (let l = 0; l <= degree; l++) matrix[k][l] += point.weight * point.basis[k] * point.basis[l];
            right[k] += point.weight * point.basis[k] * points[point.index].y;
        }
    }
    const lower = cholesky(matrix);
    const beta = solve(lower, right);
    const unit = Array(degree + 1).fill(0);
    unit[0] = 1;
    const zeta = solve(lower, unit);
    const weights = Array(points.length).fill(0);
    for (const point of local) {
        let total = 0;
        for (let k = 0; k <= degree; k++) total += zeta[k] * point.basis[k];
        weights[point.index] = point.weight * total;
    }
    return { value: beta[0], weights, zeta0: zeta[0] };
}

function fit(points, degree, span, iterations) {
    let robustness = points.map(() => 1);
    let estimates = points.map(point => localFit(points, degree, span, robustness, point.X));
    const records = [];
    for (let iteration = 1; iteration <= iterations; iteration++) {
        const residuals = points.map((point, i) => point.y - estimates[i].value);
        const scale = median(residuals.map(Math.abs));
        robustness = residuals.map(error => {
            const u = error / (6 * scale);
            if (Math.abs(u) >= 1) return 0;
            const value = 1 - u * u;
            return value * value;
        });
        const next = points.map(point => localFit(points, degree, span, robustness, point.X));
        let change = 0;
        for (let i = 0; i < points.length; i++) change = Math.max(change, Math.abs(next[i].value - estimates[i].value));
        records.push({ iteration, scale, zeros: robustness.filter(value => value === 0).length, change });
        estimates = next;
    }
    const lev = estimates.map((estimate, i) => robustness[i] * estimate.zeta0);
    let edf = 0;
    for (const value of lev) edf += value;
    return { yhat: estimates.map(estimate => estimate.value), lev, edf, robustness, records,
        at: position => localFit(points, degree, span, robustness, position) };
}

module.exports = { median, cholesky, solve, localFit, fit };
