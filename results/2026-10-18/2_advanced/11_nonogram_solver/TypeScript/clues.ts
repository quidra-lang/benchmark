import { FILLED } from './line_solver';
import type { CellState } from './line_solver';

export type Clue = number[];

export function runClue(line: readonly CellState[]): Clue {
  const blocks: number[] = [];
  let length = 0;
  for (const state of line) {
    if (state === FILLED) length++;
    else if (length > 0) { blocks.push(length); length = 0; }
  }
  if (length > 0) blocks.push(length);
  return blocks;
}
export const spaceForm = (clue: readonly number[]): string => clue.length === 0 ? '0' : clue.join(' ');
export const commaForm = (clue: readonly number[]): string => clue.length === 0 ? '0' : clue.join(',');

export function parseClue(text: string): Clue | null {
  if (text === '0') return [];
  if (!/^[1-9][0-9]?( [1-9][0-9]?)*$/.test(text)) return null;
  return text.split(' ').map(Number);
}
export function minimumLength(clue: readonly number[]): number {
  return clue.length === 0 ? 0 : clue.reduce((sum, block) => sum + block, clue.length - 1);
}
export const fits = (clue: readonly number[], length: number): boolean => minimumLength(clue) <= length;
