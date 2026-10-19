'use strict';

const { FILLED } = require('./line_solver');

function runClue(line) {
    const blocks = [];
    let length = 0;
    for (const state of line) {
        if (state === FILLED) length++;
        else if (length > 0) {
            blocks.push(length);
            length = 0;
        }
    }
    if (length > 0) blocks.push(length);
    return blocks;
}

function spaceForm(clue) {
    return clue.length === 0 ? '0' : clue.join(' ');
}

function commaForm(clue) {
    return clue.length === 0 ? '0' : clue.join(',');
}

function parseClue(text) {
    if (text === '0') return [];
    if (!/^[1-9][0-9]?( [1-9][0-9]?)*$/.test(text)) return null;
    return text.split(' ').map(Number);
}

function minimumLength(clue) {
    if (clue.length === 0) return 0;
    let length = clue.length - 1;
    for (const block of clue) length += block;
    return length;
}

function fits(clue, length) {
    return minimumLength(clue) <= length;
}

module.exports = { runClue, spaceForm, commaForm, parseClue, minimumLength, fits };
