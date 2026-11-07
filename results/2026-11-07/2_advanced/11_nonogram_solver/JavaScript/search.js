'use strict';

const { UNKNOWN, FILLED, EMPTY } = require('./line_solver');
const { propagate, determinedCount } = require('./propagation');

function chooseCell(grid) {
    const h = grid.length;
    const w = grid[0].length;
    const rowUnknown = Array(h).fill(0);
    const columnUnknown = Array(w).fill(0);
    for (let r = 0; r < h; r++) {
        for (let c = 0; c < w; c++) {
            if (grid[r][c] !== UNKNOWN) continue;
            rowUnknown[r]++;
            columnUnknown[c]++;
        }
    }
    let best = h + w + 1;
    let chosen = null;
    for (let r = 0; r < h; r++) {
        for (let c = 0; c < w; c++) {
            if (grid[r][c] === UNKNOWN && rowUnknown[r] + columnUnknown[c] < best) {
                best = rowUnknown[r] + columnUnknown[c];
                chosen = { r, c };
            }
        }
    }
    return chosen;
}

function search(grid, rows, columns) {
    const result = {
        guesses: 0, maxDepth: 0, backtracks: 0, lineSolves: 0,
        record: [], solutions: [],
    };
    function visit(parent, depth) {
        const { r, c } = chooseCell(parent);
        for (const value of [FILLED, EMPTY]) {
            const number = ++result.guesses;
            result.maxDepth = Math.max(result.maxDepth, depth);
            const child = parent.map(row => row.slice());
            child[r][c] = value;
            const rowMarks = rows.map(() => false);
            const columnMarks = columns.map(() => false);
            rowMarks[r] = true;
            columnMarks[c] = true;
            const propagation = propagate(child, rows, columns, 'precise', rowMarks, columnMarks);
            const known = determinedCount(child);
            const solves = propagation.record.length;
            result.lineSolves += solves;
            let outcome;
            if (propagation.conflict !== null) {
                outcome = 'contradiction at=' + propagation.conflict.label;
                result.backtracks++;
            } else if (known === rows.length * columns.length) {
                result.solutions.push(child);
                outcome = 'solution' + result.solutions.length;
            } else {
                outcome = 'open';
            }
            result.record.push({ number, depth, r, c, value, solves, known, outcome });
            if (result.solutions.length === 2) return true;
            if (outcome === 'open' && visit(child, depth + 1)) return true;
        }
        return false;
    }
    visit(grid, 1);
    return result;
}

module.exports = { chooseCell, search };
