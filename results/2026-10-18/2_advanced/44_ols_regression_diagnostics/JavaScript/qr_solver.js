'use strict';

function fit(matrix, response, weights, tolerance) {
    const n = matrix.length;
    const p = matrix[0].length;
    const roots = weights.map(Math.sqrt);
    const weighted = matrix.map((row, i) => row.map(value => roots[i] * value));
    const working = weighted.map(row => row.slice());
    const b = response.map((value, i) => roots[i] * value);
    const lengths = Array(p).fill(0);
    for (let j = 0; j < p; j++) {
        let squares = 0;
        for (let i = 0; i < n; i++) squares += weighted[i][j] * weighted[i][j];
        lengths[j] = Math.sqrt(squares);
    }
    const accepted = [];
    const triangular = Array.from({ length: p }, () => Array(p).fill(0));
    for (let j = 0; j < p; j++) {
        const start = accepted.length;
        let squares = 0;
        for (let i = start; i < n; i++) squares += working[i][j] * working[i][j];
        const length = Math.sqrt(squares);
        if (length <= tolerance * lengths[j]) continue;
        accepted.push(j);
        const alpha = working[start][j] >= 0 ? -length : length;
        const vector = Array(n).fill(0);
        vector[start] = working[start][j] - alpha;
        for (let i = start + 1; i < n; i++) vector[i] = working[i][j];
        let norm = 0;
        for (let i = start; i < n; i++) norm += vector[i] * vector[i];
        for (let i = 0; i < start; i++) triangular[i][start] = working[i][j];
        triangular[start][start] = alpha;
        for (let column = j + 1; column < p; column++) {
            let projection = 0;
            for (let i = start; i < n; i++) projection += vector[i] * working[i][column];
            const delta = 2 * projection / norm;
            for (let i = start; i < n; i++) working[i][column] -= delta * vector[i];
        }
        let projection = 0;
        for (let i = start; i < n; i++) projection += vector[i] * b[i];
        const delta = 2 * projection / norm;
        for (let i = start; i < n; i++) b[i] -= delta * vector[i];
    }
    const rank = accepted.length;
    const effects = b.slice(0, rank);
    const coefficients = Array(p).fill(null);
    for (let k = rank - 1; k >= 0; k--) {
        let total = 0;
        for (let l = k + 1; l < rank; l++) total += triangular[k][l] * coefficients[accepted[l]];
        coefficients[accepted[k]] = (effects[k] - total) / triangular[k][k];
    }
    const inverse = Array.from({ length: rank }, () => Array(rank).fill(0));
    for (let m = 0; m < rank; m++) {
        for (let l = rank - 1; l >= 0; l--) {
            let total = 0;
            for (let q = l + 1; q < rank; q++) total += triangular[l][q] * inverse[q][m];
            inverse[l][m] = ((l === m ? 1 : 0) - total) / triangular[l][l];
        }
    }
    const variance = inverse.map(row => row.reduce((sum, value) => sum + value * value, 0));
    const u = [];
    const g = [];
    const leverage = [];
    const fitted = [];
    const residuals = [];
    const weightedResiduals = [];
    let rss = 0;
    for (let i = 0; i < n; i++) {
        const transformed = [];
        let h = 0;
        for (let k = 0; k < rank; k++) {
            let total = 0;
            for (let m = 0; m < rank; m++) total += weighted[i][accepted[m]] * inverse[m][k];
            transformed.push(total);
            h += total * total;
        }
        const gradient = [];
        for (let k = 0; k < rank; k++) {
            let total = 0;
            for (let m = 0; m < rank; m++) total += inverse[k][m] * transformed[m];
            gradient.push(total);
        }
        let prediction = 0;
        for (let k = 0; k < rank; k++) prediction += matrix[i][accepted[k]] * coefficients[accepted[k]];
        const residual = response[i] - prediction;
        const epsilon = roots[i] * residual;
        u.push(transformed);
        g.push(gradient);
        leverage.push(h);
        fitted.push(prediction);
        residuals.push(residual);
        weightedResiduals.push(epsilon);
        rss += epsilon * epsilon;
    }
    return { matrix, response, weights, n, p, rank, accepted, effects, coefficients, inverse, variance,
        u, g, leverage, fitted, residuals, weightedResiduals, rss };
}

module.exports = { fit };
