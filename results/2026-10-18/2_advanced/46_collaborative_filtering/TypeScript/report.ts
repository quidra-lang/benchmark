import { writeFileSync } from 'node:fs';
export function real(v: number | null): string { if (v === null) return '-'; if (Math.abs(v) >= 1e21) return BigInt(v).toString() + '.0000'; const text = v.toFixed(4); return +text === 0 ? '0.0000' : text; }
export function writeLines(name: string, lines: string[]): void { writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii'); }
