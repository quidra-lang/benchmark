import { mkdirSync, writeFileSync } from 'node:fs';
export function real(v: number | null, digits = 4): string { if (v === null) return '-'; if (Math.abs(v) >= 1e21) return BigInt(v).toString() + '.' + '0'.repeat(digits); const text = v.toFixed(digits); return +text === 0 ? (0).toFixed(digits) : text; }
export function frame(rows: string[][]): string[] { const edge = '+' + '-'.repeat(rows[0].length) + '+'; return [edge, ...rows.map(r => '|' + r.join('') + '|'), edge]; }
export function write(name: string, lines: string[]): void { mkdirSync('output', { recursive: true }); writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii'); }
