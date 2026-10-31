import { readFileSync } from 'node:fs';

const messages = {
    wrongType: 'WRONGTYPE Operation against a key holding the wrong kind of value',
    notInteger: 'ERR value is not an integer or out of range',
    overflow: 'ERR increment or decrement would overflow',
    syntax: 'ERR syntax error',
    positive: 'ERR value is out of range, must be positive',
    noKey: 'ERR no such key',
};
class CommandError extends Error {}
function fail(message) { throw new CommandError(message); }
const integerNotation = /^(?:0|-?[1-9][0-9]{0,8})$/;
function number(value, message = messages.notInteger) {
    if (!integerNotation.test(value)) fail(message);
    return Number(value);
}
function increment(value, delta) {
    const result = value + delta;
    if (Math.abs(result) > 999999999) fail(messages.overflow);
    return result;
}
const status = value => [value];
const integer = value => [`(integer) ${value}`];
const string = value => [value === null ? '(nil)' : JSON.stringify(value)];
function array(values) {
    if (values.length === 0) return ['(empty array)'];
    const width = String(values.length).length;
    return values.map((value, index) => `${String(index + 1).padStart(width)}) ${string(value)[0]}`);
}
const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;
function range(sequence, start, stop) {
    if (start < 0) start += sequence.length;
    if (stop < 0) stop += sequence.length;
    start = Math.max(0, start); stop = Math.min(sequence.length - 1, stop);
    return start <= stop ? sequence.slice(start, stop + 1) : sequence.slice(0, 0);
}

function splitArguments(line) {
    const argumentsList = [];
    let position = 0;
    while (position < line.length) {
        if (line[position] === ' ') { ++position; continue; }
        if (line[position] !== '"') {
            const start = position;
            while (position < line.length && line[position] !== ' ') ++position;
            argumentsList.push(line.slice(start, position));
            continue;
        }
        ++position;
        let value = '', closed = false;
        while (position < line.length) {
            const character = line[position++];
            if (character === '"') { closed = true; break; }
            if (character === '\\') {
                if (position === line.length || !['"', '\\'].includes(line[position])) return null;
                value += line[position++];
            } else value += character;
        }
        if (!closed || (position < line.length && line[position] !== ' ')) return null;
        argumentsList.push(value);
    }
    return argumentsList;
}

function parsePattern(pattern) {
    const parts = [];
    for (let position = 0; position < pattern.length; ++position) {
        const character = pattern[position];
        if (character === '\\') {
            if (++position === pattern.length) fail('ERR invalid pattern');
            parts.push({ kind: 'literal', value: pattern[position] });
        } else if (character === '[') {
            const end = pattern.indexOf(']', position + 1);
            if (end < 0) fail('ERR invalid pattern');
            let content = pattern.slice(position + 1, end);
            const negated = content.startsWith('^');
            if (negated) content = content.slice(1);
            if (content.length === 0) fail('ERR invalid pattern');
            const characters = new Set();
            for (let index = 0; index < content.length;) {
                if (index + 2 < content.length && content[index + 1] === '-') {
                    const first = content.charCodeAt(index), last = content.charCodeAt(index + 2);
                    for (let code = Math.min(first, last); code <= Math.max(first, last); ++code) characters.add(String.fromCharCode(code));
                    index += 3;
                } else characters.add(content[index++]);
            }
            parts.push({ kind: 'class', characters, negated }); position = end;
        } else if (character === '*') parts.push({ kind: 'star' });
        else if (character === '?') parts.push({ kind: 'any' });
        else parts.push({ kind: 'literal', value: character });
    }
    return parts;
}
function matches(parts, value) {
    let previous = Array(value.length + 1).fill(false);
    previous[0] = true;
    for (const part of parts) {
        const current = Array(value.length + 1).fill(false);
        if (part.kind === 'star') {
            current[0] = previous[0];
            for (let index = 1; index <= value.length; ++index) current[index] = previous[index] || current[index - 1];
        } else {
            for (let index = 0; index < value.length; ++index) {
                const accepts = part.kind === 'any' || (part.kind === 'literal' ? part.value === value[index]
                    : part.characters.has(value[index]) !== part.negated);
                current[index + 1] = previous[index] && accepts;
            }
        }
        previous = current;
    }
    return previous[value.length];
}
function scoreBound(word) {
    if (word === '-inf' || word === '+inf') return { value: word === '-inf' ? -Infinity : Infinity, inclusive: true };
    const inclusive = !word.startsWith('(');
    return { value: number(inclusive ? word : word.slice(1), 'ERR min or max is not a float'), inclusive };
}

