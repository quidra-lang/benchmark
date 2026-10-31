'use strict';

const fs = require('node:fs');

function real(value) {
  if (value === null) return '-';
  if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.0000';
  const text = value.toFixed(4);
  return text === '-0.0000' ? '0.0000' : text;
}

function writeLines(filename, lines) {
  fs.writeFileSync('output/' + filename, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { real, writeLines };
