import { mkdirSync, writeFileSync } from 'node:fs';

export function gcd(a: number, b: number): number { while (b) [a, b] = [b, a % b]; return a; }
export function fraction(a: number, b: number): string {
  const divisor = gcd(Math.abs(a), b); return `${a / divisor}/${b / divisor}`;
}
export const root = (value: number) => value === Infinity ? '-' : Math.sqrt(value).toFixed(3);
export function ariValue(numerator: number, denominator: number): string {
  const text = (numerator / denominator).toFixed(4); return text === '-0.0000' ? '0.0000' : text;
}
export function frame(rows: string[]): string[] {
  const border = '+' + '-'.repeat(rows[0].length) + '+';
  return [border, ...rows.map(row => '|' + row + '|'), border];
}
export function writeReport(name: string, lines: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
