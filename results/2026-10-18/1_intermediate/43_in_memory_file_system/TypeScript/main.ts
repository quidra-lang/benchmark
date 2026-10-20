import { readFileSync } from 'node:fs';

type Node = Directory | File | Link;
type Target = Directory | File;
type Output = (line: string) => void;
type Resolution<T extends Node = Node> =
    | { node: T; parent?: never; name?: never; reason?: never }
    | { node?: never; parent: Directory; name: string; reason: string }
    | { node?: never; parent?: never; name?: never; reason: string };
type Creation =
    | [kind: 'd', parent: Directory, name: string]
    | [kind: 'f', parent: Directory, name: string, content?: readonly string[]]
    | [kind: 'l', parent: Directory, name: string, content: string];
interface ParsedOptions { flags: Set<string>; paths: string[] }
interface Visit { node: Node; path: string; depth: number }
interface Input { lines: readonly string[]; name: string | null }

const compare = (left: string, right: string): number => left < right ? -1 : left > right ? 1 : 0;
const join = (path: string, name: string): string => path === '/' ? `/${name}` : `${path}/${name}`;
const lastComponent = (path: string): string => path.slice(path.lastIndexOf('/') + 1);
const missing = 'No such file or directory';
const notDirectory = 'Not a directory';

abstract class NodeBase {
    readonly inode: number;
    modified: number;
    parent!: Directory; // Assigned by add; the root is its own parent.
    name = '';
    abstract readonly kind: 'd' | 'f' | 'l';
    abstract get size(): number;
    constructor(inode: number, modified: number) {
        this.inode = inode; this.modified = modified;
    }
    get links(): number { return 1; }
}
class Directory extends NodeBase {
    readonly kind = 'd';
    readonly entries = new Map<string, Node>();
    get size(): number { return this.entries.size; }
    get links(): number { return 2 + [...this.entries.values()].filter(node => node.kind === 'd').length; }
}
class File extends NodeBase {
    readonly kind = 'f';
    lines: string[];
    constructor(inode: number, modified: number, lines: readonly string[] = []) { super(inode, modified); this.lines = lines.slice(); }
    get size(): number { return this.lines.reduce((sum, line) => sum + line.length + 1, 0); }
}
class Link extends NodeBase {
    readonly kind = 'l';
    readonly target: string;
    constructor(inode: number, modified: number, target: string) { super(inode, modified); this.target = target; }
    get size(): number { return this.target.length; }
}
class ResolutionError extends Error {
    readonly parent: Directory | null;
    readonly creationName: string | null;
    constructor(reason: string, parent: Directory | null = null, creationName: string | null = null) {
        super(reason); this.parent = parent; this.creationName = creationName;
    }
}
function options(arguments_: readonly string[]): ParsedOptions {
    const flags = new Set<string>();
    let count = 0;
    while (count < arguments_.length && arguments_[count].startsWith('-')) {
        for (const flag of arguments_[count].slice(1)) flags.add(flag);
        count++;
    }
    return { flags, paths: arguments_.slice(count) };
}
function entries(node: Directory, hidden = true): [string, Node][] {
    return [...node.entries].filter(([name]) => hidden || !name.startsWith('.')).sort(([a], [b]) => compare(a, b));
}
function globMatches(pattern: string, name: string): boolean {
    let previous = Array<boolean>(name.length + 1).fill(false);
    previous[0] = true;
    for (const character of pattern) {
        const current = Array<boolean>(name.length + 1).fill(false);
        if (character === '*') {
            current[0] = previous[0];
            for (let index = 1; index <= name.length; index++) current[index] = previous[index] || current[index - 1];
        } else {
            for (let index = 0; index < name.length; index++) current[index + 1] = previous[index] && (character === '?' || character === name[index]);
        }
        previous = current;
    }
    return previous[name.length];
}

