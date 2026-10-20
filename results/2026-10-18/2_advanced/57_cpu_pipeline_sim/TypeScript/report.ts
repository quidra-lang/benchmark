import { mkdirSync, writeFileSync } from 'node:fs';

const rounded = (p: number, q: number) => Math.floor((2 * p * 10000 + q) / (2 * q));
export function decimal(p: number, q: number): string {
  const n = rounded(p, q);
  return `${Math.floor(n / 10000)}.${String(n % 10000).padStart(4, '0')}`;
}
export function percentage(p: number, q: number): string {
  if (!q) return '-';
  const n = rounded(p, q);
  return `${Math.floor(n / 100)}.${String(n % 100).padStart(2, '0')}`;
}
export function fraction(p: number, q: number): string {
  let a = p;
  let b = q;
  while (b) [a, b] = [b, a % b];
  return `${p / a}/${q / a}`;
}
export const hex = (value: number) => value.toString(16).padStart(8, '0');
export function diagramRow(
  instruction: number | undefined,
  pc: number,
  kind: string,
  cells: Map<number, string>,
  start: number,
  end: number,
  annotation: string,
): string {
  const number = instruction === undefined ? '     -' : String(instruction).padStart(6);
  const characters: string[] = [];
  for (let cycle = start; cycle <= end; cycle++) characters.push(cells.get(cycle) ?? '.');
  return `${number} ${hex(pc)} ${kind.padEnd(6)} ${characters.join('')}${annotation}`;
}
export function cycleDigits(start: number, end: number): string {
  let result = 'cycle' + ' '.repeat(18);
  for (let cycle = start; cycle <= end; cycle++) result += cycle % 10;
  return result;
}
export function writeReport(name: string, lines: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}
