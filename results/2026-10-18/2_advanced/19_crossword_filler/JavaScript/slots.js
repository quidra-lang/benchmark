'use strict';

const { isWhite } = require('./grid');

function runs(rows) {
    const result = [];
    const h = rows.length;
    const w = rows[0].length;
    for (let r = 0; r < h; r++) {
        for (let c = 0; c < w; c++) {
            if (!isWhite(rows[r][c])) continue;
            for (const axis of ['A', 'D']) {
                const dr = axis === 'D' ? 1 : 0;
                const dc = axis === 'A' ? 1 : 0;
                if (r - dr >= 0 && c - dc >= 0 && isWhite(rows[r - dr][c - dc])) continue;
                const cells = [];
                let rr = r;
                let cc = c;
                while (rr < h && cc < w && isWhite(rows[rr][cc])) {
                    cells.push(rr * w + cc);
                    rr += dr;
                    cc += dc;
                }
                result.push({ r, c, axis, cells, length: cells.length });
            }
        }
    }
    return result;
}

function shortRun(allRuns) {
    return allRuns.find(run => run.length === 2) ?? null;
}

function extractSlots(rows, allRuns) {
    const numbers = Array(rows.length * rows[0].length).fill(0);
    const membership = numbers.map(() => []);
    const slots = [];
    let number = 0;
    for (const run of allRuns) {
        if (run.length < 3) continue;
        const first = run.cells[0];
        if (numbers[first] === 0) numbers[first] = ++number;
        const slot = { ...run, number: numbers[first], label: numbers[first] + run.axis, index: slots.length };
        slots.push(slot);
        for (const cell of slot.cells) membership[cell].push(slot.index);
    }
    for (const slot of slots) {
        const crossing = new Set();
        for (const cell of slot.cells) {
            for (const index of membership[cell]) if (index !== slot.index) crossing.add(index);
        }
        slot.crossing = [...crossing].sort((a, b) => a - b);
    }
    return { slots, numbers, membership };
}

module.exports = { runs, shortRun, extractSlots };
