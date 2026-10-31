'use strict';

function advance(process, sendingEvent = null) {
    if (sendingEvent !== null) {
        process.L = Math.max(process.L, sendingEvent.L);
        for (let i = 0; i < process.V.length; i++) process.V[i] = Math.max(process.V[i], sendingEvent.V[i]);
    }
    process.L++;
    process.V[process.index]++;
}

function lessEqual(left, right) {
    return left.every((value, i) => value <= right[i]);
}

function relation(left, right) {
    const equal = left.every((value, i) => value === right[i]);
    if (!equal && lessEqual(left, right)) return '->';
    if (!equal && lessEqual(right, left)) return '<-';
    return '||';
}

function deliverable(copy, counters) {
    const source = copy.source;
    return copy.message.stamp.every((value, i) =>
        i === source ? value === counters[i] + 1 : value <= counters[i]);
}

function missingProcesses(copy, counters) {
    const missing = [];
    for (let i = 0; i < counters.length; i++) {
        if (copy.message.stamp[i] > counters[i] + (i === copy.source ? 1 : 0)) missing.push(i);
    }
    return missing;
}

const vector = values => values.join(',');

module.exports = { advance, lessEqual, relation, deliverable, missingProcesses, vector };
