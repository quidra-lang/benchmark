'use strict';

const { Fraction, point } = require('./rational');
const { flatten, interior } = require('./rings');

function render(target, values) {
  const [x0, y0, width, height, columns, rows] = values, grid = [], counts = { '#': 0, a: 0, b: 0, '+': 0 };
  const result = flatten(target.result);
  for (let row = 0; row < rows; row++) {
    let text = '';
    for (let col = 0; col < columns; col++) {
      const center = point(new Fraction(2 * x0 + (2 * col + 1) * width, 2),
        new Fraction(2 * y0 + (2 * (rows - 1 - row) + 1) * height, 2));
      let character = '.';
      if (interior(center, result)) character = '#';
      else if (target.operands !== null) {
        const a = interior(center, target.operands[0].rings), b = interior(center, target.operands[1].rings);
        character = a && b ? '+' : a ? 'a' : b ? 'b' : '.';
      }
      if (character !== '.') counts[character]++;
      text += character;
    }
    grid.push(text);
  }
  return { grid, counts };
}

module.exports = { render };
