'use strict';

const fs = require('node:fs');

function fraction(numerator, denominator) {
  let first = numerator;
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return `${numerator / first}/${denominator / first}`;
}

function ids(values) {
  return values.length ? values.join(' ') : '-';
}

function writeLines(filename, lines) {
  fs.writeFileSync('output/' + filename, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}

module.exports = { fraction, ids, writeLines };
