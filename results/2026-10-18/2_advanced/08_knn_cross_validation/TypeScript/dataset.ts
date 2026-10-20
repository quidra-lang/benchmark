import { readFileSync } from 'node:fs';

export type ScalingMethod = 'standard' | 'minmax';
export type Metric = 'squared_euclidean' | 'manhattan' | 'chebyshev' | 'cosine';
export type Weighting = 'uniform' | 'distance';
export interface Row { id: string; features: number[]; label: string | null; target: number | null; index: number }
export interface TrainingRow extends Row { label: string; target: number }
export interface Settings {
  scalings: ScalingMethod[]; ks: number[]; metrics: Metric[]; weightings: Weighting[];
  folds: number; editK: number; curve: number[]; bins: number[]; top: number;
}
export interface Dataset { features: string[]; train: TrainingRow[]; test: Row[]; settings: Settings }
export interface Model { k: number; metric: Metric; weighting: Weighting; scaling: ScalingMethod; order: number }

const lines = (name: string) => readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);
function parseRow(line: string, index: number): Row {
  const cells = line.split(','), label = cells[cells.length - 2], target = cells[cells.length - 1];
  return { id: cells[0], features: cells.slice(1, -2).map(Number), label: label || null,
    target: target === '' ? null : Number(target), index };
}
function choice<T extends string>(text: string, values: readonly T[]): T { return values.find(value => value === text)!; }
export function readDataset(): Dataset {
  const training = lines('train.csv'), params = new Map(lines('params.txt').map(line => {
    const [key, ...values] = line.split(' '); return [key, values];
  }));
  const values = (key: string) => params.get(key)!;
  const train = training.slice(1).map((line, index): TrainingRow => {
    const row = parseRow(line, index); return { ...row, label: row.label!, target: row.target! };
  });
  return { features: training[0].split(',').slice(1, -2), train, test: lines('test.csv').slice(1).map(parseRow), settings: {
    scalings: values('SCALINGS').map(value => choice(value, ['standard', 'minmax'] as const)),
    ks: values('K_VALUES').map(Number),
    metrics: values('METRICS').map(value => choice(value, ['squared_euclidean', 'manhattan', 'chebyshev', 'cosine'] as const)),
    weightings: values('WEIGHTINGS').map(value => choice(value, ['uniform', 'distance'] as const)),
    folds: Number(values('FOLDS')[0]), editK: Number(values('EDIT_K')[0]), curve: values('CURVE').map(Number),
    bins: values('BINS').map(Number), top: Number(values('TOP')[0]) } };
}
