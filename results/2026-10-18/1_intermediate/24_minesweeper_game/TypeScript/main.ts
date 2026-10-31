import { readFileSync } from 'node:fs';

type Safety = 'block' | 'cell' | 'none';
type GameState = 'ready' | 'playing' | 'won' | 'lost';
type Mark = 'none' | 'flag' | 'question';
type MoveKind = 'reveal' | 'flag' | 'unflag' | 'question' | 'chord' | 'auto-reveal' | 'auto-flag' | 'guess';
type UndoCommand = 'reveal' | 'flag' | 'unflag' | 'question' | 'chord' | 'auto' | 'solve';
type Probability = readonly [numerator: number, denominator: number];

type Move = Readonly<{ kind: MoveKind; cell: number }>;
interface UndoSnapshot {
    readonly command: UndoCommand;
    readonly visible: readonly boolean[];
    readonly marks: readonly Mark[];
    readonly moveCount: number;
}
interface Constraint {
    readonly cell: number;
    readonly cells: readonly number[];
    readonly remaining: number;
}
interface Component {
    readonly cells: number[];
    readonly constraints: Constraint[];
}
interface ConfigurationCounts {
    configs: number;
    minimum: number;
    maximum: number;
    frequencies: number[];
}
interface Deduction {
    safe: Map<number, string>;
    mines: Map<number, string>;
}
interface AutoTotals { rounds: number; flagged: number; opened: number }
interface SolveTotals extends AutoTotals { guesses: number }
interface Statistics {
    played: number;
    won: number;
    lost: number;
    streak: number;
    best: number;
    fastest: number | null;
}

class CommandError extends Error {}

function fail(message: string): never {
    throw new CommandError(message);
}

function fraction(numerator: number, denominator: number): string {
    let a = numerator;
    let b = denominator;
    while (b !== 0) [a, b] = [b, a % b];
    return `${numerator / a}/${denominator / a}`;
}

class Board {
    readonly size: number;
    readonly neighbors: readonly (readonly number[])[];
    mines: readonly boolean[] | null = null;
    numbers: readonly number[];
    visible: boolean[] = [];
    marks: Mark[] = [];
    moves: Move[] = [];
    undo: UndoSnapshot[] = [];
    exploded: number | null = null;
    state: GameState = 'ready';

    constructor(readonly width: number, readonly height: number,
                readonly mineCount: number, readonly seed: number) {
        this.size = width * height;
        this.numbers = Array<number>(this.size).fill(0);
        this.neighbors = Array.from({ length: this.size }, (_, cell) => {
            const result: number[] = [];
            const x = cell % width;
            const y = Math.floor(cell / width);
            for (let dy = -1; dy <= 1; dy++) {
                for (let dx = -1; dx <= 1; dx++) {
                    if ((dx === 0 && dy === 0) || x + dx < 0 || x + dx >= width ||
                        y + dy < 0 || y + dy >= height) continue;
                    result.push((y + dy) * width + x + dx);
                }
            }
            return result;
        });
        this.restart();
    }

    restart(): void {
        this.visible = Array<boolean>(this.size).fill(false);
        this.marks = Array<Mark>(this.size).fill('none');
        this.moves = [];
        this.undo = [];
        this.exploded = null;
        this.state = this.mines === null ? 'ready' : 'playing';
    }

    copy(): Board {
        const board = new Board(this.width, this.height, this.mineCount, this.seed);
        board.mines = this.mines;
        board.numbers = this.numbers;
        board.visible = [...this.visible];
        board.marks = [...this.marks];
        board.moves = [...this.moves];
        board.exploded = this.exploded;
        board.state = this.state;
        return board;
    }

    coordinate(cell: number): string {
        return `${cell % this.width},${Math.floor(cell / this.width)}`;
    }

    get finished(): boolean { return this.state === 'won' || this.state === 'lost'; }
    get safeCount(): number { return this.size - this.mineCount; }
    get revealedCount(): number { return this.visible.filter(Boolean).length; }
    get remaining(): number { return this.mineCount - this.marks.filter(mark => mark === 'flag').length; }

