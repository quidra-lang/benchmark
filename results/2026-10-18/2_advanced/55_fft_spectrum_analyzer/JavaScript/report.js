'use strict';

const fs = require('node:fs');

function fixed(value) {
  const absolute = Math.abs(value);
  const text = absolute >= 1e21 ? BigInt(absolute).toString() + '.0000' : absolute.toFixed(4);
  return value < 0 && text !== '0.0000' ? '-' + text : text;
}

function writeLines(name, lines) {
  fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

function writeCsv(name, rows) {
  writeLines(name, rows.map(row => row.join(',')));
}

function shadeLines(levels, sampleRate, frameLength) {
  const shades = ' .:-=+*#%@';
  const lines = [];
  for (let k = frameLength / 2; k >= 0; k--) {
    lines.push(fixed(k * sampleRate / frameLength).padStart(9) + ' |' + levels.map(frame => shades[frame[k]]).join('') + '|');
  }
  return lines;
}

module.exports = { fixed, writeLines, writeCsv, shadeLines };
