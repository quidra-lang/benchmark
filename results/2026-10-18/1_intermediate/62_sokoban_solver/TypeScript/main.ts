import { readFileSync } from 'node:fs';

type Direction = 'u' | 'd' | 'l' | 'r';
type Transform = 'ROT90' | 'ROT180' | 'ROT270' | 'FLIPH' | 'FLIPV';
type ArgumentKind = 'text' | 'number' | 'steps' | 'direction' | 'name' | 'transform';
interface Position { readonly player: number; readonly boxes: readonly number[]; }
interface Step { position: Position; letter: string; }
interface CameFrom { cell: number; direction: Direction; }
interface Push { box: number; direction: Direction; }
interface SearchNode {
    boxes: readonly number[];
    representative: number;
    parent: number;
    push: Push | null;
}
interface SearchResult {
    outcome: 'found' | 'limit' | 'no solution';
    expanded: number;
    states: number;
    notation: string;
}
interface Simulation { position: Position; letters: string; failure: string | null; }
interface Summary { text: string; notation: string | null; }
interface Snapshot { position: Position; history: string; }
interface Solution { notation: string; position: Position; }
interface Assignment { order: number[]; pushes: number[]; total: number; }
interface LoadedLevel { level: Level; position: Position; }
const DIRECTIONS: readonly Direction[] = ['u', 'd', 'l', 'r'];
const DELTAS: readonly (readonly [number, number])[] = [[-1, 0], [1, 0], [0, -1], [0, 1]];
const TURNS = new Map<string, string>([
    ['ROT90', 'rlud'], ['ROT180', 'durl'], ['ROT270', 'lrdu'],
    ['FLIPH', 'udrl'], ['FLIPV', 'dulr'],
]);
const LEVEL_CHARACTERS = '#-.$*@+';
const STEP_LETTERS = 'udlrUDLR';
const COMMANDS = new Map<string, readonly ArgumentKind[]>([
    ['IMPORT', ['text']], ['VALID', []], ['INFO', []], ['SHOW', []], ['EXPORT', []],
    ['MOVE', ['steps']], ['PUSH', ['number', 'number', 'direction']],
    ['BRING', ['number', 'number', 'number', 'number']], ['PATH', ['number', 'number']],
    ['UNDO', ['number']], ['REDO', ['number']], ['RESET', []], ['STATUS', []],
    ['HISTORY', []], ['BOXES', []], ['REACH', []], ['DEADSQUARES', []],
    ['DEADLOCK', []], ['BOUND', []], ['SAVE', ['name']], ['RESTORE', ['name']],
    ['CHECK', ['steps']], ['SOLVE', ['number']], ['HINT', ['number']],
    ['PLAY', []], ['TRANSFORM', ['transform']],
]);

class CommandError extends Error {}
class StepFailure extends Error {}

function decode(text: string, allowed: string): string | null {
    let result = '';
    for (let index = 0; index < text.length;) {
        const start = index;
        while (index < text.length && text[index] >= '0' && text[index] <= '9') index++;
        const count = text.slice(start, index);
        if (count.length > 2 || count.startsWith('0') || index === text.length) return null;
        const symbol = text[index++];
        if (!allowed.includes(symbol)) return null;
        result += symbol.repeat(count ? Number(count) : 1);
    }
    return result;
}

function encode(text: string): string {
    let result = '';
    for (let start = 0; start < text.length;) {
        let end = start + 1;
        while (end < text.length && text[end] === text[start]) end++;
        const count = end - start;
        result += (count > 1 ? String(count) : '') + text[start];
        start = end;
    }
    return result;
}

function validArgument(kind: ArgumentKind, text: string): boolean {
    switch (kind) {
        case 'number': return /^(0|[1-9][0-9]{0,5})$/.test(text);
        case 'steps': return decode(text, STEP_LETTERS) !== null;
        case 'direction': return DIRECTIONS.some(direction => direction === text);
        case 'name': return /^[a-z]{1,8}$/.test(text);
        case 'transform': return TURNS.has(text);
        default: return true;
    }
}

