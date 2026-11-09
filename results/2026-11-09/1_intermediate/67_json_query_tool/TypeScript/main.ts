import * as fs from 'node:fs';

type Value = null | boolean | number | string | Value[] | Map<string, Value>;
type Step = string | number;
type Match = { value: Value; path: Step[]; order: number[] };
type Selector = { kind: string; key?: string; index?: number; start?: number; end?: number; descendant: boolean };
function isIdentifier(text: string): boolean {
    return /^[A-Za-z_]/.test(text) && !/[^A-Za-z0-9_]/.test(text);
}
const integerNotation = /^(?:0|-?[1-9][0-9]{0,8})$/;
const escapeCodes: Record<string, string> = { b: '\b', f: '\f', n: '\n', r: '\r', t: '\t', '/': '/', '\\': '\\' };
class JsonFailure extends Error {
    constructor(public position: number, message: string) { super(message); }
}
function quote(text: string, delimiter = '"'): string {
    let result = delimiter;
    const escapes: Record<string, string> = { '\b': '\\b', '\f': '\\f', '\n': '\\n', '\r': '\\r', '\t': '\\t' };
    for (const char of text) {
        if (char === delimiter || char === '\\') result += '\\' + char;
        else if (Object.hasOwn(escapes, char)) result += escapes[char];
        else if (char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127) result += '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0');
        else result += char;
    }
    return result + delimiter;
}
function compact(value: Value): string {
    if (value instanceof Map) return '{' + [...value].map(([key, child]) => quote(key) + ':' + compact(child)).join(',') + '}';
    if (Array.isArray(value)) return '[' + value.map(compact).join(',') + ']';
    return typeof value === 'string' ? quote(value) : String(value);
}
function pretty(value: Value, indentation = ''): string {
    const next = indentation + '  ';
    if (value instanceof Map && value.size > 0) return '{\n' + [...value].map(([key, child]) => next + quote(key) + ': ' + pretty(child, next)).join(',\n') + '\n' + indentation + '}';
    if (Array.isArray(value) && value.length > 0) return '[\n' + value.map(child => next + pretty(child, next)).join(',\n') + '\n' + indentation + ']';
    return compact(value);
}
function clone(value: Value): Value {
    if (value instanceof Map) return new Map<string, Value>([...value].map(([key, child]) => [key, clone(child)]));
    return Array.isArray(value) ? value.map(clone) : value;
}
function typeName(value: Value): string {
    return value === null ? 'null' : value instanceof Map ? 'object' : Array.isArray(value) ? 'array' : typeof value;
}

