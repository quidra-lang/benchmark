'use strict';

const fs = require('node:fs');

function real(value, digits = 4) {
  if (value === null) return '-';
  let text = Math.abs(value).toFixed(digits);
  if (text.includes('e')) {
    text = BigInt(Math.abs(value)).toString() + '.' + '0'.repeat(digits);
  }
  return value < 0 && /[1-9]/.test(text) ? '-' + text : text;
}

const rounded = value => Number(real(value));
const ratio = (numerator, denominator) => `${numerator}/${denominator} ${real(numerator / denominator)}`;

function fractionMetric(numerator, denominator) {
  if (denominator === 0) return '- -';
  if (numerator === 0) return '0/1 0.0000';
  let left = numerator, right = denominator;
  while (right !== 0) [left, right] = [right, left % right];
  return `${numerator / left}/${denominator / left} ${real(numerator / denominator)}`;
}

function writeReport(name, lines) {
  fs.mkdirSync('output', { recursive: true });
  fs.writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { real, rounded, ratio, fractionMetric, writeReport };
