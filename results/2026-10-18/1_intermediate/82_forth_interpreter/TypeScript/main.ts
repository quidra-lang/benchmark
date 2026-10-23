import * as fs from 'node:fs';

interface Word {
    name: string; kind: string; here: number; address: number; value: bigint; deferred: bigint | null;
    does: { definition: Word; start: number } | null; rawName: string; actions: Action[];
    locals: Map<string, number>; localCount: number; anonymous: boolean;
}
type Action =
    | { kind: 'literal'; raw: string; value: bigint }
    | { kind: 'call' | 'value-set' | 'defer-set'; raw: string; word: Word }
    | { kind: 'write' | 'abort'; raw: string; text: string }
    | { kind: 'exit' | 'recurse' | 'does' | 'noop' | 'endcase'; raw: string }
    | { kind: 'local-get' | 'local-set'; raw: string; slot: number }
    | { kind: 'locals'; raw: string; slots: number[] }
    | { kind: 'branch' | 'jump' | 'leave' | 'of'; raw: string; target: number }
    | { kind: 'loop-enter'; raw: string; conditional: boolean; target: number }
    | { kind: 'loop-next'; raw: string; increment: boolean; target: number }
    | { kind: 'return'; raw: string; operation: string };
type TargetedAction = Extract<Action, { target: number }>;
type Control =
    | { kind: 'IF' | 'ELSE' | 'BEGIN' | 'OF'; index: number }
    | { kind: 'WHILE'; index: number; begin: number }
    | { kind: 'DO' | '?DO'; index: number; leaves: number[] }
    | { kind: 'CASE'; index: number; endofs: number[] };


