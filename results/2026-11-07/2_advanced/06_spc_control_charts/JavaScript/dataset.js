'use strict';

const fs = require('node:fs');

const CONSTANTS = new Map([
  [2, [1.880, 2.659, 0, 3.267, 0, 3.267, 1.128, 0.7979]],
  [3, [1.023, 1.954, 0, 2.568, 0, 2.574, 1.693, 0.8862]],
  [4, [0.729, 1.628, 0, 2.266, 0, 2.282, 2.059, 0.9213]],
  [5, [0.577, 1.427, 0, 2.089, 0, 2.114, 2.326, 0.9400]],
  [6, [0.483, 1.287, 0.030, 1.970, 0, 2.004, 2.534, 0.9515]],
  [7, [0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594]],
  [8, [0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650]],
  [9, [0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693]],
  [10, [0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727]],
].map(([size, row]) => {
  const [A2, A3, B3, B4, D3, D4, d2, c4] = row;
  return [size, {A2, A3, B3, B4, D3, D4, d2, c4}];
}));

function readLines(path) {
  return fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
}

function readDataset() {
  const spec = {rules: new Map()};
  for (const line of readLines('input/spec.txt')) {
    const [name, ...values] = line.split(' ');
    if (name === 'rules') spec.rules.set(values[0], values.slice(1).map(Number));
    else spec[name] = name === 'characteristic' ? values[0] : Number(values[0]);
  }
  const samples = readLines('input/measurements.csv').slice(1).map(line => {
    const [number, subgroup, value] = line.split(',').map(Number);
    return {number, subgroup, value};
  });
  const lots = readLines('input/attributes.csv').slice(1).map(line => {
    const [number, inspected, defectives, defects] = line.split(',').map(Number);
    return {number, inspected, defectives, defects};
  });
  return {spec, samples, lots, constants: CONSTANTS.get(spec.subgroup_size)};
}

module.exports = {CONSTANTS, readDataset};
