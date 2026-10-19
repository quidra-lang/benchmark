import { readFileSync } from 'node:fs';

type Action = 'HIT' | 'STAND' | 'DOUBLE' | 'SPLIT' | 'SURRENDER';
type Finish = 'pending' | 'ordinary' | 'bust' | 'surrender' | 'charlie';
type Outcome = 'blackjack' | 'win' | 'charlie' | 'push' | 'lose' | 'bust' | 'surrender';
type CharlieRule = 0 | 5 | 6 | 7;
interface Rules {
    DEALER: 'S17' | 'H17';
    PEN: number;
    MIN: number;
    MAX: number;
    BJ: '3:2' | '6:5';
    DAS: boolean;
    DOUBLE: 'ANY' | '9-11' | '10-11';
    HANDS: number;
    RSA: boolean;
    SURRENDER: boolean;
    CHARLIE: CharlieRule;
    SIDEMAX: number;
}
type RuleName = keyof Rules;
const RULE_NAMES = ['DEALER', 'PEN', 'MIN', 'MAX', 'BJ', 'DAS', 'DOUBLE', 'HANDS', 'RSA', 'SURRENDER', 'CHARLIE', 'SIDEMAX'] as const satisfies readonly RuleName[];
const STAT_NAMES = ['rounds', 'hands', 'wins', 'losses', 'pushes', 'blackjacks', 'busts', 'surrenders', 'doubles', 'splits'] as const;
const IDLE_COMMANDS = new Set(['SHOE', 'RULE', 'PLAYER', 'LEAVE', 'REBUY', 'BET', 'SIDE', 'DEAL']);
const output: string[] = [];
const emit = (...fields: (string | number)[]): void => { output.push(fields.join(' ')); };
const signed = (value: number): string => value >= 0 ? `+${value}` : String(value);

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
function integerWord(word: string, low: number, high: number): number {
    if (!/^(0|[1-9][0-9]{0,9})$/.test(word)) fail(`bad value ${word}`);
    const value = Number(word);
    if (value < low || value > high) fail(`bad value ${word}`);
    return value;
}
function choice<T extends string>(word: string, choices: readonly T[]): T {
    if (!(choices as readonly string[]).includes(word)) fail(`bad value ${word}`);
    return word as T;
}
function isRuleName(word: string): word is RuleName {
    return (RULE_NAMES as readonly string[]).includes(word);
}
function newRules(): Rules {
    return { DEALER: 'S17', PEN: 75, MIN: 10, MAX: 500, BJ: '3:2', DAS: true,
        DOUBLE: 'ANY', HANDS: 4, RSA: false, SURRENDER: true, CHARLIE: 0, SIDEMAX: 25 };
}
function changeRule(original: Rules, name: RuleName, word: string): Rules {
    const next = { ...original };
    switch (name) {
        case 'DEALER': next.DEALER = choice(word, ['S17', 'H17']); break;
        case 'PEN': next.PEN = integerWord(word, 50, 90); break;
        case 'MIN': next.MIN = integerWord(word, 1, 10000); break;
        case 'MAX': next.MAX = integerWord(word, 1, 10000); break;
        case 'BJ': next.BJ = choice(word, ['3:2', '6:5']); break;
        case 'DAS': next.DAS = choice(word, ['ON', 'OFF']) === 'ON'; break;
        case 'DOUBLE': next.DOUBLE = choice(word, ['ANY', '9-11', '10-11']); break;
        case 'HANDS': next.HANDS = integerWord(word, 1, 4); break;
        case 'RSA': next.RSA = choice(word, ['ON', 'OFF']) === 'ON'; break;
        case 'SURRENDER': next.SURRENDER = choice(word, ['ON', 'OFF']) === 'ON'; break;
        case 'CHARLIE': {
            const value = integerWord(word, 0, 7);
            if (value !== 0 && value !== 5 && value !== 6 && value !== 7) fail(`bad value ${word}`);
            next.CHARLIE = value;
            break;
        }
        case 'SIDEMAX': next.SIDEMAX = integerWord(word, 0, 1000); break;
    }
    return next;
}
function ruleText(value: Rules[RuleName]): string {
    return typeof value === 'boolean' ? value ? 'ON' : 'OFF' : String(value);
}

