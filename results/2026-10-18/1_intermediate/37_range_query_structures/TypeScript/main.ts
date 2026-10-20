import { readFileSync } from 'node:fs';

const arrayKinds = ['SEG', 'LAZY', 'FEN', 'RFEN', 'SPARSE', 'SQRT', 'PERSIST'] as const;
type ArrayKind = typeof arrayKinds[number];
type Kind = ArrayKind | 'GRID';
type QueryKind = Exclude<ArrayKind, 'PERSIST'>;
type DumpKind = Exclude<Kind, 'PERSIST'>;
type Operation = 'SUM' | 'MIN' | 'MAX' | 'GCD';
const operations: readonly Operation[] = ['SUM', 'MIN', 'MAX', 'GCD'];
class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
function isOperation(text: string): text is Operation { return operations.some(op => op === text); }
const sum = (values: readonly number[]): number => values.reduce((a, b) => a + b, 0);
const words = (values: readonly number[]): string => values.join(' ');
const lowbit = (value: number): number => value & -value;
const isqrt = (value: number): number => Math.floor(Math.sqrt(value));
function gcd(a: number, b: number): number {
    a = Math.abs(a); b = Math.abs(b);
    while (b !== 0) [a, b] = [b, a % b];
    return a;
}
function combine(op: Operation, a: number, b: number): number {
    switch (op) {
        case 'SUM': return a + b;
        case 'MIN': return Math.min(a, b);
        case 'MAX': return Math.max(a, b);
        case 'GCD': return gcd(a, b);
    }
}
class Span {
    constructor(readonly left: number, readonly right: number) {}
    get length(): number { return this.right - this.left + 1; }
    get middle(): number { return Math.floor((this.left + this.right) / 2); }
    get leaf(): boolean { return this.left === this.right; }
    covers(other: Span): boolean { return this.left <= other.left && other.right <= this.right; }
    leftChild(): Span { return new Span(this.left, this.middle); }
    rightChild(): Span { return new Span(this.middle + 1, this.right); }
}
const whole = (n: number): Span => new Span(0, n - 1);
interface Aggregate { readonly sum: number; readonly min: number; readonly max: number }
interface Answer { readonly value: number; readonly visited: number }
interface Report { readonly text: string; readonly values: readonly number[] }
const aggregate = (values: readonly number[]): Aggregate => ({ sum: sum(values), min: Math.min(...values), max: Math.max(...values) });
const merge = (a: Aggregate, b: Aggregate): Aggregate => ({ sum: a.sum + b.sum, min: Math.min(a.min, b.min), max: Math.max(a.max, b.max) });
const describe = (value: Aggregate): string => `sum=${value.sum} min=${value.min} max=${value.max}`;
const report = (answer: Answer): Report => ({ text: `sum=${answer.value} visited=${answer.visited}`, values: [answer.value] });
class Counts { visited = 0; covered = 0; pushes = 0; }
interface NumberedSpan { readonly node: number; readonly span: Span }
interface Cell { readonly row: number; readonly column: number }
class Layout {
    readonly ranges: (Span | undefined)[];
    readonly nodes: NumberedSpan[] = [];
    constructor(readonly n: number) {
        this.ranges = Array<Span | undefined>(4 * n);
        const build = (node: number, span: Span): void => {
            this.ranges[node] = span;
            this.nodes.push({ node, span });
            if (!span.leaf) { build(2 * node, span.leftChild()); build(2 * node + 1, span.rightChild()); }
        };
        build(1, whole(n));
        this.nodes.sort((a, b) => a.node - b.node);
    }
    at(node: number): Span { return this.ranges[node]!; }
}