    unknown(cell: number): boolean {
        return !this.visible[cell] && this.marks[cell] !== 'flag';
    }

    determine(mines: readonly boolean[]): void {
        this.mines = mines;
        this.numbers = this.neighbors.map(cells => cells.filter(cell => mines[cell]).length);
        this.state = 'playing';
    }

    place(first: number, safety: Safety): void {
        const x = first % this.width;
        const y = Math.floor(first / this.width);
        const candidates: number[] = [];
        for (let cell = 0; cell < this.size; cell++) {
            if (safety === 'none' || (safety === 'cell' && cell !== first) ||
                (safety === 'block' && (Math.abs(cell % this.width - x) >= 2 ||
                    Math.abs(Math.floor(cell / this.width) - y) >= 2))) candidates.push(cell);
        }
        const mines = Array<boolean>(this.size).fill(false);
        let random = this.seed;
        for (let i = 0; i < this.mineCount; i++) {
            random = 48271 * random % 2147483647;
            const index = random % candidates.length;
            mines[candidates[index]] = true;
            candidates.splice(index, 1);
        }
        this.determine(mines);
    }

    reveal(cell: number, safety: Safety): number {
        if (this.mines === null) this.place(cell, safety);
        if (this.mines![cell]) {
            this.state = 'lost';
            this.exploded = cell;
            return 0;
        }
        const queue = [cell];
        this.visible[cell] = true;
        this.marks[cell] = 'none';
        for (let head = 0; head < queue.length; head++) {
            const current = queue[head];
            if (this.numbers[current] !== 0) continue;
            for (const next of this.neighbors[current]) {
                if (!this.unknown(next)) continue;
                this.visible[next] = true;
                this.marks[next] = 'none';
                queue.push(next);
            }
        }
        return queue.length;
    }

    chord(cell: number, safety: Safety): number {
        let opened = 0;
        for (const next of this.neighbors[cell]) {
            if (this.unknown(next)) opened += this.reveal(next, safety);
            if (this.state === 'lost') break;
        }
        return opened;
    }

    checkWin(): void {
        if (this.state !== 'playing' || this.revealedCount !== this.safeCount) return;
        this.state = 'won';
        for (let cell = 0; cell < this.size; cell++) {
            if (this.mines![cell]) this.marks[cell] = 'flag';
        }
    }

    display(): string[] {
        const cells = this.visible.map((visible, cell) => {
            const mark = this.marks[cell];
            if (this.state === 'lost') {
                if (this.mines![cell]) return cell === this.exploded ? '!' : mark === 'flag' ? 'F' : '*';
                if (mark === 'flag') return 'X';
            }
            if (visible) return this.numbers[cell] === 0 ? '.' : String(this.numbers[cell]);
            return mark === 'flag' ? 'F' : mark === 'question' ? '?' : '#';
        });
        return Array.from({ length: this.height }, (_, y) =>
            cells.slice(y * this.width, (y + 1) * this.width).join(''));
    }

    finishOutput(): string[] {
        if (this.state === 'lost') return [`boom ${this.coordinate(this.exploded!)}`, ...this.display()];
        if (this.state === 'won') return [`win moves ${this.moves.length}`];
        return [];
    }

    constraints(): Constraint[] {
        const result: Constraint[] = [];
        for (let cell = 0; cell < this.size; cell++) {
            if (!this.visible[cell] || this.numbers[cell] === 0) continue;
            const cells = this.neighbors[cell].filter(next => this.unknown(next));
            if (cells.length === 0) continue;
            const flags = this.neighbors[cell].filter(next => this.marks[next] === 'flag').length;
            result.push({ cell, cells, remaining: this.numbers[cell] - flags });
        }
        return result;
    }

