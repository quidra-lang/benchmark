'use strict';

const fs = require('node:fs');

function items(prefix, values) {
    return prefix + ' ' + Object.entries(values).map(([name, value]) => `${name}=${value}`).join(' ');
}

function numberList(values) {
    return values.length === 0 ? '-' : values.join(',');
}

function frequencyList(values) {
    const counts = new Map();
    for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
    return counts.size === 0 ? '-' : [...counts].sort((first, second) => first[0] - second[0])
        .map(([value, count]) => `${value}:${count}`).join(',');
}

function boardLines(columns) {
    return columns.map(column => '.'.repeat(column - 1) + 'Q' + '.'.repeat(columns.length - column));
}

function writeParagraphs(filename, paragraphs) {
    fs.writeFileSync(`output/${filename}`, paragraphs.length === 0 ? '' : paragraphs.map(lines => lines.join('\n')).join('\n\n') + '\n', 'ascii');
}

function writeCsv(filename, rows) {
    fs.writeFileSync(`output/${filename}`, rows.map(row => row.join(',')).join('\n') + '\n', 'ascii');
}

module.exports = { items, numberList, frequencyList, boardLines, writeParagraphs, writeCsv };
