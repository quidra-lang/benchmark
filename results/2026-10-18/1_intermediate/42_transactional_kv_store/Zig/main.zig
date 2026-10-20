const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Text = []const u8;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Kind = enum { string, list, hash, set, zset };
const Field = struct { name: Text, value: Text };
const Score = struct { name: Text, score: i64 };
const Value = union(Kind) {
    string: Text,
    list: []const Text,
    hash: []const Field,
    set: []const Text,
    zset: []const Score,

    fn empty(value: Value) bool {
        return switch (value) {
            .string => false,
            .list, .set => |items| items.len == 0,
            .hash => |items| items.len == 0,
            .zset => |items| items.len == 0,
        };
    }
    fn retain(value: Value, gpa: Allocator) Allocator.Error!Value {
        return switch (value) {
            .string => value,
            .list => |items| .{ .list = try gpa.dupe(Text, items) },
            .hash => |items| .{ .hash = try gpa.dupe(Field, items) },
            .set => |items| .{ .set = try gpa.dupe(Text, items) },
            .zset => |items| .{ .zset = try gpa.dupe(Score, items) },
        };
    }
};
const Entry = struct { key: Text, value: Value, expiry: ?i64 = null };
const Snapshot = struct { name: Text, entries: []const Entry };
const Verb = enum {
    SET, GET, MSET, MGET, INCR, DECR, INCRBY, DECRBY, APPEND, STRLEN, GETRANGE,
    LPUSH, RPUSH, LPOP, RPOP, LRANGE, LLEN, LINDEX, LSET, LREM, LTRIM, LINSERT,
    HSET, HGET, HDEL, HGETALL, HLEN, HEXISTS, HKEYS, HVALS, HINCRBY,
    SADD, SREM, SISMEMBER, SMEMBERS, SCARD, SINTER, SUNION, SDIFF,
    SINTERSTORE, SUNIONSTORE, SDIFFSTORE,
    ZADD, ZSCORE, ZINCRBY, ZREM, ZCARD, ZRANK, ZRANGE, ZRANGEBYSCORE,
    DEL, EXISTS, TYPE, RENAME, RENAMENX, KEYS, EXPIRE, TTL, PERSIST, TICK, TIME, DBSIZE, FLUSH, INFO,
    BEGIN, COMMIT, ROLLBACK, SNAPSHOT, RESTORE,
};
const Group = enum { text, list, hash, set, zset, key, control };
const Format = struct { group: Group, minimum: usize, maximum: ?usize = null, parity: ?usize = null };
fn commandFormat(verb: Verb) Format {
    return switch (verb) {
        .SET => .{ .group = .text, .minimum = 2 },
        .GET, .INCR, .DECR, .STRLEN => .{ .group = .text, .minimum = 1, .maximum = 1 },
        .MSET => .{ .group = .text, .minimum = 2, .parity = 0 },
        .MGET => .{ .group = .text, .minimum = 1 },
        .INCRBY, .DECRBY, .APPEND => .{ .group = .text, .minimum = 2, .maximum = 2 },
        .GETRANGE => .{ .group = .text, .minimum = 3, .maximum = 3 },
        .LPUSH, .RPUSH => .{ .group = .list, .minimum = 2 },
        .LPOP, .RPOP => .{ .group = .list, .minimum = 1, .maximum = 2 },
        .LRANGE, .LSET, .LREM, .LTRIM => .{ .group = .list, .minimum = 3, .maximum = 3 },
        .LLEN => .{ .group = .list, .minimum = 1, .maximum = 1 },
        .LINDEX => .{ .group = .list, .minimum = 2, .maximum = 2 },
        .LINSERT => .{ .group = .list, .minimum = 4, .maximum = 4 },
        .HSET => .{ .group = .hash, .minimum = 3, .parity = 1 },
        .HGET, .HEXISTS => .{ .group = .hash, .minimum = 2, .maximum = 2 },
        .HDEL => .{ .group = .hash, .minimum = 2 },
        .HGETALL, .HLEN, .HKEYS, .HVALS => .{ .group = .hash, .minimum = 1, .maximum = 1 },
        .HINCRBY => .{ .group = .hash, .minimum = 3, .maximum = 3 },
        .SADD, .SREM => .{ .group = .set, .minimum = 2 },
        .SISMEMBER => .{ .group = .set, .minimum = 2, .maximum = 2 },
        .SMEMBERS, .SCARD => .{ .group = .set, .minimum = 1, .maximum = 1 },
        .SINTER, .SUNION, .SDIFF => .{ .group = .set, .minimum = 1 },
        .SINTERSTORE, .SUNIONSTORE, .SDIFFSTORE => .{ .group = .set, .minimum = 2 },
        .ZADD => .{ .group = .zset, .minimum = 3, .parity = 1 },
        .ZSCORE, .ZRANK => .{ .group = .zset, .minimum = 2, .maximum = 2 },
        .ZINCRBY => .{ .group = .zset, .minimum = 3, .maximum = 3 },
        .ZREM => .{ .group = .zset, .minimum = 2 },
        .ZCARD => .{ .group = .zset, .minimum = 1, .maximum = 1 },
        .ZRANGE, .ZRANGEBYSCORE => .{ .group = .zset, .minimum = 3, .maximum = 4 },
        .DEL, .EXISTS => .{ .group = .key, .minimum = 1 },
        .TYPE, .KEYS, .TTL, .PERSIST, .TICK => .{ .group = .key, .minimum = 1, .maximum = 1 },
        .RENAME, .RENAMENX => .{ .group = .key, .minimum = 2, .maximum = 2 },
        .EXPIRE => .{ .group = .key, .minimum = 2, .maximum = 3 },
        .TIME, .DBSIZE, .FLUSH, .INFO => .{ .group = .key, .minimum = 0, .maximum = 0 },
        .BEGIN, .COMMIT, .ROLLBACK => .{ .group = .control, .minimum = 0, .maximum = 0 },
        .SNAPSHOT, .RESTORE => .{ .group = .control, .minimum = 1, .maximum = 1 },
    };
}