    deduce(): Deduction {
        const constraints = this.constraints();
        const safe = new Map<number, string>();
        const mines = new Map<number, string>();
        const include = (target: Map<number, string>, cells: readonly number[], reason: string): void => {
            for (const cell of cells) if (!target.has(cell)) target.set(cell, reason);
        };
        for (const c of constraints) {
            if (c.remaining === 0) include(safe, c.cells, `single ${this.coordinate(c.cell)}`);
        }
        if (safe.size !== 0) return { safe, mines };
        for (const c of constraints) {
            if (c.remaining === c.cells.length) include(mines, c.cells, `single ${this.coordinate(c.cell)}`);
        }
        if (mines.size !== 0) return { safe, mines };
        for (const a of constraints) {
            for (const b of constraints) {
                if (a.cells.length >= b.cells.length || !a.cells.every(cell => b.cells.includes(cell))) continue;
                const difference = b.cells.filter(cell => !a.cells.includes(cell));
                const remaining = b.remaining - a.remaining;
                const reason = `subset ${this.coordinate(a.cell)} ${this.coordinate(b.cell)}`;
                if (remaining === 0) include(safe, difference, reason);
                if (remaining === difference.length) include(mines, difference, reason);
            }
        }
        if (safe.size === 0 && mines.size === 0 && this.state === 'playing' && this.remaining === 0) {
            for (let cell = 0; cell < this.size; cell++) if (this.unknown(cell)) safe.set(cell, 'count');
        }
        return { safe, mines };
    }

    frontier(): Component[] {
        const constraints = this.constraints();
        const parent = Array.from({ length: this.size }, (_, cell) => cell);
        const present = Array<boolean>(this.size).fill(false);
        const root = (cell: number): number => {
            while (parent[cell] !== cell) {
                parent[cell] = parent[parent[cell]];
                cell = parent[cell];
            }
            return cell;
        };
        for (const c of constraints) {
            for (const cell of c.cells) {
                present[cell] = true;
                parent[root(cell)] = root(c.cells[0]);
            }
        }
        const groups = new Map<number, Component>();
        for (let cell = 0; cell < this.size; cell++) {
            if (!present[cell]) continue;
            const representative = root(cell);
            if (!groups.has(representative)) groups.set(representative, { cells: [], constraints: [] });
            groups.get(representative)!.cells.push(cell);
        }
        for (const c of constraints) groups.get(root(c.cells[0]))!.constraints.push(c);
        return [...groups.values()];
    }

    auto(safety: Safety): AutoTotals {
        const totals: AutoTotals = { rounds: 0, flagged: 0, opened: 0 };
        while (this.state === 'playing') {
            const { safe, mines } = this.deduce();
            if (safe.size === 0 && mines.size === 0) break;
            totals.rounds++;
            for (const cell of [...safe.keys()].sort((a, b) => a - b)) {
                if (this.visible[cell]) continue;
                this.moves.push({ kind: 'auto-reveal', cell });
                totals.opened += this.reveal(cell, safety);
                this.checkWin();
                if (this.finished) return totals;
            }
            for (const cell of [...mines.keys()].sort((a, b) => a - b)) {
                if (!this.unknown(cell)) continue;
                this.marks[cell] = 'flag';
                totals.flagged++;
                this.moves.push({ kind: 'auto-flag', cell });
            }
        }
        return totals;
    }

    solve(safety: Safety): SolveTotals {
        const totals: SolveTotals = { guesses: 0, rounds: 0, flagged: 0, opened: 0 };
        while (!this.finished) {
            const automatic = this.auto(safety);
            totals.rounds += automatic.rounds;
            totals.flagged += automatic.flagged;
            totals.opened += automatic.opened;
            if (this.finished) break;
            const probabilities = Array<Probability | null>(this.size).fill(null);
            const onFrontier = Array<boolean>(this.size).fill(false);
            for (const component of this.frontier()) {
                const counts = countConfigurations(component);
                component.cells.forEach((cell, index) => {
                    onFrontier[cell] = true;
                    if (counts.configs !== 0) probabilities[cell] = [counts.frequencies[index], counts.configs];
                });
            }
            let unknownCount = 0;
            for (let cell = 0; cell < this.size; cell++) if (this.unknown(cell)) unknownCount++;
            const unconstrainedNumerator = Math.max(this.remaining, 0);
            let chosen = -1;
            let bestNumerator = 0;
            let bestDenominator = 1;
            for (let cell = 0; cell < this.size; cell++) {
                if (!this.unknown(cell)) continue;
                const probability: Probability | null = onFrontier[cell] ? probabilities[cell] : [unconstrainedNumerator, unknownCount];
                if (probability === null) continue;
                const [numerator, denominator] = probability;
                if (chosen === -1 || numerator * bestDenominator < bestNumerator * denominator) {
                    chosen = cell;
                    bestNumerator = numerator;
                    bestDenominator = denominator;
                }
            }
            if (chosen === -1) break;
            totals.guesses++;
            this.moves.push({ kind: 'guess', cell: chosen });
            totals.opened += this.reveal(chosen, safety);
            this.checkWin();
        }
        return totals;
    }

