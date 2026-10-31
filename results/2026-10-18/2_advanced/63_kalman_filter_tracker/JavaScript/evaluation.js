'use strict';

const { minimumMatching } = require('./association');

function distance(first, second) {
    const x = first[0] - second[0], y = first[1] - second[1];
    return Math.sqrt(x * x + y * y);
}

function ospa(first, second, cutoff) {
    if (first.length === 0 && second.length === 0) return 0;
    if (first.length === 0 || second.length === 0) return cutoff;
    const [small, large] = first.length <= second.length ? [first, second] : [second, first];
    const costs = small.map(point => large.map(other => {
        const d = Math.min(cutoff, distance(point, other));
        return d * d;
    }));
    const pairs = minimumMatching(costs);
    let total = costs[pairs[0][0]][pairs[0][1]];
    for (let i = 1; i < pairs.length; i++) total += costs[pairs[i][0]][pairs[i][1]];
    return Math.sqrt((total + cutoff * cutoff * (large.length - small.length)) / large.length);
}

function continuity(labels) {
    let covered = 0, groups = 0, swaps = 0, delay = null, previousLabel = null, previousCovered = false;
    for (let i = 0; i < labels.length; i++) {
        const label = labels[i];
        if (label === null) {
            previousCovered = false;
            continue;
        }
        if (delay === null) delay = i;
        covered++;
        if (!previousCovered) groups++;
        if (previousLabel !== null && previousLabel !== label) swaps++;
        previousLabel = label;
        previousCovered = true;
    }
    return { covered, breaks: Math.max(0, groups - 1), swaps, delay };
}

function fixed(value) {
    let result;
    if (Math.abs(value) < 1e21) result = value.toFixed(4);
    else result = (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + '.0000';
    return result === '-0.0000' ? '0.0000' : result;
}

module.exports = { distance, ospa, continuity, fixed };
