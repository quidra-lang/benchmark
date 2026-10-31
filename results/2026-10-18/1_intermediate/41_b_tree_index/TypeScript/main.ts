import { readFileSync } from 'node:fs';

interface Entry { readonly key: number; value: string }
interface SearchResult { node: Node | null; index: number; path: string[] }
interface Changes { writes: number; frees: number }
interface ScanResult { entries: Entry[]; visited: number }
type Insertion = { inserted: true } | { inserted: false; old: string };
type MergeCase = '2c' | '3b-left' | '3b-right';
type DeleteCase = '1' | '2a' | '2b' | '3a-left' | '3a-right' | MergeCase;
type Trace = string[] | null;
type Cursor = number | 'BEGIN' | 'END' | null;

class CommandError extends Error {}
function fail(reason: string): never { throw new CommandError(reason); }
const entryText = (entry: Entry): string => `${entry.key}=${entry.value}`;
const emit = (trace: Trace, line: string): void => { if (trace !== null) trace.push(line); };

class Node {
    page: number;
    entries: Entry[];
    children: Node[];
    constructor(page: number, entries: Entry[] = [], children: Node[] = []) {
        this.page = page; this.entries = entries; this.children = children;
    }
    get leaf(): boolean { return this.children.length === 0; }
    notation(): string { return `[${this.entries.map(entry => entry.key).join(' ')}]`; }
    position(key: number): number {
        const found = this.entries.findIndex(entry => key <= entry.key);
        return found < 0 ? this.entries.length : found;
    }
    clone(): Node { return new Node(this.page, this.entries.map(entry => ({ ...entry })), this.children.map(child => child.clone())); }
    content(): string { return JSON.stringify([this.entries.map(entry => [entry.key, entry.value]), this.children.map(child => child.page)]); }
    dump(): string[] {
        const tokens = ['('];
        if (!this.leaf) tokens.push(...this.children[0].dump());
        for (let index = 0; index < this.entries.length; ++index) {
            tokens.push(entryText(this.entries[index]));
            if (!this.leaf) tokens.push(...this.children[index + 1].dump());
        }
        tokens.push(')');
        return tokens;
    }
}

