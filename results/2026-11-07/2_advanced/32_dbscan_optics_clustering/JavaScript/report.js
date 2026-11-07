'use strict';

const fs = require('node:fs');

function fraction(numerator, denominator) {
    let a = Math.abs(numerator);
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return `${numerator / a}/${denominator / a}`;
}

const root = value => value === Infinity ? '-' : Math.sqrt(value).toFixed(3);
const integer = value => value === Infinity ? '-' : String(value);

function ariValue(numerator, denominator) {
    const text = (numerator / denominator).toFixed(4);
    return text === '-0.0000' ? '0.0000' : text;
}

function frame(rows) {
    const border = '+' + '-'.repeat(rows[0].length) + '+';
    return [border, ...rows.map(row => '|' + row + '|'), border];
}

function writeLines(name, lines) {
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

module.exports = { fraction, root, integer, ariValue, frame, writeLines };
