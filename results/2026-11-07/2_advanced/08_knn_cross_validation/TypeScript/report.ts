import { mkdirSync, writeFileSync } from 'node:fs';
export function real(value: number | null, digits = 4): string {
  if (value === null) return '-';
  let text = Math.abs(value).toFixed(digits);
  if (text.includes('e')) text = BigInt(Math.abs(value)).toString() + '.' + '0'.repeat(digits);
  return value < 0 && /[1-9]/.test(text) ? '-' + text : text;
}
export const rounded = (value: number) => Number(real(value));
export const ratio = (a: number, b: number) => `${a}/${b} ${real(a / b)}`;
export function fractionMetric(a: number, b: number): string {
  if (b === 0) return '- -';
  if (a === 0) return '0/1 0.0000';
  let x = a;
  let y = b;
  while (y !== 0) [x, y] = [y, x % y];
  return `${a / x}/${b / x} ${real(a / b)}`;
}
export function writeReport(name: string, lines: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}