function directionOf(letter: string): Direction { return letter.toLowerCase() as Direction; }
function pushCount(letters: string): number { return [...letters].filter(letter => letter !== letter.toLowerCase()).length; }
function moveBox(boxes: readonly number[], source: number, destination: number): number[] {
    return boxes.map(box => box === source ? destination : box).sort((a, b) => a - b);
}
function samePosition(a: Position, b: Position): boolean {
    return a.player === b.player && a.boxes.length === b.boxes.length
        && a.boxes.every((box, index) => box === b.boxes[index]);
}
function turnLetters(letters: string, kind: Transform): string {
    const turn = TURNS.get(kind)!;
    return [...letters].map(letter => {
        const direction = turn[DIRECTIONS.indexOf(directionOf(letter))];
        return letter === letter.toLowerCase() ? direction : direction.toUpperCase();
    }).join('');
}
function counted(label: string, letters: string): string {
    return letters.length ? `${label} ${letters.length} ${letters}` : `${label} 0`;
}
function countTrue(flags: readonly boolean[]): number { return flags.filter(Boolean).length; }

function findInterior(height: number, width: number, walls: readonly boolean[], start: number): boolean[] {
    const seen = Array<boolean>(height * width).fill(false);
    const queue = [start];
    seen[start] = true;
    for (let head = 0; head < queue.length; head++) {
        const cell = queue[head];
        const row = Math.floor(cell / width), column = cell % width;
        for (const [dr, dc] of DELTAS) {
            const r = row + dr, c = column + dc;
            if (r < 0 || r >= height || c < 0 || c >= width) continue;
            const neighbor = r * width + c;
            if (!walls[neighbor] && !seen[neighbor]) {
                seen[neighbor] = true;
                queue.push(neighbor);
            }
        }
    }
    return seen;
}

class Level {
    readonly height: number;
    readonly width: number;
    readonly size: number;
    readonly walls: readonly boolean[];
    readonly goals: readonly boolean[];
    readonly interior: readonly boolean[];
    readonly offsets: readonly number[];
    readonly goalCells: readonly number[];
    reason: string | null;
    distances: number[][];
    dead: boolean[];
    constructor(height: number, width: number, walls: readonly boolean[], goals: readonly boolean[], interior: readonly boolean[]) {
        this.height = height;
        this.width = width;
        this.size = height * width;
        this.walls = walls;
        this.goals = goals;
        this.interior = interior;
        this.offsets = [-width, width, -1, 1];
        this.goalCells = Array.from({length: this.size}, (_, cell) => cell).filter(cell => goals[cell]);
        this.reason = null;
        this.distances = [];
        this.dead = Array<boolean>(this.size).fill(false);
    }

    offsetOf(direction: Direction): number { return this.offsets[DIRECTIONS.indexOf(direction)]; }
    cellText(cell: number): string { return `${Math.floor(cell / this.width) + 1} ${cell % this.width + 1}`; }
    cellAt(row: number, column: number): number { return (row - 1) * this.width + column - 1; }
    contains(row: number, column: number): boolean { return row >= 1 && row <= this.height && column >= 1 && column <= this.width; }
    onBorder(cell: number): boolean {
        const row = Math.floor(cell / this.width), column = cell % this.width;
        return row === 0 || row === this.height - 1 || column === 0 || column === this.width - 1;
    }

    invalidity(players: number, boxes: readonly number[]): string | null {
        if (players !== 1) return `players ${players}`;
        if (!boxes.length) return 'no boxes';
        if (boxes.length !== this.goalCells.length) return `boxes ${boxes.length} goals ${this.goalCells.length}`;
        for (let cell = 0; cell < this.size; cell++) {
            if (this.interior[cell] && this.onBorder(cell)) return `open ${this.cellText(cell)}`;
        }
        for (let cell = 0; cell < this.size; cell++) {
            if ((this.goals[cell] || boxes.includes(cell)) && !this.interior[cell]) return `outside ${this.cellText(cell)}`;
        }
        return null;
    }

