'use strict';

function grid(width, height) {
  return Array.from({ length: height }, () => Array(width).fill(' '));
}

function frame(rows) {
  const border = '+' + '-'.repeat(rows[0].length) + '+';
  return [border, ...rows.map(row => '|' + row.join('') + '|'), border];
}

function biplotCell(x, y, maximumX, maximumY, width, height) {
  return { column: Math.min(Math.floor((x + maximumX) / (2 * maximumX) * width), width - 1),
    row: Math.min(Math.floor((maximumY - y) / (2 * maximumY) * height), height - 1) };
}

function diagnosticCell(t2, spe, maximumX, maximumY, width, height) {
  return { column: Math.min(Math.floor(t2 / maximumX * width), width - 1),
    row: height - 1 - Math.min(Math.floor(spe / maximumY * height), height - 1) };
}

function shaft(origin, tip) {
  const dc = tip.column - origin.column;
  const dr = tip.row - origin.row;
  const steps = Math.max(Math.abs(dc), Math.abs(dr));
  const character = 2 * Math.abs(dr) <= Math.abs(dc) ? '-' : 2 * Math.abs(dc) <= Math.abs(dr) ? '|' : dc * dr < 0 ? '/' : '\\';
  const cells = [];
  for (let step = 1; step < steps; step++) {
    cells.push({ column: origin.column + Math.sign(dc) * Math.floor((2 * step * Math.abs(dc) + steps) / (2 * steps)),
      row: origin.row + Math.sign(dr) * Math.floor((2 * step * Math.abs(dr) + steps) / (2 * steps)), character });
  }
  return cells;
}

function scree(width, bar, brokenStick, kaiser) {
  let line = '';
  for (let position = 1; position <= width; position++) {
    line += position === brokenStick ? 'o' : position === kaiser ? ':' : position <= bar ? '#' : ' ';
  }
  return line;
}

module.exports = { grid, frame, biplotCell, diagnosticCell, shaft, scree };
