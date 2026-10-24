'use strict';

const fs = require('node:fs');

function lines(filename) {
  return fs.readFileSync(filename, 'ascii').slice(0, -1).split('\n');
}

function point(id, x, y) {
  return { id, x, y, box: [x, y, x, y] };
}

function readDataset() {
  const points = lines('input/points.csv').slice(1).map(line => point(...line.split(',').map(Number)));
  const rectangles = lines('input/rects.csv').slice(1).map(line => {
    const [id, ...box] = line.split(',').map(Number);
    return { id, box };
  });
  const parameters = lines('input/params.txt').map(line => line.split(' ').slice(1).map(Number));
  const settings = { world: parameters[0][0], bucket: parameters[1][0], maximum: parameters[2][0],
    minimum: parameters[2][1], cell: parameters[3][0] };
  const commands = lines('input/queries.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return { name, args: values.map(Number) };
  });
  return { points, rectangles, settings, commands };
}

module.exports = { point, readDataset };
