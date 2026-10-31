'use strict';

const { clamp } = require('./color');

const zigzag = [];
for (let diagonal = 0; diagonal <= 14; diagonal++) {
  const positions = [];
  for (let u = 0; u < 8; u++) if (diagonal - u >= 0 && diagonal - u < 8) positions.push(u * 8 + diagonal - u);
  if (diagonal % 2 === 0) positions.reverse();
  zigzag.push(...positions);
}

function rnd(value, shift) { return Math.floor((value + 2 ** (shift - 1)) / 2 ** shift); }

function forward(values, C) {
  const intermediate = Array(64).fill(0), result = Array(64).fill(0);
  for (let u = 0; u < 8; u++) for (let x = 0; x < 8; x++) {
    let sum = 0;
    for (let y = 0; y < 8; y++) sum += C[u * 8 + y] * (values[y * 8 + x] - 128);
    intermediate[u * 8 + x] = rnd(sum, 11);
  }
  for (let u = 0; u < 8; u++) for (let v = 0; v < 8; v++) {
    let sum = 0;
    for (let x = 0; x < 8; x++) sum += intermediate[u * 8 + x] * C[v * 8 + x];
    result[u * 8 + v] = rnd(sum, 15);
  }
  return result;
}

function inverse(values, C) {
  const intermediate = Array(64).fill(0), result = Array(64).fill(0);
  for (let y = 0; y < 8; y++) for (let v = 0; v < 8; v++) {
    let sum = 0;
    for (let u = 0; u < 8; u++) sum += C[u * 8 + y] * values[u * 8 + v];
    intermediate[y * 8 + v] = rnd(sum, 11);
  }
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    let sum = 0;
    for (let v = 0; v < 8; v++) sum += intermediate[y * 8 + v] * C[v * 8 + x];
    result[y * 8 + x] = clamp(rnd(sum, 15) + 128);
  }
  return result;
}

function tables(base, quality) {
  const scale = quality < 50 ? Math.floor(5000 / quality) : 200 - 2 * quality;
  return base.map(table => table.map(value => Math.min(Math.max(Math.floor((value * scale + 50) / 100), 1), 255)));
}

function quantize(values, table) {
  return zigzag.map(index => {
    const magnitude = Math.floor((Math.abs(values[index]) + Math.floor(table[index] / 2)) / table[index]);
    return values[index] < 0 ? -magnitude : magnitude;
  });
}

function dequantize(coefficients, table, keep = 64) {
  const result = Array(64).fill(0);
  for (let i = 0; i < keep; i++) result[zigzag[i]] = coefficients[i] * table[zigzag[i]];
  return result;
}

module.exports = { zigzag, rnd, forward, inverse, tables, quantize, dequantize };
