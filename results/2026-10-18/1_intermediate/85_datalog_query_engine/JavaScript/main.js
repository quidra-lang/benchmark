const fs = require('node:fs');

class Problem extends Error {}
function fail(reason) { throw new Problem(reason); }
const reserved = new Set('not mod count sum min max retract dump why forget listing strata stats check predicates undo halt'.split(' '));
const comparisons = new Set(['=', '!=', '<', '<=', '>', '>=']);
const arithmetic = new Set(['+', '-', '*', '/', 'mod']);
function valueText(value) { return typeof value === 'bigint' ? String(value) : /^[a-z][a-zA-Z0-9_]*$/.test(value) && !reserved.has(value) ? value : '"' + value + '"'; }
function valueCompare(a, b) {
    if (typeof a === 'bigint') {
        if (typeof b !== 'bigint') return -1;
        return a < b ? -1 : a > b ? 1 : 0;
    }
    if (typeof b === 'bigint') return 1;
    return a < b ? -1 : a > b ? 1 : 0;
}
function tupleCompare(a, b) { for (let i = 0; i < a.length; i++) { const order = valueCompare(a[i], b[i]); if (order !== 0) return order; } return 0; }
function tupleKey(values) { return JSON.stringify(values.map(value => typeof value === 'bigint' ? ['integer', String(value)] : ['symbol', value])); }
function bindingKey(binding) { const names = [...binding.keys()].sort(); return JSON.stringify(names.map(name => [name, tupleKey([binding.get(name)])])); }
function lex(line) {
    const tokens = [];
    for (let i = 0; i < line.length;) {
        const c = line[i];
        if (c === ' ') { i++; continue; }
        if (c === '%') break;
        if (c === '"') {
            const end = line.indexOf('"', i + 1);
            if (end < 0) fail('unterminated string');
            tokens.push({ kind: 'string', text: line.slice(i, end + 1), value: line.slice(i + 1, end) });
            i = end + 1;
            continue;
        }
        const pair = line.slice(i, i + 2);
        if ([':-', '?-', '!=', '<=', '>='].includes(pair)) { tokens.push({ kind: pair, text: pair }); i += 2; continue; }
        if ('(),.:=<>+-*/'.includes(c)) { tokens.push({ kind: c, text: c }); i++; continue; }
        if (/[a-zA-Z0-9_]/.test(c)) {
            const start = i;
            while (i < line.length && /[a-zA-Z0-9_]/.test(line[i])) i++;
            const text = line.slice(start, i);
            if (/^[a-z]/.test(text)) tokens.push({ kind: reserved.has(text) ? text : 'name', text, value: text });
            else if (/^[A-Z]/.test(text)) tokens.push({ kind: 'variable', text });
            else if (text === '_') tokens.push({ kind: 'anonymous', text });
            else if (/^[0-9]+$/.test(text)) {
                const value = BigInt(text);
                if (value > 1000000000n) fail("integer out of range '" + text + "'");
                tokens.push({ kind: 'integer', text, value });
            } else fail("bad token '" + text + "'");
            continue;
        }
        fail("bad character '" + c + "'");
    }
    tokens.push({ kind: 'end', text: '' });
    return tokens;
}
class Parser {
    constructor(tokens) { this.tokens = tokens; this.at = 0; }
    peek(offset = 0) { return this.tokens[this.at + offset]; }
    syntax() { const token = this.peek(); fail(token.kind === 'end' ? 'syntax error at end of line' : "syntax error at '" + token.text + "'"); }
    take(kind) { if (this.peek().kind !== kind) this.syntax(); return this.tokens[this.at++]; }
    term() {
        const token = this.peek();
        if (token.kind === 'name' || token.kind === 'string' || token.kind === 'integer') {
            this.at++;
            const value = token.kind === 'integer' ? BigInt(token.text) : token.kind === 'string' ? token.text.slice(1, -1) : token.text;
            return { kind: 'constant', value };
        }
        if (token.kind === '-') { this.at++; return { kind: 'constant', value: -BigInt(this.take('integer').text) }; }
        if (token.kind === 'variable') { this.at++; return { kind: 'variable', name: token.text }; }
        if (token.kind === 'anonymous') { this.at++; return { kind: 'anonymous' }; }
        this.syntax();
    }
    atom() {
        const name = this.take('name').text, terms = [];
        if (this.peek().kind === '(') {
            this.at++; terms.push(this.term());
            while (this.peek().kind === ',') { this.at++; terms.push(this.term()); }
            this.take(')');
        }
        return { name, terms };
    }
    factor() {
        if (this.peek().kind === '(') { this.at++; const expression = this.expression(); this.take(')'); return { kind: 'parentheses', expression }; }
        return { kind: 'term', term: this.term() };
    }
    product() {
        let left = this.factor();
        while (['*', '/', 'mod'].includes(this.peek().kind)) { const operator = this.tokens[this.at++].kind; left = { kind: 'operation', operator, left, right: this.factor() }; }
        return left;
    }
    expression() {
        let left = this.product();
        while (this.peek().kind === '+' || this.peek().kind === '-') { const operator = this.tokens[this.at++].kind; left = { kind: 'operation', operator, left, right: this.product() }; }
        return left;
    }
    literal() {
        if (this.peek().kind === 'not') { this.at++; return { kind: 'atom', atom: this.atom(), negative: true }; }
        if (this.peek().kind === 'name' && !comparisons.has(this.peek(1).kind) && !arithmetic.has(this.peek(1).kind)) return { kind: 'atom', atom: this.atom(), negative: false };
        const left = this.expression(), operator = this.peek().kind;
        if (!comparisons.has(operator)) this.syntax();
        this.at++;
        return { kind: 'comparison', left, operator, right: this.expression() };
    }
    body() {
        const literals = [this.literal()];
        while (this.peek().kind === ',') { this.at++; literals.push(this.literal()); }
        return literals;
    }
    statement() {
        let result;
        const kind = this.peek().kind;
        if (kind === 'name' || kind === ':-') {
            const head = kind === 'name' ? this.atom() : null;
            let body = [];
            if (this.peek().kind === ':-') { this.at++; body = this.body(); }
            result = { kind: 'clause', head, body };
        } else if (kind === '?-') {
            this.at++;
            let aggregate = '', variable = '';
            if (['count', 'sum', 'min', 'max'].includes(this.peek().kind)) {
                aggregate = this.tokens[this.at++].kind;
                if (aggregate !== 'count') { variable = this.take('variable').text; this.take(':'); }
            }
            result = { kind: 'query', aggregate, variable, body: this.body() };
        } else if (kind === 'retract' || kind === 'why') {
            this.at++; result = { kind: 'atom-command', command: kind, atom: this.atom() };
        } else if (kind === 'dump' || kind === 'listing') {
            this.at++;
            const name = kind === 'dump' || this.peek().kind === 'name' ? this.take('name').text : null;
            result = { kind: 'named-command', command: kind, name };
        } else if (kind === 'forget') {
            this.at++; result = { kind: 'forget', number: Number(this.take('integer').text) };
        } else if (['strata', 'stats', 'check', 'predicates', 'undo', 'halt'].includes(kind)) {
            this.at++; result = { kind: 'simple', command: kind };
        } else this.syntax();
        this.take('.'); this.take('end');
        return result;
    }
}
function expressionTerms(expression) { return expression.kind === 'term' ? [expression.term] : expression.kind === 'parentheses' ? expressionTerms(expression.expression) : [...expressionTerms(expression.left), ...expressionTerms(expression.right)]; }
function literalTerms(literal) { return literal.kind === 'atom' ? literal.atom.terms : [...expressionTerms(literal.left), ...expressionTerms(literal.right)]; }
function allTerms(head, body) { return [...(head === null ? [] : head.terms), ...body.flatMap(literalTerms)]; }
function variables(terms) { return [...new Set(terms.filter(term => term.kind === 'variable').map(term => term.name))]; }
function termValue(term, binding) { return term.kind === 'constant' ? term.value : binding.get(term.name); }
function termText(term, binding = null) { return term.kind === 'constant' ? valueText(term.value) : term.kind === 'anonymous' ? '_' : binding === null ? term.name : valueText(binding.get(term.name)); }
function atomText(atom, binding = null) { return atom.name + (atom.terms.length ? '(' + atom.terms.map(term => termText(term, binding)).join(', ') + ')' : ''); }
function tupleText(name, values) { return name + (values.length ? '(' + values.map(valueText).join(', ') + ')' : ''); }
function expressionText(expression, binding = null) {
    if (expression.kind === 'term') return termText(expression.term, binding);
    if (expression.kind === 'parentheses') return '(' + expressionText(expression.expression, binding) + ')';
    return expressionText(expression.left, binding) + ' ' + expression.operator + ' ' + expressionText(expression.right, binding);
}
function literalText(literal, binding = null) { return literal.kind === 'atom' ? (literal.negative ? 'not ' : '') + atomText(literal.atom, binding) : expressionText(literal.left, binding) + ' ' + literal.operator + ' ' + expressionText(literal.right, binding); }
function ruleText(head, body) { return (head === null ? ':- ' : atomText(head) + ' :- ') + body.map(literal => literalText(literal)).join(', ') + '.'; }
function expressionValue(expression, binding) {
    if (expression.kind === 'term') return termValue(expression.term, binding);
    if (expression.kind === 'parentheses') return expressionValue(expression.expression, binding);
    const a = expressionValue(expression.left, binding), b = expressionValue(expression.right, binding);
    if (typeof a !== 'bigint' || typeof b !== 'bigint') return null;
    switch (expression.operator) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        default: {
            if (b === 0n) return null;
            const quotient = a / b, q = a % b !== 0n && (a < 0n) !== (b < 0n) ? quotient - 1n : quotient;
            return expression.operator === '/' ? q : a - b * q;
        }
    }
}
function comparisonHolds(literal, binding) {
    const a = expressionValue(literal.left, binding), b = expressionValue(literal.right, binding);
    if (a === null || b === null) return false;
    if (literal.operator === '=') return a === b;
    if (literal.operator === '!=') return a !== b;
    if (typeof a !== 'bigint' || typeof b !== 'bigint') return false;
    return literal.operator === '<' ? a < b : literal.operator === '<=' ? a <= b : literal.operator === '>' ? a > b : a >= b;
}
function match(atom, values, binding) {
    const next = new Map(binding);
    for (let i = 0; i < atom.terms.length; i++) {
        const term = atom.terms[i], value = values[i];
        if (term.kind === 'constant') { if (term.value !== value) return null; }
        else if (term.kind === 'variable') { if (next.has(term.name) && next.get(term.name) !== value) return null; next.set(term.name, value); }
    }
    return next;
}
function solutions(body, data, before = Infinity) {
    const positives = body.filter(literal => literal.kind === 'atom' && !literal.negative).map(literal => literal.atom);
    const filters = body.filter(literal => literal.kind === 'comparison' || literal.negative);
    const bound = new Set(), ordered = [];
    while (positives.length > 0) {
        positives.sort((a, b) => {
            const score = (atom) => atom.terms.filter(term => term.kind === 'constant' || term.kind === 'variable' && bound.has(term.name)).length;
            return score(b) - score(a) || data.get(a.name).size - data.get(b.name).size;
        });
        const atom = positives.shift();
        ordered.push({ atom, tuples: [...data.get(atom.name).values()].filter(tuple => tuple.round < before) });
        for (const name of variables(atom.terms)) bound.add(name);
    }
    function accepts(binding) {
        for (const literal of filters) if (variables(literalTerms(literal)).every(name => binding.has(name))) {
            if (literal.kind === 'comparison') { if (!comparisonHolds(literal, binding)) return false; }
            else if ([...data.get(literal.atom.name).values()].some(tuple => match(literal.atom, tuple.values, binding) !== null)) return false;
        }
        return true;
    }
    const answers = new Map();
    function visit(index, binding) {
        if (index === ordered.length) { if (accepts(binding)) answers.set(bindingKey(binding), binding); return; }
        const { atom, tuples } = ordered[index], seen = new Set();
        for (const tuple of tuples) {
            const candidate = match(atom, tuple.values, binding);
            if (candidate === null || !accepts(candidate)) continue;
            const key = bindingKey(candidate);
            if (seen.has(key)) continue;
            seen.add(key); visit(index + 1, candidate);
        }
    }
    visit(0, new Map());
    return [...answers.values()];
}
function assignment(predicates, rules) {
    const levels = new Map([...predicates.keys()].map(name => [name, 0]));
    for (let iteration = 0; iteration < predicates.size; iteration++) {
        let changed = false;
        for (const rule of rules) if (rule.head !== null) for (const literal of rule.body) if (literal.kind === 'atom') {
            const level = levels.get(literal.atom.name) + (literal.negative ? 1 : 0);
            if (level > levels.get(rule.head.name)) { levels.set(rule.head.name, level); changed = true; }
        }
        if (!changed) return levels;
        if (iteration === predicates.size - 1) return null;
    }
    return levels;
}