    analyze(): void {
        this.distances = this.goalCells.map(goal => this.pushDistances(goal));
        this.dead = this.interior.map((inside, cell) => inside && this.distances.every(distance => distance[cell] === -1));
    }

    pushDistances(goal: number): number[] {
        const distance = Array<number>(this.size).fill(-1);
        const queue = [goal];
        distance[goal] = 0;
        for (let head = 0; head < queue.length; head++) {
            const cell = queue[head];
            for (const offset of this.offsets) {
                const box = cell - offset;
                if (this.interior[box] && this.interior[box - offset] && distance[box] === -1) {
                    distance[box] = distance[cell] + 1;
                    queue.push(box);
                }
            }
        }
        return distance;
    }

    goalDistance(cell: number): number | null {
        const defined = this.distances.map(distance => distance[cell]).filter(distance => distance >= 0);
        return defined.length ? Math.min(...defined) : null;
    }
    boxesOnGoals(boxes: readonly number[]): number { return boxes.filter(box => this.goals[box]).length; }
    solved(boxes: readonly number[]): boolean { return this.boxesOnGoals(boxes) === boxes.length; }

    reachable(player: number, boxes: readonly number[]): boolean[] {
        const seen = Array<boolean>(this.size).fill(false);
        const queue = [player];
        seen[player] = true;
        for (let head = 0; head < queue.length; head++) {
            for (const offset of this.offsets) {
                const neighbor = queue[head] + offset;
                if (this.interior[neighbor] && !seen[neighbor] && !boxes.includes(neighbor)) {
                    seen[neighbor] = true;
                    queue.push(neighbor);
                }
            }
        }
        return seen;
    }
    representative(player: number, boxes: readonly number[]): number { return this.reachable(player, boxes).indexOf(true); }

    walkPath(start: number, target: number, boxes: readonly number[]): string {
        const cameFrom = Array<CameFrom | null>(this.size).fill(null);
        const queue = [start];
        for (let head = 0; head < queue.length; head++) {
            const cell = queue[head];
            for (const direction of DIRECTIONS) {
                const neighbor = cell + this.offsetOf(direction);
                if (this.interior[neighbor] && !boxes.includes(neighbor)
                    && neighbor !== start && cameFrom[neighbor] === null) {
                    cameFrom[neighbor] = {cell, direction};
                    queue.push(neighbor);
                }
            }
        }
        const path: Direction[] = [];
        for (let cell = target; cell !== start;) {
            const from = cameFrom[cell]!;
            path.push(from.direction);
            cell = from.cell;
        }
        return path.reverse().join('');
    }

    step(position: Position, direction: Direction): Step {
        const offset = this.offsetOf(direction);
        const target = position.player + offset;
        if (this.walls[target]) throw new StepFailure('wall');
        if (!position.boxes.includes(target)) {
            return {position: {player: target, boxes: position.boxes}, letter: direction};
        }
        const beyond = target + offset;
        if (this.walls[beyond] || position.boxes.includes(beyond)) throw new StepFailure('blocked');
        return {position: {player: target, boxes: moveBox(position.boxes, target, beyond)}, letter: direction.toUpperCase()};
    }

    pushable(box: number, direction: Direction, boxes: readonly number[], reachable: readonly boolean[]): boolean {
        const offset = this.offsetOf(direction), destination = box + offset;
        return !!reachable[box - offset] && !!this.interior[destination] && !boxes.includes(destination);
    }
    sideBlocked(box: number, sides: readonly number[], boxes: readonly number[], assumed: readonly number[]): boolean {
        if (sides.some(side => this.walls[side] || assumed.includes(side))) return true;
        if (sides.every(side => this.dead[side])) return true;
        const extended = [...assumed, box];
        return sides.some(side => boxes.includes(side) && this.frozen(side, boxes, extended));
    }
    frozen(box: number, boxes: readonly number[], assumed: readonly number[] = []): boolean {
        return this.sideBlocked(box, [box - 1, box + 1], boxes, assumed)
            && this.sideBlocked(box, [box - this.width, box + this.width], boxes, assumed);
    }
    hasFrozenBox(boxes: readonly number[]): boolean { return boxes.some(box => !this.goals[box] && this.frozen(box, boxes)); }

