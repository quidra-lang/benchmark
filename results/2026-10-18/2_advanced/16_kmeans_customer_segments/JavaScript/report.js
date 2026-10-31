'use strict';

const fs = require('node:fs');

function real(value) {
  if (value === null) return '-';
  let text = Math.abs(value).toFixed(4);
  if (text.includes('e')) text = BigInt(Math.abs(value)).toString() + '.0000';
  return value < 0 && /[1-9]/.test(text) ? '-' + text : text;
}

const rounded = value => Number(real(value));

function amount(value) {
  const magnitude = Math.abs(value);
  return (value < 0 ? '-' : '') + Math.floor(magnitude / 100) + '.' + String(magnitude % 100).padStart(2, '0');
}

function writeReport(name, lines) {
  fs.mkdirSync('output', { recursive: true });
  fs.writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { real, rounded, amount, writeReport };
