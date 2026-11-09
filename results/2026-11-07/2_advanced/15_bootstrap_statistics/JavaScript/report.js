'use strict';

const fs = require('node:fs');
const { reduced } = require('./tests');

function real(value) {
    let text = Math.abs(value).toFixed(4);
    if (text.includes('e')) text = BigInt(Math.abs(value)).toString() + '.0000';
    return value < 0 && /[1-9]/.test(text) ? '-' + text : text;
}

function pValue(numerator, denominator) {
    const [first, second] = reduced(numerator, denominator);
    return `${first}/${second} ${real(first / second)}`;
}

function numberList(numbers) {
    return numbers.length === 0 ? 'none' : numbers.join(' ');
}

function binNumber(value, lo, hi, count) {
    return Math.min(Math.floor(count * (value - lo) / (hi - lo)), count - 1) + 1;
}

function bar(count, top) {
    return '#'.repeat(Math.floor((40 * count + top - 1) / top));
}

function writeLines(name, lines) {
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
}

module.exports = { real, pValue, numberList, binNumber, bar, writeLines };