class Segment {
    readonly shape: Layout;
    readonly tree: number[];
    constructor(values: readonly number[], readonly op: Operation) {
        this.shape = new Layout(values.length);
        this.tree = Array<number>(4 * values.length).fill(0);
        const build = (node: number): void => {
            const span = this.shape.at(node);
            if (span.leaf) this.tree[node] = this.leafValue(values[span.left]);
            else { build(2 * node); build(2 * node + 1); this.pull(node); }
        };
        build(1);
    }
    private leafValue(value: number): number { return this.op === 'GCD' ? Math.abs(value) : value; }
    private pull(node: number): void { this.tree[node] = combine(this.op, this.tree[2 * node], this.tree[2 * node + 1]); }
    private queryAt(node: number, wanted: Span): Answer {
        const span = this.shape.at(node);
        if (wanted.covers(span)) return { value: this.tree[node], visited: 1 };
        let answer: Answer;
        if (wanted.right <= span.middle) answer = this.queryAt(2 * node, wanted);
        else if (wanted.left > span.middle) answer = this.queryAt(2 * node + 1, wanted);
        else {
            const a = this.queryAt(2 * node, wanted), b = this.queryAt(2 * node + 1, wanted);
            answer = { value: combine(this.op, a.value, b.value), visited: a.visited + b.visited };
        }
        return { value: answer.value, visited: answer.visited + 1 };
    }
    query(span: Span): Report {
        const answer = this.queryAt(1, span);
        return { text: `${this.op.toLowerCase()}=${answer.value} visited=${answer.visited}`, values: [answer.value] };
    }
    update(index: number, value: number, node = 1): number {
        const span = this.shape.at(node);
        if (span.leaf) { this.tree[node] = this.leafValue(value); return 1; }
        const visited = this.update(index, value, index <= span.middle ? 2 * node : 2 * node + 1);
        this.pull(node);
        return visited + 1;
    }
    dump(): string[] {
        return [`SEG DUMP ${this.op} nodes=${this.shape.nodes.length}`,
            ...this.shape.nodes.map(({ node, span }) => `NODE ${node} ${span.left} ${span.right} ${this.tree[node]}`)];
    }
}
interface LazyNode { value: Aggregate; assign: number | null; add: number }
class LazyTree {
    readonly shape: Layout;
    readonly nodes: LazyNode[];
    constructor(values: readonly number[]) {
        this.shape = new Layout(values.length);
        this.nodes = Array.from({ length: 4 * values.length }, () => ({ value: { sum: 0, min: 0, max: 0 }, assign: null, add: 0 }));
        const build = (node: number): void => {
            const span = this.shape.at(node);
            if (span.leaf) this.nodes[node].value = { sum: values[span.left], min: values[span.left], max: values[span.left] };
            else { build(2 * node); build(2 * node + 1); this.pull(node); }
        };
        build(1);
    }
    private pull(node: number): void { this.nodes[node].value = merge(this.nodes[2 * node].value, this.nodes[2 * node + 1].value); }
    private apply(node: number, value: number, assign: boolean): void {
        const span = this.shape.at(node), target = this.nodes[node], old = target.value;
        target.value = assign ? { sum: value * span.length, min: value, max: value } :
            { sum: old.sum + value * span.length, min: old.min + value, max: old.max + value };
        if (!span.leaf) {
            if (assign) { target.assign = value; target.add = 0; }
            else target.add += value;
        }
    }
    private push(node: number, counts: Counts): void {
        const source = this.nodes[node];
        if (source.assign === null && source.add === 0) return;
        for (const child of [2 * node, 2 * node + 1]) {
            if (source.assign !== null) this.apply(child, source.assign, true);
            if (source.add !== 0) this.apply(child, source.add, false);
        }
        source.assign = null; source.add = 0; counts.pushes++;
    }
    update(wanted: Span, value: number, assign: boolean): Counts {
        const counts = new Counts();
        const visit = (node: number): void => {
            counts.visited++;
            const span = this.shape.at(node);
            if (wanted.covers(span)) { counts.covered++; this.apply(node, value, assign); return; }
            this.push(node, counts);
            if (wanted.left <= span.middle) visit(2 * node);
            if (wanted.right > span.middle) visit(2 * node + 1);
            this.pull(node);
        };
        visit(1);
        return counts;
    }
    query(wanted: Span): Report {
        const counts = new Counts();
        const visit = (node: number): Aggregate => {
            counts.visited++;
            const span = this.shape.at(node);
            if (wanted.covers(span)) return this.nodes[node].value;
            this.push(node, counts);
            if (wanted.right <= span.middle) return visit(2 * node);
            if (wanted.left > span.middle) return visit(2 * node + 1);
            const a = visit(2 * node), b = visit(2 * node + 1);
            return merge(a, b);
        };
        const value = visit(1);
        return { text: `${describe(value)} visited=${counts.visited} pushes=${counts.pushes}`, values: [value.sum, value.min, value.max] };
    }
    dump(): string[] {
        return [`LAZY DUMP nodes=${this.shape.nodes.length}`, ...this.shape.nodes.map(({ node, span }) => {
            const item = this.nodes[node];
            return `NODE ${node} ${span.left} ${span.right} ${describe(item.value)} assign=${item.assign ?? '-'} add=${item.add}`;
        })];
    }
}

