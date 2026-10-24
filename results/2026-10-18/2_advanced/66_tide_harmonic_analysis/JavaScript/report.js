'use strict';

const fs = require('node:fs');

function real(value, digits) {
  if (value === null) return 'none';
  if (Math.abs(value) >= 1e21) return BigInt(value).toString() + '.' + '0'.repeat(digits);
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}

function plotLines(cells, heights) {
  const labels = heights.map(height => real(height / 100, 2));
  let width = 0;
  for (const label of labels) width = Math.max(width, label.length);
  const result = cells.map((row, index) => labels[index].padStart(width) + ' |' + row.join('') + '|');
  let axis = ' '.repeat(width) + ' +';
  for (let column = 0; column < cells[0].length; column++) axis += column % 6 === 0 ? '+' : '-';
  result.push(axis + '+');
  return result;
}

function writeFiles(files) {
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
}

module.exports = {real, plotLines, writeFiles};
