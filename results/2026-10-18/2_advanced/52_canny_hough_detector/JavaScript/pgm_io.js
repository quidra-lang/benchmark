'use strict';

const fs = require('fs');

function readLines(path) {
  return fs.readFileSync(path, 'ascii').trimEnd().split('\n');
}

function readImage(path) {
  const lines = readLines(path);
  const [width, height] = lines[1].split(' ').map(Number);
  const pixels = lines.slice(3).flatMap(line => line.split(' ').map(Number));
  return { width, height, pixels };
}

function readTrig(path) {
  const cos = [], sin = [];
  for (const line of readLines(path)) {
    const [theta, c, s] = line.split(' ').map(Number);
    cos[theta] = c;
    sin[theta] = s;
  }
  return { cos, sin };
}

function readParams(path) {
  const params = {};
  for (const line of readLines(path)) {
    const [name, ...tokens] = line.split(' ');
    const values = tokens.map(Number);
    params[name] = name === 'gauss_kernel' ? values : values[0];
  }
  return params;
}

function writeImage(path, width, height, pixels) {
  const lines = ['P2', `${width} ${height}`, '255'];
  for (let y = 0; y < height; y++) {
    lines.push(Array.from(pixels.slice(y * width, (y + 1) * width)).join(' '));
  }
  fs.writeFileSync(path, lines.join('\n') + '\n', 'ascii');
}

module.exports = { readImage, readTrig, readParams, writeImage };
