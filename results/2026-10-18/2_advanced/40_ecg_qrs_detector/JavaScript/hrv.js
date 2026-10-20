'use strict';

const { rdiv } = require('./report');
const sum = values => values.reduce((total, value) => total + value, 0);
const sumSquares = values => values.reduce((total, value) => total + value * value, 0);

function isqrt(value) {
    let low = 0;
    let high = 1;
    while (high * high <= value) high *= 2;
    while (low + 1 < high) {
        const middle = Math.floor((low + high) / 2);
        if (middle * middle <= value) low = middle;
        else high = middle;
    }
    return low;
}

const root = (numerator, denominator) => Math.floor((isqrt(Math.floor(40000 * numerator / denominator)) + 1) / 2);
const meanHeartRate = intervals => intervals.length ? rdiv(6000000 * intervals.length, sum(intervals)) : null;

function intervalStatistics(rr, nn, pairs) {
    const e = nn.length;
    const count = pairs.length;
    const differences = pairs.map(([a, b]) => b - a);
    const sums = pairs.map(([a, b]) => a + b);
    const nnNumerator = e * sumSquares(nn) - sum(nn) ** 2;
    const differenceNumerator = count * sumSquares(differences) - sum(differences) ** 2;
    const sumNumerator = count * sumSquares(sums) - sum(sums) ** 2;
    const nn50 = differences.filter(value => Math.abs(value) > 50).length;
    return { meanRR: rr.length ? rdiv(100 * sum(rr), rr.length) : null, meanHR: meanHeartRate(rr),
        meanNN: e ? rdiv(100 * sum(nn), e) : null, sdnn: e >= 2 ? root(nnNumerator, e * (e - 1)) : null,
        rmssd: count ? root(sumSquares(differences), count) : null,
        sdsd: count >= 2 ? root(differenceNumerator, count * (count - 1)) : null, nn50,
        pnn50: count ? rdiv(10000 * nn50, count) : null,
        sd1: count >= 2 ? root(differenceNumerator, 2 * count * (count - 1)) : null,
        sd2: count >= 2 ? root(sumNumerator, 2 * count * (count - 1)) : null };
}

function histogram(intervals) {
    const bins = new Map();
    for (const interval of intervals) {
        const bin = Math.floor(16 * interval / 125);
        bins.set(bin, (bins.get(bin) ?? 0) + 1);
    }
    return [...bins].sort((a, b) => a[0] - b[0]);
}

function ranges(values, predicate) {
    const result = [];
    let start = null;
    for (let i = 0; i <= values.length; i++) {
        if (i < values.length && predicate(values[i], i)) { if (start === null) start = i; }
        else if (start !== null) { result.push([start, i - 1]); start = null; }
    }
    return result;
}

module.exports = { sum, root, meanHeartRate, intervalStatistics, histogram, ranges };
