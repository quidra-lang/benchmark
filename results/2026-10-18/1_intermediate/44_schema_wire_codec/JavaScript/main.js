'use strict';

const fs = require('node:fs');
const maximum = 9007199254740991n;
const signedMinimum = -4503599627370496n;
const signedMaximum = 4503599627370495n;
const wireNames = new Map([[0, 'varint'], [1, 'i64'], [2, 'len'], [5, 'i32']]);

class CommandError extends Error {}
function fail(reason) { throw new CommandError(reason); }
const byteError = (reason, offset) => fail(`${reason} at byte ${offset}`);
const columnError = (reason, column) => fail(`${reason} at column ${column}`);
const hex = data => data.length === 0 ? '-' : data.toString('hex');
const rawText = raw => typeof raw === 'bigint' ? String(raw) : `<${raw.toString('hex')}>`;
const zigzag = value => value < 0n ? -2n * value - 1n : 2n * value;

class Schema {
    constructor(lines) {
        this.types = new Map();
        const integers = [
            ['uint32', 0, 0n, 4294967295n], ['uint64', 0, 0n, maximum],
            ['sint32', 0, -2147483648n, 2147483647n], ['sint64', 0, signedMinimum, signedMaximum],
            ['fixed32', 5, 0n, 4294967295n], ['sfixed32', 5, -2147483648n, 2147483647n],
            ['fixed64', 1, 0n, maximum],
        ];
        for (const [name, wire, minimum, maximum] of integers) this.types.set(name, { kind: 'integer', name, wire, minimum, maximum });
        for (const [name, wire] of [['bool', 0], ['string', 2], ['bytes', 2]]) this.types.set(name, { kind: name, name, wire });
        let current = null;
        this.nextLine = 0;
        while (lines[this.nextLine] !== 'END SCHEMA') {
            const words = lines[this.nextLine++].split(' ');
            if (words[0] === 'ENUM') {
                current = { kind: 'enum', name: words[1], wire: 0, values: [], byName: new Map(), byNumber: new Map() };
                this.types.set(current.name, current);
            } else if (words[0] === 'MESSAGE') {
                current = { kind: 'message', name: words[1], wire: 2, fields: [], byName: new Map(), byNumber: new Map() };
                this.types.set(current.name, current);
            } else if (words[0] === 'VALUE') {
                const name = words[1], number = BigInt(words[2]);
                current.values.push({ name, number });
                current.byName.set(name, number); current.byNumber.set(number, name);
            } else if (words[0] === 'FIELD') {
                current.fields.push({ number: Number(words[1]), typeName: words[2], name: words[3],
                    required: words[4] === 'REQUIRED', repeated: words[4] === 'REPEATED',
                    packed: words[5] === 'PACKED', group: words[4] === 'ONEOF' ? words[5] : null });
            } else current = null;
        }
        this.nextLine++;
        for (const type of this.types.values()) {
            if (type.kind === 'enum') type.values.sort((a, b) => a.number < b.number ? -1 : a.number > b.number ? 1 : 0);
            if (type.kind !== 'message') continue;
            type.fields.sort((a, b) => a.number - b.number);
            for (const field of type.fields) {
                field.type = this.types.get(field.typeName);
                type.byNumber.set(field.number, field); type.byName.set(field.name, field);
            }
        }
    }
    tree(type) {
        const lines = [type.name];
        const visit = (current, chain, depth) => {
            for (const field of current.fields) {
                const kind = field.required ? 'required ' : field.packed ? 'repeated packed '
                    : field.repeated ? 'repeated ' : field.group !== null ? `oneof ${field.group} ` : '';
                let line = '  '.repeat(depth) + `${field.number} ${field.name}: ${kind}${field.type.name}`;
                if (field.type.kind === 'enum') line += ` (${field.type.values.map(value => `${value.name}=${value.number}`).join(', ')})`;
                const recursive = field.type.kind === 'message' && chain.includes(field.type);
                if (recursive) line += ' (recursive)';
                lines.push(line);
                if (field.type.kind === 'message' && !recursive) visit(field.type, chain.concat(field.type), depth + 1);
            }
        };
        visit(type, [type], 1);
        return lines;
    }
}

