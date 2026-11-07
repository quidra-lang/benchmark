'use strict';

const {count} = require('./dfg');

function dependency(counts, first, second) {
    const forward = count(counts, first, second);
    const reverse = count(counts, second, first);
    return [BigInt(forward - reverse), BigInt(forward + reverse + 1)];
}

const loopMeasure = observations => [BigInt(observations), BigInt(observations + 1)];

function routingMeasure(counts, activity, first, second, split) {
    const numerator = count(counts, first, second) + count(counts, second, first);
    const denominator = split ? count(counts, activity, first) + count(counts, activity, second) + 1
        : count(counts, first, activity) + count(counts, second, activity) + 1;
    return [BigInt(numerator), BigInt(denominator)];
}

function compareFractions(first, second) {
    const difference = first[0] * second[1] - second[0] * first[1];
    return difference < 0n ? -1 : difference > 0n ? 1 : 0;
}

function subtractFractions(first, second) {
    return [first[0] * second[1] - second[0] * first[1], first[1] * second[1]];
}

module.exports = {dependency, loopMeasure, routingMeasure, compareFractions, subtractFractions};
