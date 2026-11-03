'use strict';

const fs = require('node:fs');
class CommandError extends Error {}
const fail = reason => { throw new CommandError(reason); };
const sum = values => values.reduce((total, value) => total + value, 0);
const ascii = (first, second) => first < second ? -1 : first > second ? 1 : 0;
const money = value => `${Math.floor(value / 100)}.${String(value % 100).padStart(2, '0')}`;
const summaryMethods = ['PLURALITY', 'RUNOFF', 'IRV', 'COOMBS', 'BUCKLIN', 'BORDA', 'BALDWIN', 'NANSON', 'BLACK', 'VETO', 'COPELAND', 'MINIMAX WINNING', 'SCHULZE', 'RANKEDPAIRS', 'KEMENY'];

class Election {
    constructor(names, number) {
        this.names = names;
        this.number = number;
        this.withdrawn = new Set();
        this.entries = [];
        this.cache = new Map();
        this.setPriority(names.map((_, index) => index).sort((a, b) => ascii(names[a], names[b])));
    }
    zeros() { return this.names.map(() => 0); }
    matrix() { return this.names.map(() => this.zeros()); }
    active() { return this.names.map((_, index) => index).filter(index => !this.withdrawn.has(index)); }
    candidate(name) {
        const index = this.names.indexOf(name);
        if (index < 0) fail(`unknown candidate ${name}`);
        return index;
    }
    nameList(names) {
        const found = [];
        for (const name of names) {
            const candidate = this.candidate(name);
            if (found.includes(candidate)) fail(`duplicate candidate ${name}`);
            found.push(candidate);
        }
        return found;
    }
    setPriority(order) {
        this.priority = order;
        this.tieRank = this.zeros();
        order.forEach((candidate, index) => { this.tieRank[candidate] = index; });
    }
    list(field, separator = ', ') { return field.map(candidate => this.names[candidate]).join(separator); }
    values(field, values, format = String) { return field.map(candidate => `${this.names[candidate]} ${format(values[candidate])}`).join(', '); }
    ordered(field, values, ascending = false) {
        const direction = ascending ? 1 : -1;
        return field.slice().sort((a, b) => direction * (values[a] - values[b]) || this.tieRank[a] - this.tieRank[b]);
    }
    preferred(field) { return field.slice().sort((a, b) => this.tieRank[a] - this.tieRank[b]); }
    aggregate(field) {
        const mask = field.reduce((bits, candidate) => bits | (1 << candidate), 0);
        if (this.cache.has(mask)) return this.cache.get(mask);
        const combined = new Map();
        for (const entry of this.entries) for (const group of entry) {
            const ranking = group.ranking.filter(candidate => mask & (1 << candidate));
            const key = ranking.join(',');
            if (combined.has(key)) combined.get(key).votes += group.votes;
            else combined.set(key, { votes: group.votes, ranking });
        }
        const groups = [...combined.values()], first = this.zeros(), last = this.zeros(), borda = this.zeros();
        const positions = this.names.map(() => field.map(() => 0)), pairwise = this.matrix();
        let total = 0, blank = 0;
        for (const { votes, ranking } of groups) {
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
        const aggregate = { groups, first, last, borda, positions, pairwise, total, blank };
        this.cache.set(mask, aggregate);
        return aggregate;
    }
}

function eliminate(election, field, values, history) {
    const minimum = Math.min(...field.map(candidate => values[candidate]));
    let candidates = field.filter(candidate => values[candidate] === minimum);
    const tie = candidates.length > 1;
    for (let round = history.length - 1; round >= 0 && candidates.length > 1; --round) {
        const oldMinimum = Math.min(...candidates.map(candidate => history[round][candidate]));
        candidates = candidates.filter(candidate => history[round][candidate] === oldMinimum);
    }
    return { candidate: election.preferred(candidates).at(-1), tie };
}
function winnerLine(election, standings, tie) { return `winner: ${election.names[standings[0]]}${tie ? ' (tie)' : ''}`; }
function rankedResult(election, standings, tie, lines) { return { standings, tie, lines: [...lines, winnerLine(election, standings, tie)] }; }
function scoredResult(election, field, values, label, ascending = false) {
    const standings = election.ordered(field, values, ascending);
    return rankedResult(election, standings, values[standings[0]] === values[standings[1]], [`${label}: ${election.values(field, values)}`]);
}
function pairLines(election, field, matrix) {
    const lines = [];
    for (let i = 0; i < field.length; ++i) for (let j = i + 1; j < field.length; ++j) {
        const first = field[i], second = field[j], a = matrix[first][second], b = matrix[second][first];
        const result = a > b ? election.names[first] : b > a ? election.names[second] : 'tie';
        lines.push(`${election.names[first]} vs ${election.names[second]}: ${a}-${b} (${result})`);
    }
    return lines;
}
function runoff(election, field) {
    const first = election.aggregate(field).first, order = election.ordered(field, first);
    const lines = [`round 1: ${election.values(field, first)}`];
    if (2 * first[order[0]] > sum(field.map(candidate => first[candidate]))) return rankedResult(election, order, false, lines);
    const finalists = order.slice(0, 2).sort((a, b) => a - b), second = election.aggregate(finalists).first;
    const advancementTie = order.length >= 3 && first[order[1]] === first[order[2]];
    lines.push(`finalists: ${election.list(finalists)}${advancementTie ? ' (tie)' : ''}`, `round 2: ${election.values(finalists, second)}`);
    const winners = finalists.slice().sort((a, b) => second[b] - second[a] || first[b] - first[a] || election.tieRank[a] - election.tieRank[b]);
    return rankedResult(election, [...winners, ...order.slice(2)], second[winners[0]] === second[winners[1]], lines);
}
function eliminationRounds(election, field, coombs) {
    let remaining = field.slice();
    const eliminated = [], history = [], lines = [], exhausted = [];
    for (let round = 1; ; ++round) {
        const aggregate = election.aggregate(remaining), values = aggregate.first;
        const ordered = election.ordered(remaining, values), active = sum(remaining.map(candidate => values[candidate]));
        let line = `round ${round}: ${election.values(remaining, values)}`;
        exhausted.push(`round ${round}: active ${active}, exhausted ${aggregate.total - active}`);
        if (remaining.length === 1 || 2 * values[ordered[0]] > active) {
            const result = rankedResult(election, [...ordered, ...eliminated.reverse()], false, [...lines, line]);
            return { ...result, exhausted };
        }
        let chosen;
        if (coombs) {
            const last = aggregate.last, maximum = Math.max(...remaining.map(candidate => last[candidate]));
            const tied = remaining.filter(candidate => last[candidate] === maximum);
            const candidate = tied.slice().sort((a, b) => values[a] - values[b] || election.tieRank[b] - election.tieRank[a])[0];
            chosen = { candidate, tie: tied.length > 1 };
            line += `; last ${election.values(remaining, last)}`;
        } else chosen = eliminate(election, remaining, values, history);
        lines.push(`${line}; eliminated ${election.names[chosen.candidate]}${chosen.tie ? ' (tie)' : ''}`);
        history.push(values);
        eliminated.push(chosen.candidate);
        remaining = remaining.filter(candidate => candidate !== chosen.candidate);
    }
}
function bucklin(election, field) {
    const aggregate = election.aggregate(field), majority = Math.floor((aggregate.total - aggregate.blank) / 2) + 1;
    const history = [], lines = [`majority: ${majority}`];
    for (let depth = 1; depth <= field.length; ++depth) {
        const values = aggregate.positions.map(positions => sum(positions.slice(0, depth)));
        history.push(values);
        lines.push(`round ${depth}: ${election.values(field, values)}`);
        if (field.some(candidate => values[candidate] >= majority) || depth === field.length) break;
    }
    const standings = field.slice().sort((a, b) => {
        for (let round = history.length - 1; round >= 0; --round) if (history[round][a] !== history[round][b]) return history[round][b] - history[round][a];
        return election.tieRank[a] - election.tieRank[b];
    });
    const final = history.at(-1);
    return rankedResult(election, standings, final[standings[0]] === final[standings[1]], lines);
}
function bordaRounds(election, field, nanson) {
    let remaining = field.slice();
    const eliminated = [], history = [], lines = [];
    for (let round = 1; remaining.length >= 2; ++round) {
        const values = election.aggregate(remaining).borda;
        let line = `round ${round}: ${election.values(remaining, values)}`;
        if (nanson) {
            const total = sum(remaining.map(candidate => values[candidate]));
            const removed = remaining.filter(candidate => values[candidate] * remaining.length < total);
            if (removed.length === 0) { lines.push(line); break; }
            line += `; eliminated ${election.list(removed)}`;
            eliminated.unshift(election.ordered(removed, values));
            remaining = remaining.filter(candidate => !removed.includes(candidate));
        } else {
            const chosen = eliminate(election, remaining, values, history);
            line += `; eliminated ${election.names[chosen.candidate]}${chosen.tie ? ' (tie)' : ''}`;
            eliminated.unshift([chosen.candidate]);
            remaining = remaining.filter(candidate => candidate !== chosen.candidate);
        }
        history.push(values);
        lines.push(line);
    }
    return rankedResult(election, [...election.preferred(remaining), ...eliminated.flat()], remaining.length > 1, lines);
}
function condorcetWinner(field, pairwise, loser = false) {
    return field.find(candidate => field.every(other => candidate === other || (loser ? pairwise[candidate][other] < pairwise[other][candidate] : pairwise[candidate][other] > pairwise[other][candidate])));
}
function closure(field, edges) {
    const reach = edges.map(row => row.slice());
    for (const middle of field) for (const first of field) for (const second of field) {
        if (reach[first][middle] && reach[middle][second]) reach[first][second] = true;
    }
    return reach;
}
function condorcet(election, field, pairwise) {
    const winner = condorcetWinner(field, pairwise), loser = condorcetWinner(field, pairwise, true);
    const weak = election.names.map(() => election.names.map(() => false)), strong = weak.map(row => row.slice());
    for (const first of field) for (const second of field) {
        weak[first][second] = first === second || pairwise[first][second] >= pairwise[second][first];
        strong[first][second] = first !== second && pairwise[first][second] > pairwise[second][first];
    }
    const weakReach = closure(field, weak), strongReach = closure(field, strong);
    const smith = field.filter(candidate => field.every(other => weakReach[candidate][other]));
    const schwartz = field.filter(candidate => field.every(other => !strongReach[other][candidate] || strongReach[candidate][other]));
    return { standings: [], tie: false, lines: [`winner: ${winner === undefined ? 'NONE' : election.names[winner]}`, `loser: ${loser === undefined ? 'NONE' : election.names[loser]}`, `smith: ${election.list(smith)}`, `schwartz: ${election.list(schwartz)}`] };
}
function topological(election, field, beats) {
    let remaining = field.slice(), tie = false;
    const standings = [];
    while (remaining.length > 0) {
        const eligible = remaining.filter(candidate => remaining.every(other => candidate === other || !beats(other, candidate)));
        if (standings.length === 0) tie = eligible.length > 1;
        const next = election.preferred(eligible)[0];
        standings.push(next);
        remaining = remaining.filter(candidate => candidate !== next);
    }
    return { standings, tie };
}
function schulze(election, field, pairwise) {
    const strengths = election.matrix();
    for (const first of field) for (const second of field) {
        if (first !== second && pairwise[first][second] > pairwise[second][first]) strengths[first][second] = pairwise[first][second];
    }
    for (const middle of field) for (const first of field) if (first !== middle) {
        for (const second of field) if (second !== middle && second !== first) {
            strengths[first][second] = Math.max(strengths[first][second], Math.min(strengths[first][middle], strengths[middle][second]));
        }
    }
    const { standings, tie } = topological(election, field, (first, second) => strengths[first][second] > strengths[second][first]);
    return rankedResult(election, standings, tie, [...pairLines(election, field, strengths), `ranking: ${election.list(standings, ' > ')}`]);
}
function rankedPairs(election, field, pairwise) {
    const pairs = [], edges = election.names.map(() => election.names.map(() => false)), lines = [];
    for (const first of field) for (const second of field) if (pairwise[first][second] > pairwise[second][first]) pairs.push([first, second]);
    pairs.sort(([a, b], [c, d]) => pairwise[c][d] - pairwise[a][b] || pairwise[b][a] - pairwise[d][c] || election.tieRank[a] - election.tieRank[c] || election.tieRank[b] - election.tieRank[d]);
    for (const [first, second] of pairs) {
        const lock = !closure(field, edges)[second][first];
        if (lock) edges[first][second] = true;
        lines.push(`${lock ? 'lock' : 'skip'} ${election.names[first]}>${election.names[second]} ${pairwise[first][second]}-${pairwise[second][first]}`);
    }
    const { standings, tie } = topological(election, field, (first, second) => edges[first][second]);
    return rankedResult(election, standings, tie, lines);
}
function kemeny(election, field, pairwise) {
    const memo = new Map([[0, { score: 0, count: 1, first: [] }]]);
    function solve(mask) {
        if (memo.has(mask)) return memo.get(mask);
        let score = -1, count = 0, first = [];
        for (const candidate of field) if (mask & (1 << candidate)) {
            const rest = mask ^ (1 << candidate), suffix = solve(rest);
            const value = suffix.score + sum(field.filter(other => rest & (1 << other)).map(other => pairwise[candidate][other]));
            if (value > score) { score = value; count = suffix.count; first = [candidate]; }
            else if (value === score) { count += suffix.count; first.push(candidate); }
        }
        const result = { score, count, first };
        memo.set(mask, result);
        return result;
    }
    let mask = field.reduce((bits, candidate) => bits | (1 << candidate), 0);
    const optimal = solve(mask), standings = [];
    while (mask !== 0) {
        const candidate = election.preferred(solve(mask).first)[0];
        standings.push(candidate);
        mask ^= 1 << candidate;
    }
    return rankedResult(election, standings, optimal.first.length > 1, [`score: ${optimal.score}`, `optimal: ${optimal.count}`, `ranking: ${election.list(standings, ' > ')}`]);
}
function stv(election, field, seats) {
    if (seats >= field.length) fail('too many seats');
    const aggregate = election.aggregate(field), groups = aggregate.groups.filter(group => group.ranking.length > 0);
    const quota = Math.floor(100 * (aggregate.total - aggregate.blank) / (seats + 1)) + 1;
    const perVote = groups.map(() => 100), elected = [], history = [], lines = [`quota: ${money(quota)}`];
    let continuing = field.slice();
    for (let round = 1; ; ++round) {
        const values = election.zeros(), current = [];
        let exhausted = 0;
        groups.forEach((group, index) => {
            const candidate = group.ranking.find(candidate => continuing.includes(candidate));
            current.push(candidate);
            if (candidate === undefined) exhausted += group.votes * perVote[index];
            else values[candidate] += group.votes * perVote[index];
        });
        let line = `round ${round}: ${election.values(continuing, values, money)}; exhausted ${money(exhausted)}`;
        const ordered = election.ordered(continuing, values);
        if (continuing.length === seats - elected.length) {
            elected.push(...ordered);
            lines.push(`${line}; elected ${election.list(ordered)}`);
            break;
        }
        let removed;
        if (values[ordered[0]] >= quota) {
            removed = ordered[0];
            elected.push(removed);
            const total = values[removed], surplus = total - quota;
            current.forEach((candidate, index) => { if (candidate === removed) perVote[index] = Math.floor(perVote[index] * surplus / total); });
            line += `; elected ${election.names[removed]} (surplus ${money(surplus)})`;
        } else {
            const chosen = eliminate(election, continuing, values, history);
            removed = chosen.candidate;
            line += `; excluded ${election.names[removed]}${chosen.tie ? ' (tie)' : ''}`;
        }
        lines.push(line);
        if (elected.length === seats) break;
        history.push(values);
        continuing = continuing.filter(candidate => candidate !== removed);
    }
    return { standings: [], tie: false, lines: [...lines, `elected: ${election.list(elected)}`] };
}
function tally(election, method, field) {
    const [kind, argument] = method.split(' '), aggregate = election.aggregate(field), pairwise = aggregate.pairwise;
    switch (kind) {
        case 'PLURALITY': return scoredResult(election, field, aggregate.first, 'votes');
        case 'RUNOFF': return runoff(election, field);
        case 'IRV': return eliminationRounds(election, field, false);
        case 'COOMBS': return eliminationRounds(election, field, true);
        case 'BUCKLIN': return bucklin(election, field);
        case 'BORDA': return scoredResult(election, field, aggregate.borda, 'scores');
        case 'BALDWIN': return bordaRounds(election, field, false);
        case 'NANSON': return bordaRounds(election, field, true);
        case 'BLACK': {
            const winner = condorcetWinner(field, pairwise), ordered = election.ordered(field, aggregate.borda);
            const standings = winner === undefined ? ordered : [winner, ...ordered.filter(candidate => candidate !== winner)];
            const tie = winner === undefined && aggregate.borda[ordered[0]] === aggregate.borda[ordered[1]];
            return rankedResult(election, standings, tie, [`condorcet: ${winner === undefined ? 'NONE' : election.names[winner]}`, `scores: ${election.values(field, aggregate.borda)}`]);
        }
        case 'VETO': return scoredResult(election, field, aggregate.last, 'vetoes', true);
        case 'CONDORCET': return condorcet(election, field, pairwise);
        case 'COPELAND': {
            const scores = election.zeros(), parts = [];
            for (const candidate of field) {
                let wins = 0, draws = 0, losses = 0;
                for (const other of field) if (other !== candidate) {
                    if (pairwise[candidate][other] > pairwise[other][candidate]) ++wins;
                    else if (pairwise[candidate][other] === pairwise[other][candidate]) ++draws;
                    else ++losses;
                }
                scores[candidate] = 2 * wins + draws;
                parts.push(`${election.names[candidate]} ${Math.floor(scores[candidate] / 2)}.${scores[candidate] % 2 ? '5' : '0'} (${wins}-${draws}-${losses})`);
            }
            const standings = election.ordered(field, scores);
            return rankedResult(election, standings, scores[standings[0]] === scores[standings[1]], [`scores: ${parts.join(', ')}`]);
        }
        case 'MINIMAX': {
            const scores = election.zeros();
            for (const candidate of field) for (const other of field) if (candidate !== other) {
                const opposition = pairwise[other][candidate], support = pairwise[candidate][other];
                if (argument === 'OPPOSITION') scores[candidate] = Math.max(scores[candidate], opposition);
                else if (opposition > support) scores[candidate] = Math.max(scores[candidate], argument === 'MARGIN' ? opposition - support : opposition);
            }
            return scoredResult(election, field, scores, 'scores', true);
        }
        case 'SCHULZE': return schulze(election, field, pairwise);
        case 'RANKEDPAIRS': return rankedPairs(election, field, pairwise);
        case 'KEMENY': return kemeny(election, field, pairwise);
        case 'APPROVAL': return scoredResult(election, field, aggregate.positions.map(positions => sum(positions.slice(0, Number(argument)))), 'approvals');
        case 'STV': return stv(election, field, Number(argument));
        default: throw new Error(`Unknown method ${method}`);
    }
}
function reports(election, command, args, field) {
    const aggregate = election.aggregate(field);
    switch (command) {
        case 'STATUS': {
            const withdrawn = election.names.map((_, index) => index).filter(candidate => election.withdrawn.has(candidate));
            return [`election ${election.number}`, `active: ${election.list(field)}`, `withdrawn: ${withdrawn.length ? election.list(withdrawn) : 'none'}`, `tiebreak: ${election.list(election.priority)}`, `ballots: ${aggregate.total} in ${election.entries.length} entries`];
        }
        case 'BALLOTS': {
            const groups = aggregate.groups.map(group => ({ votes: group.votes, notation: group.ranking.length ? election.list(group.ranking, '>') : '-' }));
            groups.sort((a, b) => b.votes - a.votes || ascii(a.notation, b.notation));
            return [`total ${aggregate.total}, blank ${aggregate.blank}, distinct ${groups.length}`, ...groups.map(group => `${group.votes} ${group.notation}`)];
        }
        case 'PROFILE': return field.map(candidate => `${election.names[candidate]}: ${aggregate.positions[candidate].join(' ')} unranked ${aggregate.total - sum(aggregate.positions[candidate])}`);
        case 'PAIRWISE': return pairLines(election, field, aggregate.pairwise);
        case 'EXHAUSTED': return eliminationRounds(election, field, false).exhausted;
        case 'RANKING':
        case 'SPOILERS': {
            if (args[0] === 'CONDORCET' || args[0] === 'STV') fail('not rankable');
            if (command === 'SPOILERS' && field.length < 3) fail('too few candidates');
            const method = args.join(' '), standings = tally(election, method, field).standings;
            if (command === 'RANKING') return [election.list(standings, ' > ')];
            const winner = standings[0], lines = [`winner: ${election.names[winner]}`];
            for (const excluded of field) if (excluded !== winner) {
                const other = tally(election, method, field.filter(candidate => candidate !== excluded)).standings[0];
                lines.push(`without ${election.names[excluded]}: ${election.names[other]}${other !== winner ? ' (changed)' : ''}`);
            }
            return lines;
        }
        case 'SUMMARY': {
            const wins = election.zeros(), lines = [];
            for (const method of summaryMethods) {
                const winner = tally(election, method, field).standings[0];
                ++wins[winner];
                lines.push(`${method}: ${election.names[winner]}`);
            }
            return [...lines, `wins: ${election.values(field, wins)}`];
        }
        case 'COMPARE': {
            const candidates = [];
            for (const name of args) {
                const candidate = election.candidate(name);
                if (election.withdrawn.has(candidate)) fail(`withdrawn candidate ${name}`);
                candidates.push(candidate);
            }
            const [first, second] = candidates;
            if (first === second) fail('same candidate');
            const a = aggregate.pairwise[first][second], b = aggregate.pairwise[second][first], ahead = [[], []];
            for (const method of summaryMethods) {
                const standings = tally(election, method, field).standings;
                ahead[standings.indexOf(first) < standings.indexOf(second) ? 0 : 1].push(method);
            }
            return [`${args[0]} ${a}, ${args[1]} ${b}, neither ${aggregate.total - a - b}`, ...args.map((name, index) => `${name} ahead: ${ahead[index].length ? ahead[index].join(', ') : 'none'}`)];
        }
        default: return tally(election, [command, ...args].join(' '), field).lines;
    }
}
class VoteCounter {
    constructor() { this.election = null; this.count = 0; }
    execute(line) {
        const [command, ...args] = line.split(' ');
        if (command === 'CANDIDATES') {
            if (args.length < 2) fail('too few candidates');
            const seen = new Set();
            for (const name of args) {
                if (seen.has(name)) fail(`duplicate candidate ${name}`);
                seen.add(name);
            }
            this.election = new Election(args, ++this.count);
            return [`election ${this.count}: ${args.length} candidates`];
        }
        const election = this.election;
        if (election === null) fail('no election');
        const field = election.active();
        switch (command) {
            case 'BALLOT': {
                const ranking = args[1] === '-' ? [] : election.nameList(args[1].split('>'));
                election.entries.push([{ votes: Number(args[0]), ranking }]);
                election.cache.clear();
                return [];
            }
            case 'RANDOM': {
                let state = Number(args[1]);
                const draw = () => { state = 48271 * state % 2147483647; return state; };
                const groups = [];
                for (let group = 0; group < Number(args[0]); ++group) {
                    const ranking = field.slice();
                    for (let index = ranking.length - 1; index >= 1; --index) {
                        const other = draw() % (index + 1);
                        [ranking[index], ranking[other]] = [ranking[other], ranking[index]];
                    }
                    groups.push({ votes: 1, ranking: ranking.slice(0, draw() % ranking.length + 1) });
                }
                election.entries.push(groups);
                election.cache.clear();
                return [];
            }
            case 'UNDO':
                if (election.entries.length === 0) fail('nothing to undo');
                election.entries.pop();
                election.cache.clear();
                return [];
            case 'WITHDRAW':
            case 'RESTORE': {
                const candidate = election.candidate(args[0]);
                if (command === 'WITHDRAW') {
                    if (election.withdrawn.has(candidate)) fail(`already withdrawn ${args[0]}`);
                    if (field.length <= 2) fail('too few candidates');
                    election.withdrawn.add(candidate);
                } else {
                    if (!election.withdrawn.has(candidate)) fail(`not withdrawn ${args[0]}`);
                    election.withdrawn.delete(candidate);
                }
                return [];
            }
            case 'TIEBREAK': {
                const order = election.nameList(args);
                if (order.length !== election.names.length) fail('incomplete tiebreak');
                election.setPriority(order);
                return [];
            }
            default:
                if (command !== 'STATUS' && election.entries.length === 0) fail('no ballots');
                return [`[${line}]`, ...reports(election, command, args, field)];
        }
    }
}

const input = fs.readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const counter = new VoteCounter(), output = [];
for (let index = 1; index <= Number(input[0]); ++index) {
    try { output.push(...counter.execute(input[index])); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        output.push(`ERROR ${error.message}`);
    }
}
process.stdout.write(output.join('\n') + '\n');