class Message {
    constructor(type) { this.type = type; this.values = new Map(); this.unknown = []; }
    replace(field, values) {
        if (field.group !== null) {
            for (const other of this.type.fields) if (other !== field && other.group === field.group) this.values.delete(other.number);
        }
        if (values.length) this.values.set(field.number, values);
        else this.values.delete(field.number);
    }
    apply(field, values) {
        const previous = this.values.get(field.number) ?? [];
        if (field.repeated) this.replace(field, previous.concat(values));
        else if (field.type.kind === 'message' && previous.length) {
            previous[0].merge(values[0]); this.replace(field, previous);
        } else this.replace(field, values);
    }
    merge(other) {
        for (const field of this.type.fields) {
            const values = other.values.get(field.number);
            if (values) this.apply(field, values);
        }
        this.unknown = this.unknown.concat(other.unknown);
    }
    checkRequired(prefix = '') {
        for (const field of this.type.fields) {
            const values = this.values.get(field.number) ?? [];
            const path = prefix + field.name;
            if (field.required && values.length === 0) fail(`missing required field ${path}`);
            if (field.type.kind === 'message') values.forEach((value, index) => value.checkRequired(path + (field.repeated ? `[${index}]` : '') + '.'));
        }
    }
}

function varint(value) {
    const bytes = [];
    do {
        const low = Number(value % 128n); value /= 128n;
        bytes.push(low + (value === 0n ? 0 : 128));
    } while (value !== 0n);
    return Buffer.from(bytes);
}
function valueBytes(type, value) {
    if (value instanceof Message) return encode(value);
    if (typeof value === 'boolean') return varint(value ? 1n : 0n);
    if (typeof value === 'string') return Buffer.from(value, 'ascii');
    if (typeof value !== 'bigint') return value;
    if (type.name === 'sint32' || type.name === 'sint64') value = zigzag(value);
    if (type.wire === 0) return varint(value);
    if (type.name === 'sfixed32' && value < 0n) value += 4294967296n;
    const result = Buffer.alloc(type.wire === 5 ? 4 : 8);
    if (type.wire === 5) result.writeUInt32LE(Number(value));
    else result.writeBigUInt64LE(value);
    return result;
}
function record(number, wire, raw) {
    const tag = varint(BigInt(number) * 8n + BigInt(wire));
    if (wire === 0) return Buffer.concat([tag, varint(raw)]);
    return Buffer.concat(wire === 2 ? [tag, varint(BigInt(raw.length)), raw] : [tag, raw]);
}
function fieldBytes(field, values) {
    if (values.length === 0) return Buffer.alloc(0);
    if (field.packed) return record(field.number, 2, Buffer.concat(values.map(value => valueBytes(field.type, value))));
    const tag = varint(BigInt(field.number) * 8n + BigInt(field.type.wire));
    return Buffer.concat(values.map(value => {
        const bytes = valueBytes(field.type, value);
        return Buffer.concat(field.type.wire === 2 ? [tag, varint(BigInt(bytes.length)), bytes] : [tag, bytes]);
    }));
}
function encode(message) {
    const chunks = [];
    for (const field of message.type.fields) {
        const values = message.values.get(field.number);
        if (values) chunks.push(fieldBytes(field, values));
    }
    for (const unknown of message.unknown) chunks.push(record(unknown.number, unknown.wire, unknown.raw));
    return Buffer.concat(chunks);
}

function quote(text, json = false) {
    let result = '"';
    for (const character of text) {
        const code = character.charCodeAt(0);
        if (character === '"' || character === '\\') result += '\\' + character;
        else if (code === 10) result += '\\n';
        else if (code === 9) result += '\\t';
        else if (code >= 32 && code <= 126) result += character;
        else result += (json ? '\\u00' : '\\x') + code.toString(16).padStart(2, '0');
    }
    return result + '"';
}
function notation(type, value, json = false) {
    if (value instanceof Message) {
        const items = [];
        for (const field of type.fields) {
            const values = value.values.get(field.number);
            if (!values) continue;
            const name = json ? quote(field.name.replace(/_([a-z0-9])/g, (_, character) => character.toUpperCase())) : field.name;
            const text = field.repeated ? listNotation(field.type, values, json) : notation(field.type, values[0], json);
            items.push(name + (json ? ':' : ': ') + text);
        }
        return '{' + items.join(json ? ',' : ', ') + '}';
    }
    if (typeof value === 'bigint') {
        if (type.kind === 'enum') return json ? quote(type.byNumber.get(value)) : type.byNumber.get(value);
        return json && type.name.endsWith('64') ? quote(String(value)) : String(value);
    }
    if (typeof value === 'boolean') return String(value);
    if (typeof value === 'string') return quote(value, json);
    return json ? quote(value.toString('base64')) : rawText(value);
}
function listNotation(type, values, json = false) { return '[' + values.map(value => notation(type, value, json)).join(json ? ',' : ', ') + ']'; }
function textFormat(message) {
    const lines = [`${message.type.name} {`];
    const visit = (current, depth) => {
        const indent = '  '.repeat(depth);
        for (const field of current.type.fields) {
            for (const value of current.values.get(field.number) ?? []) {
                if (value instanceof Message) {
                    lines.push(`${indent}${field.name} {`); visit(value, depth + 1); lines.push(indent + '}');
                } else lines.push(`${indent}${field.name}: ${notation(field.type, value)}`);
            }
        }
        for (const unknown of current.unknown) lines.push(`${indent}${unknown.number}: ${wireNames.get(unknown.wire)} ${rawText(unknown.raw)}`);
    };
    visit(message, 1); lines.push('}');
    return lines;
}

