'use strict';

const fs = require('node:fs');

function readLines(filename) {
  return fs.readFileSync(filename, 'ascii').slice(0, -1).split('\n');
}

function readDataset() {
  const training = readLines('input/train.csv');
  const testing = readLines('input/test.csv');
  const features = training[0].split(',').slice(1, -1);
  const records = lines => lines.slice(1).map(line => {
    const fields = line.split(',');
    return { id: Number(fields[0]), values: fields.slice(1, -1).map(Number), label: fields.at(-1) };
  });
  const train = records(training);
  const test = records(testing);
  const classes = [...new Set(train.map(row => row.label))].sort();
  const classNumbers = new Map(classes.map((name, index) => [name, index]));
  for (const row of [...train, ...test]) row.class = classNumbers.get(row.label);
  const costLines = readLines('input/costs.csv');
  const costClasses = costLines[0].split(',').slice(1);
  const costs = Array.from({ length: classes.length }, () => []);
  for (const line of costLines.slice(1)) {
    const fields = line.split(',');
    costs[classNumbers.get(fields[0])] = classes.map(name => Number(fields[costClasses.indexOf(name) + 1]));
  }
  const settings = { subsets: [], pairs: [] };
  for (const line of readLines('input/params.txt')) {
    const [keyword, ...values] = line.split(' ');
    switch (keyword) {
      case 'PRIOR': settings.prior = values[0]; break;
      case 'VAR_SMOOTHING': settings.epsilon = Number(values[0]); break;
      case 'SMOOTHING_GRID': settings.smoothingGrid = values.map(Number); break;
      case 'QDA_GAMMA': settings.gamma = Number(values[0]); break;
      case 'GAMMA_GRID': settings.gammaGrid = values.map(Number); break;
      case 'CV_FOLDS': settings.folds = Number(values[0]); break;
      case 'CALIBRATION_EDGES': settings.calibration = values.map(Number); break;
      case 'REJECT_THRESHOLDS': settings.reject = values.map(Number); break;
      case 'CURVE': settings.curve = values.map(Number); break;
      case 'OUTLIER_THRESHOLD': settings.outlier = Number(values[0]); break;
      case 'BOOTSTRAP': [settings.resamples, settings.seed] = values.map(Number); break;
      case 'MAP_SIZE': [settings.width, settings.height] = values.map(Number); break;
      case 'PLOT_SIZE': [settings.plotWidth, settings.plotHeight] = values.map(Number); break;
      case 'SUBSET':
        settings.subsets.push({ name: values[0], features: values.slice(1).map(name => features.indexOf(name)) });
        break;
      case 'PAIR': settings.pairs.push(values.map(name => features.indexOf(name))); break;
    }
  }
  return { features, classes, train, test, costs, settings };
}

module.exports = { readDataset };