class Bit {
    readonly tree: number[];
    constructor(n: number, values?: readonly number[]) {
        this.tree = Array<number>(n + 1).fill(0);
        values?.forEach((value, index) => this.add(index + 1, value));
    }
    add(position: number, value: number): number {
        let visited = 0;
        for (; position < this.tree.length; position += lowbit(position)) { this.tree[position] += value; visited++; }
        return visited;
    }
    prefix(position: number): Answer {
        let value = 0, visited = 0;
        for (; position > 0; position -= lowbit(position)) { value += this.tree[position]; visited++; }
        return { value, visited };
    }
    query(span: Span): Answer {
        const a = this.prefix(span.right + 1), b = this.prefix(span.left);
        return { value: a.value - b.value, visited: a.visited + b.visited };
    }
    lower(rest: number): Answer {
        const n = this.tree.length - 1;
        let step = 1, position = 0, visited = 0;
        while (2 * step <= n) step *= 2;
        for (; step > 0; step = Math.floor(step / 2)) {
            if (position + step <= n) {
                const value = this.tree[position + step]; visited++;
                if (value < rest) { rest -= value; position += step; }
            }
        }
        return { value: position < n ? position : -1, visited };
    }
    dump(name: string): string { return `${name} ${words(this.tree.slice(1))}`; }
}
class Fenwick {
    readonly values: number[];
    readonly bit: Bit;
    constructor(values: readonly number[]) { this.values = values.slice(); this.bit = new Bit(values.length, values); }
    query(span: Span): Report { return report(this.bit.query(span)); }
    dump(): string[] { return [`FEN DUMP n=${this.values.length}`, this.bit.dump('T')]; }
}
class RangeFenwick {
    readonly first: Bit;
    readonly second: Bit;
    constructor(values: readonly number[]) {
        this.first = new Bit(values.length); this.second = new Bit(values.length);
        values.forEach((value, index) => {
            const difference = value - (index === 0 ? 0 : values[index - 1]);
            this.first.add(index + 1, difference); this.second.add(index + 1, difference * index);
        });
    }
    add(span: Span, value: number): number {
        let visited = this.first.add(span.left + 1, value);
        visited += this.first.add(span.right + 2, -value);
        visited += this.second.add(span.left + 1, value * span.left);
        visited += this.second.add(span.right + 2, -value * (span.right + 1));
        return visited;
    }
    private prefix(position: number): Answer {
        const a = this.first.prefix(position), b = this.second.prefix(position);
        return { value: position * a.value - b.value, visited: a.visited + b.visited };
    }
    query(span: Span): Report {
        const a = this.prefix(span.right + 1), b = this.prefix(span.left);
        return report({ value: a.value - b.value, visited: a.visited + b.visited });
    }
    dump(): string[] { return [`RFEN DUMP n=${this.first.tree.length - 1}`, this.first.dump('B1'), this.second.dump('B2')]; }
}

class SparseTable {
    readonly values: readonly number[];
    readonly minima: number[][];
    readonly maxima: number[][];
    constructor(values: readonly number[]) {
        this.values = values.slice();
        this.minima = [Array.from({ length: values.length }, (_, i) => i)];
        this.maxima = [this.minima[0].slice()];
        for (let width = 2; width <= values.length; width *= 2) {
            const previousMin = this.minima.at(-1)!, previousMax = this.maxima.at(-1)!;
            const minimum: number[] = [], maximum: number[] = [];
            for (let index = 0; index + width <= values.length; index++) {
                minimum.push(this.select(previousMin[index], previousMin[index + width / 2], true));
                maximum.push(this.select(previousMax[index], previousMax[index + width / 2], false));
            }
            this.minima.push(minimum); this.maxima.push(maximum);
        }
    }
    private select(a: number, b: number, minimum: boolean): number {
        return (minimum ? this.values[a] <= this.values[b] : this.values[a] >= this.values[b]) ? a : b;
    }
    query(span: Span): Report {
        let level = 0, width = 1;
        while (2 * width <= span.length) { level++; width *= 2; }
        const end = span.right - width + 1;
        const low = this.select(this.minima[level][span.left], this.minima[level][end], true);
        const high = this.select(this.maxima[level][span.left], this.maxima[level][end], false);
        return { text: `min=${this.values[low]} minpos=${low} max=${this.values[high]} maxpos=${high} level=${level}`, values: [this.values[low], this.values[high]] };
    }
    dump(): string[] {
        const rows = [`SPARSE DUMP levels=${this.minima.length}`];
        this.minima.forEach((row, level) => rows.push(`MIN ${level} ${words(row)}`, `MAX ${level} ${words(this.maxima[level])}`));
        return rows;
    }
}
interface Partition { readonly cells: readonly number[]; readonly blocks: readonly number[] }
const partitionText = (part: Partition): string => `whole=${part.blocks.length} cells=${part.cells.length}`;
class SqrtBlocks {
    readonly raw: number[];
    readonly tags: number[];
    readonly sums: number[];
    constructor(values: readonly number[], readonly block: number) {
        this.raw = values.slice(); this.tags = Array<number>(Math.ceil(values.length / block)).fill(0); this.sums = this.tags.slice();
        values.forEach((value, index) => { this.sums[Math.floor(index / block)] += value; });
    }
    private partition(span: Span): Partition {
        const first = Math.floor(span.left / this.block), last = Math.floor(span.right / this.block);
        const cells: number[] = [], blocks: number[] = [];
        for (let index = span.left; index <= span.right; index++) {
            const block = Math.floor(index / this.block);
            if (block === first || block === last) cells.push(index);
        }
        for (let block = first + 1; block < last; block++) blocks.push(block);
        return { cells, blocks };
    }
    add(span: Span, value: number): Partition {
        const part = this.partition(span);
        for (const index of part.cells) { this.raw[index] += value; this.sums[Math.floor(index / this.block)] += value; }
        for (const block of part.blocks) { this.tags[block] += value; this.sums[block] += value * this.block; }
        return part;
    }
    query(span: Span): Report {
        const part = this.partition(span);
        let value = 0;
        for (const index of part.cells) value += this.raw[index] + this.tags[Math.floor(index / this.block)];
        for (const block of part.blocks) value += this.sums[block];
        return { text: `sum=${value} ${partitionText(part)}`, values: [value] };
    }
    dump(): string[] {
        return [`SQRT DUMP block=${this.block} blocks=${this.tags.length}`, ...this.tags.map((tag, block) => {
            const first = block * this.block, end = Math.min(first + this.block, this.raw.length);
            return `BLOCK ${block} ${first} ${end - 1} add=${tag} sum=${this.sums[block]} ${words(this.raw.slice(first, end))}`;
        })];
    }
}

