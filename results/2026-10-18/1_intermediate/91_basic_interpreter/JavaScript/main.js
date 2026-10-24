const fs = require('fs');

class Expr {
    constructor(kind, type, value = '', args = []) { Object.assign(this, {kind, type, value, args}); }
}
class Statement {
    line = 0;
    next = null;
    expr = null;
    target = null;
    targets = [];
    expressions = [];
    values = [];
    numbers = [];
    name = '';
    mode = '';
    clauses = [];
    items = [];
    constructor(kind) { this.kind = kind; }
}
class SyntaxFault extends Error {}
class RuntimeFault extends Error {}
const syntax = () => { throw new SyntaxFault('SYNTAX ERROR'); };
const fault = (message) => { throw new RuntimeFault(message); };
const variable = (name) => /^[A-Z][0-9]?\$?$/.test(name);
const valueType = (value) => typeof value === 'string' ? 'S' : 'I';
const nameType = (name) => name.endsWith('$') ? 'S' : 'I';
const signatures = new Map([
    ['ABS', ['I']], ['SGN', ['I']], ['INT', ['I']], ['SQR', ['I']], ['RND', ['I']],
    ['LEN', ['S']], ['ASC', ['S']], ['VAL', ['S']], ['CHR$', ['I']], ['STR$', ['I']],
    ['LEFT$', ['SI']], ['RIGHT$', ['SI']], ['MID$', ['SI', 'SII']], ['INSTR', ['SS']],
]);
const errorCodes = new Map([
    ['NEXT WITHOUT FOR', 1], ['RETURN WITHOUT GOSUB', 3], ['OUT OF DATA', 4],
    ['ILLEGAL FUNCTION CALL', 5], ['OVERFLOW', 6], ['OUT OF MEMORY', 7],
    ['UNDEFINED LINE NUMBER', 8], ['SUBSCRIPT OUT OF RANGE', 9], ['DUPLICATE DEFINITION', 10],
    ['DIVISION BY ZERO', 11], ['TYPE MISMATCH', 13], ['STRING TOO LONG', 15],
    ['RESUME WITHOUT ERROR', 20], ['FOR WITHOUT NEXT', 26], ['WHILE WITHOUT WEND', 29],
    ['WEND WITHOUT WHILE', 30], ['INPUT PAST END', 62],
]);

function tokenize(text) {
    const tokens = [];
    for (let p = 0; p < text.length;) {
        const ch = text[p];
        if (ch === ' ') { p++; continue; }
        if (ch === '"') {
            const end = text.indexOf('"', p + 1);
            if (end < 0) syntax();
            tokens.push({kind: 'S', text: text.slice(p, end + 1), value: text.slice(p + 1, end)});
            p = end + 1;
        } else if (/[0-9]/.test(ch)) {
            const start = p;
            while (p < text.length && /[0-9]/.test(text[p])) p++;
            const word = text.slice(start, p), value = Number(word);
            if (value > 32767) syntax();
            tokens.push({kind: 'I', text: word, value});
        } else if (/[A-Z]/.test(ch)) {
            if (text.startsWith('REM', p)) { tokens.push({kind: 'W', text: 'REM', value: 'REM'}); break; }
            const start = p;
            while (p < text.length && /[A-Z0-9]/.test(text[p])) p++;
            if (text[p] === '$') p++;
            const word = text.slice(start, p);
            tokens.push({kind: 'W', text: word, value: word});
        } else {
            let word = text.slice(p, p + 2);
            if (!['<>', '<=', '>='].includes(word)) word = ch;
            if (!'+-*/^=<>() ,;:'.includes(ch)) syntax();
            tokens.push({kind: 'P', text: word, value: word}); p += word.length;
        }
    }
    tokens.push({kind: 'E', text: '', value: ''});
    return tokens;
}

