const fs = require('fs');

class CommandError extends Error {}
function fail(reason) { throw new CommandError(reason); }
function sequence(prefix, count) { return Array.from({ length: count }, (_, i) => prefix + i); }
function ordered(values) { return [...values].sort((a, b) => a - b); }
function subsetKey(values) { return ordered(values).join(','); }
function stripRight(text) {
    let end = text.length;
    while (end > 0 && text[end - 1] === ' ') end--;
    return text.slice(0, end);
}

class Automaton {
    constructor(kind, names, alphabet, start, accepting = []) {
        this.kind = kind;
        this.names = [...names];
        this.alphabet = [...alphabet].sort();
        this.start = start;
        this.accepting = new Set(accepting);
        this.rows = names.map(() => new Map());
        this.closures = null;
        this.determinized = null;
    }
    add(from, symbol, to) {
        if (!this.rows[from].has(symbol)) this.rows[from].set(symbol, new Set());
        this.rows[from].get(symbol).add(to);
    }
    targets(from, symbol) { return this.rows[from].get(symbol) || new Set(); }
    delta(from, symbol) { return this.targets(from, symbol).values().next().value; }
    triples() {
        const result = [];
        for (let p = 0; p < this.names.length; p++) {
            for (const symbol of [...this.alphabet, 'e']) {
                for (const q of ordered(this.targets(p, symbol))) result.push([p, symbol, q]);
            }
        }
        return result;
    }
    summary(name) {
        let transitions = 0;
        for (const row of this.rows) for (const values of row.values()) transitions += values.size;
        return `${this.kind} ${name}: alphabet=${this.alphabet.join('')} states=${this.names.length} accepting=${this.accepting.size} transitions=${transitions}`;
    }
    notation(states) { return '{' + ordered(states).map(i => this.names[i]).join(',') + '}'; }
    list(states) { return ordered(states).map(i => this.names[i]).join(',') || 'none'; }
    closure(states) {
        if (this.closures === null) {
            this.closures = this.names.map((_, start) => {
                const seen = new Set([start]), queue = [start];
                for (let i = 0; i < queue.length; i++) for (const q of this.targets(queue[i], 'e')) {
                    if (!seen.has(q)) { seen.add(q); queue.push(q); }
                }
                return seen;
            });
        }
        const result = new Set();
        for (const p of states) for (const q of this.closures[p]) result.add(q);
        return result;
    }
    destination(states, symbol) {
        const moved = new Set();
        for (const p of states) for (const q of this.targets(p, symbol)) moved.add(q);
        return this.closure(moved);
    }
    accepts(states) { for (const p of states) if (this.accepting.has(p)) return true; return false; }
}

function determinize(source) {
    if (source.determinized !== null) return source.determinized;
    const sets = [source.closure([source.start])], indices = new Map([[subsetKey(sets[0]), 0]]), transitions = [];
    for (let i = 0; i < sets.length; i++) for (const symbol of source.alphabet) {
        const next = source.destination(sets[i], symbol), key = subsetKey(next);
        if (!indices.has(key)) { indices.set(key, sets.length); sets.push(next); }
        transitions.push([i, symbol, indices.get(key)]);
    }
    const result = new Automaton('DFA', sequence('D', sets.length), source.alphabet, 0,
        sets.flatMap((set, i) => source.accepts(set) ? [i] : []));
    for (const [p, symbol, q] of transitions) result.add(p, symbol, q);
    source.determinized = { automaton: result, sets };
    return source.determinized;
}

function graphReach(source, reverse = false) {
    const edges = source.names.map(() => new Set());
    for (const [p, , q] of source.triples()) edges[reverse ? q : p].add(reverse ? p : q);
    const seen = new Set(reverse ? source.accepting : [source.start]), queue = [...seen];
    for (let i = 0; i < queue.length; i++) for (const q of edges[queue[i]]) {
        if (!seen.has(q)) { seen.add(q); queue.push(q); }
    }
    return seen;
}

