import { readFileSync } from 'node:fs';

type Mode = 'RNE' | 'RNA' | 'RTZ' | 'RUP' | 'RDN';
type Sign = 0 | 1;
type Special = 'inf' | '-inf' | 'nan';
type IntegerType = 'I8' | 'U8' | 'I16' | 'U16' | 'I32' | 'U32';
type Comparison = 'LT' | 'EQ' | 'GT';
type PatternClass = 'zero' | 'subnormal' | 'normal' | 'infinity' | 'qnan' | 'snan';
type ArithmeticCommand = 'ADD' | 'SUB' | 'MUL' | 'DIV' | 'SQRT' | 'FMA';
type SummationCommand = 'SUM' | 'KAHAN';
type NeighborCommand = 'NEXTUP' | 'NEXTDOWN' | 'ULP';
type Command = ArithmeticCommand | SummationCommand | NeighborCommand | 'FORMAT' | 'ENCODE' | 'DECODE'
    | 'CONVERT' | 'COMPARE' | 'TOINT' | 'TABLE' | 'DOT';
interface Result { readonly pattern: number; readonly flags: number }
interface Fields { readonly sign: Sign; readonly exponent: number; readonly fraction: number; readonly q: number }
interface Units { readonly integer: bigint; readonly inexact: boolean }
type Real = { readonly kind: 'exact'; readonly value: Exact } | { readonly kind: 'special'; readonly value: Special };

const INVALID = 1, DIVBYZERO = 2, OVERFLOW = 4, UNDERFLOW = 8, INEXACT = 16;
const MODES: ReadonlySet<string> = new Set<Mode>(['RNE', 'RNA', 'RTZ', 'RUP', 'RDN']);
const TYPES = {
    I8: [-128n, 127n], U8: [0n, 255n], I16: [-32768n, 32767n], U16: [0n, 65535n],
    I32: [-2147483648n, 2147483647n], U32: [0n, 4294967295n],
} as const satisfies Record<IntegerType, readonly [bigint, bigint]>;
const ARITHMETIC: ReadonlySet<string> = new Set<ArithmeticCommand>(['ADD', 'SUB', 'MUL', 'DIV', 'SQRT', 'FMA']);

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
function modeOf(word = 'RNE'): Mode {
    if (!MODES.has(word)) fail(`BAD MODE ${word}`);
    return word as Mode;
}
function typeOf(word: string): IntegerType {
    if (!Object.hasOwn(TYPES, word)) fail(`BAD TYPE ${word}`);
    return word as IntegerType;
}
function isArithmetic(command: Command): command is ArithmeticCommand { return ARITHMETIC.has(command); }
function flagsText(flags: number): string {
    const names = ['invalid', 'divbyzero', 'overflow', 'underflow', 'inexact'];
    return 'flags=' + (names.filter((_, index) => (flags & (1 << index)) !== 0).join(',') || 'none');
}
const xorSign = (a: Sign, b: Sign): Sign => a === b ? 0 : 1;
const oppositeSign = (sign: Sign): Sign => sign === 0 ? 1 : 0;
const result = (pattern: number, flags = 0): Result => ({ pattern, flags });

function gcd(a: bigint, b: bigint): bigint {
    while (b !== 0n) [a, b] = [b, a % b];
    return a;
}
function scaled(numerator: bigint, denominator: bigint, exponent: number): readonly [bigint, bigint] {
    return exponent >= 0
        ? [numerator << BigInt(exponent), denominator]
        : [numerator, denominator << BigInt(-exponent)];
}
function integerSqrt(value: bigint): bigint {
    if (value === 0n) return 0n;
    let root = 1n << BigInt((value.toString(2).length + 1) >> 1);
    while (true) {
        const next = (root + value / root) >> 1n;
        if (next >= root) return root;
        root = next;
    }
}

// The magnitude is n * 2^e / d; the separate sign also represents negative zero.
class Exact {
    constructor(
        readonly n: bigint,
        readonly e = 0,
        readonly d = 1n,
        readonly sign: Sign = 0,
    ) {}

