import { mkdirSync, writeFileSync } from 'node:fs';

export function real(value: number | null, digits: number): string { if (value === null) return 'none'; if (Math.abs(value) >= 1e21) return BigInt(value).toString() + (digits ? '.' + '0'.repeat(digits) : ''); const text = value.toFixed(digits); return Number(text) === 0 ? (0).toFixed(digits) : text; }
export function plotLines(cells: string[][], heights: number[]): string[] {
    const labels = heights.map(h => real(h / 100, 2)), width = Math.max(...labels.map(s => s.length));
    return [...cells.map((row, i) => labels[i].padStart(width) + ' |' + row.join('') + '|'), ' '.repeat(width) + ' +' + cells[0].map((_, c) => c % 6 === 0 ? '+' : '-').join('') + '+'];
}
export function writeFiles(files: Record<string, string[]>): void { mkdirSync('output', { recursive: true }); for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii'); }
