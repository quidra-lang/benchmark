'use strict';

const samplesPerTick = (rate, tempo) => Math.floor(rate * 5 / (tempo * 2));

function nextRow(song, position, row) {
    const cells = song.patterns.get(song.order[position])[row];
    let jump = null;
    let breakRow = null;
    let stop = false;
    for (const { effect } of cells) {
        if (effect?.name === 'F' && effect.argument === 0) stop = true;
        if (effect?.name === 'B') jump = effect.argument;
        if (effect?.name === 'D') breakRow = effect.argument >= 64 ? 0 : effect.argument;
    }
    if (stop) return { reason: 'stop', position, row };
    let nextPosition;
    let next;
    if (jump !== null || breakRow !== null) { nextPosition = jump ?? position + 1; next = breakRow ?? 0; }
    else { nextPosition = row === 63 ? position + 1 : position; next = row === 63 ? 0 : row + 1; }
    return nextPosition >= song.order.length ? { reason: 'finished' } : { position: nextPosition, row: next };
}

function reachableRows(song) {
    const reachable = new Set();
    let current = { position: 0, row: 0 };
    while (!current.reason) {
        const key = current.position + ',' + current.row;
        if (reachable.has(key)) break;
        reachable.add(key);
        current = nextRow(song, current.position, current.row);
    }
    return reachable;
}

module.exports = { samplesPerTick, nextRow, reachableRows };