const point = (card: number): number => Math.min(card % 13 + 1, 10);
const cardText = (card: number): string => 'A23456789TJQK'[card % 13] + 'CDHS'[Math.floor(card / 13)];
interface Total { readonly value: number; readonly soft: boolean }
class Hand {
    finish: Finish = 'pending';
    constructor(
        readonly cards: number[],
        public bet: number,
        readonly split = false,
        readonly splitAces = false,
    ) {}
    total(): Total {
        const raw = this.cards.reduce((sum, card) => sum + point(card), 0);
        const soft = this.cards.some(card => card % 13 === 0) && raw + 10 <= 21;
        return { value: raw + (soft ? 10 : 0), soft };
    }
    blackjack(): boolean { return !this.split && this.cards.length === 2 && this.total().value === 21; }
    text(): string {
        const total = this.total();
        const status = this.blackjack() ? 'blackjack' : total.value > 21 ? `bust ${total.value}`
            : total.soft ? `soft ${total.value}` : String(total.value);
        return `${this.cards.map(cardText).join(' ')} (${status})`;
    }
    finishCheck(rules: Rules, handCount: number): void {
        const total = this.total().value;
        if (total > 21) this.finish = 'bust';
        else if (rules.CHARLIE !== 0 && this.cards.length === rules.CHARLIE) this.finish = 'charlie';
        else if (total === 21) this.finish = 'ordinary';
        else if (this.splitAces && this.cards.length === 2) {
            const again = this.cards.every(card => card % 13 === 0) && rules.RSA && handCount < rules.HANDS;
            this.finish = again ? 'pending' : 'ordinary';
        }
    }
    outcome(dealer: number, dealerBlackjack: boolean): Outcome {
        if (dealerBlackjack) return this.blackjack() ? 'push' : 'lose';
        if (this.blackjack()) return 'blackjack';
        if (this.finish === 'bust' || this.finish === 'surrender' || this.finish === 'charlie') return this.finish;
        return dealer > 21 || this.total().value > dealer ? 'win' : this.total().value === dealer ? 'push' : 'lose';
    }
}
class Statistics {
    rounds = 0;
    hands = 0;
    wins = 0;
    losses = 0;
    pushes = 0;
    blackjacks = 0;
    busts = 0;
    surrenders = 0;
    doubles = 0;
    splits = 0;
    record(result: Outcome): void {
        this.hands++;
        if (result === 'blackjack' || result === 'win' || result === 'charlie') this.wins++;
        else if (result === 'push') this.pushes++;
        else this.losses++;
        if (result === 'blackjack') this.blackjacks++;
        if (result === 'bust') this.busts++;
        if (result === 'surrender') this.surrenders++;
    }
    text(): string { return STAT_NAMES.map(name => `${name} ${this[name]}`).join(' '); }
}
class Player {
    bet = 0;
    side = 0;
    insurance = 0;
    net = 0;
    hands: Hand[] = [];
    readonly stats = new Statistics();
    constructor(readonly name: string, readonly seat: number, public bankroll: number) {}
    handName(index: number): string { return `${this.name}[${index + 1}]`; }
}
class Shoe {
    cards: number[] = [];
    drawn = 0;
    running = 0;
    constructor(readonly decks: number, private randomState: bigint) { this.shuffle(); }
    shuffle(): void {
        this.cards = Array.from({ length: 52 * this.decks }, (_, index) => index % 52);
        for (let index = this.cards.length - 1; index >= 1; index--) {
            this.randomState = this.randomState * 48271n % 2147483647n;
            const other = Number(this.randomState % BigInt(index + 1));
            [this.cards[index], this.cards[other]] = [this.cards[other], this.cards[index]];
        }
        this.drawn = this.running = 0;
    }
    cut(penetration: number): number { return Math.floor(this.cards.length * penetration / 100); }
    static hilo(card: number): number {
        const value = point(card);
        return value >= 2 && value <= 6 ? 1 : value === 1 || value === 10 ? -1 : 0;
    }
    draw(visible: boolean): number {
        const card = this.cards[this.drawn++];
        if (visible) this.running += Shoe.hilo(card);
        return card;
    }
}
interface Turn { readonly player: Player; readonly index: number; readonly hand: Hand }
type TableState = { kind: 'idle' } | { kind: 'insurance'; next: number } | { kind: 'play'; turn: Turn };
type Command =
    | { kind: 'SHOE'; decks: number; seed: bigint }
    | { kind: 'RULE'; name: RuleName; rules: Rules }
    | { kind: 'PLAYER'; name: string; bankroll: number }
    | { kind: 'LEAVE'; player: Player }
    | { kind: 'REBUY' | 'BET' | 'SIDE' | 'INSURANCE'; player: Player; amount: number }
    | { kind: 'action'; action: Action; player: Player }
    | { kind: 'AUTO'; player: Player }
    | { kind: 'RULES' | 'DEAL' | 'HINT' | 'STATUS' | 'COUNT' | 'STATS' };

