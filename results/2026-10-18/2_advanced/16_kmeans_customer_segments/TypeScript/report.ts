import { mkdirSync, writeFileSync } from 'node:fs';
export function real(value: number | null): string {
  if (value === null) return '-';
  let text = Math.abs(value).toFixed(4);
  if (text.includes('e')) text = BigInt(Math.abs(value)).toString() + '.0000';
  return value < 0 && /[1-9]/.test(text) ? '-' + text : text;
}
export const rounded = (value: number) => Number(real(value));
export function amount(value: number): string {
  const magnitude = Math.abs(value);
  return (value < 0 ? '-' : '') + Math.floor(magnitude / 100) + '.' + String(magnitude % 100).padStart(2, '0');
}
export function writeReport(name: string, lines: string[]) {
  mkdirSync('output', { recursive: true });
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
