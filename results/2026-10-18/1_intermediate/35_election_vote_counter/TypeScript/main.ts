import { readFileSync } from 'node:fs';

type PlainMethod = 'PLURALITY' | 'RUNOFF' | 'IRV' | 'COOMBS' | 'BUCKLIN' | 'BORDA'
    | 'BALDWIN' | 'NANSON' | 'BLACK' | 'VETO' | 'COPELAND' | 'SCHULZE' | 'RANKEDPAIRS' | 'KEMENY';
type MinimaxKind = 'WINNING' | 'MARGIN' | 'OPPOSITION';
type RankedMethod = { readonly kind: PlainMethod }
    | { readonly kind: 'MINIMAX'; readonly metric: MinimaxKind }
    | { readonly kind: 'APPROVAL'; readonly count: number };
type Method = RankedMethod | { readonly kind: 'CONDORCET' } | { readonly kind: 'STV'; readonly seats: number };
type ReportKind = 'STATUS' | 'BALLOTS' | 'PROFILE' | 'PAIRWISE' | 'EXHAUSTED' | 'SUMMARY';
type Command = { readonly kind: 'CANDIDATES'; readonly names: readonly string[] }
    | { readonly kind: 'TIEBREAK'; readonly names: readonly string[] }
    | { readonly kind: 'BALLOT'; readonly votes: number; readonly names: readonly string[] }
    | { readonly kind: 'RANDOM'; readonly count: number; readonly seed: number }
    | { readonly kind: 'UNDO' }
    | { readonly kind: 'WITHDRAW' | 'RESTORE'; readonly name: string }
    | { readonly kind: ReportKind }
    | { readonly kind: 'COMPARE'; readonly names: readonly [string, string] }
    | { readonly kind: 'RANKING' | 'SPOILERS'; readonly method: Method }
    | { readonly kind: 'TALLY'; readonly method: Method };
type Field = readonly number[];
type Scores = readonly number[];
type Matrix = readonly Scores[];
interface Ballot { readonly votes: number; readonly ranking: Field }
interface Aggregate {
    readonly groups: readonly Ballot[];
    readonly first: Scores;
    readonly last: Scores;
    readonly borda: Scores;
    readonly positions: Matrix;
    readonly pairwise: Matrix;
    readonly total: number;
    readonly blank: number;
}
interface Result { readonly lines: readonly string[] }
interface RankedResult extends Result { readonly standings: Field }
interface Removal { readonly candidate: number; readonly tie: boolean }

class CommandError extends Error {}
function fail(reason: string): never { throw new CommandError(reason); }
const sum = (values: Scores): number => values.reduce((total, value) => total + value, 0);
const ascii = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const money = (value: number): string => String(Math.floor(value / 100)) + '.' + String(value % 100).padStart(2, '0');
const tieMark = (tie: boolean): string => tie ? ' (tie)' : '';
const summaryMethods: readonly RankedMethod[] = [
    { kind: 'PLURALITY' }, { kind: 'RUNOFF' }, { kind: 'IRV' }, { kind: 'COOMBS' },
    { kind: 'BUCKLIN' }, { kind: 'BORDA' }, { kind: 'BALDWIN' }, { kind: 'NANSON' },
    { kind: 'BLACK' }, { kind: 'VETO' }, { kind: 'COPELAND' }, { kind: 'MINIMAX', metric: 'WINNING' },
    { kind: 'SCHULZE' }, { kind: 'RANKEDPAIRS' }, { kind: 'KEMENY' }
];

