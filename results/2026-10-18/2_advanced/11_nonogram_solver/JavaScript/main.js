'use strict';

const fs = require('node:fs');
const { runClue, spaceForm, commaForm, parseClue, minimumLength, fits } = require('./clues');
const { UNKNOWN, FILLED, EMPTY, hasPlacement } = require('./line_solver');
const { getLine, determinedCount, propagate } = require('./propagation');
const { chooseCell, search } = require('./search');
const { stateChar, stateString, sideBySide, answerSheet } = require('./render');

function toState(character) {
    return character === '#' ? FILLED : character === '.' ? EMPTY : UNKNOWN;
}

function readPuzzles(text) {
    const lines = text.split('\n');
    const blocks = [];
    let cursor = 0;
    while (cursor < lines.length) {
        const header = lines[cursor++];
        if (header === '' || header.startsWith('#')) continue;
        const name = header.slice(7);
        const size = lines[cursor++].split(' ');
        const w = Number(size[1]);
        const h = Number(size[2]);
        cursor++; // ROWS
        const rowLines = [];
        while (lines[cursor] !== 'COLUMNS') rowLines.push(lines[cursor++]);
        cursor++;
        const columnLines = [];
        while (lines[cursor] !== 'END' && lines[cursor] !== 'ANSWER'
            && !lines[cursor].startsWith('GIVEN ')) {
            columnLines.push(lines[cursor++]);
        }
        const givens = [];
        while (lines[cursor].startsWith('GIVEN ')) {
            const fields = lines[cursor++].split(' ');
            givens.push({ r: Number(fields[1]) - 1, c: Number(fields[2]) - 1,
                character: fields[3], state: toState(fields[3]) });
        }
        let answer = null;
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

function readPictures(text) {
    const lines = text.split('\n');
    const blocks = [];
    let cursor = 0;
    while (cursor < lines.length) {
        const header = lines[cursor++];
        if (header === '' || header.startsWith('#')) continue;
        const name = header.slice(8);
        const picture = [];
        while (lines[cursor] !== 'END') picture.push(lines[cursor++]);
        cursor++;
        blocks.push({ name, picture });
    }
    return blocks;
}

function validatePuzzle(puzzle, seen) {
    const { name, w, h, rowLines, columnLines, givens, answer } = puzzle;
    const duplicate = seen.has(name);
    seen.add(name);
    if (!/^[a-z0-9_]{1,20}$/.test(name)) return 'bad name';
    if (duplicate) return 'duplicate name';
    if (w < 1 || w > 30 || h < 1 || h > 30) return 'bad size';
    if (rowLines.length !== h) return `row count ${rowLines.length} expected ${h}`;
    if (columnLines.length !== w) return `column count ${columnLines.length} expected ${w}`;
    puzzle.rows = [];
    puzzle.columns = [];
    for (const [kind, texts, length, clues] of [
        ['row', rowLines, w, puzzle.rows], ['column', columnLines, h, puzzle.columns],
    ]) {
        for (let index = 0; index < texts.length; index++) {
            const clue = parseClue(texts[index]);
            if (clue === null) return `bad clue ${kind} ${index + 1}`;
            if (!fits(clue, length)) return `${kind} ${index + 1} too long`;
            clues.push(clue);
        }
    }
    let rowTotal = 0;
    let columnTotal = 0;
    for (const clue of puzzle.rows) for (const block of clue) rowTotal += block;
    for (const clue of puzzle.columns) for (const block of clue) columnTotal += block;
    if (rowTotal !== columnTotal) return `total mismatch rows=${rowTotal} columns=${columnTotal}`;
    const cells = new Set();
    for (let index = 0; index < givens.length; index++) {
        const { r, c, character } = givens[index];
        if (r < 0 || r >= h || c < 0 || c >= w || (character !== '#' && character !== '.')) {
            return `bad given ${index + 1}`;
        }
        const key = r * w + c;
        if (cells.has(key)) return `duplicate given ${index + 1}`;
        cells.add(key);
    }
    if (answer !== null && (answer.length !== h
        || answer.some(line => line.length !== w || !/^[#.?]+$/.test(line)))) {
        return 'bad answer';
    }
    return null;
}

function validatePicture(block, seen) {
    const duplicate = seen.has(block.name);
    seen.add(block.name);
    if (!/^[a-z0-9_]{1,20}$/.test(block.name)) return 'bad name';
    if (duplicate) return 'duplicate name';
    if (block.picture.length < 1 || block.picture.length > 30) return 'bad height';
    const width = block.picture[0].length;
    for (let index = 0; index < block.picture.length; index++) {
        const line = block.picture[index];
        if (line.length < 1 || line.length > 30 || line.length !== width || !/^[#.]+$/.test(line)) {
            return `bad row ${index + 1}`;
        }
    }
    return null;
}

function logicalSolve(puzzle, givens, kind) {
    const grid = Array.from({ length: puzzle.h }, () => Array(puzzle.w).fill(UNKNOWN));
    for (const given of givens) grid[given.r][given.c] = given.state;
    const propagation = propagate(grid, puzzle.rows, puzzle.columns, kind);
    const known = determinedCount(grid);
    let result = known === puzzle.h * puzzle.w ? 'solved' : 'stuck';
    if (propagation.conflict !== null) result = 'contradiction at=' + propagation.conflict.label;
    return { ...propagation, known, result };
}

function analyze(puzzle, givens) {
    const simple = logicalSolve(puzzle, givens, 'simple');
    const logic = logicalSolve(puzzle, givens, 'precise');
    let searched = null;
    let solutions = [];
    let status;
    let difficulty = '-';
    if (logic.conflict !== null) {
        status = 'contradiction';
    } else if (logic.result === 'solved') {
        status = 'unique';
        difficulty = simple.result === 'solved' ? 'easy' : 'medium';
        solutions = [logic.grid];
    } else {
        searched = search(logic.grid, puzzle.rows, puzzle.columns);
        solutions = searched.solutions;
        status = ['none', 'unique', 'multiple'][solutions.length];
        if (status === 'unique') difficulty = 'hard';
    }
    return {
        simple, logic, search: searched, solutions, status, difficulty,
        lineSolves: logic.record.length + (searched === null ? 0 : searched.lineSolves),
        guesses: searched === null ? 0 : searched.guesses,
        maxDepth: searched === null ? 0 : searched.maxDepth,
    };
}

function clueStatistics(puzzle) {
    let rowBlocks = 0;
    let columnBlocks = 0;
    let filled = 0;
    let maximum = 0;
    let fixed = 0;
    for (const clue of puzzle.rows) {
        rowBlocks += clue.length;
        for (const block of clue) filled += block;
    }
    for (const clue of puzzle.columns) columnBlocks += clue.length;
    for (const [clues, length] of [[puzzle.rows, puzzle.w], [puzzle.columns, puzzle.h]]) {
        for (const clue of clues) {
            for (const block of clue) maximum = Math.max(maximum, block);
            if (clue.length === 0 || minimumLength(clue) === length) fixed++;
        }
    }
    return `row_blocks=${rowBlocks} column_blocks=${columnBlocks} filled=${filled}`
        + ` max_block=${maximum} fixed_lines=${fixed}`;
}

function lineStatistics(record) {
    let productive = 0;
    let idle = 0;
    let best = 0;
    let at = '-';
    for (const item of record) {
        if (item.gain === null) continue;
        if (item.gain === 0) idle++;
        else productive++;
        if (item.gain > best) {
            best = item.gain;
            at = item.label;
        }
    }
    return `steps productive=${productive} idle=${idle} best=${best} at=${at}`;
}

function remainingUnknowns(grid, axis, count) {
    const items = [];
    for (let index = 0; index < count; index++) {
        let unknown = 0;
        for (const state of getLine(grid, axis, index)) if (state === UNKNOWN) unknown++;
        if (unknown > 0) items.push(`${index + 1}:${unknown}`);
    }
    return items.join(' ');
}

function differingCells(first, second) {
    const cells = [];
    for (let r = 0; r < first.length; r++) {
        for (let c = 0; c < first[r].length; c++) {
            if (first[r][c] !== second[r][c]) cells.push({ r, c });
        }
    }
    return cells;
}

function pictureFeatures(grid) {
    const h = grid.length;
    const w = grid[0].length;
    const visited = Array.from({ length: h }, () => Array(w).fill(false));
    const directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    let filled = 0;
    let components = 0;
    let largest = 0;
    let minRow = h;
    let minColumn = w;
    let maxRow = -1;
    let maxColumn = -1;
    let lr = true;
    let ud = true;
    let rot180 = true;
    for (let r = 0; r < h; r++) {
        for (let c = 0; c < w; c++) {
            const state = grid[r][c];
            if (state !== grid[r][w - 1 - c]) lr = false;
            if (state !== grid[h - 1 - r][c]) ud = false;
            if (state !== grid[h - 1 - r][w - 1 - c]) rot180 = false;
            if (state !== FILLED) continue;
            filled++;
            minRow = Math.min(minRow, r);
            minColumn = Math.min(minColumn, c);
            maxRow = Math.max(maxRow, r);
            maxColumn = Math.max(maxColumn, c);
            if (visited[r][c]) continue;
            components++;
            const stack = [{ r, c }];
            visited[r][c] = true;
            let size = 0;
            while (stack.length > 0) {
                const cell = stack.pop();
                size++;
                for (const [dr, dc] of directions) {
                    const rr = cell.r + dr;
                    const cc = cell.c + dc;
                    if (rr < 0 || rr >= h || cc < 0 || cc >= w) continue;
                    if (grid[rr][cc] !== FILLED || visited[rr][cc]) continue;
                    visited[rr][cc] = true;
                    stack.push({ r: rr, c: cc });
                }
            }
            largest = Math.max(largest, size);
        }
    }
    const bbox = filled === 0 ? '-' : [minRow + 1, minColumn + 1, maxRow + 1, maxColumn + 1].join(',');
    const symmetries = [];
    if (lr) symmetries.push('lr');
    if (ud) symmetries.push('ud');
    if (rot180) symmetries.push('rot180');
    return `filled=${filled} components=${components} largest=${largest} bbox=${bbox}`
        + ` symmetry=${symmetries.length === 0 ? 'none' : symmetries.join(',')}`;
}

function numberList(values) {
    return values.length === 0 ? '-' : values.join(',');
}

function evaluateGivens(puzzle, analysis) {
    if (puzzle.givens.length === 0 || analysis.status === 'multiple') return null;
    const numbers = [];
    for (let index = 0; index < puzzle.givens.length; index++) {
        const trial = analyze(puzzle, puzzle.givens.filter((given, k) => k !== index));
        if (analysis.status === 'unique' ? trial.status === 'unique'
            : trial.status === 'unique' || trial.status === 'multiple') {
            numbers.push(index + 1);
        }
    }
    const kind = analysis.status === 'unique' ? 'redundant' : 'blame';
    return `givens ${kind}=${numberList(numbers)}`;
}

function gradeAnswer(puzzle, analysis) {
    if (puzzle.answer === null) return null;
    const grid = puzzle.answer.map(line => Array.from(line, toState));
    const rows = [];
    const columns = [];
    const givens = [];
    for (let r = 0; r < puzzle.h; r++) {
        if (!hasPlacement(grid[r], puzzle.rows[r])) rows.push(r + 1);
    }
    for (let c = 0; c < puzzle.w; c++) {
        if (!hasPlacement(getLine(grid, 'C', c), puzzle.columns[c])) columns.push(c + 1);
    }
    for (let index = 0; index < puzzle.givens.length; index++) {
        const given = puzzle.givens[index];
        const state = grid[given.r][given.c];
        if (state !== UNKNOWN && state !== given.state) givens.push(index + 1);
    }
    const known = determinedCount(grid);
    const mismatch = rows.length > 0 || columns.length > 0 || givens.length > 0;
    const result = known < puzzle.h * puzzle.w ? 'partial' : mismatch ? 'wrong' : 'correct';
    let extendable = 'no';
    if (result === 'partial' && !mismatch) {
        const combined = puzzle.givens.slice();
        const originalCells = new Set(puzzle.givens.map(given => given.r * puzzle.w + given.c));
        for (let r = 0; r < puzzle.h; r++) {
            for (let c = 0; c < puzzle.w; c++) {
                if (grid[r][c] !== UNKNOWN && !originalCells.has(r * puzzle.w + c)) {
                    combined.push({ r, c, state: grid[r][c] });
                }
            }
        }
        const trial = analyze(puzzle, combined);
        if (trial.status === 'unique' || trial.status === 'multiple') extendable = 'yes';
    }
    let differs = 0;
    if (analysis.status === 'unique') {
        for (let r = 0; r < puzzle.h; r++) {
            for (let c = 0; c < puzzle.w; c++) {
                if (grid[r][c] !== UNKNOWN && grid[r][c] !== analysis.solutions[0][r][c]) differs++;
            }
        }
    }
    return { grid, rows, columns, givens, known, result, extendable, differs };
}

function answerLines(puzzle, analysis, grade) {
    let headline = `answer result=${grade.result} known=${grade.known}`
        + ` rows=${numberList(grade.rows)} columns=${numberList(grade.columns)}`
        + ` givens=${numberList(grade.givens)}`;
    if (grade.result === 'partial') headline += ' extendable=' + grade.extendable;
    if (analysis.status === 'unique') headline += ' differs=' + grade.differs;
    const lines = [headline];
    for (const [axis, numbers, clues] of [['R', grade.rows, puzzle.rows], ['C', grade.columns, puzzle.columns]]) {
        for (const number of numbers) {
            const line = getLine(grade.grid, axis, number - 1);
            const detail = grade.result === 'partial' ? 'cells=' + stateString(line) : 'got=' + commaForm(runClue(line));
            lines.push(`mismatch ${axis}${number} expected=${commaForm(clues[number - 1])} ${detail}`);
        }
    }
    return lines;
}

function puzzleParagraph(puzzle, analysis, grade) {
    const { simple, logic } = analysis;
    const lines = [
        'PUZZLE ' + puzzle.name,
        `size=${puzzle.w}x${puzzle.h} givens=${puzzle.givens.length} status=${analysis.status} difficulty=${analysis.difficulty}`,
        'clues ' + clueStatistics(puzzle),
        `simple known=${simple.known} line_solves=${simple.record.length} result=${simple.result}`,
        `logic known=${logic.known} line_solves=${logic.record.length} result=${logic.result}`,
        lineStatistics(logic.record),
    ];
    if (puzzle.h * puzzle.w <= 49) {
        lines.push('trace ' + logic.record.map(item => item.label + (item.gain === null ? '!' : '+' + item.gain)).join(' '));
    }
    if (logic.result === 'stuck') {
        lines.push('stuck rows=' + remainingUnknowns(logic.grid, 'R', puzzle.h)
            + ' columns=' + remainingUnknowns(logic.grid, 'C', puzzle.w));
    }
    if (analysis.status === 'contradiction') {
        const { axis, index, label } = logic.conflict;
        const clue = axis === 'R' ? puzzle.rows[index] : puzzle.columns[index];
        lines.push(`conflict line=${label} clue=${commaForm(clue)} cells=${stateString(getLine(logic.grid, axis, index))}`);
    }
    if (analysis.search !== null) {
        const searched = analysis.search;
        lines.push(`search guesses=${searched.guesses} max_depth=${searched.maxDepth} backtracks=${searched.backtracks}`
            + ` solutions=${searched.solutions.length} line_solves=${searched.lineSolves}`);
        for (const guess of searched.record) {
            lines.push(`guess ${guess.number} depth=${guess.depth} cell=${guess.r + 1},${guess.c + 1}`
                + ` value=${stateChar(guess.value)} solves=${guess.solves} known=${guess.known} result=${guess.outcome}`);
        }
    }
    if (analysis.status === 'multiple') {
        const cells = differingCells(analysis.solutions[0], analysis.solutions[1]);
        lines.push(`differ count=${cells.length} cells=` + cells.map(cell => `${cell.r + 1},${cell.c + 1}`).join(' '));
    }
    const grids = [];
    if (analysis.status === 'contradiction') {
        grids.push({ name: 'partial', grid: logic.grid });
    } else {
        if (simple.result === 'stuck') grids.push({ name: 'simple', grid: simple.grid });
        if (logic.result === 'stuck') grids.push({ name: 'logic', grid: logic.grid });
        if (analysis.status === 'multiple') {
            grids.push({ name: 'first', grid: analysis.solutions[0] });
            grids.push({ name: 'second', grid: analysis.solutions[1] });
        }
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

function clueKey(puzzle) {
    return JSON.stringify([puzzle.w, puzzle.h, puzzle.rows, puzzle.columns]);
}

function processPuzzles(text) {
    const puzzles = readPuzzles(text);
    const paragraphs = [];
    const stats = ['puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'];
    const totals = { invalid: 0, contradiction: 0, none: 0, unique: 0, multiple: 0,
        easy: 0, medium: 0, hard: 0, lineSolves: 0, guesses: 0 };
    const ranking = [];
    const sameClues = new Map();
    const seen = new Set();
    for (const puzzle of puzzles) {
        const error = validatePuzzle(puzzle, seen);
        if (error !== null) {
            totals.invalid++;
            paragraphs.push(`PUZZLE ${puzzle.name}\nerror ${error}`);
            stats.push([puzzle.name, 'invalid', ...Array(11).fill('-')].join(','));
            continue;
        }
        const key = clueKey(puzzle);
        if (!sameClues.has(key)) sameClues.set(key, puzzle.name);
        const analysis = analyze(puzzle, puzzle.givens);
        const grade = gradeAnswer(puzzle, analysis);
        paragraphs.push(puzzleParagraph(puzzle, analysis, grade));
        totals[analysis.status]++;
        if (analysis.difficulty !== '-') totals[analysis.difficulty]++;
        totals.lineSolves += analysis.lineSolves;
        totals.guesses += analysis.guesses;
        if (analysis.status === 'unique') ranking.push({ puzzle, analysis, score: analysis.lineSolves + 25 * analysis.guesses });
        stats.push([puzzle.name, analysis.status, analysis.difficulty, puzzle.w, puzzle.h, puzzle.givens.length,
            analysis.simple.known, analysis.logic.known, analysis.lineSolves, analysis.guesses, analysis.maxDepth,
            analysis.solutions.length, grade === null ? '-' : grade.result].join(','));
    }
    const difficultyOrder = { easy: 0, medium: 1, hard: 2 };
    ranking.sort((a, b) => difficultyOrder[a.analysis.difficulty] - difficultyOrder[b.analysis.difficulty]
        || a.score - b.score || (a.puzzle.name < b.puzzle.name ? -1 : a.puzzle.name > b.puzzle.name ? 1 : 0));
    const rankLines = ['RANKING'];
    for (let index = 0; index < ranking.length; index++) {
        const { puzzle, analysis, score } = ranking[index];
        rankLines.push(`rank ${index + 1} ${puzzle.name} ${analysis.difficulty} score=${score} size=${puzzle.w}x${puzzle.h}`);
    }
    paragraphs.push(rankLines.join('\n'));
    paragraphs.push(`SUMMARY puzzles=${puzzles.length} invalid=${totals.invalid} contradiction=${totals.contradiction}`
        + ` none=${totals.none} unique=${totals.unique} multiple=${totals.multiple}`
        + ` easy=${totals.easy} medium=${totals.medium} hard=${totals.hard}`
        + ` line_solves=${totals.lineSolves} guesses=${totals.guesses}`);
    return { solutions: paragraphs.join('\n\n') + '\n', stats: stats.join('\n') + '\n', sameClues };
}

function generatePicture(block, sameClues) {
    const grid = block.picture.map(line => Array.from(line, toState));
    const h = grid.length;
    const w = grid[0].length;
    const puzzle = { name: block.name, w, h, rows: grid.map(runClue),
        columns: Array.from({ length: w }, (_, c) => runClue(getLine(grid, 'C', c))) };
    const initial = analyze(puzzle, []);
    let analysis = initial;
    let givens = [];
    const lines = [
        `# picture ${block.name} size=${w}x${h} ${pictureFeatures(grid)}`,
        `# clues ${clueStatistics(puzzle)} duplicate_of=${sameClues.get(clueKey(puzzle)) ?? '-'}`,
        `# plain status=${initial.status} difficulty=${initial.difficulty} line_solves=${initial.lineSolves} guesses=${initial.guesses}`,
    ];
    while (analysis.status === 'multiple') {
        const { r, c } = differingCells(analysis.solutions[0], analysis.solutions[1])[0];
        const state = grid[r][c];
        givens.push({ r, c, state });
        analysis = analyze(puzzle, givens);
        lines.push(`# hint ${givens.length} cell=${r + 1},${c + 1} value=${stateChar(state)} status=${analysis.status}`);
    }
    // Removal visits the original addition order while each trial uses the current list.
    for (const given of givens.slice()) {
        const reduced = givens.filter(cell => cell !== given);
        const trial = analyze(puzzle, reduced);
        if (trial.status === 'unique') {
            givens = reduced;
            lines.push(`# drop cell=${given.r + 1},${given.c + 1}`);
        }
    }
    analysis = analyze(puzzle, givens);
    let logicHints = 0;
    while (analysis.difficulty === 'hard') {
        const { r, c } = chooseCell(analysis.logic.grid);
        const state = grid[r][c];
        givens.push({ r, c, state });
        analysis = analyze(puzzle, givens);
        logicHints++;
        lines.push(`# logic hint ${logicHints} cell=${r + 1},${c + 1} value=${stateChar(state)} difficulty=${analysis.difficulty}`);
    }
    lines.push(`# final status=${analysis.status} difficulty=${analysis.difficulty} hints=${givens.length}`
        + ` line_solves=${analysis.lineSolves} guesses=${analysis.guesses}`);
    lines.push('PUZZLE ' + block.name, `SIZE ${w} ${h}`, 'ROWS', ...puzzle.rows.map(spaceForm),
        'COLUMNS', ...puzzle.columns.map(spaceForm));
    const ordered = givens.slice().sort((a, b) => a.r - b.r || a.c - b.c);
    for (const given of ordered) lines.push(`GIVEN ${given.r + 1} ${given.c + 1} ${stateChar(given.state)}`);
    lines.push('END');
    return { paragraph: lines.join('\n'), initial, hintCount: givens.length };
}

function processPictures(text, sameClues) {
    const blocks = readPictures(text);
    const paragraphs = [];
    const seen = new Set();
    let invalid = 0;
    let unique = 0;
    let lineLogic = 0;
    let hinted = 0;
    let hints = 0;
    for (const block of blocks) {
        const error = validatePicture(block, seen);
        if (error !== null) {
            invalid++;
            paragraphs.push(`# picture ${block.name} error ${error}`);
            continue;
        }
        const generated = generatePicture(block, sameClues);
        paragraphs.push(generated.paragraph);
        if (generated.initial.status === 'unique') unique++;
        if (generated.initial.difficulty === 'easy' || generated.initial.difficulty === 'medium') lineLogic++;
        if (generated.hintCount > 0) hinted++;
        hints += generated.hintCount;
    }
    paragraphs.push(`# SUMMARY pictures=${blocks.length} invalid=${invalid} unique=${unique}`
        + ` line_logic=${lineLogic} hinted=${hinted} hints=${hints}`);
    return paragraphs.join('\n\n') + '\n';
}

function main() {
    const puzzles = processPuzzles(fs.readFileSync('input/puzzles.txt', 'ascii'));
    fs.mkdirSync('output', { recursive: true });
    fs.writeFileSync('output/solutions.txt', puzzles.solutions, 'ascii');
    fs.writeFileSync('output/stats.csv', puzzles.stats, 'ascii');
    const pictures = processPictures(fs.readFileSync('input/pictures.txt', 'ascii'), puzzles.sameClues);
    fs.writeFileSync('output/generated.txt', pictures, 'ascii');
}

if (require.main === module) main();
