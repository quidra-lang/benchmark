import { readFileSync } from 'node:fs';

const modes = ['CHAIN', 'LINEAR', 'QUADRATIC', 'DOUBLE', 'ROBINHOOD', 'CUCKOO'] as const;
type Mode = typeof modes[number];
type ProbingMode = 'LINEAR' | 'QUADRATIC' | 'DOUBLE';
type Command = { readonly kind: 'CREATE'; readonly mode: string; readonly capacity: number }
    | { readonly kind: 'MAXLOAD' | 'MINLOAD'; readonly value: number }
    | { readonly kind: 'TRACE'; readonly flag: string }
    | { readonly kind: 'HASH'; readonly key: string; readonly capacity: number }
    | { readonly kind: 'PUT' | 'ADD'; readonly key: string; readonly value: number }
    | { readonly kind: 'GET' | 'DEL' | 'PROBE'; readonly key: string }
    | { readonly kind: 'GEN' | 'GENDEL'; readonly count: number; readonly length: number; readonly seed: number }
    | { readonly kind: 'RESIZE' | 'COMPARE'; readonly capacity: number }
    | { readonly kind: 'CONVERT'; readonly mode: string }
    | { readonly kind: 'TOP'; readonly limit: number }
    | { readonly kind: 'SCAN'; readonly cursor: number; readonly limit: number }
    | { readonly kind: 'BENCH'; readonly capacity: number; readonly count: number; readonly length: number; readonly seed: number }
    | { readonly kind: 'CLEAR' | 'DUMP' | 'MAP' | 'STATS' | 'KEYS' | 'CLUSTERS' | 'DIST' };
interface Item { readonly key: string; readonly value: number }
const tombstone = Symbol('tombstone');
type Slot = Item | typeof tombstone | null;
type Layout = { readonly mode: 'CHAIN'; readonly buckets: Item[][] }
    | { readonly mode: ProbingMode; readonly slots: Slot[] }
    | { readonly mode: 'ROBINHOOD' | 'CUCKOO'; readonly slots: (Item | null)[] };
interface Counters {
    probes: number; rehashes: number; inserts: number; updates: number;
    hits: number; misses: number; deletes: number; absent: number;
}
interface Hit { readonly item: Item; readonly position: number; readonly chainIndex: number | null }
interface Search {
    readonly hit: Hit | null;
    readonly probes: number;
    readonly available: number | null;
    readonly path: readonly string[];
}
type Placement = { readonly success: true; readonly position: number; readonly reused: boolean;
                  readonly shifted: number; readonly kicks: number; readonly moves: readonly string[] }
    | { readonly success: false; readonly homeless: Item; readonly kicks: number; readonly moves: readonly string[] };
interface Removal { readonly shifted: number; readonly moves: readonly string[] }
interface Mutation { readonly changed: boolean; readonly rehashes: readonly string[]; readonly rows: readonly string[] }
interface Cost { readonly key: string; readonly cost: number; readonly position: string }
interface Metrics { readonly longest: number; readonly average: string }

