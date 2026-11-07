import { mkdirSync, writeFileSync } from 'node:fs';

export type Fraction = [bigint, bigint];
export function fraction(
  value: number | bigint | Fraction,
  denominator: number | bigint = 1,
): string {
  let n: bigint;
  let d: bigint;
  if (Array.isArray(value)) [n, d] = value;
  else {
    n = BigInt(value);
    d = BigInt(denominator);
  }
  const negative = n < 0n;
  if (negative) n = -n;
  let a = n;
  let b = d;
  while (b !== 0n) [a, b] = [b, a % b];
  n /= a;
  d /= a;
  const t = (10000n * n) / d;
  const decimal = `${t / 10000n}.${String(t % 10000n).padStart(4, '0')}`;
  return `${negative ? '-' : ''}${n}/${d}=${negative && t !== 0n ? '-' : ''}${decimal}`;
}
export function percentage(numerator: number, denominator: number): string {
  const t = (10000n * BigInt(numerator)) / BigInt(denominator);
  return `${t / 100n}.${String(t % 100n).padStart(2, '0')}%`;
}
export const list = (values: string[]): string => (values.length ? values.join(',') : '-');
export function writeOutputs(files: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(files)) {
    writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
}
