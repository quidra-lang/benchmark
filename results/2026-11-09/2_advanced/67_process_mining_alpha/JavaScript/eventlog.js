'use strict';

const fs = require('node:fs');
const MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

function readInputs() {
    const rows = fs.readFileSync('input/eventlog.csv', 'ascii').slice(0, -1).split('\n').slice(1);
    const events = rows.map((text, i) => {
        const [caseId, activity, timestamp, resource] = text.split(',');
        return {caseId, activity, timestamp, resource, line: i + 2};
    });
    const parameters = fs.readFileSync('input/params.txt', 'ascii').slice(0, -1).split('\n')
        .map(line => line.split(' '));
    return {rows: events, parameters: new Map(parameters)};
}

function timestampMinutes(timestamp) {
    const month = Number(timestamp.slice(5, 7));
    const day = Number(timestamp.slice(8, 10));
    const hour = Number(timestamp.slice(11, 13));
    const minute = Number(timestamp.slice(14, 16));
    if (month < 1 || month > 12 || day < 1 || day > MONTH_LENGTHS[month - 1]
        || hour > 23 || minute > 59) return null;
    let days = 0;
    for (let i = 0; i < month - 1; i++) days += MONTH_LENGTHS[i];
    return ((days + day - 1) * 24 + hour) * 60 + minute;
}

function buildCases(events) {
    const grouped = new Map();
    for (const event of events) {
        if (!grouped.has(event.caseId)) grouped.set(event.caseId, []);
        grouped.get(event.caseId).push(event);
    }
    return [...grouped.keys()].sort().map(id => {
        const ordered = grouped.get(id).sort((a, b) => a.time - b.time || a.line - b.line);
        return {id, events: ordered, trace: ordered.map(event => event.activity),
            duration: ordered.at(-1).time - ordered[0].time};
    });
}

function median(values) {
    const sorted = values.toSorted((a, b) => a - b);
    const middle = sorted.length >> 1;
    return sorted.length % 2 === 1 ? [BigInt(sorted[middle]), 1n]
        : [BigInt(sorted[middle - 1]) + BigInt(sorted[middle]), 2n];
}

const quotient = (numerator, denominator) => Number(BigInt(numerator) / BigInt(denominator));

module.exports = {readInputs, timestampMinutes, buildCases, median, quotient};