    splitRows(symbols: string): string[] {
        const rows: string[] = [];
        for (let start = 0; start < this.size; start += this.width) rows.push(symbols.slice(start, start + this.width));
        return rows;
    }
    render(position: Position): string[] {
        let symbols = '';
        for (let cell = 0; cell < this.size; cell++) {
            if (this.walls[cell]) symbols += '#';
            else if (cell === position.player) symbols += this.goals[cell] ? '+' : '@';
            else if (position.boxes.includes(cell)) symbols += this.goals[cell] ? '*' : '$';
            else symbols += this.goals[cell] ? '.' : '-';
        }
        return this.splitRows(symbols);
    }
    deadMap(): string[] {
        let symbols = '';
        for (let cell = 0; cell < this.size; cell++) {
            symbols += this.walls[cell] ? '#' : this.goals[cell] ? '.' : this.dead[cell] ? 'x' : '-';
        }
        return this.splitRows(symbols);
    }

    mapCell(kind: Transform, cell: number): number {
        const row = Math.floor(cell / this.width), column = cell % this.width;
        switch (kind) {
            case 'ROT90': return column * this.height + this.height - 1 - row;
            case 'ROT180': return (this.height - 1 - row) * this.width + this.width - 1 - column;
            case 'ROT270': return (this.width - 1 - column) * this.height + row;
            case 'FLIPH': return row * this.width + this.width - 1 - column;
            default: return (this.height - 1 - row) * this.width + column;
        }
    }
    mapPosition(kind: Transform, position: Position): Position {
        return {player: this.mapCell(kind, position.player), boxes: position.boxes.map(box => this.mapCell(kind, box)).sort((a, b) => a - b)};
    }
    transformed(kind: Transform): Level {
        const rotated = kind === 'ROT90' || kind === 'ROT270';
        const walls = Array<boolean>(this.size).fill(false), goals = Array<boolean>(this.size).fill(false), interior = Array<boolean>(this.size).fill(false);
        for (let cell = 0; cell < this.size; cell++) {
            const moved = this.mapCell(kind, cell);
            walls[moved] = this.walls[cell];
            goals[moved] = this.goals[cell];
            interior[moved] = this.interior[cell];
        }
        const level = new Level(rotated ? this.width : this.height, rotated ? this.height : this.width, walls, goals, interior);
        level.analyze();
        return level;
    }
}

function buildLevel(rows: readonly string[]): LoadedLevel {
    const height = rows.length, width = rows[0].length;
    const cells = [...rows.join('')];
    const walls = cells.map(symbol => symbol === '#'), goals = cells.map(symbol => '.*+'.includes(symbol));
    const players: number[] = [], boxes: number[] = [];
    cells.forEach((symbol, cell) => {
        if ('@+'.includes(symbol)) players.push(cell);
        if ('$*'.includes(symbol)) boxes.push(cell);
    });
    const interior = players.length === 1 ? findInterior(height, width, walls, players[0]) : Array<boolean>(cells.length).fill(false);
    const level = new Level(height, width, walls, goals, interior);
    level.reason = level.invalidity(players.length, boxes);
    if (level.reason === null) level.analyze();
    return {level, position: {player: players.length ? players[0] : -1, boxes}};
}

function stateKey(boxes: readonly number[], representative: number): string { return `${boxes.join(',')}:${representative}`; }
function solutionNotation(level: Level, start: Position, nodes: readonly SearchNode[]): string {
    const pushes: Push[] = [];
    for (let node = nodes[nodes.length - 1]; node.parent !== -1; node = nodes[node.parent]) {
        if (node.push !== null) pushes.push(node.push);
    }
    let position = start, notation = '';
    for (const {box, direction} of pushes.reverse()) {
        const offset = level.offsetOf(direction);
        notation += level.walkPath(position.player, box - offset, position.boxes) + direction.toUpperCase();
        position = {player: box, boxes: moveBox(position.boxes, box, box + offset)};
    }
    return notation;
}

