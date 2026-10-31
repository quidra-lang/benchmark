const fs = require('node:fs');

const ships = ['CARRIER', 'BATTLESHIP', 'CRUISER', 'SUBMARINE', 'DESTROYER'];
const lengths = [5, 4, 3, 3, 2];
const symbols = ['C', 'B', 'R', 'S', 'D'];
const strategies = ['HUNT', 'PROB', 'RANDOM'];
const advance = state => 48271 * state % 2147483647;
const coordinate = cell => String.fromCharCode(65 + Math.floor(cell / 10)) + (cell % 10 + 1);
const parseCell = word => (word.charCodeAt(0) - 65) * 10 + Number(word.slice(1)) - 1;
const shipRange = cells => `${coordinate(cells[0])}-${coordinate(cells[cells.length - 1])}`;
const touching = (a, b) => Math.abs(Math.floor(a / 10) - Math.floor(b / 10)) <= 1 && Math.abs(a % 10 - b % 10) <= 1;

class CommandError extends Error {}
function fail(message) { throw new CommandError(message); }

function step(cell, dr, dc) {
    const row = Math.floor(cell / 10) + dr;
    const column = cell % 10 + dc;
    return row >= 0 && row < 10 && column >= 0 && column < 10 ? row * 10 + column : -1;
}

function footprint(start, direction, length) {
    const row = Math.floor(start / 10);
    const column = start % 10;
    if ((direction === 'H' ? column : row) + length > 10) return null;
    return Array.from({ length }, (_, index) => start + index * (direction === 'H' ? 1 : 10));
}

class Player {
    constructor(seed, wins = 0) {
        this.fleet = Array.from({ length: 5 }, () => []);
        this.attacked = Array(100).fill(false);
        this.candidates = [];
        this.random = seed;
        this.controller = 'HUMAN';
        this.torpedo = false;
        this.sonar = false;
        this.shots = 0;
        this.hits = 0;
        this.sinks = 0;
        this.turns = 0;
        this.streak = 0;
        this.bestStreak = 0;
        this.wins = wins;
    }

    shipAt(cell) { return this.fleet.findIndex(cells => cells.includes(cell)); }
    sunk(ship) { return this.fleet[ship].length !== 0 && this.fleet[ship].every(cell => this.attacked[cell]); }
    get placed() { return this.fleet.filter(cells => cells.length !== 0).length; }
    get afloat() { return this.fleet.filter((cells, ship) => cells.length !== 0 && !this.sunk(ship)).length; }
    get defeated() { return this.fleet.every((_, ship) => this.sunk(ship)); }
}

class Game {
    constructor(wins = [0, 0]) {
        this.phase = 'SETUP';
        this.current = 0;
        this.winner = -1;
        this.salvo = false;
        this.chain = false;
        this.touch = false;
        this.reefs = new Set();
        this.players = [new Player(1, wins[0]), new Player(2, wins[1])];
    }

    placementProblem(player, cells) {
        if (cells === null) return 'out of bounds';
        if (cells.some(cell => this.reefs.has(cell))) return 'on reef';
        for (let ship = 0; ship < 5; ship++) {
            if (cells.some(cell => player.fleet[ship].includes(cell))) return `overlaps ${ships[ship]}`;
        }
        if (!this.touch) {
            for (let ship = 0; ship < 5; ship++) {
                if (cells.some(cell => player.fleet[ship].some(other => touching(cell, other)))) return `touches ${ships[ship]}`;
            }
        }
        return null;
    }

    placementOutput(p) {
        return this.players[p].fleet.map((cells, ship) => `PLACED ${p + 1} ${ships[ship]} ${shipRange(cells)}`);
    }

