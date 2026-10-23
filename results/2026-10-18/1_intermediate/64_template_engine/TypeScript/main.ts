import * as fs from 'node:fs';

type Value = null | string | number | boolean | Value[] | Map<string, Value>;
type Part = string | number;
type Argument = string | number;
type SourceLine = { number: number; text: string };
type Filter = { name: string; args: Argument[] };
type Expression = { name: string; filters: Filter[] };
type Node = string | Tag;

const identifier = /^[A-Za-z_][A-Za-z0-9_]*$/;
const keyPattern = /^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[(?:0|[1-9][0-9]*)\])*$/;
const namePattern = /^(?:\.|@(?:index|number|first|last)|(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*)(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*))*)$/;
const integerPattern = /^(?:0|-?[1-9][0-9]*)$/;
const numericPattern = /^-?[0-9]{1,9}$/;
const noArguments = new Set(['upper', 'lower', 'title', 'trim', 'length', 'first', 'last', 'reverse', 'items', 'comma', 'sum', 'min', 'max']);
const numericFilters = new Set(['add', 'sub', 'mul', 'div', 'mod', 'gt', 'lt']);
const filters = new Set([...noArguments, ...numericFilters, 'default', 'eq', 'pad', 'lpad', 'truncate', 'replace', 'join', 'sort', 'pluck']);
const standaloneKinds = new Set(['section', 'inverted', 'close', 'comment', 'partial', 'delimiter']);
const sigils: Record<string, string> = { '#': 'section', '^': 'inverted', '/': 'close', '!': 'comment', '>': 'partial', '&': 'raw', '=': 'delimiter' };
function strip(text: string): string {
    let start = 0;
    let end = text.length;
    while (start < end && text[start] === ' ') start++;
    while (end > start && text[end - 1] === ' ') end--;
    return text.slice(start, end);
}

class TemplateError extends Error {
    constructor(public number: number, message: string) {
        super(message);
    }
}

class Tag {
    expression: Expression | null = null;
    children: Node[] = [];
    indentation = '';

    constructor(public kind: string, public number: number, public argument: string) {}
}

function hasPart(value: Value, part: Part): boolean {
    return typeof part === 'string' ? value instanceof Map && value.has(part) : Array.isArray(value) && part < value.length;
}

function getPart(value: Value, part: Part): Value {
    return typeof part === 'string' ? (value as Map<string, Value>).get(part)! : (value as Value[])[part];
}

function putPart(container: Value, part: Part, value: Value): void {
    if (typeof part === 'string') (container as Map<string, Value>).set(part, value);
    else (container as Value[])[part] = value;
}

function parseKey(key: string): { part: Part; prefix: string }[] {
    if (!keyPattern.test(key)) throw new Error(`bad key '${key}'`);
    return [...key.matchAll(/([A-Za-z_][A-Za-z0-9_]*)|\[(0|[1-9][0-9]*)\]/g)].map(match => ({
        part: match[1] === undefined ? Number(match[2]) : match[1],
        prefix: key.slice(0, match.index! + match[0].length),
    }));
}

function readScalar(text: string, start: number): [Value, number] {
    if (text[start] === '"') {
        let result = '';
        for (let position = start + 1; position < text.length; position++) {
            const char = text[position];
            if (char === '"') return [result, position + 1];
            if (char === '\\') {
                const next = text[++position];
                if (next !== '"' && next !== '\\' && next !== 'n') throw new Error();
                result += next === 'n' ? '\n' : next;
            } else result += char;
        }
        throw new Error();
    }
    let end = start;
    while (end < text.length && text[end] !== ',' && text[end] !== ']') end++;
    const word = text.slice(start, end);
    if (word === 'true' || word === 'false') return [word === 'true', end];
    if (integerPattern.test(word)) return [Number(word), end];
    throw new Error();
}

function parseValue(text: string): Value {
    try {
        if (text === '[]') return [];
        if (text === '{}') return new Map<string, Value>();
        if (text.startsWith('[')) {
            const values: Value[] = [];
            let position = 1;
            while (true) {
                const [value, end] = readScalar(text, position);
                values.push(value);
                if (text.slice(end) === ']') return values;
                if (text.slice(end, end + 2) !== ', ') throw new Error();
                position = end + 2;
            }
        }
        const [value, end] = readScalar(text, 0);
        if (end !== text.length) throw new Error();
        return value;
    } catch {
        throw new Error(`bad value '${text}'`);
    }
}

