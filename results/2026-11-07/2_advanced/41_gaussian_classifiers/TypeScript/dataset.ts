import { readFileSync } from 'node:fs';
export interface Row {
  id: number;
  values: number[];
  label: string;
  class: number;
}
export type Prior = 'empirical' | 'uniform';
export interface Subset {
  name: string;
  features: number[];
}
export interface Settings {
  prior: Prior;
  epsilon: number;
  smoothingGrid: number[];
  gamma: number;
  gammaGrid: number[];
  folds: number;
  calibration: number[];
  reject: number[];
  curve: number[];
  outlier: number;
  resamples: number;
  seed: number;
  width: number;
  height: number;
  plotWidth: number;
  plotHeight: number;
  subsets: Subset[];
  pairs: number[][];
}
export interface Dataset {
  features: string[];
  classes: string[];
  train: Row[];
  test: Row[];
  costs: number[][];
  settings: Settings;
}
const readLines = (name: string) =>
  readFileSync('input/' + name, 'ascii')
    .slice(0, -1)
    .split('\n');
export function readDataset(): Dataset {
  const training = readLines('train.csv');
  const testing = readLines('test.csv');
  const features = training[0].split(',').slice(1, -1);
  const records = (lines: string[]): Row[] =>
    lines.slice(1).map((line) => {
      const f = line.split(',');
      return {
        id: Number(f[0]),
        values: f.slice(1, -1).map(Number),
        label: f[f.length - 1],
        class: 0,
      };
    });
  const train = records(training);
  const test = records(testing);
  const classes = [...new Set(train.map((r) => r.label))].sort();
  for (const row of [...train, ...test]) row.class = classes.indexOf(row.label);
  const costLines = readLines('costs.csv');
  const costClasses = costLines[0].split(',').slice(1);
  const costs: number[][] = Array.from({ length: classes.length }, () => []);
  for (const line of costLines.slice(1)) {
    const f = line.split(',');
    costs[classes.indexOf(f[0])] = classes.map((name) => Number(f[costClasses.indexOf(name) + 1]));
  }
  const settings: Settings = {
    prior: 'empirical',
    epsilon: 0,
    smoothingGrid: [],
    gamma: 0,
    gammaGrid: [],
    folds: 0,
    calibration: [],
    reject: [],
    curve: [],
    outlier: 0,
    resamples: 0,
    seed: 0,
    width: 0,
    height: 0,
    plotWidth: 0,
    plotHeight: 0,
    subsets: [],
    pairs: [],
  };
  for (const line of readLines('params.txt')) {
    const [key, ...v] = line.split(' ');
    const nums = v.map(Number);
    switch (key) {
      case 'PRIOR':
        settings.prior = v[0] === 'uniform' ? 'uniform' : 'empirical';
        break;
      case 'VAR_SMOOTHING':
        settings.epsilon = nums[0];
        break;
      case 'SMOOTHING_GRID':
        settings.smoothingGrid = nums;
        break;
      case 'QDA_GAMMA':
        settings.gamma = nums[0];
        break;
      case 'GAMMA_GRID':
        settings.gammaGrid = nums;
        break;
      case 'CV_FOLDS':
        settings.folds = nums[0];
        break;
      case 'CALIBRATION_EDGES':
        settings.calibration = nums;
        break;
      case 'REJECT_THRESHOLDS':
        settings.reject = nums;
        break;
      case 'CURVE':
        settings.curve = nums;
        break;
      case 'OUTLIER_THRESHOLD':
        settings.outlier = nums[0];
        break;
      case 'BOOTSTRAP':
        [settings.resamples, settings.seed] = nums;
        break;
      case 'MAP_SIZE':
        [settings.width, settings.height] = nums;
        break;
      case 'PLOT_SIZE':
        [settings.plotWidth, settings.plotHeight] = nums;
        break;
      case 'SUBSET':
        settings.subsets.push({
          name: v[0],
          features: v.slice(1).map((name) => features.indexOf(name)),
        });
        break;
      case 'PAIR':
        settings.pairs.push(v.map((name) => features.indexOf(name)));
        break;
    }
  }
  return { features, classes, train, test, costs, settings };
}
