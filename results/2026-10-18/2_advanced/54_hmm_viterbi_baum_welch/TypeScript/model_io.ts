import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
export interface Model { name: string; pi: number[]; a: number[][]; b: number[][] }
export interface Alphabet { states: string[]; symbols: string[]; missing: string }
export interface Sequence { name: string; obs: number[] }
export interface Labeled extends Sequence { path: number[]; role: 'TRAIN' | 'TEST' }
export function normalize(values: number[]): number[] { let total = 0; for (const v of values) total += v; return values.map(v => v / total); }
export function readInput() {
  const lines = (name: string) => readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
  const rows = lines('model.txt').map(line => line.split(' ')), states = rows[0].slice(1), symbols = rows[1].slice(1), missing = rows[2][1], k = states.length;
  const model: Model = { name: 'INITIAL', pi: normalize(rows[3].slice(1).map(Number)), a: rows.slice(4, 4 + k).map(r => normalize(r.slice(2).map(Number))), b: rows.slice(4 + k).map(r => normalize(r.slice(2).map(Number))) };
  return { alphabet: { states, symbols, missing }, model, sequences: lines('sequences.txt').map(line => line.split(' ')), labeled: lines('labeled.txt'),
    parameters: new Map(lines('params.txt').map((line): [string, string[]] => { const [key, ...v] = line.split(' '); return [key, v]; })) };
}
export function real(v: number | null, digits = 4): string { if (v === null) return '-'; if (Math.abs(v) >= 1e21) return BigInt(v).toString() + '.' + '0'.repeat(digits); const text = v.toFixed(digits); return +text === 0 ? (0).toFixed(digits) : text; }
export function modelLines(m: Model, alphabet: Alphabet): string[] {
  const reals = (v: number[]) => v.map(x => real(x)).join(' ');
  return [`MODEL ${m.name}`, 'STATES ' + alphabet.states.join(' '), 'SYMBOLS ' + alphabet.symbols.join(' '), 'MISSING ' + alphabet.missing, 'INITIAL ' + reals(m.pi),
    ...m.a.map((row, i) => `TRANSITION ${alphabet.states[i]} ${reals(row)}`), ...m.b.map((row, i) => `EMISSION ${alphabet.states[i]} ${reals(row)}`)];
}
export function write(name: string, lines: string[]): void { mkdirSync('output', { recursive: true }); writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii'); }