class Tree {
    readonly degree: number;
    root = new Node(0);
    splits = 0;
    merges = 0;
    borrows = 0;
    constructor(degree: number) { this.degree = degree; }
    clone(): Tree {
        const copy = new Tree(this.degree);
        copy.root = this.root.clone();
        copy.splits = this.splits; copy.merges = this.merges; copy.borrows = this.borrows;
        return copy;
    }
    nodes(): Node[] {
        const result: Node[] = [];
        const visit = (node: Node): void => { result.push(node); node.children.forEach(visit); };
        visit(this.root);
        return result;
    }
    entries(): Entry[] {
        const result: Entry[] = [];
        const visit = (node: Node): void => {
            if (!node.leaf) visit(node.children[0]);
            for (let index = 0; index < node.entries.length; ++index) {
                result.push(node.entries[index]);
                if (!node.leaf) visit(node.children[index + 1]);
            }
        };
        visit(this.root);
        return result;
    }
    height(): number {
        let height = 0, node = this.root;
        while (!node.leaf) { ++height; node = node.children[0]; }
        return height;
    }
    snapshot(): Map<number, string> { return new Map<number, string>(this.nodes().map(node => [node.page, node.content()])); }
    changes(before: ReadonlyMap<number, string>): Changes {
        const after = this.snapshot();
        return {
            writes: [...after].filter(([page, content]) => before.get(page) !== content).length,
            frees: [...before.keys()].filter(page => !after.has(page)).length,
        };
    }
    allocate(entries: Entry[] = [], children: Node[] = []): Node {
        const used = new Set(this.nodes().map(node => node.page));
        let page = 0;
        while (used.has(page)) ++page;
        return new Node(page, entries, children);
    }
    search(key: number): SearchResult {
        const path: string[] = [];
        let node = this.root;
        while (true) {
            path.push(node.notation());
            const index = node.position(key);
            if (index < node.entries.length && node.entries[index].key === key) return { node, index, path };
            if (node.leaf) return { node: null, index: -1, path };
            node = node.children[index];
        }
    }
    violation(): string | null {
        let referenceDepth: number | null = null;
        const visit = (node: Node, location: string, depth: number, low: number, high: number): string | null => {
            const count = node.entries.length, minimum = node === this.root ? (node.leaf ? 0 : 1) : this.degree - 1;
            const maximum = 2 * this.degree - 1, at = `at=${location} node=${node.notation()}`;
            if (count < minimum || count > maximum) return `COUNT ${at} keys=${count} allowed=${minimum}..${maximum}`;
            for (let index = 0; index + 1 < count; ++index) if (node.entries[index].key >= node.entries[index + 1].key) {
                return `ORDER ${at} ${node.entries[index].key}>=${node.entries[index + 1].key}`;
            }
            for (const entry of node.entries) if (entry.key <= low || entry.key >= high) {
                return `RANGE ${at} key=${entry.key} low=${low === -Infinity ? '-inf' : low} high=${high === Infinity ? '+inf' : high}`;
            }
            if (node.leaf) {
                if (referenceDepth === null) referenceDepth = depth;
                else if (depth !== referenceDepth) return `DEPTH ${at} depth=${depth} expected=${referenceDepth}`;
            }
            for (let index = 0; index < node.children.length; ++index) {
                const problem = visit(node.children[index], `${location}.${index}`, depth + 1,
                    index === 0 ? low : node.entries[index - 1].key, index === count ? high : node.entries[index].key);
                if (problem !== null) return problem;
            }
            return null;
        };
        return visit(this.root, 'root', 0, -Infinity, Infinity);
    }
    static load(degree: number, tokens: readonly string[]): Tree {
        let position = 0, page = 0;
        const unexpected = (): never => fail(`SYNTAX ${position + 1}`);
        const entry = (): Entry => {
            if (position === tokens.length || tokens[position] === '(' || tokens[position] === ')') unexpected();
            const [key, value] = tokens[position++].split('=');
            return { key: Number(key), value };
        };
        const parse = (): Node => {
            if (position === tokens.length || tokens[position] !== '(') unexpected();
            ++position;
            const node = new Node(page++);
            if (tokens[position] === '(') {
                node.children.push(parse());
                while (tokens[position] !== ')') { node.entries.push(entry()); node.children.push(parse()); }
            } else {
                while (tokens[position] !== ')') node.entries.push(entry());
            }
            ++position;
            return node;
        };
        const tree = new Tree(degree);
        tree.root = parse();
        if (position !== tokens.length) unexpected();
        return tree;
    }
    split(parent: Node, index: number, trace: Trace): void {
        const child = parent.children[index], before = child.notation(), middle = child.entries[this.degree - 1];
        const right = this.allocate(child.entries.slice(this.degree), child.children.slice(this.degree));
        child.entries = child.entries.slice(0, this.degree - 1);
        child.children = child.children.slice(0, this.degree);
        parent.entries.splice(index, 0, middle); parent.children.splice(index + 1, 0, right);
        ++this.splits;
        emit(trace, `STEP split page=${child.page} keys=${before} up=${middle.key} new=${right.page}`);
    }
    upsert(key: number, value: string, trace: Trace = null): Insertion {
        const found = this.search(key);
        if (found.node !== null) {
            const entry = found.node.entries[found.index], old = entry.value;
            entry.value = value;
            return { inserted: false, old };
        }
        if (this.root.entries.length === 2 * this.degree - 1) {
            this.root = this.allocate([], [this.root]);
            emit(trace, `STEP grow page=${this.root.page}`);
            this.split(this.root, 0, trace);
        }
        let node = this.root;
        while (!node.leaf) {
            let index = node.position(key);
            if (node.children[index].entries.length === 2 * this.degree - 1) {
                this.split(node, index, trace);
                if (key > node.entries[index].key) ++index;
            }
            node = node.children[index];
        }
        node.entries.splice(node.position(key), 0, { key, value });
        emit(trace, `STEP place page=${node.page} keys=${node.notation()}`);
        return { inserted: true };
    }
    merge(parent: Node, index: number, caseName: MergeCase, trace: Trace): Node {
        const left = parent.children[index], right = parent.children[index + 1];
        left.entries.push(parent.entries[index], ...right.entries);
        left.children.push(...right.children);
        parent.entries.splice(index, 1); parent.children.splice(index + 1, 1);
        ++this.merges;
        emit(trace, `STEP ${caseName} page=${parent.page} merge=${left.page}+${right.page} keys=${left.notation()}`);
        if (parent === this.root && parent.entries.length === 0) {
            this.root = left;
            emit(trace, `STEP shrink page=${left.page}`);
        }
        return left;
    }
    remove(key: number, cases: DeleteCase[] = [], trace: Trace = null, node: Node = this.root): void {
        const index = node.position(key);
        if (index < node.entries.length && node.entries[index].key === key) {
            if (node.leaf) {
                cases.push('1'); node.entries.splice(index, 1);
                emit(trace, `STEP 1 page=${node.page} keys=${node.notation()}`);
                return;
            }
            const left = node.children[index], right = node.children[index + 1];
            if (left.entries.length >= this.degree) {
                let last = left;
                while (!last.leaf) last = last.children.at(-1)!;
                const predecessor: Entry = { ...last.entries.at(-1)! };
                cases.push('2a'); emit(trace, `STEP 2a page=${node.page} pred=${predecessor.key}`);
                this.remove(predecessor.key, cases, trace, left);
                node.entries[index] = predecessor;
            } else if (right.entries.length >= this.degree) {
                let first = right;
                while (!first.leaf) first = first.children[0];
                const successor = { ...first.entries[0] };
                cases.push('2b'); emit(trace, `STEP 2b page=${node.page} succ=${successor.key}`);
                this.remove(successor.key, cases, trace, right);
                node.entries[index] = successor;
            } else {
                cases.push('2c');
                const child = this.merge(node, index, '2c', trace);
                this.remove(key, cases, trace, child);
            }
            return;
        }
        let child = node.children[index];
        if (child.entries.length === this.degree - 1) {
            const left = node.children[index - 1], right = node.children[index + 1];
            if (left !== undefined && left.entries.length >= this.degree) {
                cases.push('3a-left');
                child.entries.unshift(node.entries[index - 1]);
                node.entries[index - 1] = left.entries.pop()!;
                if (!left.leaf) child.children.unshift(left.children.pop()!);
                ++this.borrows;
                emit(trace, `STEP 3a-left page=${node.page} child=${child.page} from=${left.page} keys=${child.notation()}`);
            } else if (right !== undefined && right.entries.length >= this.degree) {
                cases.push('3a-right');
                child.entries.push(node.entries[index]);
                node.entries[index] = right.entries.shift()!;
                if (!right.leaf) child.children.push(right.children.shift()!);
                ++this.borrows;
                emit(trace, `STEP 3a-right page=${node.page} child=${child.page} from=${right.page} keys=${child.notation()}`);
            } else if (left !== undefined) {
                cases.push('3b-left'); child = this.merge(node, index - 1, '3b-left', trace);
            } else {
                cases.push('3b-right'); child = this.merge(node, index, '3b-right', trace);
            }
        }
        this.remove(key, cases, trace, child);
    }
    scan(low: number, high: number): ScanResult {
        let visited = 0;
        const entries: Entry[] = [];
        const visit = (node: Node): void => {
            ++visited;
            for (let index = 0; index <= node.entries.length; ++index) {
                if (!node.leaf && (index === 0 || node.entries[index - 1].key < high)
                    && (index === node.entries.length || node.entries[index].key > low)) visit(node.children[index]);
                if (index < node.entries.length && low <= node.entries[index].key && node.entries[index].key <= high) {
                    entries.push(node.entries[index]);
                }
            }
        };
        visit(this.root);
        return { entries, visited };
    }
    compact(): void {
        let entries = this.entries();
        let children: Node[] = [];
        while (true) {
            const groups = Math.floor((entries.length + 2 * this.degree) / (2 * this.degree));
            const keys = entries.length - groups + 1, size = Math.floor(keys / groups), extra = keys % groups;
            const nodes: Node[] = [], separators: Entry[] = [];
            let entryIndex = 0, childIndex = 0;
            for (let group = 0; group < groups; ++group) {
                const count = size + (group < extra ? 1 : 0);
                nodes.push(new Node(-1, entries.slice(entryIndex, entryIndex + count),
                    children.length === 0 ? [] : children.slice(childIndex, childIndex + count + 1)));
                entryIndex += count; childIndex += count + 1;
                if (group + 1 < groups) separators.push(entries[entryIndex++]);
            }
            if (groups === 1) { this.root = nodes[0]; break; }
            entries = separators; children = nodes;
        }
        this.nodes().forEach((node, page) => { node.page = page; });
        this.splits = 0; this.merges = 0; this.borrows = 0;
    }
}

