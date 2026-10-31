'use strict';

const board = require('./board');
const RACK_SIZE = 7;
const BINGO = 50;
const tileKind = letter => letter >= 'a' && letter <= 'z' ? '?' : letter;

function squares(move) {
    return Array.from(move.word, (letter, i) => ({
        row: move.row + (move.direction === 'down' ? i : 0),
        column: move.column + (move.direction === 'across' ? i : 0), letter,
    }));
}

function crossWord(grid, tile, direction) {
    const dr = direction === 'down' ? 1 : 0;
    const dc = direction === 'across' ? 1 : 0;
    let row = tile.row;
    let column = tile.column;
    while (board.occupied(grid, row - dr, column - dc)) { row -= dr; column -= dc; }
    const start = { row, column, direction };
    let word = '';
    while (board.inside(row, column) && ((row === tile.row && column === tile.column) || board.occupied(grid, row, column))) {
        word += row === tile.row && column === tile.column ? tile.letter : grid[row][column];
        row += dr;
        column += dc;
    }
    return { ...start, word };
}

function wordScore(grid, word, table) {
    let total = 0;
    let multiplier = 1;
    for (const tile of squares(word)) {
        let points = table.get(tileKind(tile.letter)).value;
        if (grid[tile.row][tile.column] === '.') {
            const premium = board.PREMIUMS[tile.row][tile.column];
            if (premium === '+') points *= 2;
            if (premium === '^') points *= 3;
            if (premium === '*') multiplier *= 2;
            if (premium === '#') multiplier *= 3;
        }
        total += points;
    }
    return total * multiplier;
}

function score(grid, move, table) {
    const tiles = squares(move).filter(tile => grid[tile.row][tile.column] === '.');
    const words = [{ row: move.row, column: move.column, direction: move.direction, word: move.word }];
    const perpendicular = move.direction === 'across' ? 'down' : 'across';
    for (const tile of tiles) {
        const cross = crossWord(grid, tile, perpendicular);
        if (cross.word.length >= 2) words.push(cross);
    }
    let total = tiles.length === RACK_SIZE ? BINGO : 0;
    for (const word of words) {
        word.score = wordScore(grid, word, table);
        total += word.score;
    }
    return { ...move, tiles, words, score: total };
}

module.exports = { RACK_SIZE, BINGO, tileKind, squares, crossWord, wordScore, score };
