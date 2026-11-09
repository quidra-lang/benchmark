'use strict';

const fs = require('node:fs');
const kinds = ['SEG', 'LAZY', 'FEN', 'RFEN', 'SPARSE', 'SQRT', 'PERSIST'];
const operations = ['SUM', 'MIN', 'MAX', 'GCD'];
const sum = values => values.reduce((total, value) => total + value, 0);
const lowbit = position => position & -position;
const summary = value => `sum=${value.sum} min=${value.min} max=${value.max}`;
class CommandError extends Error {}
const fail = message => { throw new CommandError(message); };
function gcd(a, b) {
    a = Math.abs(a); b = Math.abs(b);
    while (b !== 0) [a, b] = [b, a % b];
    return a;
}
function combine(operation, a, b) {
    switch (operation) {
        case 'SUM': return a + b;
        case 'MIN': return Math.min(a, b);
        case 'MAX': return Math.max(a, b);
        case 'GCD': return gcd(a, b);
    }
}
function merge(a, b) { return { sum: a.sum + b.sum, min: Math.min(a.min, b.min), max: Math.max(a.max, b.max) }; }

class SegmentTree {
    constructor(values, operation) {
        this.n = values.length;
        this.operation = operation;
        this.nodes = [];
        const build = (index, l, r) => {
            let value;
            if (l === r) value = operation === 'GCD' ? Math.abs(values[l]) : values[l];
            else {
                const middle = Math.floor((l + r) / 2);
                value = combine(operation, build(2 * index, l, middle), build(2 * index + 1, middle + 1, r));
            }
            this.nodes[index] = { l, r, value };
            return value;
        };
        build(1, 0, this.n - 1);
    }
    query(l, r) {
        let visited = 0;
        const walk = index => {
            ++visited;
            const node = this.nodes[index];
            if (l <= node.l && node.r <= r) return node.value;
            const middle = Math.floor((node.l + node.r) / 2);
            if (r <= middle) return walk(2 * index);
            if (l > middle) return walk(2 * index + 1);
            return combine(this.operation, walk(2 * index), walk(2 * index + 1));
        };
        const value = walk(1);
        return { value, visited };
    }
    update(position, value) {
        let visited = 0;
        const walk = index => {
            ++visited;
            const node = this.nodes[index];
            if (node.l === node.r) node.value = this.operation === 'GCD' ? Math.abs(value) : value;
            else {
                const middle = Math.floor((node.l + node.r) / 2);
                walk(position <= middle ? 2 * index : 2 * index + 1);
                node.value = combine(this.operation, this.nodes[2 * index].value, this.nodes[2 * index + 1].value);
            }
        };
        walk(1);
        return visited;
    }
    buildLine() { return `SEG BUILD ${this.operation} nodes=${2 * this.n - 1} maxnode=${this.nodes.length - 1} root=${this.nodes[1].value}`; }
    dump() {
        const rows = [`SEG DUMP ${this.operation} nodes=${2 * this.n - 1}`];
        this.nodes.forEach((node, index) => rows.push(`NODE ${index} ${node.l} ${node.r} ${node.value}`));
        return rows;
    }
}
class LazyTree {
    constructor(values) {
        this.n = values.length;
        this.nodes = [];
        const build = (index, l, r) => {
            let valuesAtNode;
            if (l === r) valuesAtNode = { sum: values[l], min: values[l], max: values[l] };
            else {
                const middle = Math.floor((l + r) / 2);
                valuesAtNode = merge(build(2 * index, l, middle), build(2 * index + 1, middle + 1, r));
            }
            return this.nodes[index] = { l, r, ...valuesAtNode, assign: null, add: 0 };
        };
        build(1, 0, this.n - 1);
    }
    assign(index, value) {
        const node = this.nodes[index];
        node.sum = value * (node.r - node.l + 1);
        node.min = node.max = value;
        if (node.l < node.r) { node.assign = value; node.add = 0; }
    }
    add(index, value) {
        const node = this.nodes[index];
        node.sum += value * (node.r - node.l + 1);
        node.min += value; node.max += value;
        if (node.l < node.r) node.add += value;
    }
    push(index) {
        const node = this.nodes[index];
        if (node.assign === null && node.add === 0) return 0;
        for (const child of [2 * index, 2 * index + 1]) {
            if (node.assign !== null) this.assign(child, node.assign);
            if (node.add !== 0) this.add(child, node.add);
        }
        node.assign = null; node.add = 0;
        return 1;
    }
    update(l, r, value, assignment) {
        let visited = 0, covered = 0, pushes = 0;
        const walk = index => {
            ++visited;
            const node = this.nodes[index];
            if (l <= node.l && node.r <= r) {
                ++covered;
                if (assignment) this.assign(index, value);
                else this.add(index, value);
                return;
            }
            pushes += this.push(index);
            const middle = Math.floor((node.l + node.r) / 2);
            if (l <= middle) walk(2 * index);
            if (r > middle) walk(2 * index + 1);
            Object.assign(node, merge(this.nodes[2 * index], this.nodes[2 * index + 1]));
        };
        walk(1);
        return { visited, covered, pushes };
    }
    query(l, r) {
        let visited = 0, pushes = 0;
        const walk = index => {
            ++visited;
            const node = this.nodes[index];
            if (l <= node.l && node.r <= r) return { sum: node.sum, min: node.min, max: node.max };
            pushes += this.push(index);
            const middle = Math.floor((node.l + node.r) / 2);
            if (r <= middle) return walk(2 * index);
            if (l > middle) return walk(2 * index + 1);
            return merge(walk(2 * index), walk(2 * index + 1));
        };
        return { ...walk(1), visited, pushes };
    }
    buildLine() { return `LAZY BUILD nodes=${2 * this.n - 1} ${summary(this.nodes[1])}`; }
    dump() {
        const rows = [`LAZY DUMP nodes=${2 * this.n - 1}`];
        this.nodes.forEach((node, index) => rows.push(`NODE ${index} ${node.l} ${node.r} ${summary(node)} assign=${node.assign ?? '-'} add=${node.add}`));
        return rows;
    }
}
class Fenwick {
    constructor(values) {
        this.n = values.length;
        this.tree = [0, ...values];
        for (let position = 1; position <= this.n; ++position) {
            const parent = position + lowbit(position);
            if (parent <= this.n) this.tree[parent] += this.tree[position];
        }
    }
    add(position, value) {
        let visited = 0;
        for (; position <= this.n; position += lowbit(position)) { this.tree[position] += value; ++visited; }
        return visited;
    }
    prefix(position) {
        let value = 0, visited = 0;
        for (; position >= 1; position -= lowbit(position)) { value += this.tree[position]; ++visited; }
        return { value, visited };
    }
    range(l, r) {
        const right = this.prefix(r + 1), left = this.prefix(l);
        return { value: right.value - left.value, visited: right.visited + left.visited };
    }
    lower(value) {
        let position = 0, visited = 0;
        for (let step = 2 ** Math.floor(Math.log2(this.n)); step >= 1; step = Math.floor(step / 2)) {
            if (position + step <= this.n) {
                ++visited;
                if (this.tree[position + step] < value) { value -= this.tree[position + step]; position += step; }
            }
        }
        return { index: position < this.n ? position : null, visited };
    }
}
class FenwickArray {
    constructor(values) { this.contents = values.slice(); this.bit = new Fenwick(values); }
    add(index, value) { this.contents[index] += value; return this.bit.add(index + 1, value); }
    buildLine() { return `FEN BUILD n=${this.contents.length} total=${sum(this.contents)}`; }
    dump() { return [`FEN DUMP n=${this.contents.length}`, 'T ' + this.bit.tree.slice(1).join(' ')]; }
}
class RangeFenwick {
    constructor(values) {
        this.n = values.length;
        const differences = values.map((value, index) => value - (index === 0 ? 0 : values[index - 1]));
        this.first = new Fenwick(differences);
        this.second = new Fenwick(differences.map((value, index) => value * index));
    }
    add(l, r, value) {
        return this.first.add(l + 1, value) + this.first.add(r + 2, -value)
            + this.second.add(l + 1, value * l) + this.second.add(r + 2, -value * (r + 1));
    }
    prefix(position) {
        const first = this.first.prefix(position), second = this.second.prefix(position);
        return { value: position * first.value - second.value, visited: first.visited + second.visited };
    }
    query(l, r) {
        const right = this.prefix(r + 1), left = this.prefix(l);
        return { value: right.value - left.value, visited: right.visited + left.visited };
    }
    buildLine() { return `RFEN BUILD n=${this.n} total=${this.prefix(this.n).value}`; }
    dump() { return [`RFEN DUMP n=${this.n}`, 'B1 ' + this.first.tree.slice(1).join(' '), 'B2 ' + this.second.tree.slice(1).join(' ')]; }
}
class SparseTable {
    constructor(values) {
        this.contents = values.slice();
        this.minimum = [values.map((_, index) => index)];
        this.maximum = [values.map((_, index) => index)];
        for (let level = 1, width = 2; width <= values.length; ++level, width *= 2) {
            const minima = [], maxima = [], half = width / 2;
            for (let index = 0; index + width <= values.length; ++index) {
                const a = this.minimum[level - 1][index], b = this.minimum[level - 1][index + half];
                const c = this.maximum[level - 1][index], d = this.maximum[level - 1][index + half];
                minima.push(values[a] <= values[b] ? a : b);
                maxima.push(values[c] >= values[d] ? c : d);
            }
            this.minimum.push(minima); this.maximum.push(maxima);
        }
    }
    query(l, r) {
        const level = Math.floor(Math.log2(r - l + 1)), end = r - 2 ** level + 1;
        const a = this.minimum[level][l], b = this.minimum[level][end], c = this.maximum[level][l], d = this.maximum[level][end];
        const minpos = this.contents[a] <= this.contents[b] ? a : b, maxpos = this.contents[c] >= this.contents[d] ? c : d;
        return { min: this.contents[minpos], minpos, max: this.contents[maxpos], maxpos, level };
    }
    buildLine() { return `SPARSE BUILD levels=${this.minimum.length} entries=${sum(this.minimum.map(row => row.length))}`; }
    dump() {
        const rows = [`SPARSE DUMP levels=${this.minimum.length}`];
        this.minimum.forEach((row, level) => rows.push(`MIN ${level} ${row.join(' ')}`, `MAX ${level} ${this.maximum[level].join(' ')}`));
        return rows;
    }
}
class SquareRoot {
    constructor(values, block) {
        this.n = values.length;
        this.block = block;
        this.raw = values.slice();
        this.tags = Array(Math.ceil(this.n / block)).fill(0);
        this.sums = this.tags.slice();
        values.forEach((value, index) => this.sums[Math.floor(index / block)] += value);
    }
    split(l, r) {
        const left = Math.floor(l / this.block), right = Math.floor(r / this.block), cells = [], whole = [];
        if (left === right) {
            for (let index = l; index <= r; ++index) cells.push(index);
        } else {
            for (let index = l; index < (left + 1) * this.block; ++index) cells.push(index);
            for (let index = right * this.block; index <= r; ++index) cells.push(index);
            for (let block = left + 1; block < right; ++block) whole.push(block);
        }
        return { cells, whole };
    }
    add(l, r, value) {
        const { cells, whole } = this.split(l, r);
        for (const index of cells) { this.raw[index] += value; this.sums[Math.floor(index / this.block)] += value; }
        for (const block of whole) { this.tags[block] += value; this.sums[block] += value * this.block; }
        return { cells: cells.length, whole: whole.length };
    }
    query(l, r) {
        const { cells, whole } = this.split(l, r);
        const value = sum(cells.map(index => this.raw[index] + this.tags[Math.floor(index / this.block)])) + sum(whole.map(block => this.sums[block]));
        return { value, cells: cells.length, whole: whole.length };
    }
    buildLine() { return `SQRT BUILD block=${this.block} blocks=${this.tags.length}`; }
    dump() {
        return [`SQRT DUMP block=${this.block} blocks=${this.tags.length}`, ...this.tags.map((tag, block) => {
            const first = block * this.block, last = Math.min(first + this.block, this.n) - 1;
            return `BLOCK ${block} ${first} ${last} add=${tag} sum=${this.sums[block]} ${this.raw.slice(first, last + 1).join(' ')}`;
        })];
    }
}
class PersistentTree {
    constructor(values) {
        this.n = values.length;
        this.nodes = 0;
        const build = (l, r) => {
            ++this.nodes;
            if (l === r) return { sum: values[l], left: null, right: null };
            const middle = Math.floor((l + r) / 2), left = build(l, middle), right = build(middle + 1, r);
            return { sum: left.sum + right.sum, left, right };
        };
        this.roots = [build(0, this.n - 1)];
    }
    fork(version, index, value, addition = false) {
        const before = this.nodes;
        const copy = (node, l, r) => {
            ++this.nodes;
            if (l === r) return { sum: addition ? node.sum + value : value, left: null, right: null };
            const middle = Math.floor((l + r) / 2);
            const left = index <= middle ? copy(node.left, l, middle) : node.left;
            const right = index > middle ? copy(node.right, middle + 1, r) : node.right;
            return { sum: left.sum + right.sum, left, right };
        };
        this.roots.push(copy(this.roots[version], 0, this.n - 1));
        return this.nodes - before;
    }
    query(version, l, r) {
        let visited = 0;
        const walk = (node, nl, nr) => {
            ++visited;
            if (l <= nl && nr <= r) return node.sum;
            const middle = Math.floor((nl + nr) / 2);
            if (r <= middle) return walk(node.left, nl, middle);
            if (l > middle) return walk(node.right, middle + 1, nr);
            return walk(node.left, nl, middle) + walk(node.right, middle + 1, nr);
        };
        const value = walk(this.roots[version], 0, this.n - 1);
        return { value, visited };
    }
}
class Persistence {
    constructor(values) {
        this.positions = new PersistentTree(values);
        this.values = [...new Set(values)].sort((a, b) => a - b);
        this.prefixes = new PersistentTree(Array(this.values.length).fill(0));
        const ranks = new Map(this.values.map((value, index) => [value, index]));
        values.forEach((value, index) => this.prefixes.fork(index, ranks.get(value), 1, true));
    }
    kth(l, r, k) {
        let upper = this.prefixes.roots[r + 1], lower = this.prefixes.roots[l];
        let left = 0, right = this.values.length - 1, visited = 1;
        while (left < right) {
            const middle = Math.floor((left + right) / 2), count = upper.left.sum - lower.left.sum;
            if (k <= count) { upper = upper.left; lower = lower.left; right = middle; }
            else { k -= count; upper = upper.right; lower = lower.right; left = middle + 1; }
            ++visited;
        }
        return { value: this.values[left], visited };
    }
    buildLine() { return `PERSIST BUILD nodes=${this.positions.nodes} distinct=${this.values.length} valuenodes=${this.prefixes.nodes}`; }
    nodeLine() { return `PERSIST NODES versions=${this.positions.roots.length} position=${this.positions.nodes} value=${this.prefixes.nodes}`; }
}
class Grid {
    constructor(height, width, values) {
        this.h = height; this.w = width;
        this.tree = Array.from({ length: height + 1 }, () => Array(width + 1).fill(0));
        values.forEach((value, index) => this.add(Math.floor(index / width), index % width, value));
    }
    add(i, j, value) {
        let visited = 0;
        for (let y = i + 1; y <= this.h; y += lowbit(y)) {
            for (let z = j + 1; z <= this.w; z += lowbit(z)) { this.tree[y][z] += value; ++visited; }
        }
        return visited;
    }
    prefix(i, j) {
        let value = 0, visited = 0;
        for (let y = i; y >= 1; y -= lowbit(y)) {
            for (let z = j; z >= 1; z -= lowbit(z)) { value += this.tree[y][z]; ++visited; }
        }
        return { value, visited };
    }
    query(i1, j1, i2, j2) {
        const a = this.prefix(i2 + 1, j2 + 1), b = this.prefix(i1, j2 + 1), c = this.prefix(i2 + 1, j1), d = this.prefix(i1, j1);
        return { value: a.value - b.value - c.value + d.value, visited: a.visited + b.visited + c.visited + d.visited };
    }
    dump() { return [`GRID DUMP rows=${this.h} cols=${this.w}`, ...this.tree.slice(1).map((row, index) => `ROW ${index + 1} ${row.slice(1).join(' ')}`)]; }
}
function mo(values, ranges) {
    const block = Math.floor(Math.sqrt(values.length));
    const queries = ranges.map(([l, r], index) => ({ l, r, index, block: Math.floor(l / block) }));
    const order = queries.slice().sort((a, b) => a.block - b.block || (a.block % 2 === 0 ? a.r - b.r : b.r - a.r) || a.index - b.index);
    const counts = new Map(), answers = Array(ranges.length);
    let left = 0, right = -1, moves = 0;
    const add = index => { const value = values[index]; counts.set(value, (counts.get(value) ?? 0) + 1); ++moves; };
    const remove = index => {
        const value = values[index], count = counts.get(value) - 1;
        if (count === 0) counts.delete(value);
        else counts.set(value, count);
        ++moves;
    };
    for (const query of order) {
        while (left > query.l) add(--left);
        while (right < query.r) add(++right);
        while (left < query.l) remove(left++);
        while (right > query.r) remove(right--);
        answers[query.index] = counts.size;
    }
    return [`MO queries=${ranges.length} block=${block} moves=${moves}`, 'ORDER ' + order.map(query => query.index + 1).join(' '),
        ...queries.map(query => `ANSWER ${query.index + 1} ${query.l} ${query.r} distinct=${answers[query.index]}`)];
}
class Laboratory {
    constructor(values) {
        this.array = values.slice();
        this.original = values.slice();
        this.structures = Object.fromEntries(kinds.map(kind => [kind, null]));
        this.grid = null;
    }
    checkIndex(index) { if (index < 0 || index >= this.array.length) fail(`BAD INDEX ${index}`); }
    checkRange(l, r) {
        this.checkIndex(l); this.checkIndex(r);
        if (l > r) fail(`BAD RANGE ${l} ${r}`);
    }
    checkVersion(state, version) {
        if (version < 0 || version >= state.positions.roots.length) fail(`BAD VERSION ${version}`);
    }
    checkCell(i, j) {
        if (i < 0 || i >= this.grid.h || j < 0 || j >= this.grid.w) fail(`BAD CELL ${i} ${j}`);
    }
    create(kind, option) {
        switch (kind) {
            case 'SEG': return new SegmentTree(this.array, option);
            case 'LAZY': return new LazyTree(this.array);
            case 'FEN': return new FenwickArray(this.array);
            case 'RFEN': return new RangeFenwick(this.array);
            case 'SPARSE': return new SparseTable(this.array);
            case 'SQRT': return new SquareRoot(this.array, option);
            case 'PERSIST': return new Persistence(this.array);
            default: throw new Error(`Unknown structure ${kind}`);
        }
    }
    describe(kind, l, r, version = null) {
        const state = this.structures[kind];
        switch (kind) {
            case 'SEG': {
                const result = state.query(l, r), key = state.operation.toLowerCase();
                return { text: `${key}=${result.value} visited=${result.visited}`, values: { [key]: result.value } };
            }
            case 'LAZY': {
                const result = state.query(l, r);
                return { text: `${summary(result)} visited=${result.visited} pushes=${result.pushes}`,
                    values: { sum: result.sum, min: result.min, max: result.max } };
            }
            case 'FEN':
            case 'RFEN': {
                const result = kind === 'FEN' ? state.bit.range(l, r) : state.query(l, r);
                return { text: `sum=${result.value} visited=${result.visited}`, values: { sum: result.value } };
            }
            case 'SPARSE': {
                const result = state.query(l, r);
                return { text: `min=${result.min} minpos=${result.minpos} max=${result.max} maxpos=${result.maxpos} level=${result.level}`,
                    values: { min: result.min, max: result.max } };
            }
            case 'SQRT': {
                const result = state.query(l, r);
                return { text: `sum=${result.value} whole=${result.whole} cells=${result.cells}`, values: { sum: result.value } };
            }
            case 'PERSIST': {
                const selected = version ?? state.positions.roots.length - 1, result = state.positions.query(selected, l, r);
                return { text: `sum=${result.value} visited=${result.visited}`, values: { sum: result.value }, version: selected };
            }
        }
    }
    check(l, r) {
        const values = this.array.slice(l, r + 1), direct = { sum: sum(values), min: Math.min(...values), max: Math.max(...values), gcd: values.reduce(gcd, 0) };
        const rows = [`CHECK ${l} ${r} ${summary(direct)} gcd=${direct.gcd}`];
        let ok = 0, different = 0;
        for (const kind of kinds) if (this.structures[kind] !== null) {
            const result = this.describe(kind, l, r), matches = Object.entries(result.values).every(([key, value]) => value === direct[key]);
            if (matches) ++ok;
            else ++different;
            const prefix = kind === 'PERSIST' ? `version=${result.version} ` : '';
            rows.push(`${kind} ${matches ? 'OK' : 'DIFF'} ${prefix}${result.text}`);
        }
        rows.push(`RESULT ok=${ok} diff=${different}`);
        return rows;
    }
    modifyArray(l, r, value, assignment = false) {
        for (let index = l; index <= r; ++index) this.array[index] = assignment ? value : this.array[index] + value;
    }
    execute(line) {
        const words = line.split(' '), kind = words[0], action = words[1];
        if (kind === 'LOAD') {
            const removed = kinds.filter(kind => this.structures[kind] !== null).length;
            this.array = words.slice(1).map(Number);
            this.original = this.array.slice();
            this.structures = Object.fromEntries(kinds.map(kind => [kind, null]));
            return [`LOAD n=${this.array.length} removed=${removed}`];
        }
        if (kind === 'RESET') {
            this.array = this.original.slice();
            let rebuilt = 0;
            for (const kind of kinds) {
                const previous = this.structures[kind];
                if (previous === null) continue;
                const option = kind === 'SEG' ? previous.operation : kind === 'SQRT' ? previous.block : undefined;
                this.structures[kind] = this.create(kind, option);
                ++rebuilt;
            }
            return [`RESET rebuilt=${rebuilt}`];
        }
        if (kind === 'ARRAY' || kind === 'CHECK') {
            const [l, r] = words.slice(1).map(Number);
            this.checkRange(l, r);
            return kind === 'CHECK' ? this.check(l, r) : [`ARRAY ${l} ${r} ${this.array.slice(l, r + 1).join(' ')}`];
        }
        if (kind === 'MO') {
            const numbers = words.slice(1).map(Number), ranges = [];
            for (let index = 0; index < numbers.length; index += 2) {
                const l = numbers[index], r = numbers[index + 1];
                this.checkRange(l, r);
                ranges.push([l, r]);
            }
            return mo(this.array, ranges);
        }
        const args = words.slice(2);
        if (action === 'BUILD') {
            let option;
            if (kind === 'SEG') {
                option = args[0];
                if (!operations.includes(option)) fail(`BAD OP ${option}`);
            } else if (kind === 'SQRT') {
                option = args.length === 0 ? Math.floor(Math.sqrt(this.array.length)) : Number(args[0]);
                if (option > this.array.length) fail(`BAD BLOCK ${option}`);
            } else if (kind === 'GRID') {
                const [height, width, ...values] = args.map(Number);
                if (values.length !== height * width) fail(`BAD COUNT ${values.length} ${height * width}`);
                this.grid = new Grid(height, width, values);
                return [`GRID BUILD rows=${height} cols=${width} total=${sum(values)}`];
            }
            const state = this.create(kind, option);
            this.structures[kind] = state;
            return [state.buildLine()];
        }
        const state = kind === 'GRID' ? this.grid : this.structures[kind];
        if (state === null) fail(`NOT BUILT ${kind}`);
        if (action === 'DUMP') return state.dump();
        const numbers = args.map(Number);
        if (kind === 'SEG') {
            if (action === 'UPDATE') {
                const [index, value] = numbers;
                this.checkIndex(index);
                const visited = state.update(index, value);
                this.array[index] = value;
                return [`SEG UPDATE ${index} ${value} root=${state.nodes[1].value} visited=${visited}`];
            }
            const [l, r] = numbers;
            this.checkRange(l, r);
            return [`SEG QUERY ${l} ${r} ${this.describe(kind, l, r).text}`];
        }
        if (kind === 'LAZY') {
            const [l, r, value] = numbers;
            this.checkRange(l, r);
            if (action === 'QUERY') return [`LAZY QUERY ${l} ${r} ${this.describe(kind, l, r).text}`];
            const assignment = action === 'ASSIGN', result = state.update(l, r, value, assignment);
            this.modifyArray(l, r, value, assignment);
            return [`LAZY ${action} ${l} ${r} ${value} visited=${result.visited} covered=${result.covered} pushes=${result.pushes}`];
        }
        if (kind === 'FEN') {
            if (action === 'LOWER') {
                const negative = state.contents.findIndex(value => value < 0);
                if (negative >= 0) fail(`NEGATIVE ${negative}`);
                const result = state.bit.lower(numbers[0]);
                return [`FEN LOWER ${numbers[0]} index=${result.index ?? 'none'} visited=${result.visited}`];
            }
            if (action === 'RANGE') {
                const [l, r] = numbers;
                this.checkRange(l, r);
                return [`FEN RANGE ${l} ${r} ${this.describe(kind, l, r).text}`];
            }
            const index = numbers[0];
            this.checkIndex(index);
            if (action === 'ADD') {
                const value = numbers[1], visited = state.add(index, value);
                this.array[index] += value;
                return [`FEN ADD ${index} ${value} visited=${visited}`];
            }
            if (action === 'PREFIX') {
                const result = state.bit.prefix(index + 1);
                return [`FEN PREFIX ${index} sum=${result.value} visited=${result.visited}`];
            }
        }
        if (kind === 'RFEN' || kind === 'SQRT') {
            const [l, r, value] = numbers;
            this.checkRange(l, r);
            if (action === 'SUM') return [`${kind} SUM ${l} ${r} ${this.describe(kind, l, r).text}`];
            const result = state.add(l, r, value);
            this.modifyArray(l, r, value);
            const detail = kind === 'RFEN' ? `visited=${result}` : `whole=${result.whole} cells=${result.cells}`;
            return [`${kind} ADD ${l} ${r} ${value} ${detail}`];
        }
        if (kind === 'SPARSE') {
            const [l, r] = numbers;
            this.checkRange(l, r);
            return [`SPARSE QUERY ${l} ${r} ${this.describe(kind, l, r).text}`];
        }
        if (kind === 'PERSIST') {
            if (action === 'NODES') return [state.nodeLine()];
            if (action === 'KTH') {
                const [l, r, k] = numbers;
                this.checkRange(l, r);
                if (k < 1 || k > r - l + 1) fail(`BAD K ${k}`);
                const result = state.kth(l, r, k);
                return [`PERSIST KTH ${l} ${r} ${k} value=${result.value} visited=${result.visited}`];
            }
            const version = numbers[0];
            this.checkVersion(state, version);
            if (action === 'SET') {
                const [, index, value] = numbers;
                this.checkIndex(index);
                const newVersion = state.positions.roots.length, created = state.positions.fork(version, index, value);
                return [`PERSIST SET ${version} ${index} ${value} version=${newVersion} created=${created}`];
            }
            const [, l, r] = numbers;
            this.checkRange(l, r);
            return [`PERSIST QUERY ${version} ${l} ${r} ${this.describe(kind, l, r, version).text}`];
        }
        if (kind === 'GRID') {
            if (action === 'ADD') {
                const [i, j, value] = numbers;
                this.checkCell(i, j);
                return [`GRID ADD ${i} ${j} ${value} visited=${state.add(i, j, value)}`];
            }
            const [i1, j1, i2, j2] = numbers;
            this.checkCell(i1, j1); this.checkCell(i2, j2);
            if (i1 > i2 || j1 > j2) fail(`BAD RECT ${i1} ${j1} ${i2} ${j2}`);
            const result = state.query(i1, j1, i2, j2);
            return [`GRID SUM ${i1} ${j1} ${i2} ${j2} sum=${result.value} visited=${result.visited}`];
        }
        throw new Error(`Unhandled command ${line}`);
    }
}

const input = fs.readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const laboratory = new Laboratory(input[1].split(' ').map(Number));
for (let index = 0; index < Number(input[2]); ++index) {
    try { process.stdout.write(laboratory.execute(input[index + 3]).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
