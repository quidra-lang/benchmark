'use strict';

const {pairKey, count} = require('./dfg');

function compareSequences(first, second) {
    for (let i = 0; i < Math.min(first.length, second.length); i++) {
        if (first[i] !== second[i]) return first[i] < second[i] ? -1 : 1;
    }
    return first.length - second.length;
}

const comparePairs = (first, second) => compareSequences(first.A, second.A) || compareSequences(first.B, second.B);

function extendPair(pair, activity, side, relation) {
    const own = pair[side];
    if (own.includes(activity) || relation(activity, activity) !== '#') return null;
    if (own.some(other => relation(activity, other) !== '#')) return null;
    if (side === 'A' && pair.B.some(other => relation(activity, other) !== '->')) return null;
    if (side === 'B' && pair.A.some(other => relation(other, activity) !== '->')) return null;
    return {A: side === 'A' ? [...pair.A, activity].sort() : pair.A,
        B: side === 'B' ? [...pair.B, activity].sort() : pair.B};
}

function triangleCounts(log) {
    const triangles = new Map();
    for (const {trace, weight} of log) {
        for (let i = 0; i + 2 < trace.length; i++) {
            if (trace[i] !== trace[i + 1] && trace[i] === trace[i + 2]) {
                const key = pairKey(trace[i], trace[i + 1]);
                triangles.set(key, (triangles.get(key) || 0) + weight);
            }
        }
    }
    return triangles;
}

function alphaPlusRelation(counts, triangles) {
    const causal = (first, second) => count(counts, first, second) > 0
        && (count(counts, second, first) === 0 || (first !== second
            && count(triangles, first, second) > 0 && count(triangles, second, first) > 0));
    return (first, second) => {
        if (causal(first, second)) return '->';
        if (causal(second, first)) return '<-';
        return count(counts, first, second) > 0 && count(counts, second, first) > 0 ? '||' : '#';
    };
}

module.exports = {compareSequences, comparePairs, extendPair, triangleCounts, alphaPlusRelation};
