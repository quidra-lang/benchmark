'use strict';

const fs = require('node:fs');

function real(value, places = 4) {
    if (value === null) return '-';
    if (Math.abs(value) >= 1e21) return `${BigInt(value)}.${'0'.repeat(places)}`;
    const text = value.toFixed(places);
    return Number(text) === 0 ? (0).toFixed(places) : text;
}

function frame(rows) {
    const border = `+${'-'.repeat(rows[0].length)}+`;
    return [border, ...rows.map(row => `|${row.join('')}|`), border];
}

function write(name, lines) {
    fs.mkdirSync('output', {recursive: true});
    fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

module.exports = {real, frame, write};