class ForthError extends Error {
    word: string;
    code: bigint | null;
    constructor(word: string, reason: string, code: bigint | null = null) { super(reason); this.word = word; this.code = code; }
}
function fail(word: string, reason: string, code: bigint | null = null): never { throw new ForthError(word, reason, code); }
const compileOnly = new Set('IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT" [\'] {:'.split(' '));
const interpretOnly = new Set([':', ':NONAME', 'FORGET']);
const special = new Set([...compileOnly, ...interpretOnly, '."', '(', '\\', 'TO', 'IS']);
const builtinNames = '+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER \' EXECUTE CATCH THROW ABORT WORDS'.split(' ');
function newWord(name: string, kind: string, here: number): Word {
    return { name, kind, here, address: here, value: 0n, deferred: null, does: null,
        rawName: name, actions: [], locals: new Map(), localCount: 0, anonymous: false };
}
function upper(word: string): string { return word.toUpperCase(); }
function quotient(a: bigint, b: bigint): bigint { const q = a / b; return a % b !== 0n && (a < 0n) !== (b < 0n) ? q - 1n : q; }
class Forth {
    stack: bigint[];
    returns: bigint[];
    memory: bigint[];
    dictionary: Word[];
    tokens: Word[];
    builtins: Map<string, Word>;
    compiling: Word | null;
    control: Control[];
    depth: number;
    pending: string;
    output: string[];
    line: string;
    position: number;
    constructor() {
        this.stack = []; this.returns = []; this.memory = [10n]; this.dictionary = []; this.tokens = [];
        this.builtins = new Map(builtinNames.map(name => [name, newWord(name, 'builtin', 0)]));
        this.compiling = null; this.control = []; this.depth = 0; this.pending = ''; this.output = []; this.line = ''; this.position = 0;
    }
    read(): string | null { while (this.position < this.line.length && this.line[this.position] === ' ') this.position++; if (this.position === this.line.length) return null; const start = this.position; while (this.position < this.line.length && this.line[this.position] !== ' ') this.position++; return this.line.slice(start, this.position); }
    name(raw: string): string { const value = this.read(); if (value === null) fail(raw, 'missing name', -16n); return value; }
    lookup(name: string): Word | null { name = upper(name); for (let i = this.dictionary.length - 1; i >= 0; i--) if (this.dictionary[i].name === name) return this.dictionary[i]; return this.builtins.get(name) ?? null; }
    number(raw: string, radix = this.memory[0]): bigint | null {
        if (raw.length === 3 && raw[0] === "'" && raw[2] === "'") return BigInt(raw.charCodeAt(1));
        let text = upper(raw);
        let base: number;
        if ('$#%'.includes(text[0])) { base = text[0] === '$' ? 16 : text[0] === '#' ? 10 : 2; text = text.slice(1); }
        else { if (radix < 2n || radix > 36n) fail(raw, 'invalid base', -40n); base = Number(radix); }
        const negative = text.startsWith('-'); if (negative) text = text.slice(1);
        if (text === '') return null;
        let value = 0n;
        for (const character of text) { const code = character.charCodeAt(0), digit = code >= 48 && code <= 57 ? code - 48 : code >= 65 && code <= 90 ? code - 55 : -1; if (digit < 0 || digit >= base) return null; value = value * BigInt(base) + BigInt(digit); }
        return negative ? -value : value;
    }
    checkName(name: string): void { if (special.has(upper(name)) || this.number(name, 10n) !== null) fail(name, 'invalid name', -19n); }
    pop(count: number, raw: string): bigint[] { if (this.stack.length < count) fail(raw, 'stack underflow', -4n); return this.stack.splice(this.stack.length - count, count); }
    push(value: bigint, raw: string): void { this.stack.push(value); if (this.stack.length > 1000) fail(raw, 'stack overflow', -3n); }
    pushMany(values: bigint[], raw: string): void { for (const value of values) this.push(value, raw); }
    needReturns(count: number, raw: string): void { if (this.returns.length < count) fail(raw, 'return stack underflow', -6n); }
    pushReturn(value: bigint, raw: string): void { this.returns.push(value); if (this.returns.length > 1000) fail(raw, 'return stack overflow', -5n); }
    address(value: bigint, raw: string): number { if (value < 0n || value % 8n !== 0n || value >= BigInt(this.memory.length * 8)) fail(raw, 'invalid address', -9n); return Number(value / 8n); }
    validToken(value: bigint): boolean { return value >= 1n && value <= BigInt(this.tokens.length); }
    xt(word: Word): bigint { let index = this.tokens.indexOf(word); if (index < 0) { this.tokens.push(word); index = this.tokens.length - 1; } return BigInt(index + 1); }
    format(value: bigint, raw: string): string { const base = this.memory[0]; if (base < 2n || base > 36n) fail(raw, 'invalid base', -40n); return value.toString(Number(base)).toUpperCase(); }
    flush(): void { let end = this.pending.length; while (end && this.pending[end - 1] === ' ') end--; this.output.push(this.pending.slice(0, end)); this.pending = ''; }
    executeToken(value: bigint, raw: string): void { if (!this.validToken(value)) fail(raw, 'invalid argument', -24n); const word = this.tokens[Number(value - 1n)]; this.execute(word, word.name); }
    define(kind: string, raw: string): void {
        const name = this.name(raw); this.checkName(name);
        const value = kind === 'CONSTANT' || kind === 'VALUE' ? this.pop(1, raw)[0] : 0n;
        const here = this.memory.length * 8, word = newWord(upper(name), kind.toLowerCase(), here);
        word.value = value;
        this.dictionary.push(word);
        if (kind === 'VARIABLE' || kind === 'VALUE') this.memory.push(value);
    }
    execute(word: Word, raw: string): void {
        while (word.kind === 'defer') {
            const token = word.deferred;
            if (token === null) fail(raw, 'deferred word not set', -21n);
            if (!this.validToken(token)) fail(raw, 'invalid argument', -24n);
            word = this.tokens[Number(token - 1n)];
            raw = word.name;
        }
        switch (word.kind) {
            case 'builtin': this.builtin(word.name, raw); return;
            case 'colon': this.definition(word, 0, raw); return;
            case 'constant': this.push(word.value, raw); return;
            case 'value': this.push(this.memory[word.address / 8], raw); return;
            case 'create': case 'variable': this.push(BigInt(word.address), raw); if (word.does !== null) this.definition(word.does.definition, word.does.start, raw); return;
        }
    }
    builtin(name: string, raw: string): void {
        if (['CREATE', 'VARIABLE', 'CONSTANT', 'VALUE', 'DEFER'].includes(name)) { this.define(name, raw); return; }
        if (name === "'") { const name = this.name(raw), word = this.lookup(name); if (word === null) fail(name, 'undefined word', -13n); this.push(this.xt(word), raw); return; }
        if (name === 'EXECUTE') { this.executeToken(this.pop(1, raw)[0], raw); return; }
        if (name === 'CATCH') {
            const token = this.pop(1, raw)[0]; if (!this.validToken(token)) fail(raw, 'invalid argument', -24n);
            const stack = [...this.stack], returns = this.returns.length, depth = this.depth;
            try { this.executeToken(token, raw); }
            catch (error) { if (!(error instanceof ForthError) || error.code === null) throw error; this.stack = stack; if (this.returns.length > returns) this.returns.length = returns; this.depth = depth; this.push(error.code, raw); return; }
            this.push(0n, raw); return;
        }
        if (name === 'THROW') { const n = this.pop(1, raw)[0]; if (n !== 0n) fail(raw, 'exception ' + n, n); return; }
        if (name === 'ABORT') fail(raw, 'aborted', -1n);
        if (name === 'WORDS') { for (const word of [...this.dictionary].reverse()) this.pending += word.name + ' '; return; }
        if (name === 'CR') { this.flush(); return; }
        if (name === 'SPACE') { this.pending += ' '; return; }
        if (name === 'DEPTH') { this.push(BigInt(this.stack.length), raw); return; }
        if (name === 'HERE') { this.push(BigInt(this.memory.length * 8), raw); return; }
        if (name === 'BASE') { this.push(0n, raw); return; }
        if (name === 'HEX' || name === 'DECIMAL') { this.memory[0] = name === 'HEX' ? 16n : 10n; return; }
        if (name === 'TRUE' || name === 'FALSE' || name === 'BL') { this.push(name === 'TRUE' ? -1n : name === 'FALSE' ? 0n : 32n, raw); return; }
        if (name === '.S') { const count = this.format(BigInt(this.stack.length), raw), values = this.stack.map(value => this.format(value, raw)); this.pending += '<' + count + '> ' + (values.length ? values.join(' ') + ' ' : ''); return; }
        if (name === 'PICK' || name === 'ROLL') {
            const n = this.pop(1, raw)[0]; if (n < 0n) fail(raw, 'invalid argument', -24n); if (n >= BigInt(this.stack.length)) fail(raw, 'stack underflow', -4n);
            const index = this.stack.length - 1 - Number(n), value = this.stack[index]; if (name === 'ROLL') this.stack.splice(index, 1); this.push(value, raw); return;
        }
        const arity = ['*/', '*/MOD', 'ROT', '-ROT', 'WITHIN'].includes(name) ? 3 : ['2SWAP', '2OVER'].includes(name) ? 4 : ['+', '-', '*', '/', 'MOD', '/MOD', '=', '<>', '<', '>', 'MIN', 'MAX', 'AND', 'OR', 'XOR', 'SWAP', 'OVER', 'NIP', 'TUCK', '2DUP', '2DROP', '.R', '!', '+!'].includes(name) ? 2 : 1;
        const values = this.pop(arity, raw), a = values[0], b = values[1], c = values[2], d = values[3];
        const flag = (condition: boolean): bigint => condition ? -1n : 0n;
        switch (name) {
            case '+': this.push(a + b, raw); break;
            case '-': this.push(a - b, raw); break;
            case '*': this.push(a * b, raw); break;
            case '/': case 'MOD': case '/MOD': case '*/': case '*/MOD': {
                const n = name.startsWith('*/') ? a * b : a, divisor = name.startsWith('*/') ? c : b;
                if (divisor === 0n) fail(raw, 'division by zero', -10n);
                const q = quotient(n, divisor), r = n - divisor * q;
                if (['MOD', '/MOD', '*/MOD'].includes(name)) this.push(r, raw); if (name !== 'MOD') this.push(q, raw); break;
            }
            case 'NEGATE': this.push(-a, raw); break;
            case 'ABS': this.push(a < 0n ? -a : a, raw); break;
            case 'MIN': this.push(a < b ? a : b, raw); break;
            case 'MAX': this.push(a > b ? a : b, raw); break;
            case '1+': this.push(a + 1n, raw); break;
            case '1-': this.push(a - 1n, raw); break;
            case '2*': this.push(a * 2n, raw); break;
            case '2/': this.push(quotient(a, 2n), raw); break;
            case '=': this.push(flag(a === b), raw); break;
            case '<>': this.push(flag(a !== b), raw); break;
            case '<': this.push(flag(a < b), raw); break;
            case '>': this.push(flag(a > b), raw); break;
            case '0=': this.push(flag(a === 0n), raw); break;
            case '0<>': this.push(flag(a !== 0n), raw); break;
            case '0<': this.push(flag(a < 0n), raw); break;
            case '0>': this.push(flag(a > 0n), raw); break;
            case 'WITHIN': this.push(flag(b <= a && a < c), raw); break;
            case 'AND': this.push(a & b, raw); break;
            case 'OR': this.push(a | b, raw); break;
            case 'XOR': this.push(a ^ b, raw); break;
            case 'INVERT': this.push(~a, raw); break;
            case 'DUP': this.pushMany([a, a], raw); break;
            case '?DUP': this.pushMany(a === 0n ? [a] : [a, a], raw); break;
            case 'DROP': case '2DROP': break;
            case 'SWAP': this.pushMany([b, a], raw); break;
            case 'OVER': this.pushMany([a, b, a], raw); break;
            case 'ROT': this.pushMany([b, c, a], raw); break;
            case '-ROT': this.pushMany([c, a, b], raw); break;
            case 'NIP': this.push(b, raw); break;
            case 'TUCK': this.pushMany([b, a, b], raw); break;
            case '2DUP': this.pushMany([a, b, a, b], raw); break;
            case '2SWAP': this.pushMany([c, d, a, b], raw); break;
            case '2OVER': this.pushMany([a, b, c, d, a, b], raw); break;
            case '.': this.pending += this.format(a, raw) + ' '; break;
            case '.R': { const text = this.format(a, raw); this.pending += text.padStart(Math.max(0, Number(b)), ' '); break; }
            case '?': { const index = this.address(a, raw); this.pending += this.format(this.memory[index], raw) + ' '; break; }
            case 'EMIT': if (a < 32n || a > 126n) fail(raw, 'invalid argument', -24n); this.pending += String.fromCharCode(Number(a)); break;
            case 'SPACES': if (a > 0n) this.pending += ' '.repeat(Number(a)); break;
            case '!': this.memory[this.address(b, raw)] = a; break;
            case '@': this.push(this.memory[this.address(a, raw)], raw); break;
            case '+!': { const index = this.address(b, raw); this.memory[index] += a; break; }
            case ',': this.memory.push(a); break;
            case 'ALLOT': if (a < 0n || a % 8n !== 0n) fail(raw, 'invalid argument', -24n); for (let i = 0; i < Number(a / 8n); i++) this.memory.push(0n); break;
            case 'CELLS': this.push(a * 8n, raw); break;
            case 'CELL+': this.push(a + 8n, raw); break;
        }
    }
    definition(definition: Word, start: number, raw: string): void {
        if (this.depth === 100) fail(raw, 'nesting too deep', -7n);
        this.depth++;
        const returns = this.returns.length;
        const locals: bigint[] = Array(definition.localCount).fill(0n);
        for (let pc = start; pc < definition.actions.length; pc++) {
            const action = definition.actions[pc], word = action.raw;
            switch (action.kind) {
                case 'literal': this.push(action.value, word); break;
            case 'call': this.execute(action.word, word); break;
                case 'write': this.pending += action.text; break;
            case 'abort': if (this.pop(1, word)[0] !== 0n) fail(word, action.text, -2n); break;
                case 'exit': pc = definition.actions.length; break;
                case 'recurse': this.definition(definition, 0, word); break;
                case 'does': { const newest = this.dictionary.at(-1); if (newest === undefined || newest.kind !== 'create') fail(word, 'no CREATE word', -31n); newest.does = { definition, start: pc + 1 }; pc = definition.actions.length; break; }
                case 'local-get': this.push(locals[action.slot], word); break;
            case 'local-set': locals[action.slot] = this.pop(1, word)[0]; break;
                case 'locals': { const values = this.pop(action.slots.length, word); action.slots.forEach((slot, i) => { locals[slot] = values[i]; }); break; }
                case 'value-set': this.memory[action.word.address / 8] = this.pop(1, word)[0]; break;
                case 'defer-set': { const value = this.pop(1, word)[0]; if (!this.validToken(value)) fail(word, 'invalid argument', -24n); action.word.deferred = value; break; }
                case 'branch': if (this.pop(1, word)[0] === 0n) pc = action.target - 1; break;
            case 'jump': pc = action.target - 1; break;
                case 'loop-enter': { const [limit, index] = this.pop(2, word); if (action.conditional && limit === index) pc = action.target - 1; else { this.pushReturn(limit, word); this.pushReturn(index, word); } break; }
                case 'loop-next': { const step = action.increment ? 1n : this.pop(1, word)[0]; this.needReturns(2, word); const index = this.returns.at(-1)!, limit = this.returns.at(-2)!, next = index + step; if ((index - limit < 0n) !== (next - limit < 0n)) this.returns.length -= 2; else { this.returns[this.returns.length - 1] = next; pc = action.target - 1; } break; }
                case 'leave': this.needReturns(2, word); this.returns.length -= 2; pc = action.target - 1; break;
                case 'of': { const [a, b] = this.pop(2, word); if (a !== b) { this.push(a, word); pc = action.target - 1; } break; }
                case 'endcase': this.pop(1, word); break;
                case 'return':
                    if (action.operation === '>R') this.pushReturn(this.pop(1, word)[0], word);
                    else { const count = action.operation === 'J' ? 3 : action.operation === 'UNLOOP' ? 2 : 1; this.needReturns(count, word); if (action.operation === 'UNLOOP') this.returns.length -= 2; else if (action.operation === 'R>') this.push(this.returns.pop()!, word); else this.push(this.returns[this.returns.length - count], word); } break;
            }
        }
        if (this.returns.length > returns) this.returns.length = returns;
        this.depth--;
    }
    emit(action: Action): number { const index = this.compiling!.actions.length; this.compiling!.actions.push(action); return index; }
    mismatch(raw: string): never { fail(raw, 'control structure mismatch'); }
    compile(raw: string): void {
        const name = upper(raw), definition = this.compiling!, top = this.control.at(-1), index = definition.actions.length;
        if (name === ';') {
            if (top !== undefined) { const kind = top.kind === 'ELSE' ? 'IF' : top.kind === 'WHILE' ? 'BEGIN' : top.kind; fail(raw, 'unclosed ' + kind); }
            this.compiling = null;
            if (definition.anonymous) this.push(this.xt(definition), raw); else this.dictionary.push(definition);
            return;
        }
        if (name === '{:') {
            const words: string[] = []; let closed = false;
            let word: string | null;
            while ((word = this.read()) !== null) { if (upper(word) === ':}') { closed = true; break; } words.push(word); }
            if (!closed) fail(raw, 'unterminated locals');
            const marker = words.indexOf('--'), names = marker < 0 ? words : words.slice(0, marker);
            const slots: number[] = [];
            for (const name of names) this.checkName(name);
            for (const name of names) { const slot = definition.localCount++; definition.locals.set(upper(name), slot); slots.push(slot); }
            this.emit({ kind: 'locals', raw, slots }); return;
        }
        if (name === "[']") { const name = this.name(raw), word = this.lookup(name); if (word === null) fail(name, 'undefined word', -13n); this.emit({ kind: 'literal', raw, value: this.xt(word) }); return; }
        if (name === 'DOES>') { if (this.control.length) this.mismatch(raw); this.emit({ kind: 'does', raw }); return; }
        if (name === 'EXIT' || name === 'RECURSE') { this.emit({ kind: name === 'EXIT' ? 'exit' : 'recurse', raw }); return; }
        if (['>R', 'R>', 'R@', 'I', 'J', 'UNLOOP'].includes(name)) { this.emit({ kind: 'return', raw, operation: name }); return; }
        if (name === 'IF') { this.control.push({ kind: 'IF', index: this.emit({ kind: 'branch', raw, target: 0 }) }); return; }
        if (name === 'ELSE') { if (top === undefined || top.kind !== 'IF') this.mismatch(raw); this.emit({ kind: 'jump', raw, target: 0 }); (definition.actions[top.index] as TargetedAction).target = index + 1; this.control[this.control.length - 1] = { kind: 'ELSE', index }; return; }
        if (name === 'THEN') { if (top === undefined || top.kind !== 'IF' && top.kind !== 'ELSE') this.mismatch(raw); this.emit({ kind: 'noop', raw }); (definition.actions[top.index] as TargetedAction).target = index + 1; this.control.pop(); return; }
        if (name === 'BEGIN') { this.emit({ kind: 'noop', raw }); this.control.push({ kind: 'BEGIN', index }); return; }
        if (name === 'UNTIL' || name === 'AGAIN') { if (top === undefined || top.kind !== 'BEGIN') this.mismatch(raw); this.emit({ kind: name === 'UNTIL' ? 'branch' : 'jump', raw, target: top.index + 1 }); this.control.pop(); return; }
        if (name === 'WHILE') { if (top === undefined || top.kind !== 'BEGIN') this.mismatch(raw); this.emit({ kind: 'branch', raw, target: 0 }); this.control[this.control.length - 1] = { kind: 'WHILE', index, begin: top.index }; return; }
        if (name === 'REPEAT') { if (top === undefined || top.kind !== 'WHILE') this.mismatch(raw); this.emit({ kind: 'jump', raw, target: top.begin + 1 }); (definition.actions[top.index] as TargetedAction).target = index + 1; this.control.pop(); return; }
        if (name === 'DO' || name === '?DO') { this.emit({ kind: 'loop-enter', raw, conditional: name === '?DO', target: 0 }); this.control.push({ kind: name, index, leaves: [] }); return; }
        if (name === 'LOOP' || name === '+LOOP') { if (top === undefined || top.kind !== 'DO' && top.kind !== '?DO') this.mismatch(raw); this.emit({ kind: 'loop-next', raw, increment: name === 'LOOP', target: top.index + 1 }); (definition.actions[top.index] as TargetedAction).target = index + 1; for (const leave of top.leaves) (definition.actions[leave] as TargetedAction).target = index + 1; this.control.pop(); return; }
        if (name === 'LEAVE') { const loop = [...this.control].reverse().find((record): record is Extract<Control, { leaves: number[] }> => record.kind === 'DO' || record.kind === '?DO'); if (loop === undefined) this.mismatch(raw); loop.leaves.push(this.emit({ kind: 'leave', raw, target: 0 })); return; }
        if (name === 'CASE') { this.emit({ kind: 'noop', raw }); this.control.push({ kind: 'CASE', index, endofs: [] }); return; }
        if (name === 'OF') { if (top === undefined || top.kind !== 'CASE') this.mismatch(raw); this.emit({ kind: 'of', raw, target: 0 }); this.control.push({ kind: 'OF', index }); return; }
        if (name === 'ENDOF') { if (top === undefined || top.kind !== 'OF') this.mismatch(raw); this.emit({ kind: 'jump', raw, target: 0 }); (definition.actions[top.index] as TargetedAction).target = index + 1; this.control.pop(); (this.control.at(-1)! as Extract<Control, { kind: 'CASE' }>).endofs.push(index); return; }
        if (name === 'ENDCASE') { if (top === undefined || top.kind !== 'CASE') this.mismatch(raw); this.emit({ kind: 'endcase', raw }); for (const endof of top.endofs) (definition.actions[endof] as TargetedAction).target = index + 1; this.control.pop(); return; }
        if (definition.locals.has(name)) { this.emit({ kind: 'local-get', raw, slot: definition.locals.get(name)! }); return; }
        const word = this.lookup(name); if (word !== null) { this.emit({ kind: 'call', raw, word }); return; }
        const value = this.number(raw); if (value === null) fail(raw, 'undefined word', -13n); this.emit({ kind: 'literal', raw, value });
    }
    assign(raw: string, kind: string): void {
        const name = this.name(raw), normalized = upper(name);
        if (kind === 'TO' && this.compiling !== null && this.compiling.locals.has(normalized)) { this.emit({ kind: 'local-set', raw, slot: this.compiling.locals.get(normalized)! }); return; }
        const word = this.lookup(name); if (word === null) fail(name, 'undefined word', -13n);
        if (word.kind !== (kind === 'TO' ? 'value' : 'defer')) fail(name, kind === 'TO' ? 'not a value' : 'not deferred');
        if (this.compiling !== null) this.emit({ kind: kind === 'TO' ? 'value-set' : 'defer-set', raw, word });
        else { const value = this.pop(1, raw)[0]; if (kind === 'TO') this.memory[word.address / 8] = value; else { if (!this.validToken(value)) fail(raw, 'invalid argument', -24n); word.deferred = value; } }
    }
    process(raw: string): void {
        const name = upper(raw);
        if (name === '\\') { this.position = this.line.length; return; }
        if (name === '(') { const end = this.line.indexOf(')', this.position); if (end < 0) fail(raw, 'unterminated comment'); this.position = end + 1; return; }
        if (this.compiling === null && compileOnly.has(name)) fail(raw, 'compile only');
        if (this.compiling !== null && interpretOnly.has(name)) fail(raw, 'interpret only');
        if (name === '."' || name === 'ABORT"') {
            const start = this.position + 1, end = this.line.indexOf('"', start); if (this.position === this.line.length || end < 0) fail(raw, 'unterminated string');
            const text = this.line.slice(start, end); this.position = end + 1;
            if (this.compiling === null) this.pending += text; else this.emit({ kind: name === '."' ? 'write' : 'abort', raw, text }); return;
        }
        if (name === 'TO' || name === 'IS') { this.assign(raw, name); return; }
        if (name === ':' || name === ':NONAME') {
            const wordName = name === ':' ? this.name(raw) : raw; if (name === ':') this.checkName(wordName);
            this.compiling = newWord(name === ':' ? upper(wordName) : ':NONAME', 'colon', this.memory.length * 8);
            this.compiling.rawName = wordName; this.compiling.anonymous = name === ':NONAME';
            this.control = []; return;
        }
        if (name === 'FORGET') {
            const name = this.name(raw), normalized = upper(name); let index = this.dictionary.length - 1; while (index >= 0 && this.dictionary[index].name !== normalized) index--;
            if (index < 0) fail(name, 'undefined word', -13n); this.memory.length = this.dictionary[index].here / 8; this.dictionary.length = index; return;
        }
        if (this.compiling !== null) { this.compile(raw); return; }
        const word = this.lookup(name); if (word !== null) { this.execute(word, raw); return; }
        const value = this.number(raw); if (value === null) fail(raw, 'undefined word', -13n); this.push(value, raw);
    }
    run(line: string): void {
        this.line = line; this.position = 0;
        try { let word: string | null; while ((word = this.read()) !== null) this.process(word); }
        catch (error) { if (!(error instanceof ForthError)) throw error; if (this.pending.length) this.flush(); this.output.push(`ERROR ${error.word}: ${error.message}`); this.stack = []; this.returns = []; this.depth = 0; this.compiling = null; this.control = []; }
        if (this.pending.length) this.flush();
    }
}
const forth = new Forth();
for (const line of fs.readFileSync(0, 'utf8').split(/\r?\n/)) {
    if (line === 'BYE') { if (forth.compiling !== null) forth.output.push(`ERROR ${forth.compiling.rawName}: unterminated definition`); break; }
    forth.run(line);
}
if (forth.output.length) process.stdout.write(forth.output.join('\n') + '\n');
