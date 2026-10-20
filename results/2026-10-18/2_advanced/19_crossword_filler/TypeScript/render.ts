import type { State } from './filler.ts';
import type { Slot } from './slots.ts';
import type { WordEntry } from './word_index.ts';
export interface GridLayout { h: number; w: number; rows: string[]; numbers: number[] }
export function decimal(n: number, d: number, digits: number): string {
    const p = BigInt(n), q = BigInt(d), scale = 10n ** BigInt(digits), rounded = (2n * p * scale + q) / (2n * q);
    return `${rounded / scale}.${String(rounded % scale).padStart(digits, '0')}`;
}
export function gridLines(template: GridLayout, state: State): string[] {
    return Array.from({ length: template.h }, (_, r) => state.cells.slice(r * template.w, (r + 1) * template.w).join(''));
}
export function numberDiagram(template: GridLayout): string[] {
    return template.rows.map((row, r) => [...row].map((cell, c) => {
        const number = template.numbers[r * template.w + c];
        return cell === '#' ? '##' : number ? String(number).padStart(2, ' ') : ' .';
    }).join(' '));
}
export function listLine(slot: Slot, word: WordEntry | null, clue: string | null, pattern: string, theme: boolean): string {
    if (word === null) return `${slot.number}. (unfilled) (${slot.length}) ${pattern} -`;
    return `${slot.number}. ${clue ?? '(no clue)'} (${slot.length}) ${word.word} ${word.score}${theme ? ' theme' : ''}`;
}
