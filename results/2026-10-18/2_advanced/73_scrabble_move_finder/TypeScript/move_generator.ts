import * as board from './board.ts';
import type { Grid, Tile, Word } from './board.ts';
import type { Node } from './dictionary_trie.ts';
import { Trie } from './dictionary_trie.ts';
import { crossWord } from './scoring.ts';
export interface Move extends Word {
  tiles: Tile[];
}
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
export function anchors(grid: Grid) {
  const result = new Set<number>();
  if (!board.tiles(grid).length) result.add(board.CENTER * board.SIZE + board.CENTER);
  else {
    for (let r = 0; r < board.SIZE; r++) {
      for (let c = 0; c < board.SIZE; c++) {
        if (grid[r][c] === '.' && board.adjacent(grid, r, c)) result.add(r * board.SIZE + c);
      }
    }
  }
  return result;
}
export function crossChecks(grid: Grid, trie: Trie) {
  const allowed: (Set<string> | null)[][] = Array.from({ length: board.SIZE }, () =>
    Array(board.SIZE).fill(null),
  );
  let checked = 0;
  let dead = 0;
  let total = 0;
  for (let row = 0; row < board.SIZE; row++) {
    for (let column = 0; column < board.SIZE; column++) {
      if (grid[row][column] !== '.') continue;
      const letters = new Set<string>();
      if (!board.occupied(grid, row - 1, column) && !board.occupied(grid, row + 1, column)) {
        for (const letter of ALPHABET) letters.add(letter);
      } else {
        checked++;
        for (const letter of ALPHABET) {
          if (trie.has(crossWord(grid, { row, column, letter }, 'down').word.toUpperCase())) {
            letters.add(letter);
          }
        }
        if (!letters.size) dead++;
        total += letters.size;
      }
      allowed[row][column] = letters;
    }
  }
  return { allowed, stats: [checked, dead, total] };
}
function acrossMoves(
  grid: Grid,
  rack: string,
  trie: Trie,
  anchorSet: Set<number>,
  checks: ReturnType<typeof crossChecks>,
) {
  const result: Move[] = [];
  const counts = new Map<string, number>();
  for (const tile of rack) counts.set(tile, (counts.get(tile) ?? 0) + 1);
  for (const anchor of anchorSet) {
    const row = Math.floor(anchor / board.SIZE);
    const anchorColumn = anchor % board.SIZE;
    function choices(
      node: Node,
      allowed: Set<string> | null,
      use: (node: Node, letter: string) => void,
    ) {
      for (const letter of [...node.children.keys()].sort()) {
        if (allowed !== null && !allowed.has(letter)) continue;
        for (const tile of [letter, '?']) {
          if (!(counts.get(tile) ?? 0)) continue;
          counts.set(tile, counts.get(tile)! - 1);
          use(node.children.get(letter)!, tile === '?' ? letter.toLowerCase() : letter);
          counts.set(tile, counts.get(tile)! + 1);
        }
      }
    }
    function extend(column: number, node: Node, word: string, start: number, filled: boolean) {
      const occupied = column < board.SIZE && grid[row][column] !== '.';
      if (!occupied && filled && node.terminal) {
        const tiles: Tile[] = [];
        for (let i = 0; i < word.length; i++) {
          if (grid[row][start + i] === '.') tiles.push({ row, column: start + i, letter: word[i] });
        }
        result.push({ row, column: start, direction: 'across', word, tiles });
      }
      if (column >= board.SIZE) return;
      if (occupied) {
        const letter = grid[row][column];
        const child = node.children.get(letter.toUpperCase());
        if (child) extend(column + 1, child, word + letter, start, filled);
      } else {
        choices(node, checks.allowed[row][column], (child, letter) =>
          extend(column + 1, child, word + letter, start, filled || column === anchorColumn),
        );
      }
    }
    if (board.occupied(grid, row, anchorColumn - 1)) {
      let start = anchorColumn - 1;
      while (board.occupied(grid, row, start - 1)) start--;
      const prefix = grid[row].slice(start, anchorColumn).join('');
      const node = trie.find(prefix.toUpperCase());
      if (node) extend(anchorColumn, node, prefix, start, false);
    } else {
      let limit = 0;
      while (
        anchorColumn - limit - 1 >= 0 &&
        grid[row][anchorColumn - limit - 1] === '.' &&
        !anchorSet.has(row * board.SIZE + anchorColumn - limit - 1)
      ) {
        limit++;
      }
      const leftPart = (node: Node, word: string) => {
        extend(anchorColumn, node, word, anchorColumn - word.length, false);
        if (word.length < limit) {
          choices(node, null, (child, letter) => leftPart(child, word + letter));
        }
      };
      leftPart(trie.root, '');
    }
  }
  return result;
}
export function generate(grid: Grid, rack: string, trie: Trie) {
  const anchorSet = anchors(grid);
  const across = crossChecks(grid, trie);
  const transposed = board.transpose(grid);
  const down = crossChecks(transposed, trie);
  const moves = acrossMoves(grid, rack, trie, anchorSet, across);
  for (const move of acrossMoves(transposed, rack, trie, anchors(transposed), down)) {
    const tiles = board.transposeTiles(move.tiles);
    if (
      tiles.length === 1 &&
      (board.occupied(grid, tiles[0].row, tiles[0].column - 1) ||
        board.occupied(grid, tiles[0].row, tiles[0].column + 1))
    ) {
      continue;
    }
    moves.push({ ...move, row: move.column, column: move.row, direction: 'down', tiles });
  }
  return { moves, anchors: anchorSet.size, across: across.stats, down: down.stats };
}
