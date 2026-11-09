import { readFileSync } from 'node:fs';

type PlayerIndex = 0 | 1;
type ShipIndex = 0 | 1 | 2 | 3 | 4;
type Phase = 'SETUP' | 'BATTLE' | 'OVER';
type Strategy = 'HUNT' | 'PROB' | 'RANDOM';
type Controller = 'HUMAN' | Strategy;
type Direction = 'H' | 'V';
type Side = 'W' | 'E';
type CellView = '~' | '.' | 'o' | 'x' | '#';
type HuntStep = 'LINE' | 'STACK' | 'PARITY';
type OutputMode = 'normal' | 'match' | 'quiet';
type Fleet = [readonly number[], readonly number[], readonly number[], readonly number[], readonly number[]];

const ships = ['CARRIER', 'BATTLESHIP', 'CRUISER', 'SUBMARINE', 'DESTROYER'] as const;
const shipIndices = [0, 1, 2, 3, 4] as const;
const playerIndices = [0, 1] as const;
const lengths = [5, 4, 3, 3, 2] as const;
const symbols = ['C', 'B', 'R', 'S', 'D'] as const;
const strategies: readonly Strategy[] = ['HUNT', 'PROB', 'RANDOM'];
type ShipName = typeof ships[number];

type Command =
    | { kind: 'PLACE'; player: PlayerIndex; ship: ShipIndex; cell: number; direction: Direction }
    | { kind: 'REMOVE'; player: PlayerIndex; ship: ShipIndex }
    | { kind: 'AUTOPLACE'; player: PlayerIndex; seed: number }
    | { kind: 'SEED'; player: PlayerIndex; seed: number }
    | { kind: 'LAYOUT'; player: PlayerIndex; layout: string }
    | { kind: 'REEF'; cell: number }
    | { kind: 'SALVO'; enabled: boolean }
    | { kind: 'CHAIN'; enabled: boolean }
    | { kind: 'TOUCH'; enabled: boolean }
    | { kind: 'FIRE'; player: PlayerIndex; cells: readonly number[] }
    | { kind: 'AI'; player: PlayerIndex; strategy: Strategy }
    | { kind: 'HINT'; player: PlayerIndex; strategy: Strategy }
    | { kind: 'TORPEDO'; player: PlayerIndex; row: number; side: Side }
    | { kind: 'SONAR'; player: PlayerIndex; cell: number }
    | { kind: 'RESIGN'; player: PlayerIndex }
    | { kind: 'DENSITY'; player: PlayerIndex }
    | { kind: 'SHOW'; player: PlayerIndex }
    | { kind: 'RADAR'; player: PlayerIndex }
    | { kind: 'EXPORT'; player: PlayerIndex }
    | { kind: 'FLEET'; player: PlayerIndex }
    | { kind: 'CONTROL'; player: PlayerIndex; controller: Controller }
    | { kind: 'NEW' }
    | { kind: 'STATUS' }
    | { kind: 'STATS' }
    | { kind: 'MATCH'; seeds: readonly [number, number]; strategies: readonly [Strategy, Strategy] }
    | { kind: 'SERIES'; count: number; seed: number; strategies: readonly [Strategy, Strategy] }
    | { kind: 'TOURNEY'; count: number; seed: number };

type SpecialCommand = Extract<Command, { kind: 'TORPEDO' | 'SONAR' }>;
type Shot = { kind: 'ALREADY' | 'MISS' | 'HIT' } | { kind: 'SUNK'; ship: ShipIndex };
interface Choice { readonly cell: number; readonly info: number | HuntStep; readonly nextRandom: number }
interface MatchResult {
    readonly winner: PlayerIndex;
    readonly shots: readonly [number, number];
    readonly hits: readonly [number, number];
}