    negated(): Exact { return new Exact(this.n, this.e, this.d, oppositeSign(this.sign)); }
    log2Floor(): number {
        let exponent = this.n.toString(2).length - this.d.toString(2).length + this.e;
        const [n, d] = scaled(this.n, this.d, this.e - exponent);
        if (n < d) exponent--;
        return exponent;
    }
    fraction(): string {
        if (this.n === 0n) return '0';
        let [n, d] = scaled(this.n, this.d, this.e);
        const divisor = gcd(n, d);
        n /= divisor;
        d /= divisor;
        return (this.sign ? '-' : '') + n + (d === 1n ? '' : `/${d}`);
    }
    decimal(keepZeroSign = false): string {
        const [n, d] = scaled(this.n, this.d, this.e);
        let text = String(n / d);
        let remainder = n % d;
        if (remainder !== 0n) {
            text += '.';
            while (remainder !== 0n) {
                remainder *= 10n;
                text += remainder / d;
                remainder %= d;
            }
        }
        return (this.sign && (this.n !== 0n || keepZeroSign) ? '-' : '') + text;
    }
}
function exactProduct(a: Exact, b: Exact): Exact {
    return new Exact(a.n * b.n, a.e + b.e, a.d * b.d, xorSign(a.sign, b.sign));
}
function exactSum(terms: readonly Exact[], mode: Mode): Exact {
    const nonzero = terms.filter(term => term.n !== 0n);
    if (nonzero.length === 0) {
        const sameSign = terms.every(term => term.sign === terms[0].sign);
        return new Exact(0n, 0, 1n, sameSign ? terms[0].sign : mode === 'RDN' ? 1 : 0);
    }
    // Operands, products and differences entering a sum are dyadic (d = 1).
    const exponent = Math.min(...nonzero.map(term => term.e));
    let numerator = 0n;
    for (const term of nonzero) {
        const aligned = term.n << BigInt(term.e - exponent);
        numerator += term.sign ? -aligned : aligned;
    }
    const sign: Sign = numerator < 0n || numerator === 0n && mode === 'RDN' ? 1 : 0;
    return new Exact(numerator < 0n ? -numerator : numerator, exponent, 1n, sign);
}
function increment(mode: Mode, sign: Sign, integer: bigint, inexact: boolean, halfway: bigint): boolean {
    if (!inexact) return false;
    switch (mode) {
        case 'RNE': return halfway > 0n || halfway === 0n && integer % 2n === 1n;
        case 'RNA': return halfway >= 0n;
        case 'RTZ': return false;
        case 'RUP': return sign === 0;
        case 'RDN': return sign === 1;
    }
}
function roundedUnits(value: Exact, exponent: number, mode: Mode): Units {
    const [n, d] = scaled(value.n, value.d, value.e - exponent);
    let integer = n / d;
    const remainder = n % d;
    const inexact = remainder !== 0n;
    if (increment(mode, value.sign, integer, inexact, 2n * remainder - d)) integer++;
    return { integer, inexact };
}
function roundedSqrtUnits(value: Exact, exponent: number, mode: Mode): Units {
    const [n, d] = scaled(value.n, value.d, value.e - 2 * exponent);
    let integer = integerSqrt(n / d);
    const inexact = integer * integer * d !== n;
    const midpoint = 2n * integer + 1n;
    const halfway = 4n * n - d * midpoint * midpoint;
    if (increment(mode, 0, integer, inexact, halfway)) integer++;
    return { integer, inexact };
}

class MiniFormat {
    readonly w: number;
    readonly bias: number;
    readonly emin: number;
    readonly emax: number;
    readonly hidden: number;
    readonly exponentMask: number;
    readonly signBit: number;
    readonly infinity: number;
    readonly nan: number;
    readonly maximum: number;

