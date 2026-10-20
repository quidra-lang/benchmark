import { UNKNOWN, solveLine } from './line_solver';
import type { Grid, CellState, SolveKind } from './line_solver';
import type { Clue } from './clues';

export type Axis = 'R' | 'C';
export interface SolveRecord { label: string; gain: number | null }
export interface Conflict { axis: Axis; index: number; label: string }
export interface Propagation { grid: Grid; record: SolveRecord[]; conflict: Conflict | null }

export function getLine(grid: Grid, axis: Axis, index: number): CellState[] {
  return axis === 'R' ? grid[index].slice() : grid.map(row => row[index]);
}
export function determinedCount(grid: Grid): number {
  let count = 0;
  for (const row of grid) for (const state of row) if (state !== UNKNOWN) count++;
  return count;
}

export function propagate(grid: Grid, rows: Clue[], columns: Clue[], kind: SolveKind,
  rowMarks?: boolean[], columnMarks?: boolean[]): Propagation {
  const markedRows = rowMarks === undefined ? rows.map(() => true) : rowMarks.slice();
  const markedColumns = columnMarks === undefined ? columns.map(() => true) : columnMarks.slice();
  const record: SolveRecord[] = [];
  for (;;) {
    let axis: Axis = 'R', index = markedRows.indexOf(true);
    if (index === -1) { axis = 'C'; index = markedColumns.indexOf(true); }
    if (index === -1) return { grid, record, conflict: null };
    (axis === 'R' ? markedRows : markedColumns)[index] = false;
    const label = axis + (index + 1), line = getLine(grid, axis, index);
    const clue = axis === 'R' ? rows[index] : columns[index];
    const solved = solveLine(line, clue, kind);
    if (solved === null) {
      record.push({ label, gain: null });
      return { grid, record, conflict: { axis, index, label } };
    }
    record.push({ label, gain: solved.gain });
    for (let p = 0; p < line.length; p++) {
      if (line[p] !== UNKNOWN || solved.line[p] === UNKNOWN) continue;
      if (axis === 'R') { grid[index][p] = solved.line[p]; markedColumns[p] = true; }
      else { grid[p][index] = solved.line[p]; markedRows[p] = true; }
    }
  }
}