type PersistentNode = { readonly value: number } & (
    | { readonly kind: 'leaf' }
    | { readonly kind: 'branch'; readonly left: PersistentNode; readonly right: PersistentNode }
);
interface ChangedNode { readonly node: PersistentNode; readonly created: number }
function buildNode(values: readonly number[] | null, span: Span): PersistentNode {
    if (span.leaf) return { kind: 'leaf', value: values?.[span.left] ?? 0 };
    const left = buildNode(values, span.leftChild()), right = buildNode(values, span.rightChild());
    return { kind: 'branch', value: left.value + right.value, left, right };
}
function changeNode(source: PersistentNode, span: Span, index: number, value: number, increment: boolean): ChangedNode {
    if (source.kind === 'leaf') return { node: { kind: 'leaf', value: increment ? source.value + value : value }, created: 1 };
    let left = source.left, right = source.right;
    let changed: ChangedNode;
    if (index <= span.middle) { changed = changeNode(left, span.leftChild(), index, value, increment); left = changed.node; }
    else { changed = changeNode(right, span.rightChild(), index, value, increment); right = changed.node; }
    return { node: { kind: 'branch', value: left.value + right.value, left, right }, created: changed.created + 1 };
}
function queryNode(node: PersistentNode, span: Span, wanted: Span): Answer {
    if (node.kind === 'leaf' || wanted.covers(span)) return { value: node.value, visited: 1 };
    let answer: Answer;
    if (wanted.right <= span.middle) answer = queryNode(node.left, span.leftChild(), wanted);
    else if (wanted.left > span.middle) answer = queryNode(node.right, span.rightChild(), wanted);
    else {
        const a = queryNode(node.left, span.leftChild(), wanted), b = queryNode(node.right, span.rightChild(), wanted);
        answer = { value: a.value + b.value, visited: a.visited + b.visited };
    }
    return { value: answer.value, visited: answer.visited + 1 };
}
class Persistent {
    readonly n: number;
    readonly domain: readonly number[];
    readonly roots: PersistentNode[];
    readonly prefixes: PersistentNode[];
    positionNodes: number;
    valueNodes: number;
    constructor(values: readonly number[]) {
        this.n = values.length;
        this.domain = [...new Set(values)].sort((a, b) => a - b);
        this.roots = [buildNode(values, whole(this.n))]; this.positionNodes = 2 * this.n - 1;
        this.prefixes = [buildNode(null, whole(this.domain.length))]; this.valueNodes = 2 * this.domain.length - 1;
        const ranks = new Map(this.domain.map((value, index) => [value, index]));
        for (const value of values) {
            const changed = changeNode(this.prefixes.at(-1)!, whole(this.domain.length), ranks.get(value)!, 1, true);
            this.prefixes.push(changed.node); this.valueNodes += changed.created;
        }
    }
    set(version: number, index: number, value: number): number {
        const changed = changeNode(this.roots[version], whole(this.n), index, value, false);
        this.roots.push(changed.node); this.positionNodes += changed.created;
        return changed.created;
    }
    query(version: number, span: Span): Report { return report(queryNode(this.roots[version], whole(this.n), span)); }
    kth(wanted: Span, k: number): Answer {
        let upper = this.prefixes[wanted.right + 1], lower = this.prefixes[wanted.left];
        let span = whole(this.domain.length), visited = 1;
        while (upper.kind === 'branch' && lower.kind === 'branch') {
            const count = upper.left.value - lower.left.value;
            if (k <= count) { upper = upper.left; lower = lower.left; span = span.leftChild(); }
            else { k -= count; upper = upper.right; lower = lower.right; span = span.rightChild(); }
            visited++;
        }
        return { value: this.domain[span.left], visited };
    }
}
class Grid {
    readonly tree: number[][];
    constructor(readonly height: number, readonly width: number, values: readonly number[]) {
        this.tree = Array.from({ length: height + 1 }, () => Array<number>(width + 1).fill(0));
        values.forEach((value, index) => this.add(Math.floor(index / width), index % width, value));
    }
    checkCell(row: number, column: number): void {
        if (row < 0 || row >= this.height || column < 0 || column >= this.width) fail(`BAD CELL ${row} ${column}`);
    }
    add(row: number, column: number, value: number): number {
        let visited = 0;
        for (let y = row + 1; y <= this.height; y += lowbit(y)) {
            for (let x = column + 1; x <= this.width; x += lowbit(x)) { this.tree[y][x] += value; visited++; }
        }
        return visited;
    }
    private prefix(row: number, column: number): Answer {
        let value = 0, visited = 0;
        for (let y = row; y > 0; y -= lowbit(y)) {
            for (let x = column; x > 0; x -= lowbit(x)) { value += this.tree[y][x]; visited++; }
        }
        return { value, visited };
    }
    query(row: number, column: number, bottom: number, right: number): Answer {
        const a = this.prefix(bottom + 1, right + 1), b = this.prefix(row, right + 1);
        const c = this.prefix(bottom + 1, column), d = this.prefix(row, column);
        return { value: a.value - b.value - c.value + d.value, visited: a.visited + b.visited + c.visited + d.visited };
    }
    dump(): string[] {
        return [`GRID DUMP rows=${this.height} cols=${this.width}`,
            ...this.tree.slice(1).map((row, index) => `ROW ${index + 1} ${words(row.slice(1))}`)];
    }
}

