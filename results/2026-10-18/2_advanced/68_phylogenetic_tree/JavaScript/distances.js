'use strict';

const { LETTERS } = require('./alignment');

function countPair(first, second, weights) {
    let n = 0;
    let s = 0;
    let v = 0;
    for (let c = 0; c < weights.length; c++) {
        const a = LETTERS.indexOf(first[c]);
        const b = LETTERS.indexOf(second[c]);
        if (a < 0 || b < 0) continue;
        n += weights[c];
        if (a === b) continue;
        if ((a === 0 && b === 2) || (a === 2 && b === 0) ||
            (a === 1 && b === 3) || (a === 3 && b === 1)) s += weights[c];
        else v += weights[c];
    }
    return { n, s, v };
}

function tallyPairs(taxa, weights) {
    const pairs = [];
    for (let i = 0; i < taxa.length; i++) {
        for (let j = i + 1; j < taxa.length; j++) {
            pairs.push({ i, j, ...countPair(taxa[i].sequence, taxa[j].sequence, weights) });
        }
    }
    return pairs;
}

function distance(model, pair, saturation) {
    const { n, s, v } = pair;
    const saturated = n === 0 || (model === 'JC' && 4 * (s + v) >= 3 * n) ||
        (model === 'K2P' && (2 * s + v >= n || 2 * v >= n));
    if (saturated) return { value: saturation, saturated: true };
    let value;
    if (model === 'P') value = (s + v) / n;
    else if (model === 'JC') value = -(3 / 4) * Math.log(1 - (4 * (s + v)) / (3 * n));
    else value = -(1 / 2) * Math.log(1 - (2 * s) / n - v / n) -
        (1 / 4) * Math.log(1 - (2 * v) / n);
    return { value, saturated: false };
}

function buildMatrix(count, pairs, model, saturation) {
    const matrix = Array.from({ length: count }, () => Array(count).fill(0));
    const saturated = [];
    for (const pair of pairs) {
        const result = distance(model, pair, saturation);
        matrix[pair.i][pair.j] = matrix[pair.j][pair.i] = result.value;
        if (result.saturated) saturated.push(pair);
    }
    return { matrix, saturated };
}

module.exports = { countPair, tallyPairs, distance, buildMatrix };
