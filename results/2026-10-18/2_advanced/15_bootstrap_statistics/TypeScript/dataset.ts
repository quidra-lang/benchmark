import { readFileSync } from 'node:fs';

export interface Group {
  name: string;
  sample: number[];
}
export interface Pair {
  x: Group;
  y: Group;
}
export interface Settings {
  seed: number;
  bootstrap: number;
  permutations: number;
  confidence: number;
  pilot: number;
  simulations: number;
  innerPermutations: number;
  bins: number;
}
export interface Dataset {
  groups: Group[];
  pairs: Pair[];
  before: number[];
  after: number[];
  differences: number[];
  settings: Settings;
}
function lines(name: string): string[] {
  return readFileSync(`input/${name}`, 'ascii').slice(0, -1).split('\n');
}
function hundredths(text: string): number {
  const [whole, fraction = ''] = text.split('.');
  return Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
}
export function readDataset(): Dataset {
  const groups: Group[] = [];
  const byName = new Map<string, Group>();
  for (const line of lines('samples.csv').slice(1)) {
    const [name, value] = line.split(',');
    let group = byName.get(name);
    if (!group) {
      group = { name, sample: [] };
      byName.set(name, group);
      groups.push(group);
    }
    group.sample.push(hundredths(value));
  }
  const before: number[] = [];
  const after: number[] = [];
  const differences: number[] = [];
  for (const line of lines('paired.csv').slice(1)) {
    const fields = line.split(',');
    const b = hundredths(fields[1]);
    const a = hundredths(fields[2]);
    before.push(b);
    after.push(a);
    differences.push(a - b);
  }
  const params = lines('params.txt').map((line) => line.split(' '));
  const settings: Settings = {
    seed: Number(params[0][1]),
    bootstrap: Number(params[1][1]),
    permutations: Number(params[2][1]),
    confidence: Number(params[3][1]),
    pilot: Number(params[4][1]),
    simulations: Number(params[5][1]),
    innerPermutations: Number(params[5][2]),
    bins: Number(params[6][1]),
  };
  const pairs = params
    .slice(7)
    .map((fields) => ({ x: byName.get(fields[1])!, y: byName.get(fields[2])! }));
  return { groups, pairs, before, after, differences, settings };
}
