import { mkdirSync, writeFileSync } from 'node:fs';
import { itemsetKey } from './baskets.ts';
import type { Fraction, Rule } from './rules.ts';
export const quotient = (n: number | bigint, d: number | bigint) => Number(BigInt(n) / BigInt(d));
export function fraction(value: Fraction): string {
  const negative = value.numerator < 0n;
  const n = negative ? -value.numerator : value.numerator;
  const t = (10000n * n) / value.denominator;
  return `${negative ? '-' : ''}${n}/${value.denominator}=${negative && t !== 0n ? '-' : ''}${t / 10000n}.${String(t % 10000n).padStart(4, '0')}`;
}
export function percentage(n: number, d: number): string {
  const t = (10000n * BigInt(n)) / BigInt(d);
  return `${t / 100n}.${String(t % 100n).padStart(2, '0')}%`;
}
export function money(cents: number): string {
  const n = BigInt(cents);
  return `${n / 100n}.${String(n % 100n).padStart(2, '0')}`;
}
export function ruleLines(rules: Rule[]): string[] {
  return [
    'rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement',
    ...rules.map((r) =>
      [
        r.rank,
        itemsetKey(r.antecedent),
        itemsetKey(r.consequent),
        r.count,
        fraction(r.support),
        fraction(r.confidence),
        fraction(r.lift),
        fraction(r.leverage),
        r.conviction === null ? 'INF' : fraction(r.conviction),
        fraction(r.improvement),
      ].join(','),
    ),
  ];
}
export function writeFiles(files: Record<string, string[]>) {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(files)) {
    writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
  }
}
