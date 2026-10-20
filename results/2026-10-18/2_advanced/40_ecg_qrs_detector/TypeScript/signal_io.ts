import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';

export type Label = 'N' | 'V' | 'A';
export interface Annotation {
  sample: number;
  label: Label;
}
export interface Settings {
  refractory: number;
  twave: number;
  searchback: number;
  premature: number;
  qrsWidth: number;
  match: number;
  pause: number;
  brady: number;
  tachy: number;
  excerpt: number;
  segment: number;
  stripStart: number;
  stripLength: number;
  stripRows: number;
  chartRows: number;
  poincareSize: number;
}
const lines = (name: string): string[] =>
  readFileSync('input/' + name, 'ascii')
    .split('\n')
    .slice(0, -1);
export function readInput() {
  const signal = lines('ecg.csv')
    .slice(1)
    .map((line) => Number(line.split(',')[1]));
  const annotations: Annotation[] = lines('annotations.csv')
    .slice(1)
    .map((line) => {
      const [sample, label] = line.split(',');
      if (label !== 'N' && label !== 'V' && label !== 'A') {
        throw new Error('Invalid annotation label');
      }
      return { sample: Number(sample), label };
    });
  const parameters = new Map(
    lines('params.txt').map((line) => {
      const [name, value] = line.split(' ');
      return [name, Number(value)];
    }),
  );
  const p = (name: string): number => parameters.get(name)!;
  const settings: Settings = {
    refractory: p('refractory_ms'),
    twave: p('twave_ms'),
    searchback: p('searchback_percent'),
    premature: p('premature_percent'),
    qrsWidth: p('qrs_width_ms'),
    match: p('match_ms'),
    pause: p('pause_ms'),
    brady: p('brady_ms'),
    tachy: p('tachy_ms'),
    excerpt: p('excerpt_ms'),
    segment: p('segment_ms'),
    stripStart: p('strip_start_ms'),
    stripLength: p('strip_ms'),
    stripRows: p('strip_rows'),
    chartRows: p('chart_rows'),
    poincareSize: p('poincare_size'),
  };
  return { signal, annotations, settings };
}
export function writeReports(reports: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, rows] of Object.entries(reports)) {
    writeFileSync('output/' + name, rows.length ? rows.join('\n') + '\n' : '', 'ascii');
  }
}
