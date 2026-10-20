import { readFileSync } from 'node:fs';
export type Missing = 'listwise' | 'mean';
export type Scaling = 'covariance' | 'correlation';
export type Criterion = 'kaiser' | 'broken_stick' | 'parallel' | 'cumulative';
export interface Row { id: string; values: (number | null)[] }
export interface Settings {
  missing: Missing; scaling: Scaling; components: number | Criterion; target: number; parallel: number; seed: number;
  t2Limit: number; speLimit: number; cycles: number; top: number; screeWidth: number; biplotWidth: number; biplotHeight: number;
  radius: number; diagnosticWidth: number; diagnosticHeight: number;
}
export function readDataset() {
  const lines = (name: string) => readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
  const input = lines('data.csv'), names = input[0].split(',').slice(1);
  const rows = (input: string[]): Row[] => input.slice(1).map(line => { const [id, ...v] = line.split(','); return { id, values: v.map(x => x === 'NA' ? null : +x) }; });
  const parameters = new Map(lines('params.txt').map(line => { const [k, ...v] = line.split(' '); return [k, v]; }));
  const p = (k: string) => parameters.get(k)!, n = (k: string) => +p(k)[0], rule = p('COMPONENTS')[0];
  const settings: Settings = { missing: p('MISSING')[0] as Missing, scaling: p('SCALING')[0] as Scaling,
    components: /^[0-9]+$/.test(rule) ? +rule : rule as Criterion, target: n('CUMULATIVE_TARGET'), parallel: n('PARALLEL'), seed: +p('PARALLEL')[1],
    t2Limit: n('T2_LIMIT'), speLimit: n('SPE_LIMIT'), cycles: n('VARIMAX_CYCLES'), top: n('TOP_ROWS'), screeWidth: n('SCREE_WIDTH'),
    biplotWidth: n('BIPLOT_SIZE'), biplotHeight: +p('BIPLOT_SIZE')[1], radius: n('CIRCLE_RADIUS'),
    diagnosticWidth: n('DIAGNOSTIC_SIZE'), diagnosticHeight: +p('DIAGNOSTIC_SIZE')[1] };
  return { names, rows: rows(input), supplementary: rows(lines('supplementary.csv')), settings };
}
export type Dataset = ReturnType<typeof readDataset>;