class Reader {
    constructor(data, position = 0, end = data.length) { this.data = data; this.position = position; this.end = end; }
    varint() {
        const start = this.position;
        let value = 0n, place = 1n;
        for (let index = 0; index < 8; index++) {
            if (this.position === this.end) byteError('truncated varint', start);
            const byte = this.data[this.position++];
            value += BigInt(byte % 128) * place;
            if (byte < 128) {
                if (value > maximum) byteError('varint too large', start);
                return value;
            }
            if (index === 7) byteError('varint too long', start);
            place *= 128n;
        }
        throw new Error('Unreachable varint');
    }
    fixed(length) {
        const start = this.position;
        if (this.end - start < length) byteError(length === 4 ? 'truncated i32' : 'truncated i64', start);
        this.position += length;
        return this.data.subarray(start, this.position);
    }
    raw(wire) {
        const position = this.position;
        if (wire === 0) return { raw: this.varint(), position, start: position };
        if (wire !== 2) return { raw: this.fixed(wire === 5 ? 4 : 8), position, start: position };
        const length = this.varint(), start = this.position;
        if (length > BigInt(this.end - start)) byteError('length past end', position);
        this.position += Number(length);
        return { raw: this.data.subarray(start, this.position), position, start };
    }
}
class Decoder {
    constructor(data, explain = false) { this.data = data; this.explain = explain; this.lines = []; }
    convert(type, raw, position, start, depth) {
        if (type.kind === 'message') return this.message(type, start, start + raw.length, depth + 1);
        if (type.kind === 'bytes') return raw;
        if (type.kind === 'string') {
            for (let index = 0; index < raw.length; index++) if (raw[index] >= 128) byteError('invalid string', start + index);
            return raw.toString('ascii');
        }
        let value = typeof raw === 'bigint' ? raw : raw.length === 4 ? BigInt(raw.readUInt32LE()) : raw.readBigUInt64LE();
        if (type.kind === 'bool') {
            if (value !== 0n && value !== 1n) byteError('value out of range', position);
            return value === 1n;
        }
        if (type.kind === 'enum') {
            if (!type.byNumber.has(value)) byteError('unknown enum number', position);
            return value;
        }
        if (type.name === 'sint32' || type.name === 'sint64') value = value % 2n === 0n ? value / 2n : -(value + 1n) / 2n;
        if (type.name === 'sfixed32' && value >= 2147483648n) value -= 4294967296n;
        if (value < type.minimum || value > type.maximum) byteError('value out of range', position);
        return value;
    }
    message(type, start = 0, end = this.data.length, depth = 0) {
        const result = new Message(type), reader = new Reader(this.data, start, end);
        while (reader.position < end) {
            const offset = reader.position, tag = reader.varint();
            const number = Number(tag / 8n), wire = Number(tag % 8n);
            if (number === 0) byteError('invalid field number', offset);
            if (!wireNames.has(wire)) byteError('invalid wire type', offset);
            const field = type.byNumber.get(number);
            const packed = field && field.repeated && field.type.wire !== 2 && wire === 2;
            if (field && wire !== field.type.wire && !packed) byteError('wire type mismatch', offset);
            const value = reader.raw(wire);
            let line = '  '.repeat(depth) + `${offset} ${number} ${field ? field.name : '?'} ${wireNames.get(wire)}`;
            if (wire === 2) line += ` ${value.raw.length}`;
            if (!field) {
                if (this.explain) this.lines.push(line + ' ' + rawText(value.raw));
                else result.unknown.push({ number, wire, raw: value.raw });
                continue;
            }
            const values = [];
            if (packed) {
                const payload = new Reader(this.data, value.start, reader.position);
                while (payload.position < payload.end) {
                    const element = payload.raw(field.type.wire);
                    values.push(this.convert(field.type, element.raw, element.position, element.start, depth));
                }
                line += ' packed' + values.map(item => ' ' + notation(field.type, item)).join('');
            } else {
                if (this.explain && field.type.kind === 'message') this.lines.push(line);
                const item = this.convert(field.type, value.raw, value.position, value.start, depth);
                values.push(item);
                if (field.type.kind !== 'message') line += ' ' + notation(field.type, item);
            }
            if (this.explain) { if (field.type.kind !== 'message') this.lines.push(line); }
            else result.apply(field, values);
        }
        return result;
    }
    decode(type) { const result = this.message(type); result.checkRequired(); return result; }
}

