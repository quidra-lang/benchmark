import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { runClue, spaceForm, commaForm, parseClue, minimumLength, fits } from './clues';
import type { Clue } from './clues';
import { UNKNOWN, FILLED, EMPTY, hasPlacement } from './line_solver';
import type { CellState, Grid, SolveKind } from './line_solver';
import { getLine, determinedCount, propagate } from './propagation';
import type { Axis, Propagation, SolveRecord } from './propagation';
import { chooseCell, search } from './search';
import type { Coordinate, SearchResult } from './search';
import { stateChar, stateString, sideBySide, answerSheet } from './render';
import type { NamedGrid } from './render';

interface Given extends Coordinate { state: CellState }
interface RawGiven extends Coordinate { character: string }
interface RawPuzzle {
  name: string; w: number; h: number; rowLines: string[]; columnLines: string[];
  givens: RawGiven[]; answer: string[] | null;
}
interface ClueSet { name: string; w: number; h: number; rows: Clue[]; columns: Clue[] }
interface Puzzle extends ClueSet { givens: Given[]; answer: Grid | null }
interface Picture { name: string; picture: string[] }
type Validation<T> = { value: T } | { error: string };
type Status = 'contradiction' | 'none' | 'unique' | 'multiple';
type Difficulty = '-' | 'easy' | 'medium' | 'hard';
interface LogicalResult extends Propagation { known: number; result: string }
interface Analysis {
  simple: LogicalResult; logic: LogicalResult; search: SearchResult | null; solutions: Grid[];
  status: Status; difficulty: Difficulty; lineSolves: number; guesses: number; maxDepth: number;
}
interface Grade {
  grid: Grid; rows: number[]; columns: number[]; givens: number[]; known: number;
  result: 'partial' | 'wrong' | 'correct'; extendable: 'yes' | 'no'; differs: number;
}
interface Ranking { puzzle: Puzzle; analysis: Analysis; score: number }

function toState(character: string): CellState {
  return character === '#' ? FILLED : character === '.' ? EMPTY : UNKNOWN;
}

function readPuzzles(text: string): RawPuzzle[] {
  const lines = text.split('\n'), blocks: RawPuzzle[] = [];
  let cursor = 0;
  while (cursor < lines.length) {
    const header = lines[cursor++];
    if (header === '' || header.startsWith('#')) continue;
    const name = header.slice(7), size = lines[cursor++].split(' ');
    const w = Number(size[1]), h = Number(size[2]);
    cursor++; // ROWS
    const rowLines: string[] = [], columnLines: string[] = [];
    while (lines[cursor] !== 'COLUMNS') rowLines.push(lines[cursor++]);
    cursor++;
    while (lines[cursor] !== 'END' && lines[cursor] !== 'ANSWER' && !lines[cursor].startsWith('GIVEN ')) {
      columnLines.push(lines[cursor++]);
    }
    const givens: RawGiven[] = [];
    while (lines[cursor].startsWith('GIVEN ')) {
      const fields = lines[cursor++].split(' ');
      givens.push({ r: Number(fields[1]) - 1, c: Number(fields[2]) - 1, character: fields[3] });
    }
    let answer: string[] | null = null;
    if (lines[cursor] === 'ANSWER') {
      cursor++;
      answer = [];
      while (lines[cursor] !== 'END') answer.push(lines[cursor++]);
    }
    cursor++;
    blocks.push({ name, w, h, rowLines, columnLines, givens, answer });
  }
  return blocks;
}

function readPictures(text: string): Picture[] {
  const lines = text.split('\n'), blocks: Picture[] = [];
  let cursor = 0;
  while (cursor < lines.length) {
    const header = lines[cursor++];
    if (header === '' || header.startsWith('#')) continue;
    const name = header.slice(8), picture: string[] = [];
    while (lines[cursor] !== 'END') picture.push(lines[cursor++]);
    cursor++;
    blocks.push({ name, picture });
  }
  return blocks;
}

