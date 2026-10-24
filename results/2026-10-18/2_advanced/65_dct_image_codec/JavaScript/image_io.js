'use strict';

const fs = require('fs');

function readLines(path) { return fs.readFileSync(path, 'ascii').split('\n').slice(0, -1); }
function writeLines(path, lines) { fs.writeFileSync(path, lines.join('\n') + '\n', 'ascii'); }

function readPPM(path) {
  const lines = readLines(path), [width, height] = lines[1].split(' ').map(Number);
  return { width, height, pixels: lines.slice(3).map(line => {
    const values = line.split(' ').map(Number);
    return Array.from({ length: width }, (_, x) => values.slice(3 * x, 3 * x + 3));
  }) };
}

function writePPM(path, image) {
  writeLines(path, ['P3', `${image.width} ${image.height}`, '255', ...image.pixels.map(row => row.flat().join(' '))]);
}

function readParams(path) {
  const result = {};
  for (const line of readLines(path)) {
    const [name, ...values] = line.split(' ');
    result[name] = name === 'huffman' || name === 'sampling' ? values[0]
      : name === 'qualities' || name === 'truncate' ? values.map(Number) : Number(values[0]);
  }
  return result;
}

function readTables(path) {
  const lines = readLines(path), rows = start => lines.slice(start, start + 8).flatMap(line => line.split(' ').map(Number));
  const huffman = [];
  for (let i = 27; i < 39; i += 3) {
    const [, tableClass, id] = lines[i].split(' ');
    huffman.push({ tableClass: Number(tableClass), id: Number(id),
      bits: lines[i + 1].split(' ').map(Number), values: lines[i + 2].split(' ').map(Number) });
  }
  return { C: rows(1), base: [rows(10), rows(19)], huffman };
}

function readHex(path) {
  const text = readLines(path).join(''), bytes = [];
  for (let i = 0; i < text.length; i += 2) bytes.push(parseInt(text.slice(i, i + 2), 16));
  return bytes;
}

function writeHex(path, bytes) {
  const lines = [];
  for (let i = 0; i < bytes.length; i += 32) lines.push(bytes.slice(i, i + 32).map(value => value.toString(16).padStart(2, '0')).join(''));
  writeLines(path, lines);
}

module.exports = { readPPM, writePPM, readParams, readTables, readHex, writeHex, writeLines };