function parseMethod(words: readonly string[]): Method {
    switch (words[0]) {
        case 'MINIMAX': return { kind: 'MINIMAX', metric: words[1] as MinimaxKind };
        case 'APPROVAL': return { kind: 'APPROVAL', count: Number(words[1]) };
        case 'STV': return { kind: 'STV', seats: Number(words[1]) };
        case 'CONDORCET': return { kind: 'CONDORCET' };
        default: return { kind: words[0] as PlainMethod };
    }
}
function methodText(method: Method): string {
    switch (method.kind) {
        case 'MINIMAX': return 'MINIMAX ' + method.metric;
        case 'APPROVAL': return 'APPROVAL ' + method.count;
        case 'STV': return 'STV ' + method.seats;
        default: return method.kind;
    }
}
function rankable(method: Method): method is RankedMethod {
    return method.kind !== 'CONDORCET' && method.kind !== 'STV';
}
function parseCommand(line: string): Command {
    const [kind, ...args] = line.split(' ');
    switch (kind) {
        case 'CANDIDATES': case 'TIEBREAK': return { kind, names: args };
        case 'BALLOT': return { kind, votes: Number(args[0]), names: args[1] === '-' ? [] : args[1].split('>') };
        case 'RANDOM': return { kind, count: Number(args[0]), seed: Number(args[1]) };
        case 'UNDO': return { kind };
        case 'WITHDRAW': case 'RESTORE': return { kind, name: args[0] };
        case 'STATUS': case 'BALLOTS': case 'PROFILE': case 'PAIRWISE': case 'EXHAUSTED': case 'SUMMARY': return { kind };
        case 'COMPARE': return { kind, names: [args[0], args[1]] };
        case 'RANKING': case 'SPOILERS': return { kind, method: parseMethod(args) };
        default: return { kind: 'TALLY', method: parseMethod([kind, ...args]) };
    }
}

class Election {
    readonly names: readonly string[];
    readonly number: number;
    readonly withdrawn = new Set<number>();
    readonly entries: (readonly Ballot[])[] = [];
    private readonly cache = new Map<number, Aggregate>();
    priority: Field;
    tieRank: Scores;

    constructor(names: readonly string[], number: number) {
        this.names = names;
        this.number = number;
        this.priority = names.map((_, index) => index).sort((a, b) => ascii(names[a], names[b]));
        this.tieRank = names.map((_, candidate) => this.priority.indexOf(candidate));
    }
    zeros(): number[] { return this.names.map(() => 0); }
    matrix(): number[][] { return this.names.map(() => this.zeros()); }
    active(): number[] { return this.names.map((_, index) => index).filter(index => !this.withdrawn.has(index)); }
    candidate(name: string): number {
        const candidate = this.names.indexOf(name);
        if (candidate < 0) fail('unknown candidate ' + name);
        return candidate;
    }
    checkedNames(names: readonly string[]): number[] {
        const result: number[] = [];
        for (const name of names) {
            const candidate = this.candidate(name);
            if (result.includes(candidate)) fail('duplicate candidate ' + name);
            result.push(candidate);
        }
        return result;
    }
    setPriority(order: Field): void {
        this.priority = order;
        this.tieRank = this.names.map((_, candidate) => order.indexOf(candidate));
    }
    addEntry(groups: readonly Ballot[]): void { this.entries.push(groups); this.cache.clear(); }
    undo(): void {
        if (this.entries.length === 0) fail('nothing to undo');
        this.entries.pop();
        this.cache.clear();
    }
    list(field: Field, separator = ', '): string { return field.map(candidate => this.names[candidate]).join(separator); }
    values(field: Field, values: Scores, format: (value: number) => string = String): string {
        return field.map(candidate => this.names[candidate] + ' ' + format(values[candidate])).join(', ');
    }
    ordered(field: Field, scores: Scores, ascending = false): number[] {
        const direction = ascending ? 1 : -1;
        return field.slice().sort((a, b) => direction * (scores[a] - scores[b]) || this.tieRank[a] - this.tieRank[b]);
    }
    preferred(field: Field): number[] { return field.slice().sort((a, b) => this.tieRank[a] - this.tieRank[b]); }