function tokenize(text) {
    const tokens = [];
    let position = 0;
    while (position < text.length) {
        if (text[position] === ' ') { position++; continue; }
        const start = position, column = start + 1, character = text[position++];
        if ('{}[]:,'.includes(character)) { tokens.push({ kind: character, column }); continue; }
        if (character === '"') {
            let value = '', closed = false;
            while (position < text.length) {
                let next = text[position++];
                if (next === '"') { closed = true; break; }
                if (next === '\\') {
                    if (position === text.length) columnError('syntax error', column);
                    const escape = text[position++];
                    if (escape === '"' || escape === '\\') next = escape;
                    else if (escape === 'n') next = '\n';
                    else if (escape === 't') next = '\t';
                    else if (escape === 'x') {
                        const pair = text.slice(position, position + 2);
                        if (!/^[0-7][0-9a-f]$/.test(pair)) columnError('syntax error', column);
                        next = String.fromCharCode(parseInt(pair, 16)); position += 2;
                    } else columnError('syntax error', column);
                }
                value += next;
            }
            if (!closed) columnError('syntax error', column);
            tokens.push({ kind: 'string', value, column });
        } else if (character === '<') {
            const end = text.indexOf('>', position);
            const digits = text.slice(position, end);
            if (end < 0 || !/^(?:[0-9a-f]{2})*$/.test(digits)) columnError('syntax error', column);
            tokens.push({ kind: 'bytes', value: Buffer.from(digits, 'hex'), column }); position = end + 1;
        } else if (character === '-' || /[0-9]/.test(character)) {
            if (character === '-' && (position === text.length || !/[0-9]/.test(text[position]))) columnError('syntax error', column);
            while (position < text.length && /[0-9]/.test(text[position])) position++;
            tokens.push({ kind: 'integer', value: BigInt(text.slice(start, position)), column });
        } else if (/[A-Za-z_]/.test(character)) {
            while (position < text.length && /[A-Za-z0-9_]/.test(text[position])) position++;
            tokens.push({ kind: 'name', value: text.slice(start, position), column });
        } else columnError('syntax error', column);
    }
    tokens.push({ kind: 'end', column: text.length + 1 });
    return tokens;
}
function shape(token) {
    if (token.kind === '{') return 'message';
    if (token.kind === '[') return 'list';
    if (token.kind === 'name') return token.value === 'true' || token.value === 'false' ? 'bool' : 'enum';
    return ['integer', 'string', 'bytes'].includes(token.kind) ? token.kind : null;
}
class LiteralParser {
    constructor(text) { this.tokens = tokenize(text); this.position = 0; }
    get next() { return this.tokens[this.position]; }
    expect(kind) {
        const token = this.next;
        if (token.kind !== kind) columnError('syntax error', token.column);
        this.position++;
        return token;
    }
    finish() { if (this.next.kind !== 'end') columnError('syntax error', this.next.column); }
    message(type) {
        this.expect('{');
        const result = new Message(type), seen = new Set(), groups = new Set();
        if (this.next.kind !== '}') {
            while (true) {
                const token = this.next;
                if (token.kind !== 'name') columnError('syntax error', token.column);
                const field = type.byName.get(token.value);
                if (!field) columnError('unknown field', token.column);
                if (seen.has(field.number)) columnError('duplicate field', token.column);
                if (field.group !== null && groups.has(field.group)) columnError('oneof conflict', token.column);
                seen.add(field.number); if (field.group !== null) groups.add(field.group);
                this.position++; this.expect(':');
                result.replace(field, this.field(field));
                if (this.next.kind !== ',') break;
                this.position++;
            }
        }
        const closing = this.expect('}');
        for (const field of type.fields) if (field.required && !seen.has(field.number)) columnError(`missing required field ${field.name}`, closing.column);
        return result;
    }
    field(field) {
        if (!field.repeated) return [this.element(field.type)];
        const nextShape = shape(this.next);
        if (nextShape === null) columnError('syntax error', this.next.column);
        if (nextShape !== 'list') columnError('type mismatch', this.next.column);
        this.expect('[');
        const values = [];
        if (this.next.kind !== ']') {
            values.push(this.element(field.type));
            while (this.next.kind === ',') { this.position++; values.push(this.element(field.type)); }
        }
        this.expect(']');
        return values;
    }
    element(type) {
        const token = this.next, nextShape = shape(token);
        if (nextShape === null) columnError('syntax error', token.column);
        if (nextShape !== type.kind) columnError('type mismatch', token.column);
        if (type.kind === 'message') return this.message(type);
        this.position++;
        if (type.kind === 'integer') {
            if (token.value < type.minimum || token.value > type.maximum) columnError('out of range', token.column);
        } else if (type.kind === 'bool') return token.value === 'true';
        else if (type.kind === 'enum') {
            if (!type.byName.has(token.value)) columnError('unknown enum value', token.column);
            return type.byName.get(token.value);
        }
        return token.value;
    }
}

