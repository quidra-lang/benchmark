'use strict';

const { rowAt } = require('./estimators');

function plotLines(collections, width, height, time) {
  const cells = Array.from({ length: height }, () => Array(width).fill(' '));
  function occupy(band, column, letter) {
    const previous = cells[band][column];
    cells[band][column] = previous === ' ' || previous === letter ? letter : '*';
  }
  for (let g = 0; g < collections.length; g++) {
    const collection = collections[g];
    const letter = String.fromCharCode(65 + g);
    let previousBand = null;
    for (let column = 0; column < width; column++) {
      const sampleTime = column * (time / width);
      if (sampleTime > collection.maxTime) break;
      const band = Math.min(height - 1, Math.floor(rowAt(collection.km, sampleTime).survival * height));
      occupy(band, column, letter);
      if (previousBand !== null && previousBand - 1 > band) {
        for (let q = band + 1; q < previousBand; q++) occupy(q, column, letter);
      }
      previousBand = band;
    }
  }
  const border = '   +' + '-'.repeat(width) + '+';
  const lines = [border];
  for (let q = height - 1; q >= 0; q--) {
    lines.push(String(Math.floor(100 * q / height)).padStart(3) + '|' + cells[q].join('') + '|');
  }
  lines.push(border, `time 0 to ${time} days, ${time / width} days per column`);
  return lines;
}

module.exports = { plotLines };