    autoPlace(p, seed) {
        const player = this.players[p];
        player.random = seed;
        player.fleet = Array.from({ length: 5 }, () => []);
        let attempts = 0;
        for (let ship = 0; ship < 5; ship++) {
            while (player.fleet[ship].length === 0) {
                attempts++;
                player.random = advance(player.random);
                const direction = player.random % 2 === 0 ? 'H' : 'V';
                player.random = advance(player.random);
                const span = 11 - lengths[ship];
                const index = player.random % (10 * span);
                const start = direction === 'H' ? Math.floor(index / span) * 10 + index % span : index;
                const cells = footprint(start, direction, lengths[ship]);
                if (this.placementProblem(player, cells) === null) player.fleet[ship] = cells;
            }
        }
        return attempts;
    }

    view(p) {
        const opponent = this.players[1 - p];
        return Array.from({ length: 100 }, (_, cell) => {
            if (this.reefs.has(cell)) return '~';
            if (!opponent.attacked[cell]) return '.';
            const ship = opponent.shipAt(cell);
            return ship === -1 ? 'o' : opponent.sunk(ship) ? '#' : 'x';
        });
    }

    excluded(view) {
        const result = Array(100).fill(false);
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

    density(p, view, excluded) {
        const scores = Array(100).fill(0);
        for (let ship = 0; ship < 5; ship++) {
            if (this.players[1 - p].sunk(ship)) continue;
            for (let start = 0; start < 100; start++) {
                for (const direction of ['H', 'V']) {
                    const cells = footprint(start, direction, lengths[ship]);
                    if (cells === null || cells.some(cell => excluded[cell] || (view[cell] !== '.' && view[cell] !== 'x'))) continue;
                    const weight = 1 + 10 * cells.filter(cell => view[cell] === 'x').length;
                    for (const cell of cells) scores[cell] += weight;
                }
            }
        }
        return scores;
    }

    choose(p, strategy, mutate = true) {
        const player = this.players[p];
        const view = this.view(p);
        const excluded = this.excluded(view);
        const candidate = cell => cell >= 0 && cell < 100 && view[cell] === '.' && !excluded[cell];
        if (strategy === 'PROB') {
            const scores = this.density(p, view, excluded);
            let chosen = -1;
            for (let cell = 0; cell < 100; cell++) {
                if (view[cell] === '.' && (chosen === -1 || scores[cell] > scores[chosen])) chosen = cell;
            }
            return { cell: chosen, info: String(scores[chosen]) };
        }
        if (strategy === 'RANDOM') {
            const cells = Array.from({ length: 100 }, (_, cell) => cell).filter(candidate);
            const random = advance(player.random);
            if (mutate) player.random = random;
            return { cell: cells[random % cells.length], info: String(cells.length) };
        }
        for (let cell = 0; cell < 100; cell++) {
            if (view[cell] !== 'x') continue;
            for (const [dr, dc] of [[0, 1], [1, 0]]) {
                const neighbor = step(cell, dr, dc);
                if (neighbor === -1 || view[neighbor] !== 'x') continue;
                let front = neighbor;
                while (front !== -1 && view[front] === 'x') front = step(front, dr, dc);
                const back = step(cell, -dr, -dc);
                if (candidate(front)) return { cell: front, info: 'LINE' };
                if (candidate(back)) return { cell: back, info: 'LINE' };
            }
        }
        for (let i = player.candidates.length - 1; i >= 0; i--) {
            if (candidate(player.candidates[i])) return { cell: player.candidates[i], info: 'STACK' };
        }
        const shortest = Math.min(...lengths.filter((_, ship) => !this.players[1 - p].sunk(ship)));
        for (let cell = 0; cell < 100; cell++) {
            if (candidate(cell) && (Math.floor(cell / 10) + cell % 10) % shortest === 0) return { cell, info: 'PARITY' };
        }
        throw new Error('No strategy candidate');
    }

    shoot(p, cell) {
        const player = this.players[p];
        const opponent = this.players[1 - p];
        let text = 'ALREADY';
        let hit = false;
        let sunk = -1;
        if (!opponent.attacked[cell]) {
            opponent.attacked[cell] = true;
            const ship = opponent.shipAt(cell);
            if (ship === -1) text = 'MISS';
            else {
                hit = true;
                if (opponent.sunk(ship)) {
                    text = `SUNK ${ships[ship]}`;
                    sunk = ship;
                } else {
                    text = 'HIT';
                    for (const [dr, dc] of [[0, -1], [1, 0], [0, 1], [-1, 0]]) {
                        const next = step(cell, dr, dc);
                        if (next !== -1) player.candidates.push(next);
                    }
                }
            }
        }
        player.shots++;
        if (hit) {
            player.hits++;
            player.streak++;
            player.bestStreak = Math.max(player.bestStreak, player.streak);
        } else player.streak = 0;
        if (sunk !== -1) player.sinks++;
        return { text, hit, sunk };
    }

    allowance(p) { return this.salvo ? this.players[p].afloat : 1; }

    finishTurn(p, hit, output, mode) {
        this.players[p].turns++;
        if (this.players[1 - p].defeated) {
            this.phase = 'OVER';
            this.winner = p;
            this.players[p].wins++;
            if (mode === 'normal') output.push(`WINNER ${p + 1}`);
        } else this.current = this.chain && hit ? p : 1 - p;
    }

    shootingTurn(p, strategy, cells, output, mode = 'normal') {
        this.phase = 'BATTLE';
        const count = this.allowance(p);
        let hit = false;
        for (let i = 0; i < count; i++) {
            const cell = strategy === null ? cells[i] : this.choose(p, strategy).cell;
            const result = this.shoot(p, cell);
            hit ||= result.hit;
            if (mode === 'normal') output.push(`SHOT ${p + 1} ${coordinate(cell)} ${result.text}`);
            if (mode === 'match' && result.sunk !== -1) output.push(`SINK ${p + 1} ${ships[result.sunk]} ${this.players[p].shots}`);
            if (this.players[1 - p].defeated) break;
        }
        this.finishTurn(p, hit, output, mode);
    }

    checkTurn(p) {
        if (this.phase === 'OVER') fail('game over');
        if (this.phase === 'SETUP' && this.players.some(player => player.placed !== 5)) fail('fleets not ready');
        if (p !== this.current) fail('not your turn');
    }

    specialTurn(p, command, args, output) {
        this.phase = 'BATTLE';
        const player = this.players[p];
        const opponent = this.players[1 - p];
        let hit = false;
        if (command === 'SONAR') {
            player.sonar = true;
            const center = parseCell(args[0]);
            let count = 0;
            for (let dr = -1; dr <= 1; dr++) {
                for (let dc = -1; dc <= 1; dc++) {
                    const cell = step(center, dr, dc);
                    if (cell !== -1 && !opponent.attacked[cell] && opponent.shipAt(cell) !== -1) count++;
                }
            }
            output.push(`SONAR ${p + 1} ${args[0]} ${count}`);
        } else {
            player.torpedo = true;
            const row = args[0].charCodeAt(0) - 65;
            let result = 'MISS';
            let shot = null;
            for (let index = 0; index < 10; index++) {
                const cell = row * 10 + (args[1] === 'W' ? index : 9 - index);
                if (this.reefs.has(cell)) {
                    result = `REEF ${coordinate(cell)}`;
                    break;
                }
                if (opponent.shipAt(cell) !== -1) {
                    shot = this.shoot(p, cell);
                    result = `${shot.text} ${coordinate(cell)}`;
                    hit = shot.hit;
                    break;
                }
                opponent.attacked[cell] = true;
            }
            if (shot === null) {
                player.shots++;
                player.streak = 0;
            }
            output.push(`TORPEDO ${p + 1} ${args[0]} ${args[1]} ${result}`);
        }
        this.finishTurn(p, hit, output, 'normal');
    }

    automatic(output) {
        while (this.phase === 'BATTLE' && this.players[this.current].controller !== 'HUMAN') {
            const p = this.current;
            this.shootingTurn(p, this.players[p].controller, [], output);
        }
    }

    match(seed1, seed2, strategy1, strategy2, output = null) {
        const game = new Game();
        game.salvo = this.salvo;
        game.chain = this.chain;
        game.touch = this.touch;
        game.reefs = new Set(this.reefs);
        game.autoPlace(0, seed1);
        game.autoPlace(1, seed2);
        game.phase = 'BATTLE';
        const choices = [strategy1, strategy2];
        const lines = output ?? [];
        while (game.phase !== 'OVER') {
            game.shootingTurn(game.current, choices[game.current], [], lines, output === null ? 'quiet' : 'match');
        }
        return game;
    }

    layout(p, text) {
        const grid = text.replaceAll('/', '');
        const fleet = symbols.map(symbol => Array.from({ length: 100 }, (_, cell) => cell).filter(cell => grid[cell] === symbol));
        for (let ship = 0; ship < 5; ship++) {
            const cells = fleet[ship];
            if (cells.length !== lengths[ship]) fail(`${ships[ship]} has ${cells.length} cells`);
            const horizontal = cells.every((cell, index) => cell === cells[0] + index && Math.floor(cell / 10) === Math.floor(cells[0] / 10));
            const vertical = cells.every((cell, index) => cell === cells[0] + 10 * index);
            if (!horizontal && !vertical) fail(`${ships[ship]} not straight`);
            if (cells.some(cell => this.reefs.has(cell))) fail(`${ships[ship]} on reef`);
        }
        if (!this.touch) {
            for (let first = 0; first < 5; first++) {
                for (let second = first + 1; second < 5; second++) {
                    if (fleet[first].some(cell => fleet[second].some(other => touching(cell, other)))) fail(`${ships[first]} touches ${ships[second]}`);
                }
            }
        }
        this.players[p].fleet = fleet;
        return [`LAYOUT ${p + 1}`, ...this.placementOutput(p)];
    }

    boardOutput(p, radar) {
        const player = this.players[p];
        const view = radar ? this.view(p) : Array.from({ length: 100 }, (_, cell) => {
            if (this.reefs.has(cell)) return '~';
            const ship = player.shipAt(cell);
            if (ship !== -1) return player.attacked[cell] ? symbols[ship].toLowerCase() : symbols[ship];
            return player.attacked[cell] ? 'o' : '.';
        });
        const output = [`${radar ? 'RADAR' : 'BOARD'} ${p + 1}`, '  1 2 3 4 5 6 7 8 9 10'];
        for (let row = 0; row < 10; row++) output.push(String.fromCharCode(65 + row) + ' ' + view.slice(row * 10, row * 10 + 10).join(' '));
        return output;
    }

    densityOutput(p) {
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

    export(p) {
        const grid = Array(100).fill('.');
        this.players[p].fleet.forEach((cells, ship) => { for (const cell of cells) grid[cell] = symbols[ship]; });
        return Array.from({ length: 10 }, (_, row) => grid.slice(row * 10, row * 10 + 10).join('')).join('/');
    }

    fleetOutput(p) {
        const player = this.players[p];
        const output = [`FLEET ${p + 1} afloat ${player.afloat}`];
        player.fleet.forEach((cells, ship) => {
            if (cells.length === 0) output.push(`${ships[ship]} unplaced`);
            else output.push(`${ships[ship]} ${shipRange(cells)} ${cells.filter(cell => player.attacked[cell]).length}/${lengths[ship]} ${player.sunk(ship) ? 'SUNK' : 'AFLOAT'}`);
        });
        return output;
    }

    status() {
        const prefix = `STATUS ${this.phase} salvo ${this.salvo ? 'ON' : 'OFF'} chain ${this.chain ? 'ON' : 'OFF'} touch ${this.touch ? 'ON' : 'OFF'} reefs ${this.reefs.size}`;
        if (this.phase === 'SETUP') return `${prefix} placed ${this.players[0].placed} ${this.players[1].placed}`;
        const turn = this.phase === 'BATTLE' ? `turn ${this.current + 1} shots ${this.allowance(this.current)}` : `winner ${this.winner + 1}`;
        return `${prefix} ${turn} afloat ${this.players[0].afloat} ${this.players[1].afloat}`;
    }

    statistics() {
        return this.players.map((player, p) => {
            const accuracy = player.shots === 0 ? '-' : `${Math.floor(player.hits * 100 / player.shots)}%`;
            return `STATS ${p + 1} shots ${player.shots} hits ${player.hits} sunk ${player.sinks} turns ${player.turns} streak ${player.bestStreak} accuracy ${accuracy} wins ${player.wins}`;
        });
    }
}

const setupCommands = new Set(['PLACE', 'REMOVE', 'AUTOPLACE', 'LAYOUT', 'REEF', 'SALVO', 'CHAIN', 'TOUCH']);
const turnCommands = new Set(['FIRE', 'AI', 'TORPEDO', 'SONAR']);

class Program {
    constructor() { this.game = new Game(); }

    execute(words) {
        const command = words[0];
        const p = Number(words[1]) - 1;
        if (command === 'NEW') {
            this.game = new Game(this.game.players.map(player => player.wins));
            return ['NEW'];
        }
        const game = this.game;
        if (setupCommands.has(command)) {
            if (game.phase !== 'SETUP') fail('setup closed');
            if (command === 'PLACE' || command === 'REMOVE') {
                const player = game.players[p];
                const ship = ships.indexOf(words[2]);
                if (command === 'REMOVE') {
                    if (player.fleet[ship].length === 0) fail(`${ships[ship]} not placed`);
                    player.fleet[ship] = [];
                    return [`REMOVED ${p + 1} ${ships[ship]}`];
                }
                if (player.fleet[ship].length !== 0) fail(`${ships[ship]} already placed`);
                const cells = footprint(parseCell(words[3]), words[4], lengths[ship]);
                const problem = game.placementProblem(player, cells);
                if (problem !== null) fail(problem);
                player.fleet[ship] = cells;
                return [`PLACED ${p + 1} ${ships[ship]} ${shipRange(cells)}`];
            }
            if (command === 'AUTOPLACE') {
                const attempts = game.autoPlace(p, Number(words[2]));
                return [`AUTOPLACE ${p + 1} attempts ${attempts}`, ...game.placementOutput(p)];
            }
            if (command === 'LAYOUT') return game.layout(p, words[2]);
            if (command === 'REEF') {
                const cell = parseCell(words[1]);
                if (game.reefs.has(cell)) fail(`reef exists at ${coordinate(cell)}`);
                for (let owner = 0; owner < 2; owner++) {
                    const ship = game.players[owner].shipAt(cell);
                    if (ship !== -1) fail(`${coordinate(cell)} occupied by ${owner + 1} ${ships[ship]}`);
                }
                game.reefs.add(cell);
                return [`REEF ${coordinate(cell)}`];
            }
            game[command.toLowerCase()] = words[1] === 'ON';
            return [`${command} ${words[1]}`];
        }
        if (turnCommands.has(command)) {
            game.checkTurn(p);
            const output = [];
            if (command === 'FIRE') {
                const allowance = game.allowance(p);
                if (words.length - 2 !== allowance) fail(`expected ${allowance} shots`);
                const cells = words.slice(2).map(parseCell);
                for (const cell of cells) if (game.reefs.has(cell)) fail(`reef at ${coordinate(cell)}`);
                game.shootingTurn(p, null, cells, output);
            } else if (command === 'AI') game.shootingTurn(p, words[2], [], output);
            else {
                if (command === 'TORPEDO' && game.players[p].torpedo) fail('torpedo used');
                if (command === 'SONAR' && game.players[p].sonar) fail('sonar used');
                game.specialTurn(p, command, words.slice(2), output);
            }
            game.automatic(output);
            return output;
        }
        switch (command) {
            case 'RESIGN': {
                if (game.phase !== 'BATTLE') fail('not in battle');
                game.phase = 'OVER';
                game.winner = 1 - p;
                game.players[1 - p].wins++;
                return [`RESIGN ${p + 1}`, `WINNER ${2 - p}`];
            }
            case 'CONTROL':
                game.players[p].controller = words[2];
                return [`CONTROL ${p + 1} ${words[2]}`];
            case 'SEED':
                game.players[p].random = Number(words[2]);
                return [`SEED ${p + 1} ${game.players[p].random}`];
            case 'HINT': {
                if (game.phase === 'OVER') fail('game over');
                const choice = game.choose(p, words[2], false);
                return [`HINT ${p + 1} ${words[2]} ${coordinate(choice.cell)} ${choice.info}`];
            }
            case 'DENSITY':
                if (game.phase === 'OVER') fail('game over');
                return game.densityOutput(p);
            case 'SHOW': return game.boardOutput(p, false);
            case 'RADAR': return game.boardOutput(p, true);
            case 'EXPORT': return [`EXPORT ${p + 1} ${game.export(p)}`];
            case 'FLEET': return game.fleetOutput(p);
            case 'STATUS': return [game.status()];
            case 'STATS': return game.statistics();
            case 'MATCH': {
                const output = [`MATCH 1 ${words[3]} 2 ${words[4]}`];
                const match = game.match(Number(words[1]), Number(words[2]), words[3], words[4], output);
                const [first, second] = match.players;
                output.push(`RESULT winner ${match.winner + 1} shots ${first.shots} ${second.shots} hits ${first.hits} ${second.hits}`);
                return output;
            }
            case 'SERIES': {
                const count = Number(words[1]);
                let random = Number(words[2]);
                const wins = [0, 0];
                const shots = [0, 0];
                const fastest = [null, null];
                for (let i = 0; i < count; i++) {
                    random = advance(random);
                    const seed1 = random;
                    random = advance(random);
                    const match = game.match(seed1, random, words[3], words[4]);
                    wins[match.winner]++;
                    match.players.forEach((player, seat) => { shots[seat] += player.shots; });
                    const wonShots = match.players[match.winner].shots;
                    fastest[match.winner] = Math.min(fastest[match.winner] ?? wonShots, wonShots);
                }
                return [`SERIES ${count} wins ${wins[0]} ${wins[1]} shots ${shots[0]} ${shots[1]} fastest ${fastest[0] ?? '-'} ${fastest[1] ?? '-'}`];
            }
            case 'TOURNEY': {
                const count = Number(words[1]);
                let random = Number(words[2]);
                const totals = strategies.map((strategy, index) => ({ strategy, index, wins: 0, shots: 0 }));
                for (let first = 0; first < 3; first++) {
                    for (let second = 0; second < 3; second++) {
                        if (first === second) continue;
                        for (let i = 0; i < count; i++) {
                            random = advance(random);
                            const seed1 = random;
                            random = advance(random);
                            const match = game.match(seed1, random, strategies[first], strategies[second]);
                            totals[match.winner === 0 ? first : second].wins++;
                            totals[first].shots += match.players[0].shots;
                            totals[second].shots += match.players[1].shots;
                        }
                    }
                }
                totals.sort((a, b) => b.wins - a.wins || a.shots - b.shots || a.index - b.index);
                return [`TOURNEY ${count}`, ...totals.map((total, rank) => `${rank + 1} ${total.strategy} wins ${total.wins} shots ${total.shots}`)];
            }
        }
        throw new Error('Unknown command');
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const count = Number(lines[0]);
const program = new Program();
for (let i = 1; i <= count; i++) {
    try {
        process.stdout.write(program.execute(lines[i].split(' ')).join('\n') + '\n');
    } catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