function pushSearch(level: Level, start: Position, fixed: readonly number[], target: number | null, pruning: boolean, limit: number | null): SearchResult {
    const representative = level.representative(start.player, start.boxes);
    const nodes: SearchNode[] = [{boxes: start.boxes, representative, parent: -1, push: null}];
    const known = new Set([stateKey(start.boxes, representative)]);
    let expanded = 0;
    while (expanded < nodes.length) {
        if (limit !== null && expanded === limit) return {outcome: 'limit', expanded, states: nodes.length, notation: ''};
        const parent = expanded, node = nodes[expanded++];
        const reachable = level.reachable(node.representative, node.boxes);
        for (const box of node.boxes) {
            if (fixed.includes(box)) continue;
            for (const direction of DIRECTIONS) {
                if (!level.pushable(box, direction, node.boxes, reachable)) continue;
                const destination = box + level.offsetOf(direction);
                const boxes = moveBox(node.boxes, box, destination);
                if (pruning && (level.dead[destination] || level.hasFrozenBox(boxes))) continue;
                const nextRepresentative = level.representative(box, boxes);
                const key = stateKey(boxes, nextRepresentative);
                if (known.has(key)) continue;
                known.add(key);
                nodes.push({boxes, representative: nextRepresentative, parent, push: {box, direction}});
                if (target === null ? level.solved(boxes) : destination === target) {
                    return {outcome: 'found', expanded, states: nodes.length, notation: solutionNotation(level, start, nodes)};
                }
            }
        }
    }
    return {outcome: 'no solution', expanded, states: nodes.length, notation: ''};
}

class Sokoban {
    readonly output: string[];
    private level!: Level;
    private initial!: Position;
    private current!: Position;
    private history = '';
    private redoList = '';
    private snapshots = new Map<string, Snapshot>();
    private solution: Solution | null = null;
    constructor(rows: readonly string[]) {
        this.output = [];
        this.load(rows);
    }
    emit(...parts: (string | number)[]): void { this.output.push(parts.join(' ')); }
    load(rows: readonly string[]): void {
        const loaded = buildLevel(rows);
        this.level = loaded.level;
        this.initial = loaded.position;
        this.current = this.initial;
        this.history = '';
        this.redoList = '';
        this.snapshots = new Map<string, Snapshot>();
        this.solution = null;
    }
    cellArgument(args: readonly string[], index: number): number { return this.level.cellAt(Number(args[index]), Number(args[index + 1])); }

    simulate(directions: string): Simulation {
        let position = this.current, letters = '';
        for (const letter of directions) {
            try {
                const step = this.level.step(position, directionOf(letter));
                position = step.position;
                letters += step.letter;
            } catch (error) {
                if (!(error instanceof StepFailure)) throw error;
                return {position, letters, failure: `step ${letters.length + 1} ${error.message}`};
            }
        }
        return {position, letters, failure: null};
    }
    takeSteps(directions: string): Simulation {
        const result = this.simulate(directions);
        this.current = result.position;
        this.history += result.letters;
        if (result.letters.length) this.redoList = '';
        return result;
    }
    progress(boxes: readonly number[]): string {
        const count = this.level.boxesOnGoals(boxes);
        return `goals ${count}/${boxes.length}` + (count === boxes.length ? ' solved' : '');
    }
    searchSolution(limit: number): Summary {
        if (this.level.solved(this.current.boxes)) return {text: 'already solved', notation: null};
        const result = pushSearch(this.level, this.current, [], null, true, limit);
        const counts = `expanded ${result.expanded} states ${result.states}`;
        if (result.outcome !== 'found') return {text: `${result.outcome} ${counts}`, notation: null};
        const notation = result.notation;
        return {text: `solution pushes ${pushCount(notation)} moves ${notation.length} ${counts}`, notation};
    }

