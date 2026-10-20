'use strict';

const SIZE = 15;
const CENTER = 7;
const PREMIUMS = [
    '# . . + . . . # . . . + . . #',
    '. * . . . ^ . . . ^ . . . * .',
    '. . * . . . + . + . . . * . .',
    '+ . . * . . . + . . . * . . +',
    '. . . . * . . . . . * . . . .',
    '. ^ . . . ^ . . . ^ . . . ^ .',
    '. . + . . . + . + . . . + . .',
    '# . . + . . . * . . . + . . #',
    '. . + . . . + . + . . . + . .',
    '. ^ . . . ^ . . . ^ . . . ^ .',
    '. . . . * . . . . . * . . . .',
    '+ . . * . . . + . . . * . . +',
    '. . * . . . + . + . . . * . .',
    '. * . . . ^ . . . ^ . . . * .',
    '# . . + . . . # . . . + . . #',
].map(line => line.split(' '));

const inside = (row, column) => row >= 0 && row < SIZE && column >= 0 && column < SIZE;
const occupied = (grid, row, column) => inside(row, column) && grid[row][column] !== '.';
const square = (row, column) => String.fromCharCode(65 + column) + (row + 1);
const position = (row, column, direction) => direction === 'across'
    ? (row + 1) + String.fromCharCode(65 + column) : square(row, column);
const empty = () => Array.from({ length: SIZE }, () => Array(SIZE).fill('.'));
const clone = grid => grid.map(row => row.slice());
const transpose = grid => Array.from({ length: SIZE }, (_, row) => grid.map(line => line[row]));
const transposeTiles = tiles => tiles.map(tile => ({ ...tile, row: tile.column, column: tile.row }));

function parsePosition(text) {
    let match = /^([1-9]|1[0-5])([A-O])$/.exec(text);
    if (match) return { row: Number(match[1]) - 1, column: match[2].charCodeAt(0) - 65, direction: 'across' };
    match = /^([A-O])([1-9]|1[0-5])$/.exec(text);
    return match ? { row: Number(match[2]) - 1, column: match[1].charCodeAt(0) - 65, direction: 'down' } : null;
}

function tiles(grid) {
    const result = [];
    for (let row = 0; row < SIZE; row++) for (let column = 0; column < SIZE; column++) {
        if (grid[row][column] !== '.') result.push({ row, column, letter: grid[row][column] });
    }
    return result;
}

function adjacent(grid, row, column) {
    return [[-1, 0], [1, 0], [0, -1], [0, 1]].some(([dr, dc]) => occupied(grid, row + dr, column + dc));
}

function connected(grid) {
    const placed = tiles(grid);
    if (placed.length === 0) return true;
    const queue = [placed[0]];
    const seen = new Set([placed[0].row * SIZE + placed[0].column]);
    for (let i = 0; i < queue.length; i++) {
        const { row, column } = queue[i];
        for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
            const r = row + dr;
            const c = column + dc;
            const key = r * SIZE + c;
            if (occupied(grid, r, c) && !seen.has(key)) {
                seen.add(key);
                queue.push({ row: r, column: c });
            }
        }
    }
    return seen.size === placed.length;
}

function words(grid) {
    const result = [];
    for (const direction of ['across', 'down']) {
        const oriented = direction === 'across' ? grid : transpose(grid);
        for (let row = 0; row < SIZE; row++) {
            let column = 0;
            while (column < SIZE) {
                if (oriented[row][column] === '.') { column++; continue; }
                const start = column;
                let word = '';
                while (column < SIZE && oriented[row][column] !== '.') word += oriented[row][column++];
                if (word.length >= 2) result.push(direction === 'across'
                    ? { row, column: start, direction, word }
                    : { row: start, column: row, direction, word });
            }
        }
    }
    return result;
}

function display(grid) {
    const lines = ['   ' + Array.from({ length: SIZE }, (_, i) => String.fromCharCode(65 + i)).join(' ')];
    for (let row = 0; row < SIZE; row++) {
        lines.push(String(row + 1).padStart(2) + ' ' + grid[row].map((letter, column) =>
            letter === '.' ? PREMIUMS[row][column] : letter).join(' '));
    }
    return lines;
}

module.exports = { SIZE, CENTER, PREMIUMS, inside, occupied, square, position, empty, clone,
    transpose, transposeTiles, parsePosition, tiles, adjacent, connected, words, display };