type Command =
    | { readonly type: 'LOAD'; readonly values: readonly number[] }
    | { readonly type: 'RESET' }
    | { readonly type: 'ARRAY' | 'CHECK'; readonly span: Span }
    | { readonly type: 'MO'; readonly queries: readonly Span[] }
    | { readonly type: 'SEG BUILD'; readonly op: string }
    | { readonly type: 'SQRT BUILD'; readonly block: number | undefined }
    | { readonly type: 'BUILD'; readonly kind: Exclude<ArrayKind, 'SEG' | 'SQRT'> }
    | { readonly type: 'GRID BUILD'; readonly height: number; readonly width: number; readonly values: readonly number[] }
    | { readonly type: 'DUMP'; readonly kind: DumpKind }
    | { readonly type: 'QUERY'; readonly kind: QueryKind; readonly span: Span }
    | { readonly type: 'SEG UPDATE' | 'FEN ADD'; readonly index: number; readonly value: number }
    | { readonly type: 'FEN PREFIX'; readonly index: number }
    | { readonly type: 'FEN LOWER'; readonly k: number }
    | { readonly type: 'LAZY UPDATE'; readonly span: Span; readonly value: number; readonly assign: boolean }
    | { readonly type: 'RANGE ADD'; readonly kind: 'RFEN' | 'SQRT'; readonly span: Span; readonly value: number }
    | { readonly type: 'PERSIST SET'; readonly version: number; readonly index: number; readonly value: number }
    | { readonly type: 'PERSIST QUERY'; readonly version: number; readonly span: Span }
    | { readonly type: 'PERSIST KTH'; readonly span: Span; readonly k: number }
    | { readonly type: 'PERSIST NODES' }
    | { readonly type: 'GRID ADD'; readonly row: number; readonly column: number; readonly value: number }
    | { readonly type: 'GRID SUM'; readonly first: Cell; readonly second: Cell };