class Table {
    private rules = newRules();
    private readonly seats: (Player | null)[] = Array(7).fill(null);
    private participants: Player[] = [];
    private shoe: Shoe | null = null;
    private state: TableState = { kind: 'idle' };
    private round = 0;
    private dealer = new Hand([], 0);
    private holeVisible = false;
    private dealerBlackjacks = 0;
    private dealerBusts = 0;

    private seated(): Player[] { return this.seats.filter((player): player is Player => player !== null); }
    private find(name: string): Player | undefined { return this.seated().find(player => player.name === name); }
    private lookup(name: string): Player { return this.find(name) ?? fail(`unknown player ${name}`); }
    private requireShoe(): Shoe { return this.shoe ?? fail('no shoe'); }
    private requireTurn(): Turn {
        if (this.state.kind === 'idle') fail('no round');
        if (this.state.kind === 'insurance') fail('insurance pending');
        return this.state.turn;
    }
    private handLine(turn: Turn, verb = ''): void {
        emit(`${turn.player.handName(turn.index)}${verb}: ${turn.hand.text()}`);
    }
    private revealDealer(): void {
        if (!this.holeVisible) {
            this.requireShoe().running += Shoe.hilo(this.dealer.cards[1]);
            this.holeVisible = true;
        }
        emit(`dealer: ${this.dealer.text()}`);
    }
    private profit(bet: number, result: Outcome): number {
        switch (result) {
            case 'blackjack': return this.rules.BJ === '3:2' ? Math.floor(bet * 3 / 2) : Math.floor(bet * 6 / 5);
            case 'win': case 'charlie': return bet;
            case 'push': return 0;
            case 'surrender': return Math.floor(bet / 2) - bet;
            case 'lose': case 'bust': return -bet;
        }
    }
    private settle(dealerBlackjack: boolean): void {
        const dealer = this.dealer.total().value;
        for (const player of this.participants) {
            player.hands.forEach((hand, index) => {
                const result = hand.outcome(dealer, dealerBlackjack);
                const profit = this.profit(hand.bet, result);
                player.bankroll += hand.bet + profit;
                player.net += profit;
                player.stats.record(result);
                emit(player.handName(index), result, signed(profit));
            });
            emit(player.name, 'bankroll', player.bankroll);
        }
        for (const player of this.seated()) player.bet = player.side = 0;
        this.state = { kind: 'idle' };
    }
    private dealerTurn(): void {
        this.revealDealer();
        const required = this.participants.some(player => player.hands.some(hand => hand.finish === 'ordinary' && !hand.blackjack()));
        let drew = false;
        if (required) for (;;) {
            const total = this.dealer.total();
            if (!(total.value < 17 || total.value === 17 && total.soft && this.rules.DEALER === 'H17')) break;
            this.dealer.cards.push(this.requireShoe().draw(true));
            emit(`dealer hits: ${this.dealer.text()}`);
            drew = true;
        }
        if (drew && this.dealer.total().value > 21) this.dealerBusts++;
        this.settle(false);
    }
    private firstUnfinished(): Turn | null {
        for (const player of this.participants) {
            const index = player.hands.findIndex(hand => hand.finish === 'pending');
            if (index >= 0) return { player, index, hand: player.hands[index] };
        }
        return null;
    }
    private advance(): void {
        for (;;) {
            const turn = this.firstUnfinished();
            if (turn === null) { this.dealerTurn(); return; }
            if (turn.hand.cards.length === 1) {
                turn.hand.cards.push(this.requireShoe().draw(true));
                this.handLine(turn);
                turn.hand.finishCheck(this.rules, turn.player.hands.length);
                if (turn.hand.finish !== 'pending') continue;
            }
            this.state = { kind: 'play', turn };
            return;
        }
    }
    private peek(): void {
        const natural = this.dealer.blackjack();
        emit('dealer peeks:', natural ? 'blackjack' : 'no blackjack');
        for (const player of this.participants) {
            if (player.insurance === 0) continue;
            const profit = natural ? player.insurance * 2 : -player.insurance;
            player.bankroll += player.insurance + profit;
            player.net += profit;
            emit(player.name, 'insurance', signed(profit));
        }
        if (natural) {
            this.dealerBlackjacks++;
            this.revealDealer();
            this.settle(true);
        } else this.advance();
    }
    private deal(): void {
        const shoe = this.requireShoe();
        if (shoe.drawn >= shoe.cut(this.rules.PEN)) { shoe.shuffle(); emit('shuffle'); }
        this.round++;
        emit('round', this.round);
        this.participants = this.seated().filter(player => player.bet !== 0);
        for (const player of this.participants) {
            player.bankroll -= player.bet + player.side;
            player.insurance = 0;
            player.stats.rounds++;
            player.hands = [new Hand([], player.bet)];
        }
        for (const player of this.participants) player.hands[0].cards.push(shoe.draw(true));
        this.dealer = new Hand([shoe.draw(true)], 0);
        for (const player of this.participants) {
            const hand = player.hands[0];
            hand.cards.push(shoe.draw(true));
            if (hand.blackjack()) hand.finish = 'ordinary';
        }
        this.dealer.cards.push(shoe.draw(false));
        this.holeVisible = false;
        for (const player of this.participants) this.handLine({ player, index: 0, hand: player.hands[0] });
        emit('dealer:', cardText(this.dealer.cards[0]), '??');
        for (const player of this.participants) {
            if (player.side === 0) continue;
            const [first, second] = player.hands[0].cards;
            const sameColor = [0, 3].includes(Math.floor(first / 13)) === [0, 3].includes(Math.floor(second / 13));
            const multiplier = first % 13 !== second % 13 ? -1 : first === second ? 25 : sameColor ? 12 : 6;
            const result = multiplier === 25 ? 'perfect' : multiplier === 12 ? 'colored' : multiplier === 6 ? 'mixed' : 'lose';
            const profit = player.side * multiplier;
            player.bankroll += player.side + profit;
            player.net += profit;
            emit(player.name, 'side', result, signed(profit));
        }
        const up = point(this.dealer.cards[0]);
        if (up === 1) { this.state = { kind: 'insurance', next: 0 }; emit('insurance offered'); }
        else if (up === 10) this.peek();
        else this.advance();
    }
    private actionProblem(turn: Turn, action: Action): string | null {
        const { player, hand } = turn;
        if (action === 'HIT') return hand.splitAces ? 'split aces' : null;
        if (action === 'DOUBLE') {
            if (hand.splitAces) return 'split aces';
            if (hand.cards.length !== 2) return 'two cards only';
            const total = hand.total();
            const low = this.rules.DOUBLE === '9-11' ? 9 : 10;
            const limited = this.rules.DOUBLE !== 'ANY' && (total.soft || total.value < low || total.value > 11);
            if (limited || !this.rules.DAS && hand.split) return 'double not allowed';
            if (player.bankroll < hand.bet) return 'insufficient funds';
        } else if (action === 'SPLIT') {
            if (hand.cards.length !== 2) return 'two cards only';
            if (point(hand.cards[0]) !== point(hand.cards[1])) return 'not a pair';
            if (player.hands.length >= this.rules.HANDS) return 'hand limit';
            if (player.bankroll < hand.bet) return 'insufficient funds';
        } else if (action === 'SURRENDER') {
            if (!this.rules.SURRENDER || hand.split) return 'surrender not allowed';
            if (hand.cards.length !== 2) return 'two cards only';
        }
        return null;
    }
    private recommend(turn: Turn): Action {
        const hand = turn.hand;
        const canSplit = this.actionProblem(turn, 'SPLIT') === null;
        if (hand.splitAces) return canSplit ? 'SPLIT' : 'STAND';
        const upcard = point(this.dealer.cards[0]);
        const up = upcard === 1 ? 11 : upcard;
        if (canSplit) {
            const pair = point(hand.cards[0]);
            const preferred = [1, 8].includes(pair) || pair === 9 && ![7, 10, 11].includes(up)
                || [2, 3, 7].includes(pair) && up <= 7 || pair === 6 && up <= 6 || pair === 4 && [5, 6].includes(up);
            if (preferred) return 'SPLIT';
        }
        const total = hand.total();
        const value = total.value;
        const canDouble = this.actionProblem(turn, 'DOUBLE') === null;
        if (total.soft) {
            if (value >= 19) return 'STAND';
            if (value === 18) {
                if (up >= 3 && up <= 6) return canDouble ? 'DOUBLE' : 'STAND';
                return [2, 7, 8].includes(up) ? 'STAND' : 'HIT';
            }
            const wantsDouble = value === 17 && up >= 3 && up <= 6 || [15, 16].includes(value) && up >= 4 && up <= 6
                || [13, 14].includes(value) && [5, 6].includes(up);
            return wantsDouble && canDouble ? 'DOUBLE' : 'HIT';
        }
        if (value >= 17) return 'STAND';
        if (value >= 13) {
            if (up <= 6) return 'STAND';
            if ((value === 16 && up >= 9 || value === 15 && up === 10) && this.actionProblem(turn, 'SURRENDER') === null) return 'SURRENDER';
            return 'HIT';
        }
        if (value === 12) return up >= 4 && up <= 6 ? 'STAND' : 'HIT';
        const wantsDouble = value === 11 && up <= 10 || value === 10 && up <= 9 || value === 9 && up >= 3 && up <= 6;
        return wantsDouble && canDouble ? 'DOUBLE' : 'HIT';
    }
    private perform(turn: Turn, action: Action): void {
        const { player, hand, index } = turn;
        if (action === 'SPLIT') {
            player.bankroll -= hand.bet;
            player.stats.splits++;
            emit(player.handName(index), 'splits', cardText(hand.cards[0]), cardText(hand.cards[1]));
            const aces = hand.splitAces || point(hand.cards[0]) === 1;
            const first = new Hand([hand.cards[0]], hand.bet, true, aces);
            const second = new Hand([hand.cards[1]], hand.bet, true, aces);
            player.hands.splice(index, 1, first, second);
            first.cards.push(this.requireShoe().draw(true));
            this.handLine({ player, index, hand: first });
            first.finishCheck(this.rules, player.hands.length);
        } else if (action === 'STAND' || action === 'SURRENDER') {
            hand.finish = action === 'STAND' ? 'ordinary' : 'surrender';
            this.handLine(turn, action === 'STAND' ? ' stands' : ' surrenders');
        } else {
            if (action === 'DOUBLE') {
                player.bankroll -= hand.bet;
                hand.bet *= 2;
                player.stats.doubles++;
            }
            hand.cards.push(this.requireShoe().draw(true));
            this.handLine(turn, action === 'DOUBLE' ? ' doubles' : ' hits');
            hand.finishCheck(this.rules, player.hands.length);
            if (action === 'DOUBLE' && hand.finish === 'pending') hand.finish = 'ordinary';
        }
        this.advance();
    }
    private status(): void {
        switch (this.state.kind) {
            case 'idle': emit('table idle round', this.round); break;
            case 'insurance': emit('table insurance round', this.round, 'next', this.participants[this.state.next].name); break;
            case 'play': emit('table play round', this.round, 'turn', this.state.turn.player.handName(this.state.turn.index)); break;
        }
        if (this.state.kind !== 'idle') emit('dealer:', cardText(this.dealer.cards[0]), '??');
        for (const player of this.seated()) {
            emit('seat', player.seat + 1, player.name, 'bankroll', player.bankroll, 'bet', player.bet, 'side', player.side);
            if (this.state.kind !== 'idle' && this.participants.includes(player)) {
                player.hands.forEach((hand, index) => emit(`${player.handName(index)}: ${hand.text()} bet ${hand.bet}`));
            }
        }
    }