class JsonReader {
    position = 0;
    constructor(public text: string) {}
    current(): string { return this.text[this.position] ?? ''; }
    fail(reason: string, position = this.position): never { throw new JsonFailure(position, reason); }
    whitespace(): void { while (this.current() === ' ' || this.current() === '\n') this.position++; }
    string(delimiter = '"'): string {
        this.position++;
        let result = '';
        while (true) {
            const char = this.current();
            if (char === '' || char === '\n') this.fail('unterminated string');
            if (char === delimiter) { this.position++; return result; }
            if (char !== '\\') { result += char; this.position++; continue; }
            const start = this.position;
            const escaped = this.text[start + 1] ?? '';
            if (escaped === '' || escaped === '\n') this.fail('unterminated string', start + 1);
            if (escaped === 'u') {
                const digits = this.text.slice(start + 2, start + 6);
                if (!/^[0-9A-Fa-f]{4}$/.test(digits)) this.fail('bad unicode escape', start);
                const code = parseInt(digits, 16);
                if (code > 127) this.fail('non-ascii escape', start);
                result += String.fromCharCode(code); this.position += 6;
            } else if (escaped === delimiter || Object.hasOwn(escapeCodes, escaped)) {
                result += escaped === delimiter ? delimiter : escapeCodes[escaped]; this.position += 2;
            } else this.fail(`invalid escape '\\${escaped}'`, start);
        }
    }
    number(): number {
        const start = this.position;
        const negative = this.current() === '-';
        if (negative) this.position++;
        const digitsStart = this.position;
        while (/^[0-9]$/.test(this.current())) this.position++;
        const digits = this.text.slice(digitsStart, this.position);
        if (digits.length === 0) this.fail('invalid number', start);
        if (digits.length > 1 && digits[0] === '0') this.fail('leading zero', digitsStart);
        if (this.current() === '.') this.fail('fraction not allowed');
        if (this.current() === 'e' || this.current() === 'E') this.fail('exponent not allowed');
        if (digits.length >= 10) this.fail('number out of range', start);
        return (negative ? -1 : 1) * Number(digits);
    }
    value(): Value {
        this.whitespace();
        const char = this.current();
        if (char === '') this.fail('unexpected end of input');
        if (char === '"') return this.string();
        if (char === '-' || /^[0-9]$/.test(char)) return this.number();
        if (/^[A-Za-z]$/.test(char)) {
            const start = this.position;
            while (/^[A-Za-z]$/.test(this.current())) this.position++;
            const word = this.text.slice(start, this.position);
            if (word === 'null') return null;
            if (word === 'true' || word === 'false') return word === 'true';
            this.fail(`invalid literal '${word}'`, start);
        }
        if (char === '{') {
            this.position++; this.whitespace();
            const object = new Map<string, Value>();
            if (this.current() === '}') { this.position++; return object; }
            while (true) {
                this.whitespace();
                if (this.current() === '') this.fail('unexpected end of input');
                if (this.current() !== '"') this.fail('expected key');
                const start = this.position;
                const key = this.string();
                if (object.has(key)) this.fail('duplicate key ' + quote(key), start);
                this.whitespace();
                if (this.current() === '') this.fail('unexpected end of input');
                if (this.current() !== ':') this.fail("expected ':'");
                this.position++; object.set(key, this.value()); this.whitespace();
                if (this.current() === '}') { this.position++; return object; }
                if (this.current() === '') this.fail('unexpected end of input');
                if (this.current() !== ',') this.fail("expected ',' or '}'");
                this.position++; this.whitespace();
                if (this.current() === '}') this.fail('trailing comma');
            }
        }
        if (char === '[') {
            this.position++; this.whitespace();
            const array: Value[] = [];
            if (this.current() === ']') { this.position++; return array; }
            while (true) {
                array.push(this.value()); this.whitespace();
                if (this.current() === ']') { this.position++; return array; }
                if (this.current() === '') this.fail('unexpected end of input');
                if (this.current() !== ',') this.fail("expected ',' or ']'");
                this.position++; this.whitespace();
                if (this.current() === ']') this.fail('trailing comma');
            }
        }
        this.fail(`unexpected character '${char}'`);
    }
    parse(): Value {
        const value = this.value(); this.whitespace();
        if (this.current() !== '') this.fail('trailing characters');
        return value;
    }
}
function path(text: string, field = false): Selector[] {
    try {
        if (text[0] !== (field ? '@' : '$')) throw new Error();
        const result: Selector[] = [];
        let position = 1;
        while (position < text.length) {
            let descendant = false;
            let bracket = false;
            if (!field && text.startsWith('..', position)) { descendant = true; position += 2; bracket = text[position] === '['; }
            else if (text[position] === '.') position++;
            else if (text[position] === '[') bracket = true;
            else throw new Error();
            let selector: Selector;
            if (bracket) {
                position++;
                if (text[position] === "'") {
                    const reader = new JsonReader(text); reader.position = position;
                    const key = reader.string("'"); position = reader.position;
                    if (text[position++] !== ']') throw new Error();
                    selector = { kind: 'key', key, descendant };
                } else {
                    const end = text.indexOf(']', position);
                    if (end < 0) throw new Error();
                    const selection = text.slice(position, end); position = end + 1;
                    if (integerNotation.test(selection)) selector = { kind: 'index', index: Number(selection), descendant };
                    else if (!field && selection === '*') selector = { kind: 'all', descendant };
                    else if (!field && selection.includes(':')) {
                        const parts = selection.split(':');
                        if (parts.length !== 2 || parts.some(part => part !== '' && !integerNotation.test(part))) throw new Error();
                        selector = { kind: 'slice', start: parts[0] === '' ? undefined : Number(parts[0]), end: parts[1] === '' ? undefined : Number(parts[1]), descendant };
                    } else throw new Error();
                }
            } else if (!field && text[position] === '*') { position++; selector = { kind: 'all', descendant }; }
            else {
                const name = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(position));
                if (name === null) throw new Error();
                position += name[0].length; selector = { kind: 'key', key: name[0], descendant };
            }
            result.push(selector);
        }
        return result;
    } catch { throw new Error(field ? 'bad field' : 'bad path'); }
}
function children(match: Match): Match[] {
    if (match.value instanceof Map) return [...match.value].map(([key, value], index) => ({ value, path: [...match.path, key], order: [...match.order, index] }));
    if (Array.isArray(match.value)) return match.value.map((value, index) => ({ value, path: [...match.path, index], order: [...match.order, index] }));
    return [];
}
function preorder(match: Match): Match[] {
    const result: Match[] = [];
    const pending = [match];
    while (pending.length > 0) {
        const next = pending.pop()!; result.push(next); pending.push(...children(next).reverse());
    }
    return result;
}
function select(match: Match, selector: Selector): Match[] {
    const all = children(match);
    if (selector.kind === 'all') return all;
    if (selector.kind === 'key') return match.value instanceof Map ? all.filter(child => child.path[child.path.length - 1] === selector.key) : [];
    if (!Array.isArray(match.value)) return [];
    const length = match.value.length;
    if (selector.kind === 'index') {
        const index = selector.index! < 0 ? length + selector.index! : selector.index!;
        return index >= 0 && index < length ? [all[index]] : [];
    }
    const bound = (value: number): number => Math.min(length, Math.max(0, value < 0 ? length + value : value));
    return all.slice(bound(selector.start ?? 0), bound(selector.end ?? length));
}
function applySegment(matches: Match[], selector: Selector): Match[] {
    return matches.flatMap(match => (selector.descendant ? preorder(match) : [match]).flatMap(value => select(value, selector)));
}
function evaluate(document: Value, selectors: Selector[]): Match[] {
    return selectors.reduce(applySegment, [{ value: document, path: [], order: [] }]);
}
function location(steps: Step[]): string {
    return '$' + steps.map(step => typeof step === 'number' ? `[${step}]` : isIdentifier(step) ? '.' + step : '[' + quote(step, "'") + ']').join('');
}
function fieldValue(value: Value, selectors: Selector[]): Value | undefined {
    let matches: Match[] = [{ value, path: [], order: [] }];
    for (const selector of selectors) matches = applySegment(matches, selector);
    return matches.length === 0 ? undefined : matches[0].value;
}
function equal(left: Value, right: Value): boolean {
    if (typeName(left) !== typeName(right)) return false;
    if (left instanceof Map && right instanceof Map) return left.size === right.size && [...left].every(([key, value]) => right.has(key) && equal(value, right.get(key)!));
    if (Array.isArray(left) && Array.isArray(right)) return left.length === right.length && left.every((value, index) => equal(value, right[index]));
    return left === right;
}
function compareKeys(left: Value | undefined, right: Value | undefined): number {
    const rank = (value: Value | undefined): number => value === null ? 0 : typeof value === 'number' ? 1 : typeof value === 'string' ? 2 : 3;
    const difference = rank(left) - rank(right);
    if (difference !== 0) return difference;
    if (typeof left === 'number' && typeof right === 'number') return left - right;
    if (typeof left === 'string' && typeof right === 'string') return left === right ? 0 : left < right ? -1 : 1;
    return 0;
}
function targets(matches: Match[]): Match[] {
    const unique = new Map<string, Match>();
    for (const match of matches) unique.set(JSON.stringify(match.path), match);
    return [...unique.values()].sort((a, b) => {
        for (let i = 0; i < Math.min(a.order.length, b.order.length); i++) if (a.order[i] !== b.order[i]) return b.order[i] - a.order[i];
        return b.order.length - a.order.length;
    });
}
function getAt(document: Value, steps: Step[]): Value {
    let value = document;
    for (const step of steps) value = typeof step === 'string' ? (value as Map<string, Value>).get(step)! : (value as Value[])[step];
    return value;
}
function putAt(document: Value, steps: Step[], value: Value): Value {
    if (steps.length === 0) return value;
    const parent = getAt(document, steps.slice(0, -1));
    const last = steps[steps.length - 1];
    if (typeof last === 'string') (parent as Map<string, Value>).set(last, value);
    else (parent as Value[])[last] = value;
    return document;
}
function merge(target: Map<string, Value>, source: Map<string, Value>): void {
    for (const [key, value] of source) {
        const previous = target.get(key);
        if (previous instanceof Map && value instanceof Map) merge(previous, value);
        else target.set(key, clone(value));
    }
}
function splitLimited(text: string, maximum: number): string[] {
    const result: string[] = [];
    let start = 0;
    while (result.length < maximum) {
        const space = text.indexOf(' ', start);
        if (space < 0) break;
        result.push(text.slice(start, space)); start = space + 1;
    }
    result.push(text.slice(start)); return result;
}

