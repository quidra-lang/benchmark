import { readFileSync } from 'node:fs';

type Word = number;
type ArgumentKind = 'name' | 'code' | 'number' | 'bits' | 'erasure';
interface Format {
    readonly types: readonly ArgumentKind[];
    readonly repeat: ArgumentKind | null;
    readonly maximum: number;
}
const format = (types: readonly ArgumentKind[], repeat: ArgumentKind | null = null, maximum = 0): Format =>
    ({ types, repeat, maximum });
const formats = {
    GEN: format(['name'], 'bits', 24), PCHECK: format(['name'], 'bits', 24),
    HAMMING: format(['name', 'number']), SIMPLEX: format(['name', 'number']),
    REPETITION: format(['name', 'number']), PARITY: format(['name', 'number']),
    RM: format(['name', 'number', 'number']), CYCLIC: format(['name', 'number', 'bits']),
    DUAL: format(['name', 'code']), EXTEND: format(['name', 'code']),
    PUNCTURE: format(['name', 'code', 'number']), SHORTEN: format(['name', 'code', 'number']),
    AUGMENT: format(['name', 'code']), EXPURGATE: format(['name', 'code']),
    PERMUTE: format(['name', 'code'], 'number', 24), DIRECTSUM: format(['name', 'code', 'code']),
    UUV: format(['name', 'code', 'code']), PRODUCT: format(['name', 'code', 'code']),
    LIST: format([]), DELETE: format(['code']), SHOW: format(['code']), INFO: format(['code']),
    SYSTEMATIC: format(['code']), WEIGHTS: format(['code']), COVERING: format(['code']),
    BURST: format(['code']), TRELLIS: format(['code']), STDARRAY: format(['code']), EQUAL: format(['code', 'code']),
    ENCODE: format(['code', 'bits']), SYNDROME: format(['code', 'bits']), DECODE: format(['code', 'bits']),
    BOUNDED: format(['code', 'number', 'bits']), COSET: format(['code', 'bits']), ERASURE: format(['code', 'erasure']),
    INTERLEAVE: format(['code', 'number', 'number'], 'bits', 8), CRC: format(['bits', 'bits']),
    CRCCHECK: format(['bits', 'bits']), FACTOR: format(['number']), MACWILLIAMS: format(['number'], 'number', 25),
    BOUNDS: format(['number', 'number']),
} as const;
type CommandName = keyof typeof formats;
const isCommandName = (name: string): name is CommandName => Object.hasOwn(formats, name);
const patterns: Readonly<Record<ArgumentKind, RegExp>> = {
    name: /^[A-Za-z][A-Za-z0-9]{0,7}$/, code: /^[A-Za-z][A-Za-z0-9]{0,7}$/,
    number: /^(0|[1-9][0-9]{0,3})$/, bits: /^[01]{1,30}$/, erasure: /^[01?]{1,30}$/,
};

type Definition = Readonly<
    { command: 'GEN' | 'PCHECK'; name: string; rows: readonly string[] } |
    { command: 'HAMMING' | 'SIMPLEX' | 'REPETITION' | 'PARITY'; name: string; parameter: number } |
    { command: 'RM'; name: string; order: number; variables: number } |
    { command: 'CYCLIC'; name: string; length: number; polynomial: string } |
    { command: 'DUAL' | 'EXTEND' | 'AUGMENT' | 'EXPURGATE'; name: string; source: Code } |
    { command: 'PUNCTURE' | 'SHORTEN'; name: string; source: Code; position: number } |
    { command: 'PERMUTE'; name: string; source: Code; order: readonly number[] } |
    { command: 'DIRECTSUM' | 'UUV' | 'PRODUCT'; name: string; source: Code; other: Code }
>;
type Inspection = Readonly<
    { command: 'SHOW' | 'INFO' | 'SYSTEMATIC' | 'WEIGHTS' | 'COVERING' | 'BURST' | 'TRELLIS' | 'STDARRAY'; name: string; code: Code } |
    { command: 'EQUAL'; name: string; code: Code; otherName: string; other: Code }
>;
type Encoding = Readonly<
    { command: 'ENCODE' | 'SYNDROME' | 'DECODE' | 'COSET' | 'ERASURE'; name: string; code: Code; text: string } |
    { command: 'BOUNDED'; name: string; code: Code; text: string; limit: number } |
    { command: 'INTERLEAVE'; name: string; code: Code; start: number; length: number; messages: readonly string[] }