function parsePath(type, text) {
    const parts = text.split('.'), segments = [];
    let current = type;
    for (let position = 0; position < parts.length; position++) {
        const match = parts[position].match(/^([a-z][a-z0-9_]*)(?:\[([0-9]{1,6})\])?$/);
        if (!match) fail('invalid path');
        const field = current.byName.get(match[1]), index = match[2] === undefined ? null : Number(match[2]);
        if (!field || (index !== null && !field.repeated)) fail('invalid path');
        if (position + 1 < parts.length) {
            if (field.type.kind !== 'message' || (field.repeated && index === null)) fail('invalid path');
            current = field.type;
        }
        segments.push({ field, index });
    }
    return segments;
}
function parentAt(message, segments, create = false) {
    let current = message;
    for (const { field, index } of segments.slice(0, -1)) {
        let values = current.values.get(field.number) ?? [];
        if (index !== null && index >= values.length) {
            if (create) fail('index out of range');
            return null;
        }
        if (index === null && values.length === 0) {
            if (!create) return null;
            values = [new Message(field.type)]; current.replace(field, values);
        }
        current = values[index ?? 0];
    }
    return current;
}
function getPath(message, segments) {
    const parent = parentAt(message, segments), { field, index } = segments.at(-1);
    const values = parent?.values.get(field.number) ?? [];
    if (field.repeated && index === null) return listNotation(field.type, values);
    const value = values[index ?? 0];
    return value === undefined ? '(none)' : notation(field.type, value);
}
function patch(message, segments, text) {
    const { field, index } = segments.at(-1), parser = new LiteralParser(text);
    const replacement = field.repeated && index === null ? parser.field(field) : [parser.element(field.type)];
    parser.finish();
    const parent = parentAt(message, segments, true);
    if (index === null) parent.replace(field, replacement);
    else {
        const values = parent.values.get(field.number) ?? [];
        if (index >= values.length) fail('index out of range');
        values[index] = replacement[0];
    }
    message.checkRequired();
}
function clear(message, segments) {
    const parent = parentAt(message, segments), { field, index } = segments.at(-1);
    if (parent !== null) {
        if (index === null) parent.values.delete(field.number);
        else {
            const values = parent.values.get(field.number) ?? [];
            if (index < values.length) values.splice(index, 1);
            if (values.length === 0) parent.values.delete(field.number);
        }
    }
    message.checkRequired();
}
function differences(first, second) {
    const lines = [];
    const visit = (left, right, prefix) => {
        for (const field of left.type.fields) {
            const x = left.values.get(field.number) ?? [], y = right.values.get(field.number) ?? [];
            for (let index = 0; index < Math.max(x.length, y.length); index++) {
                const path = prefix + field.name + (field.repeated ? `[${index}]` : '');
                const a = x[index], b = y[index];
                if (a instanceof Message && b instanceof Message) visit(a, b, path + '.');
                else if (a === undefined || b === undefined || !(Buffer.isBuffer(a) && Buffer.isBuffer(b) ? a.equals(b) : a === b)) {
                    lines.push(`${path}: ${a === undefined ? '(none)' : notation(field.type, a)} -> ${b === undefined ? '(none)' : notation(field.type, b)}`);
                }
            }
        }
    };
    visit(first, second, '');
    return lines.length ? lines : ['SAME'];
}

