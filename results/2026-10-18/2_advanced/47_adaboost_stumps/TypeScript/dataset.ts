import { readFileSync } from 'node:fs';
export interface ValuesRow {
  values: number[];
}
export interface BinaryRow extends ValuesRow {
  id: string;
  label: number;
}
export interface MultiRow extends ValuesRow {
  id: string;
  category: number;
}
export type Variant = 'discrete' | 'real' | 'gentle' | 'logit';
export interface Parameters {
  rounds: number;
  variants: Variant[];
  bins: number;
  smoothing: number;
  convergence: number;
  clip: number;
  folds: number;
  margins: number[];
  classes: number;
  sammeRounds: number;
  permutationRepeats: number;
  permutationSeed: number;
  noiseSeed: number;
  noise: number[];
  sizes: number[];
  shrinkage: number[];
  bootstrapSamples: number;
  bootstrapSeed: number;
}
const readLines = (name: string) =>
  readFileSync('input/' + name, 'ascii')
    .split('\n')
    .slice(0, -1);
function binaryRows(lines: string[]): BinaryRow[] {
  return lines.slice(1).map((line) => {
    const fields = line.split(',');
    return {
      id: fields[0],
      values: fields.slice(1, -1).map(Number),
      label: Number(fields[fields.length - 1]),
    };
  });
}
function variant(name: string): Variant {
  if (name === 'discrete' || name === 'real' || name === 'gentle' || name === 'logit') return name;
  throw new Error('Unknown variant');
}
export function readDataset() {
  const trainLines = readLines('train.csv');
  const testLines = readLines('test.csv');
  const multiLines = readLines('multiclass.csv');
  const multiTrain: MultiRow[] = [];
  const multiTest: MultiRow[] = [];
  for (const line of multiLines.slice(1)) {
    const fields = line.split(',');
    const row = {
      id: fields[0],
      values: fields.slice(1, -2).map(Number),
      category: Number(fields[fields.length - 2]),
    };
    (fields[fields.length - 1] === 'train' ? multiTrain : multiTest).push(row);
  }
  const s = readLines('params.txt').map((line) => line.split(' ').slice(1));
  const params: Parameters = {
    rounds: Number(s[0][0]),
    variants: s[1].map(variant),
    bins: Number(s[2][0]),
    smoothing: Number(s[3][0]),
    convergence: Number(s[4][0]),
    clip: Number(s[5][0]),
    folds: Number(s[6][0]),
    margins: s[7].map(Number),
    classes: Number(s[8][0]),
    sammeRounds: Number(s[9][0]),
    permutationRepeats: Number(s[10][0]),
    permutationSeed: Number(s[10][1]),
    noiseSeed: Number(s[11][0]),
    noise: s[11].slice(1).map(Number),
    sizes: s[12].map(Number),
    shrinkage: s[13].map(Number),
    bootstrapSamples: Number(s[14][0]),
    bootstrapSeed: Number(s[14][1]),
  };
  return {
    features: trainLines[0].split(',').slice(1, -1),
    train: binaryRows(trainLines),
    test: binaryRows(testLines),
    multiFeatures: multiLines[0].split(',').slice(1, -2),
    multiTrain,
    multiTest,
    params,
  };
}