>;
type Independent = Readonly<
    { command: 'CRC' | 'CRCCHECK'; generator: string; text: string } |
    { command: 'FACTOR'; length: number } |
    { command: 'MACWILLIAMS'; length: number; counts: readonly number[] } |
    { command: 'BOUNDS'; length: number; distance: number }
>;
type Command = Definition | Inspection | Encoding | Independent |
    Readonly<{ command: 'LIST' } | { command: 'DELETE'; name: string; code: Code }>;
const defining: ReadonlySet<CommandName> = new Set([
    'GEN', 'PCHECK', 'HAMMING', 'SIMPLEX', 'REPETITION', 'PARITY', 'RM', 'CYCLIC', 'DUAL',
    'EXTEND', 'PUNCTURE', 'SHORTEN', 'AUGMENT', 'EXPURGATE', 'PERMUTE', 'DIRECTSUM', 'UUV', 'PRODUCT',
]);
const isDefinition = (value: Command): value is Definition => defining.has(value.command);
class CommandError extends Error {}
function fail(reason: string): never { throw new CommandError(reason); }
function unreachable(value: never): never { throw new Error(`Unexpected command: ${String(value)}`); }

const bit = (word: Word, length: number, column: number): number => (word >>> (length - column - 1)) & 1;
const bits = (word: Word, length: number): string => word.toString(2).padStart(length, '0');
const degree = (word: Word): number => 31 - Math.clz32(word);
const yes = (value: boolean): string => value ? 'yes' : 'no';
function weight(word: Word): number {
    let count = 0;
    for (; word; word &= word - 1) ++count;
    return count;
}
function gcd(a: number, b: number): number {
    a = Math.abs(a); b = Math.abs(b);
    while (b) [a, b] = [b, a % b];
    return a;
}
interface Division { readonly quotient: Word; readonly remainder: Word }
function divide(dividend: Word, divisor: Word): Division {
    let quotient = 0;
    const d = degree(divisor);
    while (dividend && degree(dividend) >= d) {
        const shift = degree(dividend) - d;
        quotient ^= 1 << shift;
        dividend ^= divisor << shift;
    }
    return { quotient, remainder: dividend };
}
function basis(rows: readonly Word[], length: number): Word[] {
    const pivots = Array<Word>(length).fill(0), kept: Word[] = [];
    for (const original of rows) {
        let row = original;
        for (let column = 0; column < length; ++column) if (bit(row, length, column)) {
            if (pivots[column]) row ^= pivots[column];
            else { pivots[column] = row; kept.push(original); break; }
        }
    }
    return kept;
}
interface Echelon { readonly rows: readonly Word[]; readonly columns: readonly number[] }
function rref(original: readonly Word[], length: number): Echelon {
    const rows = original.slice(), columns: number[] = [];
    for (let column = 0; column < length; ++column) {
        const pivot = columns.length;
        const found = rows.findIndex((row, index) => index >= pivot && bit(row, length, column));
        if (found < 0) continue;
        [rows[pivot], rows[found]] = [rows[found], rows[pivot]];
        for (let row = 0; row < rows.length; ++row) if (row !== pivot && bit(rows[row], length, column)) rows[row] ^= rows[pivot];
        columns.push(column);
    }
    return { rows: rows.slice(0, columns.length), columns };
}
function nullspace(original: readonly Word[], length: number): Word[] {
    const { rows, columns } = rref(original, length), free: Word[] = [];
    for (let column = 0; column < length; ++column) if (!columns.includes(column)) {
        let word = 1 << (length - column - 1);
        for (let row = 0; row < rows.length; ++row) if (bit(rows[row], length, column)) word |= 1 << (length - columns[row] - 1);
        free.push(word);
    }
    return free;
}
function span(rows: readonly Word[]): Word[] {
    const words = [0];
    for (const row of rows) {
        const count = words.length;
        for (let index = 0; index < count; ++index) words.push(words[index] ^ row);
    }
    return words;
}
function distribution(words: readonly Word[], length: number): number[] {
    const counts = Array<number>(length + 1).fill(0);
    for (const word of words) ++counts[weight(word)];
    return counts;
}
const weightList = (counts: readonly number[]): string => counts.flatMap((count, index) => count ? [`${index}:${count}`] : []).join(' ');
function* fixedWeight(length: number, count: number): Generator<Word, void, unknown> {
    if (count === 0) { yield 0; return; }
    for (let word = 2 ** count - 1; word < 2 ** length;) {
        yield word;
        const lowest = word & -word, next = word + lowest;
        word = next | (((next ^ word) >>> 2) / lowest);
    }
}
function dimension(length: number, rank: number): void {
    if (rank < 1 || rank > 12 || length - rank < 1 || length - rank > 12) fail(`bad dimension ${length} ${rank}`);
}
function removeBit(word: Word, length: number, column: number): Word {
    const low = length - column - 1;
    return ((word >>> (low + 1)) << low) | (word & ((1 << low) - 1));
}
function reedMuller(order: number, variables: number): Word[] {
    const length = 1 << variables;
    if (order === 0) return [(1 << length) - 1];
    const half = length / 2;
    return [...reedMuller(Math.min(order, variables - 1), variables - 1).map(row => (row << half) | row),
        ...reedMuller(order - 1, variables - 1)];
}