    replay(count: number, safety: Safety): string[] {
        const board = this.copy();
        board.restart();
        for (const move of this.moves.slice(0, count)) {
            switch (move.kind) {
                case 'reveal': case 'auto-reveal': case 'guess': board.reveal(move.cell, safety); break;
                case 'chord': board.chord(move.cell, safety); break;
                case 'flag': case 'auto-flag': board.marks[move.cell] = 'flag'; break;
                case 'unflag': board.marks[move.cell] = 'none'; break;
                case 'question': board.marks[move.cell] = board.marks[move.cell] === 'question' ? 'none' : 'question'; break;
            }
            board.checkWin();
        }
        return board.display();
    }

    boardInfo(): string {
        const mines = this.mines!;
        const visited = Array<boolean>(this.size).fill(false);
        let openings = 0;
        let largest = 0;
        let isolatedNumbers = 0;
        for (let cell = 0; cell < this.size; cell++) {
            if (mines[cell]) continue;
            if (this.numbers[cell] !== 0) {
                if (!this.neighbors[cell].some(next => !mines[next] && this.numbers[next] === 0)) isolatedNumbers++;
                continue;
            }
            if (visited[cell]) continue;
            openings++;
            const queue = [cell];
            const opening = new Set([cell]);
            visited[cell] = true;
            for (let head = 0; head < queue.length; head++) {
                for (const next of this.neighbors[queue[head]]) {
                    opening.add(next);
                    if (!mines[next] && this.numbers[next] === 0 && !visited[next]) {
                        visited[next] = true;
                        queue.push(next);
                    }
                }
            }
            largest = Math.max(largest, opening.size);
        }
        return `3bv ${openings + isolatedNumbers} openings ${openings} largest ${largest} mines ${this.mineCount} safe ${this.safeCount}`;
    }
}

function countConfigurations(component: Component): ConfigurationCounts {
    const positions = new Map<number, number>(component.cells.map((cell, index): [number, number] => [cell, index]));
    const constraints = component.constraints.map(c => ({
        cells: c.cells.map(cell => positions.get(cell)!), remaining: c.remaining,
    }));
    const incidence = Array.from({ length: component.cells.length }, (): number[] => []);
    constraints.forEach((c, index) => {
        for (const cell of c.cells) incidence[cell].push(index);
    });
    const assigned = Array<number>(constraints.length).fill(0);
    const unassigned = constraints.map(c => c.cells.length);
    const values = Array<number>(component.cells.length).fill(0);
    const result: ConfigurationCounts = { configs: 0, minimum: component.cells.length, maximum: 0, frequencies: values.slice() };
    if (constraints.some(c => c.remaining < 0 || c.remaining > c.cells.length)) return result;
    const order = component.cells.map((_, index) => index).sort((a, b) => incidence[b].length - incidence[a].length || a - b);
    const search = (depth: number, mineCount: number): void => {
        if (depth === order.length) {
            result.configs++;
            result.minimum = Math.min(result.minimum, mineCount);
            result.maximum = Math.max(result.maximum, mineCount);
            values.forEach((value, index) => { result.frequencies[index] += value; });
            return;
        }
        const cell = order[depth];
        for (let value = 0; value <= 1; value++) {
            values[cell] = value;
            let possible = true;
            for (const index of incidence[cell]) {
                assigned[index] += value;
                unassigned[index]--;
                const target = constraints[index].remaining;
                if (assigned[index] > target || assigned[index] + unassigned[index] < target) possible = false;
            }
            if (possible) search(depth + 1, mineCount + value);
            for (const index of incidence[cell]) {
                assigned[index] -= value;
                unassigned[index]++;
            }
        }
        values[cell] = 0;
    };
    search(0, 0);
    return result;
}