const commands = new Map();
function register(group, names, minimum, maximum = minimum, parity = null) {
    for (const name of names.split(' ')) commands.set(name, { group, minimum, maximum, parity });
}
register('strings', 'SET', 2, Infinity);
register('strings', 'GET INCR DECR STRLEN', 1);
register('strings', 'MSET', 2, Infinity, 0);
register('strings', 'MGET', 1, Infinity);
register('strings', 'INCRBY DECRBY APPEND', 2);
register('strings', 'GETRANGE', 3);
register('lists', 'LPUSH RPUSH', 2, Infinity);
register('lists', 'LPOP RPOP', 1, 2);
register('lists', 'LRANGE LSET LREM LTRIM', 3);
register('lists', 'LLEN', 1);
register('lists', 'LINDEX', 2);
register('lists', 'LINSERT', 4);
register('hashes', 'HSET', 3, Infinity, 1);
register('hashes', 'HGET HEXISTS', 2);
register('hashes', 'HDEL', 2, Infinity);
register('hashes', 'HGETALL HLEN HKEYS HVALS', 1);
register('hashes', 'HINCRBY', 3);
register('sets', 'SADD SREM', 2, Infinity);
register('sets', 'SISMEMBER', 2);
register('sets', 'SMEMBERS SCARD', 1);
register('sets', 'SINTER SUNION SDIFF', 1, Infinity);
register('sets', 'SINTERSTORE SUNIONSTORE SDIFFSTORE', 2, Infinity);
register('sortedSets', 'ZADD', 3, Infinity, 1);
register('sortedSets', 'ZSCORE ZRANK', 2);
register('sortedSets', 'ZINCRBY', 3);
register('sortedSets', 'ZREM', 2, Infinity);
register('sortedSets', 'ZCARD', 1);
register('sortedSets', 'ZRANGE ZRANGEBYSCORE', 3, 4);
register('keys', 'DEL EXISTS', 1, Infinity);
register('keys', 'TYPE KEYS TTL PERSIST TICK', 1);
register('keys', 'RENAME RENAMENX', 2);
register('keys', 'EXPIRE', 2, 3);
register('keys', 'TIME DBSIZE FLUSH INFO', 0);
register('control', 'BEGIN COMMIT ROLLBACK', 0);
register('control', 'SNAPSHOT RESTORE', 1);