function minimize(source) {
    const reachable = graphReach(source), states = ordered(reachable);
    let blocks = [states.filter(p => source.accepting.has(p)), states.filter(p => !source.accepting.has(p))]
        .filter(block => block.length).sort((a, b) => a[0] - b[0]);
    const rounds = [blocks];
    while (true) {
        const membership = new Map();
        blocks.forEach((block, i) => block.forEach(p => membership.set(p, i)));
        const groups = new Map();
        for (const p of states) {
            const key = [membership.get(p), ...source.alphabet.map(symbol => membership.get(source.delta(p, symbol)))].join(',');
            if (!groups.has(key)) groups.set(key, []);
            groups.get(key).push(p);
        }
        const next = [...groups.values()];
        if (next.length === blocks.length) break;
        blocks = next;
        rounds.push(blocks);
    }
    const membership = new Map();
    blocks.forEach((block, i) => block.forEach(p => membership.set(p, i)));
    const order = [membership.get(source.start)], indices = new Map([[order[0], 0]]), transitions = [];
    for (let i = 0; i < order.length; i++) for (const symbol of source.alphabet) {
        const next = membership.get(source.delta(blocks[order[i]][0], symbol));
        if (!indices.has(next)) { indices.set(next, order.length); order.push(next); }
        transitions.push([i, symbol, indices.get(next)]);
    }
    const result = new Automaton('DFA', sequence('M', order.length), source.alphabet, 0,
        order.flatMap((block, i) => source.accepting.has(blocks[block][0]) ? [i] : []));
    for (const [p, symbol, q] of transitions) result.add(p, symbol, q);
    return { automaton: result, rounds, blocks: order.map(i => blocks[i]), unreachable: source.names.flatMap((_, i) => reachable.has(i) ? [] : [i]) };
}

function language(source, countWords = false) {
    const dfa = determinize(source).automaton, live = graphReach(dfa, true);
    if (!live.has(dfa.start)) return { kind: 'empty', count: 0 };
    const color = new Array(dfa.names.length).fill(0), postorder = [];
    let infinite = false;
    function visit(p) {
        if (!live.has(p)) return;
        if (color[p] === 1) { infinite = true; return; }
        if (color[p] === 2) return;
        color[p] = 1;
        for (const symbol of dfa.alphabet) visit(dfa.delta(p, symbol));
        color[p] = 2;
        postorder.push(p);
    }
    visit(dfa.start);
    if (infinite) return { kind: 'infinite', count: 0 };
    if (!countWords) return { kind: 'finite', count: 0 };
    const totals = new Array(dfa.names.length).fill(0);
    for (const p of postorder) {
        totals[p] = Number(dfa.accepting.has(p));
        for (const symbol of dfa.alphabet) totals[p] += totals[dfa.delta(p, symbol)];
    }
    return { kind: 'finite', count: totals[dfa.start] };
}

function smallest(source) {
    const dfa = determinize(source).automaton, queue = [{ state: dfa.start, word: '' }], seen = new Set([dfa.start]);
    for (let i = 0; i < queue.length; i++) {
        const { state, word } = queue[i];
        if (dfa.accepting.has(state)) return word;
        for (const symbol of dfa.alphabet) {
            const next = dfa.delta(state, symbol);
            if (!seen.has(next)) { seen.add(next); queue.push({ state: next, word: word + symbol }); }
        }
    }
    return null;
}

