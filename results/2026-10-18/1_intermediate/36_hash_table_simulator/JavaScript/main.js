'use strict';

const fs = require('node:fs');
const modes = ['CHAIN', 'LINEAR', 'QUADRATIC', 'DOUBLE', 'ROBINHOOD', 'CUCKOO'];
const commands = new Set(['CREATE', 'MAXLOAD', 'MINLOAD', 'TRACE', 'HASH', 'PUT', 'ADD', 'GET', 'DEL', 'PROBE', 'GEN', 'GENDEL', 'RESIZE', 'CONVERT', 'CLEAR', 'DUMP', 'MAP', 'STATS', 'KEYS', 'TOP', 'SCAN', 'CLUSTERS', 'DIST', 'COMPARE', 'BENCH']);
const tombstone = Symbol('tombstone');
class CommandError extends Error {}
const fail = message => { throw new CommandError(message); };
const ascii = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const isItem = slot => slot !== null && slot !== tombstone;
const content = slot => slot === null ? '-' : slot === tombstone ? 'D' : slot.key;
const pairText = item => `${item.key}=${item.value}`;
const gauge = value => value < 10 ? String(value) : '+';
function hash(key, base, modulus) {
    let value = 0;
    for (const character of key) value = (value * base + character.charCodeAt(0)) % modulus;
    return value;
}
function prime(value) {
    for (let candidate = Math.max(2, value); ; ++candidate) {
        let valid = true;
        for (let divisor = 2; divisor * divisor <= candidate; ++divisor) if (candidate % divisor === 0) { valid = false; break; }
        if (valid) return candidate;
    }
}
function decimal(numerator, denominator) {
    const value = denominator === 0 ? 0 : Math.floor(100 * numerator / denominator);
    return `${Math.floor(value / 100)}.${String(value % 100).padStart(2, '0')}`;
}
function generatedKeys(count, length, seed) {
    let state = seed;
    const keys = [];
    for (let index = 0; index < count; ++index) {
        let key = '';
        for (let place = 0; place < length; ++place) {
            state = 48271 * state % 2147483647;
            key += String.fromCharCode(97 + state % 26);
        }
        keys.push(key);
    }
    return keys;
}
function histogram(values) {
    const counts = new Map();
    for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
    return [...counts].sort((a, b) => a[0] - b[0]).map(([value, count]) => `${value} ${count} ${'#'.repeat(Math.min(count, 50))}${count > 50 ? '+' : ''}`);
}
function runs(slots) {
    const empty = slots.indexOf(null);
    if (empty < 0) return [slots.length];
    const lengths = [];
    let length = 0;
    for (let offset = 1; offset <= slots.length; ++offset) {
        if (slots[(empty + offset) % slots.length] !== null) ++length;
        else if (length > 0) { lengths.push(length); length = 0; }
    }
    return lengths;
}
class Table {
    constructor(mode, capacity) {
        this.mode = mode;
        this.cap = capacity;
        this.size = 0;
        this.tomb = 0;
        this.buckets = mode === 'CHAIN' ? Array.from({ length: capacity }, () => []) : [];
        this.slots = mode === 'CHAIN' ? [] : Array(capacity * (mode === 'CUCKOO' ? 2 : 1)).fill(null);
        this.counters = { probes: 0, rehashes: 0, inserts: 0, updates: 0, hits: 0, misses: 0, deletes: 0, absent: 0 };
    }
    slotCount() { return this.cap * (this.mode === 'CUCKOO' ? 2 : 1); }
    position(index) { return this.mode === 'CUCKOO' ? `T${Math.floor(index / this.cap) + 1}.${index % this.cap}` : String(index); }
    distance(key, position) { return (position - hash(key, 31, this.cap) + this.cap) % this.cap; }
    items() { return this.mode === 'CHAIN' ? this.buckets.flat() : this.slots.filter(isItem); }
    search(key, tracing = false) {
        let probes = 0, available = null;
        const path = [], first = hash(key, 31, this.cap);
        const result = (item = null, position = -1, chainIndex = -1) => ({ item, position, chainIndex, probes, path, available });
        const examine = (index, slot) => {
            ++probes;
            if (tracing) path.push(`${this.position(index)}:${content(slot)}`);
        };
        if (this.mode === 'CHAIN') {
            const bucket = this.buckets[first];
            for (let index = 0; index < bucket.length; ++index) {
                examine(first, bucket[index]);
                if (bucket[index].key === key) return result(bucket[index], first, index);
            }
            return result();
        }
        if (this.mode === 'CUCKOO') {
            for (const index of [first, this.cap + hash(key, 37, this.cap)]) {
                const item = this.slots[index];
                examine(index, item);
                if (item !== null && item.key === key) return result(item, index);
            }
            return result();
        }
        const step = this.mode === 'DOUBLE' ? 1 + hash(key, 37, this.cap - 1) : 1;
        for (let i = 0; i < this.cap; ++i) {
            const offset = this.mode === 'QUADRATIC' ? i * i : i * step;
            const index = (first + offset) % this.cap, slot = this.slots[index];
            examine(index, slot);
            if (slot === null) { if (available === null) available = index; return result(); }
            if (slot === tombstone) { if (available === null) available = index; continue; }
            if (slot.key === key) return result(slot, index);
            if (this.mode === 'ROBINHOOD' && this.distance(slot.key, index) < i) return result();
        }
        return result();
    }
    place(item, initial = null, tracing = false) {
        const moves = [];
        const result = (success, position = -1, extra = {}) => ({ success, position, reused: false, shifted: 0, kicks: 0, homeless: null, moves, ...extra });
        if (this.mode === 'CHAIN') {
            const index = hash(item.key, 31, this.cap);
            this.buckets[index].push(item);
            return result(true, index);
        }
        if (['LINEAR', 'QUADRATIC', 'DOUBLE'].includes(this.mode)) {
            const search = initial ?? this.search(item.key), index = search.available;
            if (index === null) return result(false, -1, { homeless: item });
            const reused = this.slots[index] === tombstone;
            this.slots[index] = item;
            if (reused) --this.tomb;
            return result(true, index, { reused });
        }
        if (this.mode === 'ROBINHOOD') {
            let current = item, position = hash(item.key, 31, this.cap), distance = 0, from = null, original = null, shifted = 0;
            for (;;) {
                const occupant = this.slots[position];
                if (occupant === null) {
                    this.slots[position] = current;
                    if (tracing && from !== null) moves.push(`SHIFT ${current.key} ${from} -> ${position}`);
                    if (original === null) original = position;
                    return result(true, original, { shifted });
                }
                const otherDistance = this.distance(occupant.key, position);
                if (otherDistance < distance) {
                    this.slots[position] = current;
                    if (tracing && from !== null) moves.push(`SHIFT ${current.key} ${from} -> ${position}`);
                    if (original === null) original = position;
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
            const occupant = this.slots[index];
            if (occupant === null) {
                this.slots[index] = current;
                return result(true, this.search(item.key).position, { kicks });
            }
            if (kicks === this.cap) return result(false, -1, { kicks, homeless: current });
            this.slots[index] = current;
            ++kicks;
            if (tracing) moves.push(`KICK ${occupant.key} ${this.position(index)}`);
            current = occupant;
            part = 1 - part;
        }
    }
    remove(found, tracing) {
        const moves = [];
        let shifted = 0;
        if (this.mode === 'CHAIN') this.buckets[found.position].splice(found.chainIndex, 1);
        else if (['LINEAR', 'QUADRATIC', 'DOUBLE'].includes(this.mode)) {
            this.slots[found.position] = tombstone;
            ++this.tomb;
        } else {
            this.slots[found.position] = null;
            if (this.mode === 'ROBINHOOD') {
                let next = (found.position + 1) % this.cap;
                while (this.slots[next] !== null && this.distance(this.slots[next].key, next) >= 1) {
                    const item = this.slots[next], destination = (next - 1 + this.cap) % this.cap;
                    this.slots[destination] = item;
                    this.slots[next] = null;
                    if (tracing) moves.push(`SHIFT ${item.key} ${next} -> ${destination}`);
                    ++shifted;
                    next = (next + 1) % this.cap;
                }
            }
        }
        --this.size;
        return { shifted, moves };
    }
    static rebuild(items, mode, capacity) {
        const table = new Table(mode, capacity);
        for (const item of items) {
            if (!table.place(item).success) return null;
            ++table.size;
        }
        return table;
    }
    adopt(table) {
        this.mode = table.mode;
        this.cap = table.cap;
        this.size = table.size;
        this.tomb = table.tomb;
        this.buckets = table.buckets;
        this.slots = table.slots;
    }
    automatic(reason, capacity, pending = null) {
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
    loadCheck(maxLoad) {
        const threshold = maxLoad * this.slotCount();
        if (100 * (this.size + this.tomb) <= threshold) return [];
        const grow = 200 * this.size > threshold;
        return [this.automatic(grow ? 'load' : 'tomb', grow ? prime(2 * this.cap) : this.cap)];
    }
    shrinkCheck(minLoad, maxLoad) {
        const capacity = prime(Math.floor(this.cap / 2)), slots = capacity * (this.mode === 'CUCKOO' ? 2 : 1);
        if (100 * this.size >= minLoad * this.slotCount() || capacity >= this.cap || 100 * this.size > maxLoad * slots) return [];
        const replacement = Table.rebuild(this.items(), this.mode, capacity);
        if (replacement === null) return [];
        const old = this.cap;
        this.adopt(replacement);
        ++this.counters.rehashes;
        return [`REHASH shrink ${old} -> ${capacity}`];
    }
    put(key, value, command, maxLoad, tracing = false) {
        const found = this.search(key, tracing), trace = tracing ? [`PATH ${found.path.length ? found.path.join(' ') : 'none'}`] : [];
        this.counters.probes += found.probes;
        if (found.item !== null) {
            const old = found.item.value, next = command === 'ADD' ? old + value : value;
            const item = { key, value: next };
            if (this.mode === 'CHAIN') this.buckets[found.position][found.chainIndex] = item;
            else this.slots[found.position] = item;
            ++this.counters.updates;
            return { fresh: false, rehashes: [], rows: [`${command} ${key}=${next} UPDATED old=${old} at=${this.position(found.position)} probes=${found.probes}`, ...trace] };
        }
        const item = { key, value }, placed = this.place(item, found, tracing);
        ++this.size;
        ++this.counters.inserts;
        let row = `${command} ${key}=${value} NEW`;
        if (placed.success) {
            row += ` at=${this.position(placed.position)} probes=${found.probes}`;
            if (placed.reused) row += ' reused';
            if (this.mode === 'ROBINHOOD') row += ` shifted=${placed.shifted}`;
            if (this.mode === 'CUCKOO') row += ` kicks=${placed.kicks}`;
        } else row += ` probes=${found.probes}` + (this.mode === 'CUCKOO' ? ` kicks=${placed.kicks} failed` : ' full');
        const rehashes = [];
        if (!placed.success) rehashes.push(this.automatic(this.mode === 'CUCKOO' ? 'kicks' : 'full', prime(2 * this.cap), placed.homeless));
        rehashes.push(...this.loadCheck(maxLoad));
        return { fresh: true, rehashes, rows: [row, ...trace, ...placed.moves, ...rehashes] };
    }
    get(key, tracing) {
        const found = this.search(key, tracing);
        this.counters.probes += found.probes;
        let row;
        if (found.item === null) { ++this.counters.misses; row = `GET ${key} NOT FOUND probes=${found.probes}`; }
        else { ++this.counters.hits; row = `GET ${key}=${found.item.value} at=${this.position(found.position)} probes=${found.probes}`; }
        return tracing ? [row, `PATH ${found.path.length ? found.path.join(' ') : 'none'}`] : [row];
    }
    delete(key, minLoad, maxLoad, tracing = false) {
        const found = this.search(key, tracing), trace = tracing ? [`PATH ${found.path.length ? found.path.join(' ') : 'none'}`] : [];
        this.counters.probes += found.probes;
        if (found.item === null) {
            ++this.counters.absent;
            return { deleted: false, rehashes: [], rows: [`DEL ${key} NOT FOUND probes=${found.probes}`, ...trace] };
        }
        const removed = this.remove(found, tracing);
        ++this.counters.deletes;
        let row = `DEL ${key} OK at=${this.position(found.position)} probes=${found.probes}`;
        if (this.mode === 'ROBINHOOD') row += ` shifted=${removed.shifted}`;
        const rehashes = this.shrinkCheck(minLoad, maxLoad);
        return { deleted: true, rehashes, rows: [row, ...trace, ...removed.moves, ...rehashes] };
    }
    costs() {
        const records = [];
        if (this.mode === 'CHAIN') {
            this.buckets.forEach((bucket, position) => bucket.forEach((item, index) => records.push({ key: item.key, cost: index + 1, position: String(position) })));
        } else this.slots.forEach((item, position) => {
            if (!isItem(item)) return;
            const cost = this.mode === 'CUCKOO' ? (position < this.cap ? 1 : 2) : this.mode === 'ROBINHOOD' || this.mode === 'LINEAR' ? this.distance(item.key, position) + 1 : this.search(item.key).probes;
            records.push({ key: item.key, cost, position: this.position(position) });
        });
        return records;
    }
    metrics() {
        const costs = this.costs();
        const longest = costs.reduce((value, item) => Math.max(value, item.cost), 0), total = costs.reduce((value, item) => value + item.cost, 0);
        return { longest, average: decimal(total, this.size) };
    }
    dump() {
        const rows = [`DUMP ${this.mode} cap=${this.cap} size=${this.size} tomb=${this.tomb}`];
        if (this.mode === 'CHAIN') this.buckets.forEach((bucket, index) => rows.push(`${index} ${bucket.length ? bucket.map(pairText).join(' ') : '-'}`));
        else this.slots.forEach((slot, index) => {
            const position = this.mode === 'CUCKOO' ? `T${Math.floor(index / this.cap) + 1} ${index % this.cap}` : String(index);
            let value = isItem(slot) ? pairText(slot) : content(slot);
            if (this.mode === 'ROBINHOOD' && slot !== null) value += ` d=${this.distance(slot.key, index)}`;
            rows.push(`${position} ${value}`);
        });
        return rows;
    }
    map() {
        const rows = [`MAP ${this.mode} cap=${this.cap}`];
        const costs = new Map(this.costs().map(item => [item.key, item.cost]));
        const parts = this.mode === 'CUCKOO' ? [this.slots.slice(0, this.cap), this.slots.slice(this.cap)] : [this.mode === 'CHAIN' ? this.buckets : this.slots];
        parts.forEach((part, number) => {
            const characters = part.map(slot => {
                if (this.mode === 'CHAIN') return slot.length === 0 ? '.' : gauge(slot.length);
                if (slot === null) return '.';
                if (slot === tombstone) return 'D';
                return this.mode === 'CUCKOO' ? '#' : gauge(costs.get(slot.key) - 1);
            });
            for (let index = 0; index < characters.length; index += 40) {
                const prefix = this.mode === 'CUCKOO' ? `T${number + 1} ` : '';
                rows.push(`${prefix}${String(index).padStart(5, '0')} ${characters.slice(index, index + 40).join('')}`);
            }
        });
        return rows;
    }
    statistics() {
        const { longest, average } = this.metrics(), count = this.counters;
        return [`STATS ${this.mode} size=${this.size} cap=${this.cap} slots=${this.slotCount()} tomb=${this.tomb} load=${decimal(100 * this.size, this.slotCount())}% longest=${longest} avg=${average} probes=${count.probes} rehashes=${count.rehashes}`,
            `OPS inserts=${count.inserts} updates=${count.updates} hits=${count.hits} misses=${count.misses} deletes=${count.deletes} absent=${count.absent}`];
    }
    scan(cursor, limit) {
        const keys = [];
        let next = cursor;
        while (next < this.slotCount() && keys.length < limit) {
            if (this.mode === 'CHAIN') {
                for (const item of this.buckets[next]) keys.push(item.key);
            } else if (isItem(this.slots[next])) keys.push(this.slots[next].key);
            ++next;
        }
        if (next === this.slotCount()) next = 0;
        return [[`SCAN next=${next}`, ...keys].join(' ')];
    }
    clusters() {
        const lengths = this.mode === 'CHAIN' ? this.buckets.filter(bucket => bucket.length > 0).map(bucket => bucket.length)
            : this.mode === 'CUCKOO' ? [...runs(this.slots.slice(0, this.cap)), ...runs(this.slots.slice(this.cap))] : runs(this.slots);
        const longest = lengths.reduce((maximum, length) => Math.max(maximum, length), 0);
        return [`CLUSTERS runs=${lengths.length} longest=${longest}`, ...histogram(lengths)];
    }
    distribution() {
        const costs = this.costs().map(item => item.cost), longest = costs.reduce((maximum, cost) => Math.max(maximum, cost), 0);
        return [`DIST keys=${this.size} longest=${longest}`, ...histogram(costs)];
    }
}

function checkCapacity(capacity) { if (capacity < 2 || capacity > 10000) fail('BAD CAPACITY'); }
function checkMode(mode) { if (!modes.includes(mode)) fail(`BAD MODE ${mode}`); }
function checkGeneration(count, length, seed) {
    if (count < 1 || count > 500 || length < 1 || length > 10 || seed < 1 || seed > 2147483646) fail('BAD ARGUMENT');
}
class Simulator {
    constructor() { this.table = null; this.maxLoad = 75; this.minLoad = 0; this.tracing = false; }
    compare(capacity) {
        const items = this.table.items().slice().sort((a, b) => ascii(a.key, b.key)), rows = [`COMPARE keys=${items.length} cap=${capacity}`];
        for (const mode of modes) {
            const table = new Table(mode, capacity);
            for (const item of items) table.put(item.key, item.value, 'PUT', this.maxLoad);
            const { longest, average } = table.metrics();
            rows.push(`${mode} cap=${table.cap} longest=${longest} avg=${average} probes=${table.counters.probes} rehashes=${table.counters.rehashes}`);
        }
        return rows;
    }
    bench(capacity, count, length, seed) {
        const keys = generatedKeys(2 * count, length, seed), rows = [`BENCH cap=${capacity} count=${count} len=${length} seed=${seed}`];
        for (const mode of modes) {
            const table = new Table(mode, capacity);
            for (let index = 0; index < count; ++index) table.put(keys[index], index + 1, 'PUT', this.maxLoad);
            let misses = 0, probes = 0;
            for (let index = count; index < keys.length; ++index) {
                const found = table.search(keys[index]);
                if (found.item === null) { ++misses; probes += found.probes; }
            }
            rows.push(`${mode} cap=${table.cap} keys=${table.size} hit=${table.metrics().average} misses=${misses} miss=${decimal(probes, misses)} rehashes=${table.counters.rehashes}`);
        }
        return rows;
    }
    execute(line) {
        const [command, ...args] = line.split(' ');
        if (!commands.has(command)) fail(`UNKNOWN COMMAND ${command}`);
        if (command === 'CREATE') {
            checkMode(args[0]);
            const capacity = Number(args[1]);
            checkCapacity(capacity);
            this.table = new Table(args[0], prime(capacity));
            return [`CREATE ${args[0]} cap=${this.table.cap}`];
        }
        if (command === 'MAXLOAD' || command === 'MINLOAD') {
            const value = Number(args[0]), maximum = command === 'MAXLOAD';
            if (maximum ? value < 10 || value > 95 : value > 40) fail('BAD LOAD');
            if (maximum) this.maxLoad = value;
            else this.minLoad = value;
            return [`${command} ${value}`];
        }
        if (command === 'TRACE') {
            if (args[0] !== 'ON' && args[0] !== 'OFF') fail('BAD ARGUMENT');
            this.tracing = args[0] === 'ON';
            return [`TRACE ${args[0]}`];
        }
        if (command === 'HASH') {
            const key = args[0], capacity = Number(args[1]);
            checkCapacity(capacity);
            return [`HASH ${key} m=${capacity} h31=${hash(key, 31, capacity)} h37=${hash(key, 37, capacity)} step=${1 + hash(key, 37, capacity - 1)}`];
        }
        if (command === 'BENCH') {
            const [capacity, count, length, seed] = args.map(Number);
            checkCapacity(capacity);
            checkGeneration(count, length, seed);
            return this.bench(prime(capacity), count, length, seed);
        }
        const table = this.table;
        if (table === null) fail('NO TABLE');
        switch (command) {
            case 'PUT':
            case 'ADD': return table.put(args[0], Number(args[1]), command, this.maxLoad, this.tracing).rows;
            case 'GET': return table.get(args[0], this.tracing);
            case 'DEL': return table.delete(args[0], this.minLoad, this.maxLoad, this.tracing).rows;
            case 'PROBE': {
                const found = table.search(args[0], true);
                return [[`PROBE ${args[0]}`, ...found.path, `${found.item === null ? 'MISS' : 'FOUND'} probes=${found.probes}`].join(' ')];
            }
            case 'GEN':
            case 'GENDEL': {
                const [count, length, seed] = args.map(Number);
                checkGeneration(count, length, seed);
                const keys = generatedKeys(count, length, seed), rows = [];
                let successes = 0;
                keys.forEach((key, index) => {
                    if (command === 'GEN') {
                        const result = table.put(key, index + 1, 'PUT', this.maxLoad);
                        successes += Number(result.fresh);
                        rows.push(...result.rehashes);
                    } else {
                        const result = table.delete(key, this.minLoad, this.maxLoad);
                        successes += Number(result.deleted);
                        rows.push(...result.rehashes);
                    }
                });
                rows.push(command === 'GEN' ? `GEN ${count} new=${successes} updated=${count - successes}` : `GENDEL ${count} deleted=${successes} missing=${count - successes}`);
                return rows;
            }
            case 'RESIZE':
            case 'CONVERT': {
                let mode = table.mode, capacity = table.cap;
                if (command === 'RESIZE') { checkCapacity(Number(args[0])); capacity = prime(Number(args[0])); }
                else { checkMode(args[0]); mode = args[0]; }
                const slots = capacity * (mode === 'CUCKOO' ? 2 : 1);
                if (100 * table.size > this.maxLoad * slots) fail('TOO SMALL');
                const replacement = Table.rebuild(table.items(), mode, capacity);
                if (replacement === null) fail('REBUILD FAILED');
                const row = command === 'RESIZE' ? `RESIZE ${table.cap} -> ${capacity}` : `CONVERT ${table.mode} -> ${mode} cap=${capacity}`;
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
                const limit = Number(args[0]);
                if (limit < 1 || limit > 100) fail('BAD ARGUMENT');
                const items = table.costs().sort((a, b) => b.cost - a.cost || ascii(a.key, b.key)).slice(0, limit);
                return [`TOP ${items.length}`, ...items.map(item => `${item.key} cost=${item.cost} at=${item.position}`)];
            }
            case 'SCAN': {
                const [cursor, limit] = args.map(Number);
                if (limit < 1 || limit > 100) fail('BAD ARGUMENT');
                if (cursor >= table.slotCount()) fail('BAD CURSOR');
                return table.scan(cursor, limit);
            }
            case 'CLUSTERS': return table.clusters();
            case 'DIST': return table.distribution();
            case 'COMPARE': {
                const capacity = Number(args[0]);
                checkCapacity(capacity);
                return this.compare(prime(capacity));
            }
            default: throw new Error(`Unhandled command ${command}`);
        }
    }
}

const input = fs.readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
const simulator = new Simulator();
for (let index = 1; index <= Number(input[0]); ++index) {
    try { process.stdout.write(simulator.execute(input[index]).join('\n') + '\n'); }
    catch (error) {
        if (!(error instanceof CommandError)) throw error;
        process.stdout.write(`ERROR ${error.message}\n`);
    }
}
