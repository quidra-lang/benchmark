import { UNKNOWN, FILLED } from './line_solver';
import type { Grid, CellState } from './line_solver';
import { spaceForm } from './clues';
import type { Clue } from './clues';

export interface NamedGrid { name: string; grid: Grid }
export const stateChar = (state: CellState): string => state === UNKNOWN ? '?' : state === FILLED ? '#' : '.';
export const stateString = (line: readonly CellState[]): string => line.map(stateChar).join('');

export function sideBySide(grids: NamedGrid[]): string[] {
  if (grids.length === 0) return [];
  const lines = ['grid ' + grids.map(item => item.name).join(' ')];
  for (let r = 0; r < grids[0].grid.length; r++) lines.push(grids.map(item => stateString(item.grid[r])).join(' | '));
  return lines;
}

export function answerSheet(grid: Grid, rows: Clue[], columns: Clue[]): string[] {
  const tokens = columns.map(clue => spaceForm(clue).split(' ')), rowText = rows.map(spaceForm);
  let width = 0, depth = 0, prefix = 0;
  for (const column of tokens) {
    depth = Math.max(depth, column.length);
    for (const token of column) width = Math.max(width, token.length + 1);
  }
  for (const text of rowText) prefix = Math.max(prefix, text.length);
  const lines: string[] = [];
  for (let t = 0; t < depth; t++) {
    let line = ' '.repeat(prefix);
    for (const column of tokens) {
      const index = t - (depth - column.length);
      line += index < 0 ? ' '.repeat(width) : column[index].padStart(width, ' ');
    }
    lines.push(line.replace(/ +$/, ''));
  }
  for (let r = 0; r < grid.length; r++) {
    let line = rowText[r].padStart(prefix, ' ');
    for (const cell of grid[r]) line += ' '.repeat(width - 1) + stateChar(cell);
    lines.push(line);
  }
  return lines;
}
