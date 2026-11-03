'use strict';

function majority(counts) {
    let selected = 0;
    for (let index = 1; index < counts.length; index++) {
        if (counts[index] > counts[selected]) selected = index;
    }
    return selected;
}

function statistics(rows, classCount) {
    const counts = Array(classCount).fill(0);
    for (const row of rows) counts[row.label]++;
    let sumSquares = 0;
    for (const count of counts) sumSquares += count * count;
    const predicted = majority(counts);
    return {
        n: rows.length,
        counts,
        sumSquares,
        majority: predicted,
        error: rows.length - counts[predicted],
    };
}

function evaluationValue(left, right) {
    return {
        numerator: left.sumSquares * right.n + right.sumSquares * left.n,
        denominator: left.n * right.n,
    };
}

function compareFractions(left, right) {
    // The task bounds every cross product below 2^53, so these integers are exact.
    const a = left.numerator * right.denominator;
    const b = right.numerator * left.denominator;
    return a < b ? -1 : a > b ? 1 : 0;
}

function improves(value, stats) {
    return value.numerator * stats.n > stats.sumSquares * value.denominator;
}

function impurityDecrease(node) {
    const left = node.left.sumSquares / node.left.n;
    const right = node.right.sumSquares / node.right.n;
    const parent = node.sumSquares / node.n;
    return (left + right) - parent;
}

module.exports = {
    majority, statistics, evaluationValue, compareFractions, improves, impurityDecrease,
};
