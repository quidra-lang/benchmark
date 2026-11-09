'use strict';

const fs = require('node:fs');

function fraction(value, denominator = 1) {
    let numerator;
    if (Array.isArray(value)) [numerator, denominator] = value;
    else numerator = value;
    let n = BigInt(numerator);
    let d = BigInt(denominator);
    const negative = n < 0n;
    if (negative) n = -n;
    let first = n;
    let second = d;
    while (second !== 0n) [first, second] = [second, first % second];
    n /= first;
    d /= first;
    const truncated = 10000n * n / d;
    const decimal = `${truncated / 10000n}.${String(truncated % 10000n).padStart(4, '0')}`;
    return `${negative ? '-' : ''}${n}/${d}=${negative && truncated !== 0n ? '-' : ''}${decimal}`;
}

function percentage(numerator, denominator) {
    const truncated = 10000n * BigInt(numerator) / BigInt(denominator);
    return `${truncated / 100n}.${String(truncated % 100n).padStart(2, '0')}%`;
}

const list = values => values.length === 0 ? '-' : values.join(',');

function writeOutputs(files) {
    fs.mkdirSync('output', {recursive: true});
    for (const [filename, lines] of Object.entries(files)) {
        fs.writeFileSync(`output/${filename}`, lines.join('\n') + '\n', 'ascii');
    }
}

module.exports = {fraction, percentage, list, writeOutputs};
