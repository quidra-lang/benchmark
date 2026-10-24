'use strict';

const pairKey = (first, second) => first + '\0' + second;
const count = (counts, first, second) => counts.get(pairKey(first, second)) || 0;

function countFollows(log) {
    const counts = new Map();
    for (const {trace, weight} of log) {
        for (let i = 1; i < trace.length; i++) {
            const key = pairKey(trace[i - 1], trace[i]);
            counts.set(key, (counts.get(key) || 0) + weight);
        }
    }
    return counts;
}

function basicRelation(counts, first, second) {
    const forward = count(counts, first, second) > 0;
    const reverse = count(counts, second, first) > 0;
    if (forward) return reverse ? '||' : '->';
    return reverse ? '<-' : '#';
}

function table(rows, width) {
    const numbers = rows.map((_, i) => String(i + 1).padStart(width));
    const lines = ['    ' + numbers.join('')];
    rows.forEach((row, i) => lines.push(String(i + 1).padStart(4)
        + row.map(value => String(value).padStart(width)).join('')));
    return lines;
}

function footprint(activities, relation) {
    const lines = activities.map((activity, i) => `ACTIVITY ${i + 1} ${activity}`);
    const cells = activities.map(first => activities.map(second => relation(first, second)));
    for (const line of table(cells, 4)) lines.push(line);
    return lines;
}

module.exports = {pairKey, count, countFollows, basicRelation, table, footprint};