    // Only counts and effective rankings are cached; method decisions use the current priority.
    aggregate(field: Field): Aggregate {
        const mask = field.reduce((bits, candidate) => bits | (1 << candidate), 0);
        const cached = this.cache.get(mask);
        if (cached !== undefined) return cached;
        const combined = new Map<string, { votes: number; ranking: number[] }>();
        for (const entry of this.entries) for (const group of entry) {
            const ranking = group.ranking.filter(candidate => (mask & (1 << candidate)) !== 0);
            const key = ranking.join(',');
            const previous = combined.get(key);
            if (previous === undefined) combined.set(key, { votes: group.votes, ranking });
            else previous.votes += group.votes;
        }
        const groups = [...combined.values()];
        const first = this.zeros(), last = this.zeros(), borda = this.zeros();
        const positions = this.names.map(() => field.map(() => 0)), pairwise = this.matrix();
        let total = 0, blank = 0;
        for (const group of groups) {
            const { votes, ranking } = group;
            total += votes;
            if (ranking.length === 0) blank += votes;
            else first[ranking[0]] += votes;
            const ranks = this.names.map(() => field.length);
            ranking.forEach((candidate, index) => {
                ranks[candidate] = index;
                positions[candidate][index] += votes;
                borda[candidate] += votes * (field.length - index - 1);
            });
            for (const candidate of field) {
                if (ranking.length < field.length ? ranks[candidate] === field.length : candidate === ranking.at(-1)) last[candidate] += votes;
                for (const other of field) if (ranks[candidate] < ranks[other]) pairwise[candidate][other] += votes;
            }
        }
        const result: Aggregate = { groups, first, last, borda, positions, pairwise, total, blank };
        this.cache.set(mask, result);
        return result;
    }
}