interface Decoded { readonly error: Word; readonly word: Word; readonly message: Word }
class Code {
    readonly n: number;
    readonly k: number;
    readonly G: readonly Word[];
    readonly H: readonly Word[];
    readonly polynomial: Word | null;
    readonly words: readonly Word[];
    private readonly messages = new Map<Word, Word>();
    private leaderTable: readonly Word[] | null = null;
    constructor(length: number, generator: readonly Word[], check: readonly Word[] | null = null, polynomial: Word | null = null) {
        dimension(length, generator.length);
        this.n = length; this.k = generator.length;
        this.G = generator.slice(); this.H = check?.slice() ?? nullspace(generator, length);
        this.polynomial = polynomial;
        this.words = Array.from({ length: 1 << this.k }, (_, message) => {
            const word = this.encode(message);
            this.messages.set(word, message);
            return word;
        }).sort((a, b) => a - b);
    }
    get encoder(): 'matrix' | 'polynomial' { return this.polynomial === null ? 'matrix' : 'polynomial'; }
    contains(word: Word): boolean { return this.messages.has(word); }
    messageOf(word: Word): Word { return this.messages.get(word)!; }
    encode(message: Word): Word {
        if (this.polynomial !== null) {
            const shifted = message << (this.n - this.k);
            return shifted | divide(shifted, this.polynomial).remainder;
        }
        let word = 0;
        for (let row = 0; row < this.k; ++row) if (bit(message, this.k, row)) word ^= this.G[row];
        return word;
    }
    syndrome(word: Word): Word {
        let result = 0;
        for (const row of this.H) result = (result << 1) | (weight(row & word) % 2);
        return result;
    }
    leaders(): readonly Word[] {
        if (this.leaderTable !== null) return this.leaderTable;
        const result = Array<Word>(1 << (this.n - this.k)).fill(-1);
        let remaining = result.length;
        for (let count = 0; remaining; ++count) for (const word of fixedWeight(this.n, count)) {
            const syndrome = this.syndrome(word);
            if (result[syndrome] === -1) {
                result[syndrome] = word;
                if (--remaining === 0) break;
            }
        }
        this.leaderTable = result;
        return result;
    }
    decode(word: Word): Decoded {
        const error = this.leaders()[this.syndrome(word)], corrected = word ^ error;
        return { error, word: corrected, message: this.messageOf(corrected) };
    }
    decodedText(decoded: Decoded): string {
        return `codeword ${bits(decoded.word, this.n)} message ${bits(decoded.message, this.k)} error ${bits(decoded.error, this.n)} weight ${weight(decoded.error)}`;
    }
}

