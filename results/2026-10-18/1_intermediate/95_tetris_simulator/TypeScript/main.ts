import * as fs from 'node:fs';

type Kind = 'I' | 'O' | 'T' | 'S' | 'Z' | 'J' | 'L';
type Point = [number, number];
type Position = [number, number, number];
interface Motion { position: Position; test: number; }
interface Route { position: Position; keys: string[]; }
interface Candidate { value: number; kind: Kind; keys: string[]; }
interface Statistics {
    drops: number; holds: number; operations: number; faults: number; perfect: number;
    sent: number; cancelled: number; received: number; combo: number; chain: number;
    kinds: Record<Kind, number>; clears: Record<string, number>;
}
interface State {
    board: number[]; random: number; queue: Kind[]; hold: Kind | null; usedHold: boolean;
    kind: Kind; position: Position; last: string; test: number;
    keys: number; drop: number; fall: number; ground: number; resets: number; lowest: number;
    initialLevel: number; level: number; score: number; lines: number; pieces: number;
    streak: number; chain: number; pending: number[]; stats: Statistics; ended: boolean;
}
interface SavedGame { state: State; history: State[]; start: State; }
class GameOver extends Error {}
const kinds: Kind[] = ['I', 'O', 'T', 'S', 'Z', 'J', 'L'];
const movements = ['L', 'R', 'LL', 'RR', 'SD', 'DD', 'CW', 'CCW'];
const operations = new Set([...movements, 'HD', 'LOCK', 'HOLD']);
const commands = new Set('NEW PRINT NEXT PREVIEW STATUS ANALYZE ROW GARBAGE ATTACK TICK UNDO SAVE LOAD SPINS HINT AUTO'.split(' '));
const afterEnd = new Set('PRINT NEXT PREVIEW STATUS ANALYZE LOAD'.split(' '));
const states = ['0', 'R', '2', 'L'];
const clearNames = ['SINGLE', 'DOUBLE', 'TRIPLE', 'TETRIS', 'TSPIN_MINI', 'TSPIN_MINI_SINGLE', 'TSPIN_MINI_DOUBLE', 'TSPIN', 'TSPIN_SINGLE', 'TSPIN_DOUBLE', 'TSPIN_TRIPLE'];
const frames: Record<Kind, string[]> = {
    I: ['....', '####', '....', '....'], O: ['##', '##'], T: ['.#.', '###', '...'],
    S: ['.##', '##.', '...'], Z: ['##.', '.##', '...'], J: ['#..', '###', '...'], L: ['..#', '###', '...'],
};
const shapes = {} as Record<Kind, Point[][]>;
for (const k of kinds) {
    let blocks: Point[] = [];
    frames[k].forEach((row, j) => [...row].forEach((ch, i) => { if (ch === '#') blocks.push([i, j]); }));
    shapes[k] = [blocks];
    for (let s = 1; s < 4; s++) { blocks = blocks.map(([i, j]) => [frames[k].length - 1 - j, i]); shapes[k].push(blocks); }
}
const ordinaryKicks: Record<string, Point[]> = {
    '01': [[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
    '10': [[0,0],[1,0],[1,-1],[0,2],[1,2]],
    '12': [[0,0],[1,0],[1,-1],[0,2],[1,2]],
    '21': [[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
    '23': [[0,0],[1,0],[1,1],[0,-2],[1,-2]],
    '32': [[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
    '30': [[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
    '03': [[0,0],[1,0],[1,1],[0,-2],[1,-2]],
};
const iKicks: Record<string, Point[]> = {
    '01': [[0,0],[-2,0],[1,0],[-2,-1],[1,2]],
    '10': [[0,0],[2,0],[-1,0],[2,1],[-1,-2]],
    '12': [[0,0],[-1,0],[2,0],[-1,2],[2,-1]],
    '21': [[0,0],[1,0],[-2,0],[1,-2],[-2,1]],
    '23': [[0,0],[2,0],[-1,0],[2,1],[-1,-2]],
    '32': [[0,0],[-2,0],[1,0],[-2,-1],[1,2]],
    '30': [[0,0],[1,0],[-2,0],[1,-2],[-2,1]],
    '03': [[0,0],[-1,0],[2,0],[-1,2],[2,-1]],
};
const output: string[] = [];
const emit = (text: string): void => { output.push(text); };
const total = (values: number[]) => values.reduce((a, b) => a + b, 0);
const spawn = (kind: Kind): Position => [0, kind === 'O' ? 5 : 4, 22];
const key = (p: Position): string => p.join(',');
const cells = (kind: Kind, [s, x, y]: Position): Point[] => shapes[kind][s].map(([i, j]) => [x + i, y - j]);
const lowest = (kind: Kind, p: Position): number => Math.min(...cells(kind, p).map(([, r]) => r));
function bag(random: number): {random: number; pieces: Kind[]} {
    const pieces = [...kinds];
    for (let i = 6; i >= 1; i--) { random = 48271 * random % 2147483647; const j = random % (i + 1); [pieces[i], pieces[j]] = [pieces[j], pieces[i]]; }
    return {random, pieces};
}
function fits(board: number[], kind: Kind, p: Position): boolean {
    return cells(kind, p).every(([c, r]) => c >= 1 && c <= 10 && r >= 1 && r <= 22 && (board[r - 1] & (1 << (c - 1))) === 0);
}
function move(board: number[], kind: Kind, p: Position, operation: string): Motion | null {
    const [s, x, y] = p;
    if (operation === 'CW' || operation === 'CCW') {
        const b = (s + (operation === 'CW' ? 1 : 3)) % 4;
        const offsets: Point[] = kind === 'O' ? [[0,0]] : (kind === 'I' ? iKicks : ordinaryKicks)[String(s) + b];
        for (let i = 0; i < offsets.length; i++) { const [dx, dy] = offsets[i], q: Position = [b, x + dx, y + dy]; if (fits(board, kind, q)) return {position: q, test: i + 1}; }
        return null;
    }
    const dx = operation === 'L' || operation === 'LL' ? -1 : operation === 'R' || operation === 'RR' ? 1 : 0;
    const dy = dx === 0 ? -1 : 0, repeat = ['LL', 'RR', 'DD'].includes(operation);
    let position = p, changed = false;
    do {
        const q: Position = [s, position[1] + dx, position[2] + dy];
        if (!fits(board, kind, q)) break;
        position = q; changed = true;
    } while (repeat);
    return changed ? {position, test: 0} : null;
}
function landing(board: number[], kind: Kind, p: Position): Position { return move(board, kind, p, 'DD')?.position ?? p; }
function placed(board: number[], kind: Kind, p: Position): {board: number[]; lines: number} {
    const result = [...board]; for (const [c, r] of cells(kind, p)) result[r - 1] |= 1 << (c - 1);
    const remaining = result.filter(row => row !== 1023), lines = 22 - remaining.length;
    return {board: remaining.concat(Array(lines).fill(0)), lines};
}
function evaluation(board: number[], cleared: number): {heights: number[]; holes: number; bumpiness: number; value: number} {
    const heights = Array(10).fill(0); let holes = 0, bumpiness = 0;
    for (let c = 0; c < 10; c++) { for (let r = 21; r >= 0; r--) if (board[r] & (1 << c)) { heights[c] = r + 1; break; } for (let r = 0; r < heights[c]; r++) if (!(board[r] & (1 << c))) holes++; }
    for (let c = 0; c < 9; c++) bumpiness += Math.abs(heights[c] - heights[c + 1]);
    return {heights, holes, bumpiness, value: 76 * cleared - 51 * total(heights) - 36 * holes - 18 * bumpiness};
}
function routes(board: number[], kind: Kind, start: Position, target: Position | null = null): Route[] {
    if (!fits(board, kind, start)) return [];
    const queue: Route[] = [{position: start, keys: []}], seen = new Set([key(start)]);
    for (let i = 0; i < queue.length; i++) {
        const entry = queue[i];
        if (target && key(landing(board, kind, entry.position)) === key(target)) return [entry];
        for (const operation of movements) {
            const result = move(board, kind, entry.position, operation);
            if (result && !seen.has(key(result.position))) { seen.add(key(result.position)); queue.push({position: result.position, keys: [...entry.keys, operation]}); }
        }
    }
    return target ? [] : queue;
}
function tSpin(board: number[], p: Position, test: number): string {
    const [s, x, y] = p, corners: Point[] = [[x,y],[x+2,y],[x+2,y-2],[x,y-2]];
    const blocked = corners.map(([c, r]) => c < 1 || c > 10 || r < 1 || r > 22 || (board[r - 1] & (1 << (c - 1))) !== 0);
    if (blocked.filter(Boolean).length < 3) return '';
    return (blocked[s] && blocked[(s + 1) % 4]) || test === 5 ? 'full' : 'mini';
}
function clearInfo(spin: string, lines: number): {name: string; points: number; sent: number} {
    if (spin === 'full') return {name: ['TSPIN','TSPIN_SINGLE','TSPIN_DOUBLE','TSPIN_TRIPLE'][lines], points: [400,800,1200,1600][lines], sent: [0,2,4,6][lines]};
    if (spin === 'mini') return {name: ['TSPIN_MINI','TSPIN_MINI_SINGLE','TSPIN_MINI_DOUBLE'][lines], points: [100,200,400][lines], sent: [0,0,1][lines]};
    return {name: ['', 'SINGLE', 'DOUBLE', 'TRIPLE', 'TETRIS'][lines], points: [0,100,300,500,800][lines], sent: [0,0,1,2,4][lines]};
}

class Game {
    state: State;
    history: State[] = [];
    start: State;
    saves = new Map<string, SavedGame>();
    constructor(public number: number, seed: number, level: number) {
        this.state = {
            board: Array(22).fill(0), random: seed, queue: [], hold: null, usedHold: false,
            kind: 'I', position: spawn('I'), last: 'none', test: 0, keys: 0, drop: 0, fall: 0, ground: 0, resets: 0, lowest: 0,
            initialLevel: level, level, score: 0, lines: 0, pieces: 0, streak: 0, chain: 0, pending: [], ended: false,
            stats: {drops: 0, holds: 0, operations: 0, faults: 0, perfect: 0, sent: 0, cancelled: 0, received: 0, combo: 0, chain: 0,
                kinds: Object.fromEntries(kinds.map(k => [k, 0])) as Record<Kind, number>, clears: Object.fromEntries(clearNames.map(k => [k, 0]))},
        };
        this.addBag(); this.spawnPiece(this.next()); this.start = structuredClone(this.state);
    }
    addBag(): void { const result = bag(this.state.random); this.state.random = result.random; this.state.queue.push(...result.pieces); }
    next(): Kind { const kind = this.state.queue.shift()!; if (this.state.queue.length < 5) this.addBag(); return kind; }
    spawnPiece(kind: Kind): void {
        const s = this.state; s.kind = kind; s.position = spawn(kind); s.last = 'none'; s.test = 0;
        s.keys = 0; s.drop = 0; s.fall = 0; s.ground = 0; s.resets = 0; s.lowest = lowest(kind, s.position);
        if (!fits(s.board, kind, s.position)) this.over('block out');
    }
    over(reason: string): never { emit('game over ' + reason); this.summary(); this.state.ended = true; throw new GameOver(); }
    update(position: Position, last: string, test = 0): void {
        const s = this.state; s.position = position; s.last = last; s.test = test;
        const row = lowest(s.kind, position); if (row < s.lowest) { s.lowest = row; s.resets = 0; }
    }
    grounded(): boolean { const s = this.state; return move(s.board, s.kind, s.position, 'SD') === null; }
    drops(rows: number): void { this.state.score += rows; this.state.drop += rows; this.state.stats.drops += rows; }
    insertGarbage(rows: number, hole: number): void {
        const s = this.state;
        if (s.board.slice(22 - rows).some(row => row !== 0)) this.over('top out');
        s.board = Array(rows).fill(1023 ^ (1 << (hole - 1))).concat(s.board.slice(0, 22 - rows));
    }
    operation(operation: string): void {
        const s = this.state;
        if (movements.includes(operation)) {
            s.keys++;
            const result = move(s.board, s.kind, s.position, operation);
            if (!result) { emit('fail ' + operation); return; }
            if (operation === 'SD' || operation === 'DD') {
                this.drops(s.position[2] - result.position[2]); this.update(result.position, 'move'); s.fall = 0; s.ground = 0;
            } else {
                this.update(result.position, operation === 'CW' || operation === 'CCW' ? 'rotation' : 'move', result.test);
                if (s.ground > 0 && s.resets < 15) { s.ground = 0; s.resets++; }
            }
        } else if (operation === 'HD') {
            const p = landing(s.board, s.kind, s.position), rows = s.position[2] - p[2];
            this.drops(2 * rows); if (rows > 0) this.update(p, 'move'); this.lock();
        } else if (operation === 'LOCK') {
            if (this.grounded()) this.lock(); else emit('fail LOCK');
        } else {
            if (s.usedHold) { emit('fail HOLD'); return; }
            s.usedHold = true; s.stats.holds++;
            const previous = s.hold; s.hold = s.kind; this.spawnPiece(previous ?? this.next());
        }
    }
    tick(): void {
        const s = this.state;
        if (!this.grounded()) {
            s.ground = 0; s.fall++;
            const interval = s.level >= 13 ? 1 : [60,48,37,28,21,16,11,8,6,4,3,2][s.level - 1];
            if (s.fall >= interval) { this.update([s.position[0], s.position[1], s.position[2] - 1], 'move'); s.fall = 0; }
        } else { s.ground++; if (s.ground >= 30) this.lock(); }
    }
    lock(): void {
        const s = this.state, kind = s.kind, position = s.position, oldCells = cells(kind, position);
        const shortest = routes(s.board, kind, spawn(kind), position)[0];
        const spin = kind === 'T' && s.last === 'rotation' ? tSpin(s.board, position, s.test) : '';
        const placement = placed(s.board, kind, position), n = placement.lines; s.board = placement.board;
        this.history.push(structuredClone(this.start)); s.pieces++; s.stats.kinds[kind]++; s.stats.operations += s.keys;
        const info = clearInfo(spin, n), level = s.level;
        let points = info.points * level, sent = info.sent, backToBack = false;
        if (n > 0) { s.streak++; if (n === 4 || spin !== '') { s.chain++; backToBack = s.chain >= 2; } else s.chain = 0; } else s.streak = 0;
        if (backToBack) { points = Math.floor(points * 3 / 2); sent++; }
        const combo = s.streak - 1, comboPoints = combo >= 1 ? 50 * combo * level : 0;
        if (combo >= 0) sent += [0,1,1,2,2,3,3,4,4,4,5][Math.min(combo, 10)];
        const perfect = n > 0 && s.board.every(row => row === 0);
        const perfectPoints = perfect ? (n === 4 && backToBack ? 3200 : [800,1200,1800,2000][n - 1]) * level : 0;
        if (perfect) { sent += 10; s.stats.perfect++; }
        const gained = points + comboPoints + perfectPoints;
        s.score += gained; s.lines += n; s.stats.sent += sent; s.stats.combo = Math.max(s.stats.combo, combo); s.stats.chain = Math.max(s.stats.chain, s.chain);
        emit(`lock ${s.pieces} ${kind} ${states[position[0]]} ${position[1]} ${position[2]} keys ${s.keys} ${shortest ? shortest.keys.length : '-'} drop ${s.drop} lines ${n} sent ${sent} +${gained} total ${s.score}`);
        if (shortest && s.keys > shortest.keys.length) { s.stats.faults++; emit('finesse ' + (shortest.keys.join(' ') || 'none')); }
        if (info.name) {
            s.stats.clears[info.name]++;
            emit(`clear ${info.name} ${points}` + (backToBack ? ' b2b' : '') + (combo >= 1 ? ` combo ${combo} ${comboPoints}` : '') + (perfect ? ` perfect ${perfectPoints}` : ''));
        }
        const nextLevel = s.initialLevel + Math.floor(s.lines / 10);
        if (nextLevel > level) { s.level = nextLevel; emit('level ' + s.level); }
        if (oldCells.every(([, row]) => row >= 21)) this.over('lock out');
        const cancelled = Math.min(sent, total(s.pending));
        let remaining = cancelled;
        while (remaining > 0) { const count = Math.min(remaining, s.pending[0]); remaining -= count; s.pending[0] -= count; if (s.pending[0] === 0) s.pending.shift(); }
        if (cancelled > 0) { s.stats.cancelled += cancelled; emit(`cancel ${cancelled} pending ${total(s.pending)}`); }
        if (n === 0) {
            let risen = 0;
            while (s.pending.length > 0 && risen < 8) {
                const count = Math.min(s.pending[0], 8 - risen); s.random = 48271 * s.random % 2147483647; const hole = s.random % 10 + 1;
                this.insertGarbage(count, hole); s.stats.received += count; risen += count; s.pending[0] -= count;
                if (s.pending[0] === 0) s.pending.shift();
                emit(`rise ${count} hole ${hole} pending ${total(s.pending)}`);
            }
        }
        s.usedHold = false; this.spawnPiece(this.next()); this.start = structuredClone(s);
    }
    candidates(kind: Kind, start: Position, prefix: string[]): Candidate[] {
        const s = this.state, result: Candidate[] = [], seen = new Set<string>();
        for (const turns of [[], ['CW'], ['CW','CW'], ['CCW']]) {
            let p = start, valid = true;
            for (const turn of turns) { const step = move(s.board, kind, p, turn); if (!step) { valid = false; break; } p = step.position; }
            if (!valid) continue;
            const add = (q: Position, shifts: string[]): void => {
                const landed = landing(s.board, kind, q), id = cells(kind, landed).map(([c, r]) => (r - 1) * 10 + c - 1).sort((a, b) => a - b).join(',');
                if (seen.has(id)) return; seen.add(id);
                const placedPiece = placed(s.board, kind, landed);
                result.push({value: evaluation(placedPiece.board, placedPiece.lines).value, kind, keys: [...prefix, ...turns, ...shifts, 'HD']});
            };
            add(p, []);
            for (const direction of ['L', 'R']) {
                let q = p; const shifts: string[] = [];
                while (true) { const step = move(s.board, kind, q, direction); if (!step) break; q = step.position; shifts.push(direction); add(q, shifts); }
            }
        }
        return result;
    }
    ranked(): Candidate[] {
        const s = this.state, result = this.candidates(s.kind, s.position, []), held = s.hold ?? s.queue[0];
        if (!s.usedHold && fits(s.board, held, spawn(held))) result.push(...this.candidates(held, spawn(held), ['HOLD']));
        return result.sort((a, b) => b.value - a.value);
    }
    spins(): void {
        const s = this.state;
        if (s.kind !== 'T') { emit('spins 0'); return; }
        const found = new Map<string, {position: Position; spin: string}>();
        for (const route of routes(s.board, s.kind, s.position)) for (const turn of ['CW', 'CCW']) {
            const result = move(s.board, 'T', route.position, turn);
            if (!result || move(s.board, 'T', result.position, 'SD')) continue;
            const spin = tSpin(s.board, result.position, result.test), id = key(result.position);
            if (spin && (!found.has(id) || spin === 'full')) found.set(id, {position: result.position, spin});
        }
        const candidates = [...found.values()].sort((a, b) => a.position[2] - b.position[2] || a.position[1] - b.position[1] || a.position[0] - b.position[0]);
        for (const candidate of candidates) { const [state, x, y] = candidate.position; emit(`spin ${states[state]} ${x} ${y} ${clearInfo(candidate.spin, placed(s.board, 'T', candidate.position).lines).name}`); }
        emit('spins ' + candidates.length);
    }
    summary(): void {
        const s = this.state, a = s.stats, c = a.clears;
        const ratio = (x: number, y: number): string => { const q = y === 0 ? 0 : Math.floor(100 * x / y); return Math.floor(q / 100) + '.' + String(q % 100).padStart(2, '0'); };
        emit(`summary game ${this.number} score ${s.score} level ${s.level} lines ${s.lines} pieces ${s.pieces}`);
        emit(`clears single ${c.SINGLE} double ${c.DOUBLE} triple ${c.TRIPLE} tetris ${c.TETRIS} perfect ${a.perfect}`);
        emit(`tspins mini ${c.TSPIN_MINI} mini_single ${c.TSPIN_MINI_SINGLE} mini_double ${c.TSPIN_MINI_DOUBLE} zero ${c.TSPIN} single ${c.TSPIN_SINGLE} double ${c.TSPIN_DOUBLE} triple ${c.TSPIN_TRIPLE}`);
        emit('pieces ' + kinds.map(k => k + ' ' + a.kinds[k]).join(' '));
        emit(`best combo ${a.combo} chain ${a.chain} holds ${a.holds} drops ${a.drops} faults ${a.faults}`);
        emit(`garbage sent ${a.sent} cancelled ${a.cancelled} received ${a.received}`);
        emit(`rates app ${ratio(a.sent, s.pieces)} apl ${ratio(a.sent, s.lines)} kpp ${ratio(a.operations, s.pieces)}`);
    }
    command(command: string, args: string[]): void {
        const s = this.state;
        switch (command) {
            case 'PRINT': {
                const current = new Set(s.ended ? [] : cells(s.kind, s.position).map(([c, r]) => r * 10 + c));
                const ghost = new Set(s.ended ? [] : cells(s.kind, landing(s.board, s.kind, s.position)).map(([c, r]) => r * 10 + c));
                for (let r = 22; r >= 1; r--) { let row = String(r).padStart(2, ' ') + ' '; for (let c = 1; c <= 10; c++) row += s.board[r - 1] & (1 << (c - 1)) ? '#' : current.has(r * 10 + c) ? '@' : ghost.has(r * 10 + c) ? '+' : '.'; emit(row); }
                break;
            }
            case 'NEXT': emit(`hold ${s.hold ?? '-'} next ${s.queue.slice(0, 5).join('')}`); break;
            case 'PREVIEW': {
                const n = Number(args[0]), queue = [...s.queue]; let random = s.random;
                while (queue.length < n) { const result = bag(random); random = result.random; queue.push(...result.pieces); }
                emit('preview ' + queue.slice(0, n).join('')); break;
            }
            case 'STATUS': emit(`score ${s.score} level ${s.level} lines ${s.lines} pieces ${s.pieces}`); emit(`piece ${s.ended ? '-' : s.kind + ' ' + states[s.position[0]] + ' ' + s.position[1] + ' ' + s.position[2]} streak ${s.streak} chain ${s.chain} pending ${total(s.pending)}`); break;
            case 'ANALYZE': { const e = evaluation(s.board, 0); emit('heights ' + e.heights.join(' ')); emit(`holes ${e.holes} bumpiness ${e.bumpiness} value ${e.value}`); break; }
            case 'ROW': {
                const r = Number(args[0]), pattern = args[1];
                if (cells(s.kind, s.position).some(([c, row]) => row === r && pattern[c - 1] === '#')) { emit('ERROR overlap'); break; }
                s.board[r - 1] = [...pattern].reduce((row, ch, i) => row | (ch === '#' ? 1 << i : 0), 0); emit('OK'); break;
            }
            case 'GARBAGE': {
                const n = Number(args[0]), hole = Number(args[1]); this.insertGarbage(n, hole);
                for (let j = 0; j <= n; j++) { const p: Position = [s.position[0], s.position[1], s.position[2] + j]; if (fits(s.board, s.kind, p)) { s.position = p; emit('OK'); return; } }
                this.over('top out');
            }
            case 'ATTACK': s.pending.push(Number(args[0])); emit('pending ' + total(s.pending)); break;
            case 'TICK': for (let i = 0; i < Number(args[0]); i++) this.tick(); break;
            case 'UNDO':
                if (this.history.length === 0) emit('ERROR nothing to undo');
                else { this.state = structuredClone(this.history.pop()!); this.start = structuredClone(this.state); emit(`undo ${this.state.pieces} ${this.state.kind}`); }
                break;
            case 'SAVE': this.saves.set(args[0], structuredClone({state: s, history: this.history, start: this.start})); emit('OK'); break;
            case 'LOAD': {
                const saved = this.saves.get(args[0]);
                if (!saved) emit('ERROR unknown save');
                else { const copy = structuredClone(saved); this.state = copy.state; this.history = copy.history; this.start = copy.start; emit(`load ${this.state.pieces} ${this.state.kind}`); }
                break;
            }
            case 'SPINS': this.spins(); break;
            case 'HINT': this.ranked().slice(0, Number(args[0])).forEach((c, i) => emit(`hint ${i + 1} ${c.kind} ${c.keys.join(' ')} value ${c.value}`)); break;
            case 'AUTO':
                for (let i = 0; i < Number(args[0]); i++) { const best = this.ranked()[0]; emit(`auto ${best.kind} ${best.keys.join(' ')}`); for (const operation of best.keys) this.operation(operation); }
                break;
        }
    }
}

function validArguments(command: string, args: string[]): boolean {
    const number = (text: string, low: number, high: number): boolean => /^(0|[1-9][0-9]*)$/.test(text) && Number(text) >= low && Number(text) <= high;
    if (command === 'NEW') return args.length === 2 && number(args[0], 1, 2147483646) && number(args[1], 1, 15);
    if (command === 'ROW') return args.length === 2 && number(args[0], 1, 22) && /^[#.]{10}$/.test(args[1]) && args[1].includes('.');
    if (command === 'GARBAGE') return args.length === 2 && number(args[0], 1, 10) && number(args[1], 1, 10);
    if (command === 'SAVE' || command === 'LOAD') return args.length === 1 && /^[a-z]{1,8}$/.test(args[0]);
    const limits = new Map([['PREVIEW',14], ['ATTACK',20], ['TICK',1000], ['HINT',10], ['AUTO',50]]);
    if (limits.has(command)) return args.length === 1 && number(args[0], 1, limits.get(command)!);
    return args.length === 0;
}
const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
let game: Game | null = null, serial = 0;
for (const line of lines.slice(1, Number(lines[0]) + 1)) {
    const [command, ...args] = line.split(' ');
    try {
        if (commands.has(command)) {
            if (!validArguments(command, args)) emit('ERROR bad arguments');
            else if (command === 'NEW') {
                if (game && !game.state.ended) { emit('game stopped'); game.summary(); }
                emit(`game ${++serial} seed ${Number(args[0])} level ${Number(args[1])}`); game = new Game(serial, Number(args[0]), Number(args[1]));
            } else if (!game) emit('ERROR no game');
            else if (game.state.ended && !afterEnd.has(command)) emit('ERROR game over');
            else game.command(command, args);
        } else {
            const invalid = [command, ...args].find(word => !operations.has(word));
            if (invalid !== undefined) emit('ERROR unknown ' + invalid);
            else if (!game) emit('ERROR no game');
            else if (game.state.ended) emit('ERROR game over');
            else for (const operation of [command, ...args]) game.operation(operation);
        }
    } catch (e) { if (!(e instanceof GameOver)) throw e; }
}
if (game && !game.state.ended) { emit('game stopped'); game.summary(); }
process.stdout.write(output.join('\n') + '\n');
