export const SIZE = 15;
export const CENTER = 7;
export type Grid = string[][];
export type Direction = 'across' | 'down';
export interface Point {
  row: number;
  column: number;
}
export interface Tile extends Point {
  letter: string;
}
export interface Position extends Point {
  direction: Direction;
}
export interface Word extends Position {
  word: string;
}
export const PREMIUMS = [
  '# . . + . . . # . . . + . . #',
  '. * . . . ^ . . . ^ . . . * .',
  '. . * . . . + . + . . . * . .',
  '+ . . * . . . + . . . * . . +',
  '. . . . * . . . . . * . . . .',
  '. ^ . . . ^ . . . ^ . . . ^ .',
  '. . + . . . + . + . . . + . .',
  '# . . + . . . * . . . + . . #',
  '. . + . . . + . + . . . + . .',
  '. ^ . . . ^ . . . ^ . . . ^ .',
  '. . . . * . . . . . * . . . .',
  '+ . . * . . . + . . . * . . +',
  '. . * . . . + . + . . . * . .',
  '. * . . . ^ . . . ^ . . . * .',
  '# . . + . . . # . . . + . . #',
].map((line) => line.split(' '));
export const inside = (r: number, c: number) => r >= 0 && r < SIZE && c >= 0 && c < SIZE;
export const occupied = (grid: Grid, r: number, c: number) => inside(r, c) && grid[r][c] !== '.';
export const square = (r: number, c: number) => String.fromCharCode(65 + c) + (r + 1);
export const position = (r: number, c: number, dir: Direction) =>
  dir === 'across' ? r + 1 + String.fromCharCode(65 + c) : square(r, c);
export const empty = (): Grid => Array.from({ length: SIZE }, () => Array(SIZE).fill('.'));
export const clone = (grid: Grid) => grid.map((row) => row.slice());
export const transpose = (grid: Grid) =>
  Array.from({ length: SIZE }, (_, row) => grid.map((line) => line[row]));
export const transposeTiles = (tiles: Tile[]) =>
  tiles.map((tile) => ({ ...tile, row: tile.column, column: tile.row }));
export function parsePosition(text: string): Position | null {
  let m = /^([1-9]|1[0-5])([A-O])$/.exec(text);
  if (m) return { row: Number(m[1]) - 1, column: m[2].charCodeAt(0) - 65, direction: 'across' };
  m = /^([A-O])([1-9]|1[0-5])$/.exec(text);
  return m ? { row: Number(m[2]) - 1, column: m[1].charCodeAt(0) - 65, direction: 'down' } : null;
}
export function tiles(grid: Grid) {
  const result: Tile[] = [];
  for (let row = 0; row < SIZE; row++) {
    for (let column = 0; column < SIZE; column++) {
      if (grid[row][column] !== '.') result.push({ row, column, letter: grid[row][column] });
    }
  }
  return result;
}
export const adjacent = (grid: Grid, r: number, c: number) =>
  [
    [-1, 0],
    [1, 0],
    [0, -1],
    [0, 1],
  ].some(([dr, dc]) => occupied(grid, r + dr, c + dc));
export function connected(grid: Grid) {
  const placed = tiles(grid);
  if (!placed.length) return true;
  const queue: Point[] = [placed[0]];
  const seen = new Set([placed[0].row * SIZE + placed[0].column]);
  for (let i = 0; i < queue.length; i++) {
    for (const [dr, dc] of [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ]) {
      const row = queue[i].row + dr;
      const column = queue[i].column + dc;
      const key = row * SIZE + column;
      if (occupied(grid, row, column) && !seen.has(key)) {
        seen.add(key);
        queue.push({ row, column });
      }
    }
  }
  return seen.size === placed.length;
}
export function words(grid: Grid) {
  const result: Word[] = [];
  for (const direction of ['across', 'down'] as const) {
    const oriented = direction === 'across' ? grid : transpose(grid);
    for (let row = 0; row < SIZE; row++) {
      let column = 0;
      while (column < SIZE) {
        if (oriented[row][column] === '.') {
          column++;
          continue;
        }
        const start = column;
        let word = '';
        while (column < SIZE && oriented[row][column] !== '.') word += oriented[row][column++];
        if (word.length >= 2) {
          result.push(
            direction === 'across'
              ? { row, column: start, direction, word }
              : { row: start, column: row, direction, word },
          );
        }
      }
    }
  }
  return result;
}
export function display(grid: Grid) {
  const lines = [
    '   ' + Array.from({ length: SIZE }, (_, i) => String.fromCharCode(65 + i)).join(' '),
  ];
  for (let r = 0; r < SIZE; r++) {
    lines.push(
      String(r + 1).padStart(2) +
        ' ' +
        grid[r].map((letter, c) => (letter === '.' ? PREMIUMS[r][c] : letter)).join(' '),
    );
  }
  return lines;
}