class CommandError extends Error {}
function fail(message: string): never { throw new CommandError(message); }
const ascii = (a: string, b: string): number => a < b ? -1 : a > b ? 1 : 0;
const isItem = (slot: Slot): slot is Item => slot !== null && slot !== tombstone;
const content = (slot: Slot): string => slot === null ? '-' : slot === tombstone ? 'D' : slot.key;
const pairText = (item: Item): string => `${item.key}=${item.value}`;
const gauge = (value: number): string => value < 10 ? String(value) : '+';
const pathLine = (search: Search): string => `PATH ${search.path.length ? search.path.join(' ') : 'none'}`;
function hash(key: string, base: number, modulus: number): number {
    let value = 0;
    for (const character of key) value = (value * base + character.charCodeAt(0)) % modulus;
    return value;
}
function prime(value: number): number {
    for (let candidate = Math.max(2, value); ; ++candidate) {
        let valid = true;
        for (let divisor = 2; divisor * divisor <= candidate; ++divisor) {
            if (candidate % divisor === 0) { valid = false; break; }
        }
        if (valid) return candidate;
    }
}
function decimal(numerator: number, denominator: number): string {
    const value = denominator === 0 ? 0 : Math.floor(100 * numerator / denominator);
    return `${Math.floor(value / 100)}.${String(value % 100).padStart(2, '0')}`;
}
function generatedKeys(count: number, length: number, seed: number): string[] {
    const keys: string[] = [];
    for (let index = 0; index < count; ++index) {
        let key = '';
        for (let place = 0; place < length; ++place) {
            seed = 48271 * seed % 2147483647;
            key += String.fromCharCode(97 + seed % 26);
        }
        keys.push(key);
    }
    return keys;
}
function histogram(values: readonly number[]): string[] {
    const counts = new Map<number, number>();
    for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
    return [...counts].sort((a, b) => a[0] - b[0]).map(([value, count]) =>
        `${value} ${count} ${'#'.repeat(Math.min(count, 50))}${count > 50 ? '+' : ''}`);
}
function runs(slots: readonly Slot[]): number[] {
    const empty = slots.indexOf(null);
    if (empty < 0) return [slots.length];
    const lengths: number[] = [];
    let length = 0;
    for (let offset = 1; offset <= slots.length; ++offset) {
        if (slots[(empty + offset) % slots.length] !== null) ++length;
        else if (length > 0) { lengths.push(length); length = 0; }
    }
    return lengths;
}
function checkCapacity(capacity: number): void {
    if (capacity < 2 || capacity > 10000) fail('BAD CAPACITY');
}
function checkedMode(word: string): Mode {
    return modes.find(mode => mode === word) ?? fail(`BAD MODE ${word}`);
}
function checkGeneration(count: number, length: number, seed: number): void {
    if (count < 1 || count > 500 || length < 1 || length > 10 || seed < 1 || seed > 2147483646) fail('BAD ARGUMENT');
}
function parseCommand(line: string): Command {
    const [kind, ...args] = line.split(' ');
    switch (kind) {
        case 'CREATE': return { kind, mode: args[0], capacity: Number(args[1]) };
        case 'MAXLOAD': case 'MINLOAD': return { kind, value: Number(args[0]) };
        case 'TRACE': return { kind, flag: args[0] };
        case 'HASH': return { kind, key: args[0], capacity: Number(args[1]) };
        case 'PUT': case 'ADD': return { kind, key: args[0], value: Number(args[1]) };
        case 'GET': case 'DEL': case 'PROBE': return { kind, key: args[0] };
        case 'GEN': case 'GENDEL': return { kind, count: Number(args[0]), length: Number(args[1]), seed: Number(args[2]) };
        case 'RESIZE': case 'COMPARE': return { kind, capacity: Number(args[0]) };
        case 'CONVERT': return { kind, mode: args[0] };
        case 'TOP': return { kind, limit: Number(args[0]) };
        case 'SCAN': return { kind, cursor: Number(args[0]), limit: Number(args[1]) };
        case 'BENCH': return { kind, capacity: Number(args[0]), count: Number(args[1]), length: Number(args[2]), seed: Number(args[3]) };
        case 'CLEAR': case 'DUMP': case 'MAP': case 'STATS': case 'KEYS': case 'CLUSTERS': case 'DIST': return { kind };
        default: return fail(`UNKNOWN COMMAND ${kind}`);
    }
}