function splitUnquoted(text: string, separator: string): string[] {
    const parts: string[] = [];
    let quoted = false;
    let start = 0;
    for (let index = 0; index < text.length; index++) {
        if (text[index] === "'") quoted = !quoted;
        else if (text[index] === separator && !quoted) {
            parts.push(text.slice(start, index));
            start = index + 1;
        }
    }
    parts.push(text.slice(start));
    return parts;
}

function validArguments(name: string, args: Argument[]): boolean {
    const number = args.length > 0 && typeof args[0] === 'number';
    const string = args.length > 0 && typeof args[0] === 'string';
    if (noArguments.has(name)) return args.length === 0;
    if (name === 'default' || name === 'eq') return args.length === 1;
    if (name === 'sort') return args.length === 0 || args.length === 1 && string;
    if (name === 'join' || name === 'pluck') return args.length === 1 && string;
    if (name === 'replace') return args.length === 2 && string && args[0] !== '' && typeof args[1] === 'string';
    if (name === 'pad' || name === 'lpad') {
        return number && (args[0] as number) >= 0 && (args.length === 1 || args.length === 2 && typeof args[1] === 'string' && args[1].length === 1);
    }
    if (name === 'truncate') return args.length === 1 && number && (args[0] as number) >= 0;
    return args.length === 1 && number && (!(name === 'div' || name === 'mod') || args[0] !== 0);
}

function parseExpression(text: string, number: number): Expression {
    const parts = splitUnquoted(text, '|');
    const name = strip(parts[0]);
    if (!namePattern.test(name)) throw new TemplateError(number, `invalid name '${name}'`);
    const chain: Filter[] = [];
    for (const part of parts.slice(1)) {
        const [filter, ...notations] = splitUnquoted(strip(part), ':');
        if (!filters.has(filter)) throw new TemplateError(number, `unknown filter '${filter}'`);
        const args: Argument[] = [];
        let valid = true;
        for (const notation of notations) {
            if (/^'[^']*'$/.test(notation)) args.push(notation.slice(1, -1));
            else if (numericPattern.test(notation)) args.push(Number(notation));
            else valid = false;
        }
        if (!valid || !validArguments(filter, args)) throw new TemplateError(number, `bad arguments for '${filter}'`);
        chain.push({ name: filter, args });
    }
    return { name, filters: chain };
}

function parseSource(source: SourceLine[]): Node[] {
    let opening = '{{';
    let closing = '}}';
    const nodes: Node[] = [];
    const targets: Node[][] = [nodes];
    const sections: Tag[] = [];
    for (const { number, text } of source) {
        let position = 0;
        const tokens: Node[] = [];
        const lineTags: Tag[] = [];
        while (true) {
            const start = text.indexOf(opening, position);
            if (start < 0) {
                tokens.push(text.slice(position));
                break;
            }
            tokens.push(text.slice(position, start));
            const after = start + opening.length;
            const triple = text[after] === '{';
            const terminator = triple ? '}' + closing : closing;
            const end = text.indexOf(terminator, after + (triple ? 1 : 0));
            if (end < 0) throw new TemplateError(number, 'unclosed tag');
            const content = strip(text.slice(after + (triple ? 1 : 0), end));
            const kind = triple ? 'raw' : sigils[content[0]] ?? 'variable';
            const argument = triple || kind === 'variable' || kind === 'delimiter' ? content : strip(content.slice(1));
            const tag = new Tag(kind, number, argument);
            position = end + terminator.length;
            if (kind === 'delimiter') {
                const words = strip(content.slice(1, -1)).split(/ +/);
                if (content.length < 2 || !content.endsWith('=') || words.length !== 2 || words.some(word => word.includes('='))) {
                    throw new TemplateError(number, 'invalid delimiters');
                }
                [opening, closing] = words;
            } else if (kind === 'variable' || kind === 'raw' || kind === 'section' || kind === 'inverted') {
                tag.expression = parseExpression(argument, number);
                if (kind === 'section' || kind === 'inverted') sections.push(tag);
            } else if (kind === 'close') {
                if (!namePattern.test(argument)) throw new TemplateError(number, `invalid name '${argument}'`);
                if (sections.length === 0) throw new TemplateError(number, `unexpected closing '${argument}'`);
                const expected = sections[sections.length - 1].expression!.name;
                if (argument !== expected) throw new TemplateError(number, `mismatched closing '${argument}', expected '${expected}'`);
                sections.pop();
            } else if (kind === 'partial' && !identifier.test(argument)) {
                throw new TemplateError(number, `invalid name '${argument}'`);
            }
            lineTags.push(tag);
            tokens.push(tag);
        }
        const standalone = lineTags.length === 1 && standaloneKinds.has(lineTags[0].kind) && tokens.every(token => typeof token !== 'string' || /^ *$/.test(token));
        let placed: Node[] = tokens;
        if (standalone) {
            if (lineTags[0].kind === 'partial') lineTags[0].indentation = tokens[0] as string;
            placed = lineTags;
        } else placed.push('\n');
        for (const token of placed) {
            const target = targets[targets.length - 1];
            if (typeof token === 'string') {
                if (token !== '') target.push(token);
            } else if (token.kind === 'section' || token.kind === 'inverted') {
                target.push(token);
                targets.push(token.children);
            } else if (token.kind === 'close') targets.pop();
            else if (token.kind !== 'comment' && token.kind !== 'delimiter') target.push(token);
        }
    }
    if (sections.length > 0) {
        const tag = sections[sections.length - 1];
        throw new TemplateError(tag.number, `unclosed section '${tag.expression!.name}'`);
    }
    return nodes;
}