    loadRows(width: number, rows: readonly string[]): void {
        const bad = rows.findIndex(row => row.length !== width || [...row].some(symbol => !LEVEL_CHARACTERS.includes(symbol)));
        if (bad !== -1) throw new CommandError(`bad row ${bad + 1}`);
        this.load(rows);
        this.emit('loaded', `${rows.length}x${width}`);
    }
    importLevel(text: string): void {
        const rows: string[] = [];
        for (const part of text.split('|')) {
            const row = decode(part, LEVEL_CHARACTERS);
            if (row === null) throw new CommandError('bad level');
            rows.push(row);
        }
        const width = rows[0].length;
        if (rows.length > 10 || width < 1 || width > 10 || rows.some(row => row.length !== width)) throw new CommandError('bad level');
        this.load(rows);
        this.emit('loaded', `${rows.length}x${width}`);
    }
    move(word: string): void {
        const result = this.takeSteps(decode(word, STEP_LETTERS)!);
        if (result.letters.length) this.emit('moved', result.letters);
        if (result.failure !== null) throw new CommandError(result.failure);
    }
    push(box: number, direction: Direction): void {
        const level = this.level, boxes = this.current.boxes;
        if (!boxes.includes(box)) throw new CommandError('no box');
        const offset = level.offsetOf(direction), destination = box + offset;
        if (!level.interior[destination] || boxes.includes(destination)) throw new CommandError('blocked');
        if (!level.reachable(this.current.player, boxes)[box - offset]) throw new CommandError('unreachable');
        const path = level.walkPath(this.current.player, box - offset, boxes);
        this.emit('pushed', this.takeSteps(path + direction).letters);
    }
    bring(source: number, target: number): void {
        const boxes = this.current.boxes;
        if (!boxes.includes(source)) throw new CommandError('no box');
        if (source === target) { this.emit('brought', 0); return; }
        const result = pushSearch(this.level, this.current, boxes.filter(box => box !== source), target, false, null);
        if (result.outcome !== 'found') throw new CommandError('no route');
        this.takeSteps(result.notation);
        this.emit('brought', pushCount(result.notation), result.notation);
    }
    path(target: number): void {
        if (!this.level.reachable(this.current.player, this.current.boxes)[target]) throw new CommandError('unreachable');
        const path = this.level.walkPath(this.current.player, target, this.current.boxes);
        this.emit(counted('path', this.takeSteps(path).letters));
    }
    undo(requested: number): void {
        if (!this.history.length) throw new CommandError('nothing to undo');
        const count = Math.min(requested, this.history.length);
        for (let index = 0; index < count; index++) {
            const letter = this.history[this.history.length - 1], direction = directionOf(letter);
            this.history = this.history.slice(0, -1);
            const offset = this.level.offsetOf(direction), player = this.current.player;
            const boxes = letter === direction ? this.current.boxes : moveBox(this.current.boxes, player + offset, player);
            this.current = {player: player - offset, boxes};
            this.redoList += direction;
        }
        this.emit('undone', count);
    }
    redo(requested: number): void {
        if (!this.redoList.length) throw new CommandError('nothing to redo');
        const count = Math.min(requested, this.redoList.length);
        for (let index = 0; index < count; index++) {
            const direction = directionOf(this.redoList[this.redoList.length - 1]);
            this.redoList = this.redoList.slice(0, -1);
            const step = this.level.step(this.current, direction);
            this.current = step.position;
            this.history += step.letter;
        }
        this.emit('redone', count);
    }
    showBoxes(): void {
        const boxes = this.current.boxes, level = this.level;
        const reachable = level.reachable(this.current.player, boxes);
        this.emit('boxes', boxes.length);
        for (const box of boxes) {
            const distance = level.goalDistance(box);
            const directions = DIRECTIONS.filter(direction => level.pushable(box, direction, boxes, reachable)).join('');
            this.emit('box', level.cellText(box), distance === null ? 'dead' : distance, directions || '-');
        }
    }
    deadlock(): void {
        const level = this.level, boxes = this.current.boxes;
        const dead = boxes.find(box => level.dead[box]);
        if (dead !== undefined) { this.emit('deadlock dead', level.cellText(dead)); return; }
        const frozen = boxes.find(box => !level.goals[box] && level.frozen(box, boxes));
        if (frozen !== undefined) { this.emit('deadlock frozen', level.cellText(frozen)); return; }
        this.emit('no deadlock');
    }
    bound(): void {
        const boxes = this.current.boxes, level = this.level;
        const best: {value: Assignment | null} = {value: null};
        const assign = (order: number[], pushes: number[], used: ReadonlySet<number>, total: number): void => {
            if (order.length === boxes.length) {
                if (best.value === null || total < best.value.total) best.value = {order, pushes, total};
                return;
            }
            for (let goal = 0; goal < level.goalCells.length; goal++) {
                const distance = level.distances[goal][boxes[order.length]];
                if (!used.has(goal) && distance >= 0) {
                    assign([...order, goal], [...pushes, distance], new Set([...used, goal]), total + distance);
                }
            }
        };
        assign([], [], new Set<number>(), 0);
        const chosen = best.value;
        if (chosen === null) { this.emit('bound none'); return; }
        this.emit('bound', chosen.total);
        boxes.forEach((box, index) => this.emit('box', level.cellText(box), 'goal', level.cellText(level.goalCells[chosen.order[index]]), 'pushes', chosen.pushes[index]));
    }
    save(name: string): void {
        this.snapshots.set(name, {position: this.current, history: this.history});
        this.emit('saved', name, 'moves', this.history.length);
    }
    restore(name: string): void {
        const snapshot = this.snapshots.get(name);
        if (snapshot === undefined) throw new CommandError(`no snapshot ${name}`);
        this.current = snapshot.position;
        this.history = snapshot.history;
        this.redoList = '';
        this.emit('restored', name, 'moves', this.history.length);
    }
    check(word: string): void {
        const result = this.simulate(decode(word, STEP_LETTERS)!);
        if (result.failure !== null) this.emit('check fail', result.failure);
        else this.emit('check ok moves', result.letters.length, 'pushes', pushCount(result.letters), this.progress(result.position.boxes));
    }
    solve(limit: number): void {
        const summary = this.searchSolution(limit);
        this.emit(summary.text);
        this.solution = null;
        if (summary.notation !== null) {
            this.emit(summary.notation);
            this.solution = {notation: summary.notation, position: this.current};
        }
    }
    hint(limit: number): void {
        const summary = this.searchSolution(limit);
        if (summary.notation === null) { this.emit(summary.text); return; }
        const end = [...summary.notation].findIndex(letter => letter !== letter.toLowerCase());
        const part = summary.notation.slice(0, end + 1);
        this.takeSteps(part);
        this.emit('hint', part);
    }
    play(): void {
        if (this.solution === null || !samePosition(this.solution.position, this.current)) throw new CommandError('no solution');
        const notation = this.solution.notation;
        this.takeSteps(notation);
        this.emit('played pushes', pushCount(notation), 'moves', notation.length);
    }
    transform(kind: Transform): void {
        const old = this.level;
        this.level = old.transformed(kind);
        this.initial = old.mapPosition(kind, this.initial);
        this.current = old.mapPosition(kind, this.current);
        this.history = turnLetters(this.history, kind);
        this.redoList = turnLetters(this.redoList, kind);
        for (const [name, snapshot] of this.snapshots) {
            this.snapshots.set(name, {position: old.mapPosition(kind, snapshot.position), history: turnLetters(snapshot.history, kind)});
        }
        if (this.solution !== null) this.solution = {notation: turnLetters(this.solution.notation, kind), position: old.mapPosition(kind, this.solution.position)};
        this.emit('transformed', `${this.level.height}x${this.level.width}`);
    }