class Shell {
    readonly root: Directory;
    cwd: Directory;
    previous: string | null = null;
    clock = 0;
    nextInode = 2;
    readonly terminal: Output;
    constructor(terminal: Output) {
        this.root = new Directory(1, 0);
        this.root.parent = this.root;
        this.cwd = this.root;
        this.terminal = terminal;
    }
    absolute(node: Node): string {
        const names: string[] = [];
        while (node !== this.root) { names.push(node.name); node = node.parent; }
        return '/' + names.reverse().join('/');
    }
    descendant(node: Node, ancestor: Node): boolean {
        while (true) {
            if (node === ancestor) return true;
            if (node === this.root) return false;
            node = node.parent;
        }
    }
    add(parent: Directory, name: string, node: Node): void {
        parent.entries.set(name, node);
        parent.modified = this.clock;
        node.parent = parent; node.name = name;
    }
    create(kind: 'd', parent: Directory, name: string): Directory;
    create(kind: 'f', parent: Directory, name: string, content?: readonly string[]): File;
    create(kind: 'l', parent: Directory, name: string, content: string): Link;
    create(...arguments_: Creation): Node {
        const [kind, parent, name, content] = arguments_;
        const inode = this.nextInode++;
        const node = kind === 'd' ? new Directory(inode, this.clock)
            : kind === 'f' ? new File(inode, this.clock, content ?? []) : new Link(inode, this.clock, content);
        this.add(parent, name, node);
        return node;
    }
    detach(node: Node): void { node.parent.entries.delete(node.name); node.parent.modified = this.clock; }
    write(node: File, lines: readonly string[], append = false): void {
        node.lines = append ? node.lines.concat(lines) : lines.slice();
        node.modified = this.clock;
    }
    resolve(path: string, follow?: true, makeParents?: boolean): Resolution<Target>;
    resolve(path: string, follow: false, makeParents?: boolean): Resolution;
    resolve(path: string, follow: boolean, makeParents?: boolean): Resolution;
    resolve(path: string, follow = true, makeParents = false): Resolution {
        let expansions = 0;
        const walk = (text: string, base: Directory, finalLink: boolean, original: boolean): Node => {
            let node: Node = text.startsWith('/') ? this.root : base;
            const components = text.split('/').filter(Boolean);
            for (let index = 0; index < components.length; index++) {
                if (node.kind !== 'd') throw new ResolutionError(notDirectory);
                const name = components[index];
                if (name === '.') continue;
                if (name === '..') { node = node.parent; continue; }
                let child: Node | undefined = node.entries.get(name);
                if (!child) {
                    if (original && makeParents && index + 1 < components.length) child = this.create('d', node, name);
                    else throw new ResolutionError(missing, original && index + 1 === components.length ? node : null, name);
                }
                if (child.kind === 'l' && (index + 1 < components.length || finalLink)) {
                    if (++expansions > 8) throw new ResolutionError('Too many levels of symbolic links');
                    child = walk(child.target, node, true, false);
                }
                node = child;
            }
            return node;
        };
        try { return { node: walk(path, this.cwd, follow, true) }; }
        catch (error) {
            if (!(error instanceof ResolutionError)) throw error;
            return error.parent !== null && error.creationName !== null
                ? { reason: error.message, parent: error.parent, name: error.creationName }
                : { reason: error.message };
        }
    }
    clone(source: Node, parent: Directory, name: string): Node {
        if (source.kind === 'd') {
            const copy = this.create('d', parent, name);
            for (const [childName, child] of entries(source)) this.clone(child, copy, childName);
            return copy;
        }
        return source.kind === 'f' ? this.create('f', parent, name, source.lines) : this.create('l', parent, name, source.target);
    }
    *walk(node: Node, path: string, depth = 0, limit = Infinity): Generator<Visit, void, unknown> {
        yield { node, path, depth };
        if (node.kind === 'd' && depth < limit) {
            for (const [name, child] of entries(node)) yield* this.walk(child, join(path, name), depth + 1, limit);
        }
    }
    *inputs(command: string, paths: readonly string[], input: readonly string[]): Generator<Input, void, unknown> {
        if (paths.length === 0) { yield { lines: input, name: null }; return; }
        for (const path of paths) {
            const found = this.resolve(path);
            if (!found.node) this.terminal(`${command}: ${path}: ${found.reason}`);
            else if (found.node.kind === 'd') this.terminal(`${command}: ${path}: Is a directory`);
            else yield { lines: found.node.lines, name: path };
        }
    }
    move(paths: readonly string[]): void {
        const destination = paths.at(-1)!, sources = paths.slice(0, -1);
        if (sources.length > 1 && this.resolve(destination).node?.kind !== 'd') {
            this.terminal(`mv: target '${destination}' is not a directory`); return;
        }
        for (const sourcePath of sources) {
            const basename = lastComponent(sourcePath);
            const problem = (target: string, reason: string): void => this.terminal(`mv: cannot move '${sourcePath}' to '${target}': ${reason}`);
            if (['', '.', '..'].includes(basename)) { problem(destination, 'Invalid argument'); continue; }
            const sourceResult = this.resolve(sourcePath, false);
            if (!sourceResult.node) { this.terminal(`mv: cannot stat '${sourcePath}': ${sourceResult.reason}`); continue; }
            const source = sourceResult.node, targetResult = this.resolve(destination);
            let parent: Directory, name: string, target: string;
            if (targetResult.node?.kind === 'd') {
                parent = targetResult.node; name = basename; target = join(destination, name);
            } else {
                const result = this.resolve(destination, false);
                if (result.node) { parent = result.node.parent; name = result.node.name; }
                else if (result.parent) { parent = result.parent; name = result.name; }
                else { problem(destination, result.reason); continue; }
                target = destination;
            }
            const existing = parent.entries.get(name);
            if (source.kind === 'd' && this.descendant(parent, source)) {
                this.terminal(`mv: cannot move '${sourcePath}' to a subdirectory of itself, '${target}'`);
            } else if (existing === source) {
                this.terminal(`mv: '${sourcePath}' and '${target}' are the same file`);
            } else if (existing && source.kind === 'd' && existing.kind !== 'd') {
                this.terminal(`mv: cannot overwrite non-directory '${target}' with directory '${sourcePath}'`);
            } else if (existing?.kind === 'd' && source.kind !== 'd') {
                this.terminal(`mv: cannot overwrite directory '${target}' with non-directory '${sourcePath}'`);
            } else if (existing?.kind === 'd' && existing.entries.size > 0) {
                problem(target, 'Directory not empty');
            } else if (existing === this.cwd) {
                problem(target, 'Device or resource busy');
            } else {
                if (existing) this.detach(existing);
                this.detach(source); this.add(parent, name, source);
            }
        }
    }
    copy(flags: ReadonlySet<string>, paths: readonly string[]): void {
        const destination = paths.at(-1)!, sources = paths.slice(0, -1);
        if (sources.length > 1 && this.resolve(destination).node?.kind !== 'd') {
            this.terminal(`cp: target '${destination}' is not a directory`); return;
        }
        for (const sourcePath of sources) {
            const basename = lastComponent(sourcePath);
            const problem = (target: string, reason: string): void => this.terminal(`cp: cannot copy '${sourcePath}' to '${target}': ${reason}`);
            if (['', '.', '..'].includes(basename)) { problem(destination, 'Invalid argument'); continue; }
            const sourceResult = this.resolve(sourcePath);
            if (!sourceResult.node) { this.terminal(`cp: cannot stat '${sourcePath}': ${sourceResult.reason}`); continue; }
            const source = sourceResult.node;
            if (source.kind === 'd' && !flags.has('r')) { this.terminal(`cp: -r not specified; omitting directory '${sourcePath}'`); continue; }
            const destinationResult = this.resolve(destination);
            if (!destinationResult.node && !destinationResult.parent) { problem(destination, destinationResult.reason); continue; }
            const target = destinationResult.node?.kind === 'd' ? join(destination, basename) : destination;
            if (source.kind === 'd') {
                const result = this.resolve(target, false);
                if (result.node) problem(target, 'File exists');
                else if (!result.parent) problem(target, result.reason);
                else if (this.descendant(result.parent, source)) this.terminal(`cp: cannot copy a directory, '${sourcePath}', into itself, '${target}'`);
                else this.clone(source, result.parent, result.name);
            } else {
                const result = this.resolve(target);
                if (result.parent) this.create('f', result.parent, result.name, source.lines);
                else if (!result.node) problem(target, result.reason);
                else if (result.node === source) this.terminal(`cp: '${sourcePath}' and '${target}' are the same file`);
                else if (result.node.kind === 'd') this.terminal(`cp: cannot overwrite directory '${target}' with non-directory '${sourcePath}'`);
                else this.write(result.node, source.lines);
            }
        }
    }
    listing(flags: ReadonlySet<string>, paths: readonly string[], output: Output): void {
        if (paths.length === 0) paths = ['.'];
        for (const path of paths) {
            const result = this.resolve(path, !flags.has('l'));
            if (!result.node) { this.terminal(`ls: cannot access '${path}': ${result.reason}`); continue; }
            const node = result.node;
            let list: [string, Node][];
            if (node.kind !== 'd') list = [[path, node]];
            else {
                if (paths.length > 1) output(`${path}:`);
                list = entries(node, flags.has('a'));
                if (flags.has('a')) list.unshift(['.', node], ['..', node.parent]);
                if (flags.has('t')) list.sort((left, right) => right[1].modified - left[1].modified);
                if (flags.has('r')) list.reverse();
            }
            const columns = ['links', 'size', 'modified'] as const;
            const widths = columns.map(key => Math.max(0, ...list.map(([, item]) => String(item[key]).length)));
            for (const [name, item] of list) {
                if (!flags.has('l')) output(name);
                else {
                    const values = columns.map((key, index) => String(item[key]).padStart(widths[index]));
                    output(`${item.kind === 'f' ? '-' : item.kind} ${values.join(' ')} ${name}` + (item.kind === 'l' ? ` -> ${item.target}` : ''));
                }
            }
        }
    }
    execute(text: string, input: readonly string[], output: Output): void {
        const space = text.indexOf(' ');
        const command = space < 0 ? text : text.slice(0, space);
        const arguments_ = space < 0 ? [] : text.slice(space + 1).split(' ');
        const { flags, paths } = options(arguments_);
        switch (command) {
            case 'pwd': output(this.absolute(this.cwd)); break;
            case 'echo': output(text.slice(space + 1)); break;
            case 'cd': {
                const previous = arguments_[0] === '-';
                const path = previous ? this.previous : arguments_[0] ?? '/';
                if (path === null) { this.terminal('cd: OLDPWD not set'); break; }
                const result = this.resolve(path);
                if (!result.node) this.terminal(`cd: ${path}: ${result.reason}`);
                else if (result.node.kind !== 'd') this.terminal(`cd: ${path}: Not a directory`);
                else {
                    this.previous = this.absolute(this.cwd); this.cwd = result.node;
                    if (previous) output(this.absolute(this.cwd));
                }
                break;
            }
            case 'mkdir':
                for (const path of paths) {
                    const result = this.resolve(path, false, flags.has('p'));
                    if (result.parent) this.create('d', result.parent, result.name);
                    else if (!result.node) this.terminal(`mkdir: cannot create directory '${path}': ${result.reason}`);
                    else if (!flags.has('p') || this.resolve(path).node?.kind !== 'd') this.terminal(`mkdir: cannot create directory '${path}': File exists`);
                }
                break;
            case 'touch':
                for (const path of arguments_) {
                    const result = this.resolve(path);
                    if (result.parent) this.create('f', result.parent, result.name);
                    else if (result.node) result.node.modified = this.clock;
                    else this.terminal(`touch: cannot touch '${path}': ${result.reason}`);
                }
                break;
            case 'ls': this.listing(flags, paths, output); break;
            case 'stat':
                for (const path of arguments_) {
                    const result = this.resolve(path, false), node = result.node;
                    if (!node) this.terminal(`stat: cannot stat '${path}': ${result.reason}`);
                    else {
                        const kind = node.kind === 'd' ? 'directory' : node.kind === 'l' ? 'symbolic link'
                            : node.lines.length === 0 ? 'regular empty file' : 'regular file';
                        output(`${path}: ${kind}, size ${node.size}, inode ${node.inode}, links ${node.links}, modified ${node.modified}`);
                    }
                }
                break;
            case 'rm':
                for (const path of paths) {
                    const problem = (reason: string): void => this.terminal(`rm: cannot remove '${path}': ${reason}`);
                    if (['.', '..'].includes(lastComponent(path))) {
                        this.terminal(`rm: refusing to remove '.' or '..' directory: skipping '${path}'`); continue;
                    }
                    const result = this.resolve(path, false);
                    if (!result.node) { if (!(flags.has('f') && result.reason === missing)) problem(result.reason); }
                    else if (result.node.kind === 'd' && !flags.has('r')) problem('Is a directory');
                    else if (this.descendant(this.cwd, result.node)) problem('Device or resource busy');
                    else this.detach(result.node);
                }
                break;
            case 'rmdir':
                for (const path of arguments_) {
                    const problem = (reason: string): void => this.terminal(`rmdir: failed to remove '${path}': ${reason}`);
                    if (['.', '..'].includes(lastComponent(path))) { problem('Invalid argument'); continue; }
                    const result = this.resolve(path, false);
                    if (!result.node) problem(result.reason);
                    else if (result.node.kind !== 'd') problem(notDirectory);
                    else if (this.descendant(this.cwd, result.node)) problem('Device or resource busy');
                    else if (result.node.entries.size > 0) problem('Directory not empty');
                    else this.detach(result.node);
                }
                break;
            case 'mv': this.move(arguments_); break;
            case 'cp': this.copy(flags, paths); break;
            case 'ln': {
                const [target, path] = arguments_.slice(1), result = this.resolve(path, false);
                if (result.parent) this.create('l', result.parent, result.name, target);
                else this.terminal(`ln: failed to create symbolic link '${path}': ${result.node ? 'File exists' : result.reason}`);
                break;
            }
            case 'readlink':
            case 'realpath': {
                const path = arguments_[0], result = this.resolve(path, command === 'realpath');
                if (!result.node) this.terminal(`${command}: ${path}: ${result.reason}`);
                else if (command === 'realpath') output(this.absolute(result.node));
                else if (result.node.kind === 'l') output(result.node.target);
                else this.terminal(`readlink: ${path}: Invalid argument`);
                break;
            }
            case 'find': this.find(arguments_, output); break;
            case 'du': this.diskUsage(flags, paths, output); break;
            case 'tree': this.tree(flags, paths[0] ?? '.', output); break;
            case 'cat': case 'wc': case 'head': case 'tail': case 'grep': case 'sort': case 'uniq':
                this.textCommand(command, arguments_, input, output); break;
            default: this.terminal(`${command}: command not found`);
        }
    }
    find(arguments_: readonly string[], output: Output): void {
        const path = arguments_.length && !arguments_[0].startsWith('-') ? arguments_[0] : '.';
        const tests = new Map<string, string>();
        for (let index = arguments_[0] === path ? 1 : 0; index < arguments_.length; index += 2) tests.set(arguments_[index], arguments_[index + 1]);
        const result = this.resolve(path);
        if (!result.node) { this.terminal(`find: '${path}': ${result.reason}`); return; }
        for (const item of this.walk(result.node, path, 0, tests.has('-maxdepth') ? Number(tests.get('-maxdepth')) : Infinity)) {
            const name = item.depth === 0 ? (path === '/' ? '/' : lastComponent(path)) : item.node.name;
            const pattern = tests.get('-name');
            if (pattern !== undefined && !globMatches(pattern, name)) continue;
            if (tests.has('-type') && tests.get('-type') !== item.node.kind) continue;
            output(item.path);
        }
    }
    diskUsage(flags: ReadonlySet<string>, paths: readonly string[], output: Output): void {
        if (paths.length === 0) paths = ['.'];
        const report = (node: Node, path: string, show: boolean): number => {
            let usage = node.kind === 'd' ? 0 : node.size;
            if (node.kind === 'd') {
                for (const [name, child] of entries(node)) usage += report(child, join(path, name), show && !flags.has('s') && (child.kind === 'd' || flags.has('a')));
            }
            if (show) output(`${usage} ${path}`);
            return usage;
        };
        for (const path of paths) {
            const result = this.resolve(path);
            if (!result.node) this.terminal(`du: cannot access '${path}': ${result.reason}`);
            else report(result.node, path, true);
        }
    }
    tree(flags: ReadonlySet<string>, path: string, output: Output): void {
        const result = this.resolve(path);
        if (!result.node) { this.terminal(`tree: ${path}: ${result.reason}`); return; }
        if (result.node.kind !== 'd') { this.terminal(`tree: ${path}: Not a directory`); return; }
        let directories = 0, files = 0;
        const draw = (node: Directory, prefix: string): void => {
            const list = entries(node, flags.has('a'));
            list.forEach(([name, child], index) => {
                const last = index + 1 === list.length;
                output(prefix + (last ? '`-- ' : '|-- ') + name + (child.kind === 'l' ? ` -> ${child.target}` : ''));
                if (child.kind === 'd') { directories++; draw(child, prefix + (last ? '    ' : '|   ')); }
                else files++;
            });
        };
        output(path); draw(result.node, '');
        output(`${directories} ${directories === 1 ? 'directory' : 'directories'}, ${files} ${files === 1 ? 'file' : 'files'}`);
    }
    *grepInputs(paths: readonly string[], input: readonly string[], recursive: boolean): Generator<Input, void, unknown> {
        if (!recursive) { yield* this.inputs('grep', paths, input); return; }
        if (paths.length === 0) paths = ['.'];
        for (const path of paths) {
            const result = this.resolve(path);
            if (!result.node) { this.terminal(`grep: ${path}: ${result.reason}`); continue; }
            for (const item of this.walk(result.node, path)) if (item.node.kind === 'f') yield { lines: item.node.lines, name: item.path };
        }
    }
    textCommand(command: string, arguments_: readonly string[], input: readonly string[], output: Output): void {
        const parsed = options(arguments_);
        const flags = parsed.flags;
        let paths: readonly string[] = parsed.paths;
        if (command === 'grep') {
            const pattern = flags.has('i') ? paths[0].toLowerCase() : paths[0];
            paths = paths.slice(1);
            for (const item of this.grepInputs(paths, input, flags.has('r'))) {
                const prefix = paths.length > 1 || flags.has('r') ? `${item.name}:` : '';
                let count = 0;
                item.lines.forEach((line, index) => {
                    const match = (flags.has('i') ? line.toLowerCase() : line).includes(pattern);
                    if (match !== flags.has('v')) {
                        count++;
                        if (!flags.has('c')) output(prefix + (flags.has('n') ? `${index + 1}:` : '') + line);
                    }
                });
                if (flags.has('c')) output(prefix + count);
            }
            return;
        }
        let countText = '10';
        if (command === 'head' || command === 'tail') {
            countText = arguments_[0] === '-n' ? arguments_[1] : '10';
            paths = arguments_[0] === '-n' ? arguments_.slice(2) : arguments_;
        }
        if (command === 'sort') {
            const lines: string[] = [];
            for (const item of this.inputs(command, paths, input)) {
                for (const line of item.lines) lines.push(line);
            }
            const numeric = (line: string): number => Number(line.match(/^-?[0-9]+/)?.[0] ?? 0);
            lines.sort((left, right) => (flags.has('n') ? numeric(left) - numeric(right) : 0) || compare(left, right));
            if (flags.has('r')) lines.reverse();
            lines.forEach(output);
            return;
        }
        const totals = [0, 0, 0];
        const selected = ['l', 'w', 'c'].map(letter => flags.size === 0 || flags.has(letter));
        const countsLine = (counts: readonly number[], name: string | null): string => counts.filter((_, index) => selected[index]).join(' ') + (name === null ? '' : ` ${name}`);
        for (const { lines, name } of this.inputs(command, paths, input)) {
            if (command === 'cat') lines.forEach(output);
            else if (command === 'wc') {
                const counts = [lines.length, lines.reduce((sum, line) => sum + (line.match(/[^ ]+/g)?.length ?? 0), 0), lines.reduce((sum, line) => sum + line.length + 1, 0)];
                counts.forEach((count, index) => { totals[index] += count; });
                output(countsLine(counts, name));
            } else if (command === 'head' || command === 'tail') {
                const count = Math.abs(Number(countText));
                let part: readonly string[];
                if (command === 'head') part = lines.slice(0, countText.startsWith('-') ? Math.max(0, lines.length - count) : count);
                else part = lines.slice(countText.startsWith('+') ? Math.max(0, count - 1) : Math.max(0, lines.length - count));
                part.forEach(output);
            } else {
                for (let first = 0; first < lines.length;) {
                    let end = first + 1;
                    while (end < lines.length && lines[end] === lines[first]) end++;
                    output((flags.has('c') ? `${end - first} ` : '') + lines[first]);
                    first = end;
                }
            }
        }
        if (command === 'wc' && paths.length > 1) output(countsLine(totals, 'total'));
    }
    process(line: string): void {
        this.clock++;
        this.terminal(`${this.absolute(this.cwd)}$ ${line}`);
        const redirect = line.match(/ (>>|>) ([^ ]+)$/);
        const pipeline = (redirect ? line.slice(0, redirect.index) : line).split(' | ');
        let redirectFile: File | null = null;
        if (redirect) {
            const path = redirect[2], result = this.resolve(path);
            if (result.parent) redirectFile = this.create('f', result.parent, result.name);
            else if (!result.node) { this.terminal(`sh: ${path}: ${result.reason}`); return; }
            else if (result.node.kind === 'd') { this.terminal(`sh: ${path}: Is a directory`); return; }
            else {
                redirectFile = result.node;
                if (redirect[1] === '>') this.write(redirectFile, []);
            }
        }
        let input: string[] = [];
        pipeline.forEach((command, index) => {
            const output: string[] = [];
            this.execute(command, input, line => {
                if (!redirectFile && index + 1 === pipeline.length) this.terminal(line);
                else output.push(line);
            });
            input = output;
        });
        if (redirectFile && input.length) this.write(redirectFile, input, true);
    }
}

const shell = new Shell(line => process.stdout.write(line + '\n'));
for (const line of readFileSync(0, 'utf8').split('\n')) {
    if (line === 'exit') break;
    shell.process(line);
}
