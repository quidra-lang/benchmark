'use strict';

function real(value, decimals = 4) {
    if (value === null) return '-';
    if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.' + '0'.repeat(decimals);
    const text = value.toFixed(decimals);
    return Number(text) === 0 ? (0).toFixed(decimals) : text;
}

function ratio(numerator, denominator) {
    const a = BigInt(numerator);
    const b = BigInt(denominator);
    if (b === 0n) return '-';
    const rounded = (20000n * a + b) / (2n * b);
    return (rounded / 10000n).toString() + '.' + (rounded % 10000n).toString().padStart(4, '0');
}

function fraction(value) {
    const numerator = BigInt(value[0]);
    const denominator = BigInt(value[1]);
    let a = numerator;
    let b = denominator;
    while (b !== 0n) [a, b] = [b, a % b];
    return (numerator / a).toString() + '/' + (denominator / a).toString() + ' ' + ratio(numerator, denominator);
}

function compareFractions(first, second) {
    const difference = BigInt(first[0]) * BigInt(second[1]) - BigInt(second[0]) * BigInt(first[1]);
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
}

function confusion(probabilities, targets, threshold) {
    const result = { tp: 0, fp: 0, tn: 0, fn: 0, correct: 0, predictions: [] };
    for (let row = 0; row < probabilities.length; row++) {
        const predicted = Number(probabilities[row] >= threshold);
        result.predictions.push(predicted);
        if (predicted === targets[row]) result.correct++;
        if (predicted === 1) result[targets[row] === 1 ? 'tp' : 'fp']++;
        else result[targets[row] === 1 ? 'fn' : 'tn']++;
    }
    return result;
}

function auc(scores, targets) {
    const order = scores.map((_, index) => index).sort((a, b) => scores[a] - scores[b] || a - b);
    let positives = 0;
    let ranks = 0;
    for (let start = 0; start < order.length;) {
        let end = start + 1;
        while (end < order.length && scores[order[end]] === scores[order[start]]) end++;
        const doubledRank = start + 1 + end;
        for (let position = start; position < end; position++) {
            if (targets[order[position]] === 1) {
                positives++;
                ranks += doubledRank;
            }
        }
        start = end;
    }
    return [ranks - positives * (positives + 1), 2 * positives * (scores.length - positives)];
}

function rocPoints(probabilities, targets) {
    const order = probabilities.map((_, index) => index).sort((a, b) => probabilities[b] - probabilities[a] || a - b);
    const points = [];
    let tp = 0;
    let fp = 0;
    for (let start = 0; start < order.length;) {
        let end = start + 1;
        while (end < order.length && probabilities[order[end]] === probabilities[order[start]]) end++;
        for (let position = start; position < end; position++) {
            if (targets[order[position]] === 1) tp++;
            else fp++;
        }
        points.push({ threshold: probabilities[order[start]], tp, fp });
        start = end;
    }
    return points;
}

module.exports = { real, ratio, fraction, compareFractions, confusion, auc, rocPoints };
