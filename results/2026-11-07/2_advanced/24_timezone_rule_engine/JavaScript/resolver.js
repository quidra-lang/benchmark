'use strict';

function periodIndex(periods, time) {
    let low = 0;
    let high = periods.length;
    while (low + 1 < high) {
        const middle = Math.floor((low + high) / 2);
        if (periods[middle].start <= time) low = middle;
        else high = middle;
    }
    return low;
}

function periodRange(periods, index) {
    return { start: periods[index].start, end: index + 1 < periods.length ? periods[index + 1].start : Infinity };
}

function resolveLocal(zone, local) {
    const candidates = [];
    for (let index = 0; index < zone.periods.length; index++) {
        const period = zone.periods[index];
        const time = local - period.offset;
        const range = periodRange(zone.periods, index);
        if (time >= range.start && time < range.end) candidates.push({ time, period });
    }
    candidates.sort((a, b) => a.time - b.time);
    const gap = candidates.length === 0 ? zone.transitions.find(change =>
        change.time + change.before.offset <= local && local < change.time + change.after.offset) : null;
    return { candidates, gap };
}

module.exports = { periodIndex, periodRange, resolveLocal };