function toText(value: Value): string {
    if (value === null) return '';
    if (value instanceof Map) throw new Error('cannot render map');
    if (Array.isArray(value)) return value.map(toText).join(', ');
    return String(value);
}

function truthy(value: Value): boolean {
    if (value instanceof Map) return value.size > 0;
    if (Array.isArray(value)) return value.length > 0;
    return value !== null && value !== false && value !== 0 && value !== '';
}

function toNumber(value: Value, filter: string): number {
    if (value === null) return 0;
    if (typeof value === 'number') return value;
    if (typeof value === 'string' && !value.includes('\n') && numericPattern.test(value)) return Number(value);
    throw new Error(`not a number for '${filter}'`);
}

function field(value: Value, key: string): Value {
    return value instanceof Map ? value.get(key) ?? null : null;
}

function sortRank(value: Value): number {
    if (value === null) return 0;
    if (typeof value === 'number') return 1;
    if (typeof value === 'string') return 2;
    if (typeof value === 'boolean') return 3;
    return 4;
}

function compareValues(left: Value, right: Value): number {
    const rank = sortRank(left) - sortRank(right);
    if (rank !== 0) return rank;
    if (sortRank(left) === 0 || sortRank(left) === 4) return 0;
    if (left === right) return 0;
    if (typeof left === 'number' && typeof right === 'number') return left - right;
    if (typeof left === 'string' && typeof right === 'string') return left < right ? -1 : 1;
    return Number(left) - Number(right);
}

