import { mkdirSync, writeFileSync } from 'node:fs';
export function real(value: number, digits = 6): string {
  const text = value.toFixed(digits);
  return Number(text) === 0 ? (0).toFixed(digits) : text;
}
export function roundedInteger(value: number, digits = 6): number {
  return Number(real(value, digits).replace('.', ''));
}
export function fraction(numerator: number, denominator: number): string {
  let first = Math.abs(numerator);
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  const top = numerator / first;
  const bottom = denominator / first;
  return `${top}/${bottom} ${real(top / bottom, 4)}`;
}
export function writeReports(reports: Record<string, string[]>) {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    writeFileSync(`output/${name}`, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
  }
}
