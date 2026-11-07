import { UNKNOWN, FILLED, EMPTY } from './line_solver';
import type { Grid, CellState } from './line_solver';
import type { Clue } from './clues';
import { propagate, determinedCount } from './propagation';

export interface Coordinate {
  r: number;
  c: number;
}
export interface GuessRecord extends Coordinate {
  number: number;
  depth: number;
  value: CellState;
  solves: number;
  known: number;
  outcome: string;
}
export interface SearchResult {
  guesses: number;
  maxDepth: number;
  backtracks: number;
  lineSolves: number;
  record: GuessRecord[];
  solutions: Grid[];
}

export function chooseCell(grid: Grid): Coordinate | null {
  const h = grid.length;
  const w = grid[0].length;
  const rowUnknown = Array<number>(h).fill(0);
  const columnUnknown = Array<number>(w).fill(0);
  for (let r = 0; r < h; r++) {
    for (let c = 0; c < w; c++) {
      if (grid[r][c] === UNKNOWN) {
        rowUnknown[r]++;
        columnUnknown[c]++;
      }
    }
  }
  let best = h + w + 1;
  let chosen: Coordinate | null = null;
  for (let r = 0; r < h; r++) {
    for (let c = 0; c < w; c++) {
      if (grid[r][c] === UNKNOWN && rowUnknown[r] + columnUnknown[c] < best) {
        best = rowUnknown[r] + columnUnknown[c];
        chosen = { r, c };
      }
    }
  }
  return chosen;
}

export function search(grid: Grid, rows: Clue[], columns: Clue[]): SearchResult {
  const result: SearchResult = {
    guesses: 0,
    maxDepth: 0,
    backtracks: 0,
    lineSolves: 0,
    record: [],
    solutions: [],
  };
  function visit(parent: Grid, depth: number): boolean {
    const chosen = chooseCell(parent);
    if (chosen === null) throw new Error('Search requires an unknown cell');
    const { r, c } = chosen;
    const values: CellState[] = [FILLED, EMPTY];
    for (const value of values) {
      const number = ++result.guesses;
      result.maxDepth = Math.max(result.maxDepth, depth);
      const child = parent.map((row) => row.slice());
      child[r][c] = value;
      const rowMarks = rows.map(() => false);
      const columnMarks = columns.map(() => false);
      rowMarks[r] = true;
      columnMarks[c] = true;
      const propagation = propagate(child, rows, columns, 'precise', rowMarks, columnMarks);
      const known = determinedCount(child);
      const solves = propagation.record.length;
      result.lineSolves += solves;
      let outcome: string;
      if (propagation.conflict !== null) {
        outcome = 'contradiction at=' + propagation.conflict.label;
        result.backtracks++;
      } else if (known === rows.length * columns.length) {
        result.solutions.push(child);
        outcome = 'solution' + result.solutions.length;
      } else outcome = 'open';
      result.record.push({ number, depth, r, c, value, solves, known, outcome });
      if (result.solutions.length === 2) return true;
      if (outcome === 'open' && visit(child, depth + 1)) return true;
    }
    return false;
  }
  visit(grid, 1);
  return result;
}
