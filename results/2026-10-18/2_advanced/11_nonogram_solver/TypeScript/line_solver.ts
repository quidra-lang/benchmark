export const UNKNOWN = 0;
export const FILLED = 1;
export const EMPTY = 2;
export type CellState = typeof UNKNOWN | typeof FILLED | typeof EMPTY;
export type Grid = CellState[][];
export type SolveKind = 'simple' | 'precise';
interface PlacementInfo {
  possibleFilled: boolean[];
  possibleEmpty: boolean[];
  minimum: number[];
  maximum: number[];
}
export interface LineResult {
  line: CellState[];
  gain: number;
}
const cache = new Map<string, PlacementInfo | null>();

function placementInfo(line: readonly CellState[], clue: readonly number[]): PlacementInfo | null {
  const key = line.join('') + '/' + clue.join(',');
  const known = cache.get(key);
  if (known !== undefined) return known;
  const n = line.length;
  const count = clue.length;
  const filledPrefix = Array<number>(n + 1).fill(0);
  const emptyPrefix = Array<number>(n + 1).fill(0);
  for (let p = 0; p < n; p++) {
    filledPrefix[p + 1] = filledPrefix[p] + (line[p] === FILLED ? 1 : 0);
    emptyPrefix[p + 1] = emptyPrefix[p] + (line[p] === EMPTY ? 1 : 0);
  }
  const reserve = Array<number>(count).fill(0);
  for (let b = count - 1; b >= 0; b--) {
    reserve[b] = clue[b] + (b + 1 < count ? 1 + reserve[b + 1] : 0);
  }
  const feasible = Array.from({ length: count + 1 }, () => Array<boolean>(n + 1).fill(false));
  for (let p = 0; p <= n; p++) feasible[count][p] = filledPrefix[n] === filledPrefix[p];
  const nextPosition = (b: number, start: number): number =>
    start + clue[b] + (b + 1 < count ? 1 : 0);
  function transition(b: number, position: number, start: number): boolean {
    const end = start + clue[b];
    return (
      filledPrefix[start] === filledPrefix[position] &&
      emptyPrefix[end] === emptyPrefix[start] &&
      (b + 1 === count || line[end] !== FILLED) &&
      feasible[b + 1][nextPosition(b, start)]
    );
  }
  // Suffix feasibility includes the empty gap preceding each block and its separator.
  for (let b = count - 1; b >= 0; b--) {
    for (let p = n; p >= 0; p--) {
      for (let start = p; start <= n - reserve[b]; start++) {
        if (transition(b, p, start)) {
          feasible[b][p] = true;
          break;
        }
      }
    }
  }
  let info: PlacementInfo | null = null;
  if (feasible[0][0]) {
    const possibleFilled = Array<boolean>(n).fill(false);
    const possibleEmpty = Array<boolean>(n).fill(false);
    const minimum = Array<number>(count).fill(n);
    const maximum = Array<number>(count).fill(-1);
    const reachable = Array.from({ length: count + 1 }, () => Array<boolean>(n + 1).fill(false));
    reachable[0][0] = true;
    // A reachable transition with a feasible suffix belongs to a full consistent placement.
    for (let b = 0; b < count; b++) {
      for (let p = 0; p <= n; p++) {
        if (!reachable[b][p]) continue;
        for (let start = p; start <= n - reserve[b]; start++) {
          if (!transition(b, p, start)) continue;
          const end = start + clue[b];
          minimum[b] = Math.min(minimum[b], start);
          maximum[b] = Math.max(maximum[b], start);
          for (let cell = p; cell < start; cell++) possibleEmpty[cell] = true;
          for (let cell = start; cell < end; cell++) possibleFilled[cell] = true;
          if (b + 1 < count) possibleEmpty[end] = true;
          reachable[b + 1][nextPosition(b, start)] = true;
        }
      }
    }
    for (let p = 0; p <= n; p++) {
      if (reachable[count][p]) for (let cell = p; cell < n; cell++) possibleEmpty[cell] = true;
    }
    info = { possibleFilled, possibleEmpty, minimum, maximum };
  }
  if (cache.size >= 8192) cache.clear();
  cache.set(key, info);
  return info;
}

export function hasPlacement(line: readonly CellState[], clue: readonly number[]): boolean {
  return placementInfo(line, clue) !== null;
}

export function solveLine(
  line: readonly CellState[],
  clue: readonly number[],
  kind: SolveKind,
): LineResult | null {
  const info = placementInfo(line, clue);
  if (info === null) return null;
  const result = line.slice();
  let gain = 0;
  for (let p = 0; p < line.length; p++) {
    if (line[p] !== UNKNOWN) continue;
    if (kind === 'precise') {
      if (!info.possibleEmpty[p]) result[p] = FILLED;
      else if (!info.possibleFilled[p]) result[p] = EMPTY;
    } else {
      let covered = false;
      let overlap = false;
      for (let b = 0; b < clue.length; b++) {
        if (info.minimum[b] <= p && p < info.maximum[b] + clue[b]) covered = true;
        if (info.maximum[b] <= p && p < info.minimum[b] + clue[b]) overlap = true;
      }
      if (overlap) result[p] = FILLED;
      else if (!covered) result[p] = EMPTY;
    }
    if (result[p] !== UNKNOWN) gain++;
  }
  return { line: result, gain };
}
