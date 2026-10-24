'use strict';

function logGamma(x) {
    const coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.001208650973866179, -0.000005395239384953];
    const t = x + 5.5;
    const adjusted = t - (x + 0.5) * Math.log(t);
    let sum = 1.000000000190015;
    for (let j = 0; j < coefficients.length; j++) sum += coefficients[j] / (x + j + 1);
    return -adjusted + Math.log(2.5066282746310005 * sum / x);
}

const replaceSmall = value => Math.abs(value) < 1e-300 ? 1e-300 : value;

function betaFraction(a, b, x) {
    let c = 1;
    let d = 1 / replaceSmall(1 - (a + b) * x / (a + 1));
    let h = d;
    for (let m = 1; m <= 1000; m++) {
        let q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m));
        d = 1 / replaceSmall(1 + q * d);
        c = replaceSmall(1 + q / c);
        h *= d * c;
        q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m));
        d = 1 / replaceSmall(1 + q * d);
        c = replaceSmall(1 + q / c);
        const delta = d * c;
        h *= delta;
        if (Math.abs(delta - 1) < 1e-15) break;
    }
    return h;
}

function beta(x, a, b) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const factor = Math.exp(logGamma(a + b) - logGamma(a) - logGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
    return x < (a + 1) / (a + b + 2) ? factor * betaFraction(a, b, x) / a : 1 - factor * betaFraction(b, a, 1 - x) / b;
}

function gamma(a, x) {
    if (x === 0) return 1;
    const factor = Math.exp(-x + a * Math.log(x) - logGamma(a));
    if (x < a + 1) {
        let term = 1 / a;
        let sum = term;
        let exponent = a;
        for (let i = 0; i < 1000; i++) {
            exponent++;
            term *= x / exponent;
            sum += term;
            if (Math.abs(term) < Math.abs(sum) * 1e-15) break;
        }
        return 1 - sum * factor;
    }
    let offset = x + 1 - a;
    let c = 1 / 1e-300;
    let d = 1 / offset;
    let h = d;
    for (let i = 1; i <= 1000; i++) {
        const q = -i * (i - a);
        offset += 2;
        d = 1 / replaceSmall(q * d + offset);
        c = replaceSmall(offset + q / c);
        const delta = d * c;
        h *= delta;
        if (Math.abs(delta - 1) < 1e-15) break;
    }
    return factor * h;
}

const tP = (value, degrees) => beta(degrees / (degrees + value * value), degrees / 2, 0.5);
const fP = (value, numerator, denominator) => beta(denominator / (denominator + numerator * value), denominator / 2, numerator / 2);
const chiP = (value, degrees) => gamma(degrees / 2, value / 2);

function tQuantile(confidence, degrees) {
    let low = 0;
    let high = 1000;
    for (let i = 0; i < 100; i++) {
        const middle = (low + high) / 2;
        if (tP(middle, degrees) > 1 - confidence) low = middle;
        else high = middle;
    }
    return (low + high) / 2;
}

const mark = value => value === null ? '' : value < 0.001 ? '***' : value < 0.01 ? '**' : value < 0.05 ? '*' : value < 0.1 ? '.' : '';

function fixed(value) {
    if (value === null) return 'NA';
    const magnitude = Math.abs(value);
    const text = magnitude >= 1e21 ? BigInt(magnitude).toString() + '.0000' : magnitude.toFixed(4);
    return value < 0 && text !== '0.0000' ? '-' + text : text;
}

const pValue = value => value === null ? 'NA' : value < 0.0001 ? '<0.0001' : fixed(value);

module.exports = { logGamma, betaFraction, beta, gamma, tP, fP, chiP, tQuantile, mark, fixed, pValue };
