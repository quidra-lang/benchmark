'use strict';

function fraction(numerator, denominator) {
    if (denominator === 0) return '-';
    let a = Math.abs(numerator);
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return `${numerator / a}/${denominator / a}`;
}

function confusion(size) {
    return Array.from({ length: size }, () => Array(size).fill(0));
}

function accumulate(matrix, truth, prediction) {
    let correct = 0;
    for (let t = 0; t < truth.length; t++) {
        matrix[truth[t]][prediction[t]]++;
        if (truth[t] === prediction[t]) correct++;
    }
    return correct;
}

function confusionLines(matrix, states) {
    let width = 1;
    for (const row of matrix) {
        for (const value of row) width = Math.max(width, String(value).length);
    }
    const lines = [' ' + states.map(state => ' ' + state.padStart(width)).join('')];
    for (let i = 0; i < states.length; i++) {
        lines.push(states[i] + matrix[i].map(value => ' ' + String(value).padStart(width)).join(''));
    }
    return lines;
}

function metricLines(matrix, states) {
    const rows = Array(states.length).fill(0);
    const columns = Array(states.length).fill(0);
    let total = 0;
    let correct = 0;
    for (let i = 0; i < states.length; i++) {
        correct += matrix[i][i];
        for (let j = 0; j < states.length; j++) {
            rows[i] += matrix[i][j];
            columns[j] += matrix[i][j];
            total += matrix[i][j];
        }
    }
    let chance = 0;
    for (let i = 0; i < states.length; i++) chance += rows[i] * columns[i];
    const lines = [`ACCURACY ${fraction(correct, total)}`,
        `KAPPA ${fraction(total * correct - chance, total * total - chance)}`];
    for (let i = 0; i < states.length; i++) {
        lines.push(`STATE ${states[i]} precision ${fraction(matrix[i][i], columns[i])}`
            + ` recall ${fraction(matrix[i][i], rows[i])}`
            + ` f1 ${fraction(2 * matrix[i][i], columns[i] + rows[i])}`);
    }
    return lines;
}

function runs(path) {
    const result = [];
    let start = 0;
    for (let end = 1; end <= path.length; end++) {
        if (end === path.length || path[end] !== path[start]) {
            result.push({ state: path[start], start, end: end - 1 });
            start = end;
        }
    }
    return result;
}

function overlaps(left, right) {
    return left.start <= right.end && right.start <= left.end;
}

function boundaries(path) {
    const result = [];
    for (let t = 1; t < path.length; t++) {
        if (path[t - 1] !== path[t]) result.push(t + 1);
    }
    return result;
}

function matchedBoundaries(source, target, tolerance) {
    let count = 0;
    for (const position of source) {
        if (target.some(other => Math.abs(position - other) <= tolerance)) count++;
    }
    return count;
}

module.exports = { fraction, confusion, accumulate, confusionLines, metricLines,
    runs, overlaps, boundaries, matchedBoundaries };
