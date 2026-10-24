import { readFileSync, writeFileSync } from 'node:fs';

type Strategy = 'BASIC' | 'LOW' | 'HIGH' | 'SMART' | 'MOON';
type Rules = { TARGET: number; LIMIT: number; MOON: string; JACK: string; QSBREAK: string; BLOOD: string; PASS: string };
type Play = [number, number];
type LogLine = { level: number; text: string };
type FinishedHand = { number: number; direction: string; points: number[]; shooter: number; record: string[] };
type Position = { hands: number[][]; taken: number[][]; tricks: Play[][]; counts: number[]; current: Play[]; leader: number; broken: boolean; record: string[] };
type Undo = { position: Position; logLength: number; seat: number; card: number };
const seats = 'NESW', suits = 'CDSH', ranks = '23456789TJQKA';
const strategies: Strategy[] = ['BASIC', 'LOW', 'HIGH', 'SMART', 'MOON'];
const directions: Record<string, string> = { L: 'LEFT', R: 'RIGHT', A: 'ACROSS', H: 'HOLD' };
const defaults: Rules = { TARGET: 100, LIMIT: 100, MOON: 'ADD', JACK: 'OFF', QSBREAK: 'OFF', BLOOD: 'OFF', PASS: 'LRAH' };
const QS = 36, KS = 37, AS = 38, JD = 22;
const four = (): number[] => [0, 0, 0, 0];
const rows = (): number[][] => [[], [], [], []];
const suit = (c: number): number => Math.floor(c / 13);
const penalty = (c: number): boolean => c === QS || suit(c) === 3;
const cardText = (c: number): string => ranks[c % 13] + suits[suit(c)];
const display = (cs: number[]): string => cs.slice().sort((a, b) => a - b).map(cardText).join(' ') || '-';
const lowOrder = (a: number, b: number): number => a % 13 - b % 13 || suit(a) - suit(b);
const highOrder = (a: number, b: number): number => b % 13 - a % 13 || suit(a) - suit(b);
const low = (cs: number[]): number => cs.slice().sort(lowOrder)[0];
const high = (cs: number[]): number => cs.slice().sort(highOrder)[0];
const sum = (ns: number[]): number => ns.reduce((a, b) => a + b, 0);
const pairs = (label: string, values: (string | number)[]): string => label + ' ' + values.map((v, i) => `${seats[i]} ${v}`).join(' ');
class CommandError extends Error {}
function fail(reason: string): never { throw new CommandError(reason); }
function seatValue(w: string): number {
    if (w.length !== 1 || !seats.includes(w)) fail(`bad seat ${w}`);
    return seats.indexOf(w);
}
function cardValue(w: string): number {
    if (w.length !== 2 || !ranks.includes(w[0]) || !suits.includes(w[1])) fail(`bad card ${w}`);
    return suits.indexOf(w[1]) * 13 + ranks.indexOf(w[0]);
}
function bounded(w: string, a: number, b: number): number {
    const v = Number(w);
    if (!Number.isInteger(v) || v < a || v > b) fail(`bad value ${w}`);
    return v;
}
function duplicate(cs: number[]): void {
    const seen = new Set<number>();
    for (const c of cs) {
        if (seen.has(c)) fail(`duplicate card ${cardText(c)}`);
        seen.add(c);
    }
}
class Generator {
    constructor(public state: number) {}
    draw(): number { this.state = this.state * 48271 % 2147483647; return this.state; }
    shuffle(deck: number[]): void {
        for (let i = deck.length - 1; i > 0; i--) {
            const j = this.draw() % (i + 1);
            [deck[i], deck[j]] = [deck[j], deck[i]];
        }
    }
}
class Game {
    state = 'between';
    number = 0;
    scores = four();
    stats = [four(), four(), four(), four()];
    stacked = new Map<number, number[]>();
    history: FinishedHand[] = [];
    log: LogLine[] = [];
    record: string[] = [];
    hands = rows();
    taken = rows();
    passes = new Map<number, number[]>();
    tricks: Play[][] = [];
    counts = four();
    current: Play[] = [];
    leader = 0;
    broken = false;
    undo: Undo[] = [];
    passCode = 'L';
    constructor(public rules: Rules, public bots: Strategy[], public generator: Generator) {}
    point(c: number): number { return c === QS ? 13 : suit(c) === 3 ? 1 : c === JD && this.rules.JACK === 'ON' ? -10 : 0; }
    write(level: number, text: string): void {
        this.log.push({ level, text });
        if (level > 0) this.record.push(text);
    }
    snapshot(): Position {
        return { hands: this.hands.map(a => a.slice()), taken: this.taken.map(a => a.slice()),
            tricks: this.tricks.map(t => t.map(([s, c]) => [s, c] as Play)), counts: this.counts.slice(),
            current: this.current.map(([s, c]) => [s, c] as Play), leader: this.leader,
            broken: this.broken, record: this.record.slice() };
    }
    restore(p: Position): void {
        this.hands = p.hands; this.taken = p.taken; this.tricks = p.tricks; this.counts = p.counts;
        this.current = p.current; this.leader = p.leader; this.broken = p.broken; this.record = p.record;
    }
    deal(): void {
        this.number++;
        this.passCode = this.rules.PASS[(this.number - 1) % this.rules.PASS.length];
        this.hands = [0, 1, 2, 3].map(s => (this.stacked.get(s) ?? []).slice());
        const used = new Set(this.hands.flat());
        const deck = Array.from({ length: 52 }, (_, c) => c).filter(c => !used.has(c));
        this.generator.shuffle(deck);
        const free = [0, 1, 2, 3].filter(s => !this.stacked.has(s));
        deck.forEach((c, i) => this.hands[free[i % free.length]].push(c));
        this.stacked.clear();
        this.passes.clear();
        this.taken = rows(); this.tricks = []; this.counts = four(); this.current = [];
        this.broken = false; this.undo = []; this.record = [];
        this.write(1, `hand ${this.number} pass ${directions[this.passCode]}`);
        for (let s = 0; s < 4; s++) this.write(2, `${seats[s]}: ${display(this.hands[s])}`);
        if (this.passCode === 'H') this.beginPlay();
        else this.state = 'passing';
    }
    beginPlay(): void {
        this.state = 'playing'; this.leader = this.hands.findIndex(h => h.includes(0));
        this.write(2, `lead ${seats[this.leader]}`);
    }
    passCards(s: number, cs: number[]): void {
        this.hands[s] = this.hands[s].filter(c => !cs.includes(c));
        this.passes.set(s, cs.slice());
        this.write(2, `${seats[s]} passes ${display(cs)}`);
        if (this.passes.size === 4) {
            const offset = this.passCode === 'L' ? 1 : this.passCode === 'R' ? 3 : 2;
            for (const [source, cards] of this.passes) this.hands[(source + offset) % 4] = this.hands[(source + offset) % 4].concat(cards);
            this.beginPlay();
        }
    }
    actor(): number { return (this.leader + this.current.length) % 4; }
    legal(): number[] {
        const hand = this.hands[this.actor()];
        if (!this.current.length) {
            if (!this.tricks.length) return [0];
            const safe = hand.filter(c => suit(c) !== 3);
            return !this.broken && safe.length ? safe : hand.slice();
        }
        const led = suit(this.current[0][1]);
        const follow = hand.filter(c => suit(c) === led);
        if (follow.length) return follow;
        if (!this.tricks.length && this.rules.BLOOD === 'OFF') {
            const safe = hand.filter(c => !penalty(c));
            if (safe.length) return safe;
        }
        return hand.slice();
    }
    choosePass(s: number): number[] {
        const hand = this.hands[s], strategy = this.bots[s];
        const ascending = hand.slice().sort(lowOrder), descending = hand.slice().sort(highOrder);
        const hearts = descending.filter(c => suit(c) === 3);
        const special = [QS, KS, AS].filter(c => hand.includes(c));
        let order: number[];
        if (strategy === 'LOW') order = descending;
        else if (strategy === 'HIGH') order = ascending;
        else if (strategy === 'MOON') order = ascending.filter(c => suit(c) !== 3).concat(ascending.filter(c => suit(c) === 3));
        else if (strategy === 'SMART') {
            const protectedQueen = hand.includes(QS) && hand.filter(c => suit(c) === 2).length >= 5;
            order = protectedQueen ? [] : special;
            const choices = [0, 1].filter(su => hand.some(c => suit(c) === su));
            choices.sort((a, b) => hand.filter(c => suit(c) === a).length - hand.filter(c => suit(c) === b).length || a - b);
            if (choices.length) order = order.concat(descending.filter(c => suit(c) === choices[0]));
            order = order.concat(hearts, descending);
        } else order = special.concat(hearts, descending);
        return Array.from(new Set(order)).slice(0, 3);
    }
    queenPlayed(): boolean { return this.taken.some(cs => cs.includes(QS)) || this.current.some(p => p[1] === QS); }
    choosePlay(): number {
        const seat = this.actor(), hand = this.hands[seat], legal = this.legal();
        let strategy = this.bots[seat];
        if (strategy === 'LOW') return low(legal);
        if (strategy === 'HIGH') return high(legal);
        if (strategy === 'MOON' && this.taken.some((cs, s) => s !== seat && cs.some(penalty))) strategy = 'BASIC';
        if (!this.current.length) {
            if (strategy === 'SMART' && !this.queenPlayed() && !hand.includes(QS)) {
                const spades = legal.filter(c => suit(c) === 2 && c % 13 < 10);
                if (spades.length) return low(spades);
            }
            const choices = [0, 1, 2, 3].filter(s => legal.some(c => suit(c) === s));
            choices.sort((a, b) => (strategy === 'MOON' ? -1 : 1) *
                (legal.filter(c => suit(c) === a).length - legal.filter(c => suit(c) === b).length) || a - b);
            const cs = legal.filter(c => suit(c) === choices[0]);
            return strategy === 'MOON' ? high(cs) : low(cs);
        }
        const led = suit(this.current[0][1]);
        if (hand.some(c => suit(c) === led)) {
            const winning = high(this.current.filter(p => suit(p[1]) === led).map(p => p[1])) % 13;
            const lower = legal.filter(c => c % 13 < winning);
            if (strategy === 'MOON') return high(legal) % 13 > winning ? high(legal) : low(legal);
            if (lower.length) return high(lower);
            if (strategy === 'SMART' && this.current.length === 3) {
                const safe = legal.filter(c => c !== QS);
                return safe.length ? high(safe) : QS;
            }
            return low(legal);
        }
        if (strategy === 'MOON') {
            const safe = legal.filter(c => !penalty(c));
            return low(safe.length ? safe : legal);
        }
        if (legal.includes(QS)) return QS;
        if (strategy === 'SMART' && !this.queenPlayed()) {
            if (legal.includes(AS)) return AS;
            if (legal.includes(KS)) return KS;
        }
        const hearts = legal.filter(c => suit(c) === 3);
        return high(hearts.length ? hearts : legal);
    }
    winner(plays: Play[]): number {
        const led = suit(plays[0][1]);
        return plays.filter(p => suit(p[1]) === led).sort((a, b) => b[1] % 13 - a[1] % 13)[0][0];
    }
    trickLine(plays: Play[], n: number): string {
        return `trick ${n}: ${plays.map(([s, c]) => `${seats[s]} ${cardText(c)}`).join(' ')} -> ${seats[this.winner(plays)]} ${sum(plays.map(p => this.point(p[1])))}`;
    }
    play(c: number): void {
        const seat = this.actor();
        this.undo.push({ position: this.snapshot(), logLength: this.log.length, seat, card: c });
        this.hands[seat] = this.hands[seat].filter(v => v !== c);
        this.current.push([seat, c]);
        if (suit(c) === 3 || c === QS && this.rules.QSBREAK === 'ON') this.broken = true;
        if (this.current.length === 4) {
            const winner = this.winner(this.current);
            this.taken[winner] = this.taken[winner].concat(this.current.map(p => p[1]));
            this.counts[winner]++;
            this.tricks.push(this.current);
            this.write(2, this.trickLine(this.current, this.tricks.length));
            this.current = []; this.leader = winner;
            if (this.tricks.length === 13) this.finish();
        }
    }
    undoCard(): Play {
        const u = this.undo.pop()!;
        this.restore(u.position); this.log.length = u.logLength;
        return [u.seat, u.card];
    }
    claim(s: number): void {
        const remaining = this.hands.flat(), n = 13 - this.tricks.length;
        this.taken[s] = this.taken[s].concat(remaining); this.counts[s] += n;
        this.hands = rows();
        this.write(2, `claim ${seats[s]} tricks ${n} points ${sum(remaining.map(c => this.point(c)))}`);
        this.finish();
    }
    finish(): void {
        let points = this.taken.map(cs => sum(cs.map(c => this.point(c))));
        const shooter = this.taken.findIndex(cs => cs.filter(penalty).length === 14);
        if (shooter >= 0) {
            points[shooter] -= 26;
            let method = this.rules.MOON;
            if (method === 'AUTO') {
                const add = points.map((p, s) => this.scores[s] + p + (s === shooter ? 0 : 26));
                const ended = this.number >= this.rules.LIMIT || add.some(p => p >= this.rules.TARGET);
                const winner = [0, 1, 2, 3].sort((a, b) => add[a] - add[b] || a - b)[0];
                method = ended && winner !== shooter ? 'SUB' : 'ADD';
            }
            if (method === 'SUB') points[shooter] -= 26;
            else points = points.map((p, s) => p + (s === shooter ? 0 : 26));
            this.write(1, `moon ${seats[shooter]} ${method}`);
        }
        for (let s = 0; s < 4; s++) {
            this.scores[s] += points[s];
            this.stats[s][0] += this.counts[s];
            this.stats[s][1] += this.taken[s].filter(c => suit(c) === 3).length;
            this.stats[s][2] += Number(this.taken[s].includes(QS));
            this.stats[s][3] += Number(s === shooter);
        }
        this.write(1, pairs('points', points)); this.write(1, pairs('scores', this.scores));
        this.history.push({ number: this.number, direction: directions[this.passCode], points, shooter, record: this.record.slice() });
        const ended = this.number >= this.rules.LIMIT || this.scores.some(p => p >= this.rules.TARGET);
        this.state = ended ? 'none' : 'between';
        if (ended) {
            this.write(0, `game over hands ${this.number}`);
            this.ranking().forEach((s, i) => this.write(0, `rank ${i + 1} ${seats[s]} ${this.scores[s]}`));
            for (const line of this.statsLines()) this.write(0, line);
        }
    }
    ranking(): number[] { return [0, 1, 2, 3].sort((a, b) => this.scores[a] - this.scores[b] || a - b); }
    statsLines(): string[] {
        return this.stats.map((s, i) => `stats ${seats[i]} tricks ${s[0]} hearts ${s[1]} queens ${s[2]} moons ${s[3]}`);
    }
    autoPass(): void {
        for (let s = 0; s < 4; s++) if (!this.passes.has(s)) this.passCards(s, this.choosePass(s));
    }
    autoHand(): void {
        if (this.state === 'passing') this.autoPass();
        while (this.state === 'playing') this.play(this.choosePlay());
    }
    autoGame(): void {
        if (this.state === 'passing' || this.state === 'playing') this.autoHand();
        while (this.state !== 'none') { this.deal(); this.autoHand(); }
    }
    preview(c: number): Play {
        const copy = new Game(this.rules, this.bots, new Generator(this.generator.state));
        copy.restore(this.snapshot());
        copy.state = 'playing'; copy.number = this.number; copy.passCode = this.passCode;
        copy.scores = this.scores.slice(); copy.stats = this.stats.map(s => s.slice());
        const count = copy.tricks.length;
        copy.play(c);
        while (copy.state === 'playing' && copy.tricks.length === count) copy.play(copy.choosePlay());
        const trick = copy.tricks[copy.tricks.length - 1];
        return [copy.winner(trick), sum(trick.map(p => copy.point(p[1])))];
    }
}
class Table {
    rules: Rules = { ...defaults };
    bots: Strategy[] = ['BASIC', 'BASIC', 'BASIC', 'BASIC'];
    game: Game | null = null;
    active(): boolean { return this.game !== null && this.game.state !== 'none'; }
    require(kind: string): void {
        const state = this.active() ? this.game!.state : 'none';
        if (kind === 'game' && state === 'none') fail('no game');
        if (kind === 'hand' && !['passing', 'playing'].includes(state)) fail('no hand');
        if (kind === 'playing' && state !== 'playing') fail('not playing');
        if (kind === 'passing' && state !== 'passing') fail('not passing');
        if (kind === 'between') {
            if (state === 'none') fail('no game');
            if (state !== 'between') fail('hand in progress');
        }
    }
    simulate(command: string, seed: number, count: number): string[] {
        const generator = new Generator(seed);
        if (command === 'GAME') {
            const game = new Game(this.rules, this.bots, generator); game.autoGame();
            return [`game seed ${seed}`].concat(game.log.filter(l => l.level <= count).map(l => l.text));
        }
        const rounds = command === 'ROTATE' ? 4 : 1, games = rounds * count;
        const places = [four(), four(), four(), four()], totals = four(), stats = [four(), four(), four(), four()];
        let hands = 0;
        for (let r = 0; r < rounds; r++) {
            const bots = this.bots.slice();
            for (let i = 0; i < 4; i++) bots[(i + r) % 4] = this.bots[i];
            for (let g = 0; g < count; g++) {
                const game = new Game(this.rules, bots, generator); game.autoGame(); hands += game.number;
                const ranking = game.ranking();
                for (let i = 0; i < 4; i++) {
                    const actual = (i + r) % 4;
                    places[i][ranking.indexOf(actual)]++; totals[i] += game.scores[actual];
                    for (let k = 0; k < 4; k++) stats[i][k] += game.stats[actual][k];
                }
            }
        }
        const out = [`${command.toLowerCase()} seed ${seed} games ${games} hands ${hands}`];
        for (let i = 0; i < 4; i++) {
            const cents = Math.floor(100 * totals[i] / games), abs = Math.abs(cents);
            const average = `${cents < 0 ? '-' : ''}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
            const name = seats[i] + (command === 'ROTATE' ? ` ${this.bots[i]}` : '');
            const s = stats[i];
            out.push(`${name} places ${places[i].join(' ')} total ${totals[i]} average ${average} tricks ${s[0]} hearts ${s[1]} queens ${s[2]} moons ${s[3]}`);
        }
        return out;
    }
    command(words: string[]): string[] {
        const [cmd, ...args] = words;
        const known = 'RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY'.split(' ');
        if (!known.includes(cmd)) fail(`unknown command ${cmd}`);
        if (cmd === 'RULE') {
            const [name, word] = args;
            if (!Object.hasOwn(defaults, name)) fail(`unknown rule ${name}`);
            let value: string | number = word;
            if (name === 'TARGET' || name === 'LIMIT') value = bounded(word, 1, name === 'TARGET' ? 1000 : 100);
            else {
                const valid = name === 'PASS' ? /^[LRAH]{1,8}$/.test(word) : (name === 'MOON' ? ['ADD', 'SUB', 'AUTO'] : ['ON', 'OFF']).includes(word);
                if (!valid) fail(`bad value ${word}`);
            }
            if (this.active()) fail('game in progress');
            if (name === 'TARGET') this.rules.TARGET = value as number;
            else if (name === 'LIMIT') this.rules.LIMIT = value as number;
            else this.rules[name as 'MOON' | 'JACK' | 'QSBREAK' | 'BLOOD' | 'PASS'] = value as string;
            return [`rule ${name} ${word}`];
        }
        if (cmd === 'BOT') {
            const s = seatValue(args[0]);
            if (!strategies.includes(args[1] as Strategy)) fail(`bad value ${args[1]}`);
            this.bots[s] = args[1] as Strategy;
            return [`bot ${seats[s]} ${args[1]}`];
        }
        if (cmd === 'SETTINGS') return ['rules ' + Object.entries(this.rules).map(([k, v]) => `${k} ${v}`).join(' '), pairs('bots', this.bots)];
        if (['GAME', 'MATCH', 'ROTATE'].includes(cmd)) {
            const seed = bounded(args[0], 1, 2147483646), count = bounded(args[1], cmd === 'GAME' ? 0 : 1, cmd === 'GAME' ? 2 : cmd === 'MATCH' ? 50 : 10);
            return this.simulate(cmd, seed, count);
        }
        if (cmd === 'NEW') {
            const seed = bounded(args[0], 1, 2147483646);
            if (this.active()) fail('game in progress');
            this.game = new Game(this.rules, this.bots, new Generator(seed)); return [`new game seed ${seed}`];
        }
        if (cmd === 'ABANDON') { this.require('game'); this.game = null; return ['game abandoned']; }
        let s = -1, cards: number[] = [];
        if (['STACK', 'PASS', 'PLAY', 'CLAIM'].includes(cmd)) s = seatValue(args[0]);
        if (['STACK', 'PASS', 'PLAY'].includes(cmd)) cards = args.slice(1).map(cardValue);
        if (cmd === 'STACK' && cards.length !== 13) fail('need 13 cards');
        if (cmd === 'AUTO' && !['PASS', 'CARD', 'TRICK', 'HAND', 'GAME'].includes(args[0])) fail(`bad value ${args[0]}`);
        if (['STACK', 'DEAL'].includes(cmd)) this.require('between');
        else if (cmd === 'SHOW') this.require('hand');
        else if (cmd === 'PASS') this.require('passing');
        else if (['PLAY', 'UNDO', 'CLAIM', 'LEGAL', 'PREVIEW', 'TAKEN', 'TRICKS', 'VOIDS', 'UNSEEN'].includes(cmd)) this.require('playing');
        else if (['SCORE', 'STATS', 'HISTORY', 'REPLAY'].includes(cmd)) this.require('game');
        else if (cmd === 'AUTO') this.require(args[0] === 'PASS' ? 'passing' : ['CARD', 'TRICK'].includes(args[0]) ? 'playing' : args[0] === 'HAND' ? 'hand' : 'game');
        const game = this.game!, before = game.log.length, prefix: string[] = [];
        switch (cmd) {
            case 'STACK':
                duplicate(cards);
                for (const c of cards) {
                    for (let o = 0; o < 4; o++) {
                        if (o !== s && (game.stacked.get(o) ?? []).includes(c)) {
                            fail(`${cardText(c)} stacked for ${seats[o]}`);
                        }
                    }
                }
                game.stacked.set(s, cards.slice()); return [`stacked ${seats[s]}`];
            case 'DEAL': game.deal(); break;
            case 'SHOW': return game.hands.map((cs, i) => `${seats[i]}: ${display(cs)}`);
            case 'PASS':
                if (game.passes.has(s)) fail(`${seats[s]} already passed`);
                duplicate(cards);
                for (const c of cards) if (!game.hands[s].includes(c)) fail(`${seats[s]} does not hold ${cardText(c)}`);
                game.passCards(s, cards); break;
            case 'PLAY': {
                const c = cards[0];
                if (s !== game.actor()) fail(`waiting for ${seats[game.actor()]}`);
                if (!game.hands[s].includes(c)) fail(`${seats[s]} does not hold ${cardText(c)}`);
                if (!game.legal().includes(c)) {
                    if (!game.current.length) fail(!game.tricks.length ? 'must lead 2C' : 'hearts not broken');
                    const led = suit(game.current[0][1]);
                    if (game.hands[s].some(c => suit(c) === led)) fail(`must follow ${suits[led]}`);
                    fail('no points on first trick');
                }
                prefix.push(`${seats[s]} plays ${cardText(c)}`); game.play(c); break;
            }
            case 'AUTO':
                if (args[0] === 'PASS') game.autoPass();
                else if (args[0] === 'CARD') {
                    const seat = game.actor(), c = game.choosePlay();
                    prefix.push(`${seats[seat]} plays ${cardText(c)}`); game.play(c);
                } else if (args[0] === 'TRICK') {
                    const count = game.tricks.length;
                    while (game.state === 'playing' && game.tricks.length === count) game.play(game.choosePlay());
                } else if (args[0] === 'HAND') game.autoHand();
                else game.autoGame();
                break;
            case 'UNDO': {
                if (!game.undo.length) fail('nothing to undo');
                const [seat, c] = game.undoCard(); return [`undo ${seats[seat]} ${cardText(c)}`];
            }
            case 'CLAIM':
                if (s !== game.actor()) fail(`waiting for ${seats[game.actor()]}`);
                if (game.current.length) fail('trick in progress');
                for (const c of game.hands[s]) {
                    if (game.hands.some((cs, o) => o !== s && cs.some(v => suit(v) === suit(c) && v % 13 > c % 13))) {
                        fail('claim rejected');
                    }
                }
                game.claim(s); break;
            case 'LEGAL': return [`legal ${seats[game.actor()]}: ${display(game.legal())} bot ${cardText(game.choosePlay())}`];
            case 'PREVIEW':
                return game.legal().sort((a, b) => a - b).map(c => {
                    const [w, p] = game.preview(c);
                    return `preview ${cardText(c)} -> ${seats[w]} ${p}`;
                });
            case 'SCORE': return [pairs('scores', game.scores)].concat(game.state === 'playing' ? [pairs('taken', game.taken.map(cs => sum(cs.map(c => game.point(c)))))] : []);
            case 'TAKEN': return game.taken.map((cs, i) => `${seats[i]}: ${display(cs.filter(c => game.point(c) !== 0))}`);
            case 'TRICKS': {
                const out = game.tricks.map((t, i) => game.trickLine(t, i + 1));
                if (game.current.length) out.push('current: ' + game.current.map(([s, c]) => `${seats[s]} ${cardText(c)}`).join(' '));
                return out.length ? out : ['no tricks'];
            }
            case 'VOIDS': {
                const missing = [new Set<number>(), new Set<number>(), new Set<number>(), new Set<number>()];
                for (const trick of game.tricks.concat(game.current.length ? [game.current] : [])) {
                    const led = suit(trick[0][1]);
                    for (const [s, c] of trick) if (suit(c) !== led) missing[s].add(led);
                }
                return [pairs('voids', missing.map(ms => Array.from(ms).sort().map(s => suits[s]).join('') || '-'))];
            }
            case 'UNSEEN': {
                const actor = game.actor(), seen = new Set(game.taken.flat().concat(game.current.map(p => p[1]), game.hands[actor]));
                return [`unseen ${seats[actor]}: ${display(Array.from({ length: 52 }, (_, c) => c).filter(c => !seen.has(c)))}`];
            }
            case 'STATS': return game.statsLines();
            case 'HISTORY': return game.history.length ? game.history.map(h => `hand ${h.number} pass ${h.direction} ${pairs('points', h.points)}${h.shooter >= 0 ? ` moon ${seats[h.shooter]}` : ''}`) : ['no hands'];
            case 'REPLAY': {
                const n = Number(args[0]);
                if (n < 1 || n > game.history.length) fail(`bad value ${args[0]}`);
                return game.history[n - 1].record.slice();
            }
        }
        return prefix.concat(game.log.slice(before).map(l => l.text));
    }
}
const lines = readFileSync(0, 'utf8').split(/\r?\n/), table = new Table();
for (const line of lines.slice(1, Number(lines[0]) + 1)) {
    try { for (const result of table.command(line.split(' '))) writeFileSync(1, result + '\n'); }
    catch (e) { if (e instanceof CommandError) writeFileSync(1, `error: ${e.message}\n`); else throw e; }
}
