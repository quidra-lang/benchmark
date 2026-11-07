'use strict';

const fs = require('node:fs');
const readLines = name => fs.readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');

function binaryRows(lines) {
  return lines.slice(1).map(line => {
    const fields = line.split(',');
    return { id: fields[0], values: fields.slice(1, -1).map(Number), label: Number(fields.at(-1)) };
  });
}

function readDataset() {
  const trainLines = readLines('train.csv');
  const testLines = readLines('test.csv');
  const multiLines = readLines('multiclass.csv');
  const features = trainLines[0].split(',').slice(1, -1);
  const multiFeatures = multiLines[0].split(',').slice(1, -2);
  const multiTrain = [];
  const multiTest = [];
  for (const line of multiLines.slice(1)) {
    const fields = line.split(',');
    const row = { id: fields[0], values: fields.slice(1, -2).map(Number), category: Number(fields.at(-2)) };
    (fields.at(-1) === 'train' ? multiTrain : multiTest).push(row);
  }
  const settings = readLines('params.txt').map(line => line.split(' ').slice(1));
  const params = {
    rounds: Number(settings[0][0]), variants: settings[1], bins: Number(settings[2][0]),
    smoothing: Number(settings[3][0]), convergence: Number(settings[4][0]),
    clip: Number(settings[5][0]), folds: Number(settings[6][0]), margins: settings[7].map(Number),
    classes: Number(settings[8][0]), sammeRounds: Number(settings[9][0]),
    permutationRepeats: Number(settings[10][0]), permutationSeed: Number(settings[10][1]),
    noiseSeed: Number(settings[11][0]), noise: settings[11].slice(1).map(Number),
    sizes: settings[12].map(Number), shrinkage: settings[13].map(Number),
    bootstrapSamples: Number(settings[14][0]), bootstrapSeed: Number(settings[14][1])
  };
  return { features, train: binaryRows(trainLines), test: binaryRows(testLines),
    multiFeatures, multiTrain, multiTest, params };
}

module.exports = { readDataset };