class Engine {
    constructor() { this.predicates = new Map(); this.facts = new Map(); this.rules = []; this.history = []; this.nextRule = 1; this.cached = null; }
    save(line) { this.history.push({ line, predicates: new Map(this.predicates), facts: new Map([...this.facts].map(([name, tuples]) => [name, new Map(tuples)])), rules: [...this.rules] }); }
    predicateCheck(atoms, clauses) {
        const predicates = new Map(this.predicates);
        for (const atom of atoms) {
            if (!predicates.has(atom.name)) { if (!clauses) fail('unknown predicate ' + atom.name); predicates.set(atom.name, atom.terms.length); }
            else if (predicates.get(atom.name) !== atom.terms.length) fail(`arity mismatch for ${atom.name}: expected ${predicates.get(atom.name)}, got ${atom.terms.length}`);
        }
        return predicates;
    }
    safety(head, body, aggregate = '') {
        if (head !== null && head.terms.some(term => term.kind === 'anonymous')) fail('anonymous variable in head');
        for (const literal of body) if (literal.kind === 'comparison' && literalTerms(literal).some(term => term.kind === 'anonymous')) fail('anonymous variable in comparison');
        const bound = new Set(body.filter(literal => literal.kind === 'atom' && !literal.negative).flatMap(literal => variables(literal.atom.terms)));
        const required = head === null ? aggregate ? [aggregate] : [] : variables(head.terms);
        for (const literal of body) if (literal.kind === 'comparison' || literal.negative) required.push(...variables(literalTerms(literal)));
        for (const variable of required) if (!bound.has(variable)) fail('unsafe variable ' + variable);
    }
    register(statement, line) {
        const { head, body } = statement, atoms = [...(head === null ? [] : [head]), ...body.filter(literal => literal.kind === 'atom').map(literal => literal.atom)];
        const predicates = this.predicateCheck(atoms, true);
        this.safety(head, body);
        if (head !== null && body.length === 0) {
            const values = head.terms.map(term => term.value), key = tupleKey(values);
            if (this.facts.get(head.name)?.has(key)) return [];
            this.save(line); this.predicates = predicates;
            for (const name of predicates.keys()) if (!this.facts.has(name)) this.facts.set(name, new Map());
            this.facts.get(head.name).set(key, values); this.cached = null;
            return [];
        }
        const text = ruleText(head, body), duplicate = this.rules.find(rule => ruleText(rule.head, rule.body) === text);
        if (duplicate !== undefined) fail('duplicate of rule ' + duplicate.number);
        const rule = { head, body, number: this.nextRule };
        if (head !== null && assignment(predicates, [...this.rules, rule]) === null) fail('negative cycle through ' + head.name);
        this.save(line); this.predicates = predicates;
        for (const name of predicates.keys()) if (!this.facts.has(name)) this.facts.set(name, new Map());
        this.rules.push(rule); this.nextRule++; this.cached = null;
        const counts = new Map();
        for (const term of allTerms(head, body)) if (term.kind === 'variable') counts.set(term.name, (counts.get(term.name) ?? 0) + 1);
        return [...counts].filter(([, count]) => count === 1).map(([name]) => `WARNING line ${line}: singleton variable ${name}`);
    }
    model() {
        if (this.cached !== null) return this.cached;
        const levels = assignment(this.predicates, this.rules), maximum = Math.max(0, ...levels.values());
        const data = new Map([...this.predicates.keys()].map(name => [name, new Map([...this.facts.get(name)].map(([key, values]) => [key, { values, round: 0, rule: 0 }]))]));
        const rounds = Array(maximum + 1).fill(0), added = Array(maximum + 1).fill(0);
        let serial = 0;
        for (let stratum = 0; stratum <= maximum; stratum++) {
            const rules = this.rules.filter(rule => rule.head !== null && levels.get(rule.head.name) === stratum).sort((a, b) => a.number - b.number);
            while (true) {
                const pending = new Map();
                for (const rule of rules) for (const binding of solutions(rule.body, data)) {
                    const values = rule.head.terms.map(term => termValue(term, binding)), key = tupleKey(values), name = rule.head.name;
                    if (data.get(name).has(key)) continue;
                    if (!pending.has(name)) pending.set(name, new Map());
                    if (!pending.get(name).has(key)) pending.get(name).set(key, { values, round: serial + 1, rule: rule.number });
                }
                let count = 0;
                for (const [name, tuples] of pending) for (const [key, tuple] of tuples) { data.get(name).set(key, tuple); count++; }
                if (count === 0) break;
                serial++; rounds[stratum]++; added[stratum] += count;
            }
        }
        this.cached = { data, levels, maximum, rounds, added };
        return this.cached;
    }
    answers(body, model) {
        const names = variables(body.flatMap(literalTerms));
        const rows = solutions(body, model.data).map(binding => names.map(name => binding.get(name))).sort(tupleCompare);
        return { names, rows };
    }
    answerText(names, row) { return names.map((name, i) => name + ' = ' + valueText(row[i])).join(', '); }
    proof(name, tuple, depth, model, output) {
        const indent = '  '.repeat(depth), text = tupleText(name, tuple.values);
        if (tuple.round === 0) { output.push(indent + text + ' [fact]'); return; }
        for (const rule of this.rules.filter(rule => rule.head !== null && rule.head.name === name).sort((a, b) => a.number - b.number)) {
            const names = variables(allTerms(rule.head, rule.body));
            const candidates = solutions(rule.body, model.data, tuple.round).filter(binding => tupleKey(rule.head.terms.map(term => termValue(term, binding))) === tupleKey(tuple.values));
            if (candidates.length === 0) continue;
            candidates.sort((a, b) => tupleCompare(names.map(name => a.get(name)), names.map(name => b.get(name))));
            const binding = candidates[0]; output.push(indent + text + ` [rule ${rule.number}]`);
            for (const literal of rule.body) {
                if (literal.kind === 'atom' && !literal.negative) {
                    const tuples = [...model.data.get(literal.atom.name).values()].filter(other => other.round < tuple.round && match(literal.atom, other.values, binding) !== null).sort((a, b) => tupleCompare(a.values, b.values));
                    this.proof(literal.atom.name, tuples[0], depth + 1, model, output);
                } else output.push(indent + '  ' + literalText(literal, binding));
            }
            return;
        }
    }
    recursive(name) {
        const visited = new Set();
        const visit = current => {
            for (const rule of this.rules) if (rule.head !== null && rule.head.name === current) for (const literal of rule.body) if (literal.kind === 'atom') {
                const next = literal.atom.name;
                if (next === name) return true;
                if (!visited.has(next)) { visited.add(next); if (visit(next)) return true; }
            }
            return false;
        };
        return visit(name);
    }
    process(statement, line) {
        if (statement.kind === 'clause') return this.register(statement, line);
        if (statement.kind === 'query') {
            this.predicateCheck(statement.body.filter(literal => literal.kind === 'atom').map(literal => literal.atom), false);
            this.safety(null, statement.body, statement.variable);
            const { names, rows } = this.answers(statement.body, this.model());
            if (statement.aggregate === 'count') return [String(rows.length)];
            if (statement.aggregate === 'sum') {
                const index = names.indexOf(statement.variable); let total = 0n;
                for (const row of rows) { if (typeof row[index] !== 'bigint') fail('non-integer value in sum'); total += row[index]; }
                return [String(total)];
            }
            if (statement.aggregate === 'min' || statement.aggregate === 'max') {
                if (rows.length === 0) return ['no answers'];
                const index = names.indexOf(statement.variable), values = rows.map(row => row[index]).sort(valueCompare);
                return [valueText(statement.aggregate === 'min' ? values[0] : values[values.length - 1])];
            }
            if (names.length === 0) return [rows.length > 0 ? 'true.' : 'false.'];
            return [...rows.map(row => this.answerText(names, row)), `${rows.length} ${rows.length === 1 ? 'answer' : 'answers'}`];
        }
        if (statement.kind === 'atom-command') {
            const atom = statement.atom; this.predicateCheck([atom], false);
            if (statement.command === 'retract') {
                const facts = this.facts.get(atom.name), keys = [...facts].filter(([, tuple]) => match(atom, tuple, new Map()) !== null).map(([key]) => key);
                if (keys.length === 0) fail('no matching facts');
                this.save(line); for (const key of keys) facts.delete(key); this.cached = null;
                return [`${keys.length} ${keys.length === 1 ? 'fact' : 'facts'} retracted`];
            }
            if (atom.terms.some(term => term.kind !== 'constant')) fail('why needs a ground atom');
            const model = this.model(), tuple = model.data.get(atom.name).get(tupleKey(atom.terms.map(term => term.value)));
            if (tuple === undefined) return ['false.'];
            const output = []; this.proof(atom.name, tuple, 0, model, output); return output;
        }
        if (statement.kind === 'forget') {
            const index = this.rules.findIndex(rule => rule.number === statement.number);
            if (index < 0) fail('no rule ' + statement.number);
            this.save(line); this.rules.splice(index, 1); this.cached = null; return [];
        }
        if (statement.kind === 'named-command') {
            if (statement.name !== null && !this.predicates.has(statement.name)) fail('unknown predicate ' + statement.name);
            if (statement.command === 'listing') {
                const rules = this.rules.filter(rule => statement.name === null || rule.head !== null && rule.head.name === statement.name).sort((a, b) => a.number - b.number);
                return rules.length ? rules.map(rule => rule.number + ': ' + ruleText(rule.head, rule.body)) : ['no rules'];
            }
            const tuples = [...this.model().data.get(statement.name).values()].sort((a, b) => tupleCompare(a.values, b.values));
            return [...tuples.map(tuple => tupleText(statement.name, tuple.values) + '.'), `${tuples.length} ${tuples.length === 1 ? 'tuple' : 'tuples'}`];
        }
        if (statement.command === 'undo') {
            const snapshot = this.history.pop();
            if (snapshot === undefined) fail('nothing to undo');
            this.predicates = snapshot.predicates; this.facts = snapshot.facts; this.rules = snapshot.rules; this.cached = null;
            return ['undid line ' + snapshot.line];
        }
        const model = this.model(), output = [];
        if (statement.command === 'strata') {
            if (this.predicates.size === 0) return ['no predicates'];
            for (let level = 0; level <= model.maximum; level++) output.push(`stratum ${level}: ` + [...this.predicates.keys()].filter(name => model.levels.get(name) === level).sort().map(name => name + (this.recursive(name) ? '*' : '')).join(', '));
        } else if (statement.command === 'stats') {
            let facts = 0, tuples = 0;
            for (const registered of this.facts.values()) facts += registered.size;
            for (const derived of model.data.values()) tuples += derived.size;
            const rules = this.rules.filter(rule => rule.head !== null).sort((a, b) => a.number - b.number);
            output.push(`facts ${facts}, rules ${rules.length}, constraints ${this.rules.length - rules.length}, tuples ${tuples}`);
            if (this.predicates.size > 0) for (let level = 0; level <= model.maximum; level++) output.push(`stratum ${level}: rounds ${model.rounds[level]}, new ${model.added[level]}`);
            for (const rule of rules) { let count = 0; for (const predicate of model.data.values()) for (const tuple of predicate.values()) if (tuple.rule === rule.number) count++; output.push(`rule ${rule.number}: new ${count}`); }
        } else if (statement.command === 'predicates') {
            if (this.predicates.size === 0) return ['no predicates'];
            for (const name of [...this.predicates.keys()].sort()) output.push(`${name}/${this.predicates.get(name)}: facts ${this.facts.get(name).size}, rules ${this.rules.filter(rule => rule.head !== null && rule.head.name === name).length}, tuples ${model.data.get(name).size}`);
        } else if (statement.command === 'check') {
            const constraints = this.rules.filter(rule => rule.head === null).sort((a, b) => a.number - b.number);
            if (constraints.length === 0) return ['no constraints'];
            for (const constraint of constraints) {
                const { names, rows } = this.answers(constraint.body, model);
                output.push(`constraint ${constraint.number}: ` + (rows.length ? `${rows.length} ${rows.length === 1 ? 'violation' : 'violations'}` : 'ok'));
                if (names.length > 0) for (const row of rows) output.push('  ' + this.answerText(names, row));
            }
        }
        return output;
    }
}

const engine = new Engine(), output = [];
let lineNumber = 0;
for (const line of fs.readFileSync(0, 'utf8').split(/\r?\n/)) {
    lineNumber++;
    try {
        const tokens = lex(line);
        if (tokens.length === 1) continue;
        const statement = new Parser(tokens).statement();
        if (statement.kind === 'simple' && statement.command === 'halt') break;
        output.push(...engine.process(statement, lineNumber));
    } catch (error) {
        if (!(error instanceof Problem)) throw error;
        output.push(`ERROR line ${lineNumber}: ${error.message}`);
    }
}
if (output.length > 0) process.stdout.write(output.join('\n') + '\n');
