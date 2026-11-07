import { readFileSync } from 'node:fs';

export const classes = ['ALU', 'MUL', 'LOAD', 'STORE', 'BRANCH', 'JUMP', 'NOP'] as const;
export type InstructionClass = (typeof classes)[number];
export interface Instruction {
  number: number;
  line: number;
  pc: number;
  kind: InstructionClass;
  rd?: number;
  rs1?: number;
  rs2?: number;
  outcome: 'T' | 'N' | '-';
  target?: number;
  address?: number;
}
export type Predictor = { name: string } & (
  | { scheme: 'STATIC_NT' | 'BTFN' | 'PERFECT' }
  | { scheme: 'ONEBIT' | 'TWOBIT'; size: number }
  | { scheme: 'GSHARE'; size: number; history: number }
  | { scheme: 'TOURNAMENT'; local: number; global: number; history: number; chooser: number }
);
export interface Variant {
  name: string;
  forwarding: boolean;
  stage: 'ID' | 'EX';
  latency: number;
}
export interface Configuration {
  btb: number;
  ras: number;
  predictors: Predictor[];
  variants: Variant[];
  primaryVariant: string;
  primaryPredictor: string;
  start: number;
  end: number;
  top: number;
  interval: number;
}
export const isClass = (value: string): value is InstructionClass =>
  classes.some((kind) => kind === value);
export const parseHex = (value: string): number | undefined =>
  /^[0-9a-f]{8}$/.test(value) ? parseInt(value, 16) : undefined;
export const validRegister = (value: string) =>
  value === '-' || /^r([0-9]|[12][0-9]|3[01])$/.test(value);
export const parseRegister = (value: string): number | undefined =>
  value === '-' ? undefined : +value.slice(1);
export function readInputs(): { lines: string[]; config: Configuration } {
  const lines = readFileSync('input/trace.txt', 'ascii').slice(0, -1).split('\n');
  const config: Configuration = {
    btb: 0,
    ras: 0,
    predictors: [],
    variants: [],
    primaryVariant: '',
    primaryPredictor: '',
    start: 0,
    end: 0,
    top: 0,
    interval: 0,
  };
  for (const line of readFileSync('input/config.txt', 'ascii').trimEnd().split('\n')) {
    const [kind, ...t] = line.split(' ');
    if (kind === 'BTB') config.btb = +t[0];
    else if (kind === 'RAS') config.ras = +t[0];
    else if (kind === 'PRIMARY') {
      config.primaryVariant = t[0];
      config.primaryPredictor = t[1];
    } else if (kind === 'WINDOW') {
      config.start = +t[0];
      config.end = +t[1];
    } else if (kind === 'TOP') config.top = +t[0];
    else if (kind === 'INTERVAL') config.interval = +t[0];
    else if (kind === 'VARIANT') {
      config.variants.push({
        name: t[0],
        forwarding: t[1] === 'ON',
        stage: t[2] === 'ID' ? 'ID' : 'EX',
        latency: +t[3],
      });
    } else if (kind === 'PREDICTOR') {
      const name = t[0];
      const scheme = t[1];
      if (scheme === 'STATIC_NT' || scheme === 'BTFN' || scheme === 'PERFECT') {
        config.predictors.push({ name, scheme });
      } else if (scheme === 'ONEBIT' || scheme === 'TWOBIT') {
        config.predictors.push({ name, scheme, size: +t[2] });
      } else if (scheme === 'GSHARE') {
        config.predictors.push({ name, scheme, size: +t[2], history: +t[3] });
      } else if (scheme === 'TOURNAMENT') {
        config.predictors.push({
          name,
          scheme,
          local: +t[2],
          global: +t[3],
          history: +t[4],
          chooser: +t[5],
        });
      }
    }
  }
  return { lines, config };
}