const wrong_type = "WRONGTYPE Operation against a key holding the wrong kind of value";
const not_integer = "ERR value is not an integer or out of range";
const overflow = "ERR increment or decrement would overflow";
const syntax_error = "ERR syntax error";
const positive = "ERR value is out of range, must be positive";
const no_key = "ERR no such key";

fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn upper(c: u8) u8 { return if (c >= 'a' and c <= 'z') c - 'a' + 'A' else c; }
fn lower(c: u8) u8 { return if (c >= 'A' and c <= 'Z') c - 'A' + 'a' else c; }
fn sameCase(a: Text, b: Text) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (upper(x) != upper(y)) return false;
    return true;
}
fn textIndex(items: []const Text, value: Text) ?usize {
    for (items, 0..) |item, i| if (equal(item, value)) return i;
    return null;
}
fn fieldIndex(comptime T: type, items: []const T, name: Text) ?usize {
    for (items, 0..) |item, i| if (equal(item.name, name)) return i;
    return null;
}
fn copied(comptime T: type, gpa: Allocator, items: []const T) Allocator.Error!std.ArrayList(T) {
    var result: std.ArrayList(T) = .empty;
    try result.appendSlice(gpa, items);
    return result;
}
fn lessText(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; }
fn lessField(_: void, a: Field, b: Field) bool { return lessText({}, a.name, b.name); }
fn lessScore(_: void, a: Score, b: Score) bool {
    return if (a.score == b.score) lessText({}, a.name, b.name) else a.score < b.score;
}
const Range = struct { start: usize, end: usize };
fn range(length: usize, first: i64, last: i64) Range {
    const n: i64 = @intCast(length);
    const start = @max(0, if (first < 0) first + n else first);
    const stop = @min(n - 1, if (last < 0) last + n else last);
    return if (start <= stop) .{ .start = @intCast(start), .end = @intCast(stop + 1) } else .{ .start = 0, .end = 0 };
}
fn line(out: *Writer, comptime fmt: Text, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
const Quoted = struct {
    text: Text,
    pub fn format(value: Quoted, out: *Writer) Writer.Error!void {
        try out.writeByte('"');
        for (value.text) |c| {
            if (c == '"' or c == '\\') try out.writeByte('\\');
            try out.writeByte(c);
        }
        try out.writeByte('"');
    }
};
fn decimalWidth(number: usize) usize {
    var value = number;
    var width: usize = 1;
    while (value >= 10) : (value /= 10) width += 1;
    return width;
}

fn splitArguments(gpa: Allocator, source: Text) Allocator.Error!?[]const Text {
    var words: std.ArrayList(Text) = .empty;
    var position: usize = 0;
    while (position < source.len) {
        if (source[position] == ' ') { position += 1; continue; }
        if (source[position] != '"') {
            const start = position;
            while (position < source.len and source[position] != ' ') : (position += 1) {}
            try words.append(gpa, source[start..position]);
            continue;
        }
        position += 1;
        var text: std.ArrayList(u8) = .empty;
        var closed = false;
        while (position < source.len) {
            var c = source[position];
            position += 1;
            if (c == '"') { closed = true; break; }
            if (c == '\\') {
                if (position == source.len or (source[position] != '"' and source[position] != '\\')) return null;
                c = source[position];
                position += 1;
            }
            try text.append(gpa, c);
        }
        if (!closed or (position < source.len and source[position] != ' ')) return null;
        try words.append(gpa, try text.toOwnedSlice(gpa));
    }
    return try words.toOwnedSlice(gpa);
}

const Store = struct {
    storage: Allocator,
    entries: std.ArrayList(Entry) = .empty,
    time: i64 = 0,
    transactions: std.ArrayList([]const Entry) = .empty,
    snapshots: std.ArrayList(Snapshot) = .empty,

    fn index(store: *const Store, key: Text) ?usize {
        for (store.entries.items, 0..) |entry, i| if (equal(entry.key, key)) return i;
        return null;
    }
    fn get(store: *const Store, key: Text) ?Entry {
        return if (store.index(key)) |i| store.entries.items[i] else null;
    }
    fn remove(store: *Store, key: Text) bool {
        const i = store.index(key) orelse return false;
        _ = store.entries.orderedRemove(i);
        return true;
    }
    fn put(store: *Store, key: Text, value: Value, expiry: ?i64) Allocator.Error!void {
        if (value.empty()) { _ = store.remove(key); return; }
        const entry: Entry = .{ .key = key, .value = try value.retain(store.storage), .expiry = expiry };
        if (store.index(key)) |i| store.entries.items[i] = entry else try store.entries.append(store.storage, entry);
    }
    fn update(store: *Store, key: Text, value: Value) Allocator.Error!void {
        const expiry = if (store.get(key)) |entry| entry.expiry else null;
        try store.put(key, value, expiry);
    }
    fn purge(store: *Store) usize {
        var i: usize = 0;
        var removed: usize = 0;
        while (i < store.entries.items.len) {
            const expired = if (store.entries.items[i].expiry) |expiry| expiry <= store.time else false;
            if (expired) { _ = store.entries.orderedRemove(i); removed += 1; } else i += 1;
        }
        return removed;
    }
    // Registered values are immutable; each saved database owns its entry array.
    fn copy(store: *const Store) Allocator.Error![]const Entry { return store.storage.dupe(Entry, store.entries.items); }
    fn restore(store: *Store, entries: []const Entry) Allocator.Error!void {
        store.entries.clearRetainingCapacity();
        try store.entries.appendSlice(store.storage, entries);
        _ = store.purge();
    }
};

const PatternKind = enum { literal, any, star, class };
const PatternPart = struct {
    kind: PatternKind,
    literal: u8 = 0,
    characters: [128]bool = @splat(false),
    negated: bool = false,
};
fn matches(gpa: Allocator, parts: []const PatternPart, value: Text) Allocator.Error!bool {
    var previous = try gpa.alloc(bool, value.len + 1);
    @memset(previous, false);
    previous[0] = true;
    for (parts) |part| {
        const current = try gpa.alloc(bool, value.len + 1);
        @memset(current, false);
        if (part.kind == .star) {
            current[0] = previous[0];
            for (1..current.len) |i| current[i] = previous[i] or current[i - 1];
        } else {
            for (value, 0..) |c, i| {
                const accepts = part.kind == .any or (if (part.kind == .literal) part.literal == c else part.characters[c] != part.negated);
                current[i + 1] = previous[i] and accepts;
            }
        }
        previous = current;
    }
    return previous[value.len];
}
const Bound = union(enum) {
    negative_infinity,
    positive_infinity,
    finite: struct { value: i64, inclusive: bool },
    fn accepts(bound: Bound, score: i64, is_lower: bool) bool {
        return switch (bound) {
            .negative_infinity => is_lower,
            .positive_infinity => !is_lower,
            .finite => |x| if (is_lower) (if (x.inclusive) score >= x.value else score > x.value) else (if (x.inclusive) score <= x.value else score < x.value),
        };
    }
};

const Session = struct {
    store: *Store,
    gpa: Allocator,
    out: *Writer,
    problem: Text = "",

    fn fail(session: *Session, message: Text) error{Invalid} { session.problem = message; return error.Invalid; }
    fn number(session: *Session, source: Text, message: Text) Error!i64 {
        if (equal(source, "0")) return 0;
        const start: usize = if (source.len != 0 and source[0] == '-') 1 else 0;
        const digits = source.len - start;
        if (digits < 1 or digits > 9 or source[start] < '1' or source[start] > '9') return session.fail(message);
        var value: i64 = 0;
        for (source[start..]) |c| {
            if (c < '0' or c > '9') return session.fail(message);
            value = value * 10 + c - '0';
        }
        return if (start == 0) value else -value;
    }
    fn increment(session: *Session, value: i64, delta: i64) Error!i64 {
        const result = value + delta;
        if (result < -999999999 or result > 999999999) return session.fail(overflow);
        return result;
    }
    fn getValue(session: *Session, key: Text, kind: Kind) Error!?Value {
        const entry = session.store.get(key) orelse return null;
        if (std.meta.activeTag(entry.value) != kind) return session.fail(wrong_type);
        return entry.value;
    }
    fn readText(session: *Session, key: Text) Error!Text {
        return if (try session.getValue(key, .string)) |value| value.string else "";
    }
    fn readList(session: *Session, key: Text) Error![]const Text {
        return if (try session.getValue(key, .list)) |value| value.list else &.{};
    }
    fn readHash(session: *Session, key: Text) Error![]const Field {
        return if (try session.getValue(key, .hash)) |value| value.hash else &.{};
    }
    fn readMembers(session: *Session, key: Text) Error![]const Text {
        return if (try session.getValue(key, .set)) |value| value.set else &.{};
    }
    fn readScores(session: *Session, key: Text) Error![]const Score {
        return if (try session.getValue(key, .zset)) |value| value.zset else &.{};
    }
    fn integerReply(session: *Session, value: anytype) Writer.Error!void { try line(session.out, "(integer) {d}", .{value}); }
    fn textReply(session: *Session, value: ?Text) Writer.Error!void {
        if (value) |content| try line(session.out, "{f}", .{Quoted{ .text = content }}) else try line(session.out, "(nil)", .{});
    }
    fn arrayReply(session: *Session, values: anytype) Error!void {
        if (values.len == 0) return line(session.out, "(empty array)", .{});
        const width = decimalWidth(values.len);
        for (values, 0..) |value, i| {
            try session.out.splatByteAll(' ', width - decimalWidth(i + 1));
            try session.out.print("{d}) ", .{i + 1});
            try session.textReply(value);
        }
    }
    fn sorted(session: *Session, values: []const Text) Allocator.Error![]Text {
        const result = try session.gpa.dupe(Text, values);
        std.sort.heap(Text, result, {}, lessText);
        return result;
    }
    fn parsePattern(session: *Session, source: Text) Error![]const PatternPart {
        var parts: std.ArrayList(PatternPart) = .empty;
        var i: usize = 0;
        while (i < source.len) : (i += 1) {
            const c = source[i];
            if (c == '\\') {
                i += 1;
                if (i == source.len) return session.fail("ERR invalid pattern");
                try parts.append(session.gpa, .{ .kind = .literal, .literal = source[i] });
            } else if (c == '[') {
                const relative = std.mem.findScalar(u8, source[i + 1 ..], ']') orelse return session.fail("ERR invalid pattern");
                const end = i + 1 + relative;
                var j = i + 1;
                var part: PatternPart = .{ .kind = .class };
                part.negated = j < end and source[j] == '^';
                if (part.negated) j += 1;
                if (j == end) return session.fail("ERR invalid pattern");
                while (j < end) {
                    if (j + 2 < end and source[j + 1] == '-') {
                        const first = @min(source[j], source[j + 2]);
                        const last: usize = @max(source[j], source[j + 2]);
                        for (first..last + 1) |code| part.characters[code] = true;
                        j += 3;
                    } else { part.characters[source[j]] = true; j += 1; }
                }
                try parts.append(session.gpa, part);
                i = end;
            } else try parts.append(session.gpa, switch (c) {
                '*' => .{ .kind = .star },
                '?' => .{ .kind = .any },
                else => .{ .kind = .literal, .literal = c },
            });
        }
        return parts.toOwnedSlice(session.gpa);
    }
    fn scoreBound(session: *Session, word: Text) Error!Bound {
        if (equal(word, "-inf")) return .negative_infinity;
        if (equal(word, "+inf")) return .positive_infinity;
        const inclusive = word.len == 0 or word[0] != '(';
        return .{ .finite = .{
            .value = try session.number(if (inclusive) word else word[1..], "ERR min or max is not a float"),
            .inclusive = inclusive,
        } };
    }

    fn textCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        const key = args[0];
        switch (verb) {
            .SET => {
                var options: [5]bool = @splat(false);
                const names = [_]Text{ "NX", "XX", "EX", "KEEPTTL", "GET" };
                var seconds_word: ?Text = null;
                var i: usize = 2;
                while (i < args.len) : (i += 1) {
                    var selected: ?usize = null;
                    for (names, 0..) |name, j| if (sameCase(args[i], name)) { selected = j; break; };
                    const option = selected orelse return session.fail(syntax_error);
                    if (options[option]) return session.fail(syntax_error);
                    options[option] = true;
                    if (option == 2) {
                        i += 1;
                        if (i == args.len) return session.fail(syntax_error);
                        seconds_word = args[i];
                    }
                }
                if ((options[0] and options[1]) or (options[2] and options[3])) return session.fail(syntax_error);
                var expiry: ?i64 = null;
                if (seconds_word) |word| {
                    const seconds = try session.number(word, not_integer);
                    if (seconds <= 0) return session.fail("ERR invalid expire time in 'set' command");
                    expiry = store.time + seconds;
                }
                const entry = store.get(key);
                var old: ?Text = null;
                if (options[4]) {
                    const value = try session.readText(key);
                    if (entry != null) old = value;
                }
                if (options[3] and entry != null) expiry = entry.?.expiry;
                const changed = !(options[0] and entry != null) and !(options[1] and entry == null);
                if (changed) try store.put(key, .{ .string = args[1] }, expiry);
                if (options[4]) return session.textReply(old);
                if (changed) return line(session.out, "OK", .{});
                return session.textReply(null);
            },
            .MSET => {
                var i: usize = 0;
                while (i < args.len) : (i += 2) try store.put(args[i], .{ .string = args[i + 1] }, null);
                return line(session.out, "OK", .{});
            },
            .MGET => {
                var output: std.ArrayList(?Text) = .empty;
                for (args) |name| {
                    const item: ?Text = if (store.get(name)) |entry| switch (entry.value) {
                        .string => |value| value,
                        else => null,
                    } else null;
                    try output.append(session.gpa, item);
                }
                return session.arrayReply(output.items);
            },
            .INCR, .DECR, .INCRBY, .DECRBY => {
                var delta: i64 = if (args.len == 2) try session.number(args[1], not_integer) else 1;
                if (verb == .DECR or verb == .DECRBY) delta = -delta;
                const value = try session.readText(key);
                const old = if (store.get(key) != null) try session.number(value, not_integer) else 0;
                const result = try session.increment(old, delta);
                try store.update(key, .{ .string = try std.fmt.allocPrint(store.storage, "{d}", .{result}) });
                return session.integerReply(result);
            },
            .GETRANGE => {
                const start = try session.number(args[1], not_integer);
                const stop = try session.number(args[2], not_integer);
                const value = try session.readText(key);
                const selected = range(value.len, start, stop);
                return session.textReply(value[selected.start..selected.end]);
            },
            else => {
                const value = try session.readText(key);
                if (verb == .GET) return session.textReply(if (store.get(key) != null) value else null);
                if (verb == .STRLEN) return session.integerReply(value.len);
                const joined = try std.fmt.allocPrint(store.storage, "{s}{s}", .{ value, args[1] });
                try store.update(key, .{ .string = joined });
                return session.integerReply(joined.len);
            },
        }
    }

    fn listCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        const key = args[0];
        switch (verb) {
            .LPOP, .RPOP => {
                const counted = args.len == 2;
                const requested = if (counted) try session.number(args[1], positive) else 1;
                if (requested < 0) return session.fail(positive);
                var values = try copied(Text, session.gpa, try session.readList(key));
                if (store.get(key) == null) return session.textReply(null);
                const count: usize = @min(@as(usize, @intCast(requested)), values.items.len);
                var removed: std.ArrayList(Text) = .empty;
                for (0..count) |_| {
                    const at = if (verb == .LPOP) 0 else values.items.len - 1;
                    try removed.append(session.gpa, values.orderedRemove(at));
                }
                try store.update(key, .{ .list = values.items });
                if (counted) return session.arrayReply(removed.items);
                return session.textReply(removed.items[0]);
            },
            .LRANGE, .LTRIM => {
                const start = try session.number(args[1], not_integer);
                const stop = try session.number(args[2], not_integer);
                const values = try session.readList(key);
                const selected = range(values.len, start, stop);
                const kept = values[selected.start..selected.end];
                if (verb == .LRANGE) return session.arrayReply(kept);
                try store.update(key, .{ .list = kept });
                return line(session.out, "OK", .{});
            },
            .LINDEX, .LSET => {
                var at = try session.number(args[1], not_integer);
                const values = try session.readList(key);
                if (at < 0) at += @intCast(values.len);
                const inside = at >= 0 and at < @as(i64, @intCast(values.len));
                if (verb == .LINDEX) return session.textReply(if (inside) values[@intCast(at)] else null);
                if (store.get(key) == null) return session.fail(no_key);
                if (!inside) return session.fail("ERR index out of range");
                const changed = try session.gpa.dupe(Text, values);
                changed[@intCast(at)] = args[2];
                try store.update(key, .{ .list = changed });
                return line(session.out, "OK", .{});
            },
            .LREM => {
                const count = try session.number(args[1], not_integer);
                const values = try session.readList(key);
                const limit: usize = if (count == 0) values.len else @intCast(@abs(count));
                const marked = try session.gpa.alloc(bool, values.len);
                @memset(marked, false);
                var removed: usize = 0;
                for (0..values.len) |i| {
                    const at = if (count < 0) values.len - i - 1 else i;
                    if (equal(values[at], args[2]) and removed < limit) { marked[at] = true; removed += 1; }
                }
                var kept: std.ArrayList(Text) = .empty;
                for (values, marked) |value, erase| if (!erase) try kept.append(session.gpa, value);
                try store.update(key, .{ .list = kept.items });
                return session.integerReply(removed);
            },
            .LINSERT => {
                const before = sameCase(args[1], "BEFORE");
                if (!before and !sameCase(args[1], "AFTER")) return session.fail(syntax_error);
                var values = try copied(Text, session.gpa, try session.readList(key));
                if (store.get(key) == null) return session.integerReply(@as(usize, 0));
                const pivot = textIndex(values.items, args[2]) orelse return session.integerReply(@as(i64, -1));
                try values.insert(session.gpa, pivot + @intFromBool(!before), args[3]);
                try store.update(key, .{ .list = values.items });
                return session.integerReply(values.items.len);
            },
            else => {
                var values = try copied(Text, session.gpa, try session.readList(key));
                if (verb == .LLEN) return session.integerReply(values.items.len);
                for (args[1..]) |value| {
                    if (verb == .LPUSH) try values.insert(session.gpa, 0, value) else try values.append(session.gpa, value);
                }
                try store.update(key, .{ .list = values.items });
                return session.integerReply(values.items.len);
            },
        }
    }

    fn hashCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        const key = args[0];
        if (verb == .HINCRBY) {
            const delta = try session.number(args[2], not_integer);
            var fields = try copied(Field, session.gpa, try session.readHash(key));
            const found = fieldIndex(Field, fields.items, args[1]);
            const old = if (found) |i| try session.number(fields.items[i].value, "ERR hash value is not an integer") else 0;
            const result = try session.increment(old, delta);
            const value = try std.fmt.allocPrint(store.storage, "{d}", .{result});
            if (found) |i| fields.items[i].value = value else try fields.append(session.gpa, .{ .name = args[1], .value = value });
            try store.update(key, .{ .hash = fields.items });
            return session.integerReply(result);
        }
        var fields = try copied(Field, session.gpa, try session.readHash(key));
        switch (verb) {
            .HSET => {
                var added: usize = 0;
                var i: usize = 1;
                while (i < args.len) : (i += 2) {
                    if (fieldIndex(Field, fields.items, args[i])) |at| fields.items[at].value = args[i + 1] else {
                        try fields.append(session.gpa, .{ .name = args[i], .value = args[i + 1] });
                        added += 1;
                    }
                }
                try store.update(key, .{ .hash = fields.items });
                return session.integerReply(added);
            },
            .HGET => return session.textReply(if (fieldIndex(Field, fields.items, args[1])) |i| fields.items[i].value else null),
            .HDEL => {
                var removed: usize = 0;
                for (args[1..]) |field| if (fieldIndex(Field, fields.items, field)) |i| { _ = fields.orderedRemove(i); removed += 1; };
                try store.update(key, .{ .hash = fields.items });
                return session.integerReply(removed);
            },
            .HLEN => return session.integerReply(fields.items.len),
            .HEXISTS => return session.integerReply(@intFromBool(fieldIndex(Field, fields.items, args[1]) != null)),
            else => {
                std.sort.heap(Field, fields.items, {}, lessField);
                var output: std.ArrayList(Text) = .empty;
                for (fields.items) |field| {
                    if (verb != .HVALS) try output.append(session.gpa, field.name);
                    if (verb != .HKEYS) try output.append(session.gpa, field.value);
                }
                return session.arrayReply(output.items);
            },
        }
    }

    fn setCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        const storing = verb == .SINTERSTORE or verb == .SUNIONSTORE or verb == .SDIFFSTORE;
        const operation: Verb = switch (verb) { .SINTERSTORE => .SINTER, .SUNIONSTORE => .SUNION, .SDIFFSTORE => .SDIFF, else => verb };
        if (operation == .SINTER or operation == .SUNION or operation == .SDIFF) {
            var sources: std.ArrayList([]const Text) = .empty;
            const first_source: usize = @intFromBool(storing);
            for (args[first_source..]) |key| try sources.append(session.gpa, try session.readMembers(key));
            var result = try copied(Text, session.gpa, sources.items[0]);
            for (sources.items[1..]) |source| {
                if (operation == .SUNION) {
                    for (source) |member| if (textIndex(result.items, member) == null) try result.append(session.gpa, member);
                } else {
                    var i: usize = 0;
                    while (i < result.items.len) {
                        const present = textIndex(source, result.items[i]) != null;
                        if ((operation == .SINTER and !present) or (operation == .SDIFF and present)) {
                            _ = result.orderedRemove(i);
                        } else i += 1;
                    }
                }
            }
            if (storing) {
                try store.put(args[0], .{ .set = result.items }, null);
                return session.integerReply(result.items.len);
            }
            return session.arrayReply(try session.sorted(result.items));
        }
        var members = try copied(Text, session.gpa, try session.readMembers(args[0]));
        if (verb == .SCARD) return session.integerReply(members.items.len);
        if (verb == .SMEMBERS) return session.arrayReply(try session.sorted(members.items));
        if (verb == .SISMEMBER) return session.integerReply(@intFromBool(textIndex(members.items, args[1]) != null));
        var changed: usize = 0;
        for (args[1..]) |member| {
            const found = textIndex(members.items, member);
            if (verb == .SADD) {
                if (found == null) { try members.append(session.gpa, member); changed += 1; }
            } else if (found) |i| { _ = members.orderedRemove(i); changed += 1; }
        }
        try store.update(args[0], .{ .set = members.items });
        return session.integerReply(changed);
    }

    fn sortedSetCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        const key = args[0];
        if (verb == .ZADD) {
            var numbers: std.ArrayList(i64) = .empty;
            var i: usize = 1;
            while (i < args.len) : (i += 2) try numbers.append(session.gpa, try session.number(args[i], not_integer));
            var members = try copied(Score, session.gpa, try session.readScores(key));
            var added: usize = 0;
            for (numbers.items, 0..) |score, j| {
                const name = args[2 * j + 2];
                if (fieldIndex(Score, members.items, name)) |at| members.items[at].score = score else {
                    try members.append(session.gpa, .{ .name = name, .score = score });
                    added += 1;
                }
            }
            try store.update(key, .{ .zset = members.items });
            return session.integerReply(added);
        }
        if (verb == .ZINCRBY) {
            const delta = try session.number(args[1], not_integer);
            var members = try copied(Score, session.gpa, try session.readScores(key));
            const found = fieldIndex(Score, members.items, args[2]);
            const result = try session.increment(if (found) |i| members.items[i].score else 0, delta);
            if (found) |i| members.items[i].score = result else try members.append(session.gpa, .{ .name = args[2], .score = result });
            try store.update(key, .{ .zset = members.items });
            return session.textReply(try std.fmt.allocPrint(session.gpa, "{d}", .{result}));
        }
        const by_index = verb == .ZRANGE;
        const by_score = verb == .ZRANGEBYSCORE;
        const with_scores = args.len == 4;
        var start: i64 = 0;
        var stop: i64 = 0;
        var minimum: Bound = .negative_infinity;
        var maximum: Bound = .positive_infinity;
        if (by_index or by_score) {
            if (with_scores and !sameCase(args[3], "WITHSCORES")) return session.fail(syntax_error);
            if (by_index) {
                start = try session.number(args[1], not_integer);
                stop = try session.number(args[2], not_integer);
            } else {
                minimum = try session.scoreBound(args[1]);
                maximum = try session.scoreBound(args[2]);
            }
        }
        var members = try copied(Score, session.gpa, try session.readScores(key));
        if (verb == .ZSCORE) {
            const found = fieldIndex(Score, members.items, args[1]) orelse return session.textReply(null);
            return session.textReply(try std.fmt.allocPrint(session.gpa, "{d}", .{members.items[found].score}));
        }
        if (verb == .ZREM) {
            var removed: usize = 0;
            for (args[1..]) |member| if (fieldIndex(Score, members.items, member)) |i| { _ = members.orderedRemove(i); removed += 1; };
            try store.update(key, .{ .zset = members.items });
            return session.integerReply(removed);
        }
        if (verb == .ZCARD) return session.integerReply(members.items.len);
        std.sort.heap(Score, members.items, {}, lessScore);
        if (verb == .ZRANK) {
            const rank = fieldIndex(Score, members.items, args[1]) orelse return session.textReply(null);
            return session.integerReply(rank);
        }
        var ordered: []const Score = members.items;
        if (by_index) {
            const selected = range(ordered.len, start, stop);
            ordered = ordered[selected.start..selected.end];
        }
        var output: std.ArrayList(Text) = .empty;
        for (ordered) |member| {
            if (by_score and (!minimum.accepts(member.score, true) or !maximum.accepts(member.score, false))) continue;
            try output.append(session.gpa, member.name);
            if (with_scores) try output.append(session.gpa, try std.fmt.allocPrint(session.gpa, "{d}", .{member.score}));
        }
        return session.arrayReply(output.items);
    }

    fn keyCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        switch (verb) {
            .DEL, .EXISTS => {
                var count: usize = 0;
                for (args) |key| count += @intFromBool(if (verb == .DEL) store.remove(key) else store.get(key) != null);
                return session.integerReply(count);
            },
            .KEYS => {
                const parts = try session.parsePattern(args[0]);
                var keys: std.ArrayList(Text) = .empty;
                for (store.entries.items) |entry| if (try matches(session.gpa, parts, entry.key)) try keys.append(session.gpa, entry.key);
                return session.arrayReply(try session.sorted(keys.items));
            },
            .EXPIRE => {
                var condition: usize = 0;
                if (args.len == 3) {
                    const names = [_]Text{ "NX", "XX", "GT", "LT" };
                    for (names, 0..) |name, i| if (sameCase(args[2], name)) { condition = i + 1; break; };
                    if (condition == 0) return session.fail(try std.fmt.allocPrint(session.gpa, "ERR Unsupported option {s}", .{args[2]}));
                }
                const seconds = try session.number(args[1], not_integer);
                const at = store.index(args[0]) orelse return session.integerReply(@as(usize, 0));
                const old = store.entries.items[at].expiry;
                const expiry = store.time + seconds;
                const rejected = switch (condition) {
                    1 => old != null,
                    2 => old == null,
                    3 => old == null or expiry <= old.?,
                    4 => old != null and expiry >= old.?,
                    else => false,
                };
                if (rejected) return session.integerReply(@as(usize, 0));
                if (seconds <= 0) { _ = store.entries.orderedRemove(at); } else store.entries.items[at].expiry = expiry;
                return session.integerReply(@as(usize, 1));
            },
            .TICK => {
                const ticks = try session.number(args[0], not_integer);
                if (ticks <= 0) return session.fail(positive);
                store.time += ticks;
                return session.integerReply(store.purge());
            },
            .TIME => return session.integerReply(store.time),
            .DBSIZE => return session.integerReply(store.entries.items.len),
            .FLUSH => {
                store.entries.clearRetainingCapacity();
                return line(session.out, "OK", .{});
            },
            .INFO => {
                var counts: [5]usize = @splat(0);
                var expires: usize = 0;
                for (store.entries.items) |entry| {
                    counts[@intFromEnum(std.meta.activeTag(entry.value))] += 1;
                    expires += @intFromBool(entry.expiry != null);
                }
                return line(session.out, "keys={d},expires={d},string={d},list={d},hash={d},set={d},zset={d},time={d},depth={d},snapshots={d}",
                    .{ store.entries.items.len, expires, counts[0], counts[1], counts[2], counts[3], counts[4], store.time, store.transactions.items.len, store.snapshots.items.len });
            },
            else => {
                const key = args[0];
                const entry = store.get(key);
                if (verb == .TYPE) return line(session.out, "{s}", .{if (entry) |value| @tagName(value.value) else "none"});
                if (verb == .TTL) {
                    const result: i64 = if (entry) |value| (if (value.expiry) |expiry| expiry - store.time else -1) else -2;
                    return session.integerReply(result);
                }
                if (verb == .PERSIST) {
                    const at = store.index(key) orelse return session.integerReply(@as(usize, 0));
                    if (store.entries.items[at].expiry == null) return session.integerReply(@as(usize, 0));
                    store.entries.items[at].expiry = null;
                    return session.integerReply(@as(usize, 1));
                }
                const original = entry orelse return session.fail(no_key);
                if (verb == .RENAMENX and store.get(args[1]) != null) return session.integerReply(@as(usize, 0));
                if (!equal(key, args[1])) {
                    try store.put(args[1], original.value, original.expiry);
                    _ = store.remove(key);
                }
                if (verb == .RENAME) return line(session.out, "OK", .{});
                return session.integerReply(@as(usize, 1));
            },
        }
    }

    fn controlCommand(session: *Session, verb: Verb, args: []const Text) Error!void {
        const store = session.store;
        switch (verb) {
            .BEGIN => try store.transactions.append(store.storage, try store.copy()),
            .COMMIT, .ROLLBACK => {
                const saved = store.transactions.pop() orelse return session.fail("ERR no transaction");
                if (verb == .ROLLBACK) try store.restore(saved);
            },
            .SNAPSHOT => {
                const saved = try store.copy();
                if (fieldIndex(Snapshot, store.snapshots.items, args[0])) |i| store.snapshots.items[i].entries = saved else
                    try store.snapshots.append(store.storage, .{ .name = args[0], .entries = saved });
            },
            .RESTORE => {
                const i = fieldIndex(Snapshot, store.snapshots.items, args[0]) orelse return session.fail("ERR no such snapshot");
                try store.restore(store.snapshots.items[i].entries);
            },
            else => unreachable,
        }
        try line(session.out, "OK", .{});
    }

    fn execute(session: *Session, source: Text) Error!void {
        const words = (try splitArguments(session.store.storage, source)) orelse return line(session.out, "Invalid argument(s)", .{});
        var buffer: [200]u8 = undefined;
        for (words[0], 0..) |c, i| buffer[i] = upper(c);
        const verb = std.meta.stringToEnum(Verb, buffer[0..words[0].len]) orelse
            return session.fail(try std.fmt.allocPrint(session.gpa, "ERR unknown command '{s}'", .{words[0]}));
        const specification = commandFormat(verb);
        const args = words[1..];
        const wrong_count = args.len < specification.minimum or
            (if (specification.maximum) |maximum| args.len > maximum else false) or
            (if (specification.parity) |parity| args.len % 2 != parity else false);
        if (wrong_count) {
            const name = @tagName(verb);
            for (name, 0..) |c, i| buffer[i] = lower(c);
            return session.fail(try std.fmt.allocPrint(session.gpa, "ERR wrong number of arguments for '{s}' command", .{buffer[0..name.len]}));
        }
        switch (specification.group) {
            .text => try session.textCommand(verb, args),
            .list => try session.listCommand(verb, args),
            .hash => try session.hashCommand(verb, args),
            .set => try session.setCommand(verb, args),
            .zset => try session.sortedSetCommand(verb, args),
            .key => try session.keyCommand(verb, args),
            .control => try session.controlCommand(verb, args),
        }
    }
};

fn readLine(reader: *std.Io.Reader, gpa: Allocator) !?Text {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = reader.streamDelimiterEnding(&buffer.writer, '\n') catch |err| switch (err) {
        error.EndOfStream => {
            if (buffer.written().len == 0) return null;
            return try buffer.toOwnedSlice();
        },
        else => return err,
    };
    reader.toss(1);
    return try buffer.toOwnedSlice();
}
pub fn main(init: std.process.Init) !void {
    var storage: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer storage.deinit();
    const persistent = storage.allocator();
    var store: Store = .{ .storage = persistent };
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const first = std.mem.trim(u8, (try readLine(&input.interface, persistent)).?, "\r");
    const count = try std.fmt.parseInt(usize, first, 10);
    for (0..count) |_| {
        const source = std.mem.trim(u8, (try readLine(&input.interface, persistent)).?, "\r");
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .store = &store, .gpa = gpa, .out = &response.writer };
        session.execute(source) catch |err| switch (err) {
            error.Invalid => {
                try line(&output.interface, "(error) {s}", .{session.problem});
                try output.interface.flush();
                continue;
            },
            else => return err,
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
