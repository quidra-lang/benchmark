import { writeFileSync } from 'node:fs';
import type { Fraction } from './evaluation.ts';
export function real(v: number) {
  if (Math.abs(v) >= 1e21) return BigInt(v).toString() + '.0000';
  const text = v.toFixed(4);
  return text === '-0.0000' ? '0.0000' : text;
}
export const fractionText = (v: Fraction | null) =>
  v === null ? '-' : `${v[0]}/${v[1]} ${real(v[0] / v[1])}`;
export function frame(rows: string[][]) {
  const border = '+' + '-'.repeat(rows[0].length) + '+';
  return [border, ...rows.map((r) => '|' + r.join('') + '|'), border];
}
export const cell = (v: number, low: number, high: number, size: number) =>
  Math.floor(((v - low) / (high - low)) * (size - 1) + 0.5);
export function writeLines(name: string, lines: string[]) {
  writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