class Parser {
    position = 0;
    constructor(tokens) { this.tokens = tokens; }
    current() { return this.tokens[this.position]; }
    at(word) { const t = this.current(); return (t.kind === 'P' || t.kind === 'W') && t.text === word; }
    take(word) { if (!this.at(word)) return false; this.position++; return true; }
    expect(word) { if (!this.take(word)) syntax(); }
    integer() { const expr = this.expression(); if (expr.type !== 'I') syntax(); return expr; }
    number() { const t = this.current(); if (t.kind !== 'I') syntax(); this.position++; return t.value; }
    target() {
        const token = this.current();
        if (token.kind !== 'W' || !variable(token.text)) syntax();
        this.position++;
        const result = new Expr('variable', nameType(token.text), token.text);
        if (this.take('(')) {
            result.kind = 'array'; result.args.push(this.integer());
            if (this.take(',')) result.args.push(this.integer());
            this.expect(')');
        }
        return result;
    }
    expression(level = 0) {
        if (level === 2 && this.take('NOT')) return new Expr('unary', 'I', 'NOT', [this.integerAt(2)]);
        if (level === 6 && this.take('-')) return new Expr('unary', 'I', '-', [this.integerAt(6)]);
        if (level === 8) return this.primary();
        let left = this.expression(level + 1);
        const ops = [['OR'], ['AND'], [], ['=', '<>', '<', '>', '<=', '>='], ['+', '-'], ['*', '/', 'MOD'], [], ['^']][level];
        while (ops.some(op => this.at(op))) {
            const op = this.current().text; this.position++;
            const right = this.expression(level === 7 ? 6 : level + 1);
            if (left.type !== right.type || (left.type === 'S' && level !== 3 && op !== '+')) syntax();
            left = new Expr('binary', level === 3 ? 'I' : left.type, op, [left, right]);
            if (level === 7) break;
        }
        return left;
    }
    integerAt(level) { const e = this.expression(level); if (e.type !== 'I') syntax(); return e; }
    primary() {
        const t = this.current();
        if (t.kind === 'I' || t.kind === 'S') { this.position++; return new Expr('constant', t.kind, t.value); }
        if (this.take('(')) { const e = this.expression(); this.expect(')'); return e; }
        if (t.kind === 'W' && variable(t.text)) return this.target();
        if (this.take('ERR')) return new Expr('builtin', 'I', 'ERR');
        if (this.take('ERL')) return new Expr('builtin', 'I', 'ERL');
        if (t.kind === 'W' && signatures.has(t.text)) {
            this.position++; this.expect('(');
            const args = [this.expression()];
            while (this.take(',')) args.push(this.expression());
            this.expect(')');
            if (!signatures.get(t.text).includes(args.map(e => e.type).join(''))) syntax();
            return new Expr('call', nameType(t.text), t.text, args);
        }
        return syntax();
    }
    clause() {
        if (this.current().kind === 'I') return {line: this.number(), body: []};
        return {line: null, body: this.list(true)};
    }
    list(clause = false) {
        const body = [this.statement(clause)];
        while (this.take(':')) body.push(this.statement(clause));
        return body;
    }
    statement(inClause) {
        const word = this.current().text;
        if (inClause && ['IF', 'FOR', 'NEXT', 'WHILE', 'WEND', 'DATA'].includes(word)) syntax();
        const s = new Statement(word);
        if (this.take('REM') || this.take('RETURN') || this.take('WEND') || this.take('END') || this.take('STOP')) return s;
        if (this.take('PRINT')) {
            let expressionLast = false;
            while (this.current().kind !== 'E' && !this.at(':') && !this.at('ELSE')) {
                if (this.take(';')) { s.items.push({kind: ';', expr: null}); expressionLast = false; }
                else if (this.take(',')) { s.items.push({kind: ',', expr: null}); expressionLast = false; }
                else {
                    const kind = this.at('TAB') ? 'TAB' : this.at('SPC') ? 'SPC' : 'value';
                    if (kind === 'value' && expressionLast) syntax();
                    let expr;
                    if (kind !== 'value') { this.position++; this.expect('('); expr = this.integer(); this.expect(')'); }
                    else expr = this.expression();
                    s.items.push({kind, expr}); expressionLast = kind === 'value';
                }
            }
            return s;
        }
        if (this.take('INPUT') || this.take('READ') || this.take('DIM')) {
            do { const target = this.target(); if (word === 'DIM' && target.kind !== 'array') syntax(); s.targets.push(target); } while (this.take(','));
            return s;
        }
        if (this.take('DATA')) {
            do {
                const negative = this.take('-'), t = this.current();
                if (t.kind !== 'I' && (t.kind !== 'S' || negative)) syntax();
                this.position++; s.values.push(negative ? -(t.value) : t.value);
            } while (this.take(','));
            return s;
        }
        if (this.take('IF')) {
            s.expr = this.integer(); this.expect('THEN'); s.clauses.push(this.clause());
            if (this.take('ELSE')) s.clauses.push(this.clause());
            if (this.current().kind !== 'E') syntax();
            return s;
        }
        if (this.take('GOTO') || this.take('GOSUB')) { s.numbers.push(this.number()); return s; }
        if (this.take('ON')) {
            if (this.take('ERROR')) { s.kind = 'handler'; this.expect('GOTO'); s.numbers.push(this.number()); }
            else {
                s.expr = this.integer();
                if (this.take('GOTO')) s.mode = 'GOTO'; else { this.expect('GOSUB'); s.mode = 'GOSUB'; }
                do { s.numbers.push(this.number()); } while (this.take(','));
            }
            return s;
        }
        if (this.take('RESUME')) {
            if (this.take('NEXT')) s.mode = 'NEXT';
            else if (this.current().kind === 'I') { s.mode = 'line'; s.numbers.push(this.number()); }
            return s;
        }
        if (this.take('FOR')) {
            const t = this.current();
            if (t.kind !== 'W' || !variable(t.text) || nameType(t.text) !== 'I') syntax();
            s.name = t.text; this.position++; this.expect('='); s.expressions.push(this.integer());
            this.expect('TO'); s.expressions.push(this.integer());
            s.expressions.push(this.take('STEP') ? this.integer() : new Expr('constant', 'I', 1));
            return s;
        }
        if (this.take('NEXT')) {
            if (this.current().kind === 'W' && variable(this.current().text) && nameType(this.current().text) === 'I') s.name = this.tokens[this.position++].text;
            return s;
        }
        if (this.take('WHILE') || this.take('RANDOMIZE')) { s.expr = this.integer(); return s; }
        if (this.take('RESTORE')) { if (this.current().kind === 'I') s.numbers.push(this.number()); return s; }
        this.take('LET'); s.kind = 'assign'; s.target = this.target(); this.expect('='); s.expr = this.expression();
        if (s.expr.type !== s.target.type) syntax();
        return s;
    }
    parse() { const body = this.list(); if (this.current().kind !== 'E') syntax(); return body; }
}

