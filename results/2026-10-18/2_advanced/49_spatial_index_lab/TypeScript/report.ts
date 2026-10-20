import { writeFileSync } from 'node:fs';

export function fraction(numerator: number, denominator: number): string {
    let a = numerator, b = denominator; while (b !== 0) [a, b] = [b, a % b]; return `${numerator / a}/${denominator / a}`;
}
export const ids = (values: readonly (number | string)[]): string => values.length ? values.join(' ') : '-';
export function writeLines(filename: string, lines: string[]): void { writeFileSync('output/' + filename, lines.length ? lines.join('\n') + '\n' : '', 'ascii'); }
