'use strict';

const fs = require('node:fs');

function fixed(value, digits = 4) {
  if (value === null) return '-';
  const magnitude = Math.abs(value);
  const result = magnitude >= 1e21 ?
    BigInt(magnitude).toString() + '.' + '0'.repeat(digits) : magnitude.toFixed(digits);
  return value < 0 && result !== '0.' + '0'.repeat(digits) ? '-' + result : result;
}

const ratio = (numerator, denominator) => denominator > 0 ? fixed(numerator / denominator) : '-';
const prediction = score => score > 0 ? 1 : -1;

function auc(rows, scores) {
  let positive = 0;
  let negative = 0;
  let wins = 0;
  let ties = 0;
  for (const row of rows) {
    if (row.label === 1) positive++;
    else negative++;
  }
  for (let a = 0; a < rows.length; a++) {
    if (rows[a].label !== 1) continue;
    for (let b = 0; b < rows.length; b++) {
      if (rows[b].label !== -1) continue;
      if (scores[a] > scores[b]) wins++;
      else if (scores[a] === scores[b]) ties++;
    }
  }
  return ratio(2 * wins + ties, 2 * positive * negative);
}

function confusion(rows, predictions, classes) {
  const matrix = Array.from({ length: classes }, () => Array(classes).fill(0));
  for (let i = 0; i < rows.length; i++) matrix[rows[i].category - 1][predictions[i] - 1]++;
  return matrix;
}

function countAtMost(values, threshold) {
  let count = 0;
  for (const value of values) if (value <= threshold) count++;
  return count;
}

function writeLines(name, lines) {
  fs.mkdirSync('output', { recursive: true });
  fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

module.exports = { fixed, ratio, prediction, auc, confusion, countAtMost, writeLines };