class Machine {
    variables = new Map();
    arrays = new Map();
    stack = [];
    entries = new Map();
    sequence = [];
    data = [];
    dataPosition = 0;
    inputPosition = 0;
    random = 1;
    handler = 0;
    handling = false;
    remembered = null;
    err = 0;
    erl = 0;
    buffer = '';
    output = [];
    constructor(inputs) { this.inputs = inputs; }
    endLine() { this.output.push(this.buffer.replace(/ +$/, '')); this.buffer = ''; }
    message(text) { if (this.buffer !== '') this.endLine(); this.output.push(text); }
    checked(n) { if (!Number.isFinite(n) || n < -32768 || n > 32767) fault('OVERFLOW'); return n; }
    get(name) { return this.variables.get(name) ?? (nameType(name) === 'S' ? '' : 0); }
    declare(name, bounds) {
        const count = bounds.reduce((a, b) => a * (b + 1), 1);
        this.arrays.set(name, {bounds, values: Array(count).fill(nameType(name) === 'S' ? '' : 0)});
    }
    address(target) {
        const name = target.value;
        if (target.kind === 'variable') return {name, index: null};
        const indices = target.args.map(e => this.evaluate(e));
        if (!this.arrays.has(name)) this.declare(name, indices.map(() => 10));
        const array = this.arrays.get(name);
        if (indices.length !== array.bounds.length || indices.some((n, i) => n < 0 || n > array.bounds[i])) fault('SUBSCRIPT OUT OF RANGE');
        let index = 0;
        indices.forEach((n, i) => { index = index * (array.bounds[i] + 1) + n; });
        return {name, index};
    }
    load(address) { return address.index === null ? this.get(address.name) : this.arrays.get(address.name).values[address.index]; }
    store(address, value) { if (address.index === null) this.variables.set(address.name, value); else this.arrays.get(address.name).values[address.index] = value; }
    evaluate(e) {
        const op = e.value;
        if (e.kind === 'constant') return op;
        if (e.kind === 'variable' || e.kind === 'array') return this.load(this.address(e));
        if (e.kind === 'builtin') return op === 'ERR' ? this.err : this.erl;
        if (e.kind === 'unary') { const a = this.evaluate(e.args[0]); return op === 'NOT' ? ~a : this.checked(-a); }
        const args = e.args.map(a => this.evaluate(a));
        if (e.kind === 'call') return this.call(op, args);
        const [a, b] = args;
        if (['=', '<>', '<', '>', '<=', '>='].includes(op)) {
            const order = a === b ? 0 : a < b ? -1 : 1;
            return ({'=': order === 0, '<>': order !== 0, '<': order < 0, '>': order > 0, '<=': order <= 0, '>=': order >= 0})[op] ? -1 : 0;
        }
        if (e.type === 'S') { const text = (a) + (b); if (text.length > 255) fault('STRING TOO LONG'); return text; }
        const x = a, y = b;
        switch (op) {
            case '+': return this.checked(x + y);
            case '-': return this.checked(x - y);
            case '*': return this.checked(x * y);
            case '/': if (y === 0) fault('DIVISION BY ZERO'); return this.checked(Math.trunc(x / y));
            case 'MOD': if (y === 0) fault('DIVISION BY ZERO'); return x % y;
            case '^': if (y < 0) fault('ILLEGAL FUNCTION CALL'); return this.checked(x ** y);
            case 'AND': return x & y;
            case 'OR': return x | y;
        }
        throw new Error('invalid expression');
    }
    call(name, args) {
        const n = args[0], s = args[0], k = args[1];
        switch (name) {
            case 'ABS': return this.checked(Math.abs(n));
            case 'SGN': return Math.sign(n);
            case 'INT': return n;
            case 'SQR': if (n < 0) fault('ILLEGAL FUNCTION CALL'); return Math.floor(Math.sqrt(n));
            case 'RND': if (n < 1) fault('ILLEGAL FUNCTION CALL'); this.random = 48271 * this.random % 2147483647; return this.random % n + 1;
            case 'LEN': return s.length;
            case 'ASC': if (s === '') fault('ILLEGAL FUNCTION CALL'); return s.charCodeAt(0);
            case 'VAL': { const m = /^ *([+-]?[0-9]+)/.exec(s); return this.checked(m ? Number(m[1]) : 0); }
            case 'CHR$': if (n < 32 || n > 126) fault('ILLEGAL FUNCTION CALL'); return String.fromCharCode(n);
            case 'STR$': return String(n);
            case 'LEFT$': if (k < 0) fault('ILLEGAL FUNCTION CALL'); return s.slice(0, k);
            case 'RIGHT$': if (k < 0) fault('ILLEGAL FUNCTION CALL'); return k === 0 ? '' : s.slice(-k);
            case 'MID$': {
                if (k < 1 || (args.length === 3 && (args[2]) < 0)) fault('ILLEGAL FUNCTION CALL');
                return s.slice(k - 1, args.length === 3 ? k - 1 + (args[2]) : undefined);
            }
            case 'INSTR': return s.indexOf(args[1]) + 1;
        }
        throw new Error('invalid function');
    }
    line(number) { const s = this.entries.get(number); if (!s) fault('UNDEFINED LINE NUMBER'); return s; }
    push(frame) { if (this.stack.length === 100) fault('OUT OF MEMORY'); this.stack.push(frame); }
    search(kind, name = '') {
        for (let i = this.stack.length - 1; i >= 0; i--) {
            const f = this.stack[i]; if (f.kind === 'GOSUB') break;
            if (f.kind === kind && (!name || f.name === name)) return i;
        }
        return -1;
    }
    matching(s, open, close) {
        let depth = 0;
        for (let i = this.sequence.indexOf(s) + 1; i < this.sequence.length; i++) {
            const t = this.sequence[i];
            if (t.kind === open) depth++;
            else if (t.kind === close) { if (depth === 0) return t.next; depth--; }
        }
        return fault(open + ' WITHOUT ' + close);
    }
    subroutine(number, after) { const target = this.line(number); this.push({kind: 'GOSUB', position: after}); return target; }
    execute(s) {
        let next = s.next;
        switch (s.kind) {
            case 'REM': case 'DATA': break;
            case 'assign': { const address = this.address(s.target); this.store(address, this.evaluate(s.expr)); break; }
            case 'PRINT':
                for (const item of s.items) {
                    if (item.kind === ',') this.buffer += ' '.repeat(10 - this.buffer.length % 10);
                    else if (item.kind !== ';') {
                        const value = this.evaluate(item.expr);
                        if (item.kind === 'value') this.buffer += String(value);
                        else {
                            const n = value; if (n < 0) fault('ILLEGAL FUNCTION CALL');
                            this.buffer += ' '.repeat(item.kind === 'SPC' ? n : Math.max(0, n - this.buffer.length));
                        }
                    }
                }
                if (s.items.length === 0 || ![';', ','].includes(s.items[s.items.length - 1].kind)) this.endLine();
                break;
            case 'INPUT': case 'READ':
                for (const target of s.targets) {
                    const address = this.address(target);
                    let value;
                    if (s.kind === 'READ') {
                        if (this.dataPosition === this.data.length) fault('OUT OF DATA');
                        value = this.data[this.dataPosition++].value;
                        if (valueType(value) !== target.type) fault('TYPE MISMATCH');
                    } else {
                        while (true) {
                            if (this.inputPosition === this.inputs.length) fault('INPUT PAST END');
                            const text = this.inputs[this.inputPosition++];
                            if (target.type === 'S') { value = text; break; }
                            const n = Number(text);
                            if (/^-?[0-9]+$/.test(text) && n >= -32768 && n <= 32767) { value = n; break; }
                            this.message('?REDO FROM START');
                        }
                    }
                    this.store(address, value);
                }
                break;
            case 'RESTORE':
                if (s.numbers.length) { this.line(s.numbers[0]); const p = this.data.findIndex(d => d.line >= s.numbers[0]); this.dataPosition = p < 0 ? this.data.length : p; }
                else this.dataPosition = 0;
                break;
            case 'IF': {
                const clause = s.clauses[(this.evaluate(s.expr)) !== 0 ? 0 : 1];
                if (clause) next = clause.line !== null ? this.line(clause.line) : clause.body[0];
                break;
            }
            case 'GOTO': next = this.line(s.numbers[0]); break;
            case 'GOSUB': next = this.subroutine(s.numbers[0], next); break;
            case 'ON': {
                const n = this.evaluate(s.expr);
                if (n < 0) fault('ILLEGAL FUNCTION CALL');
                if (n >= 1 && n <= s.numbers.length) next = s.mode === 'GOTO' ? this.line(s.numbers[n - 1]) : this.subroutine(s.numbers[n - 1], next);
                break;
            }
            case 'RETURN': {
                let i = this.stack.length - 1; while (i >= 0 && this.stack[i].kind !== 'GOSUB') i--;
                if (i < 0) fault('RETURN WITHOUT GOSUB');
                next = this.stack[i].position; this.stack.length = i; break;
            }
            case 'FOR': {
                const [start, final, step] = s.expressions.map(e => this.evaluate(e));
                if (step === 0) fault('ILLEGAL FUNCTION CALL');
                const i = this.search('FOR', s.name); if (i >= 0) this.stack.length = i;
                this.variables.set(s.name, start);
                if (step > 0 ? start > final : start < final) next = this.matching(s, 'FOR', 'NEXT');
                else this.push({kind: 'FOR', name: s.name, final, step, position: next});
                break;
            }
            case 'NEXT': {
                const i = this.search('FOR', s.name); if (i < 0) fault('NEXT WITHOUT FOR');
                this.stack.length = i + 1; const f = this.stack[i], step = f.step, final = f.final;
                const value = this.checked((this.get(f.name)) + step); this.variables.set(f.name, value);
                if (step > 0 ? value > final : value < final) this.stack.pop(); else next = f.position;
                break;
            }
            case 'WHILE': if ((this.evaluate(s.expr)) !== 0) this.push({kind: 'WHILE', position: s}); else next = this.matching(s, 'WHILE', 'WEND'); break;
            case 'WEND': {
                const i = this.search('WHILE'); if (i < 0) fault('WEND WITHOUT WHILE');
                next = this.stack[i].position; this.stack.length = i; break;
            }
            case 'DIM':
                for (const target of s.targets) {
                    const name = target.value, bounds = target.args.map(e => this.evaluate(e));
                    if (this.arrays.has(name)) fault('DUPLICATE DEFINITION');
                    if (bounds.some(n => n < 0)) fault('ILLEGAL FUNCTION CALL');
                    if (bounds.reduce((a, b) => a * (b + 1), 1) > 10000) fault('OUT OF MEMORY');
                    this.declare(name, bounds);
                }
                break;
            case 'RANDOMIZE': { const n = this.evaluate(s.expr); if (n < 1) fault('ILLEGAL FUNCTION CALL'); this.random = n; break; }
            case 'handler': if (s.numbers[0] !== 0) this.line(s.numbers[0]); this.handler = s.numbers[0]; break;
            case 'RESUME':
                if (!this.handling) fault('RESUME WITHOUT ERROR');
                next = s.mode === 'line' ? this.line(s.numbers[0]) : s.mode === 'NEXT' ? this.remembered.next : this.remembered;
                this.handling = false; break;
            case 'STOP': this.message('BREAK IN LINE ' + s.line); return null;
            case 'END': return null;
        }
        return next;
    }
    connect(body, after, line) {
        let next = after;
        for (let i = body.length - 1; i >= 0; i--) {
            const s = body[i]; s.line = line; s.next = next;
            for (const c of s.clauses) this.connect(c.body, next, line);
            next = s;
        }
    }
    run(source) {
        const parsed = [];
        for (const line of [...source.keys()].sort((a, b) => a - b)) {
            try { parsed.push([line, new Parser(tokenize(source.get(line))).parse()]); }
            catch (e) { if (!(e instanceof SyntaxFault)) throw e; this.message(`ERROR IN LINE ${line}: SYNTAX ERROR`); return this.finish(); }
        }
        let after = null;
        for (let i = parsed.length - 1; i >= 0; i--) {
            const [line, body] = parsed[i]; this.connect(body, after, line); this.entries.set(line, body[0]); after = body[0];
        }
        this.sequence = parsed.flatMap(([, body]) => body);
        for (const s of this.sequence) if (s.kind === 'DATA') for (const value of s.values) this.data.push({line: s.line, value});
        let position = after;
        while (position !== null) {
            const statement = position;
            try { position = this.execute(statement); }
            catch (e) {
                if (!(e instanceof RuntimeFault)) throw e;
                if (this.handler !== 0 && !this.handling) {
                    this.err = errorCodes.get(e.message); this.erl = statement.line; this.remembered = statement; this.handling = true; position = this.line(this.handler);
                } else { this.message(`ERROR IN LINE ${statement.line}: ${e.message}`); position = null; }
            }
        }
        return this.finish();
    }
    finish() { if (this.buffer !== '') this.endLine(); this.output.push('READY'); return this.output; }
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/), output = [];
let cursor = 1;
for (let p = 0; p < Number(lines[0]); p++) {
    const source = new Map();
    while (lines[cursor] !== 'RUN') {
        const match = /^([0-9]+)(?: +(.*))?$/.exec(lines[cursor++]), line = Number(match[1]);
        if (match[2] === undefined) source.delete(line); else source.set(line, match[2]);
    }
    cursor++;
    const data = [];
    while (lines[cursor] !== 'END') data.push(lines[cursor++]);
    cursor++;
    output.push(...new Machine(data).run(source));
}
process.stdout.write(output.join('\n') + '\n');
