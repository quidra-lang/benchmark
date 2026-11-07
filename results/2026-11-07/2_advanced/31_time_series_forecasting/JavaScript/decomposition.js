'use strict';

function sum(values) {
    let total = 0;
    for (const value of values) total += value;
    return total;
}

const mean = values => sum(values) / values.length;

function sampleVariance(values) {
    const average = mean(values);
    let total = 0;
    for (const value of values) { const difference = value - average; total += difference * difference; }
    return total / (values.length - 1);
}

function decompose(values, season) {
    const half = season / 2;
    const trend = Array(values.length).fill(null);
    const defined = [];
    const add = Array(season).fill(0);
    const mult = Array(season).fill(0);
    const counts = Array(season).fill(0);
    for (let t = half; t < values.length - half; t++) {
        let total = 0.5 * values[t - half];
        for (let i = t - half + 1; i < t + half; i++) total += values[i];
        total += 0.5 * values[t + half];
        trend[t] = total / season;
        defined.push(t);
        add[t % season] += values[t] - trend[t];
        mult[t % season] += values[t] / trend[t];
        counts[t % season]++;
    }
    for (let j = 0; j < season; j++) { add[j] /= counts[j]; mult[j] /= counts[j]; }
    const addMean = mean(add);
    const multMean = mean(mult);
    for (let j = 0; j < season; j++) { add[j] -= addMean; mult[j] /= multMean; }
    const residualAdd = Array(values.length).fill(null);
    const residualMult = Array(values.length).fill(null);
    for (const t of defined) {
        residualAdd[t] = values[t] - trend[t] - add[t % season];
        residualMult[t] = values[t] / (trend[t] * mult[t % season]);
    }
    return { trend, defined, add, mult, residualAdd, residualMult };
}

function regression(values) {
    const center = (values.length + 1) / 2;
    const average = mean(values);
    let numerator = 0;
    let denominator = 0;
    for (let t = 0; t < values.length; t++) {
        const difference = t + 1 - center;
        numerator += difference * (values[t] - average);
        denominator += difference * difference;
    }
    const slope = numerator / denominator;
    return { intercept: average - slope * center, slope };
}

module.exports = { sum, mean, sampleVariance, decompose, regression };