function construct(definition: Definition): Code {
    switch (definition.command) {
        case 'GEN': case 'PCHECK': {
            const n = definition.rows[0].length;
            if (definition.rows.some(row => row.length !== n)) fail('bad length');
            const rows = basis(definition.rows.map(row => parseInt(row, 2)), n);
            return definition.command === 'GEN' ? new Code(n, rows) : new Code(n, nullspace(rows, n), rows);
        }
        case 'HAMMING': case 'SIMPLEX': {
            const r = definition.parameter;
            if (r < 2 || r > 4) fail('bad parameter');
            const n = (1 << r) - 1, rows = Array<Word>(r).fill(0);
            for (let column = 1; column <= n; ++column) for (let row = 0; row < r; ++row) rows[row] = (rows[row] << 1) | bit(column, r, row);
            return definition.command === 'HAMMING' ? new Code(n, nullspace(rows, n), rows) : new Code(n, rows);
        }
        case 'REPETITION': case 'PARITY': {
            const n = definition.parameter;
            if (n < 2 || n > 24) fail('bad parameter');
            const rows = definition.command === 'REPETITION' ? [(1 << n) - 1] : Array.from({ length: n - 1 }, (_, row) => (1 << (n - row - 1)) | 1);
            return new Code(n, rows);
        }
        case 'RM': {
            const { order, variables } = definition;
            if (variables < 1 || variables > 4 || order > variables) fail('bad parameter');
            return new Code(1 << variables, reedMuller(order, variables));
        }
        case 'CYCLIC': {
            const { length: n, polynomial: text } = definition, d = text.length - 1;
            if (n < 2 || n > 24 || text[0] === '0' || text.length < 2 || text.length > n) fail('bad parameter');
            const polynomial = parseInt(text, 2);
            if (divide((1 << n) | 1, polynomial).remainder) fail('not a divisor');
            const k = n - d;
            dimension(n, k);
            const rows = Array.from({ length: k }, (_, row) => polynomial << (k - row - 1)), checks = Array<Word>(d).fill(0);
            for (let column = 0; column < n; ++column) {
                const residue = divide(1 << (n - column - 1), polynomial).remainder;
                for (let row = 0; row < d; ++row) checks[row] = (checks[row] << 1) | bit(residue, d, row);
            }
            return new Code(n, rows, checks, polynomial);
        }
        case 'DUAL': return new Code(definition.source.n, definition.source.H, definition.source.G);
        case 'EXTEND': return new Code(definition.source.n + 1, definition.source.G.map(row => (row << 1) | (weight(row) % 2)));
        case 'PUNCTURE': case 'SHORTEN': {
            const a = definition.source, column = definition.position - 1;
            if (column < 0 || column >= a.n) fail('bad position');
            let rows = a.G.slice();
            if (definition.command === 'SHORTEN') {
                const pivot = rows.findIndex(row => bit(row, a.n, column));
                if (pivot >= 0) {
                    const z = rows[pivot];
                    rows = rows.filter((_, index) => index !== pivot).map(row => bit(row, a.n, column) ? row ^ z : row);
                }
            }
            const n = a.n - 1;
            rows = rows.map(row => removeBit(row, a.n, column));
            return new Code(n, definition.command === 'PUNCTURE' ? basis(rows, n) : rows);
        }
        case 'AUGMENT': {
            const a = definition.source;
            return new Code(a.n, basis([...a.G, (1 << a.n) - 1], a.n));
        }
        case 'EXPURGATE': {
            const a = definition.source, pivot = a.G.findIndex(row => weight(row) % 2);
            const rows = pivot < 0 ? a.G : a.G.filter((_, index) => index !== pivot).map(row => weight(row) % 2 ? row ^ a.G[pivot] : row);
            return new Code(a.n, rows);
        }
        case 'PERMUTE': {
            const { source: a, order } = definition;
            if (order.length !== a.n || new Set(order).size !== a.n || order.some(column => column < 1 || column > a.n)) fail('bad permutation');
            return new Code(a.n, a.G.map(row => order.reduce((word, column) => (word << 1) | bit(row, a.n, column - 1), 0)));
        }
        case 'DIRECTSUM': case 'UUV': case 'PRODUCT': {
            const { source: a, other: b, command } = definition;
            if (command === 'UUV' && a.n !== b.n) fail('bad length');
            const n = command === 'PRODUCT' ? a.n * b.n : a.n + b.n;
            dimension(n, command === 'PRODUCT' ? a.k * b.k : a.k + b.k);
            const rows = command === 'PRODUCT' ? a.G.flatMap(x => b.G.map(y => {
                let word = 0;
                for (let column = 0; column < a.n; ++column) word = (word << b.n) | (bit(x, a.n, column) ? y : 0);
                return word;
            })) : [...a.G.map(row => (row << b.n) | (command === 'UUV' ? row : 0)), ...b.G];
            return new Code(n, rows);
        }
        default: return unreachable(definition);
    }
}

