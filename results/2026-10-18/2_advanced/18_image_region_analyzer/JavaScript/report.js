'use strict';

const fs = require('node:fs');

function floorRatio(numerator, denominator) {
    const a = BigInt(numerator);
    const b = BigInt(denominator);
    let quotient = a / b;
    if (a < 0n && a % b !== 0n) quotient--;
    return Number(quotient);
}

function decimal(numerator, denominator, digits) {
    let p = BigInt(numerator);
    const q = BigInt(denominator);
    const negative = p < 0n;
    if (negative) p = -p;
    const scale = 10n ** BigInt(digits);
    const rounded = (2n * scale * p + q) / (2n * q);
    const sign = negative && rounded > 0n ? '-' : '';
    return `${sign}${rounded / scale}.${String(rounded % scale).padStart(digits, '0')}`;
}

function hullArea(doubledArea) {
    return `${floorRatio(doubledArea, 2)}.${doubledArea % 2 === 0 ? '0' : '5'}`;
}

function writeReports(reports) {
    fs.mkdirSync('output', { recursive: true });
    for (const [name, lines] of Object.entries(reports)) {
        fs.writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
    }
}

module.exports = { floorRatio, decimal, hullArea, writeReports };