const advance = (state: number): number => 48271 * state % 2147483647;
const otherPlayer = (player: PlayerIndex): PlayerIndex => player === 0 ? 1 : 0;
const coordinate = (cell: number): string => String.fromCharCode(65 + Math.floor(cell / 10)) + (cell % 10 + 1);
const parseCell = (word: string): number => (word.charCodeAt(0) - 65) * 10 + Number(word.slice(1)) - 1;
const shipRange = (cells: readonly number[]): string => `${coordinate(cells[0])}-${coordinate(cells[cells.length - 1])}`;
const touching = (a: number, b: number): boolean => Math.abs(Math.floor(a / 10) - Math.floor(b / 10)) <= 1 && Math.abs(a % 10 - b % 10) <= 1;
const emptyFleet = (): Fleet => [[], [], [], [], []];
const isHit = (shot: Shot): boolean => shot.kind === 'HIT' || shot.kind === 'SUNK';
const shotText = (shot: Shot): string => shot.kind === 'SUNK' ? `SUNK ${ships[shot.ship]}` : shot.kind;

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }

function parseCommand(words: readonly string[]): Command {
    const kind = words[0] as Command['kind'];
    const player = (): PlayerIndex => (Number(words[1]) - 1) as PlayerIndex;
    const ship = (): ShipIndex => ships.indexOf(words[2] as ShipName) as ShipIndex;
    const pair = (): readonly [Strategy, Strategy] => [words[3] as Strategy, words[4] as Strategy];
    switch (kind) {
        case 'PLACE': return { kind, player: player(), ship: ship(), cell: parseCell(words[3]), direction: words[4] as Direction };
        case 'REMOVE': return { kind, player: player(), ship: ship() };
        case 'AUTOPLACE': case 'SEED': return { kind, player: player(), seed: Number(words[2]) };
        case 'LAYOUT': return { kind, player: player(), layout: words[2] };
        case 'REEF': return { kind, cell: parseCell(words[1]) };
        case 'SALVO': case 'CHAIN': case 'TOUCH': return { kind, enabled: words[1] === 'ON' };
        case 'FIRE': return { kind, player: player(), cells: words.slice(2).map(parseCell) };
        case 'AI': case 'HINT': return { kind, player: player(), strategy: words[2] as Strategy };
        case 'TORPEDO': return { kind, player: player(), row: words[2].charCodeAt(0) - 65, side: words[3] as Side };
        case 'SONAR': return { kind, player: player(), cell: parseCell(words[2]) };
        case 'RESIGN': case 'DENSITY': case 'SHOW': case 'RADAR': case 'EXPORT': case 'FLEET': return { kind, player: player() };
        case 'CONTROL': return { kind, player: player(), controller: words[2] as Controller };
        case 'MATCH': return { kind, seeds: [Number(words[1]), Number(words[2])], strategies: pair() };
        case 'SERIES': return { kind, count: Number(words[1]), seed: Number(words[2]), strategies: pair() };
        case 'TOURNEY': return { kind, count: Number(words[1]), seed: Number(words[2]) };
        case 'NEW': case 'STATUS': case 'STATS': return { kind };
    }
}

function step(cell: number, dr: number, dc: number): number {
    const row = Math.floor(cell / 10) + dr;
    const column = cell % 10 + dc;
    return row >= 0 && row < 10 && column >= 0 && column < 10 ? row * 10 + column : -1;
}

function footprint(start: number, direction: Direction, length: number): readonly number[] | null {
    const position = direction === 'H' ? start % 10 : Math.floor(start / 10);
    if (position + length > 10) return null;
    return Array.from({ length }, (_, index) => start + index * (direction === 'H' ? 1 : 10));
}

class Player {
    fleet: Fleet = emptyFleet();
    readonly attacked: boolean[] = Array<boolean>(100).fill(false);
    readonly candidates: number[] = [];
    controller: Controller = 'HUMAN';
    torpedo = false;
    sonar = false;
    shots = 0;
    hits = 0;
    sinks = 0;
    turns = 0;
    streak = 0;
    bestStreak = 0;

    constructor(public random: number, public wins = 0) {}

