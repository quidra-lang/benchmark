import { readFileSync } from 'node:fs';
export type Kernel = 'epanechnikov' | 'biweight' | 'triweight';
export type Direction = 'increasing' | 'decreasing';
export interface Point { X: number; Y: number; x: number; y: number }
export interface Series { name: string; points: Point[]; mode: Direction | 'auto' }
export interface Candidate { text: string; value: number; hundredths?: number }
export interface Estimate { value: number | null; weights: number[] | null }
export interface Fit { yhat: number[] | null; lev: number[] | null; edf: number | null; at: (position: number) => Estimate }
export interface Settings {
  windows: Candidate[]; kernels: Kernel[]; bandwidths: Candidate[]; degrees: number[]; spans: Candidate[];
  robustIterations: number; lambdas: Candidate[]; folds: number; directions: (Direction | 'auto')[]; gridPoints: number;
  bandZ: number; bandMethods: string[]; threshold: number; bootstrap: number; trim: number; seed: number;
  plotSeries: string[]; plotMethods: string[]; width: number; height: number;
}
export function hundredths(text: string): number { return Number(text.replace('.', '')); }
export function readInput() {
  const lines = (name: string) => readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
  const fields = new Map(lines('params.txt').map(line => { const [name, ...v] = line.split(' '); return [name, v]; }));
  const p = (name: string) => fields.get(name)!, integer = (name: string) => +p(name)[0];
  const decimals = (name: string) => p(name).map(text => { const h = hundredths(text); return { text, value: h / 100, hundredths: h }; });
  const settings: Settings = {
    windows: p('WINDOWS').map(text => ({ text, value: +text })), kernels: p('KERNELS') as Kernel[], bandwidths: decimals('BANDWIDTHS'),
    degrees: p('LOESS_DEGREES').map(Number), spans: decimals('SPANS'), robustIterations: integer('ROBUST_ITERATIONS'),
    lambdas: p('LAMBDAS').map(text => ({ text, value: +text })), folds: integer('CV_FOLDS'), directions: p('ISOTONIC') as (Direction | 'auto')[],
    gridPoints: integer('GRID_POINTS'), bandZ: +p('BAND_Z')[0], bandMethods: p('BAND_METHODS'), threshold: hundredths(p('OUTLIER_THRESHOLD')[0]),
    bootstrap: +p('BOOTSTRAP')[0], trim: +p('BOOTSTRAP')[1], seed: +p('BOOTSTRAP')[2], plotSeries: p('PLOT_SERIES'),
    plotMethods: p('PLOT_METHODS'), width: +p('PLOT_SIZE')[0], height: +p('PLOT_SIZE')[1],
  };
  const byName = new Map<string, Series>();
  for (const line of lines('series.csv').slice(1)) {
    const [name, rawX, rawY] = line.split(',');
    let series = byName.get(name);
    if (!series) { series = { name, points: [], mode: settings.directions[byName.size] }; byName.set(name, series); }
    const X = hundredths(rawX), Y = hundredths(rawY); series.points.push({ X, Y, x: X / 100, y: Y / 100 });
  }
  const series = [...byName.values()]; for (const s of series) s.points.sort((a, b) => a.X - b.X);
  const tests = lines('test_points.csv').slice(1).map(line => { const [name, rawX] = line.split(','); return { name, X: hundredths(rawX) }; });
  return { settings, series, tests };
}
