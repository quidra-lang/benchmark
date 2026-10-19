'use strict';

const { UNKNOWN, FILLED } = require('./line_solver');
const { spaceForm } = require('./clues');

function stateChar(state) {
    return state === UNKNOWN ? '?' : state === FILLED ? '#' : '.';
}

function stateString(line) {
    return line.map(stateChar).join('');
}

function sideBySide(grids) {
    if (grids.length === 0) return [];
    const lines = ['grid ' + grids.map(item => item.name).join(' ')];
    for (let r = 0; r < grids[0].grid.length; r++) {
        lines.push(grids.map(item => stateString(item.grid[r])).join(' | '));
    }
    return lines;
}

function answerSheet(grid, rows, columns) {
    const tokens = columns.map(clue => spaceForm(clue).split(' '));
    const rowText = rows.map(spaceForm);
    let width = 0;
    let depth = 0;
    let prefix = 0;
    for (const column of tokens) {
        depth = Math.max(depth, column.length);
        for (const token of column) width = Math.max(width, token.length + 1);
    }
    for (const text of rowText) prefix = Math.max(prefix, text.length);
    const lines = [];
    for (let t = 0; t < depth; t++) {
        let line = ' '.repeat(prefix);
        for (const column of tokens) {
            const index = t - (depth - column.length);
            line += index < 0 ? ' '.repeat(width) : column[index].padStart(width, ' ');
        }
        lines.push(line.replace(/ +$/, ''));
    }
    for (let r = 0; r < grid.length; r++) {
        let line = rowText[r].padStart(prefix, ' ');
        for (const cell of grid[r]) line += ' '.repeat(width - 1) + stateChar(cell);
        lines.push(line);
    }
    return lines;
}

module.exports = { stateChar, stateString, sideBySide, answerSheet };