    shipAt(cell: number): ShipIndex | null { return shipIndices.find(ship => this.fleet[ship].includes(cell)) ?? null; }
    sunk(ship: ShipIndex): boolean { return this.fleet[ship].length !== 0 && this.fleet[ship].every(cell => this.attacked[cell]); }
    get placed(): number { return this.fleet.filter(cells => cells.length !== 0).length; }
    get afloat(): number { return shipIndices.filter(ship => this.fleet[ship].length !== 0 && !this.sunk(ship)).length; }
    get defeated(): boolean { return shipIndices.every(ship => this.sunk(ship)); }
}

class Game {
    phase: Phase = 'SETUP';
    current: PlayerIndex = 0;
    winner: PlayerIndex | null = null;
    salvo = false;
    chain = false;
    touch = false;
    reefs = new Set<number>();
    readonly players: readonly [Player, Player];

    constructor(wins: readonly [number, number] = [0, 0]) {
        this.players = [new Player(1, wins[0]), new Player(2, wins[1])];
    }

    get finished(): boolean { return this.phase === 'OVER'; }

    placementProblem(player: Player, cells: readonly number[] | null): string | null {
        if (cells === null) return 'out of bounds';
        if (cells.some(cell => this.reefs.has(cell))) return 'on reef';
        for (const ship of shipIndices) {
            if (cells.some(cell => player.fleet[ship].includes(cell))) return `overlaps ${ships[ship]}`;
        }
        if (!this.touch) {
            for (const ship of shipIndices) {
                if (cells.some(cell => player.fleet[ship].some(other => touching(cell, other)))) return `touches ${ships[ship]}`;
            }
        }
        return null;
    }

    placementOutput(p: PlayerIndex): string[] {
        return shipIndices.map(ship => `PLACED ${p + 1} ${ships[ship]} ${shipRange(this.players[p].fleet[ship])}`);
    }

    autoPlace(p: PlayerIndex, seed: number): number {
        const player = this.players[p];
        player.random = seed;
        player.fleet = emptyFleet();
        let attempts = 0;
        for (const ship of shipIndices) {
            while (player.fleet[ship].length === 0) {
                attempts++;
                player.random = advance(player.random);
                const direction: Direction = player.random % 2 === 0 ? 'H' : 'V';
                player.random = advance(player.random);
                const span = 11 - lengths[ship];
                const index = player.random % (10 * span);
                const start = direction === 'H' ? Math.floor(index / span) * 10 + index % span : index;
                const cells = footprint(start, direction, lengths[ship]);
                if (this.placementProblem(player, cells) === null) player.fleet[ship] = cells!;
            }
        }
        return attempts;
    }

    view(p: PlayerIndex): CellView[] {
        const opponent = this.players[otherPlayer(p)];
        return Array.from({ length: 100 }, (_, cell): CellView => {
            if (this.reefs.has(cell)) return '~';
            if (!opponent.attacked[cell]) return '.';
            const ship = opponent.shipAt(cell);
            return ship === null ? 'o' : opponent.sunk(ship) ? '#' : 'x';
        });
    }

    excluded(view: readonly CellView[]): boolean[] {
        const result = Array<boolean>(100).fill(false);
        if (!this.touch) {
            for (let cell = 0; cell < 100; cell++) {
                if (view[cell] !== '#') continue;
                for (let dr = -1; dr <= 1; dr++) {
                    for (let dc = -1; dc <= 1; dc++) {
                        if (dr === 0 && dc === 0) continue;
                        const next = step(cell, dr, dc);
                        if (next !== -1) result[next] = true;
                    }
                }
            }
        }
        return result;
    }

    density(p: PlayerIndex, view: readonly CellView[], excluded: readonly boolean[]): number[] {
        const scores = Array<number>(100).fill(0);
        for (const ship of shipIndices) {
            if (this.players[otherPlayer(p)].sunk(ship)) continue;
            for (let start = 0; start < 100; start++) {
                for (const direction of ['H', 'V'] as const) {
                    const cells = footprint(start, direction, lengths[ship]);
                    if (cells === null || cells.some(cell => excluded[cell] || (view[cell] !== '.' && view[cell] !== 'x'))) continue;
                    const weight = 1 + 10 * cells.filter(cell => view[cell] === 'x').length;
                    for (const cell of cells) scores[cell] += weight;
                }
            }
        }
        return scores;
    }