function applyFilter(filter: Filter, value: Value): Value {
    const { name, args } = filter;
    const n = args[0] as number;
    const s = args[0] as string;
    switch (name) {
        case 'upper': return toText(value).toUpperCase();
        case 'lower': return toText(value).toLowerCase();
        case 'title': return [...toText(value)].map((char, index, chars) => index === 0 || chars[index - 1] === ' ' ? char.toUpperCase() : char.toLowerCase()).join('');
        case 'trim': return strip(toText(value));
        case 'length': return value instanceof Map ? value.size : Array.isArray(value) ? value.length : toText(value).length;
        case 'first': return Array.isArray(value) ? value[0] ?? null : value;
        case 'last': return Array.isArray(value) ? value[value.length - 1] ?? null : value;
        case 'reverse': return Array.isArray(value) ? [...value].reverse() : typeof value === 'string' ? [...value].reverse().join('') : value;
        case 'items': return value instanceof Map ? [...value.keys()].sort().map(key => new Map<string, Value>([['key', key], ['value', value.get(key)!]])) : value;
        case 'comma': {
            const number = toNumber(value, name);
            return (number < 0 ? '-' : '') + String(Math.abs(number)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        }
        case 'sum': case 'min': case 'max': {
            if (!Array.isArray(value)) return toNumber(value, name);
            const numbers = value.map(element => toNumber(element, name));
            if (name === 'sum') return numbers.reduce((total, number) => total + number, 0);
            if (numbers.length === 0) return null;
            return numbers.reduce((best, number) => name === 'min' ? Math.min(best, number) : Math.max(best, number));
        }
        case 'default': return truthy(value) ? value : args[0];
        case 'eq': return toText(value) === toText(args[0]);
        case 'pad': return toText(value).padEnd(n, args.length === 2 ? args[1] as string : ' ');
        case 'lpad': return toText(value).padStart(n, args.length === 2 ? args[1] as string : ' ');
        case 'truncate': {
            const text = toText(value);
            return text.length > n ? text.slice(0, n) + '...' : text;
        }
        case 'replace': return toText(value).split(s).join(args[1] as string);
        case 'join': return Array.isArray(value) ? value.map(toText).join(s) : toText(value);
        case 'pluck': return Array.isArray(value) ? value.map(element => field(element, s)) : value;
        case 'sort': return Array.isArray(value) ? value.map((element, index) => ({ element, index, key: args.length === 0 ? element : field(element, s) })).sort((a, b) => compareValues(a.key, b.key) || a.index - b.index).map(item => item.element) : value;
        default: {
            const number = toNumber(value, name);
            switch (name) {
                case 'add': return number + n;
                case 'sub': return number - n;
                case 'mul': return number * n;
                case 'div': return Math.floor(number / n);
                case 'mod': return number - n * Math.floor(number / n);
                case 'gt': return number > n;
                default: return number < n;
            }
        }
    }
}

class Renderer {
    contexts: Value[];
    loops: { index: number; count: number }[] = [];
    output: string[] = [];

    constructor(root: Map<string, Value>, private partials: Map<string, SourceLine[]>, private strict: boolean) {
        this.contexts = [root];
    }

    resolve(name: string): [boolean, Value] {
        if (name === '.') return [true, this.contexts[this.contexts.length - 1]];
        if (name.startsWith('@')) {
            if (this.loops.length === 0) return [false, null];
            const { index, count } = this.loops[this.loops.length - 1];
            if (name === '@index') return [true, index];
            if (name === '@number') return [true, index + 1];
            return [true, name === '@first' ? index === 0 : index === count - 1];
        }
        const parts: Part[] = name.split('.').map(part => /^[0-9]+$/.test(part) ? Number(part) : part);
        for (let index = this.contexts.length - 1; index >= 0; index--) {
            let value = this.contexts[index];
            if (!hasPart(value, parts[0])) continue;
            for (const part of parts) {
                if (!hasPart(value, part)) return [false, null];
                value = getPart(value, part);
            }
            return [true, value];
        }
        return [false, null];
    }

    evaluate(expression: Expression, strict: boolean): Value {
        let [found, value] = this.resolve(expression.name);
        if (!found && strict) throw new Error(`missing '${expression.name}'`);
        for (const filter of expression.filters) value = applyFilter(filter, value);
        return value;
    }

    render(nodes: Node[], depth: number): void {
        for (const node of nodes) {
            if (typeof node === 'string') {
                this.output.push(node);
                continue;
            }
            try {
                if (node.kind === 'variable' || node.kind === 'raw') {
                    const text = toText(this.evaluate(node.expression!, this.strict));
                    const escaped: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
                    this.output.push(node.kind === 'raw' ? text : text.replace(/[&<>"']/g, char => escaped[char]));
                } else if (node.kind === 'section') {
                    const value = this.evaluate(node.expression!, false);
                    if (Array.isArray(value)) {
                        for (let index = 0; index < value.length; index++) {
                            this.contexts.push(value[index]);
                            this.loops.push({ index, count: value.length });
                            this.render(node.children, depth);
                            this.loops.pop();
                            this.contexts.pop();
                        }
                    } else if (truthy(value)) {
                        this.contexts.push(value);
                        this.render(node.children, depth);
                        this.contexts.pop();
                    }
                } else if (node.kind === 'inverted') {
                    if (!truthy(this.evaluate(node.expression!, false))) this.render(node.children, depth);
                } else if (node.kind === 'partial') {
                    const source = this.partials.get(node.argument);
                    if (source === undefined) throw new Error(`unknown partial '${node.argument}'`);
                    if (depth === 8) throw new Error(`partial depth exceeded at '${node.argument}'`);
                    this.render(parseSource(source.map(line => ({ number: line.number, text: line.text === '' ? '' : node.indentation + line.text }))), depth + 1);
                }
            } catch (error) {
                if (error instanceof TemplateError) throw error;
                throw new TemplateError(node.number, (error as Error).message);
            }
        }
    }
}

class TemplateEngine {
    root = new Map<string, Value>();
    partials = new Map<string, SourceLine[]>();
    templates = new Map<string, SourceLine[]>();
    strict = false;
    output: string[] = [];

    assign(line: string): void {
        const separator = line.indexOf(' = ');
        if (separator < 0) throw new Error('bad line');
        const parts = parseKey(line.slice(0, separator));
        const value = parseValue(line.slice(separator + 3));
        let container: Value = this.root;
        let detached: { container: Value; part: Part; child: Value } | null = null;
        for (let index = 0; index < parts.length; index++) {
            const { part, prefix } = parts[index];
            if (typeof part === 'number' && part > (container as Value[]).length) throw new Error(`index gap at '${prefix}'`);
            if (index === parts.length - 1) {
                putPart(container, part, value);
                break;
            }
            const mapRequired = typeof parts[index + 1].part === 'string';
            let child: Value;
            if (hasPart(container, part)) {
                child = getPart(container, part);
                if (!(mapRequired ? child instanceof Map : Array.isArray(child))) throw new Error(`type conflict at '${prefix}'`);
            } else {
                child = mapRequired ? new Map<string, Value>() : [];
                if (detached === null) detached = { container, part, child };
                else putPart(container, part, child);
            }
            container = child;
        }
        if (detached !== null) putPart(detached.container, detached.part, detached.child);
    }

    unset(key: string): void {
        const parts = parseKey(key);
        let container: Value = this.root;
        for (let index = 0; index < parts.length; index++) {
            const part = parts[index].part;
            if (!hasPart(container, part)) throw new Error(`no value at '${key}'`);
            if (index === parts.length - 1) {
                if (typeof part === 'string') (container as Map<string, Value>).delete(part);
                else (container as Value[]).splice(part, 1);
            } else container = getPart(container, part);
        }
    }

    loadData(body: SourceLine[]): void {
        let assigned = 0;
        let unset = 0;
        const errors: string[] = [];
        for (const { number, text } of body) {
            if (text === '' || text.startsWith('#')) continue;
            try {
                if (text.startsWith('UNSET ')) {
                    this.unset(text.slice(6));
                    unset++;
                } else {
                    this.assign(text);
                    assigned++;
                }
            } catch (error) {
                errors.push(`ERROR line ${number}: ${(error as Error).message}`);
            }
        }
        this.output.push(`DATA set=${assigned} unset=${unset} errors=${errors.length}`, ...errors);
    }

    render(name: string): void {
        try {
            const renderer = new Renderer(this.root, this.partials, this.strict);
            renderer.render(parseSource(this.templates.get(name)!), 0);
            const result = renderer.output.join('');
            const lines = result === '' ? [] : result.split('\n');
            if (result.endsWith('\n')) lines.pop();
            this.output.push(`TEMPLATE ${name} OK lines=${lines.length} chars=${result.length}`, ...lines);
        } catch (error) {
            const failure = error as TemplateError;
            this.output.push(`TEMPLATE ${name} ERROR line ${failure.number}: ${failure.message}`);
        }
    }

    dump(): void {
        const leaves: string[] = [];
        const visit = (value: Value, path: string): void => {
            if (value instanceof Map && value.size > 0) {
                for (const key of [...value.keys()].sort()) visit(value.get(key)!, `${path}.${key}`);
            } else if (Array.isArray(value) && value.length > 0) {
                value.forEach((element, index) => visit(element, `${path}[${index}]`));
            } else {
                const notation = typeof value === 'string' ? '"' + value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"' : value instanceof Map ? '{}' : Array.isArray(value) ? '[]' : String(value);
                leaves.push(`${path} = ${notation}`);
            }
        };
        for (const key of [...this.root.keys()].sort()) visit(this.root.get(key)!, key);
        this.output.push(`DUMP leaves=${leaves.length}`, ...leaves);
    }

    run(lines: string[]): void {
        let position = 0;
        while (lines[position] !== 'END') {
            const line = lines[position++];
            const number = position;
            const [command, name] = line.split(' ');
            if (command === 'DATA' || command === 'PARTIAL' || command === 'TEMPLATE') {
                const body: SourceLine[] = [];
                while (lines[position] !== `END${command}`) body.push({ number: position + 1, text: lines[position++] });
                position++;
                if (command === 'DATA') this.loadData(body);
                else if (command === 'TEMPLATE') {
                    this.templates.set(name, body);
                    this.render(name);
                } else {
                    try {
                        parseSource(body);
                        const status = this.partials.has(name) ? 'REPLACED' : 'DEFINED';
                        this.partials.set(name, body);
                        this.output.push(`PARTIAL ${name} ${status} lines=${body.length}`);
                    } catch (error) {
                        const failure = error as TemplateError;
                        this.output.push(`PARTIAL ${name} ERROR line ${failure.number}: ${failure.message}`);
                    }
                }
            } else if (command === 'RENDER') {
                if (this.templates.has(name)) this.render(name);
                else this.output.push(`TEMPLATE ${name} ERROR line ${number}: unknown template '${name}'`);
            } else if (command === 'DUMP') this.dump();
            else if (command === 'STRICT') {
                this.strict = name === 'ON';
                this.output.push(line);
            } else if (command === 'RESET') {
                this.root.clear();
                this.partials.clear();
                this.templates.clear();
                this.output.push('RESET');
            }
        }
    }
}

const engine = new TemplateEngine();
engine.run(fs.readFileSync(0, 'utf8').split('\n'));
process.stdout.write(engine.output.length === 0 ? '' : engine.output.join('\n') + '\n');
