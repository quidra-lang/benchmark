'use strict';

const rdiv = (numerator, denominator) => Math.floor((2 * numerator + denominator) / (2 * denominator));

function decimal2(value) {
    const absolute = Math.abs(value);
    return (value < 0 ? '-' : '') + Math.floor(absolute / 100) + '.' + String(absolute % 100).padStart(2, '0');
}

const decimal4 = value => Math.floor(value / 10000) + '.' + String(value % 10000).padStart(4, '0');

function fraction(numerator, denominator) {
    let a = numerator;
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return numerator / a + '/' + denominator / a;
}

function ratio(numerator, denominator) {
    const raw = numerator + '/' + denominator;
    return denominator > 0 ? raw + ' reduced=' + fraction(numerator, denominator) + ' percent=' + decimal2(rdiv(10000 * numerator, denominator)) : raw + ' none';
}

const missing = value => value === null || value === undefined ? '-' : String(value);

module.exports = { rdiv, decimal2, decimal4, fraction, ratio, missing };