    choose(p: PlayerIndex, strategy: Strategy): Choice {
        const player = this.players[p];
        const view = this.view(p);
        const excluded = this.excluded(view);
        const candidate = (cell: number): boolean => cell >= 0 && cell < 100 && view[cell] === '.' && !excluded[cell];
        if (strategy === 'PROB') {
            const scores = this.density(p, view, excluded);
            let chosen = -1;
            for (let cell = 0; cell < 100; cell++) {
                if (view[cell] === '.' && (chosen === -1 || scores[cell] > scores[chosen])) chosen = cell;
            }
            return { cell: chosen, info: scores[chosen], nextRandom: player.random };
        }
        if (strategy === 'RANDOM') {
            const cells = Array.from({ length: 100 }, (_, cell) => cell).filter(candidate);
            const random = advance(player.random);
            return { cell: cells[random % cells.length], info: cells.length, nextRandom: random };
        }
        for (let cell = 0; cell < 100; cell++) {
            if (view[cell] !== 'x') continue;
            for (const [dr, dc] of [[0, 1], [1, 0]]) {
                let front = step(cell, dr, dc);
                if (front === -1 || view[front] !== 'x') continue;
                while (front !== -1 && view[front] === 'x') front = step(front, dr, dc);
                const back = step(cell, -dr, -dc);
                if (candidate(front)) return { cell: front, info: 'LINE', nextRandom: player.random };
                if (candidate(back)) return { cell: back, info: 'LINE', nextRandom: player.random };
            }
        }
        for (let i = player.candidates.length - 1; i >= 0; i--) {
            const cell = player.candidates[i];
            if (candidate(cell)) return { cell, info: 'STACK', nextRandom: player.random };
        }
        const shortest = Math.min(...shipIndices.filter(ship => !this.players[otherPlayer(p)].sunk(ship)).map(ship => lengths[ship]));
        for (let cell = 0; cell < 100; cell++) {
            if (candidate(cell) && (Math.floor(cell / 10) + cell % 10) % shortest === 0) {
                return { cell, info: 'PARITY', nextRandom: player.random };
            }
        }
        throw new Error('No strategy candidate');
    }

    shoot(p: PlayerIndex, cell: number): Shot {
        const player = this.players[p];
        const opponent = this.players[otherPlayer(p)];
        let shot: Shot = { kind: 'ALREADY' };
        if (!opponent.attacked[cell]) {
            opponent.attacked[cell] = true;
            const ship = opponent.shipAt(cell);
            shot = ship === null ? { kind: 'MISS' } : opponent.sunk(ship) ? { kind: 'SUNK', ship } : { kind: 'HIT' };
        }
        if (shot.kind === 'HIT') {
            for (const [dr, dc] of [[0, -1], [1, 0], [0, 1], [-1, 0]]) {
                const next = step(cell, dr, dc);
                if (next !== -1) player.candidates.push(next);
            }
        }
        player.shots++;
        if (isHit(shot)) {
            player.hits++;
            player.streak++;
            player.bestStreak = Math.max(player.bestStreak, player.streak);
        } else player.streak = 0;
        if (shot.kind === 'SUNK') player.sinks++;
        return shot;
    }

    allowance(p: PlayerIndex): number { return this.salvo ? this.players[p].afloat : 1; }

    finishTurn(p: PlayerIndex, hit: boolean, output: string[], mode: OutputMode): void {
        this.players[p].turns++;
        if (this.players[otherPlayer(p)].defeated) {
            this.phase = 'OVER';
            this.winner = p;
            this.players[p].wins++;
            if (mode === 'normal') output.push(`WINNER ${p + 1}`);
        } else this.current = this.chain && hit ? p : otherPlayer(p);
    }

