import { mkdirSync, writeFileSync } from 'node:fs';
import type { BinaryRow, MultiRow } from './dataset.ts';
export function fixed(value: number | null, digits = 4): string {
  if (value === null) return '-';
  const magnitude = Math.abs(value);
  const text =
    magnitude >= 1e21 ? BigInt(magnitude) + '.' + '0'.repeat(digits) : magnitude.toFixed(digits);
  return value < 0 && Number(text) !== 0 ? '-' + text : text;
}
export const ratio = (a: number, b: number): string => (b > 0 ? fixed(a / b) : '-');
export const prediction = (score: number): number => (score > 0 ? 1 : -1);
export function auc(rows: BinaryRow[], scores: number[]): string {
  let positive = 0;
  let negative = 0;
  let wins = 0;
  let ties = 0;
  for (const row of rows) {
    if (row.label === 1) positive++;
    else negative++;
  }
  for (let a = 0; a < rows.length; a++) {
    if (rows[a].label === 1) {
      for (let b = 0; b < rows.length; b++) {
        if (rows[b].label === -1) {
          if (scores[a] > scores[b]) wins++;
          else if (scores[a] === scores[b]) ties++;
        }
      }
    }
  }
  return ratio(2 * wins + ties, 2 * positive * negative);
}
export function confusion(rows: MultiRow[], predictions: number[], classes: number): number[][] {
  const matrix = Array.from({ length: classes }, () => Array<number>(classes).fill(0));
  rows.forEach((row, i) => {
    matrix[row.category - 1][predictions[i] - 1]++;
  });
  return matrix;
}
export const countAtMost = (values: number[], threshold: number): number =>
  values.filter((v) => v <= threshold).length;
export function writeLines(name: string, lines: string[]): void {
  mkdirSync('output', { recursive: true });
  writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
