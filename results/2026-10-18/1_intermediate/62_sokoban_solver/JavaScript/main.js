'use strict';

const fs = require('node:fs');
const DIRECTIONS = ['u', 'd', 'l', 'r'];
const DELTAS = [[-1, 0], [1, 0], [0, -1], [0, 1]];
const TURNS = new Map([
    ['ROT90', 'rlud'], ['ROT180', 'durl'], ['ROT270', 'lrdu'],
    ['FLIPH', 'udrl'], ['FLIPV', 'dulr'],
]);
const LEVEL_CHARACTERS = '#-.$*@+';
const STEP_LETTERS = 'udlrUDLR';
const COMMANDS = new Map([
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

function decode(text, allowed) {
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

function encode(text) {
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

function validArgument(kind, text) {
    switch (kind) {
        case 'number': return /^(0|[1-9][0-9]{0,5})$/.test(text);
        case 'steps': return decode(text, STEP_LETTERS) !== null;
        case 'direction': return DIRECTIONS.includes(text);
        case 'name': return /^[a-z]{1,8}$/.test(text);
        case 'transform': return TURNS.has(text);
        default: return true;
    }
}

function directionOf(letter) { return letter.toLowerCase(); }
function pushCount(letters) { return [...letters].filter(letter => letter !== letter.toLowerCase()).length; }
function moveBox(boxes, source, destination) {
    return boxes.map(box => box === source ? destination : box).sort((a, b) => a - b);
}
function samePosition(a, b) {
    return a.player === b.player && a.boxes.length === b.boxes.length
        && a.boxes.every((box, index) => box === b.boxes[index]);
}
function turnLetters(letters, kind) {
    const turn = TURNS.get(kind);
    return [...letters].map(letter => {
        const direction = turn[DIRECTIONS.indexOf(directionOf(letter))];
        return letter === letter.toLowerCase() ? direction : direction.toUpperCase();
    }).join('');
}
function counted(label, letters) {
    return letters.length ? `${label} ${letters.length} ${letters}` : `${label} 0`;
}
function countTrue(flags) { return flags.filter(Boolean).length; }

function findInterior(height, width, walls, start) {
    const seen = Array(height * width).fill(false);
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
    constructor(height, width, walls, goals, interior) {
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
        this.dead = Array(this.size).fill(false);
    }

    offsetOf(direction) { return this.offsets[DIRECTIONS.indexOf(direction)]; }
    cellText(cell) { return `${Math.floor(cell / this.width) + 1} ${cell % this.width + 1}`; }
    cellAt(row, column) { return (row - 1) * this.width + column - 1; }
    contains(row, column) { return row >= 1 && row <= this.height && column >= 1 && column <= this.width; }
    onBorder(cell) {
        const row = Math.floor(cell / this.width), column = cell % this.width;
        return row === 0 || row === this.height - 1 || column === 0 || column === this.width - 1;
    }

    invalidity(players, boxes) {
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

    analyze() {
        this.distances = this.goalCells.map(goal => this.pushDistances(goal));
        this.dead = this.interior.map((inside, cell) => inside && this.distances.every(distance => distance[cell] === -1));
    }

    pushDistances(goal) {
        const distance = Array(this.size).fill(-1);
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

    goalDistance(cell) {
        const defined = this.distances.map(distance => distance[cell]).filter(distance => distance >= 0);
        return defined.length ? Math.min(...defined) : null;
    }
    boxesOnGoals(boxes) { return boxes.filter(box => this.goals[box]).length; }
    solved(boxes) { return this.boxesOnGoals(boxes) === boxes.length; }

    reachable(player, boxes) {
        const seen = Array(this.size).fill(false);
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
    representative(player, boxes) { return this.reachable(player, boxes).indexOf(true); }

    walkPath(start, target, boxes) {
        const cameFrom = Array(this.size).fill(null);
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
        const path = [];
        for (let cell = target; cell !== start;) {
            const from = cameFrom[cell];
            path.push(from.direction);
            cell = from.cell;
        }
        return path.reverse().join('');
    }

    step(position, direction) {
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

    pushable(box, direction, boxes, reachable) {
        const offset = this.offsetOf(direction), destination = box + offset;
        return !!reachable[box - offset] && !!this.interior[destination] && !boxes.includes(destination);
    }
    sideBlocked(box, sides, boxes, assumed) {
        if (sides.some(side => this.walls[side] || assumed.includes(side))) return true;
        if (sides.every(side => this.dead[side])) return true;
        const extended = [...assumed, box];
        return sides.some(side => boxes.includes(side) && this.frozen(side, boxes, extended));
    }
    frozen(box, boxes, assumed = []) {
        return this.sideBlocked(box, [box - 1, box + 1], boxes, assumed)
            && this.sideBlocked(box, [box - this.width, box + this.width], boxes, assumed);
    }
    hasFrozenBox(boxes) { return boxes.some(box => !this.goals[box] && this.frozen(box, boxes)); }

    splitRows(symbols) {
        const rows = [];
        for (let start = 0; start < this.size; start += this.width) rows.push(symbols.slice(start, start + this.width));
        return rows;
    }
    render(position) {
        let symbols = '';
        for (let cell = 0; cell < this.size; cell++) {
            if (this.walls[cell]) symbols += '#';
            else if (cell === position.player) symbols += this.goals[cell] ? '+' : '@';
            else if (position.boxes.includes(cell)) symbols += this.goals[cell] ? '*' : '$';
            else symbols += this.goals[cell] ? '.' : '-';
        }
        return this.splitRows(symbols);
    }
    deadMap() {
        let symbols = '';
        for (let cell = 0; cell < this.size; cell++) {
            symbols += this.walls[cell] ? '#' : this.goals[cell] ? '.' : this.dead[cell] ? 'x' : '-';
        }
        return this.splitRows(symbols);
    }

    mapCell(kind, cell) {
        const row = Math.floor(cell / this.width), column = cell % this.width;
        switch (kind) {
            case 'ROT90': return column * this.height + this.height - 1 - row;
            case 'ROT180': return (this.height - 1 - row) * this.width + this.width - 1 - column;
            case 'ROT270': return (this.width - 1 - column) * this.height + row;
            case 'FLIPH': return row * this.width + this.width - 1 - column;
            default: return (this.height - 1 - row) * this.width + column;
        }
    }
    mapPosition(kind, position) {
        return {player: this.mapCell(kind, position.player), boxes: position.boxes.map(box => this.mapCell(kind, box)).sort((a, b) => a - b)};
    }
    transformed(kind) {
        const rotated = kind === 'ROT90' || kind === 'ROT270';
        const walls = Array(this.size).fill(false), goals = Array(this.size).fill(false), interior = Array(this.size).fill(false);
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

function buildLevel(rows) {
    const height = rows.length, width = rows[0].length;
    const cells = [...rows.join('')];
    const walls = cells.map(symbol => symbol === '#'), goals = cells.map(symbol => '.*+'.includes(symbol));
    const players = [], boxes = [];
    cells.forEach((symbol, cell) => {
        if ('@+'.includes(symbol)) players.push(cell);
        if ('$*'.includes(symbol)) boxes.push(cell);
    });
    const interior = players.length === 1 ? findInterior(height, width, walls, players[0]) : Array(cells.length).fill(false);
    const level = new Level(height, width, walls, goals, interior);
    level.reason = level.invalidity(players.length, boxes);
    if (level.reason === null) level.analyze();
    return {level, position: {player: players.length ? players[0] : -1, boxes}};
}

function stateKey(boxes, representative) { return `${boxes.join(',')}:${representative}`; }
function solutionNotation(level, start, nodes) {
    const pushes = [];
    for (let node = nodes[nodes.length - 1]; node.parent !== -1; node = nodes[node.parent]) pushes.push(node.push);
    let position = start, notation = '';
    for (const {box, direction} of pushes.reverse()) {
        const offset = level.offsetOf(direction);
        notation += level.walkPath(position.player, box - offset, position.boxes) + direction.toUpperCase();
        position = {player: box, boxes: moveBox(position.boxes, box, box + offset)};
    }
    return notation;
}

function pushSearch(level, start, fixed, target, pruning, limit) {
    const representative = level.representative(start.player, start.boxes);
    const nodes = [{boxes: start.boxes, representative, parent: -1, push: null}];
    const known = new Set([stateKey(start.boxes, representative)]);
    let expanded = 0;
    // The append-only nodes array is also the FIFO queue; found children count as known states.
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
    constructor(rows) {
        this.output = [];
        this.load(rows);
    }
    emit(...parts) { this.output.push(parts.join(' ')); }
    load(rows) {
        const loaded = buildLevel(rows);
        this.level = loaded.level;
        this.initial = loaded.position;
        this.current = this.initial;
        this.history = '';
        this.redoList = '';
        this.snapshots = new Map();
        this.solution = null;
    }
    cellArgument(args, index) { return this.level.cellAt(Number(args[index]), Number(args[index + 1])); }

    simulate(directions) {
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
    takeSteps(directions) {
        const result = this.simulate(directions);
        this.current = result.position;
        this.history += result.letters;
        if (result.letters.length) this.redoList = '';
        return result;
    }
    progress(boxes) {
        const count = this.level.boxesOnGoals(boxes);
        return `goals ${count}/${boxes.length}` + (count === boxes.length ? ' solved' : '');
    }
    searchSolution(limit) {
        if (this.level.solved(this.current.boxes)) return {text: 'already solved', notation: null};
        const result = pushSearch(this.level, this.current, [], null, true, limit);
        const counts = `expanded ${result.expanded} states ${result.states}`;
        if (result.outcome !== 'found') return {text: `${result.outcome} ${counts}`, notation: null};
        const notation = result.notation;
        return {text: `solution pushes ${pushCount(notation)} moves ${notation.length} ${counts}`, notation};
    }

    loadRows(width, rows) {
        const bad = rows.findIndex(row => row.length !== width || [...row].some(symbol => !LEVEL_CHARACTERS.includes(symbol)));
        if (bad !== -1) throw new CommandError(`bad row ${bad + 1}`);
        this.load(rows);
        this.emit('loaded', `${rows.length}x${width}`);
    }
    importLevel(text) {
        const rows = [];
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
    move(word) {
        const result = this.takeSteps(decode(word, STEP_LETTERS));
        if (result.letters.length) this.emit('moved', result.letters);
        if (result.failure !== null) throw new CommandError(result.failure);
    }
    push(box, direction) {
        const level = this.level, boxes = this.current.boxes;
        if (!boxes.includes(box)) throw new CommandError('no box');
        const offset = level.offsetOf(direction), destination = box + offset;
        if (!level.interior[destination] || boxes.includes(destination)) throw new CommandError('blocked');
        if (!level.reachable(this.current.player, boxes)[box - offset]) throw new CommandError('unreachable');
        const path = level.walkPath(this.current.player, box - offset, boxes);
        this.emit('pushed', this.takeSteps(path + direction).letters);
    }
    bring(source, target) {
        const boxes = this.current.boxes;
        if (!boxes.includes(source)) throw new CommandError('no box');
        if (source === target) { this.emit('brought', 0); return; }
        const result = pushSearch(this.level, this.current, boxes.filter(box => box !== source), target, false, null);
        if (result.outcome !== 'found') throw new CommandError('no route');
        this.takeSteps(result.notation);
        this.emit('brought', pushCount(result.notation), result.notation);
    }
    path(target) {
        if (!this.level.reachable(this.current.player, this.current.boxes)[target]) throw new CommandError('unreachable');
        const path = this.level.walkPath(this.current.player, target, this.current.boxes);
        this.emit(counted('path', this.takeSteps(path).letters));
    }
    undo(requested) {
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
    redo(requested) {
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
    showBoxes() {
        const boxes = this.current.boxes, level = this.level;
        const reachable = level.reachable(this.current.player, boxes);
        this.emit('boxes', boxes.length);
        for (const box of boxes) {
            const distance = level.goalDistance(box);
            const directions = DIRECTIONS.filter(direction => level.pushable(box, direction, boxes, reachable)).join('');
            this.emit('box', level.cellText(box), distance === null ? 'dead' : distance, directions || '-');
        }
    }
    deadlock() {
        const level = this.level, boxes = this.current.boxes;
        const dead = boxes.find(box => level.dead[box]);
        if (dead !== undefined) { this.emit('deadlock dead', level.cellText(dead)); return; }
        const frozen = boxes.find(box => !level.goals[box] && level.frozen(box, boxes));
        if (frozen !== undefined) { this.emit('deadlock frozen', level.cellText(frozen)); return; }
        this.emit('no deadlock');
    }
    bound() {
        const boxes = this.current.boxes, level = this.level;
        let best = null;
        // Ascending goal indices make equal-total assignments retain the lexicographically first.
        const assign = (order, pushes, used, total) => {
            if (order.length === boxes.length) {
                if (best === null || total < best.total) best = {order, pushes, total};
                return;
            }
            for (let goal = 0; goal < level.goalCells.length; goal++) {
                const distance = level.distances[goal][boxes[order.length]];
                if (!used.has(goal) && distance >= 0) {
                    assign([...order, goal], [...pushes, distance], new Set([...used, goal]), total + distance);
                }
            }
        };
        assign([], [], new Set(), 0);
        if (best === null) { this.emit('bound none'); return; }
        this.emit('bound', best.total);
        boxes.forEach((box, index) => this.emit('box', level.cellText(box), 'goal', level.cellText(level.goalCells[best.order[index]]), 'pushes', best.pushes[index]));
    }
    save(name) {
        // Positions and box arrays are never mutated; snapshots can safely share them.
        this.snapshots.set(name, {position: this.current, history: this.history});
        this.emit('saved', name, 'moves', this.history.length);
    }
    restore(name) {
        const snapshot = this.snapshots.get(name);
        if (snapshot === undefined) throw new CommandError(`no snapshot ${name}`);
        this.current = snapshot.position;
        this.history = snapshot.history;
        this.redoList = '';
        this.emit('restored', name, 'moves', this.history.length);
    }
    check(word) {
        const result = this.simulate(decode(word, STEP_LETTERS));
        if (result.failure !== null) this.emit('check fail', result.failure);
        else this.emit('check ok moves', result.letters.length, 'pushes', pushCount(result.letters), this.progress(result.position.boxes));
    }
    solve(limit) {
        const summary = this.searchSolution(limit);
        this.emit(summary.text);
        this.solution = null;
        if (summary.notation !== null) {
            this.emit(summary.notation);
            this.solution = {notation: summary.notation, position: this.current};
        }
    }
    hint(limit) {
        const summary = this.searchSolution(limit);
        if (summary.notation === null) { this.emit(summary.text); return; }
        const end = [...summary.notation].findIndex(letter => letter !== letter.toLowerCase());
        const part = summary.notation.slice(0, end + 1);
        this.takeSteps(part);
        this.emit('hint', part);
    }
    play() {
        if (this.solution === null || !samePosition(this.solution.position, this.current)) throw new CommandError('no solution');
        const notation = this.solution.notation;
        this.takeSteps(notation);
        this.emit('played pushes', pushCount(notation), 'moves', notation.length);
    }
    transform(kind) {
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

    checkValues(name, args) {
        const cells = name === 'BRING' ? 2 : name === 'PATH' || name === 'PUSH' ? 1 : 0;
        for (let index = 0; index < cells * 2; index += 2) {
            if (!this.level.contains(Number(args[index]), Number(args[index + 1]))) throw new CommandError('bad value');
        }
        if ((name === 'UNDO' || name === 'REDO') && Number(args[0]) < 1) throw new CommandError('bad value');
        if ((name === 'SOLVE' || name === 'HINT') && (Number(args[0]) < 1 || Number(args[0]) > 100000)) throw new CommandError('bad value');
    }
    runCommand(name, args) {
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
            case 'TRANSFORM': this.transform(args[0]); break;
        }
    }
    execute(words, rows) {
        try {
            if (words[0] === 'LOAD') this.loadRows(Number(words[2]), rows);
            else this.runCommand(words[0], words.slice(1));
        } catch (error) {
            if (!(error instanceof CommandError)) throw error;
            this.emit('error:', error.message);
        }
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
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