    shootingTurn(p: PlayerIndex, strategy: Strategy | null, cells: readonly number[], output: string[], mode: OutputMode = 'normal'): void {
        this.phase = 'BATTLE';
        const count = this.allowance(p);
        let hit = false;
        for (let i = 0; i < count; i++) {
            let cell: number;
            if (strategy === null) cell = cells[i];
            else {
                const choice = this.choose(p, strategy);
                cell = choice.cell;
                this.players[p].random = choice.nextRandom;
            }
            const shot = this.shoot(p, cell);
            hit ||= isHit(shot);
            if (mode === 'normal') output.push(`SHOT ${p + 1} ${coordinate(cell)} ${shotText(shot)}`);
            if (mode === 'match' && shot.kind === 'SUNK') output.push(`SINK ${p + 1} ${ships[shot.ship]} ${this.players[p].shots}`);
            if (this.players[otherPlayer(p)].defeated) break;
        }
        this.finishTurn(p, hit, output, mode);
    }

    checkTurn(p: PlayerIndex): void {
        if (this.phase === 'OVER') fail('game over');
        if (this.phase === 'SETUP' && this.players.some(player => player.placed !== 5)) fail('fleets not ready');
        if (p !== this.current) fail('not your turn');
    }

    specialTurn(command: SpecialCommand, output: string[]): void {
        this.phase = 'BATTLE';
        const p = command.player;
        const player = this.players[p];
        const opponent = this.players[otherPlayer(p)];
        let hit = false;
        if (command.kind === 'SONAR') {
            player.sonar = true;
            let count = 0;
            for (let dr = -1; dr <= 1; dr++) {
                for (let dc = -1; dc <= 1; dc++) {
                    const cell = step(command.cell, dr, dc);
                    if (cell !== -1 && !opponent.attacked[cell] && opponent.shipAt(cell) !== null) count++;
                }
            }
            output.push(`SONAR ${p + 1} ${coordinate(command.cell)} ${count}`);
        } else {
            player.torpedo = true;
            let result = 'MISS';
            let shot: Shot | null = null;
            for (let index = 0; index < 10; index++) {
                const cell = command.row * 10 + (command.side === 'W' ? index : 9 - index);
                if (this.reefs.has(cell)) {
                    result = `REEF ${coordinate(cell)}`;
                    break;
                }
                if (opponent.shipAt(cell) !== null) {
                    shot = this.shoot(p, cell);
                    result = `${shotText(shot)} ${coordinate(cell)}`;
                    hit = isHit(shot);
                    break;
                }
                opponent.attacked[cell] = true;
            }
            if (shot === null) {
                player.shots++;
                player.streak = 0;
            }
            output.push(`TORPEDO ${p + 1} ${String.fromCharCode(65 + command.row)} ${command.side} ${result}`);
        }
        this.finishTurn(p, hit, output, 'normal');
    }

    automatic(output: string[]): void {
        while (this.phase === 'BATTLE') {
            const p = this.current;
            const controller = this.players[p].controller;
            if (controller === 'HUMAN') break;
            this.shootingTurn(p, controller, [], output);
        }
    }

    match(seed1: number, seed2: number, methods: readonly [Strategy, Strategy], output: string[] | null = null): MatchResult {
        const game = new Game();
        game.salvo = this.salvo;
        game.chain = this.chain;
        game.touch = this.touch;
        game.reefs = new Set(this.reefs);
        game.autoPlace(0, seed1);
        game.autoPlace(1, seed2);
        game.phase = 'BATTLE';
        const lines = output ?? [];
        while (!game.finished) {
            game.shootingTurn(game.current, methods[game.current], [], lines, output === null ? 'quiet' : 'match');
        }
        return { winner: game.winner!, shots: [game.players[0].shots, game.players[1].shots], hits: [game.players[0].hits, game.players[1].hits] };
    }

