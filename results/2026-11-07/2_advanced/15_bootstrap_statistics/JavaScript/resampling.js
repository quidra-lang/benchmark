'use strict';

function sum(values) {
    let total = 0;
    for (const value of values) total += value;
    return total;
}

const sorted = values => values.slice().sort((a, b) => a - b);
const mean = values => sum(values) / (100 * values.length);

function Md(values) {
    const order = sorted(values);
    return order[Math.floor((order.length - 1) / 2)] + order[Math.floor(order.length / 2)];
}

const med = values => Md(values) / 200;

function trim(values) {
    const order = sorted(values);
    const count = Math.floor(values.length / 10);
    return sum(order.slice(count, order.length - count)) / (100 * (values.length - 2 * count));
}

function moments(values) {
    const center = mean(values);
    let second = 0;
    let third = 0;
    let fourth = 0;
    for (const value of values) {
        const deviation = value / 100 - center;
        second += deviation * deviation;
        third += deviation * deviation * deviation;
        fourth += deviation * deviation * deviation * deviation;
    }
    return { sd: Math.sqrt(second / (values.length - 1)), m2: second / values.length,
        m3: third / values.length, m4: fourth / values.length };
}

const sd = values => moments(values).sd;
const mad = values => Md(values.map(value => Math.abs(2 * value - Md(values)))) / 400;

function Qn(values, percentile) {
    const order = sorted(values);
    const u = (values.length - 1) * percentile;
    const index = Math.floor(u / 100);
    const fraction = u - 100 * index;
    return 100 * order[index] + (fraction === 0 ? 0 : fraction * (order[index + 1] - order[index]));
}

function wins(values) {
    const order = sorted(values);
    const count = Math.floor(values.length / 10);
    return values.map(value => Math.min(Math.max(value, order[count]), order[values.length - count - 1]));
}

function mdiff(x, y) {
    return (y.length * sum(x) - x.length * sum(y)) / (100 * x.length * y.length);
}

const mratio = (x, y) => Md(x) / Md(y);

function hl(x, y) {
    const differences = [];
    for (const first of x) for (const second of y) differences.push(first - second);
    return Md(differences) / 200;
}

function sp(x, y) {
    const sx = sd(x);
    const sy = sd(y);
    return Math.sqrt(((x.length - 1) * sx * sx + (y.length - 1) * sy * sy) / (x.length + y.length - 2));
}

const cd = (x, y) => mdiff(x, y) / sp(x, y);

function corr(x, y) {
    const mx = mean(x);
    const my = mean(y);
    let cross = 0;
    let first = 0;
    let second = 0;
    for (let index = 0; index < x.length; index++) {
        const e = x[index] / 100 - mx;
        const f = y[index] / 100 - my;
        cross += e * f;
        first += e * e;
        second += f * f;
    }
    return cross / Math.sqrt(first * second);
}

function drawIndices(size, rng) {
    return Array.from({ length: size }, () => rng.below(size));
}

function ordinaryIndices(size, count, rng) {
    return Array.from({ length: count }, () => drawIndices(size, rng));
}

function balancedIndices(size, count, rng) {
    const indices = Array.from({ length: size * count }, (_, index) => index % size);
    rng.shuffle(indices);
    return Array.from({ length: count }, (_, index) => indices.slice(index * size, (index + 1) * size));
}

function without(values, index) {
    return values.filter((value, position) => position !== index);
}

function meanAndSe(values) {
    const average = sum(values) / values.length;
    let squared = 0;
    for (const value of values) {
        const difference = value - average;
        squared += difference * difference;
    }
    return { average, se: Math.sqrt(squared / (values.length - 1)) };
}

function Phi(x) {
    if (x < 0) return 1 - Phi(-x);
    const eta = 1 / (1 + 0.2316419 * x);
    const psi = eta * (0.319381530 + eta * (-0.356563782
        + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
    return 1 - 0.3989422804014327 * Math.exp(-(x * x) / 2) * psi;
}

function PhiInv(p) {
    if (p > 0.5) return -PhiInv(1 - p);
    const eta = Math.sqrt(-2 * Math.log(p));
    return -(eta - (2.515517 + eta * (0.802853 + eta * 0.010328))
        / (1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))));
}

module.exports = { sum, sorted, mean, Md, med, trim, moments, sd, mad, Qn, wins, mdiff, mratio,
    hl, sp, cd, corr, drawIndices, ordinaryIndices, balancedIndices, without, meanAndSe, Phi, PhiInv };