function parseCommand(line: string): Command {
    const tokens = line.split(' '), name = tokens[0];
    const number = (index: number): number => Number(tokens[index]);
    const span = (index: number): Span => new Span(number(index), number(index + 1));
    const cell = (index: number): Cell => ({ row: number(index), column: number(index + 1) });
    if (name === 'LOAD') return { type: 'LOAD', values: tokens.slice(1).map(Number) };
    if (name === 'RESET') return { type: 'RESET' };
    if (name === 'ARRAY' || name === 'CHECK') return { type: name, span: span(1) };
    if (name === 'MO') {
        const queries: Span[] = [];
        for (let index = 1; index < tokens.length; index += 2) queries.push(span(index));
        return { type: 'MO', queries };
    }
    const kind = name as Kind, action = tokens[1]; // Command spelling is guaranteed by the input format.
    if (action === 'BUILD') {
        if (kind === 'SEG') return { type: 'SEG BUILD', op: tokens[2] };
        if (kind === 'SQRT') return { type: 'SQRT BUILD', block: tokens.length === 3 ? number(2) : undefined };
        if (kind === 'GRID') return { type: 'GRID BUILD', height: number(2), width: number(3), values: tokens.slice(4).map(Number) };
        return { type: 'BUILD', kind };
    }
    if (action === 'DUMP' && kind !== 'PERSIST') return { type: 'DUMP', kind };
    if (kind === 'GRID') return action === 'ADD' ?
        { type: 'GRID ADD', row: number(2), column: number(3), value: number(4) } :
        { type: 'GRID SUM', first: cell(2), second: cell(4) };
    if (kind === 'PERSIST') {
        if (action === 'NODES') return { type: 'PERSIST NODES' };
        if (action === 'SET') return { type: 'PERSIST SET', version: number(2), index: number(3), value: number(4) };
        if (action === 'KTH') return { type: 'PERSIST KTH', span: span(2), k: number(4) };
        return { type: 'PERSIST QUERY', version: number(2), span: span(3) };
    }
    if (kind === 'SEG' && action === 'UPDATE') return { type: 'SEG UPDATE', index: number(2), value: number(3) };
    if (kind === 'FEN') {
        if (action === 'ADD') return { type: 'FEN ADD', index: number(2), value: number(3) };
        if (action === 'PREFIX') return { type: 'FEN PREFIX', index: number(2) };
        if (action === 'LOWER') return { type: 'FEN LOWER', k: number(2) };
    }
    if (kind === 'LAZY' && (action === 'ADD' || action === 'ASSIGN')) return {
        type: 'LAZY UPDATE', span: span(2), value: number(4), assign: action === 'ASSIGN',
    };
    if ((kind === 'RFEN' || kind === 'SQRT') && action === 'ADD') return { type: 'RANGE ADD', kind, span: span(2), value: number(4) };
    return { type: 'QUERY', kind, span: span(2) };
}

