'use strict';

const fs = require('node:fs');

function roundedUnits(p, q) {
    const numerator = BigInt(p);
    const denominator = BigInt(q);
    return (2n * numerator * 10000n + denominator) / (2n * denominator);
}

function decimal(p, q) {
    const units = roundedUnits(p, q);
    return `${units / 10000n}.${String(units % 10000n).padStart(4, '0')}`;
}

function percentage(p, q) {
    if (q === 0) return '-';
    const units = roundedUnits(p, q);
    return `${units / 100n}.${String(units % 100n).padStart(2, '0')}`;
}

function fraction(p, q) {
    let a = BigInt(p);
    let b = BigInt(q);
    while (b !== 0n) [a, b] = [b, a % b];
    return `${BigInt(p) / a}/${BigInt(q) / a}`;
}

function hex(value) {
    return value.toString(16).padStart(8, '0');
}

function cycleHeader(start, end) {
    let digits = '';
    for (let cycle = start; cycle <= end; cycle++) digits += cycle % 10;
    return 'cycle' + ' '.repeat(18) + digits;
}

function diagramRow(row, start, end) {
    const characters = Array(end - start + 1).fill('.');
    for (const segment of row.segments) {
        for (let cycle = Math.max(start, segment.from); cycle <= Math.min(end, segment.to); cycle++) {
            characters[cycle - start] = cycle === segment.from ? segment.first : segment.rest;
        }
    }
    if (row.cancel !== null && row.cancel >= start && row.cancel <= end) characters[row.cancel - start] = 'x';
    if (characters.every(character => character === '.')) return null;
    return {
        line: `${String(row.number ?? '-').padStart(6)} ${hex(row.pc)} ${row.className.padEnd(6)} ${characters.join('')}${row.annotation}`,
        stallCells: characters.filter(character => character === '*').length,
        flushed: characters.filter(character => character === 'x').length
    };
}

function write(name, lines) {
    fs.mkdirSync('output', {recursive: true});
    fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}

module.exports = {decimal, percentage, fraction, hex, cycleHeader, diagramRow, write};
