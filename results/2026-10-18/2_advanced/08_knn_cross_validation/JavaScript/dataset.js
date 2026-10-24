'use strict';

const fs = require('node:fs');

function lines(name) {
  return fs.readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
}

function rows(records) {
  return records.slice(1).map((text, index) => {
    const fields = text.split(',');
    return { id: fields[0], features: fields.slice(1, -2).map(Number),
      label: fields.at(-2) === '' ? null : fields.at(-2),
      target: fields.at(-1) === '' ? null : Number(fields.at(-1)), index };
  });
}

function readDataset() {
  const training = lines('train.csv'), parameters = new Map(lines('params.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return [name, values];
  }));
  return { features: training[0].split(',').slice(1, -2), train: rows(training), test: rows(lines('test.csv')),
    settings: { scalings: parameters.get('SCALINGS'), ks: parameters.get('K_VALUES').map(Number),
      metrics: parameters.get('METRICS'), weightings: parameters.get('WEIGHTINGS'),
      folds: Number(parameters.get('FOLDS')[0]), editK: Number(parameters.get('EDIT_K')[0]),
      curve: parameters.get('CURVE').map(Number), bins: parameters.get('BINS').map(Number),
      top: Number(parameters.get('TOP')[0]) } };
}

module.exports = { readDataset };
