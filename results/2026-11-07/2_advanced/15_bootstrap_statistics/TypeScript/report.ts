import { mkdirSync, writeFileSync } from 'node:fs';
import { reduced } from './tests.ts';

export function real(value: number): string {
  const text = value.toFixed(4);
  return Number(text) === 0 ? '0.0000' : text;
}
export function pValue(numerator: number, denominator: number): string {
  const [a, b] = reduced(numerator, denominator);
  return `${a}/${b} ${real(a / b)}`;
}
export function numberList(numbers: number[]): string {
  return numbers.length ? numbers.join(' ') : 'none';
}
export function binNumber(value: number, lo: number, hi: number, count: number): number {
  return Math.min(Math.floor((count * (value - lo)) / (hi - lo)), count - 1) + 1;
}
export function bar(count: number, top: number): string {
  return '#'.repeat(Math.floor((40 * count + top - 1) / top));
}
export function writeLines(name: string, lines: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
