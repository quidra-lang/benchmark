import { readFileSync } from 'node:fs';
export const COMMANDS = ['ALLOC', 'PUSH', 'LOAD', 'POP', 'SET', 'OVERWRITE', 'CHECKPOINT'] as const;
export type Command =
  | { op: 'ALLOC'; line: number; p: number; d: number; number: number }
  | { op: 'PUSH'; line: number; r: number | null }
  | { op: 'LOAD'; line: number; i: number; f: number }
  | { op: 'POP'; line: number; n: number }
  | { op: 'SET'; line: number; i: number; f: number; r: number | null }
  | { op: 'OVERWRITE'; line: number; i: number; r: number | null }
  | { op: 'CHECKPOINT'; line: number; label: string };
export type CollectorDefinition =
  | { name: string; type: 'MARK_SWEEP' | 'MARK_COMPACT' | 'COPYING' | 'REFCOUNT' }
  | { name: string; type: 'GENERATIONAL'; young: number; age: number };
export interface Settings {
  heap: number;
  collectors: CollectorDefinition[];
  maps: Set<string>;
  windows: number[];
  width: number;
}
export function readInputs() {
  const settings: Settings = { heap: 0, collectors: [], maps: new Set(), windows: [], width: 0 };
  for (const row of readFileSync('input/config.txt', 'ascii').slice(0, -1).split('\n')) {
    const f = row.split(' ');
    switch (f[0]) {
      case 'HEAP':
        settings.heap = Number(f[1]);
        break;
      case 'WIDTH':
        settings.width = Number(f[1]);
        break;
      case 'MAPS':
        settings.maps = new Set(f.slice(1));
        break;
      case 'MMU':
        settings.windows = f.slice(1).map(Number);
        break;
      case 'COLLECTOR': {
        if (f[2] === 'GENERATIONAL') {
          settings.collectors.push({
            name: f[1],
            type: f[2],
            young: Number(f[3]),
            age: Number(f[4]),
          });
        } else if (
          f[2] === 'MARK_SWEEP' ||
          f[2] === 'MARK_COMPACT' ||
          f[2] === 'COPYING' ||
          f[2] === 'REFCOUNT'
        ) {
          settings.collectors.push({ name: f[1], type: f[2] });
        }
        break;
      }
    }
  }
  return { settings, lines: readFileSync('input/mutator.txt', 'ascii').slice(0, -1).split('\n') };
}
export function parseCommand(text: string, line: number): Command | { reason: string } {
  const [op, ...f] = text.split(' ');
  const number = /^(0|[1-9][0-9]{0,3})$/;
  const forms: Record<string, string[]> = {
    ALLOC: ['n', 'n'],
    PUSH: ['r'],
    LOAD: ['n', 'n'],
    POP: ['n'],
    SET: ['n', 'n', 'r'],
    OVERWRITE: ['n', 'r'],
    CHECKPOINT: ['label'],
  };
  const form = Object.hasOwn(forms, op) ? forms[op] : undefined;
  if (
    !form ||
    form.length !== f.length ||
    f.some((s, i) =>
      form[i] === 'label'
        ? !/^[a-z0-9_]{1,16}$/.test(s)
        : !(form[i] === 'r' && s === '-') && !number.test(s),
    )
  ) {
    return { reason: 'syntax' };
  }
  const r = (i: number) => (f[i] === '-' ? null : Number(f[i]));
  switch (op) {
    case 'ALLOC':
      return Number(f[0]) > 6 || Number(f[1]) > 24
        ? { reason: 'range' }
        : { op, line, p: Number(f[0]), d: Number(f[1]), number: 0 };
    case 'PUSH':
      return { op, line, r: r(0) };
    case 'LOAD':
      return { op, line, i: Number(f[0]), f: Number(f[1]) };
    case 'POP':
      return Number(f[0]) === 0 ? { reason: 'range' } : { op, line, n: Number(f[0]) };
    case 'SET':
      return { op, line, i: Number(f[0]), f: Number(f[1]), r: r(2) };
    case 'OVERWRITE':
      return { op, line, i: Number(f[0]), r: r(1) };
    default:
      return { op: 'CHECKPOINT', line, label: f[0] };
  }
}