    constructor(readonly name: string, readonly e: number, readonly m: number) {
        this.w = 1 + e + m;
        this.bias = (1 << (e - 1)) - 1;
        this.emin = 1 - this.bias;
        this.emax = this.bias;
        this.hidden = 1 << m;
        this.exponentMask = (1 << e) - 1;
        this.signBit = 1 << (e + m);
        this.infinity = this.exponentMask * this.hidden;
        this.nan = this.infinity + (this.hidden >> 1);
        this.maximum = this.infinity - 1;
    }
    fields(pattern: number): Fields {
        const sign: Sign = pattern & this.signBit ? 1 : 0;
        const exponent = (pattern >> this.m) & this.exponentMask;
        const fraction = pattern & (this.hidden - 1);
        const q = (exponent === 0 ? this.emin : exponent - this.bias) - this.m;
        return { sign, exponent, fraction, q };
    }
    isNaN(pattern: number): boolean {
        const field = this.fields(pattern);
        return field.exponent === this.exponentMask && field.fraction !== 0;
    }
    isSignaling(pattern: number): boolean { return this.isNaN(pattern) && this.fields(pattern).fraction < (this.hidden >> 1); }
    isInfinity(pattern: number): boolean { return (pattern & (this.signBit - 1)) === this.infinity; }
    isZero(pattern: number): boolean { return (pattern & (this.signBit - 1)) === 0; }
    isFinite(pattern: number): boolean { return this.fields(pattern).exponent !== this.exponentMask; }
    classification(pattern: number): PatternClass {
        if (this.isNaN(pattern)) return this.isSignaling(pattern) ? 'snan' : 'qnan';
        if (this.isInfinity(pattern)) return 'infinity';
        if (this.isZero(pattern)) return 'zero';
        return this.fields(pattern).exponent === 0 ? 'subnormal' : 'normal';
    }
    zero(sign: Sign): number { return sign * this.signBit; }
    inf(sign: Sign): number { return this.zero(sign) + this.infinity; }
    flip(pattern: number): number { return pattern ^ this.signBit; }
    exact(pattern: number): Exact {
        const field = this.fields(pattern);
        return new Exact(BigInt(field.exponent === 0 ? field.fraction : this.hidden + field.fraction), field.q, 1n, field.sign);
    }
    bits(pattern: number): string {
        const field = this.fields(pattern);
        return `${field.sign}|${field.exponent.toString(2).padStart(this.e, '0')}|${field.fraction.toString(2).padStart(this.m, '0')}`;
    }
    hex(pattern: number): string { return '0x' + pattern.toString(16).toUpperCase().padStart((this.w + 3) >> 2, '0'); }
    value(pattern: number): string {
        if (this.isNaN(pattern)) return 'nan';
        if (this.isInfinity(pattern)) return this.fields(pattern).sign ? '-inf' : 'inf';
        return this.exact(pattern).decimal(true);
    }
    patternText(pattern: number): string { return `${this.bits(pattern)} ${this.hex(pattern)} ${this.value(pattern)}`; }
    resultText(value: Result): string { return `${this.patternText(value.pattern)} ${flagsText(value.flags)}`; }
    overflow(sign: Sign, mode: Mode): Result {
        const infinite = mode === 'RNE' || mode === 'RNA' || mode === 'RUP' && sign === 0 || mode === 'RDN' && sign === 1;
        return result(this.zero(sign) + (infinite ? this.infinity : this.maximum), OVERFLOW | INEXACT);
    }
    private finishRound(sign: Sign, order: number, exponent: number, units: Units, unbounded: () => Units, mode: Mode): Result {
        const hidden = BigInt(this.hidden);
        let n = units.integer;
        if (n === 2n * hidden) {
            n = hidden;
            exponent++;
        }
        if (exponent > this.emax - this.m) return this.overflow(sign, mode);
        const magnitude = n >= hidden ? (exponent + this.m + this.bias) * this.hidden + Number(n - hidden) : Number(n);
        let flags = units.inexact ? INEXACT : 0;
        if (units.inexact && order < this.emin && (order < this.emin - 1 || unbounded().integer < 2n * hidden)) flags |= UNDERFLOW;
        return result(this.zero(sign) + magnitude, flags);
    }
    round(value: Exact, mode: Mode): Result {
        if (value.n === 0n) return result(this.zero(value.sign));
        const order = value.log2Floor();
        if (order > this.emax) return this.overflow(value.sign, mode);
        const exponent = Math.max(order, this.emin) - this.m;
        return this.finishRound(value.sign, order, exponent, roundedUnits(value, exponent, mode),
            () => roundedUnits(value, order - this.m, mode), mode);
    }
    sqrt(value: Exact, mode: Mode): Result {
        const log = value.log2Floor();
        const order = log >= 0 ? log >> 1 : -((-log + 1) >> 1);
        const exponent = Math.max(order, this.emin) - this.m;
        return this.finishRound(0, order, exponent, roundedSqrtUnits(value, exponent, mode),
            () => roundedSqrtUnits(value, order - this.m, mode), mode);
    }
}