const choose: number[][] = Array.from({ length: 25 }, () => Array<number>(25).fill(0));
for (let n = 0; n <= 24; ++n) {
    choose[n][0] = choose[n][n] = 1;
    for (let k = 1; k < n; ++k) choose[n][k] = choose[n - 1][k - 1] + choose[n - 1][k];
}
const binomial = (n: number, k: number): number => k < 0 || k > n ? 0 : choose[n][k];

function systematic(name: string, code: Code): string[] {
    const { n, k } = code, rows = code.G.slice(), order = Array.from({ length: n }, (_, index) => index + 1);
    for (let pivot = 0; pivot < k; ++pivot) {
        let column = pivot;
        while (!rows.some((row, index) => index >= pivot && bit(row, n, column))) ++column;
        if (column !== pivot) {
            const mask = (1 << (n - pivot - 1)) | (1 << (n - column - 1));
            for (let row = 0; row < k; ++row) if (bit(rows[row], n, pivot) !== bit(rows[row], n, column)) rows[row] ^= mask;
            [order[pivot], order[column]] = [order[column], order[pivot]];
        }
        const found = rows.findIndex((row, index) => index >= pivot && bit(row, n, pivot));
        [rows[pivot], rows[found]] = [rows[found], rows[pivot]];
        for (let row = 0; row < k; ++row) if (row !== pivot && bit(rows[row], n, pivot)) rows[row] ^= rows[pivot];
    }
    const output = [`systematic ${name} perm ${order.join(' ')}`, ...rows.map(row => `G ${bits(row, n)}`)];
    for (let column = k; column < n; ++column) {
        let row = 0;
        for (const value of rows) row = (row << 1) | bit(value, n, column);
        row = (row << (n - k)) | (1 << (n - column - 1));
        output.push(`H ${bits(row, n)}`);
    }
    return output;
}
function burst(name: string, code: Code): string[] {
    const detect = Math.min(...code.words.slice(1).map(word => degree(word) - degree(word & -word)));
    const seen = new Set<Word>([0]);
    for (let length = 1; length <= code.n; ++length) {
        for (let start = 0; start + length <= code.n; ++start) {
            for (let middle = 0; middle < (length === 1 ? 1 : 1 << (length - 2)); ++middle) {
                const pattern = length === 1 ? 1 : (1 << (length - 1)) | (middle << 1) | 1;
                const syndrome = code.syndrome(pattern << (code.n - start - length));
                if (seen.has(syndrome)) return [`burst ${name} detect ${detect} correct ${length - 1}`];
                seen.add(syndrome);
            }
        }
    }
    throw new Error('Missing burst collision');
}
function inspect(command: Inspection): string[] {
    const { name, code } = command;
    switch (command.command) {
        case 'SHOW': {
            const output = [`code ${name} n ${code.n} k ${code.k} encoder ${code.encoder}`];
            if (code.polynomial !== null) output.push(`poly g ${bits(code.polynomial, code.n - code.k + 1)} h ${bits(divide((1 << code.n) | 1, code.polynomial).quotient, code.k + 1)}`);
            return [...output, ...code.G.map(row => `G ${bits(row, code.n)}`), ...code.H.map(row => `H ${bits(row, code.n)}`)];
        }
        case 'INFO': {
            const { n, k } = code, divisor = gcd(n, k), distance = Math.min(...code.words.slice(1).map(weight)), t = Math.floor((distance - 1) / 2);
            const volume = choose[n].slice(0, t + 1).reduce((a, b) => a + b, 0);
            const cyclic = code.G.every(row => code.contains(((row << 1) & ((1 << n) - 1)) | (row >>> (n - 1))));
            return [`info ${name} n ${n} k ${k} rate ${k / divisor}/${n / divisor} d ${distance} t ${t} perfect ${yes(volume === 2 ** (n - k))} mds ${yes(distance === n - k + 1)} cyclic ${cyclic ? code.words[1].toString(2) : 'no'}`];
        }
        case 'SYSTEMATIC': return systematic(name, code);
        case 'WEIGHTS': {
            const a = distribution(code.words, code.n), b = distribution(span(code.H), code.n);
            const orthogonal = code.G.every(x => code.G.every(y => weight(x & y) % 2 === 0));
            return [`weights ${name} ${weightList(a)}`, `dual ${name} ${weightList(b)}`,
                `duality ${name} self-orthogonal ${yes(orthogonal)} self-dual ${yes(orthogonal && code.n === 2 * code.k)} formally-self-dual ${yes(a.every((value, index) => value === b[index]))}`];
        }
        case 'COVERING': {
            const counts = distribution(code.leaders(), code.n);
            let radius = code.n;
            while (counts[radius] === 0) --radius;
            return [`covering ${name} radius ${radius} leaders ${counts.slice(0, radius + 1).map((count, index) => `${index}:${count}`).join(' ')}`];
        }
        case 'BURST': return burst(name, code);
        case 'TRELLIS': {
            const profile: number[] = [];
            for (let cut = 0; cut <= code.n; ++cut) {
                const right = code.n - cut, mask = (1 << right) - 1;
                profile.push(basis(code.G.map(row => row >>> right), cut).length + basis(code.G.map(row => row & mask), right).length - code.k);
            }
            return [`trellis ${name} profile ${profile.join(' ')} max ${Math.max(...profile)}`];
        }
        case 'STDARRAY': {
            if (code.n - code.k > 6 || code.k > 4) fail('too large');
            const leaders = [...code.leaders().entries()].sort(([, a], [, b]) => weight(a) - weight(b) || a - b);
            return [`stdarray ${name} rows ${leaders.length} columns ${code.words.length}`, ...leaders.map(([syndrome, leader]) =>
                `${bits(syndrome, code.n - code.k)}: ${code.words.map(word => bits(word ^ leader, code.n)).join(' ')}`)];
        }
        case 'EQUAL': {
            const { other, otherName } = command;
            if (code.n !== other.n) return [`equal ${name} ${otherName} no lengths ${code.n} ${other.n}`];
            const common = code.k + other.k - basis([...code.G, ...other.G], code.n).length;
            return [`equal ${name} ${otherName} ${yes(code.k === common && other.k === common)} intersection ${common}`];
        }
        default: return unreachable(command);
    }
}
function interleave(command: Extract<Encoding, { command: 'INTERLEAVE' }>): string[] {
    const { name, code, messages, start, length } = command, depth = messages.length;
    if (messages.some(message => message.length !== code.k)) fail('bad length');
    if (start < 1 || length < 1 || start + length - 1 > depth * code.n) fail('bad burst');
    const sentWords = messages.map(message => code.encode(parseInt(message, 2)));
    const receivedWords = Array<Word>(depth).fill(0), sent: number[] = [], received: number[] = [];
    for (let column = 0; column < code.n; ++column) for (let row = 0; row < depth; ++row) {
        const position = column * depth + row + 1, original = bit(sentWords[row], code.n, column);
        const changed = original ^ Number(start <= position && position < start + length);
        sent.push(original); received.push(changed);
        receivedWords[row] = (receivedWords[row] << 1) | changed;
    }
    const output = [`interleave ${name} depth ${depth} burst ${start} ${length}`, `sent ${sent.join('')}`, `recv ${received.join('')}`];
    let correct = 0;
    for (let row = 0; row < depth; ++row) {
        const decoded = code.decode(receivedWords[row]), message = bits(decoded.message, code.k), ok = message === messages[row];
        if (ok) ++correct;
        output.push(`row ${row + 1} errors ${weight(receivedWords[row] ^ sentWords[row])} corrected ${weight(decoded.error)} message ${message} ${ok ? 'ok' : 'wrong'}`);
    }
    output.push(`result ok ${correct} wrong ${depth - correct}`);
    return output;
}
function encodingReport(command: Encoding): string[] {
    if (command.command === 'INTERLEAVE') return interleave(command);
    const { name, code, text } = command;
    if (text.length !== (command.command === 'ENCODE' ? code.k : code.n)) fail('bad length');
    if (command.command === 'ENCODE') return [`encode ${name} message ${text} codeword ${bits(code.encode(parseInt(text, 2)), code.n)}`];
    if (command.command === 'ERASURE') {
        let mask = 0, known = 0, erased = 0;
        for (const character of text) {
            mask = (mask << 1) | Number(character !== '?');
            known = (known << 1) | Number(character === '1');
            if (character === '?') ++erased;
        }
        const candidates = code.words.filter(word => (word & mask) === known);
        const detail = candidates.length === 1 ? ` codeword ${bits(candidates[0], code.n)} message ${bits(code.messageOf(candidates[0]), code.k)}` : '';
        return [`erasure ${name} erased ${erased} candidates ${candidates.length}${detail}`];
    }
    const word = parseInt(text, 2), syndrome = code.syndrome(word);
    if (command.command === 'SYNDROME') return [`syndrome ${name} ${bits(syndrome, code.n - code.k)} codeword ${yes(syndrome === 0)}`];
    const decoded = code.decode(word);
    if (command.command === 'COSET') return [`coset ${name} syndrome ${bits(syndrome, code.n - code.k)} leader ${bits(decoded.error, code.n)} weights ${weightList(distribution(code.words.map(value => value ^ word), code.n))}`];
    if (command.command === 'BOUNDED' && weight(decoded.error) > command.limit) return [`bounded ${name} fail weight ${weight(decoded.error)}`];
    return [`${command.command.toLowerCase()} ${name} ${code.decodedText(decoded)}`];
}
function independent(command: Independent): string[] {
    if ('generator' in command) {
        const { generator, text } = command, d = generator.length - 1;
        if (generator[0] === '0' || generator.length < 2 || generator.length > 17) fail('bad parameter');
        if (command.command === 'CRC' && text.length + d > 30) fail('bad length');
        const word = parseInt(text, 2), divisor = parseInt(generator, 2);
        const remainder = divide(command.command === 'CRC' ? word << d : word, divisor).remainder, suffix = bits(remainder, d);
        return [command.command === 'CRC' ? `crc remainder ${suffix} frame ${text}${suffix}` : `crccheck ${remainder === 0 ? 'ok' : 'error'} remainder ${suffix}`];
    }
    const n = command.length;
    if (command.command === 'BOUNDS') {
        const d = command.distance;
        if (d < 1 || d > n || n > 24) fail('bad parameter');
        const volume = choose[n].slice(0, Math.floor((d - 1) / 2) + 1).reduce((a, b) => a + b, 0);
        let hamming = 0, griesmer = 0, sum = 0;
        for (let k = 0; k <= n; ++k) if (2 ** k * volume <= 2 ** n) hamming = k;
        for (let k = 1; k <= n; ++k) {
            sum += Math.ceil(d / 2 ** (k - 1));
            if (sum <= n) griesmer = k;
        }
        return [`bounds n ${n} d ${d} singleton ${n - d + 1} hamming ${hamming} griesmer ${griesmer}`];
    }
    if (n < 1 || n > 24) fail('bad parameter');
    if (command.command === 'FACTOR') {
        let remaining = (1 << n) | 1, divisors = 1;
        const factors: string[] = [];
        for (let candidate = 2; 2 * degree(candidate) <= degree(remaining); ++candidate) {
            let exponent = 0;
            while (divide(remaining, candidate).remainder === 0) {
                remaining = divide(remaining, candidate).quotient;
                ++exponent;
            }
            if (exponent) { factors.push(`${candidate.toString(2)}^${exponent}`); divisors *= exponent + 1; }
        }
        if (remaining > 1) { factors.push(`${remaining.toString(2)}^1`); divisors *= 2; }
        return [`factor ${n} ${factors.join(' ')} divisors ${divisors}`];
    }
    const counts = command.counts;
    if (counts.length !== n + 1) fail('bad length');
    if (counts[0] !== 1) fail('bad parameter');
    const size = counts.reduce((a, b) => a + b, 0), transformed: string[] = [];
    let feasible = (size & (size - 1)) === 0;
    for (let j = 0; j <= n; ++j) {
        let numerator = 0;
        for (let x = 0; x <= n; ++x) {
            let krawtchouk = 0;
            for (let y = 0; y <= j; ++y) krawtchouk += (y % 2 ? -1 : 1) * binomial(x, y) * binomial(n - x, j - y);
            numerator += counts[x] * krawtchouk;
        }
        const divisor = gcd(numerator, size), p = numerator / divisor, q = size / divisor;
        transformed.push(q === 1 ? String(p) : `${p}/${q}`);
        if (q !== 1 || p < 0) feasible = false;
    }
    return [`macwilliams n ${n} size ${size}`, `dual ${transformed.join(' ')}`, `feasible ${yes(feasible)}`];
}