function eliminate(election: Election, field: Field, scores: Scores, history: readonly Scores[]): Removal {
    const minimum = Math.min(...field.map(candidate => scores[candidate]));
    let choices = field.filter(candidate => scores[candidate] === minimum);
    const tie = choices.length > 1;
    for (let round = history.length - 1; round >= 0 && choices.length > 1; --round) {
        const previous = history[round];
        const low = Math.min(...choices.map(candidate => previous[candidate]));
        choices = choices.filter(candidate => previous[candidate] === low);
    }
    return { candidate: election.preferred(choices).at(-1)!, tie };
}
function finish(election: Election, standings: Field, tie: boolean, lines: readonly string[]): RankedResult {
    return { standings, lines: [...lines, 'winner: ' + election.names[standings[0]] + tieMark(tie)] };
}
function scoredResult(election: Election, field: Field, scores: Scores, label: string, ascending = false): RankedResult {
    const order = election.ordered(field, scores, ascending);
    return finish(election, order, scores[order[0]] === scores[order[1]], [label + ': ' + election.values(field, scores)]);
}
function pairLines(election: Election, field: Field, matrix: Matrix): string[] {
    const lines: string[] = [];
    for (let i = 0; i < field.length; ++i) for (let j = i + 1; j < field.length; ++j) {
        const a = field[i], b = field[j], forward = matrix[a][b], backward = matrix[b][a];
        const result = forward === backward ? 'tie' : election.names[forward > backward ? a : b];
        lines.push(election.names[a] + ' vs ' + election.names[b] + ': ' + forward + '-' + backward + ' (' + result + ')');
    }
    return lines;
}
function runoff(election: Election, field: Field): RankedResult {
    const first = election.aggregate(field).first, order = election.ordered(field, first);
    const lines = ['round 1: ' + election.values(field, first)];
    if (2 * first[order[0]] > sum(field.map(a => first[a]))) return finish(election, order, false, lines);
    const finalists = order.slice(0, 2).sort((a, b) => a - b), second = election.aggregate(finalists).first;
    const advanceTie = order.length >= 3 && first[order[1]] === first[order[2]];
    lines.push('finalists: ' + election.list(finalists) + tieMark(advanceTie), 'round 2: ' + election.values(finalists, second));
    const winners = finalists.slice().sort((a, b) => second[b] - second[a] || first[b] - first[a] || election.tieRank[a] - election.tieRank[b]);
    return finish(election, [...winners, ...order.slice(2)], second[winners[0]] === second[winners[1]], lines);
}
function eliminationRounds(election: Election, field: Field, coombs = false): RankedResult & { readonly exhausted: readonly string[] } {
    let remaining = field.slice();
    const eliminated: number[] = [], history: Scores[] = [], lines: string[] = [], exhausted: string[] = [];
    for (let round = 1; ; ++round) {
        const aggregate = election.aggregate(remaining), scores = aggregate.first;
        const order = election.ordered(remaining, scores), active = sum(remaining.map(a => scores[a]));
        let line = 'round ' + round + ': ' + election.values(remaining, scores);
        exhausted.push('round ' + round + ': active ' + active + ', exhausted ' + (aggregate.total - active));
        if (remaining.length === 1 || 2 * scores[order[0]] > active) {
            return { ...finish(election, [...order, ...eliminated.reverse()], false, [...lines, line]), exhausted };
        }
        let choice: Removal;
        if (coombs) {
            const maximum = Math.max(...remaining.map(a => aggregate.last[a]));
            const tied = remaining.filter(a => aggregate.last[a] === maximum);
            tied.sort((a, b) => scores[a] - scores[b] || election.tieRank[b] - election.tieRank[a]);
            choice = { candidate: tied[0], tie: tied.length > 1 };
            line += '; last ' + election.values(remaining, aggregate.last);
        } else choice = eliminate(election, remaining, scores, history);
        lines.push(line + '; eliminated ' + election.names[choice.candidate] + tieMark(choice.tie));
        history.push(scores);
        eliminated.push(choice.candidate);
        remaining = remaining.filter(a => a !== choice.candidate);
    }
}
function bucklin(election: Election, field: Field): RankedResult {
    const aggregate = election.aggregate(field), majority = Math.floor((aggregate.total - aggregate.blank) / 2) + 1;
    const history: Scores[] = [], lines = ['majority: ' + majority];
    for (let depth = 1; depth <= field.length; ++depth) {
        const scores = aggregate.positions.map(row => sum(row.slice(0, depth)));
        history.push(scores);
        lines.push('round ' + depth + ': ' + election.values(field, scores));
        if (field.some(a => scores[a] >= majority)) break;
    }
    const order = field.slice().sort((a, b) => {
        for (let round = history.length - 1; round >= 0; --round) {
            const scores = history[round];
            if (scores[a] !== scores[b]) return scores[b] - scores[a];
        }
        return election.tieRank[a] - election.tieRank[b];
    });
    const final = history.at(-1)!;
    return finish(election, order, final[order[0]] === final[order[1]], lines);
}
function bordaRounds(election: Election, field: Field, nanson: boolean): RankedResult {
    let remaining = field.slice();
    const eliminated: number[][] = [], history: Scores[] = [], lines: string[] = [];
    for (let round = 1; remaining.length >= 2; ++round) {
        const scores = election.aggregate(remaining).borda;
        let line = 'round ' + round + ': ' + election.values(remaining, scores);
        if (nanson) {
            const total = sum(remaining.map(a => scores[a]));
            const removed = remaining.filter(a => scores[a] * remaining.length < total);
            if (removed.length === 0) { lines.push(line); break; }
            line += '; eliminated ' + election.list(removed);
            eliminated.unshift(election.ordered(removed, scores));
            remaining = remaining.filter(a => !removed.includes(a));
        } else {
            const choice = eliminate(election, remaining, scores, history);
            line += '; eliminated ' + election.names[choice.candidate] + tieMark(choice.tie);
            eliminated.unshift([choice.candidate]);
            remaining = remaining.filter(a => a !== choice.candidate);
        }
        history.push(scores);
        lines.push(line);
    }
    return finish(election, [...election.preferred(remaining), ...eliminated.flat()], nanson && remaining.length > 1, lines);
}
function condorcetWinner(field: Field, pairwise: Matrix, loser = false): number | undefined {
    return field.find(a => field.every(b => a === b || (loser ? pairwise[a][b] < pairwise[b][a] : pairwise[a][b] > pairwise[b][a])));
}
function closure(field: Field, edges: readonly (readonly boolean[])[]): boolean[][] {
    const reach = edges.map(row => row.slice());
    for (const via of field) for (const a of field) for (const b of field) reach[a][b] ||= reach[a][via] && reach[via][b];
    return reach;
}
function condorcet(election: Election, field: Field, pairwise: Matrix): Result {
    const winner = condorcetWinner(field, pairwise), loser = condorcetWinner(field, pairwise, true);
    const weak = election.names.map(() => election.names.map(() => false)), strong = weak.map(row => row.slice());
    for (const a of field) for (const b of field) {
        weak[a][b] = pairwise[a][b] >= pairwise[b][a];
        strong[a][b] = pairwise[a][b] > pairwise[b][a];
    }
    const weakReach = closure(field, weak), strongReach = closure(field, strong);
    const smith = field.filter(a => field.every(b => weakReach[a][b]));
    const schwartz = field.filter(a => field.every(b => !strongReach[b][a] || strongReach[a][b]));
    return { lines: ['winner: ' + (winner === undefined ? 'NONE' : election.names[winner]),
        'loser: ' + (loser === undefined ? 'NONE' : election.names[loser]),
        'smith: ' + election.list(smith), 'schwartz: ' + election.list(schwartz)] };
}
function topological(election: Election, field: Field, beats: (a: number, b: number) => boolean): { standings: number[]; tie: boolean } {
    let remaining = field.slice(), tie = false;
    const standings: number[] = [];
    while (remaining.length > 0) {
        const choices = remaining.filter(a => remaining.every(b => a === b || !beats(b, a)));
        if (standings.length === 0) tie = choices.length > 1;
        const chosen = election.preferred(choices)[0];
        standings.push(chosen);
        remaining = remaining.filter(a => a !== chosen);
    }
    return { standings, tie };
}
function schulze(election: Election, field: Field, pairwise: Matrix): RankedResult {
    const paths = election.matrix();
    for (const a of field) for (const b of field) if (pairwise[a][b] > pairwise[b][a]) paths[a][b] = pairwise[a][b];
    for (const via of field) for (const a of field) if (a !== via) {
        for (const b of field) if (b !== via && b !== a) paths[a][b] = Math.max(paths[a][b], Math.min(paths[a][via], paths[via][b]));
    }
    const { standings, tie } = topological(election, field, (a, b) => paths[a][b] > paths[b][a]);
    return finish(election, standings, tie, [...pairLines(election, field, paths), 'ranking: ' + election.list(standings, ' > ')]);
}
function rankedPairs(election: Election, field: Field, pairwise: Matrix): RankedResult {
    const pairs: [number, number][] = [], edges = election.names.map(() => election.names.map(() => false)), lines: string[] = [];
    for (const a of field) for (const b of field) if (pairwise[a][b] > pairwise[b][a]) pairs.push([a, b]);
    pairs.sort(([a, b], [c, d]) => pairwise[c][d] - pairwise[a][b] || pairwise[b][a] - pairwise[d][c] || election.tieRank[a] - election.tieRank[c] || election.tieRank[b] - election.tieRank[d]);
    for (const [a, b] of pairs) {
        const lock = !closure(field, edges)[b][a];
        if (lock) edges[a][b] = true;
        lines.push((lock ? 'lock ' : 'skip ') + election.names[a] + '>' + election.names[b] + ' ' + pairwise[a][b] + '-' + pairwise[b][a]);
    }
    const { standings, tie } = topological(election, field, (a, b) => edges[a][b]);
    return finish(election, standings, tie, lines);
}
function kemeny(election: Election, field: Field, pairwise: Matrix): RankedResult {
    interface Optimum { readonly score: number; readonly count: number; readonly first: Field }
    const memo = new Map<number, Optimum>([[0, { score: 0, count: 1, first: [] }]]);
    function solve(mask: number): Optimum {
        const cached = memo.get(mask);
        if (cached !== undefined) return cached;
        let score = -1, count = 0;
        let first: number[] = [];
        for (const candidate of field) if ((mask & (1 << candidate)) !== 0) {
            const rest = mask ^ (1 << candidate), suffix = solve(rest);
            const value = suffix.score + sum(field.filter(b => (rest & (1 << b)) !== 0).map(b => pairwise[candidate][b]));
            if (value > score) { score = value; count = suffix.count; first = [candidate]; }
            else if (value === score) { count += suffix.count; first.push(candidate); }
        }
        const result: Optimum = { score, count, first };
        memo.set(mask, result);
        return result;
    }
    let mask = field.reduce((bits, candidate) => bits | (1 << candidate), 0);
    const optimum = solve(mask), standings: number[] = [];
    while (mask !== 0) {
        const candidate = election.preferred(solve(mask).first)[0];
        standings.push(candidate);
        mask ^= 1 << candidate;
    }
    return finish(election, standings, optimum.first.length > 1, ['score: ' + optimum.score,
        'optimal: ' + optimum.count, 'ranking: ' + election.list(standings, ' > ')]);
}
function stv(election: Election, field: Field, seats: number): Result {
    if (seats >= field.length) fail('too many seats');
    const aggregate = election.aggregate(field), groups = aggregate.groups.filter(group => group.ranking.length > 0);
    const quota = Math.floor(100 * (aggregate.total - aggregate.blank) / (seats + 1)) + 1;
    const perVote = groups.map(() => 100), elected: number[] = [], history: Scores[] = [], lines = ['quota: ' + money(quota)];
    let continuing = field.slice();
    for (let round = 1; ; ++round) {
        const scores = election.zeros(), owners: (number | undefined)[] = [];
        let exhausted = 0;
        groups.forEach((group, index) => {
            const owner = group.ranking.find(a => continuing.includes(a));
            owners.push(owner);
            if (owner === undefined) exhausted += group.votes * perVote[index];
            else scores[owner] += group.votes * perVote[index];
        });
        let line = 'round ' + round + ': ' + election.values(continuing, scores, money) + '; exhausted ' + money(exhausted);
        const order = election.ordered(continuing, scores);
        if (continuing.length === seats - elected.length) {
            elected.push(...order);
            lines.push(line + '; elected ' + election.list(order));
            break;
        }
        let removed: number;
        if (scores[order[0]] >= quota) {
            removed = order[0];
            elected.push(removed);
            const total = scores[removed], surplus = total - quota;
            owners.forEach((owner, index) => {
                if (owner === removed) perVote[index] = Math.floor(perVote[index] * surplus / total);
            });
            line += '; elected ' + election.names[removed] + ' (surplus ' + money(surplus) + ')';
        } else {
            const choice = eliminate(election, continuing, scores, history);
            removed = choice.candidate;
            line += '; excluded ' + election.names[removed] + tieMark(choice.tie);
        }
        lines.push(line);
        if (elected.length === seats) break;
        history.push(scores);
        continuing = continuing.filter(a => a !== removed);
    }
    return { lines: [...lines, 'elected: ' + election.list(elected)] };
}

