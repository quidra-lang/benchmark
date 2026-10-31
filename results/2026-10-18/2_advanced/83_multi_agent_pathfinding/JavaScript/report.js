'use strict';

const fs = require('node:fs');

function cell(grid, value) {
  return `${value % grid.width},${Math.floor(value / grid.width)}`;
}

function name(number) {
  return String.fromCharCode(65 + number);
}

function conflict(grid, value) {
  const prefix = `${value.kind} t ${value.time} ${name(value.a)} ${name(value.b)}`;
  return value.kind === 'vertex' ? `${prefix} at ${cell(grid, value.v)}` :
    `${prefix} from ${cell(grid, value.u)} to ${cell(grid, value.v)}`;
}

function actions(grid, path) {
  let result = '';
  for (let index = 1; index < path.length; index++) {
    const delta = path[index] - path[index - 1];
    result += delta === 0 ? '.' : delta === -grid.width ? 'N' : delta === 1 ? 'E' : delta === grid.width ? 'S' : 'W';
  }
  return result;
}

function fraction(numerator, denominator) {
  let first = numerator;
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return `${numerator / first}/${denominator / first}`;
}

function csv(values) {
  return values.join(',');
}

function writeFiles(files) {
  fs.mkdirSync('output', {recursive: true});
  for (const [filename, contents] of Object.entries(files)) {
    fs.writeFileSync(`output/${filename}`, contents.join('\n') + '\n', 'ascii');
  }
}

module.exports = {cell, name, conflict, actions, fraction, csv, writeFiles};