class Laboratory {
    private readonly codes = new Map<string, Code>();
    private code(name: string): Code {
        const code = this.codes.get(name);
        if (!code) fail(`no code ${name}`);
        return code;
    }
    parse(line: string): Command {
        const [command, ...args] = line.split(' ');
        if (!isCommandName(command)) fail(`unknown command ${command}`);
        const spec = formats[command], extra = args.length - spec.types.length;
        if (spec.repeat === null ? extra !== 0 : extra < 1 || extra > spec.maximum) fail('bad arguments');
        for (let index = 0; index < args.length; ++index) {
            const kind = spec.types[index] ?? spec.repeat;
            if (kind === null || !patterns[kind].test(args[index])) fail('bad arguments');
        }
        for (let index = 0; index < spec.types.length; ++index) if (spec.types[index] === 'code') this.code(args[index]);
        const name = args[0];
        switch (command) {
            case 'GEN': case 'PCHECK': return { command, name, rows: args.slice(1) };
            case 'HAMMING': case 'SIMPLEX': case 'REPETITION': case 'PARITY': return { command, name, parameter: Number(args[1]) };
            case 'RM': return { command, name, order: Number(args[1]), variables: Number(args[2]) };
            case 'CYCLIC': return { command, name, length: Number(args[1]), polynomial: args[2] };
            case 'DUAL': case 'EXTEND': case 'AUGMENT': case 'EXPURGATE': return { command, name, source: this.code(args[1]) };
            case 'PUNCTURE': case 'SHORTEN': return { command, name, source: this.code(args[1]), position: Number(args[2]) };
            case 'PERMUTE': return { command, name, source: this.code(args[1]), order: args.slice(2).map(Number) };
            case 'DIRECTSUM': case 'UUV': case 'PRODUCT': return { command, name, source: this.code(args[1]), other: this.code(args[2]) };
            case 'LIST': return { command };
            case 'DELETE': case 'SHOW': case 'INFO': case 'SYSTEMATIC': case 'WEIGHTS': case 'COVERING': case 'BURST': case 'TRELLIS': case 'STDARRAY':
                return { command, name, code: this.code(name) };
            case 'EQUAL': return { command, name, code: this.code(name), otherName: args[1], other: this.code(args[1]) };
            case 'ENCODE': case 'SYNDROME': case 'DECODE': case 'COSET': case 'ERASURE': return { command, name, code: this.code(name), text: args[1] };
            case 'BOUNDED': return { command, name, code: this.code(name), limit: Number(args[1]), text: args[2] };
            case 'INTERLEAVE': return { command, name, code: this.code(name), start: Number(args[1]), length: Number(args[2]), messages: args.slice(3) };
            case 'CRC': case 'CRCCHECK': return { command, generator: args[0], text: args[1] };
            case 'FACTOR': return { command, length: Number(args[0]) };
            case 'MACWILLIAMS': return { command, length: Number(args[0]), counts: args.slice(1).map(Number) };
            case 'BOUNDS': return { command, length: Number(args[0]), distance: Number(args[1]) };
            default: return unreachable(command);
        }
    }
    execute(command: Command): string[] {
        if (isDefinition(command)) {
            const code = construct(command), replaced = this.codes.has(command.name);
            this.codes.set(command.name, code);
            return [`${replaced ? 'redefined' : 'defined'} ${command.name} n ${code.n} k ${code.k}`];
        }
        switch (command.command) {
            case 'LIST': return [`codes ${this.codes.size}`, ...[...this.codes].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
                .map(([name, code]) => `${name} n ${code.n} k ${code.k} encoder ${code.encoder}`)];
            case 'DELETE': this.codes.delete(command.name); return [`deleted ${command.name}`];
            case 'CRC': case 'CRCCHECK': case 'FACTOR': case 'MACWILLIAMS': case 'BOUNDS': return independent(command);
            case 'ENCODE': case 'SYNDROME': case 'DECODE': case 'BOUNDED': case 'COSET': case 'ERASURE': case 'INTERLEAVE': return encodingReport(command);
            default: return inspect(command);
        }
    }
}

const input = readFileSync(0, 'utf8').split('\n'), laboratory = new Laboratory();
for (let index = 1; index <= Number(input[0]); ++index) {
    try { process.stdout.write(laboratory.execute(laboratory.parse(input[index])).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`error: ${error.message}\n`);
    }
}