const requiresValidTree = new Set([
    'INSERT', 'BULKLOAD', 'DELETE', 'DELRANGE', 'RANGE', 'COUNT', 'MIN', 'MAX',
    'FLOOR', 'CEIL', 'RANK', 'SELECT', 'SEEK', 'NEXT', 'PREV', 'HEIGHT', 'COMPACT',
]);

class Workbench {
    private tree: Tree | null = null;
    private saved: Tree | null = null;
    private cursor: Cursor = null;
    private trace = false;
    private summary(prefix: string, tree: Tree): string {
        return `${prefix} nodes=${tree.nodes().length} keys=${tree.entries().length} ${tree.violation() === null ? 'OK' : 'DAMAGED'}`;
    }
    command(line: string): string[] {
        const [verb, ...args] = line.split(' '), first = Number(args[0]), second = Number(args[1]);
        if (verb === 'TRACE') {
            this.trace = args[0] === 'ON';
            return [`TRACE ${args[0]}`];
        }
        if (verb === 'CREATE' || verb === 'LOAD') {
            if (first < 2 || first > 5) fail(`BAD DEGREE ${first}`);
            const replacement = verb === 'CREATE' ? new Tree(first) : Tree.load(first, args.slice(1));
            this.tree = replacement; this.cursor = null;
            return [verb === 'CREATE' ? `CREATE t=${first}` : this.summary(`LOAD t=${first}`, replacement)];
        }
        if (this.tree === null) fail('NO INDEX');
        const tree = this.tree;
        if (requiresValidTree.has(verb) && tree.violation() !== null) fail('DAMAGED');
        const entries = tree.entries();
        if (['DELRANGE', 'RANGE', 'COUNT'].includes(verb) && first > second) fail(`BAD RANGE ${first} ${second}`);
        if (verb === 'SELECT' && (first < 1 || first > entries.length)) fail(`BAD POSITION ${first}`);
        if ((verb === 'NEXT' || verb === 'PREV') && this.cursor === null) fail('NO CURSOR');
        const output: string[] = [];
        switch (verb) {
        case 'INSERT': {
            const before = tree.snapshot(), splits = tree.splits;
            const result = tree.upsert(first, args[1], this.trace ? output : null);
            const { writes } = tree.changes(before);
            output.push(result.inserted
                ? `INSERT ${first} NEW splits=${tree.splits - splits} height=${tree.height()} writes=${writes}`
                : `INSERT ${first} UPDATED old=${result.old} writes=${writes}`);
            break;
        }
        case 'BULKLOAD': {
            const before = tree.snapshot(), splits = tree.splits;
            let inserted = 0, updated = 0;
            for (let index = 0; index < args.length; index += 2) {
                if (tree.upsert(Number(args[index]), args[index + 1]).inserted) ++inserted;
                else ++updated;
            }
            output.push(`BULKLOAD pairs=${args.length / 2} new=${inserted} updated=${updated} splits=${tree.splits - splits} height=${tree.height()} writes=${tree.changes(before).writes}`);
            break;
        }
        case 'DELETE': {
            const found = tree.search(first);
            if (found.node === null) { output.push(`DELETE ${first} NOT FOUND`); break; }
            const value = found.node.entries[found.index].value, before = tree.snapshot();
            const cases: DeleteCase[] = [];
            tree.remove(first, cases, this.trace ? output : null);
            const { writes, frees } = tree.changes(before);
            output.push(`DELETE ${first} REMOVED value=${value} cases=${cases.join(',')} height=${tree.height()} writes=${writes} frees=${frees}`);
            break;
        }
        case 'DELRANGE': {
            const keys = entries.filter(entry => first <= entry.key && entry.key <= second).map(entry => entry.key);
            const before = tree.snapshot(), merges = tree.merges, borrows = tree.borrows;
            for (const key of keys) tree.remove(key);
            const { writes, frees } = tree.changes(before);
            output.push(`DELRANGE ${first} ${second} removed=${keys.length} merges=${tree.merges - merges} borrows=${tree.borrows - borrows} height=${tree.height()} writes=${writes} frees=${frees}`);
            break;
        }
        case 'GET': {
            const { node, index, path } = tree.search(first);
            const result = node === null ? 'NOT FOUND' : `FOUND value=${node.entries[index].value}`;
            output.push(`GET ${first} ${result} path=${path.join(' -> ')}`);
            break;
        }
        case 'RANGE': case 'COUNT': {
            const result = tree.scan(first, second);
            const suffix = verb === 'RANGE' ? result.entries.map(entry => ` ${entryText(entry)}`).join('') : '';
            output.push(`${verb} ${first} ${second} count=${result.entries.length} visited=${result.visited}${suffix}`);
            break;
        }
        case 'MIN': case 'MAX': {
            const entry = verb === 'MIN' ? entries[0] : entries.at(-1);
            output.push(`${verb} ${entry === undefined ? 'EMPTY' : entryText(entry)}`);
            break;
        }
        case 'FLOOR': case 'CEIL': {
            const entry = verb === 'FLOOR' ? entries.findLast(entry => entry.key <= first) : entries.find(entry => entry.key >= first);
            output.push(`${verb} ${first} ${entry === undefined ? 'NONE' : entryText(entry)}`);
            break;
        }
        case 'RANK':
            output.push(`RANK ${first} ${entries.filter(entry => entry.key < first).length}`);
            break;
        case 'SELECT':
            output.push(`SELECT ${first} ${entryText(entries[first - 1])}`);
            break;
        case 'SEEK': {
            const entry = entries.find(entry => entry.key >= first);
            this.cursor = entry === undefined ? 'END' : entry.key;
            output.push(`SEEK ${first} ${entry === undefined ? 'END' : entryText(entry)}`);
            break;
        }
        case 'NEXT': case 'PREV': {
            let entry: Entry | undefined;
            const cursor = this.cursor;
            if (verb === 'NEXT') {
                if (cursor === 'BEGIN') entry = entries[0];
                else if (typeof cursor === 'number') entry = entries.find(entry => entry.key > cursor);
                this.cursor = entry === undefined ? 'END' : entry.key;
            } else {
                if (cursor === 'END') entry = entries.at(-1);
                else if (typeof cursor === 'number') entry = entries.findLast(entry => entry.key < cursor);
                this.cursor = entry === undefined ? 'BEGIN' : entry.key;
            }
            output.push(`${verb} ${entry === undefined ? this.cursor : entryText(entry)}`);
            break;
        }
        case 'PRINT': {
            let level = [tree.root], depth = 0;
            while (level.length > 0) {
                output.push(`LEVEL ${depth++} ${level.map(node => node.notation()).join(' ')}`);
                level = level.flatMap(node => node.children);
            }
            break;
        }
        case 'PAGES':
            for (const node of tree.nodes().sort((left, right) => left.page - right.page)) {
                output.push(`PAGE ${node.page} ${node.notation()} kids=${node.leaf ? '-' : node.children.map(child => child.page).join(',')}`);
            }
            break;
        case 'DUMP':
            output.push(`DUMP ${tree.degree} ${tree.root.dump().join(' ')}`);
            break;
        case 'HEIGHT':
            output.push(`HEIGHT ${tree.height()}`);
            break;
        case 'STATS': {
            const nodes = tree.nodes(), leaves = nodes.filter(node => node.leaf).length;
            const fill = Math.floor(100 * entries.length / ((2 * tree.degree - 1) * nodes.length));
            output.push(`STATS t=${tree.degree} nodes=${nodes.length} leaves=${leaves} keys=${entries.length} fill=${fill}% splits=${tree.splits} merges=${tree.merges} borrows=${tree.borrows}`);
            break;
        }
        case 'VERIFY': {
            const violation = tree.violation();
            output.push(violation === null ? 'VERIFY OK' : `VERIFY FAIL ${violation}`);
            break;
        }
        case 'REBUILD': {
            this.tree = new Tree(tree.degree);
            for (const entry of entries) this.tree.upsert(entry.key, entry.value);
            output.push(`REBUILD entries=${entries.length} keys=${this.tree.entries().length} nodes=${this.tree.nodes().length} splits=${this.tree.splits} height=${this.tree.height()}`);
            break;
        }
        case 'COMPACT': {
            const nodes = tree.nodes().length;
            tree.compact();
            output.push(`COMPACT nodes=${nodes}->${tree.nodes().length} height=${tree.height()}`);
            break;
        }
        case 'SAVE':
            this.saved = tree.clone(); output.push(this.summary('SAVE', tree));
            break;
        case 'RESTORE': {
            if (this.saved === null) fail('NO SAVE');
            this.tree = this.saved.clone(); output.push(this.summary('RESTORE', this.tree));
            break;
        }
        }
        return output;
    }
}

const lines = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const workbench = new Workbench();
const output: string[] = [];
for (let index = 1; index <= Number(lines[0]); ++index) {
    try { output.push(...workbench.command(lines[index])); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        output.push(`ERROR ${error.message}`);
    }
}
process.stdout.write(output.join('\n') + '\n');
