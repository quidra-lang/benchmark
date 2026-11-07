'use strict';

const { floorRatio } = require('./report');

function histogram(image) {
    const counts = Array(image.maxval + 1).fill(0);
    for (const value of image.pixels) counts[value]++;
    const cumulativeCounts = [];
    const cumulativeSums = [];
    let count = 0;
    let sum = 0;
    let minimum = null;
    let maximum = 0;
    let median = null;
    let mode = 0;
    let levels = 0;
    for (let value = 0; value <= image.maxval; value++) {
        count += counts[value];
        sum += value * counts[value];
        cumulativeCounts.push(count);
        cumulativeSums.push(sum);
        if (counts[value] > 0) {
            if (minimum === null) minimum = value;
            maximum = value;
            levels++;
        }
        if (median === null && 2 * count >= image.pixels.length) median = value;
        if (counts[value] > counts[mode]) mode = value;
    }
    const binWidth = floorRatio(image.maxval + 8, 8);
    const bins = [];
    for (let first = 0; first <= image.maxval; first += binWidth) {
        let frequency = 0;
        for (let value = first; value < first + binWidth && value <= image.maxval; value++) {
            frequency += counts[value];
        }
        bins.push(frequency);
    }
    return { counts, cumulativeCounts, cumulativeSums, count, sum, minimum, maximum, median, mode, levels, binWidth, bins };
}

function compareScores(first, second) {
    if (first.quotient !== second.quotient) return first.quotient < second.quotient ? -1 : 1;
    const left = first.remainder * second.denominator;
    const right = second.remainder * first.denominator;
    return left < right ? -1 : left > right ? 1 : 0;
}

function otsu(stats) {
    const candidates = [];
    for (let threshold = 0; threshold + 1 < stats.counts.length; threshold++) {
        const below = stats.cumulativeCounts[threshold];
        const above = stats.count - below;
        if (stats.counts[threshold] === 0 || above === 0) continue;
        const sumBelow = stats.cumulativeSums[threshold];
        const sumAbove = stats.sum - sumBelow;
        const numerator = sumBelow * sumBelow * above + sumAbove * sumAbove * below;
        const denominator = below * above;
        const quotient = floorRatio(numerator, denominator);
        const remainder = numerator - quotient * denominator;
        candidates.push({ threshold, below, above, sumBelow, sumAbove, denominator, quotient, remainder });
    }
    candidates.sort((a, b) => -compareScores(a, b) || a.threshold - b.threshold);
    if (candidates.length === 0) return { threshold: stats.minimum, upper: stats.minimum, candidates };
    const threshold = candidates[0].threshold;
    let next = threshold + 1;
    while (stats.counts[next] === 0) next++;
    return { threshold, upper: next - 1, candidates };
}

function isodata(stats) {
    let threshold = floorRatio(stats.sum, stats.count);
    let iterations = 0;
    while (true) {
        const below = stats.cumulativeCounts[threshold];
        const above = stats.count - below;
        if (below === 0 || above === 0) break;
        const sumBelow = stats.cumulativeSums[threshold];
        const sumAbove = stats.sum - sumBelow;
        const next = floorRatio(sumBelow * above + sumAbove * below, 2 * below * above);
        iterations++;
        if (next === threshold) break;
        threshold = next;
        if (iterations === 100) break;
    }
    return { threshold, iterations };
}

module.exports = { histogram, compareScores, otsu, isodata };
