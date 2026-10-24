const fs = require('node:fs');

class Problem extends Error {}
function fail(reason) { throw new Problem(reason); }
const precedence = new Map([['<->', 1], ['->', 2], ['|', 3], ['^', 4], ['&', 5]]);
function variable(name) { return { kind: 'variable', name }; }
function constant(value) { return { kind: 'constant', value }; }
function negate(child) { return { kind: 'not', child }; }
function binary(operator, left, right) { return { kind: 'binary', operator, left, right }; }
function notation(node) {
    if (node.kind === 'variable') return node.name;
    if (node.kind === 'constant') return String(node.value);
    if (node.kind === 'not') return '~' + (node.child.kind === 'binary' ? '(' + notation(node.child) + ')' : notation(node.child));
    const level = precedence.get(node.operator);
    const left = node.left.kind === 'binary' && (precedence.get(node.left.operator) < level || node.operator === '->' && node.left.operator === '->');
    const right = node.right.kind === 'binary' && (precedence.get(node.right.operator) < level || node.operator === node.right.operator && node.operator !== '->');
    return (left ? '(' + notation(node.left) + ')' : notation(node.left)) + ' ' + node.operator + ' ' + (right ? '(' + notation(node.right) + ')' : notation(node.right));
}
function formulaVariables(node) { return node.kind === 'variable' ? [node.name] : node.kind === 'constant' ? [] : node.kind === 'not' ? formulaVariables(node.child) : [...formulaVariables(node.left), ...formulaVariables(node.right)]; }
function variables(nodes) { return [...new Set(nodes.flatMap(formulaVariables))].sort(); }
function measure(node) {
    if (node.kind === 'variable' || node.kind === 'constant') return { size: 1, depth: 1 };
    if (node.kind === 'not') { const child = measure(node.child); return { size: child.size + 1, depth: child.depth + 1 }; }
    const left = measure(node.left), right = measure(node.right);
    return { size: left.size + right.size + 1, depth: Math.max(left.depth, right.depth) + 1 };
}
function parseFormula(text, start, definitions) {
    const tokens = [];
    for (let i = 0; i < text.length;) {
        const c = text[i], position = start + i;
        if (c === ' ') { i++; continue; }
        if (text.startsWith('<->', i)) { tokens.push({ text: '<->', position }); i += 3; continue; }
        if (text.startsWith('->', i)) { tokens.push({ text: '->', position }); i += 2; continue; }
        if (c >= 'a' && c <= 'z') {
            const begin = i++;
            while (i < text.length && /[a-z0-9]/.test(text[i])) i++;
            tokens.push({ text: text.slice(begin, i), position }); continue;
        }
        if (/[A-Z01~&^|()]/.test(c)) { tokens.push({ text: c, position }); i++; continue; }
        fail(`invalid character '${c}' at ${position}`);
    }
    tokens.push({ text: '', position: start + text.length });
    let at = 0;
    const unexpected = () => { const token = tokens[at]; fail(token.text === '' ? 'unexpected end of formula at ' + token.position : `unexpected '${token.text}' at ${token.position}`); };
    function unary() {
        const token = tokens[at];
        if (token.text === '~') { at++; return negate(unary()); }
        if (token.text === '(') { at++; const result = expression(1); if (tokens[at].text !== ')') unexpected(); at++; return result; }
        if (/^[A-Z]$/.test(token.text)) { at++; return variable(token.text); }
        if (token.text === '0' || token.text === '1') { at++; return constant(Number(token.text)); }
        if (/^[a-z]/.test(token.text)) {
            at++;
            const definition = definitions.get(token.text);
            if (definition === undefined) fail(`undefined name '${token.text}' at ${token.position}`);
            return definition;
        }
        unexpected();
    }
    function expression(minimum) {
        let left = unary();
        while (precedence.has(tokens[at].text) && precedence.get(tokens[at].text) >= minimum) {
            const operator = tokens[at++].text, level = precedence.get(operator);
            left = binary(operator, left, expression(level + (operator === '->' ? 0 : 1)));
        }
        return left;
    }
    const result = expression(1);
    if (tokens[at].text !== '') unexpected();
    return result;
}
function equal(a, b) {
    if (a === b) return true;
    if (a.kind !== b.kind) return false;
    if (a.kind === 'variable' && b.kind === 'variable') return a.name === b.name;
    if (a.kind === 'constant' && b.kind === 'constant') return a.value === b.value;
    if (a.kind === 'not' && b.kind === 'not') return equal(a.child, b.child);
    return a.kind === 'binary' && b.kind === 'binary' && a.operator === b.operator && equal(a.left, b.left) && equal(a.right, b.right);
}
function reducedNegation(a) { return a.kind === 'constant' ? constant(1 - a.value) : a.kind === 'not' ? a.child : negate(a); }
function simplifyBinary(operator, a, b) {
    const is = (node, value) => node.kind === 'constant' && node.value === value;
    const same = equal(a, b), complementary = a.kind === 'not' && equal(a.child, b) || b.kind === 'not' && equal(a, b.child);
    switch (operator) {
        case '&':
            if (is(a, 0) || is(b, 0)) return constant(0);
            if (is(a, 1)) return b; if (is(b, 1)) return a;
            if (same) return a; if (complementary) return constant(0); break;
        case '|':
            if (is(a, 1) || is(b, 1)) return constant(1);
            if (is(a, 0)) return b; if (is(b, 0)) return a;
            if (same) return a; if (complementary) return constant(1); break;
        case '^':
            if (is(a, 0)) return b; if (is(b, 0)) return a;
            if (is(a, 1)) return reducedNegation(b); if (is(b, 1)) return reducedNegation(a);
            if (same) return constant(0); if (complementary) return constant(1); break;
        case '->':
            if (is(a, 0) || is(b, 1)) return constant(1);
            if (is(a, 1)) return b; if (is(b, 0)) return reducedNegation(a);
            if (same) return constant(1); if (complementary) return b; break;
        case '<->':
            if (is(a, 1)) return b; if (is(b, 1)) return a;
            if (is(a, 0)) return reducedNegation(b); if (is(b, 0)) return reducedNegation(a);
            if (same) return constant(1); if (complementary) return constant(0); break;
    }
    return binary(operator, a, b);
}
function simplify(node, replacements = new Map()) {
    if (node.kind === 'constant') return node;
    if (node.kind === 'variable') return replacements.has(node.name) ? constant(replacements.get(node.name)) : node;
    if (node.kind === 'not') return reducedNegation(simplify(node.child, replacements));
    return simplifyBinary(node.operator, simplify(node.left, replacements), simplify(node.right, replacements));
}
const nnfCache = new WeakMap();
function nnf(node, positive = true) {
    if (!nnfCache.has(node)) nnfCache.set(node, new Map());
    const bySign = nnfCache.get(node);
    if (bySign.has(positive)) return bySign.get(positive);
    const result = nnfCompute(node, positive);
    bySign.set(positive, result);
    return result;
}
function nnfCompute(node, positive) {
    if (node.kind === 'constant') return constant(positive ? node.value : 1 - node.value);
    if (node.kind === 'variable') return positive ? node : negate(node);
    if (node.kind === 'not') return nnf(node.child, !positive);
    const a = node.left, b = node.right, operator = node.operator;
    if (operator === '&' || operator === '|') return binary(positive ? operator : operator === '&' ? '|' : '&', nnf(a, positive), nnf(b, positive));
    if (operator === '->') return binary(positive ? '|' : '&', nnf(a, !positive), nnf(b, positive));
    const same = operator === '<->' ? positive : !positive;
    return binary('|', binary('&', nnf(a, true), nnf(b, same)), binary('&', nnf(a, false), nnf(b, !same)));
}
function dual(node) {
    if (node.kind === 'variable') return node;
    if (node.kind === 'constant') return constant(1 - node.value);
    if (node.kind === 'not') return negate(dual(node.child));
    const a = dual(node.left), b = dual(node.right);
    return node.operator === '->' ? binary('&', negate(a), b) : binary(node.operator === '&' ? '|' : node.operator === '|' ? '&' : node.operator === '^' ? '<->' : '^', a, b);
}
function evaluate(node, names, row) {
    if (node.kind === 'constant') return node.value;
    if (node.kind === 'variable') return row >> (names.length - names.indexOf(node.name) - 1) & 1;
    if (node.kind === 'not') return 1 - evaluate(node.child, names, row);
    const a = evaluate(node.left, names, row), b = evaluate(node.right, names, row);
    return node.operator === '&' ? a & b : node.operator === '|' ? a | b : node.operator === '^' ? a ^ b : node.operator === '->' ? 1 - a | b : Number(a === b);
}
function bits(row, count) { return count === 0 ? '' : row.toString(2).padStart(count, '0'); }
function assignmentText(names, row) { const pattern = bits(row, names.length); return '{' + names.map((name, i) => name + '=' + pattern[i]).join(' ') + '}'; }
function literalCount(pattern) { return [...pattern].filter(c => c !== '-').length; }
function patternCompare(a, b) { const rank = { '1': 0, '0': 1, '-': 2 }; for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return rank[a[i]] - rank[b[i]]; return 0; }
function flip(pattern) { return [...pattern].map(c => c === '-' ? '-' : c === '0' ? '1' : '0').join(''); }
function contains(pattern, row) { return [...pattern].every((c, i) => c === '-' || c === row[i]); }
function patternText(pattern, names, product) { const literals = [...pattern].flatMap((c, i) => c === '-' ? [] : [(c === '0' ? '~' : '') + names[i]]); return literals.length ? literals.join(product ? ' & ' : ' | ') : product ? '1' : '0'; }
function coverText(patterns, names, product) {
    if (patterns.length === 0) return product ? '0' : '1';
    return patterns.map(pattern => { const text = patternText(pattern, names, product); return !product && patterns.length >= 2 && literalCount(pattern) >= 2 ? '(' + text + ')' : text; }).join(product ? ' | ' : ' & ');
}
function coefficients(values) {
    const result = [...values];
    for (let bit = 1; bit < values.length; bit *= 2) for (let row = 0; row < values.length; row++) if (row & bit) result[row] ^= result[row ^ bit];
    return result;
}
function minimize(names, on, dc, pos) {
    let stage = new Set([...on, ...dc].map(row => bits(row, names.length)));
    const primes = [], output = [];
    for (let number = 0;; number++) {
        const used = new Set(), next = new Set();
        for (const pattern of stage) for (let i = 0; i < pattern.length; i++) if (pattern[i] === '0') {
            const partner = pattern.slice(0, i) + '1' + pattern.slice(i + 1);
            if (stage.has(partner)) { used.add(pattern); used.add(partner); next.add(pattern.slice(0, i) + '-' + pattern.slice(i + 1)); }
        }
        const current = [...stage].filter(pattern => !used.has(pattern)); primes.push(...current);
        if (!pos) output.push(`stage ${number}: implicants ${stage.size} primes ${current.length}`);
        if (next.size === 0) break;
        stage = next;
    }
    const rows = on.map(row => bits(row, names.length));
    const target = primes.filter(pattern => rows.some(row => contains(pattern, row))).sort(patternCompare);
    const masks = target.map(pattern => rows.reduce((mask, row, i) => contains(pattern, row) ? mask | 1n << BigInt(i) : mask, 0n));
    const essential = new Set();
    for (let i = 0; i < rows.length; i++) {
        const candidates = target.map((_, j) => j).filter(j => (masks[j] & 1n << BigInt(i)) !== 0n);
        if (candidates.length === 1) essential.add(candidates[0]);
    }
    const fixed = [...essential], optional = target.map((_, i) => i).filter(i => !essential.has(i));
    const full = (1n << BigInt(rows.length)) - 1n;
    let best = null, bestLiterals = 0;
    const ordered = indices => indices.map(i => pos ? flip(target[i]) : target[i]).sort(patternCompare);
    function better(candidate, literals) {
        if (best === null || candidate.length !== best.length) return best === null || candidate.length < best.length;
        if (literals !== bestLiterals) return literals < bestLiterals;
        const a = ordered(candidate), b = ordered(best);
        for (let i = 0; i < a.length; i++) { const order = patternCompare(a[i], b[i]); if (order !== 0) return order < 0; }
        return false;
    }
    for (let subset = 0; subset < 2 ** optional.length; subset++) {
        const candidate = [...fixed]; let covered = 0n, literals = 0;
        for (let i = 0; i < optional.length; i++) if (subset & 1 << i) candidate.push(optional[i]);
        if (best !== null && candidate.length > best.length) continue;
        for (const index of candidate) { covered |= masks[index]; literals += literalCount(target[index]); }
        if (covered === full && better(candidate, literals)) { best = candidate; bestLiterals = literals; }
    }
    const chosen = ordered(best);
    if (pos) return [`minimal: ${coverText(chosen, names, false)}`, `clauses ${chosen.length} literals ${bestLiterals}`];
    output.push('primes: ' + (target.map(pattern => patternText(pattern, names, true)).join(', ') || 'none'));
    output.push('essential: ' + (fixed.map(i => target[i]).sort(patternCompare).map(pattern => patternText(pattern, names, true)).join(', ') || 'none'));
    output.push('minimal: ' + coverText(chosen, names, true), `terms ${chosen.length} literals ${bestLiterals}`);
    return output;
}
function mergeClauses(a, b) {
    let result = '';
    for (let i = 0; i < a.length; i++) {
        if (a[i] !== '-' && b[i] !== '-' && a[i] !== b[i]) return null;
        result += a[i] === '-' ? b[i] : a[i];
    }
    return result;
}
function tidy(patterns) {
    const unique = [...new Set(patterns)];
    return unique.filter(pattern => !unique.some(other => literalCount(other) < literalCount(pattern) && [...other].every((c, i) => c === '-' || c === pattern[i])));
}
function clauses(node, names, cache = new Map()) {
    if (cache.has(node)) return cache.get(node);
    const result = clausesCompute(node, names, cache);
    cache.set(node, result);
    return result;
}
function clausesCompute(node, names, cache) {
    if (node.kind === 'constant') return node.value ? [] : ['-'.repeat(names.length)];
    if (node.kind === 'variable' || node.kind === 'not') {
        const name = node.kind === 'variable' ? node.name : node.child.name, i = names.indexOf(name);
        return ['-'.repeat(i) + (node.kind === 'not' ? '0' : '1') + '-'.repeat(names.length - i - 1)];
    }
    const a = clauses(node.left, names, cache), b = clauses(node.right, names, cache);
    if (node.operator === '&') return tidy([...a, ...b]);
    const merged = [];
    for (const x of a) for (const y of b) { const value = mergeClauses(x, y); if (value !== null) merged.push(value); }
    return tidy(merged);
}
class Workbench {
    constructor() { this.definitions = new Map(); }
    define(name, formula) {
        const output = `${this.definitions.has(name) ? 'redefined' : 'defined'} ${name} = ${notation(formula)}`;
        this.definitions.set(name, formula); return [output];
    }
    command(line) {
        const split = line.indexOf(' '), command = split < 0 ? line : line.slice(0, split), argument = split < 0 ? '' : line.slice(split + 1), start = command.length + 2;
        const single = new Set('PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY MINIMIZE MINPOS KMAP SAT TAUT COUNT PROPS BDD CLAUSES DP'.split(' '));
        const divided = new Set(['RESTRICT', 'COFACTOR', 'MINDC', 'EQUIV', 'IMPLIES']);
        if (!single.has(command) && !divided.has(command) && !['DEF', 'DEFSUM', 'DEL', 'LIST'].includes(command)) fail('unknown command ' + command);
        if (command === 'LIST' && split >= 0) fail('unexpected argument');
        if (command !== 'LIST' && split < 0) fail('missing argument');
        const separator = argument.indexOf(';');
        if (divided.has(command) && separator < 0) fail("missing ';'");
        const validName = name => /^[a-z][a-z0-9]{0,7}$/.test(name);
        const words = text => text.split(' ').filter(Boolean);
        if (command === 'LIST') return ['names: ' + this.definitions.size, ...[...this.definitions.keys()].sort().map(name => name + ' = ' + notation(this.definitions.get(name)))];
        if (command === 'DEL') {
            if (!validName(argument)) fail(`invalid name '${argument}'`);
            if (!this.definitions.has(argument)) fail(`undefined name '${argument}'`);
            this.definitions.delete(argument); return ['deleted ' + argument];
        }
        if (command === 'DEF') {
            const space = argument.indexOf(' ');
            if (space < 0) fail('missing argument');
            const name = argument.slice(0, space);
            if (!validName(name)) fail(`invalid name '${name}'`);
            return this.define(name, parseFormula(argument.slice(space + 1), name.length + 6, this.definitions));
        }
        if (command === 'DEFSUM') {
            if (separator < 0) fail("missing ';'");
            const front = words(argument.slice(0, separator)), back = words(argument.slice(separator + 1));
            if (front.length === 0) fail('missing argument');
            const name = front[0], names = front.slice(1);
            if (!validName(name)) fail(`invalid name '${name}'`);
            if (names.length === 0 || names.some((name, i) => !/^[A-Z]$/.test(name) || i > 0 && names[i - 1] >= name)) fail('bad variable list');
            if (names.length >= 9) fail('too many variables: ' + names.length);
            const rows = []; let previous = -1;
            for (const word of back) {
                if (!/^(0|[1-9][0-9]*)$/.test(word) || Number(word) >= 2 ** names.length || Number(word) <= previous) fail(`bad minterm '${word}'`);
                previous = Number(word); rows.push(previous);
            }
            let formula = null;
            for (const row of rows) {
                const pattern = bits(row, names.length); let term = null;
                for (let i = 0; i < names.length; i++) { const literal = pattern[i] === '1' ? variable(names[i]) : negate(variable(names[i])); term = term === null ? literal : binary('&', term, literal); }
                formula = formula === null ? term : binary('|', formula, term);
            }
            return this.define(name, formula ?? constant(0));
        }
        const formula = parseFormula(divided.has(command) ? argument.slice(0, separator) : argument, start, this.definitions);
        const back = divided.has(command) ? argument.slice(separator + 1) : '';
        let second = null;
        if (['MINDC', 'EQUIV', 'IMPLIES'].includes(command)) second = parseFormula(back, start + separator + 1, this.definitions);
        if (command === 'RESTRICT') {
            const assignments = words(back), replacements = new Map();
            if (assignments.length === 0) fail('missing assignment');
            for (const assignment of assignments) {
                if (!/^[A-Z]=[01]$/.test(assignment)) fail(`bad assignment '${assignment}'`);
                if (replacements.has(assignment[0])) fail('duplicate variable ' + assignment[0]);
                replacements.set(assignment[0], Number(assignment[2]));
            }
            return ['restricted: ' + notation(simplify(formula, replacements))];
        }
        if (command === 'COFACTOR') {
            const list = words(back);
            if (list.length !== 1 || !/^[A-Z]$/.test(list[0])) fail('bad variable');
            const name = list[0], one = simplify(formula, new Map([[name, 1]])), zero = simplify(formula, new Map([[name, 0]]));
            return [`cofactor ${name}=1: ${notation(one)}`, `cofactor ${name}=0: ${notation(zero)}`, 'difference: ' + notation(simplifyBinary('^', one, zero))];
        }
        const names = variables(second === null ? [formula] : [formula, second]);
        if (command === 'PRINT') { const info = measure(formula); return ['formula: ' + notation(formula), 'variables: ' + (names.join(' ') || 'none'), `size ${info.size} depth ${info.depth}`]; }
        if (command === 'NNF') return ['nnf: ' + notation(nnf(formula))];
        if (command === 'DUAL') return ['dual: ' + notation(dual(formula))];
        if (command === 'SIMPLIFY') return ['simplified: ' + notation(simplify(formula))];
        if (command === 'CLAUSES' || command === 'DP') {
            let set = clauses(nnf(formula), names);
            if (command === 'CLAUSES') return ['clauses: ' + coverText(set.sort(patternCompare), names, false)];
            const output = ['start: clauses ' + set.length], empty = '-'.repeat(names.length);
            for (let i = 0; i < names.length; i++) {
                if (set.length === 0 || set.includes(empty)) break;
                const positive = set.filter(pattern => pattern[i] === '1'), negative = set.filter(pattern => pattern[i] === '0'), resolvents = new Set();
                for (const a of positive) for (const b of negative) {
                    const value = mergeClauses(a.slice(0, i) + '-' + a.slice(i + 1), b.slice(0, i) + '-' + b.slice(i + 1));
                    if (value !== null) resolvents.add(value);
                }
                set = tidy([...set.filter(pattern => pattern[i] === '-'), ...resolvents]);
                output.push(`eliminate ${names[i]}: resolvents ${resolvents.size} clauses ${set.length}`);
            }
            output.push('result: ' + (set.includes(empty) ? 'unsatisfiable' : 'satisfiable')); return output;
        }
        if (names.length >= 9) fail('too many variables: ' + names.length);
        if (command === 'KMAP' && (names.length < 2 || names.length > 4)) fail('kmap needs 2 to 4 variables');
        const values = Array.from({ length: 2 ** names.length }, (_, row) => evaluate(formula, names, row));
        const on = values.flatMap((value, row) => value === 1 ? [row] : []), off = values.flatMap((value, row) => value === 0 ? [row] : []);
        if (command === 'TABLE') return [(names.length ? names.join(' ') + ' ' : '') + '| F', ...values.map((value, row) => (names.length ? bits(row, names.length).split('').join(' ') + ' ' : '') + '| ' + value)];
        if (command === 'MINTERMS' || command === 'MAXTERMS') return [(command === 'MINTERMS' ? 'minterms: ' : 'maxterms: ') + ((command === 'MINTERMS' ? on : off).join(' ') || 'none')];
        if (command === 'DNF') return ['dnf: ' + coverText(on.map(row => bits(row, names.length)), names, true)];
        if (command === 'CNF') return ['cnf: ' + coverText(off.map(row => flip(bits(row, names.length))), names, false)];
        const anf = coefficients(values);
        if (command === 'ANF') { const patterns = anf.flatMap((value, row) => value ? [bits(row, names.length).replace(/0/g, '-')] : []).sort((a, b) => literalCount(a) - literalCount(b) || patternCompare(a, b)); return ['anf: ' + (patterns.map(pattern => patternText(pattern, names, true)).join(' ^ ') || '0')]; }
        if (command === 'SAT') return on.length ? ['satisfiable: ' + assignmentText(names, on[0])] : ['unsatisfiable'];
        if (command === 'TAUT') return off.length ? ['not a tautology: ' + assignmentText(names, off[0])] : ['tautology'];
        if (command === 'COUNT') return [`models: ${on.length} of ${values.length}`];
        if (command === 'EQUIV' || command === 'IMPLIES') {
            for (let row = 0; row < values.length; row++) {
                const a = values[row], b = evaluate(second, names, row);
                if (command === 'EQUIV' && a !== b) return [`not equivalent: ${assignmentText(names, row)} f=${a} g=${b}`];
                if (command === 'IMPLIES' && a === 1 && b === 0) return ['does not imply: ' + assignmentText(names, row)];
            }
            return [command === 'EQUIV' ? 'equivalent' : 'implies'];
        }
        if (command === 'MINIMIZE' || command === 'MINPOS') return minimize(names, command === 'MINPOS' ? off : on, [], command === 'MINPOS');
        if (command === 'MINDC') { const dc = values.flatMap((_, row) => evaluate(second, names, row) ? [row] : []), ignored = new Set(dc); return minimize(names, on.filter(row => !ignored.has(row)), dc, false); }
        if (command === 'KMAP') {
            const p = Math.floor(names.length / 2), q = names.length - p, label = names.slice(0, p).join('') + '\\' + names.slice(p).join('');
            const rows = Array.from({ length: 2 ** p }, (_, i) => i ^ i >> 1), columns = Array.from({ length: 2 ** q }, (_, i) => i ^ i >> 1);
            return [label + columns.map(column => ' ' + bits(column, q)).join(''), ...rows.map(row => bits(row, p).padEnd(label.length, ' ') + columns.map(column => ' '.repeat(q) + values[row * 2 ** q + column]).join(''))];
        }
        if (command === 'PROPS') {
            const depends = [], weights = new Map(); let monotone = true, symmetric = true;
            for (let i = 0; i < names.length; i++) {
                const bit = 1 << (names.length - 1 - i);
                if (values.some((value, row) => value !== values[row ^ bit])) depends.push(names[i]);
                if (values.some((value, row) => !(row & bit) && value > values[row | bit])) monotone = false;
            }
            for (let row = 0; row < values.length; row++) { const count = [...bits(row, names.length)].filter(c => c === '1').length; if (weights.has(count) && weights.get(count) !== values[row]) symmetric = false; weights.set(count, values[row]); }
            const yes = value => value ? 'yes' : 'no';
            return ['depends: ' + (depends.join(' ') || 'none'), 'zero-preserving: ' + yes(values[0] === 0), 'one-preserving: ' + yes(values[values.length - 1] === 1), 'self-dual: ' + yes(values.every((value, row) => value !== values[values.length - 1 - row])), 'monotone: ' + yes(monotone), 'linear: ' + yes(anf.every((value, row) => !value || (row & row - 1) === 0)), 'symmetric: ' + yes(symmetric)];
        }
        const nodes = [], unique = new Map();
        function build(index, list) {
            if (index === names.length) return list[0];
            const half = list.length / 2, lo = build(index + 1, list.slice(0, half)), hi = build(index + 1, list.slice(half));
            if (lo === hi) return lo;
            const key = [index, lo, hi].join(',');
            if (unique.has(key)) return unique.get(key);
            const id = nodes.length + 2; nodes.push({ index, lo, hi }); unique.set(key, id); return id;
        }
        const root = build(0, values), memo = new Map([[0, 0], [1, 1]]);
        function paths(id) { if (memo.has(id)) return memo.get(id); const node = nodes[id - 2], count = paths(node.lo) + paths(node.hi); memo.set(id, count); return count; }
        return ['nodes: ' + nodes.length, ...nodes.map((node, i) => `${i + 2} = ite(${names[node.index]}, ${node.hi}, ${node.lo})`), 'root: ' + root, 'paths: ' + paths(root)];
    }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/), workbench = new Workbench(), output = [];
for (let i = 0; i < Number(lines[0]); i++) {
    try { output.push(...workbench.command(lines[i + 1])); }
    catch (error) { if (!(error instanceof Problem)) throw error; output.push('error: ' + error.message); }
}
if (output.length > 0) process.stdout.write(output.join('\n') + '\n');
