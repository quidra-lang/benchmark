'use strict';

const { S, div, isqrt } = require('./fixed_point');

const add = (a, b) => a.map((value, i) => value + b[i]);
const sub = (a, b) => a.map((value, i) => value - b[i]);
const neg = a => a.map(value => -value);
const dot = (a, b) => div(a[0] * b[0] + a[1] * b[1] + a[2] * b[2], S);
const scale = (a, k) => a.map(value => div(value * k, S));
const length = a => isqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);

function normalize(a) {
  const len = length(a);
  return a.map(value => div(value * S, len));
}

module.exports = { add, sub, neg, dot, scale, length, normalize };
