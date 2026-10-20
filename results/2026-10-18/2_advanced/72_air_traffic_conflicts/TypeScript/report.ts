import { mkdirSync, writeFileSync } from 'node:fs';
export function decimal(value: number, digits = 3) { const scale = 10 ** digits, rounded = Math.floor(Math.abs(value) * scale + 0.5) / scale, text = rounded.toFixed(digits); return value < 0 && rounded !== 0 ? '-' + text : text; }
export const signed = (value: number) => value > 0 ? '+' + value : String(value);
export function chart(rows: string[]) { const border = '+' + '-'.repeat(rows[0].length) + '+'; return [border, ...rows.map(row => '|' + row + '|'), border]; }
export function writeLines(file: string, lines: string[]) { mkdirSync('output', { recursive: true }); writeFileSync(`output/${file}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii'); }
