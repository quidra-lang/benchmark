import { mkdirSync, writeFileSync } from 'node:fs';
export type Fraction = readonly [number, number];
export function real(value: number, digits = 4): string {
  const text = value.toFixed(digits);
  return +text === 0 ? (0).toFixed(digits) : text;
}
export function decimalValue(value: number, digits = 4): number { return +real(value, digits); }
export function fraction(n: number, d: number): Fraction {
  if (d < 0) { n = -n; d = -d; }
  let a = Math.abs(n), b = d;
  while (b) [a, b] = [b, a % b];
  return [n / a, d / a];
}
export function fractionText(f: Fraction): string { return `${f[0]}/${f[1]}`; }
export function fractionReal(f: Fraction, digits = 4): string {
  const n = BigInt(Math.abs(f[0])) * 10n ** BigInt(digits), d = BigInt(f[1]);
  let rounded = n / d;
  if (2n * (n % d) >= d) rounded++;
  const text = rounded.toString().padStart(digits + 1, '0'), sign = f[0] < 0 && rounded !== 0n ? '-' : '';
  return sign + (digits ? text.slice(0, -digits) + '.' + text.slice(-digits) : text);
}
export function writeReports(reports: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}