class Store {
    constructor() {
        this.database = new Map(); this.time = 0; this.stack = []; this.snapshots = new Map();
    }
    data(key, type, fallback) {
        const entry = this.database.get(key);
        if (entry !== undefined && entry.type !== type) fail(messages.wrongType);
        return entry === undefined ? fallback : entry.value;
    }
    write(key, type, value, expiry = undefined) {
        const empty = type !== 'string' && (type === 'list' ? value.length : value.size) === 0;
        if (empty) this.database.delete(key);
        else this.database.set(key, { type, value, expiry: expiry === undefined ? (this.database.get(key)?.expiry ?? null) : expiry });
    }
    purge() {
        let removed = 0;
        for (const [key, entry] of this.database) if (entry.expiry !== null && entry.expiry <= this.time) {
            this.database.delete(key); ++removed;
        }
        return removed;
    }
    command(line) {
        const words = splitArguments(line);
        if (words === null) return status('Invalid argument(s)');
        const verb = words[0].toUpperCase(), args = words.slice(1), specification = commands.get(verb);
        try {
            if (specification === undefined) fail(`ERR unknown command '${words[0]}'`);
            const { minimum, maximum, parity, group } = specification;
            if (args.length < minimum || args.length > maximum || (parity !== null && args.length % 2 !== parity)) {
                fail(`ERR wrong number of arguments for '${verb.toLowerCase()}' command`);
            }
            return this[group](verb, args);
        } catch (error) {
            if (!(error instanceof CommandError)) throw error;
            return [`(error) ${error.message}`];
        }
    }
    strings(verb, args) {
        const key = args[0];
        switch (verb) {
        case 'SET': {
            const options = new Map();
            for (let index = 2; index < args.length; ++index) {
                const option = args[index].toUpperCase();
                if (!['NX', 'XX', 'EX', 'KEEPTTL', 'GET'].includes(option) || options.has(option)) fail(messages.syntax);
                if (option === 'EX') {
                    if (++index === args.length) fail(messages.syntax);
                    options.set(option, args[index]);
                } else options.set(option, true);
            }
            if ((options.has('NX') && options.has('XX')) || (options.has('EX') && options.has('KEEPTTL'))) fail(messages.syntax);
            let expiry = null;
            if (options.has('EX')) {
                const seconds = number(options.get('EX'));
                if (seconds <= 0) fail("ERR invalid expire time in 'set' command");
                expiry = this.time + seconds;
            }
            const previous = this.database.get(key);
            if (options.has('GET')) this.data(key, 'string', null);
            const changed = !(options.has('NX') && previous !== undefined) && !(options.has('XX') && previous === undefined);
            if (options.has('KEEPTTL') && previous !== undefined) expiry = previous.expiry;
            if (changed) this.write(key, 'string', args[1], expiry);
            return options.has('GET') ? string(previous?.value ?? null) : changed ? status('OK') : string(null);
        }
        case 'GET': return string(this.data(key, 'string', null));
        case 'MSET':
            for (let index = 0; index < args.length; index += 2) this.write(args[index], 'string', args[index + 1], null);
            return status('OK');
        case 'MGET':
            return array(args.map(key => { const entry = this.database.get(key); return entry?.type === 'string' ? entry.value : null; }));
        case 'INCR': case 'DECR': case 'INCRBY': case 'DECRBY': {
            let delta = verb === 'INCR' ? 1 : verb === 'DECR' ? -1 : number(args[1]);
            if (verb === 'DECRBY') delta = -delta;
            const result = increment(number(this.data(key, 'string', '0')), delta);
            this.write(key, 'string', String(result));
            return integer(result);
        }
        case 'APPEND': {
            const value = this.data(key, 'string', '') + args[1];
            this.write(key, 'string', value);
            return integer(value.length);
        }
        case 'STRLEN': return integer(this.data(key, 'string', '').length);
        case 'GETRANGE': {
            const start = number(args[1]), stop = number(args[2]);
            return string(range(this.data(key, 'string', ''), start, stop));
        }
        }
    }
    lists(verb, args) {
        const key = args[0];
        let first, second;
        if (verb === 'LPOP' || verb === 'RPOP') {
            first = args.length === 2 ? number(args[1], messages.positive) : 1;
            if (first < 0) fail(messages.positive);
        } else if (['LRANGE', 'LINDEX', 'LSET', 'LREM', 'LTRIM'].includes(verb)) {
            first = number(args[1]);
            if (verb === 'LRANGE' || verb === 'LTRIM') second = number(args[2]);
        } else if (verb === 'LINSERT' && !['BEFORE', 'AFTER'].includes(args[1].toUpperCase())) fail(messages.syntax);
        const list = this.data(key, 'list', []);
        switch (verb) {
        case 'LPUSH': case 'RPUSH':
            for (const element of args.slice(1)) {
                if (verb === 'LPUSH') list.unshift(element); else list.push(element);
            }
            this.write(key, 'list', list);
            return integer(list.length);
        case 'LPOP': case 'RPOP': {
            if (!this.database.has(key)) return string(null);
            const removed = [];
            while (removed.length < first && list.length > 0) removed.push(verb === 'LPOP' ? list.shift() : list.pop());
            this.write(key, 'list', list);
            return args.length === 2 ? array(removed) : string(removed[0]);
        }
        case 'LRANGE': return array(range(list, first, second));
        case 'LLEN': return integer(list.length);
        case 'LINDEX': case 'LSET': {
            if (verb === 'LSET' && !this.database.has(key)) fail(messages.noKey);
            const index = first < 0 ? first + list.length : first;
            if (verb === 'LINDEX') return string(index >= 0 && index < list.length ? list[index] : null);
            if (index < 0 || index >= list.length) fail('ERR index out of range');
            list[index] = args[2]; this.write(key, 'list', list);
            return status('OK');
        }
        case 'LREM': {
            let removed = 0;
            const ordered = first < 0 ? [...list].reverse() : list;
            const remaining = ordered.filter(element => {
                if (element === args[2] && (first === 0 || removed < Math.abs(first))) { ++removed; return false; }
                return true;
            });
            if (first < 0) remaining.reverse();
            this.write(key, 'list', remaining);
            return integer(removed);
        }
        case 'LTRIM': this.write(key, 'list', range(list, first, second)); return status('OK');
        case 'LINSERT': {
            if (!this.database.has(key)) return integer(0);
            const index = list.indexOf(args[2]);
            if (index < 0) return integer(-1);
            list.splice(index + (args[1].toUpperCase() === 'AFTER' ? 1 : 0), 0, args[3]);
            this.write(key, 'list', list);
            return integer(list.length);
        }
        }
    }
    hashes(verb, args) {
        const key = args[0], delta = verb === 'HINCRBY' ? number(args[2]) : 0;
        const hash = this.data(key, 'hash', new Map());
        switch (verb) {
        case 'HSET': {
            let added = 0;
            for (let index = 1; index < args.length; index += 2) {
                if (!hash.has(args[index])) ++added;
                hash.set(args[index], args[index + 1]);
            }
            this.write(key, 'hash', hash);
            return integer(added);
        }
        case 'HGET': return string(hash.get(args[1]) ?? null);
        case 'HDEL': {
            let removed = 0;
            for (const field of args.slice(1)) if (hash.delete(field)) ++removed;
            this.write(key, 'hash', hash);
            return integer(removed);
        }
        case 'HLEN': return integer(hash.size);
        case 'HEXISTS': return integer(hash.has(args[1]) ? 1 : 0);
        case 'HINCRBY': {
            const result = increment(number(hash.get(args[1]) ?? '0', 'ERR hash value is not an integer'), delta);
            hash.set(args[1], String(result)); this.write(key, 'hash', hash);
            return integer(result);
        }
        case 'HGETALL': case 'HKEYS': case 'HVALS': {
            const fields = [...hash.keys()].sort();
            return array(verb === 'HKEYS' ? fields : verb === 'HVALS' ? fields.map(field => hash.get(field))
                : fields.flatMap(field => [field, hash.get(field)]));
        }
        }
    }
    sets(verb, args) {
        const storing = verb.endsWith('STORE'), operation = storing ? verb.slice(0, -5) : verb;
        if (['SINTER', 'SUNION', 'SDIFF'].includes(operation)) {
            const sources = (storing ? args.slice(1) : args).map(key => this.data(key, 'set', new Set()));
            const result = new Set(sources[0]);
            for (const source of sources.slice(1)) {
                if (operation === 'SUNION') for (const member of source) result.add(member);
                else if (operation === 'SINTER') { for (const member of result) if (!source.has(member)) result.delete(member); }
                else for (const member of source) result.delete(member);
            }
            if (storing) { this.write(args[0], 'set', result, null); return integer(result.size); }
            return array([...result].sort());
        }
        const key = args[0], members = this.data(key, 'set', new Set());
        switch (verb) {
        case 'SADD': {
            let added = 0;
            for (const member of args.slice(1)) if (!members.has(member)) { members.add(member); ++added; }
            this.write(key, 'set', members);
            return integer(added);
        }
        case 'SREM': {
            let removed = 0;
            for (const member of args.slice(1)) if (members.delete(member)) ++removed;
            this.write(key, 'set', members);
            return integer(removed);
        }
        case 'SISMEMBER': return integer(members.has(args[1]) ? 1 : 0);
        case 'SMEMBERS': return array([...members].sort());
        case 'SCARD': return integer(members.size);
        }
    }
    sortedSets(verb, args) {
        const key = args[0], scores = [];
        let delta, low, high;
        if (verb === 'ZADD') for (let index = 1; index < args.length; index += 2) scores.push(number(args[index]));
        if (verb === 'ZINCRBY') delta = number(args[1]);
        if (verb === 'ZRANGE' || verb === 'ZRANGEBYSCORE') {
            if (args.length === 4 && args[3].toUpperCase() !== 'WITHSCORES') fail(messages.syntax);
            if (verb === 'ZRANGE') { low = number(args[1]); high = number(args[2]); }
            else { low = scoreBound(args[1]); high = scoreBound(args[2]); }
        }
        const members = this.data(key, 'zset', new Map());
        switch (verb) {
        case 'ZADD': {
            let added = 0;
            for (let index = 0; index < scores.length; ++index) {
                const member = args[2 * index + 2];
                if (!members.has(member)) ++added;
                members.set(member, scores[index]);
            }
            this.write(key, 'zset', members);
            return integer(added);
        }
        case 'ZSCORE': return string(members.has(args[1]) ? String(members.get(args[1])) : null);
        case 'ZINCRBY': {
            const score = increment(members.get(args[2]) ?? 0, delta);
            members.set(args[2], score); this.write(key, 'zset', members);
            return string(String(score));
        }
        case 'ZREM': {
            let removed = 0;
            for (const member of args.slice(1)) if (members.delete(member)) ++removed;
            this.write(key, 'zset', members);
            return integer(removed);
        }
        case 'ZCARD': return integer(members.size);
        case 'ZRANK': case 'ZRANGE': case 'ZRANGEBYSCORE': {
            const ordered = [...members].sort((left, right) => left[1] - right[1] || compare(left[0], right[0]));
            if (verb === 'ZRANK') {
                const rank = ordered.findIndex(([member]) => member === args[1]);
                return rank < 0 ? string(null) : integer(rank);
            }
            const selected = verb === 'ZRANGE' ? range(ordered, low, high) : ordered.filter(([, score]) =>
                (score > low.value || (score === low.value && low.inclusive)) && (score < high.value || (score === high.value && high.inclusive)));
            return array(args.length === 4 ? selected.flatMap(([member, score]) => [member, String(score)]) : selected.map(([member]) => member));
        }
        }
    }
    keys(verb, args) {
        const key = args[0];
        switch (verb) {
        case 'DEL': {
            let removed = 0;
            for (const key of args) if (this.database.delete(key)) ++removed;
            return integer(removed);
        }
        case 'EXISTS': return integer(args.filter(key => this.database.has(key)).length);
        case 'TYPE': return status(this.database.get(key)?.type ?? 'none');
        case 'RENAME': case 'RENAMENX': {
            const entry = this.database.get(key);
            if (entry === undefined) fail(messages.noKey);
            if (verb === 'RENAMENX' && this.database.has(args[1])) return integer(0);
            if (key !== args[1]) { this.database.set(args[1], entry); this.database.delete(key); }
            return verb === 'RENAMENX' ? integer(1) : status('OK');
        }
        case 'KEYS': {
            const parts = parsePattern(key);
            return array([...this.database.keys()].filter(key => matches(parts, key)).sort());
        }
        case 'EXPIRE': {
            const condition = args.length === 3 ? args[2].toUpperCase() : null;
            if (condition !== null && !['NX', 'XX', 'GT', 'LT'].includes(condition)) fail(`ERR Unsupported option ${args[2]}`);
            const seconds = number(args[1]), entry = this.database.get(key);
            if (entry === undefined) return integer(0);
            const expiry = this.time + seconds, previous = entry.expiry;
            if ((condition === 'NX' && previous !== null) || (condition === 'XX' && previous === null)
                || (condition === 'GT' && (previous === null || expiry <= previous))
                || (condition === 'LT' && previous !== null && expiry >= previous)) return integer(0);
            if (seconds <= 0) this.database.delete(key); else entry.expiry = expiry;
            return integer(1);
        }
        case 'TTL': {
            const entry = this.database.get(key);
            return integer(entry === undefined ? -2 : entry.expiry === null ? -1 : entry.expiry - this.time);
        }
        case 'PERSIST': {
            const entry = this.database.get(key);
            if (entry === undefined || entry.expiry === null) return integer(0);
            entry.expiry = null;
            return integer(1);
        }
        case 'TICK': {
            const ticks = number(key);
            if (ticks <= 0) fail(messages.positive);
            this.time += ticks;
            return integer(this.purge());
        }
        case 'TIME': return integer(this.time);
        case 'DBSIZE': return integer(this.database.size);
        case 'FLUSH': this.database.clear(); return status('OK');
        case 'INFO': {
            const counts = { string: 0, list: 0, hash: 0, set: 0, zset: 0 };
            let expires = 0;
            for (const entry of this.database.values()) { ++counts[entry.type]; if (entry.expiry !== null) ++expires; }
            return status(`keys=${this.database.size},expires=${expires},string=${counts.string},list=${counts.list},hash=${counts.hash},set=${counts.set},zset=${counts.zset},time=${this.time},depth=${this.stack.length},snapshots=${this.snapshots.size}`);
        }
        }
    }
    control(verb, args) {
        switch (verb) {
        case 'BEGIN': this.stack.push(structuredClone(this.database)); break;
        case 'COMMIT': case 'ROLLBACK':
            if (this.stack.length === 0) fail('ERR no transaction');
            if (verb === 'ROLLBACK') { this.database = this.stack.pop(); this.purge(); }
            else this.stack.pop();
            break;
        case 'SNAPSHOT': this.snapshots.set(args[0], structuredClone(this.database)); break;
        case 'RESTORE':
            if (!this.snapshots.has(args[0])) fail('ERR no such snapshot');
            this.database = structuredClone(this.snapshots.get(args[0])); this.purge();
            break;
        }
        return status('OK');
    }
}

const lines = readFileSync(0, 'utf8').split(/\r?\n/), store = new Store();
for (let index = 1; index <= Number(lines[0]); ++index) process.stdout.write(store.command(lines[index]).join('\n') + '\n');