    checkValues(name: string, args: readonly string[]): void {
        const cells = name === 'BRING' ? 2 : name === 'PATH' || name === 'PUSH' ? 1 : 0;
        for (let index = 0; index < cells * 2; index += 2) {
            if (!this.level.contains(Number(args[index]), Number(args[index + 1]))) throw new CommandError('bad value');
        }
        if ((name === 'UNDO' || name === 'REDO') && Number(args[0]) < 1) throw new CommandError('bad value');
        if ((name === 'SOLVE' || name === 'HINT') && (Number(args[0]) < 1 || Number(args[0]) > 100000)) throw new CommandError('bad value');
    }
    runCommand(name: string, args: readonly string[]): void {
        const kinds = COMMANDS.get(name);
        if (kinds === undefined) throw new CommandError(`unknown command ${name}`);
        if (args.length !== kinds.length || kinds.some((kind, index) => !validArgument(kind, args[index]))) throw new CommandError('bad arguments');
        if (name === 'IMPORT') { this.importLevel(args[0]); return; }
        if (name === 'VALID') { this.emit(this.level.reason === null ? 'valid' : `invalid ${this.level.reason}`); return; }
        if (this.level.reason !== null) throw new CommandError('invalid level');
        this.checkValues(name, args);
        const level = this.level;
        switch (name) {
            case 'INFO': this.emit('size', `${level.height}x${level.width}`, 'walls', countTrue(level.walls), 'cells', countTrue(level.interior), 'boxes', this.current.boxes.length, 'dead', countTrue(level.dead)); break;
            case 'SHOW': level.render(this.current).forEach(row => this.emit(row)); break;
            case 'EXPORT': this.emit('level', level.render(this.current).map(encode).join('|')); break;
            case 'MOVE': this.move(args[0]); break;
            case 'PUSH': this.push(this.cellArgument(args, 0), directionOf(args[2])); break;
            case 'BRING': this.bring(this.cellArgument(args, 0), this.cellArgument(args, 2)); break;
            case 'PATH': this.path(this.cellArgument(args, 0)); break;
            case 'UNDO': this.undo(Number(args[0])); break;
            case 'REDO': this.redo(Number(args[0])); break;
            case 'RESET': this.current = this.initial; this.history = ''; this.redoList = ''; this.emit('reset'); break;
            case 'STATUS': this.emit('moves', this.history.length, 'pushes', pushCount(this.history), this.progress(this.current.boxes)); break;
            case 'HISTORY': this.emit(counted('history', this.history)); break;
            case 'BOXES': this.showBoxes(); break;
            case 'REACH': {
                const reach = level.reachable(this.current.player, this.current.boxes);
                this.emit('reach', countTrue(reach), 'first', level.cellText(reach.indexOf(true)));
                break;
            }
            case 'DEADSQUARES': this.emit('dead', countTrue(level.dead)); level.deadMap().forEach(row => this.emit(row)); break;
            case 'DEADLOCK': this.deadlock(); break;
            case 'BOUND': this.bound(); break;
            case 'SAVE': this.save(args[0]); break;
            case 'RESTORE': this.restore(args[0]); break;
            case 'CHECK': this.check(args[0]); break;
            case 'SOLVE': this.solve(Number(args[0])); break;
            case 'HINT': this.hint(Number(args[0])); break;
            case 'PLAY': this.play(); break;
            case 'TRANSFORM': this.transform(args[0] as Transform); break;
        }
    }
    execute(words: readonly string[], rows: readonly string[]): void {
        try {
            if (words[0] === 'LOAD') this.loadRows(Number(words[2]), rows);
            else this.runCommand(words[0], words.slice(1));
        } catch (error) {
            if (!(error instanceof CommandError)) throw error;
            this.emit('error:', error.message);
        }
    }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/);
let line = 0;
const [height] = lines[line++].split(' ').map(Number);
const game = new Sokoban(lines.slice(line, line + height));
line += height;
const commandCount = Number(lines[line++]);
for (let index = 0; index < commandCount; index++) {
    const words = lines[line++].split(' ');
    const rows = words[0] === 'LOAD' ? lines.slice(line, line + Number(words[1])) : [];
    line += rows.length;
    game.execute(words, rows);
}
process.stdout.write(game.output.join('\n') + '\n');