class QueryTool {
    document: Value = null;
    history: Value[] = [];
    output: string[] = [];
    load(lines: string[]): void {
        const text = lines.join('\n');
        try {
            const document = new JsonReader(text).parse();
            this.history.push(clone(this.document)); this.document = clone(document);
            const all = preorder({ value: document, path: [], order: [] });
            this.output.push(`LOADED nodes=${all.length} depth=${Math.max(...all.map(match => match.path.length + 1))}`);
        } catch (error) {
            const failure = error as JsonFailure;
            const before = text.slice(0, failure.position);
            const line = before.split('\n').length;
            const column = failure.position - before.lastIndexOf('\n');
            this.output.push(`PARSE ERROR line ${line} col ${column}: ${failure.message}`);
        }
    }
    execute(line: string): void {
        const space = line.indexOf(' ');
        const command = space < 0 ? line : line.slice(0, space);
        const argument = space < 0 ? null : line.slice(space + 1);
        const commands = new Set(['LOAD', 'GET', 'COMPACT', 'PRETTY', 'TYPE', 'LENGTH', 'KEYS', 'FLATTEN', 'COUNT', 'SUM', 'MIN', 'MAX', 'AVG', 'FILTER', 'SET', 'DELETE', 'INSERT', 'MERGE', 'SORT', 'RENAME', 'UNDO']);
        if (!commands.has(command)) throw new Error(`unknown command '${command}'`);
        let args = argument === null ? [] : argument.split(' ');
        if (command === 'SET' || command === 'MERGE') args = argument === null ? [] : splitLimited(argument, 1);
        if (command === 'INSERT') args = argument === null ? [] : splitLimited(argument, 2);
        if (command === 'FILTER') args = argument === null ? [] : splitLimited(argument, 3);
        const optional = ['COMPACT', 'PRETTY', 'FLATTEN'].includes(command);
        let shape = optional ? args.length <= 1 : command === 'UNDO' || command === 'LOAD' ? args.length === 0 : command === 'SET' || command === 'MERGE' || command === 'RENAME' ? args.length === 2 : command === 'INSERT' ? args.length === 3 : command === 'FILTER' ? args.length >= 3 && (args[2] === 'EXISTS' ? args.length === 3 : args.length === 4) : command === 'SORT' ? args.length >= 1 && args.length <= 3 && (args.length < 3 || args[1] !== 'DESC' && args[2] === 'DESC') : args.length === 1;
        if (!shape) throw new Error('bad arguments');
        if (command === 'UNDO') {
            if (this.history.length === 0) throw new Error('nothing to undo');
            this.document = clone(this.history.pop()!); this.output.push(`UNDO ${this.history.length}`); return;
        }
        const selectors = path(args[0] ?? '$');
        let field: Selector[] = [];
        let key = '';
        let value: Value = null;
        if (command === 'FILTER') {
            field = path(args[1], true);
            if (!['==', '!=', '<', '<=', '>', '>=', 'EXISTS'].includes(args[2])) throw new Error('bad operator');
            if (args[2] !== 'EXISTS') value = new JsonReader(args[3]).parse();
        } else if (command === 'SORT') field = path(args.length > 1 && args[1] !== 'DESC' ? args[1] : '@', true);
        else if (command === 'RENAME') {
            try {
                if (isIdentifier(args[1])) key = args[1];
                else { const reader = new JsonReader(args[1]); if (reader.current() !== "'") throw new Error(); key = reader.string("'"); if (reader.position !== args[1].length) throw new Error(); }
            } catch { throw new Error('bad key'); }
        } else if (command === 'SET' || command === 'MERGE') value = new JsonReader(args[1]).parse();
        else if (command === 'INSERT') {
            if (!integerNotation.test(args[1])) throw new Error('bad index');
            value = new JsonReader(args[2]).parse();
        }
        if (command === 'MERGE' && !(value instanceof Map)) throw new Error('merge value is not an object');
        if (command === 'DELETE' && selectors.length === 0) throw new Error('cannot delete root');
        let matches = evaluate(this.document, selectors);
        if (['FILTER', 'INSERT', 'SORT'].includes(command)) {
            const invalid = matches.find(match => !Array.isArray(match.value));
            if (invalid !== undefined) throw new Error('not an array at ' + location(invalid.path));
        }
        if (command === 'MERGE' || command === 'KEYS') {
            const invalid = matches.find(match => !(match.value instanceof Map));
            if (invalid !== undefined) throw new Error('not an object at ' + location(invalid.path));
        }
        if (command === 'LENGTH') {
            const invalid = matches.find(match => !(match.value instanceof Map) && !Array.isArray(match.value) && typeof match.value !== 'string');
            if (invalid !== undefined) throw new Error('no length at ' + location(invalid.path));
        }
        if (command === 'RENAME') {
            const invalid = matches.find(match => typeof match.path[match.path.length - 1] !== 'string');
            if (invalid !== undefined) throw new Error('not a member at ' + location(invalid.path));
        }
        if (command === 'INSERT') {
            const index = Number(args[1]);
            const invalid = matches.find(match => index < -(match.value as Value[]).length - 1 || index > (match.value as Value[]).length);
            if (invalid !== undefined) throw new Error('index out of range at ' + location(invalid.path));
        }
        if (command === 'FILTER') {
            const output: string[] = [];
            for (const match of matches) for (const child of children(match)) {
                const left = fieldValue(child.value, field);
                const operator = args[2];
                let accepted = operator === 'EXISTS' ? left !== undefined : operator === '==' ? left !== undefined && equal(left, value) : operator === '!=' ? left === undefined || !equal(left, value) : false;
                if (!['EXISTS', '==', '!='].includes(operator) && (typeof left === 'number' && typeof value === 'number' || typeof left === 'string' && typeof value === 'string')) {
                    const comparison = compareKeys(left, value);
                    accepted = operator === '<' ? comparison < 0 : operator === '<=' ? comparison <= 0 : operator === '>' ? comparison > 0 : comparison >= 0;
                }
                if (accepted) output.push(location(child.path) + ' = ' + compact(child.value));
            }
            this.output.push(...(output.length === 0 ? ['no match'] : output)); return;
        }
        if (['SET', 'DELETE', 'INSERT', 'MERGE', 'SORT', 'RENAME'].includes(command)) {
            if (command === 'SET' && selectors.length > 0) {
                const last = selectors[selectors.length - 1];
                if (last.kind === 'key' && !last.descendant) {
                    matches = [];
                    for (const parent of evaluate(this.document, selectors.slice(0, -1))) {
                        if (!(parent.value instanceof Map)) continue;
                        const keys = [...parent.value.keys()];
                        const index = keys.indexOf(last.key!);
                        matches.push({ value: parent.value.get(last.key!) ?? null, path: [...parent.path, last.key!], order: [...parent.order, index < 0 ? keys.length : index] });
                    }
                }
            }
            const selected = targets(matches);
            let document = clone(this.document);
            for (const target of selected) {
                if (command === 'SET') document = putAt(document, target.path, clone(value));
                else if (command === 'DELETE') {
                    const parent = getAt(document, target.path.slice(0, -1)); const last = target.path[target.path.length - 1];
                    if (typeof last === 'string') (parent as Map<string, Value>).delete(last); else (parent as Value[]).splice(last, 1);
                } else if (command === 'INSERT') {
                    const array = getAt(document, target.path) as Value[];
                    const index = Number(args[1]); array.splice(index < 0 ? array.length + 1 + index : index, 0, clone(value));
                } else if (command === 'MERGE') merge(getAt(document, target.path) as Map<string, Value>, value as Map<string, Value>);
                else if (command === 'SORT') {
                    const array = getAt(document, target.path) as Value[];
                    const direction = args[args.length - 1] === 'DESC' ? -1 : 1;
                    const sorted = array.map((value, index) => ({ value, index, key: fieldValue(value, field) })).sort((a, b) => direction * compareKeys(a.key, b.key) || a.index - b.index).map(item => item.value);
                    document = putAt(document, target.path, sorted);
                } else {
                    const parentPath = target.path.slice(0, -1); const old = target.path[target.path.length - 1] as string;
                    const object = getAt(document, parentPath) as Map<string, Value>;
                    if (old !== key && object.has(key)) throw new Error('key exists at ' + location(target.path));
                    document = putAt(document, parentPath, new Map<string, Value>([...object].map(([name, child]) => [name === old ? key : name, child])));
                }
            }
            this.history.push(clone(this.document)); this.document = document;
            this.output.push(`${command} ${selected.length}`); return;
        }
        if (command === 'COUNT') { this.output.push(`COUNT ${matches.length}`); return; }
        if (['SUM', 'MIN', 'MAX', 'AVG'].includes(command)) {
            const numbers = matches.map(match => match.value).filter((value): value is number => typeof value === 'number');
            const sum = numbers.reduce((total, number) => total + number, 0);
            let answer = 'null';
            if (command === 'SUM') answer = String(sum);
            else if (numbers.length > 0) {
                if (command === 'AVG') { const rounded = Math.floor((Math.abs(sum) * 200 + numbers.length) / (2 * numbers.length)); answer = (sum < 0 && rounded > 0 ? '-' : '') + Math.floor(rounded / 100) + '.' + String(rounded % 100).padStart(2, '0'); }
                else answer = String(numbers.reduce((best, number) => command === 'MIN' ? Math.min(best, number) : Math.max(best, number)));
            }
            this.output.push(command + ' ' + answer); return;
        }
        if (matches.length === 0) { this.output.push('no match'); return; }
        for (const match of matches) {
            if (command === 'GET') this.output.push(location(match.path) + ' = ' + compact(match.value));
            else if (command === 'COMPACT') this.output.push(compact(match.value));
            else if (command === 'PRETTY') this.output.push(pretty(match.value));
            else if (command === 'TYPE') this.output.push(location(match.path) + ' ' + typeName(match.value));
            else if (command === 'LENGTH') this.output.push(location(match.path) + ' ' + (match.value instanceof Map ? match.value.size : (match.value as string | Value[]).length));
            else if (command === 'KEYS') this.output.push(location(match.path) + ' ' + compact([...(match.value as Map<string, Value>).keys()]));
            else if (command === 'FLATTEN') for (const leaf of preorder(match)) if (children(leaf).length === 0) this.output.push(location(leaf.path) + ' = ' + compact(leaf.value));
        }
    }
    run(lines: string[]): void {
        let position = 0;
        const block = (): string[] => { const body: string[] = []; while (lines[position] !== '%%') body.push(lines[position++]); position++; return body; };
        this.load(block());
        while (lines[position] !== 'END') {
            const line = lines[position++];
            if (line === 'LOAD') { this.load(block()); continue; }
            try { this.execute(line); }
            catch (error) {
                this.output.push(error instanceof JsonFailure ? `PARSE ERROR col ${error.position + 1}: ${error.message}` : `ERROR ${(error as Error).message}`);
            }
        }
    }
}
const tool = new QueryTool();
tool.run(fs.readFileSync(0, 'utf8').split('\n'));
process.stdout.write(tool.output.join('\n') + '\n');