class Table {
    private layout: Layout;
    size = 0;
    tomb = 0;
    readonly counters: Counters = { probes: 0, rehashes: 0, inserts: 0, updates: 0, hits: 0, misses: 0, deletes: 0, absent: 0 };
    constructor(mode: Mode, public cap: number) {
        if (mode === 'CHAIN') this.layout = { mode, buckets: Array.from({ length: cap }, (): Item[] => []) };
        else if (mode === 'ROBINHOOD' || mode === 'CUCKOO') {
            this.layout = { mode, slots: new Array<Item | null>(cap * (mode === 'CUCKOO' ? 2 : 1)).fill(null) };
        } else this.layout = { mode, slots: new Array<Slot>(cap).fill(null) };
    }
    get mode(): Mode { return this.layout.mode; }
    slotCount(): number { return this.cap * (this.mode === 'CUCKOO' ? 2 : 1); }
    position(index: number): string {
        return this.mode === 'CUCKOO' ? `T${Math.floor(index / this.cap) + 1}.${index % this.cap}` : String(index);
    }
    distance(key: string, position: number): number { return (position - hash(key, 31, this.cap) + this.cap) % this.cap; }
    items(): Item[] {
        const data = this.layout;
        return data.mode === 'CHAIN' ? data.buckets.flat() : data.slots.filter(isItem);
    }
    search(key: string, tracing = false): Search {
        const data = this.layout, path: string[] = [], first = hash(key, 31, this.cap);
        let probes = 0, available: number | null = null;
        const result = (hit: Hit | null = null): Search => ({ hit, probes, path, available });
        const examine = (index: number, slot: Slot): void => {
            ++probes;
            if (tracing) path.push(`${this.position(index)}:${content(slot)}`);
        };
        if (data.mode === 'CHAIN') {
            const bucket = data.buckets[first];
            for (let index = 0; index < bucket.length; ++index) {
                const item = bucket[index];
                examine(first, item);
                if (item.key === key) return result({ item, position: first, chainIndex: index });
            }
            return result();
        }
        if (data.mode === 'CUCKOO') {
            for (const index of [first, this.cap + hash(key, 37, this.cap)]) {
                const item = data.slots[index];
                examine(index, item);
                if (item !== null && item.key === key) return result({ item, position: index, chainIndex: null });
            }
            return result();
        }
        const step = data.mode === 'DOUBLE' ? 1 + hash(key, 37, this.cap - 1) : 1;
        for (let offset = 0; offset < this.cap; ++offset) {
            const index = (first + (data.mode === 'QUADRATIC' ? offset * offset : offset * step)) % this.cap;
            const slot = data.slots[index];
            examine(index, slot);
            if (slot === null) { if (available === null) available = index; return result(); }
            if (slot === tombstone) { if (available === null) available = index; continue; }
            if (slot.key === key) return result({ item: slot, position: index, chainIndex: null });
            if (data.mode === 'ROBINHOOD' && this.distance(slot.key, index) < offset) return result();
        }
        return result();
    }
    place(item: Item, initial: Search | null = null, tracing = false): Placement {
        const data = this.layout, moves: string[] = [];
        const succeed = (position: number, reused = false, shifted = 0, kicks = 0): Placement =>
            ({ success: true, position, reused, shifted, kicks, moves });
        const reject = (homeless: Item, kicks = 0): Placement => ({ success: false, homeless, kicks, moves });
        if (data.mode === 'CHAIN') {
            const index = hash(item.key, 31, this.cap);
            data.buckets[index].push(item);
            return succeed(index);
        }
        if (data.mode === 'LINEAR' || data.mode === 'QUADRATIC' || data.mode === 'DOUBLE') {
            const search = initial ?? this.search(item.key), index = search.available;
            if (index === null) return reject(item);
            const reused = data.slots[index] === tombstone;
            data.slots[index] = item;
            if (reused) --this.tomb;
            return succeed(index, reused);
        }
        if (data.mode === 'ROBINHOOD') {
            let current = item, position = hash(item.key, 31, this.cap), distance = 0, shifted = 0;
            let from: number | null = null, original: number | null = null;
            for (;;) {
                const occupant = data.slots[position];
                if (occupant === null) {
                    data.slots[position] = current;
                    if (tracing && from !== null) moves.push(`SHIFT ${current.key} ${from} -> ${position}`);
                    return succeed(original ?? position, false, shifted);
                }
                const otherDistance = this.distance(occupant.key, position);
                if (otherDistance < distance) {
                    data.slots[position] = current;
                    if (tracing && from !== null) moves.push(`SHIFT ${current.key} ${from} -> ${position}`);
                    original ??= position;
                    current = occupant;
                    from = position;
                    distance = otherDistance;
                    ++shifted;
                }
                position = (position + 1) % this.cap;
                ++distance;
            }
        }
        let current = item, part = 0, kicks = 0;
        for (;;) {
            const index = part * this.cap + hash(current.key, part === 0 ? 31 : 37, this.cap);
            const occupant = data.slots[index];
            if (occupant === null) {
                data.slots[index] = current;
                return succeed(this.search(item.key).hit!.position, false, 0, kicks);
            }
            if (kicks === this.cap) return reject(current, kicks);
            data.slots[index] = current;
            ++kicks;
            if (tracing) moves.push(`KICK ${occupant.key} ${this.position(index)}`);
            current = occupant;
            part = 1 - part;
        }
    }
    remove(hit: Hit, tracing: boolean): Removal {
        const data = this.layout, moves: string[] = [];
        let shifted = 0;
        if (data.mode === 'CHAIN') data.buckets[hit.position].splice(hit.chainIndex!, 1);
        else if (data.mode === 'LINEAR' || data.mode === 'QUADRATIC' || data.mode === 'DOUBLE') {
            data.slots[hit.position] = tombstone;
            ++this.tomb;
        } else {
            data.slots[hit.position] = null;
            if (data.mode === 'ROBINHOOD') {
                let next = (hit.position + 1) % this.cap;
                for (;;) {
                    const item = data.slots[next];
                    if (item === null || this.distance(item.key, next) === 0) break;
                    const destination = (next - 1 + this.cap) % this.cap;
                    data.slots[destination] = item;
                    data.slots[next] = null;
                    if (tracing) moves.push(`SHIFT ${item.key} ${next} -> ${destination}`);
                    ++shifted;
                    next = (next + 1) % this.cap;
                }
            }
        }
        --this.size;
        return { shifted, moves };
    }
    static rebuild(items: readonly Item[], mode: Mode, capacity: number): Table | null {
        const table = new Table(mode, capacity);
        for (const item of items) {
            if (!table.place(item).success) return null;
            ++table.size;
        }
        return table;
    }
    adopt(table: Table): void {
        this.cap = table.cap;
        this.size = table.size;
        this.tomb = table.tomb;
        this.layout = table.layout;
    }
    automatic(reason: 'full' | 'kicks' | 'load' | 'tomb', capacity: number, pending: Item | null = null): string {
        const items = this.items(), old = this.cap;
        if (pending !== null) items.push(pending);
        for (;;) {
            const replacement = Table.rebuild(items, this.mode, capacity);
            if (replacement !== null) {
                this.adopt(replacement);
                ++this.counters.rehashes;
                return `REHASH ${reason} ${old} -> ${this.cap}`;
            }
            capacity = prime(2 * capacity);
        }
    }
    loadCheck(maxLoad: number): string[] {
        const threshold = maxLoad * this.slotCount();
        if (100 * (this.size + this.tomb) <= threshold) return [];
        const grow = 200 * this.size > threshold;
        return [this.automatic(grow ? 'load' : 'tomb', grow ? prime(2 * this.cap) : this.cap)];
    }
    shrinkCheck(minLoad: number, maxLoad: number): string[] {
        const capacity = prime(Math.floor(this.cap / 2)), slots = capacity * (this.mode === 'CUCKOO' ? 2 : 1);
        if (100 * this.size >= minLoad * this.slotCount() || capacity >= this.cap || 100 * this.size > maxLoad * slots) return [];
        const replacement = Table.rebuild(this.items(), this.mode, capacity);
        if (replacement === null) return [];
        const old = this.cap;
        this.adopt(replacement);
        ++this.counters.rehashes;
        return [`REHASH shrink ${old} -> ${capacity}`];
    }
    put(key: string, value: number, command: 'PUT' | 'ADD', maxLoad: number, tracing = false): Mutation {
        const search = this.search(key, tracing), trace = tracing ? [pathLine(search)] : [], hit = search.hit;
        this.counters.probes += search.probes;
        if (hit !== null) {
            const old = hit.item.value, next = command === 'ADD' ? old + value : value, item: Item = { key, value: next };
            const data = this.layout;
            if (data.mode === 'CHAIN') data.buckets[hit.position][hit.chainIndex!] = item;
            else data.slots[hit.position] = item;
            ++this.counters.updates;
            return { changed: false, rehashes: [], rows: [`${command} ${key}=${next} UPDATED old=${old} at=${this.position(hit.position)} probes=${search.probes}`, ...trace] };
        }
        const placed = this.place({ key, value }, search, tracing);
        ++this.size;
        ++this.counters.inserts;
        let row = `${command} ${key}=${value} NEW`;
        if (placed.success) {
            row += ` at=${this.position(placed.position)} probes=${search.probes}`;
            if (placed.reused) row += ' reused';
            if (this.mode === 'ROBINHOOD') row += ` shifted=${placed.shifted}`;
            if (this.mode === 'CUCKOO') row += ` kicks=${placed.kicks}`;
        } else row += ` probes=${search.probes}` + (this.mode === 'CUCKOO' ? ` kicks=${placed.kicks} failed` : ' full');
        const rehashes: string[] = [];
        if (!placed.success) rehashes.push(this.automatic(this.mode === 'CUCKOO' ? 'kicks' : 'full', prime(2 * this.cap), placed.homeless));
        rehashes.push(...this.loadCheck(maxLoad));
        return { changed: true, rehashes, rows: [row, ...trace, ...placed.moves, ...rehashes] };
    }
    get(key: string, tracing: boolean): string[] {
        const search = this.search(key, tracing), hit = search.hit;
        this.counters.probes += search.probes;
        let row: string;
        if (hit === null) { ++this.counters.misses; row = `GET ${key} NOT FOUND probes=${search.probes}`; }
        else { ++this.counters.hits; row = `GET ${key}=${hit.item.value} at=${this.position(hit.position)} probes=${search.probes}`; }
        return tracing ? [row, pathLine(search)] : [row];
    }
    delete(key: string, minLoad: number, maxLoad: number, tracing = false): Mutation {
        const search = this.search(key, tracing), trace = tracing ? [pathLine(search)] : [], hit = search.hit;
        this.counters.probes += search.probes;
        if (hit === null) {
            ++this.counters.absent;
            return { changed: false, rehashes: [], rows: [`DEL ${key} NOT FOUND probes=${search.probes}`, ...trace] };
        }
        const removed = this.remove(hit, tracing);
        ++this.counters.deletes;
        let row = `DEL ${key} OK at=${this.position(hit.position)} probes=${search.probes}`;
        if (this.mode === 'ROBINHOOD') row += ` shifted=${removed.shifted}`;
        const rehashes = this.shrinkCheck(minLoad, maxLoad);
        return { changed: true, rehashes, rows: [row, ...trace, ...removed.moves, ...rehashes] };
    }
    costs(): Cost[] {
        const data = this.layout, records: Cost[] = [];
        if (data.mode === 'CHAIN') {
            data.buckets.forEach((bucket, position) => bucket.forEach((item, index) =>
                records.push({ key: item.key, cost: index + 1, position: String(position) })));
        } else data.slots.forEach((item, position) => {
            if (!isItem(item)) return;
            const cost = data.mode === 'CUCKOO' ? (position < this.cap ? 1 : 2)
                : data.mode === 'ROBINHOOD' || data.mode === 'LINEAR' ? this.distance(item.key, position) + 1 : this.search(item.key).probes;
            records.push({ key: item.key, cost, position: this.position(position) });
        });
        return records;
    }
    metrics(): Metrics {
        const costs = this.costs();
        const longest = costs.reduce((value, item) => Math.max(value, item.cost), 0);
        const total = costs.reduce((value, item) => value + item.cost, 0);
        return { longest, average: decimal(total, this.size) };
    }
    dump(): string[] {
        const data = this.layout, rows = [`DUMP ${this.mode} cap=${this.cap} size=${this.size} tomb=${this.tomb}`];
        if (data.mode === 'CHAIN') data.buckets.forEach((bucket, index) => rows.push(`${index} ${bucket.length ? bucket.map(pairText).join(' ') : '-'}`));
        else data.slots.forEach((slot, index) => {
            const position = data.mode === 'CUCKOO' ? `T${Math.floor(index / this.cap) + 1} ${index % this.cap}` : String(index);
            let value = isItem(slot) ? pairText(slot) : content(slot);
            if (data.mode === 'ROBINHOOD' && isItem(slot)) value += ` d=${this.distance(slot.key, index)}`;
            rows.push(`${position} ${value}`);
        });
        return rows;
    }
    map(): string[] {
        const data = this.layout, rows = [`MAP ${this.mode} cap=${this.cap}`];
        const costs = new Map<string, number>(this.costs().map(item => [item.key, item.cost]));
        let characters: string[][];
        if (data.mode === 'CHAIN') characters = [data.buckets.map(bucket => bucket.length === 0 ? '.' : gauge(bucket.length))];
        else {
            const parts = data.mode === 'CUCKOO' ? [data.slots.slice(0, this.cap), data.slots.slice(this.cap)] : [data.slots];
            characters = parts.map(part => part.map(slot => {
                if (slot === null) return '.';
                if (slot === tombstone) return 'D';
                return data.mode === 'CUCKOO' ? '#' : gauge(costs.get(slot.key)! - 1);
            }));
        }
        characters.forEach((part, number) => {
            for (let index = 0; index < part.length; index += 40) {
                const prefix = data.mode === 'CUCKOO' ? `T${number + 1} ` : '';
                rows.push(`${prefix}${String(index).padStart(5, '0')} ${part.slice(index, index + 40).join('')}`);
            }
        });
        return rows;
    }
    statistics(): string[] {
        const { longest, average } = this.metrics(), count = this.counters;
        return [`STATS ${this.mode} size=${this.size} cap=${this.cap} slots=${this.slotCount()} tomb=${this.tomb} load=${decimal(100 * this.size, this.slotCount())}% longest=${longest} avg=${average} probes=${count.probes} rehashes=${count.rehashes}`,
            `OPS inserts=${count.inserts} updates=${count.updates} hits=${count.hits} misses=${count.misses} deletes=${count.deletes} absent=${count.absent}`];
    }
    scan(cursor: number, limit: number): string[] {
        const data = this.layout, keys: string[] = [];
        let next = cursor;
        while (next < this.slotCount() && keys.length < limit) {
            if (data.mode === 'CHAIN') {
                for (const item of data.buckets[next]) keys.push(item.key);
            } else {
                const slot = data.slots[next];
                if (isItem(slot)) keys.push(slot.key);
            }
            ++next;
        }
        if (next === this.slotCount()) next = 0;
        return [[`SCAN next=${next}`, ...keys].join(' ')];
    }
    clusters(): string[] {
        const data = this.layout;
        const lengths = data.mode === 'CHAIN' ? data.buckets.filter(bucket => bucket.length > 0).map(bucket => bucket.length)
            : data.mode === 'CUCKOO' ? [...runs(data.slots.slice(0, this.cap)), ...runs(data.slots.slice(this.cap))] : runs(data.slots);
        const longest = lengths.reduce((maximum, length) => Math.max(maximum, length), 0);
        return [`CLUSTERS runs=${lengths.length} longest=${longest}`, ...histogram(lengths)];
    }
    distribution(): string[] {
        const costs = this.costs().map(item => item.cost), longest = costs.reduce((maximum, cost) => Math.max(maximum, cost), 0);
        return [`DIST keys=${this.size} longest=${longest}`, ...histogram(costs)];
    }
}

