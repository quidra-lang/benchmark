'use strict';

const { sum, mean } = require('./resampling');

function* choices(size, count) {
    const positions = Array.from({ length: count }, (_, index) => index);
    for (;;) {
        yield positions.slice();
        let index = count - 1;
        while (index >= 0 && positions[index] === size - count + index) index--;
        if (index < 0) return;
        positions[index]++;
        for (let next = index + 1; next < count; next++) positions[next] = positions[next - 1] + 1;
    }
}

function reduced(numerator, denominator) {
    let first = numerator;
    let second = denominator;
    while (second !== 0) [first, second] = [second, first % second];
    return [numerator / first, denominator / first];
}

function contrast(x, y) {
    return y.length * sum(x) - x.length * sum(y);
}

function doubledRanks(values) {
    const order = values.map((value, index) => ({ value, index })).sort((a, b) => a.value - b.value);
    const ranks = Array(values.length);
    let start = 0;
    while (start < order.length) {
        let end = start + 1;
        while (end < order.length && order[end].value === order[start].value) end++;
        const rank = 2 * start + (end - start) + 1;
        for (let index = start; index < end; index++) ranks[order[index].index] = rank;
        start = end;
    }
    return ranks;
}

function tieCounts(values) {
    const counts = new Map();
    for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
    let groups = 0;
    let correction = 0;
    for (const count of counts.values()) {
        if (count < 2) continue;
        groups++;
        correction += count * count * count - count;
    }
    return { groups, correction };
}

function divide(values, sizes) {
    let start = 0;
    return sizes.map(size => {
        const part = values.slice(start, start + size);
        start += size;
        return part;
    });
}

function anova(samples) {
    const sizes = samples.map(sample => sample.length);
    const count = sum(sizes);
    const grand = sum(samples.map(sum)) / (100 * count);
    const means = samples.map(mean);
    let ssb = 0;
    let ssw = 0;
    for (let group = 0; group < samples.length; group++) {
        const difference = means[group] - grand;
        ssb += sizes[group] * (difference * difference);
        let within = 0;
        for (const value of samples[group]) {
            const residual = value / 100 - means[group];
            within += residual * residual;
        }
        ssw += within;
    }
    return { count, means, ssb, ssw, f: ssb / (samples.length - 1) / (ssw / (count - samples.length)) };
}

function kruskal(rankGroups, correction) {
    let total = 0;
    let count = 0;
    for (const ranks of rankGroups) {
        const rankSum = sum(ranks);
        total += (rankSum * rankSum) / (4 * ranks.length);
        count += ranks.length;
    }
    return (12 * total / (count * (count + 1)) - 3 * (count + 1)) / correction;
}

module.exports = { choices, reduced, contrast, doubledRanks, tieCounts, divide, anova, kruskal };