function parseReal(word: string): Real {
    if (word === 'nan' || word === 'inf' || word === '-inf') return { kind: 'special', value: word };
    if (word.startsWith('0b') || word.startsWith('0x')) fail(`BAD OPERAND ${word}`);
    const sign: Sign = word.startsWith('-') ? 1 : 0;
    const body = sign ? word.slice(1) : word;
    if (body.includes('/')) {
        const [p, q] = body.split('/').map(BigInt);
        if (q === 0n) fail(`BAD OPERAND ${word}`);
        return { kind: 'exact', value: new Exact(p, 0, q, sign) };
    }
    const [whole, fraction = ''] = body.split('.');
    return { kind: 'exact', value: new Exact(BigInt(whole + fraction), 0, 10n ** BigInt(fraction.length), sign) };
}
function encoded(format: MiniFormat, real: Real, mode: Mode): Result {
    if (real.kind === 'exact') return format.round(real.value, mode);
    if (real.value === 'nan') return result(format.nan);
    return result(format.inf(real.value === '-inf' ? 1 : 0));
}
function operand(format: MiniFormat, word: string): number {
    if (word.startsWith('0b')) {
        if (word.length - 2 !== format.w) fail(`BAD OPERAND ${word}`);
        return Number(BigInt(word));
    }
    if (word.startsWith('0x')) {
        const pattern = Number(BigInt(word));
        if (word.length - 2 !== ((format.w + 3) >> 2) || pattern >= (1 << format.w)) fail(`BAD OPERAND ${word}`);
        return pattern;
    }
    return encoded(format, parseReal(word), 'RNE').pattern;
}
function operation(format: MiniFormat, command: ArithmeticCommand, inputs: readonly number[], mode: Mode): Result {
    if (command === 'SUB') return operation(format, 'ADD', [inputs[0], format.flip(inputs[1])], mode);
    if (inputs.some(pattern => format.isNaN(pattern))) {
        return result(format.nan, inputs.some(pattern => format.isSignaling(pattern)) ? INVALID : 0);
    }
    const [a, b, c] = inputs;
    const invalid = (): Result => result(format.nan, INVALID);
    const sign = format.fields(a).sign;
    if (command === 'SQRT') {
        if (format.isZero(a)) return result(a);
        if (sign) return invalid();
        if (format.isInfinity(a)) return result(a);
        return format.sqrt(format.exact(a), mode);
    }
    const sigma = xorSign(sign, format.fields(b).sign);
    switch (command) {
        case 'ADD':
            if (format.isInfinity(a) && format.isInfinity(b) && sigma) return invalid();
            if (format.isInfinity(a)) return result(a);
            if (format.isInfinity(b)) return result(b);
            return format.round(exactSum([format.exact(a), format.exact(b)], mode), mode);
        case 'MUL':
            if (format.isInfinity(a) || format.isInfinity(b)) return format.isZero(a) || format.isZero(b) ? invalid() : result(format.inf(sigma));
            if (format.isZero(a) || format.isZero(b)) return result(format.zero(sigma));
            return format.round(exactProduct(format.exact(a), format.exact(b)), mode);
        case 'DIV': {
            if (format.isInfinity(a)) return format.isInfinity(b) ? invalid() : result(format.inf(sigma));
            if (format.isInfinity(b)) return result(format.zero(sigma));
            if (format.isZero(b)) return format.isZero(a) ? invalid() : result(format.inf(sigma), DIVBYZERO);
            if (format.isZero(a)) return result(format.zero(sigma));
            const x = format.exact(a), y = format.exact(b);
            return format.round(new Exact(x.n * y.d, x.e - y.e, x.d * y.n, sigma), mode);
        }
        case 'FMA':
            if (format.isInfinity(a) || format.isInfinity(b)) {
                if (format.isZero(a) || format.isZero(b) || format.isInfinity(c) && format.fields(c).sign !== sigma) return invalid();
                return result(format.inf(sigma));
            }
            if (format.isInfinity(c)) return result(c);
            return format.round(exactSum([exactProduct(format.exact(a), format.exact(b)), format.exact(c)], mode), mode);
    }
}
function nextUp(format: MiniFormat, pattern: number): number {
    if (pattern === format.infinity) return pattern;
    if (format.isZero(pattern)) return 1;
    return pattern + (format.fields(pattern).sign ? -1 : 1);
}
function difference(format: MiniFormat, pattern: number, exact: Exact): string {
    if (!format.isFinite(pattern)) return format.value(pattern);
    return exactSum([format.exact(pattern), exact.negated()], 'RNE').fraction();
}
const relation = (a: number, b: number): Comparison => a < b ? 'LT' : a > b ? 'GT' : 'EQ';

