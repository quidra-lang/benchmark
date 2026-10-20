import { writeFileSync } from 'node:fs';
import { splitTime } from './day_rules.ts';
import type { Period, Transition } from './resolver.ts';
const two = (n: number) => String(n).padStart(2, '0');
export function localTime(value: number) {
  const t = splitTime(value);
  return `${String(t.year).padStart(4, '0')}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}`;
}
export const utc = (n: number) => localTime(n) + 'Z';
export function offset(n: number) {
  const a = Math.abs(n);
  return (
    (n < 0 ? '-' : '+') +
    two(Math.floor(a / 3600)) +
    ':' +
    two(Math.floor((a % 3600) / 60)) +
    (a % 60 ? ':' + two(a % 60) : '')
  );
}
export function duration(n: number) {
  const a = Math.abs(n);
  return (
    (n < 0 ? '-' : '') +
    Math.floor(a / 3600) +
    ':' +
    two(Math.floor((a % 3600) / 60)) +
    ':' +
    two(a % 60)
  );
}
export const clock = (n: number) =>
  Math.floor(n / 3600) + ':' + two(Math.floor((n % 3600) / 60)) + (n % 60 ? ':' + two(n % 60) : '');
export const state = (p: Period) =>
  `${offset(p.offset)} ${p.dst ? 'DST' : 'STD'} ${p.abbreviation}`;
export const change = (t: Transition) => `${utc(t.time)} ${state(t.before)} -> ${state(t.after)}`;
export function writeLines(name: string, lines: string[]) {
  writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
export function writeBlocks(name: string, blocks: string[][]) {
  writeFileSync(
    'output/' + name,
    blocks.length ? blocks.map((b) => b.join('\n')).join('\n\n') + '\n' : '',
    'ascii',
  );
}