function tally(election: Election, method: RankedMethod, field: Field): RankedResult;
function tally(election: Election, method: Method, field: Field): Result;
function tally(election: Election, method: Method, field: Field): Result {
    const aggregate = election.aggregate(field), pairwise = aggregate.pairwise;
    switch (method.kind) {
        case 'PLURALITY': return scoredResult(election, field, aggregate.first, 'votes');
        case 'RUNOFF': return runoff(election, field);
        case 'IRV': return eliminationRounds(election, field);
        case 'COOMBS': return eliminationRounds(election, field, true);
        case 'BUCKLIN': return bucklin(election, field);
        case 'BORDA': return scoredResult(election, field, aggregate.borda, 'scores');
        case 'BALDWIN': return bordaRounds(election, field, false);
        case 'NANSON': return bordaRounds(election, field, true);
        case 'BLACK': {
            const winner = condorcetWinner(field, pairwise), order = election.ordered(field, aggregate.borda);
            const standings = winner === undefined ? order : [winner, ...order.filter(a => a !== winner)];
            const tie = winner === undefined && aggregate.borda[order[0]] === aggregate.borda[order[1]];
            return finish(election, standings, tie, ['condorcet: ' + (winner === undefined ? 'NONE' : election.names[winner]),
                'scores: ' + election.values(field, aggregate.borda)]);
        }
        case 'VETO': return scoredResult(election, field, aggregate.last, 'vetoes', true);
        case 'CONDORCET': return condorcet(election, field, pairwise);
        case 'COPELAND': {
            const scores = election.zeros(), parts: string[] = [];
            for (const candidate of field) {
                let wins = 0, draws = 0, losses = 0;
                for (const other of field) if (candidate !== other) {
                    if (pairwise[candidate][other] > pairwise[other][candidate]) ++wins;
                    else if (pairwise[candidate][other] === pairwise[other][candidate]) ++draws;
                    else ++losses;
                }
                scores[candidate] = 2 * wins + draws;
                parts.push(election.names[candidate] + ' ' + Math.floor(scores[candidate] / 2) + '.'
                    + (scores[candidate] % 2 ? '5' : '0') + ' (' + wins + '-' + draws + '-' + losses + ')');
            }
            const order = election.ordered(field, scores);
            return finish(election, order, scores[order[0]] === scores[order[1]], ['scores: ' + parts.join(', ')]);
        }
        case 'MINIMAX': {
            const scores = election.zeros();
            for (const candidate of field) for (const other of field) if (candidate !== other) {
                const opposition = pairwise[other][candidate], support = pairwise[candidate][other];
                if (method.metric === 'OPPOSITION') scores[candidate] = Math.max(scores[candidate], opposition);
                else if (opposition > support) scores[candidate] = Math.max(scores[candidate], method.metric === 'MARGIN' ? opposition - support : opposition);
            }
            return scoredResult(election, field, scores, 'scores', true);
        }
        case 'SCHULZE': return schulze(election, field, pairwise);
        case 'RANKEDPAIRS': return rankedPairs(election, field, pairwise);
        case 'KEMENY': return kemeny(election, field, pairwise);
        case 'APPROVAL': return scoredResult(election, field, aggregate.positions.map(row => sum(row.slice(0, method.count))), 'approvals');
        case 'STV': return stv(election, field, method.seats);
    }
}
type QueryCommand = Extract<Command, { readonly kind: ReportKind | 'COMPARE' | 'RANKING' | 'SPOILERS' | 'TALLY' }>;
function reports(election: Election, command: QueryCommand, field: Field): readonly string[] {
    const aggregate = election.aggregate(field);
    switch (command.kind) {
        case 'STATUS': {
            const withdrawn = election.names.map((_, index) => index).filter(a => election.withdrawn.has(a));
            return ['election ' + election.number, 'active: ' + election.list(field),
                'withdrawn: ' + (withdrawn.length ? election.list(withdrawn) : 'none'),
                'tiebreak: ' + election.list(election.priority),
                'ballots: ' + aggregate.total + ' in ' + election.entries.length + ' entries'];
        }
        case 'BALLOTS': {
            const groups = aggregate.groups.map(group => ({
                votes: group.votes, notation: group.ranking.length ? election.list(group.ranking, '>') : '-'
            }));
            groups.sort((a, b) => b.votes - a.votes || ascii(a.notation, b.notation));
            return ['total ' + aggregate.total + ', blank ' + aggregate.blank + ', distinct ' + groups.length,
                ...groups.map(group => group.votes + ' ' + group.notation)];
        }
        case 'PROFILE': return field.map(a => election.names[a] + ': ' + aggregate.positions[a].join(' ')
            + ' unranked ' + (aggregate.total - sum(aggregate.positions[a])));
        case 'PAIRWISE': return pairLines(election, field, aggregate.pairwise);
        case 'EXHAUSTED': return eliminationRounds(election, field).exhausted;
        case 'RANKING': case 'SPOILERS': {
            const method = command.method;
            if (!rankable(method)) fail('not rankable');
            if (command.kind === 'SPOILERS' && field.length < 3) fail('too few candidates');
            const standings = tally(election, method, field).standings;
            if (command.kind === 'RANKING') return [election.list(standings, ' > ')];
            const winner = standings[0], lines = ['winner: ' + election.names[winner]];
            for (const excluded of field) if (excluded !== winner) {
                const other = tally(election, method, field.filter(a => a !== excluded)).standings[0];
                lines.push('without ' + election.names[excluded] + ': ' + election.names[other] + (other === winner ? '' : ' (changed)'));
            }
            return lines;
        }
        case 'SUMMARY': {
            const wins = election.zeros(), lines: string[] = [];
            for (const method of summaryMethods) {
                const winner = tally(election, method, field).standings[0];
                ++wins[winner];
                lines.push(methodText(method) + ': ' + election.names[winner]);
            }
            return [...lines, 'wins: ' + election.values(field, wins)];
        }
        case 'COMPARE': {
            const compared: number[] = [];
            for (const name of command.names) {
                const candidate = election.candidate(name);
                if (election.withdrawn.has(candidate)) fail('withdrawn candidate ' + name);
                compared.push(candidate);
            }
            const [first, second] = compared;
            if (first === second) fail('same candidate');
            const forward = aggregate.pairwise[first][second], backward = aggregate.pairwise[second][first];
            const ahead: [string[], string[]] = [[], []];
            for (const method of summaryMethods) {
                const standings = tally(election, method, field).standings;
                ahead[standings.indexOf(first) < standings.indexOf(second) ? 0 : 1].push(methodText(method));
            }
            return [command.names[0] + ' ' + forward + ', ' + command.names[1] + ' ' + backward
                + ', neither ' + (aggregate.total - forward - backward),
                ...command.names.map((name, side) => name + ' ahead: ' + (ahead[side].length ? ahead[side].join(', ') : 'none'))];
        }
        case 'TALLY': return tally(election, command.method, field).lines;
    }
}

