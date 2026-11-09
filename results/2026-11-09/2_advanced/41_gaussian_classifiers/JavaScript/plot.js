'use strict';

const fs = require('node:fs');

function real(value) {
  if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.0000';
  const text = value.toFixed(4);
  return text === '-0.0000' ? '0.0000' : text;
}

function fractionText(value) {
  return value === null ? '-' : value[0] + '/' + value[1] + ' ' + real(value[0] / value[1]);
}

function frame(rows) {
  const border = '+' + '-'.repeat(rows[0].length) + '+';
  return [border, ...rows.map(row => '|' + row.join('') + '|'), border];
}

function cell(value, low, high, size) {
  return Math.floor((value - low) / (high - low) * (size - 1) + 0.5);
}

function writeLines(filename, lines) {
  fs.writeFileSync('output/' + filename, lines.join('\n') + '\n', 'ascii');
}

module.exports = { real, fractionText, frame, cell, writeLines };