const formats = {
    NEW: 'nnnn', PRESET: 'pn', SAFETY: 's', RESTART: '',
    REVEAL: 'nn', FLAG: 'nn', UNFLAG: 'nn', QUESTION: 'nn', CHORD: 'nn',
    UNDO: '', SHOW: '', STATUS: '', CELL: 'nn', HISTORY: 'n', REPLAY: 'n',
    HINT: '', AUTO: '', ANALYZE: '', PROB: 'nn', FRONTIER: '', SOLVE: '', BOARDINFO: '', STATS: '',
} as const;
type RegularCommand = keyof typeof formats;
type BoardCommand = Exclude<RegularCommand, 'NEW' | 'PRESET' | 'SAFETY' | 'STATS'>;

function isCommand(word: string): word is RegularCommand {
    return Object.hasOwn(formats, word);
}
function isSafety(word: string): word is Safety {
    return word === 'block' || word === 'cell' || word === 'none';
}
const presets = new Map<string, readonly [number, number, number]>([
    ['beginner', [9, 9, 10]], ['intermediate', [16, 16, 40]], ['expert', [30, 16, 99]],
]);
const cellCommands = new Set<RegularCommand>(['REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'CELL', 'PROB']);
const liveCommands = new Set<RegularCommand>(['REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'UNDO', 'HINT', 'AUTO', 'ANALYZE', 'PROB', 'FRONTIER', 'SOLVE']);
const undoKinds = new Map<RegularCommand, UndoCommand>([
    ['REVEAL', 'reveal'], ['FLAG', 'flag'], ['UNFLAG', 'unflag'], ['QUESTION', 'question'],
    ['CHORD', 'chord'], ['AUTO', 'auto'], ['SOLVE', 'solve'],
]);
const manualMoveKinds = { REVEAL: 'reveal', FLAG: 'flag', UNFLAG: 'unflag', QUESTION: 'question' } as const;

class Program {
    board: Board | null = null;
    safety: Safety = 'block';
    readonly stats: Statistics = { played: 0, won: 0, lost: 0, streak: 0, best: 0, fastest: null };

    execute(words: readonly string[], rows: readonly string[]): string[] {
        const [command, ...args] = words;
        if (command === 'LAYOUT') {
            const [width, height] = args.map(Number);
            const badRow = rows.findIndex(row => row.length !== width || /[^*.]/.test(row));
            if (badRow !== -1) fail(`bad row ${badRow + 1}`);
            const mines = rows.join('').split('').map(cell => cell === '*');
            const count = mines.filter(Boolean).length;
            if (count === 0 || count === width * height) fail(`bad mine count ${count}`);
            this.board = new Board(width, height, count, 1);
            this.board.determine(mines);
            return [`layout ${width}x${height} mines ${count}`];
        }
        if (!isCommand(command)) fail(`unknown command ${command}`);
        const format = formats[command];
        if (args.length !== format.length) fail('bad arguments');
        for (let i = 0; i < args.length; i++) {
            const valid = format[i] === 'n' ? /^(?:0|[1-9][0-9]{0,9})$/.test(args[i]) :
                format[i] === 'p' ? presets.has(args[i]) : isSafety(args[i]);
            if (!valid) fail('bad arguments');
        }
        const numbers = args.map(Number);
        if (command === 'NEW' || command === 'PRESET') {
            const [width, height, count, seed] = command === 'NEW' ? numbers : [...presets.get(args[0])!, numbers[1]];
            if (width < 1 || width > 30 || height < 1 || height > 30 || count < 1 ||
                count > width * height - 9 || seed < 1 || seed > 2147483646) fail('bad value');
            this.board = new Board(width, height, count, seed);
            return [`new ${width}x${height} mines ${count}`];
        }
        if (command === 'HISTORY' && numbers[0] === 0) fail('bad value');
        if (command === 'SAFETY') {
            this.safety = args[0] as Safety;
            return [`safety ${this.safety}`];
        }
        if (command === 'STATS') {
            const s = this.stats;
            const rate = s.played === 0 ? '-' : `${Math.floor(s.won * 100 / s.played)}%`;
            return [`stats played ${s.played} won ${s.won} lost ${s.lost} rate ${rate} streak ${s.streak} best ${s.best} fastest ${s.fastest ?? '-'}`];
        }
        const board = this.board;
        if (board === null) fail('no game');
        if (cellCommands.has(command) && (numbers[0] >= board.width || numbers[1] >= board.height)) fail('out of range');
        if (liveCommands.has(command) && board.finished) fail('game over');
        if ((command === 'ANALYZE' || command === 'BOARDINFO') && board.state === 'ready') fail('not started');
        const cell = numbers[1] * board.width + numbers[0];
        const undoKind = undoKinds.get(command);
        const snapshot: UndoSnapshot | null = undoKind === undefined ? null : {
            command: undoKind, visible: [...board.visible], marks: [...board.marks], moveCount: board.moves.length,
        };
        const response = this.boardCommand(command, numbers, cell, board);
        if (snapshot !== null && board.moves.length > snapshot.moveCount) board.undo.push(snapshot);
        if (['REVEAL', 'CHORD', 'AUTO', 'SOLVE'].includes(command) && board.finished) {
            const s = this.stats;
            s.played++;
            if (board.state === 'won') {
                s.won++;
                s.streak++;
                s.best = Math.max(s.best, s.streak);
                s.fastest = Math.min(s.fastest ?? board.moves.length, board.moves.length);
            } else {
                s.lost++;
                s.streak = 0;
            }
        }
        return response;
    }

    boardCommand(command: BoardCommand, numbers: readonly number[], cell: number, board: Board): string[] {
        const coordinate = () => board.coordinate(cell);
        switch (command) {
            case 'RESTART':
                board.restart();
                return [`restart ${board.width}x${board.height} mines ${board.mineCount}`];
            case 'REVEAL': case 'FLAG': case 'UNFLAG': case 'QUESTION': {
                if (board.visible[cell]) fail('already revealed');
                const mark = board.marks[cell];
                if (command === 'REVEAL' && mark === 'flag') fail('flagged');
                if (command === 'FLAG' && mark === 'flag') fail('already flagged');
                if (command === 'UNFLAG' && mark !== 'flag') fail('not flagged');
                board.moves.push({ kind: manualMoveKinds[command], cell });
                if (command === 'REVEAL') {
                    const opened = board.reveal(cell, this.safety);
                    if (board.state === 'lost') return board.finishOutput();
                    board.checkWin();
                    return [`revealed ${opened}`, ...board.finishOutput()];
                }
                board.marks[cell] = command === 'FLAG' ? 'flag' : command === 'UNFLAG' || mark === 'question' ? 'none' : 'question';
                const action = command === 'FLAG' ? 'flagged' : command === 'UNFLAG' ? 'unflagged' : mark === 'question' ? 'unmarked' : 'questioned';
                return [`${action} ${coordinate()} left ${board.remaining}`];
            }
            case 'CHORD': {
                if (!board.visible[cell]) fail('not revealed');
                const number = board.numbers[cell];
                if (number === 0) fail('no number');
                const flags = board.neighbors[cell].filter(next => board.marks[next] === 'flag').length;
                if (flags !== number) fail(`flags ${flags} of ${number}`);
                if (!board.neighbors[cell].some(next => board.unknown(next))) fail('nothing to reveal');
                board.moves.push({ kind: 'chord', cell });
                const opened = board.chord(cell, this.safety);
                if (board.state === 'lost') return board.finishOutput();
                board.checkWin();
                return [`chorded ${opened}`, ...board.finishOutput()];
            }
            case 'UNDO': {
                if (board.undo.length === 0) fail('nothing to undo');
                const previous = board.undo.pop()!;
                board.visible = [...previous.visible];
                board.marks = [...previous.marks];
                board.moves.length = previous.moveCount;
                return [`undo ${previous.command} moves ${board.moves.length}`];
            }
            case 'SHOW': return board.display();
            case 'STATUS': return [`status ${board.state} left ${board.remaining} moves ${board.moves.length} revealed ${board.revealedCount}/${board.safeCount}`];
            case 'CELL': {
                const neighbors = board.neighbors[cell];
                if (!board.visible[cell]) return [`cell ${coordinate()} hidden mark ${board.marks[cell]} open ${neighbors.filter(next => board.visible[next]).length}`];
                const flags = neighbors.filter(next => board.marks[next] === 'flag').length;
                return [`cell ${coordinate()} number ${board.numbers[cell]} flags ${flags} unknown ${neighbors.filter(next => board.unknown(next)).length}`];
            }
            case 'HISTORY': {
                const lines = [`history ${board.moves.length}`];
                for (let i = Math.max(0, board.moves.length - numbers[0]); i < board.moves.length; i++) {
                    lines.push(`${i + 1} ${board.moves[i].kind} ${board.coordinate(board.moves[i].cell)}`);
                }
                return lines;
            }
            case 'REPLAY':
                if (numbers[0] > board.moves.length) fail(`no move ${numbers[0]}`);
                return [`replay ${numbers[0]}/${board.moves.length}`, ...board.replay(numbers[0], this.safety)];
            case 'HINT': {
                const { safe, mines } = board.deduce();
                const choices = safe.size !== 0 ? safe : mines;
                if (choices.size === 0) return ['hint none'];
                const chosen = Math.min(...choices.keys());
                return [`hint ${safe.size !== 0 ? 'safe' : 'mine'} ${board.coordinate(chosen)} by ${choices.get(chosen)}`];
            }
            case 'AUTO': {
                const result = board.auto(this.safety);
                return [`auto rounds ${result.rounds} flagged ${result.flagged} revealed ${result.opened}`, ...board.finishOutput()];
            }
            case 'ANALYZE': {
                const copy = board.copy();
                const result = copy.auto(this.safety);
                if (copy.state === 'lost') return [`analyze boom ${copy.coordinate(copy.exploded!)} rounds ${result.rounds}`];
                if (copy.state === 'won') return [`analyze clear rounds ${result.rounds}`];
                return [`analyze stuck rounds ${result.rounds} revealed ${copy.revealedCount}/${copy.safeCount}`];
            }
            case 'PROB': {
                if (board.visible[cell]) fail('already revealed');
                if (board.marks[cell] === 'flag') fail('flagged');
                const component = board.frontier().find(group => group.cells.includes(cell));
                if (component === undefined) return [`prob ${coordinate()} unconstrained`];
                const result = countConfigurations(component);
                if (result.configs === 0) return [`prob ${coordinate()} inconsistent`];
                return [`prob ${coordinate()} ${fraction(result.frequencies[component.cells.indexOf(cell)], result.configs)} size ${component.cells.length} configs ${result.configs}`];
            }
            case 'FRONTIER': {
                const components = board.frontier();
                const lines = [`frontier ${components.reduce((sum, c) => sum + c.cells.length, 0)} components ${components.length}`];
                for (const component of components) {
                    const result = countConfigurations(component);
                    const prefix = `component ${board.coordinate(component.cells[0])} size ${component.cells.length}`;
                    lines.push(result.configs === 0 ? `${prefix} inconsistent` : `${prefix} configs ${result.configs} min ${result.minimum} max ${result.maximum}`);
                }
                return lines;
            }
            case 'SOLVE': {
                const result = board.solve(this.safety);
                return [`solve guesses ${result.guesses} rounds ${result.rounds} flagged ${result.flagged} revealed ${result.opened}`, ...board.finishOutput()];
            }
            case 'BOARDINFO': return [board.boardInfo()];
        }
        throw new Error('Unreachable command');
    }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/);
const commandCount = Number(lines[0]);
const program = new Program();
let cursor = 1;
for (let i = 0; i < commandCount; i++) {
    const words = lines[cursor++].split(' ');
    const rowCount = words[0] === 'LAYOUT' ? Number(words[2]) : 0;
    const rows = lines.slice(cursor, cursor + rowCount);
    cursor += rowCount;
    try {
        process.stdout.write(program.execute(words, rows).join('\n') + '\n');
    } catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`error: ${error.message}\n`);
    }
}
