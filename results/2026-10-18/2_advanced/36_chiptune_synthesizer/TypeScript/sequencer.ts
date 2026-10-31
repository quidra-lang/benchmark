import type { Song } from './song_parser.ts';
export const samplesPerTick = (rate: number, tempo: number): number =>
  Math.floor((rate * 5) / (tempo * 2));
export interface RowAddress {
  position: number;
  row: number;
}
export type NextRow =
  | { reason: 'stop'; position: number; row: number }
  | { reason: 'finished' }
  | { reason: 'next'; position: number; row: number };

export function nextRow(song: Song, position: number, row: number): NextRow {
  const cells = song.patterns.get(song.order[position])![row];
  let jump: number | null = null;
  let breakRow: number | null = null;
  let stop = false;
  for (const { effect } of cells) {
    if (effect?.name === 'F' && effect.argument === 0) stop = true;
    if (effect?.name === 'B') jump = effect.argument;
    if (effect?.name === 'D') breakRow = effect.argument >= 64 ? 0 : effect.argument;
  }
  if (stop) return { reason: 'stop', position, row };
  let nextPosition: number;
  let next: number;
  if (jump !== null || breakRow !== null) {
    nextPosition = jump ?? position + 1;
    next = breakRow ?? 0;
  } else {
    nextPosition = row === 63 ? position + 1 : position;
    next = row === 63 ? 0 : row + 1;
  }
  return nextPosition >= song.order.length
    ? { reason: 'finished' }
    : { reason: 'next', position: nextPosition, row: next };
}
export function reachableRows(song: Song): Set<string> {
  const reachable = new Set<string>();
  let current: NextRow = { reason: 'next', position: 0, row: 0 };
  while (current.reason === 'next') {
    const key = current.position + ',' + current.row;
    if (reachable.has(key)) break;
    reachable.add(key);
    current = nextRow(song, current.position, current.row);
  }
  return reachable;
}