class Laboratory {
    private readonly formats = new Map<string, MiniFormat>([
        ['HALF', new MiniFormat('HALF', 5, 10)], ['E5M2', new MiniFormat('E5M2', 5, 2)], ['E4M3', new MiniFormat('E4M3', 4, 3)],
    ]);
    readonly output: string[] = [];

    emit(line: string): void { this.output.push(line); }
    private format(name: string): MiniFormat {
        const format = this.formats.get(name);
        if (!format) fail(`UNKNOWN FORMAT ${name}`);
        return format;
    }
    private summary(format: MiniFormat, mode: Mode, patterns: readonly number[], pattern: number, flags: number): void {
        const exact = exactSum(patterns.map(pattern => format.exact(pattern)), mode);
        this.emit(`RESULT ${format.resultText(result(pattern, flags))}`);
        this.emit(`EXACT ${exact.decimal()}`);
        this.emit(`ROUNDED ${format.resultText(format.round(exact, mode))}`);
        this.emit(`DIFF ${difference(format, pattern, exact)}`);
    }
    private summation(command: SummationCommand, format: MiniFormat, mode: Mode, patterns: readonly number[]): void {
        if (patterns.some(pattern => !format.isFinite(pattern))) fail('NOT FINITE');
        this.emit(`${command} ${format.name} ${mode} count=${patterns.length}`);
        let sum = patterns[0], compensation = 0, flags = 0;
        for (let index = 1; index < patterns.length; index++) {
            if (command === 'SUM') {
                const added = operation(format, 'ADD', [sum, patterns[index]], mode);
                sum = added.pattern;
                flags |= added.flags;
                this.emit(`PARTIAL ${index + 1} ${format.resultText(added)}`);
            } else {
                const y = operation(format, 'SUB', [patterns[index], compensation], mode);
                const t = operation(format, 'ADD', [sum, y.pattern], mode);
                const d = operation(format, 'SUB', [t.pattern, sum], mode);
                const correction = operation(format, 'SUB', [d.pattern, y.pattern], mode);
                sum = t.pattern;
                compensation = correction.pattern;
                const stepFlags = y.flags | t.flags | d.flags | correction.flags;
                flags |= stepFlags;
                this.emit(`KSTEP ${index + 1} sum=${format.value(sum)} comp=${format.value(compensation)} ${flagsText(stepFlags)}`);
            }
        }
        this.summary(format, mode, patterns, sum, flags);
    }
    private dot(format: MiniFormat, mode: Mode, a: readonly number[], b: readonly number[]): void {
        if (a.length !== b.length) fail('LENGTH MISMATCH');
        if ([...a, ...b].some(pattern => !format.isFinite(pattern))) fail('NOT FINITE');
        let naive = operation(format, 'MUL', [a[0], b[0]], mode);
        let chained = naive;
        for (let index = 1; index < a.length; index++) {
            const product = operation(format, 'MUL', [a[index], b[index]], mode);
            const added = operation(format, 'ADD', [naive.pattern, product.pattern], mode);
            naive = result(added.pattern, naive.flags | product.flags | added.flags);
            const fused = operation(format, 'FMA', [a[index], b[index], chained.pattern], mode);
            chained = result(fused.pattern, chained.flags | fused.flags);
        }
        const exact = exactSum(a.map((pattern, index) => exactProduct(format.exact(pattern), format.exact(b[index]))), mode);
        this.emit(`DOT ${format.name} ${mode} n=${a.length}`);
        this.emit(`NAIVE ${format.resultText(naive)}`);
        this.emit(`CHAINED ${format.resultText(chained)}`);
        this.emit(`EXACT ${exact.decimal()}`);
        this.emit(`FUSED ${format.resultText(format.round(exact, mode))}`);
        this.emit(`DIFF naive=${difference(format, naive.pattern, exact)} chained=${difference(format, chained.pattern, exact)}`);
    }
    private table(format: MiniFormat): void {
        if (format.w > 8) fail('TABLE TOO LARGE');
        const count = format.infinity;
        this.emit(`TABLE ${format.name} count=${count}`);
        for (let pattern = 0; pattern < count; pattern++) {
            const gap = pattern === count - 1 ? '-'
                : exactSum([format.exact(pattern + 1), format.exact(pattern).negated()], 'RNE').decimal();
            this.emit(`ENTRY ${pattern} ${format.patternText(pattern)} gap=${gap}`);
        }
        this.emit(`MAX ${format.patternText(format.maximum)}`);
        this.emit(`MINNORMAL ${format.patternText(format.hidden)}`);
        this.emit(`MINSUBNORMAL ${format.patternText(1)}`);
        this.emit(`EPSILON ${new Exact(1n, -format.m).decimal()}`);
        this.emit(`PATTERNS finite=${2 * count} infinite=2 nan=${2 * (format.hidden - 1)} total=${1 << format.w}`);
    }
    execute(words: readonly string[]): void {
        // Command names and arities are guaranteed by the input grammar.
        const command = words[0] as Command;
        if (command === 'FORMAT') {
            const name = words[1], e = Number(words[2]), m = Number(words[3]);
            if (this.formats.has(name)) fail(`FORMAT EXISTS ${name}`);
            if (e < 2 || e > 5 || m < 1 || m > 10) fail('BAD FORMAT');
            const format = new MiniFormat(name, e, m);
            this.formats.set(name, format);
            this.emit(`FORMAT ${name} e=${e} m=${m} bits=${format.w} bias=${format.bias} emin=${format.emin} emax=${format.emax}`);
            return;
        }
        const format = this.format(words[1]);
        const name = format.name;
        if (command === 'ENCODE') {
            const real = parseReal(words[2]);
            const mode = modeOf(words[3]);
            const value = real.kind === 'special' ? real.value : real.value.fraction();
            this.emit(`ENCODE ${name} ${mode} ${value} ${format.resultText(encoded(format, real, mode))}`);
        } else if (command === 'CONVERT') {
            const target = this.format(words[2]);
            const a = operand(format, words[3]);
            const mode = modeOf(words[4]);
            const converted = format.isNaN(a) ? result(target.nan, format.isSignaling(a) ? INVALID : 0)
                : format.isInfinity(a) ? result(target.inf(format.fields(a).sign)) : target.round(format.exact(a), mode);
            this.emit(`CONVERT ${name} ${target.name} ${mode} ${target.resultText(converted)}`);
        } else if (command === 'SUM' || command === 'KAHAN' || command === 'DOT') {
            const mode = modeOf(words[2]);
            if (command === 'DOT') {
                const separator = words.indexOf('|');
                const a = words.slice(3, separator).map(word => operand(format, word));
                const b = words.slice(separator + 1).map(word => operand(format, word));
                this.dot(format, mode, a, b);
            } else this.summation(command, format, mode, words.slice(3).map(word => operand(format, word)));
        } else if (command === 'TABLE') this.table(format);
        else if (isArithmetic(command)) {
            const count = command === 'SQRT' ? 1 : command === 'FMA' ? 3 : 2;
            const patterns = words.slice(2, 2 + count).map(word => operand(format, word));
            const mode = modeOf(words[2 + count]);
            this.emit(`${command} ${name} ${mode} ${format.resultText(operation(format, command, patterns, mode))}`);
        } else {
            const a = operand(format, words[2]);
            const field = format.fields(a);
            if (command === 'DECODE') {
                this.emit(`DECODE ${name} ${format.bits(a)} ${format.hex(a)} ${format.classification(a)} sign=${field.sign}`);
                let line = `FIELDS exponent=${field.exponent} fraction=${field.fraction}`;
                if (format.isFinite(a)) {
                    line += ` unbiased=${field.q + format.m} significand=${field.exponent === 0 ? 0 : 1}.${field.fraction.toString(2).padStart(format.m, '0')}`;
                    this.emit(line);
                    this.emit(`VALUE ${format.exact(a).fraction()} ${format.value(a)}`);
                } else {
                    if (format.isNaN(a)) line += ` payload=${field.fraction % (format.hidden >> 1)}`;
                    this.emit(line);
                }
            } else if (command === 'COMPARE') {
                const b = operand(format, words[3]);
                const key = (pattern: number): number => format.fields(pattern).sign ? -(pattern - format.signBit) - 1 : pattern;
                const total = relation(key(a), key(b));
                const numeric: Comparison | 'UN' = format.isNaN(a) || format.isNaN(b) ? 'UN'
                    : format.isZero(a) && format.isZero(b) ? 'EQ' : total;
                const flags = format.isSignaling(a) || format.isSignaling(b) ? INVALID : 0;
                this.emit(`COMPARE ${name} ${format.hex(a)} ${format.hex(b)} ${numeric} total=${total} ${flagsText(flags)}`);
            } else if (command === 'TOINT') {
                const type = typeOf(words[3]);
                const mode = modeOf(words[4]);
                const prefix = `TOINT ${name} ${type} ${mode}`;
                if (!format.isFinite(a)) this.emit(`${prefix} invalid flags=invalid`);
                else {
                    const units = roundedUnits(format.exact(a), 0, mode);
                    const integer = field.sign ? -units.integer : units.integer;
                    const [minimum, maximum] = TYPES[type];
                    if (integer < minimum || integer > maximum) this.emit(`${prefix} invalid flags=invalid`);
                    else this.emit(`${prefix} ${integer} ${flagsText(units.inexact ? INEXACT : 0)}`);
                }
            } else {
                let value: Result;
                if (format.isNaN(a)) value = result(format.nan, format.isSignaling(a) ? INVALID : 0);
                else if (command === 'NEXTUP') value = result(nextUp(format, a));
                else if (command === 'NEXTDOWN') value = result(format.flip(nextUp(format, format.flip(a))));
                else value = result(format.isInfinity(a) ? format.infinity : format.round(new Exact(1n, field.q), 'RNE').pattern);
                this.emit(`${command} ${name} ${format.resultText(value)}`);
            }
        }
    }
}

const input = readFileSync(0, 'utf8').split(/\r?\n/);
const laboratory = new Laboratory();
for (const line of input.slice(1, Number(input[0]) + 1)) {
    try { laboratory.execute(line.split(' ')); }
    catch (problem) {
        if (!(problem instanceof CommandError)) throw problem;
        laboratory.emit(`ERROR ${problem.message}`);
    }
}
process.stdout.write(laboratory.output.join('\n') + '\n');