    layout(p: PlayerIndex, text: string): string[] {
        const grid = text.replaceAll('/', '');
        const fleet = emptyFleet();
        for (const ship of shipIndices) {
            const cells = Array.from({ length: 100 }, (_, cell) => cell).filter(cell => grid[cell] === symbols[ship]);
            if (cells.length !== lengths[ship]) fail(`${ships[ship]} has ${cells.length} cells`);
            const horizontal = cells.every((cell, index) => cell === cells[0] + index && Math.floor(cell / 10) === Math.floor(cells[0] / 10));
            const vertical = cells.every((cell, index) => cell === cells[0] + 10 * index);
            if (!horizontal && !vertical) fail(`${ships[ship]} not straight`);
            if (cells.some(cell => this.reefs.has(cell))) fail(`${ships[ship]} on reef`);
            fleet[ship] = cells;
        }
        if (!this.touch) {
            for (const first of shipIndices) {
                for (const second of shipIndices) {
                    if (second <= first) continue;
                    if (fleet[first].some(cell => fleet[second].some(other => touching(cell, other)))) fail(`${ships[first]} touches ${ships[second]}`);
                }
            }
        }
        this.players[p].fleet = fleet;
        return [`LAYOUT ${p + 1}`, ...this.placementOutput(p)];
    }

    boardOutput(p: PlayerIndex, radar: boolean): string[] {
        const player = this.players[p];
        const view: readonly string[] = radar ? this.view(p) : Array.from({ length: 100 }, (_, cell) => {
            if (this.reefs.has(cell)) return '~';
            const ship = player.shipAt(cell);
            if (ship !== null) return player.attacked[cell] ? symbols[ship].toLowerCase() : symbols[ship];
            return player.attacked[cell] ? 'o' : '.';
        });
        const output = [`${radar ? 'RADAR' : 'BOARD'} ${p + 1}`, '  1 2 3 4 5 6 7 8 9 10'];
        for (let row = 0; row < 10; row++) output.push(String.fromCharCode(65 + row) + ' ' + view.slice(row * 10, row * 10 + 10).join(' '));
        return output;
    }

    densityOutput(p: PlayerIndex): string[] {
        const view = this.view(p);
        const scores = this.density(p, view, this.excluded(view));
        const output = [`DENSITY ${p + 1}`, ' ' + Array.from({ length: 10 }, (_, i) => String(i + 1).padStart(5)).join('')];
        let best = -1;
        for (let row = 0; row < 10; row++) {
            let text = String.fromCharCode(65 + row);
            for (let column = 0; column < 10; column++) {
                const cell = row * 10 + column;
                const value = view[cell] === '.' ? String(scores[cell]) : view[cell] === '~' ? '~' : '-';
                text += value.padStart(5);
                if (view[cell] === '.' && (best === -1 || scores[cell] > scores[best])) best = cell;
            }
            output.push(text);
        }
        output.push(`BEST ${coordinate(best)} ${scores[best]}`);
        return output;
    }

    export(p: PlayerIndex): string {
        const grid = Array<string>(100).fill('.');
        for (const ship of shipIndices) for (const cell of this.players[p].fleet[ship]) grid[cell] = symbols[ship];
        return Array.from({ length: 10 }, (_, row) => grid.slice(row * 10, row * 10 + 10).join('')).join('/');
    }

    fleetOutput(p: PlayerIndex): string[] {
        const player = this.players[p];
        const output = [`FLEET ${p + 1} afloat ${player.afloat}`];
        for (const ship of shipIndices) {
            const cells = player.fleet[ship];
            if (cells.length === 0) output.push(`${ships[ship]} unplaced`);
            else output.push(`${ships[ship]} ${shipRange(cells)} ${cells.filter(cell => player.attacked[cell]).length}/${lengths[ship]} ${player.sunk(ship) ? 'SUNK' : 'AFLOAT'}`);
        }
        return output;
    }