class VoteCounter {
    private election: Election | null = null;
    private count = 0;

    execute(line: string): readonly string[] {
        const command = parseCommand(line);
        if (command.kind === 'CANDIDATES') {
            if (command.names.length < 2) fail('too few candidates');
            const seen = new Set<string>();
            for (const name of command.names) {
                if (seen.has(name)) fail('duplicate candidate ' + name);
                seen.add(name);
            }
            this.election = new Election(command.names, ++this.count);
            return ['election ' + this.count + ': ' + command.names.length + ' candidates'];
        }
        const election = this.election;
        if (election === null) fail('no election');
        const field = election.active();
        switch (command.kind) {
            case 'BALLOT': {
                const ranking = election.checkedNames(command.names);
                election.addEntry([{ votes: command.votes, ranking }]);
                return [];
            }
            case 'RANDOM': {
                let state = command.seed;
                const draw = (): number => { state = 48271 * state % 2147483647; return state; };
                const groups: Ballot[] = [];
                for (let group = 0; group < command.count; ++group) {
                    const ranking = field.slice();
                    for (let index = ranking.length - 1; index >= 1; --index) {
                        const other = draw() % (index + 1);
                        [ranking[index], ranking[other]] = [ranking[other], ranking[index]];
                    }
                    groups.push({ votes: 1, ranking: ranking.slice(0, draw() % ranking.length + 1) });
                }
                election.addEntry(groups);
                return [];
            }
            case 'UNDO': election.undo(); return [];
            case 'WITHDRAW': case 'RESTORE': {
                const candidate = election.candidate(command.name);
                if (command.kind === 'WITHDRAW') {
                    if (election.withdrawn.has(candidate)) fail('already withdrawn ' + command.name);
                    if (field.length <= 2) fail('too few candidates');
                    election.withdrawn.add(candidate);
                } else {
                    if (!election.withdrawn.has(candidate)) fail('not withdrawn ' + command.name);
                    election.withdrawn.delete(candidate);
                }
                return [];
            }
            case 'TIEBREAK': {
                const order = election.checkedNames(command.names);
                if (order.length !== election.names.length) fail('incomplete tiebreak');
                election.setPriority(order);
                return [];
            }
            default:
                if (command.kind !== 'STATUS' && election.entries.length === 0) fail('no ballots');
                return ['[' + line + ']', ...reports(election, command, field)];
        }
    }
}

const input = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const counter = new VoteCounter(), output: string[] = [];
for (let index = 1; index <= Number(input[0]); ++index) {
    try { output.push(...counter.execute(input[index])); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        output.push('ERROR ' + error.message);
    }
}
process.stdout.write(output.join('\n') + '\n');