const arities = new Map([
    ['VARINT', [2, 2]], ['ZIGZAG', [2, 2]], ['SCHEMA', [2, 2]], ['ENCODE', [3, Infinity]],
    ['SIZE', [3, Infinity]], ['DECODE', [3, 3]], ['LITERAL', [3, 3]], ['JSON', [3, 3]],
    ['CANON', [3, 3]], ['EXPLAIN', [3, 3]], ['GET', [4, 4]], ['PATCH', [5, Infinity]],
    ['CLEAR', [4, 4]], ['MERGE', [4, 4]], ['DIFF', [4, 4]],
]);
function fromHex(text) {
    if (text !== '-' && !/^(?:[0-9a-f]{2})+$/.test(text)) fail('invalid hex');
    return text === '-' ? Buffer.alloc(0) : Buffer.from(text, 'hex');
}
function decodePart(type, data, part) {
    try { return new Decoder(data).decode(type); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        fail(error.message + ' in ' + part);
    }
}
function execute(schema, line) {
    const words = line.split(' '), command = words[0], arity = arities.get(command);
    if (!arity) fail('unknown command');
    if (words.length < arity[0] || words.length > arity[1]) fail('wrong number of arguments');
    if (command === 'VARINT' || command === 'ZIGZAG') {
        if (!/^-?[0-9]{1,18}$/.test(words[1])) fail('invalid number');
        const value = BigInt(words[1]);
        if (command === 'VARINT') {
            if (value < 0n || value > maximum) fail('invalid number');
            return [hex(varint(value))];
        }
        if (value < signedMinimum || value > signedMaximum) fail('invalid number');
        const encoded = zigzag(value);
        return [`${encoded} ${hex(varint(encoded))}`];
    }
    const type = schema.types.get(words[1]);
    if (!type || type.kind !== 'message') fail('unknown message type');
    if (command === 'SCHEMA') return schema.tree(type);
    if (command === 'ENCODE' || command === 'SIZE') {
        const parser = new LiteralParser(words.slice(2).join(' '));
        const message = parser.message(type); parser.finish();
        const bytes = encode(message);
        if (command === 'ENCODE') return [hex(bytes)];
        let line = String(bytes.length);
        for (const field of type.fields) {
            const values = message.values.get(field.number);
            if (values) line += ` ${field.name}=${fieldBytes(field, values).length}`;
        }
        return [line];
    }
    const data = fromHex(words[2]);
    if (command === 'MERGE' || command === 'DIFF') {
        const second = fromHex(words[3]);
        if (command === 'MERGE') return textFormat(new Decoder(Buffer.concat([data, second])).decode(type));
        return differences(decodePart(type, data, 'first'), decodePart(type, second, 'second'));
    }
    const segments = ['GET', 'PATCH', 'CLEAR'].includes(command) ? parsePath(type, words[3]) : null;
    if (command === 'EXPLAIN') {
        const decoder = new Decoder(data, true); decoder.message(type);
        return decoder.lines.length ? decoder.lines : ['(empty)'];
    }
    const message = new Decoder(data).decode(type);
    switch (command) {
        case 'DECODE': return textFormat(message);
        case 'LITERAL': return [notation(type, message)];
        case 'JSON': return [notation(type, message, true)];
        case 'GET': return [getPath(message, segments)];
        case 'PATCH': patch(message, segments, words.slice(4).join(' ')); break;
        case 'CLEAR': clear(message, segments); break;
        case 'CANON': break;
        default: throw new Error('Unreachable command');
    }
    return [hex(encode(message))];
}

const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/);
const schema = new Schema(lines);
const count = Number(lines[schema.nextLine]);
for (let index = 0; index < count; index++) {
    try {
        for (const line of execute(schema, lines[schema.nextLine + 1 + index])) process.stdout.write(line + '\n');
    } catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write('ERROR ' + error.message + '\n');
    }
}