    status(): string {
        const prefix = `STATUS ${this.phase} salvo ${this.salvo ? 'ON' : 'OFF'} chain ${this.chain ? 'ON' : 'OFF'} touch ${this.touch ? 'ON' : 'OFF'} reefs ${this.reefs.size}`;
        if (this.phase === 'SETUP') return `${prefix} placed ${this.players[0].placed} ${this.players[1].placed}`;
        const turn = this.phase === 'BATTLE' ? `turn ${this.current + 1} shots ${this.allowance(this.current)}` : `winner ${this.winner! + 1}`;
        return `${prefix} ${turn} afloat ${this.players[0].afloat} ${this.players[1].afloat}`;
    }

    statistics(): string[] {
        return this.players.map((player, p) => {
            const accuracy = player.shots === 0 ? '-' : `${Math.floor(player.hits * 100 / player.shots)}%`;
            return `STATS ${p + 1} shots ${player.shots} hits ${player.hits} sunk ${player.sinks} turns ${player.turns} streak ${player.bestStreak} accuracy ${accuracy} wins ${player.wins}`;
        });
    }
}

const setupCommands = new Set<Command['kind']>(['PLACE', 'REMOVE', 'AUTOPLACE', 'LAYOUT', 'REEF', 'SALVO', 'CHAIN', 'TOUCH']);

class Program {
    game = new Game();