function validatePuzzle(raw: RawPuzzle, seen: Set<string>): Validation<Puzzle> {
  const { name, w, h, rowLines, columnLines, givens, answer } = raw;
  const duplicate = seen.has(name);
  seen.add(name);
  if (!/^[a-z0-9_]{1,20}$/.test(name)) return { error: 'bad name' };
  if (duplicate) return { error: 'duplicate name' };
  if (w < 1 || w > 30 || h < 1 || h > 30) return { error: 'bad size' };
  if (rowLines.length !== h) return { error: `row count ${rowLines.length} expected ${h}` };
  if (columnLines.length !== w) return { error: `column count ${columnLines.length} expected ${w}` };
  const rows: Clue[] = [], columns: Clue[] = [];
  const groups = [
    { kind: 'row', texts: rowLines, length: w, clues: rows },
    { kind: 'column', texts: columnLines, length: h, clues: columns },
  ];
  for (const { kind, texts, length, clues } of groups) {
    for (let index = 0; index < texts.length; index++) {
      const clue = parseClue(texts[index]);
      if (clue === null) return { error: `bad clue ${kind} ${index + 1}` };
      if (!fits(clue, length)) return { error: `${kind} ${index + 1} too long` };
      clues.push(clue);
    }
  }
  let rowTotal = 0, columnTotal = 0;
  for (const clue of rows) for (const block of clue) rowTotal += block;
  for (const clue of columns) for (const block of clue) columnTotal += block;
  if (rowTotal !== columnTotal) return { error: `total mismatch rows=${rowTotal} columns=${columnTotal}` };
  const cells = new Set<number>();
  for (let index = 0; index < givens.length; index++) {
    const { r, c, character } = givens[index];
    if (r < 0 || r >= h || c < 0 || c >= w || (character !== '#' && character !== '.')) {
      return { error: `bad given ${index + 1}` };
    }
    const key = r * w + c;
    if (cells.has(key)) return { error: `duplicate given ${index + 1}` };
    cells.add(key);
  }
  if (answer !== null && (answer.length !== h || answer.some(line => line.length !== w || !/^[#.?]+$/.test(line)))) {
    return { error: 'bad answer' };
  }
  return { value: { name, w, h, rows, columns,
    givens: givens.map(given => ({ r: given.r, c: given.c, state: toState(given.character) })),
    answer: answer === null ? null : answer.map(line => Array.from(line, toState)) } };
}

function validatePicture(block: Picture, seen: Set<string>): string | null {
  const duplicate = seen.has(block.name);
  seen.add(block.name);
  if (!/^[a-z0-9_]{1,20}$/.test(block.name)) return 'bad name';
  if (duplicate) return 'duplicate name';
  if (block.picture.length < 1 || block.picture.length > 30) return 'bad height';
  const width = block.picture[0].length;
  for (let index = 0; index < block.picture.length; index++) {
    const line = block.picture[index];
    if (line.length < 1 || line.length > 30 || line.length !== width || !/^[#.]+$/.test(line)) return `bad row ${index + 1}`;
  }
  return null;
}

function logicalSolve(puzzle: ClueSet, givens: Given[], kind: SolveKind): LogicalResult {
  const grid: Grid = Array.from({ length: puzzle.h }, () => Array<CellState>(puzzle.w).fill(UNKNOWN));
  for (const given of givens) grid[given.r][given.c] = given.state;
  const propagation = propagate(grid, puzzle.rows, puzzle.columns, kind);
  const known = determinedCount(grid);
  let result = known === puzzle.h * puzzle.w ? 'solved' : 'stuck';
  if (propagation.conflict !== null) result = 'contradiction at=' + propagation.conflict.label;
  return { ...propagation, known, result };
}

function analyze(puzzle: ClueSet, givens: Given[]): Analysis {
  const simple = logicalSolve(puzzle, givens, 'simple'), logic = logicalSolve(puzzle, givens, 'precise');
  let searched: SearchResult | null = null;
  let solutions: Grid[] = [];
  let status: Status, difficulty: Difficulty = '-';
  if (logic.conflict !== null) status = 'contradiction';
  else if (logic.result === 'solved') {
    status = 'unique';
    difficulty = simple.result === 'solved' ? 'easy' : 'medium';
    solutions = [logic.grid];
  } else {
    searched = search(logic.grid, puzzle.rows, puzzle.columns);
    solutions = searched.solutions;
    status = solutions.length === 0 ? 'none' : solutions.length === 1 ? 'unique' : 'multiple';
    if (status === 'unique') difficulty = 'hard';
  }
  return { simple, logic, search: searched, solutions, status, difficulty,
    lineSolves: logic.record.length + (searched?.lineSolves ?? 0), guesses: searched?.guesses ?? 0,
    maxDepth: searched?.maxDepth ?? 0 };
}

function clueStatistics(puzzle: ClueSet): string {
  let rowBlocks = 0, columnBlocks = 0, filled = 0, maximum = 0, fixed = 0;
  for (const clue of puzzle.rows) { rowBlocks += clue.length; for (const block of clue) filled += block; }
  for (const clue of puzzle.columns) columnBlocks += clue.length;
  for (const { clues, length } of [{ clues: puzzle.rows, length: puzzle.w }, { clues: puzzle.columns, length: puzzle.h }]) {
    for (const clue of clues) {
      for (const block of clue) maximum = Math.max(maximum, block);
      if (clue.length === 0 || minimumLength(clue) === length) fixed++;
    }
  }
  return `row_blocks=${rowBlocks} column_blocks=${columnBlocks} filled=${filled} max_block=${maximum} fixed_lines=${fixed}`;
}

function lineStatistics(record: SolveRecord[]): string {
  let productive = 0, idle = 0, best = 0, at = '-';
  for (const item of record) {
    if (item.gain === null) continue;
    if (item.gain === 0) idle++; else productive++;
    if (item.gain > best) { best = item.gain; at = item.label; }
  }
  return `steps productive=${productive} idle=${idle} best=${best} at=${at}`;
}

function remainingUnknowns(grid: Grid, axis: Axis, count: number): string {
  const items: string[] = [];
  for (let index = 0; index < count; index++) {
    let unknown = 0;
    for (const state of getLine(grid, axis, index)) if (state === UNKNOWN) unknown++;
    if (unknown > 0) items.push(`${index + 1}:${unknown}`);
  }
  return items.join(' ');
}
function differingCells(first: Grid, second: Grid): Coordinate[] {
  const cells: Coordinate[] = [];
  for (let r = 0; r < first.length; r++) for (let c = 0; c < first[r].length; c++) {
    if (first[r][c] !== second[r][c]) cells.push({ r, c });
  }
  return cells;
}

function pictureFeatures(grid: Grid): string {
  const h = grid.length, w = grid[0].length;
  const visited = Array.from({ length: h }, () => Array<boolean>(w).fill(false));
  const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
  let filled = 0, components = 0, largest = 0, minRow = h, minColumn = w, maxRow = -1, maxColumn = -1;
  let lr = true, ud = true, rot180 = true;
  for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
    const state = grid[r][c];
    if (state !== grid[r][w - 1 - c]) lr = false;
    if (state !== grid[h - 1 - r][c]) ud = false;
    if (state !== grid[h - 1 - r][w - 1 - c]) rot180 = false;
    if (state !== FILLED) continue;
    filled++;
    minRow = Math.min(minRow, r); minColumn = Math.min(minColumn, c);
    maxRow = Math.max(maxRow, r); maxColumn = Math.max(maxColumn, c);
    if (visited[r][c]) continue;
    components++;
    const stack: Coordinate[] = [{ r, c }];
    visited[r][c] = true;
    let size = 0;
    while (stack.length > 0) {
      const cell = stack.pop();
      if (cell === undefined) break;
      size++;
      for (const [dr, dc] of directions) {
        const rr = cell.r + dr, cc = cell.c + dc;
        if (rr < 0 || rr >= h || cc < 0 || cc >= w || grid[rr][cc] !== FILLED || visited[rr][cc]) continue;
        visited[rr][cc] = true;
        stack.push({ r: rr, c: cc });
      }
    }
    largest = Math.max(largest, size);
  }
  const bbox = filled === 0 ? '-' : [minRow + 1, minColumn + 1, maxRow + 1, maxColumn + 1].join(',');
  const symmetries: string[] = [];
  if (lr) symmetries.push('lr');
  if (ud) symmetries.push('ud');
  if (rot180) symmetries.push('rot180');
  return `filled=${filled} components=${components} largest=${largest} bbox=${bbox} symmetry=${symmetries.length ? symmetries.join(',') : 'none'}`;
}

const numberList = (values: number[]): string => values.length === 0 ? '-' : values.join(',');
function evaluateGivens(puzzle: Puzzle, analysis: Analysis): string | null {
  if (puzzle.givens.length === 0 || analysis.status === 'multiple') return null;
  const numbers: number[] = [];
  for (let index = 0; index < puzzle.givens.length; index++) {
    const trial = analyze(puzzle, puzzle.givens.filter((_, k) => k !== index));
    if (analysis.status === 'unique' ? trial.status === 'unique' : trial.status === 'unique' || trial.status === 'multiple') numbers.push(index + 1);
  }
  return `givens ${analysis.status === 'unique' ? 'redundant' : 'blame'}=${numberList(numbers)}`;
}

function gradeAnswer(puzzle: Puzzle, analysis: Analysis): Grade | null {
  if (puzzle.answer === null) return null;
  const grid = puzzle.answer, rows: number[] = [], columns: number[] = [], givens: number[] = [];
  for (let r = 0; r < puzzle.h; r++) if (!hasPlacement(grid[r], puzzle.rows[r])) rows.push(r + 1);
  for (let c = 0; c < puzzle.w; c++) if (!hasPlacement(getLine(grid, 'C', c), puzzle.columns[c])) columns.push(c + 1);
  for (let index = 0; index < puzzle.givens.length; index++) {
    const given = puzzle.givens[index], state = grid[given.r][given.c];
    if (state !== UNKNOWN && state !== given.state) givens.push(index + 1);
  }
  const known = determinedCount(grid), mismatch = rows.length > 0 || columns.length > 0 || givens.length > 0;
  const result = known < puzzle.h * puzzle.w ? 'partial' : mismatch ? 'wrong' : 'correct';
  let extendable: 'yes' | 'no' = 'no';
  if (result === 'partial' && !mismatch) {
    const combined = puzzle.givens.slice();
    const originalCells = new Set(puzzle.givens.map(given => given.r * puzzle.w + given.c));
    for (let r = 0; r < puzzle.h; r++) for (let c = 0; c < puzzle.w; c++) {
      if (grid[r][c] !== UNKNOWN && !originalCells.has(r * puzzle.w + c)) combined.push({ r, c, state: grid[r][c] });
    }
    const trial = analyze(puzzle, combined);
    if (trial.status === 'unique' || trial.status === 'multiple') extendable = 'yes';
  }
  let differs = 0;
  if (analysis.status === 'unique') {
    for (let r = 0; r < puzzle.h; r++) for (let c = 0; c < puzzle.w; c++) {
      if (grid[r][c] !== UNKNOWN && grid[r][c] !== analysis.solutions[0][r][c]) differs++;
    }
  }
  return { grid, rows, columns, givens, known, result, extendable, differs };
}

function answerLines(puzzle: Puzzle, analysis: Analysis, grade: Grade): string[] {
  let headline = `answer result=${grade.result} known=${grade.known} rows=${numberList(grade.rows)}`
    + ` columns=${numberList(grade.columns)} givens=${numberList(grade.givens)}`;
  if (grade.result === 'partial') headline += ' extendable=' + grade.extendable;
  if (analysis.status === 'unique') headline += ' differs=' + grade.differs;
  const lines = [headline];
  const groups: { axis: Axis; numbers: number[]; clues: Clue[] }[] = [
    { axis: 'R', numbers: grade.rows, clues: puzzle.rows }, { axis: 'C', numbers: grade.columns, clues: puzzle.columns },
  ];
  for (const { axis, numbers, clues } of groups) for (const number of numbers) {
    const line = getLine(grade.grid, axis, number - 1);
    const detail = grade.result === 'partial' ? 'cells=' + stateString(line) : 'got=' + commaForm(runClue(line));
    lines.push(`mismatch ${axis}${number} expected=${commaForm(clues[number - 1])} ${detail}`);
  }
  return lines;
}

function puzzleParagraph(puzzle: Puzzle, analysis: Analysis, grade: Grade | null): string {
  const { simple, logic } = analysis;
  const lines = ['PUZZLE ' + puzzle.name,
    `size=${puzzle.w}x${puzzle.h} givens=${puzzle.givens.length} status=${analysis.status} difficulty=${analysis.difficulty}`,
    'clues ' + clueStatistics(puzzle),
    `simple known=${simple.known} line_solves=${simple.record.length} result=${simple.result}`,
    `logic known=${logic.known} line_solves=${logic.record.length} result=${logic.result}`, lineStatistics(logic.record)];
  if (puzzle.h * puzzle.w <= 49) lines.push('trace ' + logic.record.map(item => item.label + (item.gain === null ? '!' : '+' + item.gain)).join(' '));
  if (logic.result === 'stuck') lines.push('stuck rows=' + remainingUnknowns(logic.grid, 'R', puzzle.h)
    + ' columns=' + remainingUnknowns(logic.grid, 'C', puzzle.w));
  if (analysis.status === 'contradiction' && logic.conflict !== null) {
    const { axis, index, label } = logic.conflict;
    const clue = axis === 'R' ? puzzle.rows[index] : puzzle.columns[index];
    lines.push(`conflict line=${label} clue=${commaForm(clue)} cells=${stateString(getLine(logic.grid, axis, index))}`);
  }
  if (analysis.search !== null) {
    const searched = analysis.search;
    lines.push(`search guesses=${searched.guesses} max_depth=${searched.maxDepth} backtracks=${searched.backtracks}`
      + ` solutions=${searched.solutions.length} line_solves=${searched.lineSolves}`);
    for (const guess of searched.record) lines.push(`guess ${guess.number} depth=${guess.depth} cell=${guess.r + 1},${guess.c + 1}`
      + ` value=${stateChar(guess.value)} solves=${guess.solves} known=${guess.known} result=${guess.outcome}`);
  }
  if (analysis.status === 'multiple') {
    const cells = differingCells(analysis.solutions[0], analysis.solutions[1]);
    lines.push(`differ count=${cells.length} cells=` + cells.map(cell => `${cell.r + 1},${cell.c + 1}`).join(' '));
  }
  const grids: NamedGrid[] = [];
  if (analysis.status === 'contradiction') grids.push({ name: 'partial', grid: logic.grid });
  else {
    if (simple.result === 'stuck') grids.push({ name: 'simple', grid: simple.grid });
    if (logic.result === 'stuck') grids.push({ name: 'logic', grid: logic.grid });
    if (analysis.status === 'multiple') grids.push({ name: 'first', grid: analysis.solutions[0] }, { name: 'second', grid: analysis.solutions[1] });
  }
  lines.push(...sideBySide(grids));
  if (analysis.status === 'unique') {
    lines.push('sheet', ...answerSheet(analysis.solutions[0], puzzle.rows, puzzle.columns));
    lines.push('picture ' + pictureFeatures(analysis.solutions[0]));
  }
  const evaluation = evaluateGivens(puzzle, analysis);
  if (evaluation !== null) lines.push(evaluation);
  if (grade !== null) lines.push(...answerLines(puzzle, analysis, grade));
  return lines.join('\n');
}

const clueKey = (puzzle: ClueSet): string => JSON.stringify([puzzle.w, puzzle.h, puzzle.rows, puzzle.columns]);
function processPuzzles(text: string): { solutions: string; stats: string; sameClues: Map<string, string> } {
  const puzzles = readPuzzles(text), paragraphs: string[] = [];
  const stats = ['puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'];
  const totals = { invalid: 0, contradiction: 0, none: 0, unique: 0, multiple: 0, easy: 0, medium: 0, hard: 0, lineSolves: 0, guesses: 0 };
  const ranking: Ranking[] = [], sameClues = new Map<string, string>(), seen = new Set<string>();
  for (const raw of puzzles) {
    const validated = validatePuzzle(raw, seen);
    if ('error' in validated) {
      totals.invalid++;
      paragraphs.push(`PUZZLE ${raw.name}\nerror ${validated.error}`);
      stats.push([raw.name, 'invalid', ...Array<string>(11).fill('-')].join(','));
      continue;
    }
    const puzzle = validated.value, key = clueKey(puzzle);
    if (!sameClues.has(key)) sameClues.set(key, puzzle.name);
    const analysis = analyze(puzzle, puzzle.givens), grade = gradeAnswer(puzzle, analysis);
    paragraphs.push(puzzleParagraph(puzzle, analysis, grade));
    totals[analysis.status]++;
    if (analysis.difficulty !== '-') totals[analysis.difficulty]++;
    totals.lineSolves += analysis.lineSolves;
    totals.guesses += analysis.guesses;
    if (analysis.status === 'unique') ranking.push({ puzzle, analysis, score: analysis.lineSolves + 25 * analysis.guesses });
    stats.push([puzzle.name, analysis.status, analysis.difficulty, puzzle.w, puzzle.h, puzzle.givens.length,
      analysis.simple.known, analysis.logic.known, analysis.lineSolves, analysis.guesses, analysis.maxDepth,
      analysis.solutions.length, grade?.result ?? '-'].join(','));
  }
  const difficultyOrder: Record<Difficulty, number> = { easy: 0, medium: 1, hard: 2, '-': 3 };
  ranking.sort((a, b) => difficultyOrder[a.analysis.difficulty] - difficultyOrder[b.analysis.difficulty]
    || a.score - b.score || (a.puzzle.name < b.puzzle.name ? -1 : a.puzzle.name > b.puzzle.name ? 1 : 0));
  const rankLines = ['RANKING'];
  ranking.forEach(({ puzzle, analysis, score }, index) => {
    rankLines.push(`rank ${index + 1} ${puzzle.name} ${analysis.difficulty} score=${score} size=${puzzle.w}x${puzzle.h}`);
  });
  paragraphs.push(rankLines.join('\n'));
  paragraphs.push(`SUMMARY puzzles=${puzzles.length} invalid=${totals.invalid} contradiction=${totals.contradiction}`
    + ` none=${totals.none} unique=${totals.unique} multiple=${totals.multiple} easy=${totals.easy} medium=${totals.medium} hard=${totals.hard}`
    + ` line_solves=${totals.lineSolves} guesses=${totals.guesses}`);
  return { solutions: paragraphs.join('\n\n') + '\n', stats: stats.join('\n') + '\n', sameClues };
}

function generatePicture(block: Picture, sameClues: Map<string, string>): { paragraph: string; initial: Analysis; hintCount: number } {
  const grid = block.picture.map(line => Array.from(line, toState)), h = grid.length, w = grid[0].length;
  const puzzle: ClueSet = { name: block.name, w, h, rows: grid.map(runClue),
    columns: Array.from({ length: w }, (_, c) => runClue(getLine(grid, 'C', c))) };
  const initial = analyze(puzzle, []);
  let analysis = initial, givens: Given[] = [];
  const lines = [`# picture ${block.name} size=${w}x${h} ${pictureFeatures(grid)}`,
    `# clues ${clueStatistics(puzzle)} duplicate_of=${sameClues.get(clueKey(puzzle)) ?? '-'}`,
    `# plain status=${initial.status} difficulty=${initial.difficulty} line_solves=${initial.lineSolves} guesses=${initial.guesses}`];
  while (analysis.status === 'multiple') {
    const { r, c } = differingCells(analysis.solutions[0], analysis.solutions[1])[0], state = grid[r][c];
    givens.push({ r, c, state });
    analysis = analyze(puzzle, givens);
    lines.push(`# hint ${givens.length} cell=${r + 1},${c + 1} value=${stateChar(state)} status=${analysis.status}`);
  }
  // Visit the original addition order; each trial removes only this cell from the current list.
  for (const given of givens.slice()) {
    const reduced = givens.filter(cell => cell !== given), trial = analyze(puzzle, reduced);
    if (trial.status === 'unique') {
      givens = reduced;
      lines.push(`# drop cell=${given.r + 1},${given.c + 1}`);
    }
  }
  analysis = analyze(puzzle, givens);
  let logicHints = 0;
  while (analysis.difficulty === 'hard') {
    const chosen = chooseCell(analysis.logic.grid);
    if (chosen === null) throw new Error('Hard puzzle has no unknown cell');
    const { r, c } = chosen, state = grid[r][c];
    givens.push({ r, c, state });
    analysis = analyze(puzzle, givens);
    lines.push(`# logic hint ${++logicHints} cell=${r + 1},${c + 1} value=${stateChar(state)} difficulty=${analysis.difficulty}`);
  }
  lines.push(`# final status=${analysis.status} difficulty=${analysis.difficulty} hints=${givens.length} line_solves=${analysis.lineSolves} guesses=${analysis.guesses}`);
  lines.push('PUZZLE ' + block.name, `SIZE ${w} ${h}`, 'ROWS', ...puzzle.rows.map(spaceForm), 'COLUMNS', ...puzzle.columns.map(spaceForm));
  for (const given of givens.slice().sort((a, b) => a.r - b.r || a.c - b.c)) {
    lines.push(`GIVEN ${given.r + 1} ${given.c + 1} ${stateChar(given.state)}`);
  }
  lines.push('END');
  return { paragraph: lines.join('\n'), initial, hintCount: givens.length };
}

function processPictures(text: string, sameClues: Map<string, string>): string {
  const blocks = readPictures(text), paragraphs: string[] = [], seen = new Set<string>();
  let invalid = 0, unique = 0, lineLogic = 0, hinted = 0, hints = 0;
  for (const block of blocks) {
    const error = validatePicture(block, seen);
    if (error !== null) { invalid++; paragraphs.push(`# picture ${block.name} error ${error}`); continue; }
    const generated = generatePicture(block, sameClues);
    paragraphs.push(generated.paragraph);
    if (generated.initial.status === 'unique') unique++;
    if (generated.initial.difficulty === 'easy' || generated.initial.difficulty === 'medium') lineLogic++;
    if (generated.hintCount > 0) hinted++;
    hints += generated.hintCount;
  }
  paragraphs.push(`# SUMMARY pictures=${blocks.length} invalid=${invalid} unique=${unique} line_logic=${lineLogic} hinted=${hinted} hints=${hints}`);
  return paragraphs.join('\n\n') + '\n';
}

function main(): void {
  const puzzles = processPuzzles(readFileSync('input/puzzles.txt', 'ascii'));
  mkdirSync('output', { recursive: true });
  writeFileSync('output/solutions.txt', puzzles.solutions, 'ascii');
  writeFileSync('output/stats.csv', puzzles.stats, 'ascii');
  const pictures = processPictures(readFileSync('input/pictures.txt', 'ascii'), puzzles.sameClues);
  writeFileSync('output/generated.txt', pictures, 'ascii');
}

main();
