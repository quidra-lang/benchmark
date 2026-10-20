import { readFileSync } from 'node:fs';

export interface Variable { name: string; states: string[]; parents: number[]; given?: number[][] }
export type Method = 'MINFILL' | 'GIVEN';
export interface Settings { alpha: number; method: Method; order: number[]; limit: number; seed: number; sources: ('GIVEN' | 'LEARNED')[] }
const readLines = (path: string) => readFileSync(path, 'ascii').slice(0, -1).split('\n');
export function readInputs(): { variables: Variable[]; samples: number[][]; queries: string[]; settings: Settings } {
  const variables: Variable[] = [], names = new Map<string, number>();
  const network = readLines('input/network.txt').filter(line => line !== '' && !line.startsWith('#'));
  for (let i = 0; i < network.length; i++) {
    const [kind, name, ...values] = network[i].split(' ');
    if (kind === 'VARIABLE') { names.set(name, variables.length); variables.push({ name, states: values, parents: [] }); }
    else if (kind === 'PARENTS') variables[names.get(name)!].parents = values.map(value => names.get(value)!);
    else if (kind === 'CPT') {
      const variable = variables[names.get(name)!]; let rows = 1;
      for (const parent of variable.parents) rows *= variables[parent].states.length;
      variable.given = [];
      for (let row = 0; row < rows; row++) variable.given.push(network[++i].split(' ').map(Number));
    }
  }
  const csv = readLines('input/samples.csv'), header = csv[0].split(',').map(name => names.get(name)!);
  const samples = csv.slice(1).map(line => {
    const sample = Array<number>(variables.length).fill(0);
    line.split(',').forEach((state, column) => { const v = header[column]; sample[v] = variables[v].states.indexOf(state); });
    return sample;
  });
  const params = readLines('input/params.txt').map(line => line.split(' '));
  const settings: Settings = { alpha: +params[0][1], method: params[1][1] === 'MINFILL' ? 'MINFILL' : 'GIVEN', order: params[2].slice(1).map(name => names.get(name)!), limit: +params[3][1], seed: +params[4][1], sources: params.slice(5).map(fields => fields[2] === 'GIVEN' ? 'GIVEN' : 'LEARNED') };
  return { variables, samples, queries: readLines('input/queries.txt'), settings };
}