    execute(command: Command): string[] {
        if (command.kind === 'NEW') {
            this.game = new Game([this.game.players[0].wins, this.game.players[1].wins]);
            return ['NEW'];
        }
        const game = this.game;
        if (setupCommands.has(command.kind) && game.phase !== 'SETUP') fail('setup closed');
        switch (command.kind) {
            case 'PLACE': {
                const { player: p, ship } = command;
                const player = game.players[p];
                if (player.fleet[ship].length !== 0) fail(`${ships[ship]} already placed`);
                const cells = footprint(command.cell, command.direction, lengths[ship]);
                const problem = game.placementProblem(player, cells);
                if (problem !== null) fail(problem);
                player.fleet[ship] = cells!;
                return [`PLACED ${p + 1} ${ships[ship]} ${shipRange(cells!)}`];
            }
            case 'REMOVE': {
                const { player: p, ship } = command;
                if (game.players[p].fleet[ship].length === 0) fail(`${ships[ship]} not placed`);
                game.players[p].fleet[ship] = [];
                return [`REMOVED ${p + 1} ${ships[ship]}`];
            }
            case 'AUTOPLACE': {
                const attempts = game.autoPlace(command.player, command.seed);
                return [`AUTOPLACE ${command.player + 1} attempts ${attempts}`, ...game.placementOutput(command.player)];
            }
            case 'LAYOUT': return game.layout(command.player, command.layout);
            case 'REEF': {
                const cell = command.cell;
                if (game.reefs.has(cell)) fail(`reef exists at ${coordinate(cell)}`);
                for (const owner of playerIndices) {
                    const ship = game.players[owner].shipAt(cell);
                    if (ship !== null) fail(`${coordinate(cell)} occupied by ${owner + 1} ${ships[ship]}`);
                }
                game.reefs.add(cell);
                return [`REEF ${coordinate(cell)}`];
            }
            case 'SALVO': case 'CHAIN': case 'TOUCH':
                if (command.kind === 'SALVO') game.salvo = command.enabled;
                else if (command.kind === 'CHAIN') game.chain = command.enabled;
                else game.touch = command.enabled;
                return [`${command.kind} ${command.enabled ? 'ON' : 'OFF'}`];
            case 'FIRE': case 'AI': case 'TORPEDO': case 'SONAR': {
                const p = command.player;
                game.checkTurn(p);
                const output: string[] = [];
                if (command.kind === 'FIRE') {
                    const allowance = game.allowance(p);
                    if (command.cells.length !== allowance) fail(`expected ${allowance} shots`);
                    for (const cell of command.cells) if (game.reefs.has(cell)) fail(`reef at ${coordinate(cell)}`);
                    game.shootingTurn(p, null, command.cells, output);
                } else if (command.kind === 'AI') game.shootingTurn(p, command.strategy, [], output);
                else {
                    if (command.kind === 'TORPEDO' && game.players[p].torpedo) fail('torpedo used');
                    if (command.kind === 'SONAR' && game.players[p].sonar) fail('sonar used');
                    game.specialTurn(command, output);
                }
                game.automatic(output);
                return output;
            }
            case 'RESIGN': {
                if (game.phase !== 'BATTLE') fail('not in battle');
                const winner = otherPlayer(command.player);
                game.phase = 'OVER';
                game.winner = winner;
                game.players[winner].wins++;
                return [`RESIGN ${command.player + 1}`, `WINNER ${winner + 1}`];
            }
            case 'CONTROL':
                game.players[command.player].controller = command.controller;
                return [`CONTROL ${command.player + 1} ${command.controller}`];
            case 'SEED':
                game.players[command.player].random = command.seed;
                return [`SEED ${command.player + 1} ${command.seed}`];
            case 'HINT': {
                if (game.phase === 'OVER') fail('game over');
                const choice = game.choose(command.player, command.strategy);
                return [`HINT ${command.player + 1} ${command.strategy} ${coordinate(choice.cell)} ${choice.info}`];
            }
            case 'DENSITY':
                if (game.phase === 'OVER') fail('game over');
                return game.densityOutput(command.player);
            case 'SHOW': return game.boardOutput(command.player, false);
            case 'RADAR': return game.boardOutput(command.player, true);
            case 'EXPORT': return [`EXPORT ${command.player + 1} ${game.export(command.player)}`];
            case 'FLEET': return game.fleetOutput(command.player);
            case 'STATUS': return [game.status()];
            case 'STATS': return game.statistics();
            case 'MATCH': {
                const output = [`MATCH 1 ${command.strategies[0]} 2 ${command.strategies[1]}`];
                const match = game.match(command.seeds[0], command.seeds[1], command.strategies, output);
                output.push(`RESULT winner ${match.winner + 1} shots ${match.shots[0]} ${match.shots[1]} hits ${match.hits[0]} ${match.hits[1]}`);
                return output;
            }
            case 'SERIES': {
                let random = command.seed;
                const wins = [0, 0];
                const shots = [0, 0];
                const fastest: (number | null)[] = [null, null];
                for (let i = 0; i < command.count; i++) {
                    random = advance(random);
                    const seed1 = random;
                    random = advance(random);
                    const match = game.match(seed1, random, command.strategies);
                    wins[match.winner]++;
                    for (const seat of playerIndices) shots[seat] += match.shots[seat];
                    const wonShots = match.shots[match.winner];
                    fastest[match.winner] = Math.min(fastest[match.winner] ?? wonShots, wonShots);
                }
                return [`SERIES ${command.count} wins ${wins[0]} ${wins[1]} shots ${shots[0]} ${shots[1]} fastest ${fastest[0] ?? '-'} ${fastest[1] ?? '-'}`];
            }
            case 'TOURNEY': {
                let random = command.seed;
                const totals = strategies.map((strategy, index) => ({ strategy, index, wins: 0, shots: 0 }));
                for (let first = 0; first < 3; first++) {
                    for (let second = 0; second < 3; second++) {
                        if (first === second) continue;
                        for (let i = 0; i < command.count; i++) {
                            random = advance(random);
                            const seed1 = random;
                            random = advance(random);
                            const match = game.match(seed1, random, [strategies[first], strategies[second]]);
                            totals[match.winner === 0 ? first : second].wins++;
                            totals[first].shots += match.shots[0];
                            totals[second].shots += match.shots[1];
                        }
                    }
                }
                totals.sort((a, b) => b.wins - a.wins || a.shots - b.shots || a.index - b.index);
                return [`TOURNEY ${command.count}`, ...totals.map((total, rank) => `${rank + 1} ${total.strategy} wins ${total.wins} shots ${total.shots}`)];
            }
        }
    }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/);
const count = Number(lines[0]);
const program = new Program();
for (let i = 1; i <= count; i++) {
    try {
        process.stdout.write(program.execute(parseCommand(lines[i].split(' '))).join('\n') + '\n');
    } catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