interface StructureMap {
    SEG: Segment; LAZY: LazyTree; FEN: Fenwick; RFEN: RangeFenwick;
    SPARSE: SparseTable; SQRT: SqrtBlocks; PERSIST: Persistent; GRID: Grid;
}
class Laboratory {
    private values: number[];
    private original: readonly number[];
    private structures: Partial<StructureMap> = {};
    constructor(values: readonly number[]) { this.values = values.slice(); this.original = values.slice(); }
    private require<K extends Kind>(kind: K): StructureMap[K] {
        const tree = this.structures[kind];
        if (tree === undefined) fail(`NOT BUILT ${kind}`);
        return tree;
    }
    private checkIndex(index: number): void { if (index < 0 || index >= this.values.length) fail(`BAD INDEX ${index}`); }
    private checkRange(span: Span): void {
        this.checkIndex(span.left); this.checkIndex(span.right);
        if (span.left > span.right) fail(`BAD RANGE ${span.left} ${span.right}`);
    }
    private checkVersion(tree: Persistent, version: number): void {
        if (version < 0 || version >= tree.roots.length) fail(`BAD VERSION ${version}`);
    }
    private build(kind: ArrayKind, op: Operation = 'SUM', block = isqrt(this.values.length)): string {
        const n = this.values.length;
        switch (kind) {
            case 'SEG': {
                const tree = new Segment(this.values, op); this.structures.SEG = tree;
                return `SEG BUILD ${op} nodes=${tree.shape.nodes.length} maxnode=${tree.shape.nodes.at(-1)!.node} root=${tree.tree[1]}`;
            }
            case 'LAZY': {
                const tree = new LazyTree(this.values); this.structures.LAZY = tree;
                return `LAZY BUILD nodes=${tree.shape.nodes.length} ${describe(tree.nodes[1].value)}`;
            }
            case 'FEN': this.structures.FEN = new Fenwick(this.values); return `FEN BUILD n=${n} total=${sum(this.values)}`;
            case 'RFEN': this.structures.RFEN = new RangeFenwick(this.values); return `RFEN BUILD n=${n} total=${sum(this.values)}`;
            case 'SPARSE': {
                const tree = new SparseTable(this.values); this.structures.SPARSE = tree;
                return `SPARSE BUILD levels=${tree.minima.length} entries=${sum(tree.minima.map(row => row.length))}`;
            }
            case 'SQRT': {
                const tree = new SqrtBlocks(this.values, block); this.structures.SQRT = tree;
                return `SQRT BUILD block=${block} blocks=${tree.tags.length}`;
            }
            case 'PERSIST': {
                const tree = new Persistent(this.values); this.structures.PERSIST = tree;
                return `PERSIST BUILD nodes=${tree.positionNodes} distinct=${tree.domain.length} valuenodes=${tree.valueNodes}`;
            }
        }
    }
    private updateArray(span: Span, value: number, assign = false): void {
        for (let index = span.left; index <= span.right; index++) this.values[index] = assign ? value : this.values[index] + value;
    }
    private check(span: Span): string[] {
        const values = this.values.slice(span.left, span.right + 1), direct = aggregate(values), common = values.reduce(gcd, 0);
        const rows = [`CHECK ${span.left} ${span.right} ${describe(direct)} gcd=${common}`];
        let ok = 0, different = 0;
        for (const kind of arrayKinds) {
            if (this.structures[kind] === undefined) continue;
            let expected: readonly number[] = [direct.sum];
            if (kind === 'SEG') expected = [{ SUM: direct.sum, MIN: direct.min, MAX: direct.max, GCD: common }[this.require('SEG').op]];
            else if (kind === 'LAZY') expected = [direct.sum, direct.min, direct.max];
            else if (kind === 'SPARSE') expected = [direct.min, direct.max];
            let answer: Report, prefix = '';
            if (kind === 'PERSIST') {
                const tree = this.require(kind), version = tree.roots.length - 1;
                answer = tree.query(version, span); prefix = `version=${version} `;
            } else answer = this.require(kind).query(span);
            const same = answer.values.every((value, index) => value === expected[index]);
            if (same) ok++; else different++;
            rows.push(`${kind} ${same ? 'OK' : 'DIFF'} ${prefix}${answer.text}`);
        }
        rows.push(`RESULT ok=${ok} diff=${different}`);
        return rows;
    }
    private mo(queries: readonly Span[]): string[] {
        const blockSize = isqrt(this.values.length);
        const order = queries.map((_, index) => index).sort((a, b) => {
            const first = queries[a], second = queries[b], block = Math.floor(first.left / blockSize);
            return block - Math.floor(second.left / blockSize) ||
                (block % 2 === 0 ? first.right - second.right : second.right - first.right) || a - b;
        });
        const frequencies = new Map<number, number>(), answers = Array<number>(queries.length).fill(0);
        let left = 0, right = -1, moves = 0, distinct = 0;
        const add = (index: number): void => {
            const value = this.values[index], count = frequencies.get(value) ?? 0;
            if (count === 0) distinct++;
            frequencies.set(value, count + 1);
        };
        const remove = (index: number): void => {
            const value = this.values[index], count = frequencies.get(value)! - 1;
            frequencies.set(value, count);
            if (count === 0) distinct--;
        };
        for (const index of order) {
            const target = queries[index]; moves += Math.abs(target.left - left) + Math.abs(target.right - right);
            while (left > target.left) { left--; add(left); }
            while (right < target.right) { right++; add(right); }
            while (left < target.left) { remove(left); left++; }
            while (right > target.right) { remove(right); right--; }
            answers[index] = distinct;
        }
        return [`MO queries=${queries.length} block=${blockSize} moves=${moves}`, `ORDER ${words(order.map(index => index + 1))}`,
            ...queries.map((span, index) => `ANSWER ${index + 1} ${span.left} ${span.right} distinct=${answers[index]}`)];
    }
    execute(command: Command, line: string): string[] {
        switch (command.type) {
            case 'LOAD': {
                const removed = arrayKinds.filter(kind => this.structures[kind] !== undefined).length;
                const grid = this.structures.GRID;
                this.values = command.values.slice(); this.original = command.values.slice(); this.structures = {};
                if (grid !== undefined) this.structures.GRID = grid;
                return [`LOAD n=${this.values.length} removed=${removed}`];
            }
            case 'RESET': {
                this.values = this.original.slice();
                const op = this.structures.SEG?.op ?? 'SUM', block = this.structures.SQRT?.block ?? 1;
                let rebuilt = 0;
                for (const kind of arrayKinds) if (this.structures[kind] !== undefined) { this.build(kind, op, block); rebuilt++; }
                return [`RESET rebuilt=${rebuilt}`];
            }
            case 'ARRAY':
                this.checkRange(command.span);
                return [`${line} ${words(this.values.slice(command.span.left, command.span.right + 1))}`];
            case 'CHECK': this.checkRange(command.span); return this.check(command.span);
            case 'MO':
                for (const span of command.queries) this.checkRange(span);
                return this.mo(command.queries);
            case 'SEG BUILD':
                if (!isOperation(command.op)) fail(`BAD OP ${command.op}`);
                return [this.build('SEG', command.op)];
            case 'SQRT BUILD': {
                const block = command.block ?? isqrt(this.values.length);
                if (block > this.values.length) fail(`BAD BLOCK ${block}`);
                return [this.build('SQRT', 'SUM', block)];
            }
            case 'BUILD': return [this.build(command.kind)];
            case 'GRID BUILD': {
                const { height, width, values } = command;
                if (values.length !== height * width) fail(`BAD COUNT ${values.length} ${height * width}`);
                this.structures.GRID = new Grid(height, width, values);
                return [`GRID BUILD rows=${height} cols=${width} total=${sum(values)}`];
            }
            case 'DUMP': return this.require(command.kind).dump();
            case 'QUERY': {
                const tree = this.require(command.kind);
                this.checkRange(command.span);
                return [`${line} ${tree.query(command.span).text}`];
            }
            case 'SEG UPDATE': {
                const tree = this.require('SEG'); this.checkIndex(command.index);
                const visited = tree.update(command.index, command.value);
                this.values[command.index] = command.value;
                return [`${line} root=${tree.tree[1]} visited=${visited}`];
            }
            case 'LAZY UPDATE': {
                const tree = this.require('LAZY'); this.checkRange(command.span);
                const counts = tree.update(command.span, command.value, command.assign);
                this.updateArray(command.span, command.value, command.assign);
                return [`${line} visited=${counts.visited} covered=${counts.covered} pushes=${counts.pushes}`];
            }
            case 'FEN ADD': {
                const tree = this.require('FEN'); this.checkIndex(command.index);
                const visited = tree.bit.add(command.index + 1, command.value);
                tree.values[command.index] += command.value; this.values[command.index] += command.value;
                return [`${line} visited=${visited}`];
            }
            case 'FEN PREFIX': {
                const tree = this.require('FEN'); this.checkIndex(command.index);
                return [`${line} ${report(tree.bit.prefix(command.index + 1)).text}`];
            }
            case 'FEN LOWER': {
                const tree = this.require('FEN'), negative = tree.values.findIndex(value => value < 0);
                if (negative >= 0) fail(`NEGATIVE ${negative}`);
                const answer = tree.bit.lower(command.k);
                return [`${line} index=${answer.value < 0 ? 'none' : answer.value} visited=${answer.visited}`];
            }
            case 'RANGE ADD': {
                const tree = this.require(command.kind); this.checkRange(command.span);
                const result = tree.add(command.span, command.value);
                this.updateArray(command.span, command.value);
                return [`${line} ${typeof result === 'number' ? `visited=${result}` : partitionText(result)}`];
            }
            case 'PERSIST SET': {
                const tree = this.require('PERSIST'); this.checkVersion(tree, command.version); this.checkIndex(command.index);
                const version = tree.roots.length, created = tree.set(command.version, command.index, command.value);
                return [`${line} version=${version} created=${created}`];
            }
            case 'PERSIST QUERY': {
                const tree = this.require('PERSIST'); this.checkVersion(tree, command.version); this.checkRange(command.span);
                return [`${line} ${tree.query(command.version, command.span).text}`];
            }
            case 'PERSIST KTH': {
                const tree = this.require('PERSIST'); this.checkRange(command.span);
                if (command.k < 1 || command.k > command.span.length) fail(`BAD K ${command.k}`);
                const answer = tree.kth(command.span, command.k);
                return [`${line} value=${answer.value} visited=${answer.visited}`];
            }
            case 'PERSIST NODES': {
                const tree = this.require('PERSIST');
                return [`PERSIST NODES versions=${tree.roots.length} position=${tree.positionNodes} value=${tree.valueNodes}`];
            }
            case 'GRID ADD': {
                const tree = this.require('GRID'); tree.checkCell(command.row, command.column);
                return [`${line} visited=${tree.add(command.row, command.column, command.value)}`];
            }
            case 'GRID SUM': {
                const tree = this.require('GRID'), { first, second } = command;
                tree.checkCell(first.row, first.column); tree.checkCell(second.row, second.column);
                if (first.row > second.row || first.column > second.column) fail(`BAD RECT ${first.row} ${first.column} ${second.row} ${second.column}`);
                return [`${line} ${report(tree.query(first.row, first.column, second.row, second.column)).text}`];
            }
        }
    }
}

const input = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const laboratory = new Laboratory(input[1].split(' ').map(Number));
const commandCount = Number(input[2]);
for (let index = 0; index < commandCount; index++) {
    const line = input[index + 3];
    let rows: string[];
    try { rows = laboratory.execute(parseCommand(line), line); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        rows = [`ERROR ${error.message}`];
    }
    process.stdout.write(`${rows.join('\n')}\n`);
}