class Simulator {
    private table: Table | null = null;
    private maxLoad = 75;
    private minLoad = 0;
    private tracing = false;
    private compare(current: Table, capacity: number): string[] {
        const items = current.items().sort((a, b) => ascii(a.key, b.key)), rows = [`COMPARE keys=${items.length} cap=${capacity}`];
        for (const mode of modes) {
            const table = new Table(mode, capacity);
            for (const item of items) table.put(item.key, item.value, 'PUT', this.maxLoad);
            const { longest, average } = table.metrics();
            rows.push(`${mode} cap=${table.cap} longest=${longest} avg=${average} probes=${table.counters.probes} rehashes=${table.counters.rehashes}`);
        }
        return rows;
    }
    private bench(capacity: number, count: number, length: number, seed: number): string[] {
        const keys = generatedKeys(2 * count, length, seed), rows = [`BENCH cap=${capacity} count=${count} len=${length} seed=${seed}`];
        for (const mode of modes) {
            const table = new Table(mode, capacity);
            for (let index = 0; index < count; ++index) table.put(keys[index], index + 1, 'PUT', this.maxLoad);
            let misses = 0, probes = 0;
            for (let index = count; index < keys.length; ++index) {
                const found = table.search(keys[index]);
                if (found.hit === null) { ++misses; probes += found.probes; }
            }
            rows.push(`${mode} cap=${table.cap} keys=${table.size} hit=${table.metrics().average} misses=${misses} miss=${decimal(probes, misses)} rehashes=${table.counters.rehashes}`);
        }
        return rows;
    }
    execute(command: Command): readonly string[] {
        switch (command.kind) {
            case 'CREATE': {
                const mode = checkedMode(command.mode);
                checkCapacity(command.capacity);
                this.table = new Table(mode, prime(command.capacity));
                return [`CREATE ${mode} cap=${this.table.cap}`];
            }
            case 'MAXLOAD': case 'MINLOAD': {
                const value = command.value, maximum = command.kind === 'MAXLOAD';
                if (maximum ? value < 10 || value > 95 : value > 40) fail('BAD LOAD');
                if (maximum) this.maxLoad = value;
                else this.minLoad = value;
                return [`${command.kind} ${value}`];
            }
            case 'TRACE': {
                if (command.flag !== 'ON' && command.flag !== 'OFF') fail('BAD ARGUMENT');
                this.tracing = command.flag === 'ON';
                return [`TRACE ${command.flag}`];
            }
            case 'HASH': {
                const { key, capacity } = command;
                checkCapacity(capacity);
                return [`HASH ${key} m=${capacity} h31=${hash(key, 31, capacity)} h37=${hash(key, 37, capacity)} step=${1 + hash(key, 37, capacity - 1)}`];
            }
            case 'BENCH': {
                const { capacity, count, length, seed } = command;
                checkCapacity(capacity);
                checkGeneration(count, length, seed);
                return this.bench(prime(capacity), count, length, seed);
            }
        }
        const table = this.table;
        if (table === null) fail('NO TABLE');
        switch (command.kind) {
            case 'PUT': case 'ADD': return table.put(command.key, command.value, command.kind, this.maxLoad, this.tracing).rows;
            case 'GET': return table.get(command.key, this.tracing);
            case 'DEL': return table.delete(command.key, this.minLoad, this.maxLoad, this.tracing).rows;
            case 'PROBE': {
                const search = table.search(command.key, true);
                return [[`PROBE ${command.key}`, ...search.path, `${search.hit === null ? 'MISS' : 'FOUND'} probes=${search.probes}`].join(' ')];
            }
            case 'GEN': case 'GENDEL': {
                const { count, length, seed } = command;
                checkGeneration(count, length, seed);
                const keys = generatedKeys(count, length, seed), rows: string[] = [];
                let successes = 0;
                keys.forEach((key, index) => {
                    const result = command.kind === 'GEN' ? table.put(key, index + 1, 'PUT', this.maxLoad)
                        : table.delete(key, this.minLoad, this.maxLoad);
                    successes += Number(result.changed);
                    rows.push(...result.rehashes);
                });
                rows.push(command.kind === 'GEN' ? `GEN ${count} new=${successes} updated=${count - successes}`
                    : `GENDEL ${count} deleted=${successes} missing=${count - successes}`);
                return rows;
            }
            case 'RESIZE': case 'CONVERT': {
                let mode = table.mode, capacity = table.cap;
                if (command.kind === 'RESIZE') { checkCapacity(command.capacity); capacity = prime(command.capacity); }
                else mode = checkedMode(command.mode);
                const slots = capacity * (mode === 'CUCKOO' ? 2 : 1);
                if (100 * table.size > this.maxLoad * slots) fail('TOO SMALL');
                const replacement = Table.rebuild(table.items(), mode, capacity);
                if (replacement === null) fail('REBUILD FAILED');
                const row = command.kind === 'RESIZE' ? `RESIZE ${table.cap} -> ${capacity}` : `CONVERT ${table.mode} -> ${mode} cap=${capacity}`;
                table.adopt(replacement);
                return [row];
            }
            case 'CLEAR': {
                const size = table.size;
                table.adopt(new Table(table.mode, table.cap));
                return [`CLEAR ${size}`];
            }
            case 'DUMP': return table.dump();
            case 'MAP': return table.map();
            case 'STATS': return table.statistics();
            case 'KEYS': return [[`KEYS ${table.size}`, ...table.items().map(item => item.key).sort(ascii)].join(' ')];
            case 'TOP': {
                if (command.limit < 1 || command.limit > 100) fail('BAD ARGUMENT');
                const items = table.costs().sort((a, b) => b.cost - a.cost || ascii(a.key, b.key)).slice(0, command.limit);
                return [`TOP ${items.length}`, ...items.map(item => `${item.key} cost=${item.cost} at=${item.position}`)];
            }
            case 'SCAN': {
                if (command.limit < 1 || command.limit > 100) fail('BAD ARGUMENT');
                if (command.cursor >= table.slotCount()) fail('BAD CURSOR');
                return table.scan(command.cursor, command.limit);
            }
            case 'CLUSTERS': return table.clusters();
            case 'DIST': return table.distribution();
            case 'COMPARE': {
                checkCapacity(command.capacity);
                return this.compare(table, prime(command.capacity));
            }
        }
        throw new Error('Unreachable command');
    }
}

const input = readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const simulator = new Simulator();
for (let index = 1; index <= Number(input[0]); ++index) {
    try { process.stdout.write(simulator.execute(parseCommand(input[index])).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