class RegexParser {
    constructor(text) { this.text = text; this.position = 0; }
    peek() { return this.text[this.position] || ''; }
    atomStart() { return this.peek() !== '' && /[a-z0-9(]/.test(this.peek()); }
    error() { fail('syntax error at ' + (this.position + 1)); }
    atom() {
        const symbol = this.peek();
        if (symbol !== '' && /[a-z0-9]/.test(symbol)) { this.position++; return { kind: 'symbol', symbol }; }
        if (symbol === '(') {
            this.position++;
            const result = this.alternation();
            if (this.peek() !== ')') this.error();
            this.position++;
            return result;
        }
        this.error();
    }
    factor() {
        let result = this.atom();
        while (this.peek() !== '' && '*+?'.includes(this.peek())) {
            const kind = this.peek(); this.position++;
            result = { kind, child: result };
        }
        return result;
    }
    concatenation() {
        const children = [this.factor()];
        while (this.atomStart()) children.push(this.factor());
        return children.length === 1 ? children[0] : { kind: 'concat', children };
    }
    alternation() {
        const children = [this.concatenation()];
        while (this.peek() === '|') { this.position++; children.push(this.concatenation()); }
        return children.length === 1 ? children[0] : { kind: 'alternate', children };
    }
    parse() { const result = this.alternation(); if (this.position !== this.text.length) this.error(); return result; }
}

function fromRegex(alphabet, tree) {
    let count = 0;
    const transitions = [];
    function build(node) {
        if (node.kind === 'symbol') {
            const start = count++, finish = count++;
            transitions.push([start, node.symbol, finish]);
            return [start, finish];
        }
        if (node.kind === 'concat') {
            const parts = node.children.map(build);
            for (let i = 1; i < parts.length; i++) transitions.push([parts[i - 1][1], 'e', parts[i][0]]);
            return [parts[0][0], parts.at(-1)[1]];
        }
        const start = count++;
        if (node.kind === 'alternate') {
            const parts = node.children.map(build), finish = count++;
            for (const [s, f] of parts) transitions.push([start, 'e', s], [f, 'e', finish]);
            return [start, finish];
        }
        const [s, f] = build(node.child), finish = count++;
        transitions.push([start, 'e', s], [f, 'e', finish]);
        if (node.kind !== '?') transitions.push([f, 'e', s]);
        if (node.kind !== '+') transitions.push([start, 'e', finish]);
        return [start, finish];
    }
    const [start, finish] = build(tree), result = new Automaton('NFA', sequence('N', count), alphabet, start, [finish]);
    for (const [p, symbol, q] of transitions) result.add(p, symbol, q);
    return result;
}

function product(left, right, operation) {
    const pairs = [[left.start, right.start]], indices = new Map([[pairs[0].join(','), 0]]), transitions = [];
    for (let i = 0; i < pairs.length; i++) for (const symbol of left.alphabet) {
        const next = [left.delta(pairs[i][0], symbol), right.delta(pairs[i][1], symbol)], key = next.join(',');
        if (!indices.has(key)) { indices.set(key, pairs.length); pairs.push(next); }
        transitions.push([i, symbol, indices.get(key)]);
    }
    const accepting = [];
    pairs.forEach(([p, q], i) => {
        const a = left.accepting.has(p), b = right.accepting.has(q);
        if (operation === 'UNION' ? a || b : operation === 'INTERSECT' ? a && b : a && !b) accepting.push(i);
    });
    const result = new Automaton('DFA', sequence('P', pairs.length), left.alphabet, 0, accepting);
    for (const [p, symbol, q] of transitions) result.add(p, symbol, q);
    return { automaton: result, pairs };
}

function distinguishing(left, right) {
    const a = determinize(left).automaton, b = determinize(right).automaton;
    const queue = [{ p: a.start, q: b.start, word: '' }], seen = new Set([a.start + ',' + b.start]);
    for (let i = 0; i < queue.length; i++) {
        const { p, q, word } = queue[i];
        if (a.accepting.has(p) !== b.accepting.has(q)) return { word, left: a.accepting.has(p) };
        for (const symbol of a.alphabet) {
            const nextP = a.delta(p, symbol), nextQ = b.delta(q, symbol), key = nextP + ',' + nextQ;
            if (!seen.has(key)) { seen.add(key); queue.push({ p: nextP, q: nextQ, word: word + symbol }); }
        }
    }
    return null;
}

function combine(source, other, operation) {
    const count = source.names.length, extra = operation === 'CONCAT' ? other.names.length : 1;
    const offset = operation === 'CONCAT' ? 0 : 1;
    const start = operation === 'CONCAT' ? source.start : 0;
    const accepting = operation === 'REVERSE' ? [source.start + 1] : operation === 'STAR'
        ? [0, ...[...source.accepting].map(p => p + 1)] : [...other.accepting].map(p => p + count);
    const result = new Automaton('NFA', sequence('N', count + extra), source.alphabet, start, accepting);
    for (const [p, symbol, q] of source.triples()) {
        if (operation === 'REVERSE') result.add(q + 1, symbol, p + 1);
        else result.add(p + offset, symbol, q + offset);
    }
    if (operation === 'REVERSE') for (const p of source.accepting) result.add(0, 'e', p + 1);
    else if (operation === 'STAR') {
        result.add(0, 'e', source.start + 1);
        for (const p of source.accepting) result.add(p + 1, 'e', source.start + 1);
    } else {
        for (const [p, symbol, q] of other.triples()) result.add(p + count, symbol, q + count);
        for (const p of source.accepting) result.add(p, 'e', other.start + count);
    }
    return result;
}

const roles = new Map(Object.entries({
    ACCEPT: 'RO', CLOSURE: 'RO', ENUM: 'RO', COUNT: 'RO', TODFA: 'RN', EPSFREE: 'RN', REVERSE: 'RN', STAR: 'RN',
    MINIMIZE: 'DN', COMPLEMENT: 'DN', EQUIV: 'RR', UNION: 'DDN', INTERSECT: 'DDN', DIFF: 'DDN', CONCAT: 'RRN',
    EMPTY: 'R', FINITE: 'R', INFO: 'R', TABLE: 'R', SHOW: 'R', DELETE: 'R', SYNC: 'D', LIST: ''
}));

class Toolkit {
    constructor() { this.table = new Map(); }
    register(name, source, details = []) {
        this.table.set(name, source);
        return [source.summary(name), ...details];
    }
    define(kind, args) {
        if (args.length < 5) fail('wrong number of arguments');
        const [name, stateText, alphabet, startName, acceptingText, ...words] = args;
        if (this.table.has(name)) fail(name + ' already exists');
        const names = stateText.split(','), index = new Map();
        names.forEach((state, i) => { if (index.has(state)) fail('duplicate state ' + state); index.set(state, i); });
        if (!index.has(startName)) fail('unknown state ' + startName);
        const accepting = new Set();
        if (acceptingText !== '-') for (const state of acceptingText.split(',')) {
            if (!index.has(state)) fail('unknown state ' + state);
            if (accepting.has(index.get(state))) fail('duplicate state ' + state);
            accepting.add(index.get(state));
        }
        const result = new Automaton(kind, names, alphabet, index.get(startName), accepting), seen = new Set();
        for (const word of words) {
            const [p, symbol, q] = word.split(':');
            if (!index.has(p)) fail('unknown state ' + p);
            if (symbol === 'e' && kind === 'DFA') fail('epsilon transition in DFA');
            if (symbol !== 'e' && !result.alphabet.includes(symbol)) fail('unknown symbol ' + symbol);
            if (!index.has(q)) fail('unknown state ' + q);
            if (seen.has(word)) fail('duplicate transition ' + word);
            if (kind === 'DFA' && result.targets(index.get(p), symbol).size) fail('conflicting transition ' + word);
            seen.add(word);
            result.add(index.get(p), symbol, index.get(q));
        }
        if (kind === 'DFA') for (let p = 0; p < names.length; p++) for (const symbol of result.alphabet) {
            if (!result.targets(p, symbol).size) fail('missing transition ' + names[p] + ':' + symbol);
        }
        return this.register(name, result);
    }
    command(line) {
        const [command, ...args] = line.split(' ');
        if (command === 'DFA' || command === 'NFA') return this.define(command, args);
        if (command === 'REGEX') {
            if (args.length !== 3) fail('wrong number of arguments');
            const [name, alphabet, text] = args;
            if (this.table.has(name)) fail(name + ' already exists');
            for (const symbol of text) if (/[a-z0-9]/.test(symbol) && symbol !== 'e' && !alphabet.includes(symbol)) fail('unknown symbol ' + symbol);
            return this.register(name, fromRegex(alphabet, new RegexParser(text).parse()));
        }
        if (!roles.has(command)) fail('unknown command ' + command);
        const kinds = roles.get(command);
        if (args.length !== kinds.length) fail('wrong number of arguments');
        for (let i = 0; i < kinds.length; i++) if ('RD'.includes(kinds[i]) && !this.table.has(args[i])) fail('unknown automaton ' + args[i]);
        const newIndex = kinds.indexOf('N');
        if (newIndex >= 0 && this.table.has(args[newIndex])) fail(args[newIndex] + ' already exists');
        for (let i = 0; i < kinds.length; i++) if (kinds[i] === 'D' && this.table.get(args[i]).kind !== 'DFA') fail(args[i] + ' is not a DFA');
        const source = this.table.get(args[0]), other = 'RD'.includes(kinds[1] || '-') ? this.table.get(args[1]) : null;
        if (other !== null && source.alphabet.join('') !== other.alphabet.join('')) fail('alphabets differ');
        switch (command) {
            case 'LIST': return this.table.size ? [...this.table].map(([name, automaton]) => automaton.summary(name)) : ['(none)'];
            case 'DELETE': this.table.delete(args[0]); return ['deleted ' + args[0]];
            case 'ACCEPT': {
                const word = args[1] === 'e' ? '' : args[1];
                for (const symbol of word) if (!source.alphabet.includes(symbol)) fail('unknown symbol ' + symbol);
                let states = source.closure([source.start]);
                const notation = set => source.kind === 'DFA' ? source.names[[...set][0]] : source.notation(set);
                let path = notation(states);
                for (const symbol of word) { states = source.destination(states, symbol); path += ' -' + symbol + '-> ' + notation(states); }
                return [(source.accepts(states) ? 'ACCEPT ' : 'REJECT ') + path];
            }
            case 'CLOSURE': {
                const states = args[1].split(',').map(name => { const i = source.names.indexOf(name); if (i < 0) fail('unknown state ' + name); return i; });
                return [source.notation(source.closure(states))];
            }
            case 'TODFA': {
                const result = determinize(source);
                return this.register(args[1], result.automaton, result.sets.map((set, i) => '  D' + i + ' = ' + source.notation(set)));
            }
            case 'EPSFREE': {
                const result = new Automaton('NFA', source.names, source.alphabet, source.start);
                for (let p = 0; p < source.names.length; p++) {
                    const set = source.closure([p]);
                    if (source.accepts(set)) result.accepting.add(p);
                    for (const symbol of source.alphabet) for (const q of source.destination(set, symbol)) result.add(p, symbol, q);
                }
                return this.register(args[1], result);
            }
            case 'MINIMIZE': {
                const result = minimize(source), details = ['  unreachable: ' + source.list(result.unreachable)];
                result.rounds.forEach((blocks, i) => details.push('  round ' + i + ': ' + blocks.map(block => source.notation(block)).join(' ')));
                result.blocks.forEach((block, i) => details.push('  M' + i + ' = ' + source.notation(block)));
                return this.register(args[1], result.automaton, details);
            }
            case 'EQUIV': {
                const result = distinguishing(source, other);
                return [result === null ? 'EQUIVALENT' : `NOT EQUIVALENT: ${result.word || 'e'} is accepted only by ${args[result.left ? 0 : 1]}`];
            }
            case 'UNION': case 'INTERSECT': case 'DIFF': {
                const result = product(source, other, command);
                return this.register(args[2], result.automaton, result.pairs.map(([p, q], i) => `  P${i} = (${source.names[p]},${other.names[q]})`));
            }
            case 'COMPLEMENT': {
                const result = new Automaton('DFA', source.names, source.alphabet, source.start,
                    source.names.flatMap((_, i) => source.accepting.has(i) ? [] : [i]));
                for (const [p, symbol, q] of source.triples()) result.add(p, symbol, q);
                return this.register(args[1], result);
            }
            case 'REVERSE': case 'STAR': case 'CONCAT': return this.register(args[newIndex], combine(source, other, command));
            case 'COUNT': {
                const dfa = determinize(source).automaton;
                let counts = new Array(dfa.names.length).fill(0); counts[dfa.start] = 1;
                for (let length = 0; length < Number(args[1]); length++) {
                    const next = new Array(dfa.names.length).fill(0);
                    for (let p = 0; p < counts.length; p++) for (const symbol of dfa.alphabet) next[dfa.delta(p, symbol)] += counts[p];
                    counts = next;
                }
                return [String([...dfa.accepting].reduce((sum, p) => sum + counts[p], 0))];
            }
            case 'ENUM': {
                const dfa = determinize(source).automaton, accepted = [];
                let level = [{ state: dfa.start, word: '' }], total = 0;
                for (let length = 0; length <= Number(args[1]); length++) {
                    for (const item of level) if (dfa.accepting.has(item.state)) { total++; if (accepted.length < 50) accepted.push(item.word || 'e'); }
                    if (length < Number(args[1])) level = level.flatMap(item => dfa.alphabet.map(symbol => ({ state: dfa.delta(item.state, symbol), word: item.word + symbol })));
                }
                return [String(total) + (accepted.length ? ' ' + accepted.join(' ') : '') + (total > 50 ? ' ...' : '')];
            }
            case 'EMPTY': { const word = smallest(source); return [word === null ? 'EMPTY' : 'NOT EMPTY ' + (word || 'e')]; }
            case 'FINITE': { const result = language(source, true); return [result.kind === 'infinite' ? 'INFINITE' : 'FINITE ' + result.count]; }
            case 'SYNC': {
                const initial = (1 << source.names.length) - 1, seen = new Set([initial]), queue = [{ set: initial, word: '' }];
                for (let i = 0; i < queue.length; i++) {
                    const { set, word } = queue[i];
                    if ((set & (set - 1)) === 0) return [`SYNCHRONIZING ${word || 'e'} -> ${source.names[Math.log2(set)]}`];
                    for (const symbol of source.alphabet) {
                        let next = 0;
                        for (let p = 0; p < source.names.length; p++) if (set & (1 << p)) next |= 1 << source.delta(p, symbol);
                        if (!seen.has(next)) { seen.add(next); queue.push({ set: next, word: word + symbol }); }
                    }
                }
                return ['NOT SYNCHRONIZING'];
            }
            case 'INFO': {
                const epsilon = source.rows.reduce((sum, _, p) => sum + source.targets(p, 'e').size, 0);
                const deterministic = epsilon === 0 && source.rows.every((_, p) => source.alphabet.every(symbol => source.targets(p, symbol).size <= 1));
                const complete = source.rows.every((_, p) => source.alphabet.every(symbol => source.targets(p, symbol).size >= 1));
                return [source.summary(args[0]), '  epsilon transitions: ' + epsilon, '  reachable: ' + source.list(graphReach(source)),
                    '  live: ' + source.list(graphReach(source, true)), '  deterministic: ' + (deterministic ? 'yes' : 'no'),
                    '  complete: ' + (complete ? 'yes' : 'no'), '  language: ' + language(source).kind,
                    '  minimal DFA states: ' + minimize(determinize(source).automaton).automaton.names.length];
            }
            case 'TABLE': {
                const columns = [...source.alphabet];
                if (source.kind === 'NFA' && source.rows.some((_, p) => source.targets(p, 'e').size)) columns.push('e');
                const rows = [['', ...columns]];
                source.names.forEach((name, p) => rows.push([(p === source.start ? '->' : '  ') + (source.accepting.has(p) ? '*' : ' ') + name,
                    ...columns.map(symbol => source.kind === 'DFA' ? source.names[source.delta(p, symbol)] : source.targets(p, symbol).size ? source.notation(source.targets(p, symbol)) : '-')]));
                const widths = rows[0].map((_, i) => Math.max(...rows.map(row => row[i].length)));
                return rows.map(row => stripRight(row.map((cell, i) => cell.padEnd(widths[i])).join('  ')));
            }
            case 'SHOW': return [[source.kind, args[0], source.names.join(','), source.alphabet.join(''), source.names[source.start],
                ordered(source.accepting).map(p => source.names[p]).join(',') || '-', ...source.triples().map(([p, symbol, q]) => `${source.names[p]}:${symbol}:${source.names[q]}`)].join(' ')];
        }
        throw new Error('unhandled command');
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/), toolkit = new Toolkit(), output = [];
for (const line of lines.slice(1, Number(lines[0]) + 1)) {
    if (line[0] === '#') continue;
    try { output.push(...toolkit.command(line)); }
    catch (error) { if (!(error instanceof CommandError)) throw error; output.push('error: ' + error.message); }
}
process.stdout.write(output.length ? output.join('\n') + '\n' : '');
