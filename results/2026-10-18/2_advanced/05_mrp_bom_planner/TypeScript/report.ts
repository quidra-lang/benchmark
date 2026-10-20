import { mkdirSync, writeFileSync } from 'node:fs';
export function floorRatio(a: number, b: number): number { return Number(BigInt(a) / BigInt(b)); }
export function ceilRatio(a: number, b: number): number { const n = BigInt(a), d = BigInt(b); return Number(n / d + (n % d === 0n ? 0n : 1n)); }
export function roundRatio(a: number, b: number): number { return Number((2n * BigInt(a) + BigInt(b)) / (2n * BigInt(b))); }
export function money(cents: number): string { const n = BigInt(cents); return `${n / 100n}.${String(n % 100n).padStart(2, '0')}`; }
export const percentage = (quantity: number, capacity: number): number => roundRatio(100 * quantity, capacity);
export function tableRow(label: string, values: number[], width: number): string {
  return label.padEnd(10, ' ') + values.map(n => String(n).padStart(width, ' ')).join('');
}
export function writeReports(reports: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
