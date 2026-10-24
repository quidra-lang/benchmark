import { readFileSync } from 'node:fs';

class CommandError extends Error {}
function fail(reason) { throw new CommandError(reason); }
const bit = (word, length, column) => (word >>> (length - column - 1)) & 1;
const bits = (word, length) => word.toString(2).padStart(length, '0');
const degree = word => 31 - Math.clz32(word);
const yes = value => value ? 'yes' : 'no';
function weight(word) {
    let count = 0;
    for (; word; word &= word - 1) ++count;
    return count;
}
function gcd(a, b) {
    a = Math.abs(a); b = Math.abs(b);
    while (b) [a, b] = [b, a % b];
    return a;
}
function divide(dividend, divisor) {
    let quotient = 0;
    const d = degree(divisor);
    while (dividend && degree(dividend) >= d) {
        const shift = degree(dividend) - d;
        quotient ^= 1 << shift;
        dividend ^= divisor << shift;
    }
    return { quotient, remainder: dividend };
}
function basis(rows, length) {
    const pivots = Array(length).fill(0), kept = [];
    for (const original of rows) {
        let row = original;
        for (let column = 0; column < length; ++column) if (bit(row, length, column)) {
            if (pivots[column]) row ^= pivots[column];
            else { pivots[column] = row; kept.push(original); break; }
        }
    }
    return kept;
}
function rref(original, length) {
    const rows = [...original], columns = [];
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
function nullspace(original, length) {
    const { rows, columns } = rref(original, length), free = [];
    for (let column = 0; column < length; ++column) if (!columns.includes(column)) {
        let word = 1 << (length - column - 1);
        for (let row = 0; row < rows.length; ++row) if (bit(rows[row], length, column)) word |= 1 << (length - columns[row] - 1);
        free.push(word);
    }
    return free;
}
function span(rows) {
    const words = [0];
    for (const row of rows) {
        const count = words.length;
        for (let index = 0; index < count; ++index) words.push(words[index] ^ row);
    }
    return words;
}
function distribution(words, length) {
    const counts = Array(length + 1).fill(0);
    for (const word of words) ++counts[weight(word)];
    return counts;
}
const weightList = counts => counts.flatMap((count, index) => count ? [`${index}:${count}`] : []).join(' ');
function* fixedWeight(length, count) {
    if (count === 0) { yield 0; return; }
    // Gosper's successor enumerates equal-weight vectors in lexicographic order.
    for (let word = 2 ** count - 1; word < 2 ** length;) {
        yield word;
        const lowest = word & -word, next = word + lowest;
        word = next | (((next ^ word) >>> 2) / lowest);
    }
}
function dimension(length, rank) {
    if (rank < 1 || rank > 12 || length - rank < 1 || length - rank > 12) fail(`bad dimension ${length} ${rank}`);
}
function removeBit(word, length, column) {
    const low = length - column - 1;
    return ((word >>> (low + 1)) << low) | (word & ((1 << low) - 1));
}
function reedMuller(order, variables) {
    const length = 1 << variables;
    if (order === 0) return [(1 << length) - 1];
    const half = length / 2;
    return [...reedMuller(Math.min(order, variables - 1), variables - 1).map(row => (row << half) | row),
        ...reedMuller(order - 1, variables - 1)];
}

class Code {
    constructor(length, generator, check = null, polynomial = null) {
        dimension(length, generator.length);
        this.n = length; this.k = generator.length;
        this.G = generator; this.H = check ?? nullspace(generator, length);
        this.polynomial = polynomial;
        this.messages = new Map();
        this.encoded = Array.from({ length: 1 << this.k }, (_, message) => {
            const word = this.encode(message);
            this.messages.set(word, message);
            return word;
        });
        this.words = [...this.encoded].sort((a, b) => a - b);
        this.leaderTable = null;
    }
    get encoder() { return this.polynomial === null ? 'matrix' : 'polynomial'; }
    encode(message) {
        if (this.polynomial !== null) {
            const shifted = message << (this.n - this.k);
            return shifted | divide(shifted, this.polynomial).remainder;
        }
        let word = 0;
        for (let row = 0; row < this.k; ++row) if (bit(message, this.k, row)) word ^= this.G[row];
        return word;
    }
    syndrome(word) {
        let result = 0;
        for (const row of this.H) result = (result << 1) | (weight(row & word) % 2);
        return result;
    }
    leaders() {
        if (this.leaderTable !== null) return this.leaderTable;
        const result = Array(1 << (this.n - this.k)).fill(-1);
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
    decode(word) {
        const error = this.leaders()[this.syndrome(word)], corrected = word ^ error;
        return { error, word: corrected, message: this.messages.get(corrected) };
    }
    decodedText(decoded) {
        return `codeword ${bits(decoded.word, this.n)} message ${bits(decoded.message, this.k)} error ${bits(decoded.error, this.n)} weight ${weight(decoded.error)}`;
    }
}

const formats = new Map();
function format(names, types, repeat = null, maximum = 0) {
    for (const name of names.split(' ')) formats.set(name, { types, repeat, maximum });
}
format('GEN PCHECK', ['name'], 'bits', 24);
format('HAMMING SIMPLEX REPETITION PARITY', ['name', 'number']);
format('RM', ['name', 'number', 'number']);
format('CYCLIC', ['name', 'number', 'bits']);
format('DUAL EXTEND AUGMENT EXPURGATE', ['name', 'code']);
format('PUNCTURE SHORTEN', ['name', 'code', 'number']);
format('PERMUTE', ['name', 'code'], 'number', 24);
format('DIRECTSUM UUV PRODUCT', ['name', 'code', 'code']);
format('LIST', []);
format('DELETE SHOW INFO SYSTEMATIC WEIGHTS COVERING BURST TRELLIS STDARRAY', ['code']);
format('EQUAL', ['code', 'code']);
format('ENCODE SYNDROME DECODE COSET', ['code', 'bits']);
format('BOUNDED', ['code', 'number', 'bits']);
format('ERASURE', ['code', 'erasure']);
format('INTERLEAVE', ['code', 'number', 'number'], 'bits', 8);
format('CRC CRCCHECK', ['bits', 'bits']);
format('FACTOR', ['number']);
format('MACWILLIAMS', ['number'], 'number', 25);
format('BOUNDS', ['number', 'number']);
const patterns = {
    name: /^[A-Za-z][A-Za-z0-9]{0,7}$/, code: /^[A-Za-z][A-Za-z0-9]{0,7}$/,
    number: /^(0|[1-9][0-9]{0,3})$/, bits: /^[01]{1,30}$/, erasure: /^[01?]{1,30}$/,
};
const defining = new Set('GEN PCHECK HAMMING SIMPLEX REPETITION PARITY RM CYCLIC DUAL EXTEND PUNCTURE SHORTEN AUGMENT EXPURGATE PERMUTE DIRECTSUM UUV PRODUCT'.split(' '));
const choose = Array.from({ length: 25 }, () => Array(25).fill(0));
for (let n = 0; n <= 24; ++n) {
    choose[n][0] = choose[n][n] = 1;
    for (let k = 1; k < n; ++k) choose[n][k] = choose[n - 1][k - 1] + choose[n - 1][k];
}
const binomial = (n, k) => k < 0 || k > n ? 0 : choose[n][k];

class Laboratory {
    codes = new Map();
    parse(line) {
        const [command, ...args] = line.split(' '), spec = formats.get(command);
        if (!spec) fail(`unknown command ${command}`);
        const extra = args.length - spec.types.length;
        if (spec.repeat === null ? extra !== 0 : extra < 1 || extra > spec.maximum) fail('bad arguments');
        for (let index = 0; index < args.length; ++index) if (!patterns[spec.types[index] ?? spec.repeat].test(args[index])) fail('bad arguments');
        for (let index = 0; index < spec.types.length; ++index) if (spec.types[index] === 'code' && !this.codes.has(args[index])) fail(`no code ${args[index]}`);
        return { command, args };
    }
    define(command, args) {
        const name = args[0], a = this.codes.get(args[1]), b = this.codes.get(args[2]);
        let n, G, H = null, polynomial = null;
        switch (command) {
            case 'GEN': case 'PCHECK': {
                const values = args.slice(1);
                n = values[0].length;
                if (values.some(value => value.length !== n)) fail('bad length');
                const rows = basis(values.map(value => parseInt(value, 2)), n);
                if (command === 'GEN') G = rows;
                else { H = rows; G = nullspace(H, n); }
                break;
            }
            case 'HAMMING': case 'SIMPLEX': {
                const r = Number(args[1]);
                if (r < 2 || r > 4) fail('bad parameter');
                n = (1 << r) - 1;
                const rows = Array(r).fill(0);
                for (let column = 1; column <= n; ++column) for (let row = 0; row < r; ++row) rows[row] = (rows[row] << 1) | bit(column, r, row);
                if (command === 'HAMMING') { H = rows; G = nullspace(H, n); }
                else G = rows;
                break;
            }
            case 'REPETITION': case 'PARITY': {
                n = Number(args[1]);
                if (n < 2 || n > 24) fail('bad parameter');
                G = command === 'REPETITION' ? [(1 << n) - 1] : Array.from({ length: n - 1 }, (_, row) => (1 << (n - row - 1)) | 1);
                break;
            }
            case 'RM': {
                const r = Number(args[1]), m = Number(args[2]);
                if (m < 1 || m > 4 || r > m) fail('bad parameter');
                n = 1 << m; G = reedMuller(r, m);
                break;
            }
            case 'CYCLIC': {
                n = Number(args[1]);
                const text = args[2], d = text.length - 1;
                if (n < 2 || n > 24 || text[0] === '0' || text.length < 2 || text.length > n) fail('bad parameter');
                polynomial = parseInt(text, 2);
                if (divide((1 << n) | 1, polynomial).remainder) fail('not a divisor');
                const k = n - d;
                dimension(n, k);
                G = Array.from({ length: k }, (_, row) => polynomial << (k - row - 1));
                H = Array(d).fill(0);
                for (let column = 0; column < n; ++column) {
                    const remainder = divide(1 << (n - column - 1), polynomial).remainder;
                    for (let row = 0; row < d; ++row) H[row] = (H[row] << 1) | bit(remainder, d, row);
                }
                break;
            }
            case 'DUAL': n = a.n; G = [...a.H]; H = [...a.G]; break;
            case 'EXTEND': n = a.n + 1; G = a.G.map(row => (row << 1) | (weight(row) % 2)); break;
            case 'PUNCTURE': case 'SHORTEN': {
                const column = Number(args[2]) - 1;
                if (column < 0 || column >= a.n) fail('bad position');
                let rows = [...a.G];
                if (command === 'SHORTEN') {
                    const pivot = rows.findIndex(row => bit(row, a.n, column));
                    if (pivot >= 0) {
                        const z = rows[pivot];
                        rows = rows.filter((_, index) => index !== pivot).map(row => bit(row, a.n, column) ? row ^ z : row);
                    }
                }
                n = a.n - 1; G = rows.map(row => removeBit(row, a.n, column));
                if (command === 'PUNCTURE') G = basis(G, n);
                break;
            }
            case 'AUGMENT': n = a.n; G = basis([...a.G, (1 << n) - 1], n); break;
            case 'EXPURGATE': {
                n = a.n;
                const pivot = a.G.findIndex(row => weight(row) % 2);
                G = pivot < 0 ? [...a.G] : a.G.filter((_, index) => index !== pivot).map(row => weight(row) % 2 ? row ^ a.G[pivot] : row);
                break;
            }
            case 'PERMUTE': {
                const order = args.slice(2).map(Number);
                if (order.length !== a.n || new Set(order).size !== a.n || order.some(column => column < 1 || column > a.n)) fail('bad permutation');
                n = a.n; G = a.G.map(row => order.reduce((word, column) => (word << 1) | bit(row, n, column - 1), 0));
                break;
            }
            case 'DIRECTSUM': case 'UUV': case 'PRODUCT': {
                if (command === 'UUV' && a.n !== b.n) fail('bad length');
                n = command === 'PRODUCT' ? a.n * b.n : a.n + b.n;
                dimension(n, command === 'PRODUCT' ? a.k * b.k : a.k + b.k);
                if (command === 'PRODUCT') G = a.G.flatMap(x => b.G.map(y => {
                    let word = 0;
                    for (let column = 0; column < a.n; ++column) word = (word << b.n) | (bit(x, a.n, column) ? y : 0);
                    return word;
                }));
                else G = [...a.G.map(row => (row << b.n) | (command === 'UUV' ? row : 0)), ...b.G];
                break;
            }
        }
        const code = new Code(n, G, H, polynomial), replaced = this.codes.has(name);
        this.codes.set(name, code);
        return [`${replaced ? 'redefined' : 'defined'} ${name} n ${n} k ${code.k}`];
    }
    systematic(name, code) {
        const { n, k } = code, rows = [...code.G], order = Array.from({ length: n }, (_, index) => index + 1);
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
    burst(name, code) {
        const detect = Math.min(...code.words.slice(1).map(word => degree(word) - degree(word & -word)));
        const seen = new Set([0]);
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
    }
    interleave(name, code, args) {
        const messages = args.slice(3), start = Number(args[1]), length = Number(args[2]), depth = messages.length;
        if (messages.some(message => message.length !== code.k)) fail('bad length');
        if (start < 1 || length < 1 || start + length - 1 > depth * code.n) fail('bad burst');
        const sentWords = messages.map(message => code.encode(parseInt(message, 2)));
        const receivedWords = Array(depth).fill(0), sent = [], received = [];
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
    execute({ command, args }) {
        if (defining.has(command)) return this.define(command, args);
        const name = args[0], code = this.codes.get(name);
        switch (command) {
            case 'LIST': return [`codes ${this.codes.size}`, ...[...this.codes].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
                .map(([id, value]) => `${id} n ${value.n} k ${value.k} encoder ${value.encoder}`)];
            case 'DELETE': this.codes.delete(name); return [`deleted ${name}`];
            case 'SHOW': {
                const output = [`code ${name} n ${code.n} k ${code.k} encoder ${code.encoder}`];
                if (code.polynomial !== null) output.push(`poly g ${bits(code.polynomial, code.n - code.k + 1)} h ${bits(divide((1 << code.n) | 1, code.polynomial).quotient, code.k + 1)}`);
                return [...output, ...code.G.map(row => `G ${bits(row, code.n)}`), ...code.H.map(row => `H ${bits(row, code.n)}`)];
            }
            case 'INFO': {
                const { n, k } = code, divisor = gcd(n, k), distance = Math.min(...code.words.slice(1).map(weight)), t = Math.floor((distance - 1) / 2);
                const volume = choose[n].slice(0, t + 1).reduce((a, b) => a + b, 0);
                const cyclic = code.G.every(row => code.messages.has(((row << 1) & ((1 << n) - 1)) | (row >>> (n - 1))));
                return [`info ${name} n ${n} k ${k} rate ${k / divisor}/${n / divisor} d ${distance} t ${t} perfect ${yes(volume === 2 ** (n - k))} mds ${yes(distance === n - k + 1)} cyclic ${cyclic ? code.words[1].toString(2) : 'no'}`];
            }
            case 'SYSTEMATIC': return this.systematic(name, code);
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
            case 'BURST': return this.burst(name, code);
            case 'TRELLIS': {
                const profile = [];
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
                const other = this.codes.get(args[1]);
                if (code.n !== other.n) return [`equal ${name} ${args[1]} no lengths ${code.n} ${other.n}`];
                const common = code.k + other.k - basis([...code.G, ...other.G], code.n).length;
                return [`equal ${name} ${args[1]} ${yes(code.k === common && other.k === common)} intersection ${common}`];
            }
            case 'ENCODE': {
                if (args[1].length !== code.k) fail('bad length');
                return [`encode ${name} message ${args[1]} codeword ${bits(code.encode(parseInt(args[1], 2)), code.n)}`];
            }
            case 'SYNDROME': case 'DECODE': case 'BOUNDED': case 'COSET': {
                const text = args[command === 'BOUNDED' ? 2 : 1];
                if (text.length !== code.n) fail('bad length');
                const word = parseInt(text, 2), syndrome = code.syndrome(word);
                if (command === 'SYNDROME') return [`syndrome ${name} ${bits(syndrome, code.n - code.k)} codeword ${yes(syndrome === 0)}`];
                const decoded = code.decode(word);
                if (command === 'COSET') return [`coset ${name} syndrome ${bits(syndrome, code.n - code.k)} leader ${bits(decoded.error, code.n)} weights ${weightList(distribution(code.words.map(value => value ^ word), code.n))}`];
                if (command === 'BOUNDED' && weight(decoded.error) > Number(args[1])) return [`bounded ${name} fail weight ${weight(decoded.error)}`];
                return [`${command.toLowerCase()} ${name} ${code.decodedText(decoded)}`];
            }
            case 'ERASURE': {
                const text = args[1];
                if (text.length !== code.n) fail('bad length');
                let mask = 0, known = 0, erased = 0;
                for (const character of text) {
                    mask = (mask << 1) | Number(character !== '?');
                    known = (known << 1) | Number(character === '1');
                    if (character === '?') ++erased;
                }
                const candidates = code.words.filter(word => (word & mask) === known);
                const detail = candidates.length === 1 ? ` codeword ${bits(candidates[0], code.n)} message ${bits(code.messages.get(candidates[0]), code.k)}` : '';
                return [`erasure ${name} erased ${erased} candidates ${candidates.length}${detail}`];
            }
            case 'INTERLEAVE': return this.interleave(name, code, args);
            default: return independent(command, args);
        }
    }
}

function independent(command, args) {
    if (command === 'CRC' || command === 'CRCCHECK') {
        const [generator, text] = args, d = generator.length - 1;
        if (generator[0] === '0' || generator.length < 2 || generator.length > 17) fail('bad parameter');
        if (command === 'CRC' && text.length + d > 30) fail('bad length');
        const word = parseInt(text, 2), divisor = parseInt(generator, 2);
        const remainder = divide(command === 'CRC' ? word << d : word, divisor).remainder, suffix = bits(remainder, d);
        return [command === 'CRC' ? `crc remainder ${suffix} frame ${text}${suffix}` : `crccheck ${remainder === 0 ? 'ok' : 'error'} remainder ${suffix}`];
    }
    const n = Number(args[0]);
    if (command === 'BOUNDS') {
        const d = Number(args[1]);
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
    if (command === 'FACTOR') {
        let remaining = (1 << n) | 1, divisors = 1;
        const factors = [];
        // Once all smaller factors are removed, a dividing candidate is irreducible.
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
    const counts = args.slice(1).map(Number);
    if (counts.length !== n + 1) fail('bad length');
    if (counts[0] !== 1) fail('bad parameter');
    const size = counts.reduce((a, b) => a + b, 0), transformed = [];
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

const input = readFileSync(0, 'utf8').split('\n'), laboratory = new Laboratory();
for (let index = 1; index <= Number(input[0]); ++index) {
    try { process.stdout.write(laboratory.execute(laboratory.parse(input[index])).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`error: ${error.message}\n`);
    }
}