    private parse(words: string[]): Command {
        const op = words[0];
        switch (op) {
            case 'SHOE': {
                const decks = integerWord(words[1], 1, 8);
                const seed = BigInt(integerWord(words[2], 1, 2147483646));
                return { kind: op, decks, seed };
            }
            case 'RULE': {
                const name = words[1];
                if (!isRuleName(name)) fail(`unknown rule ${name}`);
                return { kind: op, name, rules: changeRule(this.rules, name, words[2]) };
            }
            case 'PLAYER': {
                const name = words[1];
                if (!/^[A-Z]{1,8}$/.test(name)) fail(`bad name ${name}`);
                const bankroll = integerWord(words[2], 1, 1000000);
                return { kind: op, name, bankroll };
            }
            case 'LEAVE': case 'AUTO': return { kind: op, player: this.lookup(words[1]) };
            case 'REBUY': case 'BET': case 'SIDE': case 'INSURANCE': {
                const player = this.lookup(words[1]);
                const amount = integerWord(words[2], op === 'REBUY' ? 1 : 0, 1000000);
                return { kind: op, player, amount };
            }
            case 'HIT': case 'STAND': case 'DOUBLE': case 'SPLIT': case 'SURRENDER':
                return { kind: 'action', action: op, player: this.lookup(words[1]) };
            case 'RULES': case 'DEAL': case 'HINT': case 'STATUS': case 'COUNT': case 'STATS': return { kind: op };
            default: return fail(`unknown command ${op}`);
        }
    }
    execute(words: string[]): void {
        const command = this.parse(words);
        if (IDLE_COMMANDS.has(command.kind) && this.state.kind !== 'idle') fail('round in progress');
        if (command.kind === 'INSURANCE' && this.state.kind !== 'insurance') fail('no insurance');
        if (command.kind === 'action' || command.kind === 'AUTO') {
            const turn = this.requireTurn();
            if (turn.player !== command.player) fail(`waiting for ${turn.player.handName(turn.index)}`);
            if (command.kind === 'action') {
                const problem = this.actionProblem(turn, command.action);
                if (problem !== null) fail(problem);
                this.perform(turn, command.action);
            } else {
                while (this.state.kind === 'play' && this.state.turn.player === command.player) {
                    const current = this.state.turn;
                    this.perform(current, this.recommend(current));
                }
            }
            return;
        }
        switch (command.kind) {
            case 'SHOE':
                this.shoe = new Shoe(command.decks, command.seed);
                emit('shoe', command.decks, 'decks', this.shoe.cards.length, 'cards cut', this.shoe.cut(this.rules.PEN));
                break;
            case 'RULE':
                if (command.rules.MIN > command.rules.MAX) fail('min above max');
                this.rules = command.rules;
                emit('rule', command.name, ruleText(this.rules[command.name]));
                break;
            case 'RULES': emit('rules', RULE_NAMES.map(name => `${name} ${ruleText(this.rules[name])}`).join(' ')); break;
            case 'PLAYER': {
                if (this.find(command.name)) fail('player exists');
                const seat = this.seats.indexOf(null);
                if (seat < 0) fail('table full');
                this.seats[seat] = new Player(command.name, seat, command.bankroll);
                emit(command.name, 'sits at seat', seat + 1, 'with', command.bankroll);
                break;
            }
            case 'LEAVE':
                emit(command.player.name, 'leaves with', command.player.bankroll, 'net', signed(command.player.net));
                this.seats[command.player.seat] = null;
                break;
            case 'REBUY':
                command.player.bankroll += command.amount;
                emit(command.player.name, 'rebuys', command.amount, 'bankroll', command.player.bankroll);
                break;
            case 'BET': {
                const { player, amount } = command;
                if (amount !== 0) {
                    if (amount < this.rules.MIN || amount > this.rules.MAX) fail('bet out of limits');
                    if (amount + player.side > player.bankroll) fail('insufficient funds');
                }
                player.bet = amount;
                if (amount === 0) { player.side = 0; emit(player.name, 'bet cleared'); }
                else emit(player.name, 'bets', amount);
                break;
            }
            case 'SIDE': {
                const { player, amount } = command;
                if (amount !== 0) {
                    if (player.bet === 0) fail('no bet');
                    if (amount > this.rules.SIDEMAX) fail('side out of limits');
                    if (player.bet + amount > player.bankroll) fail('insufficient funds');
                }
                player.side = amount;
                if (amount === 0) emit(player.name, 'side cleared');
                else emit(player.name, 'side', amount);
                break;
            }
            case 'DEAL':
                this.requireShoe();
                if (!this.seated().some(player => player.bet !== 0)) fail('no bets');
                this.deal();
                break;
            case 'INSURANCE': {
                // The common state check has already established this alternative.
                const state = this.state as Extract<TableState, { kind: 'insurance' }>;
                const { player, amount } = command;
                const waiting = this.participants[state.next];
                if (player !== waiting) fail(`waiting for ${waiting.name}`);
                if (amount > Math.floor(player.bet / 2)) fail('insurance out of limits');
                if (amount > player.bankroll) fail('insufficient funds');
                player.bankroll -= amount;
                player.insurance = amount;
                if (amount === 0) emit(player.name, 'declines insurance');
                else emit(player.name, 'insures', amount);
                state.next++;
                if (state.next === this.participants.length) this.peek();
                break;
            }
            case 'HINT': {
                const turn = this.requireTurn();
                emit(`hint ${turn.player.handName(turn.index)}: ${this.recommend(turn).toLowerCase()}`);
                break;
            }
            case 'STATUS': this.status(); break;
            case 'COUNT': {
                const shoe = this.requireShoe();
                const remaining = shoe.cards.length - shoe.drawn;
                const scaled = Math.floor(Math.abs(shoe.running) * 5200 / remaining);
                const sign = shoe.running < 0 ? '-' : '';
                const text = `${sign}${Math.floor(scaled / 100)}.${String(scaled % 100).padStart(2, '0')}`;
                emit('count running', shoe.running, 'true', text, 'remaining', remaining);
                break;
            }
            case 'STATS': {
                const players = this.seated();
                if (players.length === 0) fail('no players');
                for (const player of players) emit('stats', player.name, player.stats.text(), 'net', signed(player.net));
                emit('stats dealer rounds', this.round, 'blackjacks', this.dealerBlackjacks, 'busts', this.dealerBusts);
                break;
            }
        }
    }
}

const input = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const table = new Table();
for (const line of input.slice(1, Number(input[0]) + 1)) {
    try { table.execute(line.split(' ')); }
    catch (problem) {
        if (!(problem instanceof CommandError)) throw problem;
        emit('error:', problem.message);
    }
}
process.stdout.write(output.join('\n') + '\n');
