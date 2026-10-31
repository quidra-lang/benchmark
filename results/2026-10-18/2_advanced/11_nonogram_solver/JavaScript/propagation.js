'use strict';

const { UNKNOWN, solveLine } = require('./line_solver');

function getLine(grid, axis, index) {
    return axis === 'R' ? grid[index].slice() : grid.map(row => row[index]);
}

function determinedCount(grid) {
    let count = 0;
    for (const row of grid) {
        for (const state of row) if (state !== UNKNOWN) count++;
    }
    return count;
}

function propagate(grid, rows, columns, kind, rowMarks, columnMarks) {
    const markedRows = rowMarks === undefined ? rows.map(() => true) : rowMarks.slice();
    const markedColumns = columnMarks === undefined ? columns.map(() => true) : columnMarks.slice();
    const record = [];
    for (;;) {
        let axis = 'R';
        let index = markedRows.indexOf(true);
        if (index === -1) {
            axis = 'C';
            index = markedColumns.indexOf(true);
        }
        if (index === -1) return { grid, record, conflict: null };
        const marks = axis === 'R' ? markedRows : markedColumns;
        marks[index] = false;
        const label = axis + (index + 1);
        const line = getLine(grid, axis, index);
        const clue = axis === 'R' ? rows[index] : columns[index];
        const solved = solveLine(line, clue, kind);
        if (solved === null) {
            record.push({ label, gain: null });
            return { grid, record, conflict: { axis, index, label } };
        }
        record.push({ label, gain: solved.gain });
        for (let p = 0; p < line.length; p++) {
            if (line[p] !== UNKNOWN || solved.line[p] === UNKNOWN) continue;
            if (axis === 'R') {
                grid[index][p] = solved.line[p];
                markedColumns[p] = true;
            } else {
                grid[p][index] = solved.line[p];
                markedRows[p] = true;
            }
        }
    }
}

module.exports = { getLine, determinedCount, propagate };
