const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Mode = enum {
    CHAIN,
    LINEAR,
    QUADRATIC,
    DOUBLE,
    ROBINHOOD,
    CUCKOO,
    fn parts(mode: Mode) usize {
        return if (mode == .CUCKOO) 2 else 1;
    }
    fn usesTombstones(mode: Mode) bool {
        return mode == .LINEAR or mode == .QUADRATIC or mode == .DOUBLE;
    }
};
const Command = enum { CREATE, MAXLOAD, MINLOAD, TRACE, HASH, PUT, ADD, GET, DEL, PROBE, GEN, GENDEL, RESIZE, CONVERT, CLEAR, DUMP, MAP, STATS, KEYS, TOP, SCAN, CLUSTERS, DIST, COMPARE, BENCH };

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn integer(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
fn signedInteger(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void {
    try out.print(fmt ++ "\n", args);
}
fn prime(value: usize) usize {
    var candidate = @max(value, 2);
    while (true) : (candidate += 1) {
        var valid = true;
        var divisor: usize = 2;
        while (divisor * divisor <= candidate) : (divisor += 1) {
            if (candidate % divisor == 0) {
                valid = false;
                break;
            }
        }
        if (valid) return candidate;
    }
}
fn gauge(value: usize) u8 {
    return if (value >= 10) '+' else '0' + @as(u8, @intCast(value));
}
const Ratio = struct {
    hundredths: u64,
    fn init(numerator: u64, denominator: u64) Ratio {
        return .{ .hundredths = if (denominator == 0) 0 else 100 * numerator / denominator };
    }
    pub fn format(value: Ratio, out: *Writer) Writer.Error!void {
        try out.print("{d}.{d:0>2}", .{ value.hundredths / 100, value.hundredths % 100 });
    }
};
const Key = struct {
    bytes: [10]u8 = undefined,
    len: usize = 0,
    fn init(text_value: []const u8) Key {
        var key: Key = .{ .len = text_value.len };
        @memcpy(key.bytes[0..text_value.len], text_value);
        return key;
    }
    fn text(key: *const Key) []const u8 {
        return key.bytes[0..key.len];
    }
    fn eql(a: Key, b: Key) bool {
        return equal(a.text(), b.text());
    }
    fn hash(key: Key, base: usize, modulus: usize) usize {
        var value: usize = 0;
        for (key.text()) |character| value = (value * base + character) % modulus;
        return value;
    }
    fn less(_: void, a: Key, b: Key) bool {
        return std.mem.order(u8, a.text(), b.text()) == .lt;
    }
    pub fn format(key: Key, out: *Writer) Writer.Error!void {
        try out.writeAll(key.text());
    }
};
const Item = struct {
    key: Key,
    value: i64,
    fn less(_: void, a: Item, b: Item) bool {
        return Key.less({}, a.key, b.key);
    }
    pub fn format(item: Item, out: *Writer) Writer.Error!void {
        try out.print("{f}={d}", .{ item.key, item.value });
    }
};
const Slot = struct {
    item: ?Item = null,
    deleted: bool = false,
    fn empty(slot: Slot) bool {
        return slot.item == null and !slot.deleted;
    }
    fn content(slot: Slot, out: *Writer) Writer.Error!void {
        if (slot.item) |item| try out.print("{f}", .{item.key}) else try out.writeAll(if (slot.deleted) "D" else "-");
    }
};
const Position = struct {
    mode: Mode,
    capacity: usize,
    index: usize,
    pub fn format(position: Position, out: *Writer) Writer.Error!void {
        if (position.mode == .CUCKOO) {
            try out.print("T{d}.{d}", .{ position.index / position.capacity + 1, position.index % position.capacity });
        } else try out.print("{d}", .{position.index});
    }
};
const Probe = struct { index: usize, slot: Slot };
const Search = struct {
    item: ?Item = null,
    position: usize = 0,
    chain_index: usize = 0,
    probes: usize = 0,
    available: ?usize = null,
    path: std.ArrayList(Probe) = .empty,
    fn examine(search: *Search, gpa: Allocator, index: usize, slot: Slot, trace: bool) Allocator.Error!void {
        search.probes += 1;
        if (trace) try search.path.append(gpa, .{ .index = index, .slot = slot });
    }
    fn found(search: *Search, item: Item, position: usize, chain_index: usize) void {
        search.item = item;
        search.position = position;
        search.chain_index = chain_index;
    }
};
const Move = struct { key: Key, from: usize, to: ?usize = null };
const Placement = struct {
    success: bool = false,
    reused: bool = false,
    position: ?usize = null,
    shifted: usize = 0,
    kicks: usize = 0,
    homeless: ?Item = null,
    moves: std.ArrayList(Move) = .empty,
};
const Removal = struct { shifted: usize = 0, moves: std.ArrayList(Move) = .empty };
const Counters = struct {
    probes: u64 = 0,
    rehashes: u64 = 0,
    inserts: u64 = 0,
    updates: u64 = 0,
    hits: u64 = 0,
    misses: u64 = 0,
    deletes: u64 = 0,
    absent: u64 = 0,
};
const Cost = struct {
    key: Key,
    probes: usize,
    position: usize,
    fn less(_: void, a: Cost, b: Cost) bool {
        return if (a.probes != b.probes) a.probes > b.probes else Key.less({}, a.key, b.key);
    }
};
const Metrics = struct { longest: usize, average: Ratio };
const Generator = struct {
    state: u64,
    length: usize,
    fn next(generator: *Generator) Key {
        var key: Key = .{ .len = generator.length };
        for (key.bytes[0..key.len]) |*character| {
            generator.state = 48271 * generator.state % 2147483647;
            character.* = 'a' + @as(u8, @intCast(generator.state % 26));
        }
        return key;
    }
};

const Table = struct {
    allocator: Allocator,
    mode: Mode,
    capacity: usize,
    size: usize = 0,
    tombstones: usize = 0,
    counters: Counters = .{},
    buckets: []std.ArrayList(Item) = &.{},
    slots: []Slot = &.{},

    fn init(allocator: Allocator, mode: Mode, capacity: usize) Allocator.Error!Table {
        var table: Table = .{ .allocator = allocator, .mode = mode, .capacity = capacity };
        if (mode == .CHAIN) {
            table.buckets = try allocator.alloc(std.ArrayList(Item), capacity);
            @memset(table.buckets, .empty);
        } else {
            table.slots = try allocator.alloc(Slot, table.slotCount());
            @memset(table.slots, .{});
        }
        return table;
    }
    fn deinit(table: *Table) void {
        for (table.buckets) |*bucket| bucket.deinit(table.allocator);
        table.allocator.free(table.buckets);
        table.allocator.free(table.slots);
    }
    fn slotCount(table: *const Table) usize {
        return table.capacity * table.mode.parts();
    }
    fn position(table: *const Table, index: usize) Position {
        return .{ .mode = table.mode, .capacity = table.capacity, .index = index };
    }
    fn distance(table: *const Table, key: Key, index: usize) usize {
        return (index + table.capacity - key.hash(31, table.capacity)) % table.capacity;
    }
    fn items(table: *const Table, gpa: Allocator) Allocator.Error![]Item {
        var result: std.ArrayList(Item) = .empty;
        if (table.mode == .CHAIN) {
            for (table.buckets) |bucket| try result.appendSlice(gpa, bucket.items);
        } else {
            for (table.slots) |slot| if (slot.item) |item| try result.append(gpa, item);
        }
        return result.items;
    }
    fn search(table: *const Table, gpa: Allocator, key: Key, trace: bool) Allocator.Error!Search {
        var result: Search = .{};
        const first = key.hash(31, table.capacity);
        if (table.mode == .CHAIN) {
            for (table.buckets[first].items, 0..) |item, i| {
                try result.examine(gpa, first, .{ .item = item }, trace);
                if (item.key.eql(key)) {
                    result.found(item, first, i);
                    break;
                }
            }
            return result;
        }
        if (table.mode == .CUCKOO) {
            for ([_]usize{ first, table.capacity + key.hash(37, table.capacity) }) |index| {
                const slot = table.slots[index];
                try result.examine(gpa, index, slot, trace);
                if (slot.item) |item| if (item.key.eql(key)) {
                    result.found(item, index, 0);
                    break;
                };
            }
            return result;
        }
        const step: usize = if (table.mode == .DOUBLE) 1 + key.hash(37, table.capacity - 1) else 1;
        for (0..table.capacity) |i| {
            const offset = if (table.mode == .QUADRATIC) i * i else i * step;
            const index = (first + offset) % table.capacity;
            const slot = table.slots[index];
            try result.examine(gpa, index, slot, trace);
            if (slot.empty()) {
                if (result.available == null) result.available = index;
                break;
            }
            if (slot.deleted) {
                if (result.available == null) result.available = index;
                continue;
            }
            const item = slot.item.?;
            if (item.key.eql(key)) {
                result.found(item, index, 0);
                break;
            }
            if (table.mode == .ROBINHOOD and table.distance(item.key, index) < i) break;
        }
        return result;
    }
    fn place(table: *Table, gpa: Allocator, item: Item, initial: ?Search, trace: bool) Allocator.Error!Placement {
        var result: Placement = .{};
        if (table.mode == .CHAIN) {
            const index = item.key.hash(31, table.capacity);
            try table.buckets[index].append(table.allocator, item);
            result.position = index;
            result.success = true;
            return result;
        }
        if (table.mode.usesTombstones()) {
            const found = initial orelse try table.search(gpa, item.key, false);
            const index = found.available orelse {
                result.homeless = item;
                return result;
            };
            result.position = index;
            result.reused = table.slots[index].deleted;
            table.slots[index] = .{ .item = item };
            if (result.reused) table.tombstones -= 1;
            result.success = true;
            return result;
        }
        var current = item;
        if (table.mode == .ROBINHOOD) {
            var index = item.key.hash(31, table.capacity);
            var dist: usize = 0;
            var from: ?usize = null;
            while (true) {
                const resident = table.slots[index].item orelse {
                    table.slots[index] = .{ .item = current };
                    if (trace) if (from) |source| try result.moves.append(gpa, .{ .key = current.key, .from = source, .to = index });
                    if (result.position == null) result.position = index;
                    result.success = true;
                    return result;
                };
                const resident_distance = table.distance(resident.key, index);
                if (resident_distance < dist) {
                    table.slots[index] = .{ .item = current };
                    if (trace) if (from) |source| try result.moves.append(gpa, .{ .key = current.key, .from = source, .to = index });
                    if (result.position == null) result.position = index;
                    current = resident;
                    from = index;
                    dist = resident_distance;
                    result.shifted += 1;
                }
                index = (index + 1) % table.capacity;
                dist += 1;
            }
        }
        var part: usize = 0;
        while (true) {
            const index = part * table.capacity + current.key.hash(if (part == 0) 31 else 37, table.capacity);
            const resident = table.slots[index].item orelse {
                table.slots[index] = .{ .item = current };
                result.success = true;
                result.position = (try table.search(gpa, item.key, false)).position;
                return result;
            };
            if (result.kicks == table.capacity) {
                result.homeless = current;
                return result;
            }
            table.slots[index] = .{ .item = current };
            result.kicks += 1;
            if (trace) try result.moves.append(gpa, .{ .key = resident.key, .from = index });
            current = resident;
            part = 1 - part;
        }
    }
    fn remove(table: *Table, gpa: Allocator, found: Search, trace: bool) Allocator.Error!Removal {
        var result: Removal = .{};
        if (table.mode == .CHAIN) {
            _ = table.buckets[found.position].orderedRemove(found.chain_index);
        } else if (table.mode.usesTombstones()) {
            table.slots[found.position] = .{ .deleted = true };
            table.tombstones += 1;
        } else {
            table.slots[found.position] = .{};
            if (table.mode == .ROBINHOOD) {
                var next = (found.position + 1) % table.capacity;
                while (table.slots[next].item) |item| {
                    if (table.distance(item.key, next) == 0) break;
                    const destination = (next + table.capacity - 1) % table.capacity;
                    table.slots[destination] = .{ .item = item };
                    table.slots[next] = .{};
                    if (trace) try result.moves.append(gpa, .{ .key = item.key, .from = next, .to = destination });
                    result.shifted += 1;
                    next = (next + 1) % table.capacity;
                }
            }
        }
        table.size -= 1;
        return result;
    }
    fn rebuild(allocator: Allocator, gpa: Allocator, listed: []const Item, mode: Mode, capacity: usize) Allocator.Error!?Table {
        var replacement = try Table.init(allocator, mode, capacity);
        errdefer replacement.deinit();
        for (listed) |item| {
            if (!(try replacement.place(gpa, item, null, false)).success) {
                replacement.deinit();
                return null;
            }
            replacement.size += 1;
        }
        return replacement;
    }
    fn adopt(table: *Table, replacement: Table) void {
        const counters = table.counters;
        table.deinit();
        table.* = replacement;
        table.counters = counters;
    }
    fn automatic(table: *Table, gpa: Allocator, out: ?*Writer, reason: []const u8, initial_capacity: usize, pending: ?Item) Error!void {
        var listed: std.ArrayList(Item) = .empty;
        try listed.appendSlice(gpa, try table.items(gpa));
        if (pending) |item| try listed.append(gpa, item);
        const old = table.capacity;
        var capacity = initial_capacity;
        while (true) {
            if (try Table.rebuild(table.allocator, gpa, listed.items, table.mode, capacity)) |replacement| {
                table.adopt(replacement);
                table.counters.rehashes += 1;
                if (out) |writer| try line(writer, "REHASH {s} {d} -> {d}", .{ reason, old, table.capacity });
                return;
            }
            capacity = prime(2 * capacity);
        }
    }
    fn loadCheck(table: *Table, gpa: Allocator, out: ?*Writer, max_load: usize) Error!void {
        const threshold = max_load * table.slotCount();
        if (100 * (table.size + table.tombstones) <= threshold) return;
        const grow = 200 * table.size > threshold;
        try table.automatic(gpa, out, if (grow) "load" else "tomb", if (grow) prime(2 * table.capacity) else table.capacity, null);
    }
    fn shrinkCheck(table: *Table, gpa: Allocator, out: ?*Writer, min_load: usize, max_load: usize) Error!void {
        const capacity = prime(table.capacity / 2);
        if (100 * table.size >= min_load * table.slotCount() or capacity >= table.capacity or
            100 * table.size > max_load * capacity * table.mode.parts()) return;
        const listed = try table.items(gpa);
        if (try Table.rebuild(table.allocator, gpa, listed, table.mode, capacity)) |replacement| {
            const old = table.capacity;
            table.adopt(replacement);
            table.counters.rehashes += 1;
            if (out) |writer| try line(writer, "REHASH shrink {d} -> {d}", .{ old, capacity });
        }
    }
    fn pathElements(table: *const Table, out: *Writer, path: []const Probe) Writer.Error!void {
        for (path) |probe| {
            try out.print(" {f}:", .{table.position(probe.index)});
            try probe.slot.content(out);
        }
    }
    fn writePath(table: *const Table, out: *Writer, found: Search) Writer.Error!void {
        try out.writeAll("PATH");
        if (found.path.items.len == 0) try out.writeAll(" none") else try table.pathElements(out, found.path.items);
        try out.writeByte('\n');
    }
    fn writeMoves(table: *const Table, out: *Writer, moves: []const Move) Writer.Error!void {
        for (moves) |move| {
            if (move.to) |destination| try line(out, "SHIFT {f} {d} -> {d}", .{ move.key, move.from, destination }) else try line(out, "KICK {f} {f}", .{ move.key, table.position(move.from) });
        }
    }
    fn put(table: *Table, gpa: Allocator, out: ?*Writer, key: Key, value: i64, add: bool, max_load: usize, detailed: bool, trace: bool) Error!bool {
        const command: []const u8 = if (add) "ADD" else "PUT";
        const found = try table.search(gpa, key, trace);
        table.counters.probes += found.probes;
        if (found.item) |old| {
            const item: Item = .{ .key = key, .value = if (add) old.value + value else value };
            if (table.mode == .CHAIN) table.buckets[found.position].items[found.chain_index] = item else table.slots[found.position] = .{ .item = item };
            table.counters.updates += 1;
            if (detailed) {
                const writer = out.?;
                try line(writer, "{s} {f} UPDATED old={d} at={f} probes={d}", .{ command, item, old.value, table.position(found.position), found.probes });
                if (trace) try table.writePath(writer, found);
            }
            return false;
        }
        const item: Item = .{ .key = key, .value = value };
        const placed = try table.place(gpa, item, found, trace);
        table.size += 1;
        table.counters.inserts += 1;
        if (detailed) {
            const writer = out.?;
            try writer.print("{s} {f} NEW", .{ command, item });
            if (placed.success) {
                try writer.print(" at={f} probes={d}", .{ table.position(placed.position.?), found.probes });
                if (placed.reused) try writer.writeAll(" reused");
                if (table.mode == .ROBINHOOD) try writer.print(" shifted={d}", .{placed.shifted});
                if (table.mode == .CUCKOO) try writer.print(" kicks={d}", .{placed.kicks});
            } else {
                try writer.print(" probes={d}", .{found.probes});
                if (table.mode == .CUCKOO) try writer.print(" kicks={d} failed", .{placed.kicks}) else try writer.writeAll(" full");
            }
            try writer.writeByte('\n');
            if (trace) {
                try table.writePath(writer, found);
                try table.writeMoves(writer, placed.moves.items);
            }
        }
        if (!placed.success) try table.automatic(gpa, out, if (table.mode == .CUCKOO) "kicks" else "full", prime(2 * table.capacity), placed.homeless);
        try table.loadCheck(gpa, out, max_load);
        return true;
    }
    fn get(table: *Table, gpa: Allocator, out: *Writer, key: Key, trace: bool) Error!void {
        const found = try table.search(gpa, key, trace);
        table.counters.probes += found.probes;
        if (found.item) |item| {
            table.counters.hits += 1;
            try line(out, "GET {f} at={f} probes={d}", .{ item, table.position(found.position), found.probes });
        } else {
            table.counters.misses += 1;
            try line(out, "GET {f} NOT FOUND probes={d}", .{ key, found.probes });
        }
        if (trace) try table.writePath(out, found);
    }
    fn delete(table: *Table, gpa: Allocator, out: ?*Writer, key: Key, min_load: usize, max_load: usize, detailed: bool, trace: bool) Error!bool {
        const found = try table.search(gpa, key, trace);
        table.counters.probes += found.probes;
        if (found.item == null) {
            table.counters.absent += 1;
            if (detailed) {
                try line(out.?, "DEL {f} NOT FOUND probes={d}", .{ key, found.probes });
                if (trace) try table.writePath(out.?, found);
            }
            return false;
        }
        const removed = try table.remove(gpa, found, trace);
        table.counters.deletes += 1;
        if (detailed) {
            const writer = out.?;
            try writer.print("DEL {f} OK at={f} probes={d}", .{ key, table.position(found.position), found.probes });
            if (table.mode == .ROBINHOOD) try writer.print(" shifted={d}", .{removed.shifted});
            try writer.writeByte('\n');
            if (trace) {
                try table.writePath(writer, found);
                try table.writeMoves(writer, removed.moves.items);
            }
        }
        try table.shrinkCheck(gpa, out, min_load, max_load);
        return true;
    }
    fn costs(table: *const Table, gpa: Allocator) Allocator.Error![]Cost {
        var result: std.ArrayList(Cost) = .empty;
        if (table.mode == .CHAIN) {
            for (table.buckets, 0..) |bucket, index| for (bucket.items, 0..) |item, i| {
                try result.append(gpa, .{ .key = item.key, .probes = i + 1, .position = index });
            };
        } else {
            for (table.slots, 0..) |slot, index| if (slot.item) |item| {
                const probes = switch (table.mode) {
                    .CUCKOO => index / table.capacity + 1,
                    .LINEAR, .ROBINHOOD => table.distance(item.key, index) + 1,
                    else => (try table.search(gpa, item.key, false)).probes,
                };
                try result.append(gpa, .{ .key = item.key, .probes = probes, .position = index });
            };
        }
        return result.items;
    }
    fn metrics(table: *const Table, gpa: Allocator) Allocator.Error!Metrics {
        var total: u64 = 0;
        var longest: usize = 0;
        for (try table.costs(gpa)) |cost| {
            total += cost.probes;
            longest = @max(longest, cost.probes);
        }
        return .{ .longest = longest, .average = Ratio.init(total, table.size) };
    }
    fn dump(table: *const Table, out: *Writer) Writer.Error!void {
        try line(out, "DUMP {s} cap={d} size={d} tomb={d}", .{ @tagName(table.mode), table.capacity, table.size, table.tombstones });
        if (table.mode == .CHAIN) {
            for (table.buckets, 0..) |bucket, index| {
                try out.print("{d}", .{index});
                if (bucket.items.len == 0) try out.writeAll(" -");
                for (bucket.items) |item| try out.print(" {f}", .{item});
                try out.writeByte('\n');
            }
        } else {
            for (table.slots, 0..) |slot, index| {
                if (table.mode == .CUCKOO) try out.print("T{d} {d} ", .{ index / table.capacity + 1, index % table.capacity }) else try out.print("{d} ", .{index});
                if (slot.item) |item| {
                    try out.print("{f}", .{item});
                    if (table.mode == .ROBINHOOD) try out.print(" d={d}", .{table.distance(item.key, index)});
                } else try slot.content(out);
                try out.writeByte('\n');
            }
        }
    }
    fn map(table: *const Table, gpa: Allocator, out: *Writer) Error!void {
        try line(out, "MAP {s} cap={d}", .{ @tagName(table.mode), table.capacity });
        const cost_by_slot = try gpa.alloc(usize, table.slotCount());
        @memset(cost_by_slot, 0);
        if (table.mode != .CHAIN) for (try table.costs(gpa)) |cost| {
            cost_by_slot[cost.position] = cost.probes;
        };
        const characters = try gpa.alloc(u8, table.capacity);
        for (0..table.mode.parts()) |part| {
            for (characters, 0..) |*character, index| {
                if (table.mode == .CHAIN) {
                    const length = table.buckets[index].items.len;
                    character.* = if (length == 0) '.' else gauge(length);
                } else {
                    const flat = part * table.capacity + index;
                    const slot = table.slots[flat];
                    character.* = if (slot.empty()) '.' else if (slot.deleted) 'D' else if (table.mode == .CUCKOO) '#' else gauge(cost_by_slot[flat] - 1);
                }
            }
            var index: usize = 0;
            while (index < table.capacity) : (index += 40) {
                if (table.mode == .CUCKOO) try out.print("T{d} ", .{part + 1});
                try line(out, "{d:0>5} {s}", .{ index, characters[index..@min(index + 40, table.capacity)] });
            }
        }
    }
    fn statistics(table: *const Table, gpa: Allocator, out: *Writer) Error!void {
        const values = try table.metrics(gpa);
        const count = table.counters;
        try line(out, "STATS {s} size={d} cap={d} slots={d} tomb={d} load={f}% longest={d} avg={f} probes={d} rehashes={d}", .{
            @tagName(table.mode),                            table.size,     table.capacity, table.slotCount(), table.tombstones,
            Ratio.init(100 * table.size, table.slotCount()), values.longest, values.average, count.probes,      count.rehashes,
        });
        try line(out, "OPS inserts={d} updates={d} hits={d} misses={d} deletes={d} absent={d}", .{ count.inserts, count.updates, count.hits, count.misses, count.deletes, count.absent });
    }
    fn scan(table: *const Table, gpa: Allocator, out: *Writer, cursor: usize, limit: usize) Error!void {
        var keys: std.ArrayList(Key) = .empty;
        var next = cursor;
        while (next < table.slotCount() and keys.items.len < limit) : (next += 1) {
            if (table.mode == .CHAIN) {
                for (table.buckets[next].items) |item| try keys.append(gpa, item.key);
            } else if (table.slots[next].item) |item| try keys.append(gpa, item.key);
        }
        if (next == table.slotCount()) next = 0;
        try out.print("SCAN next={d}", .{next});
        for (keys.items) |key| try out.print(" {f}", .{key});
        try out.writeByte('\n');
    }
    fn appendRuns(table: *const Table, gpa: Allocator, lengths: *std.ArrayList(usize), part: usize) Allocator.Error!void {
        const offset = part * table.capacity;
        var empty: ?usize = null;
        for (0..table.capacity) |i| if (table.slots[offset + i].empty()) {
            empty = i;
            break;
        };
        const start = empty orelse {
            try lengths.append(gpa, table.capacity);
            return;
        };
        var length: usize = 0;
        for (1..table.capacity + 1) |i| {
            if (!table.slots[offset + (start + i) % table.capacity].empty()) {
                length += 1;
            } else if (length > 0) {
                try lengths.append(gpa, length);
                length = 0;
            }
        }
    }
    fn clusters(table: *const Table, gpa: Allocator, out: *Writer) Error!void {
        var lengths: std.ArrayList(usize) = .empty;
        if (table.mode == .CHAIN) {
            for (table.buckets) |bucket| if (bucket.items.len > 0) try lengths.append(gpa, bucket.items.len);
        } else for (0..table.mode.parts()) |part| try table.appendRuns(gpa, &lengths, part);
        var longest: usize = 0;
        for (lengths.items) |length| longest = @max(longest, length);
        try line(out, "CLUSTERS runs={d} longest={d}", .{ lengths.items.len, longest });
        try histogram(out, lengths.items);
    }
    fn distribution(table: *const Table, gpa: Allocator, out: *Writer) Error!void {
        var values: std.ArrayList(usize) = .empty;
        var longest: usize = 0;
        for (try table.costs(gpa)) |cost| {
            try values.append(gpa, cost.probes);
            longest = @max(longest, cost.probes);
        }
        try line(out, "DIST keys={d} longest={d}", .{ table.size, longest });
        try histogram(out, values.items);
    }
};

fn smaller(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn histogram(out: *Writer, values: []usize) Writer.Error!void {
    std.sort.heap(usize, values, {}, smaller);
    var index: usize = 0;
    while (index < values.len) {
        var end = index + 1;
        while (end < values.len and values[end] == values[index]) : (end += 1) {}
        const count = end - index;
        try out.print("{d} {d} ", .{ values[index], count });
        try out.splatByteAll('#', @min(count, 50));
        if (count > 50) try out.writeByte('+');
        try out.writeByte('\n');
        index = end;
    }
}
const State = struct {
    allocator: Allocator,
    table: ?Table = null,
    max_load: usize = 75,
    min_load: usize = 0,
    tracing: bool = false,
    fn deinit(state: *State) void {
        if (state.table) |*table| table.deinit();
    }
};
const modes = [_]Mode{ .CHAIN, .LINEAR, .QUADRATIC, .DOUBLE, .ROBINHOOD, .CUCKOO };
const Session = struct {
    gpa: Allocator,
    state: *State,
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn checkedMode(session: *Session, text: []const u8) Error!Mode {
        return std.meta.stringToEnum(Mode, text) orelse return session.fail("BAD MODE {s}", .{text});
    }
    fn checkCapacity(session: *Session, value: usize) Error!void {
        if (value < 2 or value > 10000) return session.fail("BAD CAPACITY", .{});
    }
    fn checkGeneration(session: *Session, count: usize, length: usize, seed: usize) Error!void {
        if (count < 1 or count > 500 or length < 1 or length > 10 or seed < 1 or seed > 2147483646) return session.fail("BAD ARGUMENT", .{});
    }
    fn compare(session: *Session, capacity: usize) Error!void {
        const listed = try session.state.table.?.items(session.gpa);
        std.sort.heap(Item, listed, {}, Item.less);
        try line(session.out, "COMPARE keys={d} cap={d}", .{ listed.len, capacity });
        for (modes) |mode| {
            var trial = try Table.init(session.state.allocator, mode, capacity);
            defer trial.deinit();
            for (listed) |item| _ = try trial.put(session.gpa, null, item.key, item.value, false, session.state.max_load, false, false);
            const values = try trial.metrics(session.gpa);
            try line(session.out, "{s} cap={d} longest={d} avg={f} probes={d} rehashes={d}", .{ @tagName(mode), trial.capacity, values.longest, values.average, trial.counters.probes, trial.counters.rehashes });
        }
    }
    fn bench(session: *Session, capacity: usize, count: usize, length: usize, seed: usize) Error!void {
        const keys = try session.gpa.alloc(Key, 2 * count);
        var generator: Generator = .{ .state = seed, .length = length };
        for (keys) |*key| key.* = generator.next();
        try line(session.out, "BENCH cap={d} count={d} len={d} seed={d}", .{ capacity, count, length, seed });
        for (modes) |mode| {
            var trial = try Table.init(session.state.allocator, mode, capacity);
            defer trial.deinit();
            for (keys[0..count], 1..) |key, i| _ = try trial.put(session.gpa, null, key, @intCast(i), false, session.state.max_load, false, false);
            var misses: u64 = 0;
            var probes: u64 = 0;
            for (keys[count..]) |key| {
                const found = try trial.search(session.gpa, key, false);
                if (found.item == null) {
                    misses += 1;
                    probes += found.probes;
                }
            }
            const values = try trial.metrics(session.gpa);
            try line(session.out, "{s} cap={d} keys={d} hit={f} misses={d} miss={f} rehashes={d}", .{ @tagName(mode), trial.capacity, trial.size, values.average, misses, Ratio.init(probes, misses), trial.counters.rehashes });
        }
    }
    fn execute(session: *Session, text: []const u8) Error!void {
        var words: [5][]const u8 = undefined;
        var tokens = std.mem.tokenizeScalar(u8, text, ' ');
        for (&words) |*word| word.* = tokens.next() orelse break;
        const command = std.meta.stringToEnum(Command, words[0]) orelse return session.fail("UNKNOWN COMMAND {s}", .{words[0]});
        const state = session.state;
        const out = session.out;
        const gpa = session.gpa;
        switch (command) {
            .CREATE => {
                const mode = try session.checkedMode(words[1]);
                const capacity = integer(words[2]);
                try session.checkCapacity(capacity);
                const replacement = try Table.init(state.allocator, mode, prime(capacity));
                if (state.table) |*old| old.deinit();
                state.table = replacement;
                return line(out, "CREATE {s} cap={d}", .{ @tagName(mode), replacement.capacity });
            },
            .MAXLOAD, .MINLOAD => {
                const value = integer(words[1]);
                const maximum = command == .MAXLOAD;
                if (if (maximum) value < 10 or value > 95 else value > 40) return session.fail("BAD LOAD", .{});
                if (maximum) state.max_load = value else state.min_load = value;
                return line(out, "{s} {d}", .{ @tagName(command), value });
            },
            .TRACE => {
                if (!equal(words[1], "ON") and !equal(words[1], "OFF")) return session.fail("BAD ARGUMENT", .{});
                state.tracing = equal(words[1], "ON");
                return line(out, "TRACE {s}", .{words[1]});
            },
            .HASH => {
                const key = Key.init(words[1]);
                const capacity = integer(words[2]);
                try session.checkCapacity(capacity);
                return line(out, "HASH {f} m={d} h31={d} h37={d} step={d}", .{ key, capacity, key.hash(31, capacity), key.hash(37, capacity), 1 + key.hash(37, capacity - 1) });
            },
            .BENCH => {
                const capacity = integer(words[1]);
                try session.checkCapacity(capacity);
                const count = integer(words[2]);
                const length = integer(words[3]);
                const seed = integer(words[4]);
                try session.checkGeneration(count, length, seed);
                return session.bench(prime(capacity), count, length, seed);
            },
            else => {},
        }
        if (state.table == null) return session.fail("NO TABLE", .{});
        const table = &state.table.?;
        switch (command) {
            .PUT, .ADD => {
                _ = try table.put(gpa, out, Key.init(words[1]), signedInteger(words[2]), command == .ADD, state.max_load, true, state.tracing);
            },
            .GET => try table.get(gpa, out, Key.init(words[1]), state.tracing),
            .DEL => {
                _ = try table.delete(gpa, out, Key.init(words[1]), state.min_load, state.max_load, true, state.tracing);
            },
            .PROBE => {
                const key = Key.init(words[1]);
                const found = try table.search(gpa, key, true);
                try out.print("PROBE {f}", .{key});
                try table.pathElements(out, found.path.items);
                try line(out, " {s} probes={d}", .{ if (found.item == null) "MISS" else "FOUND", found.probes });
            },
            .GEN, .GENDEL => {
                const count = integer(words[1]);
                const length = integer(words[2]);
                const seed = integer(words[3]);
                try session.checkGeneration(count, length, seed);
                var generator: Generator = .{ .state = seed, .length = length };
                var changed: usize = 0;
                for (0..count) |i| {
                    const key = generator.next();
                    const success = if (command == .GEN) try table.put(gpa, out, key, @intCast(i + 1), false, state.max_load, false, false) else try table.delete(gpa, out, key, state.min_load, state.max_load, false, false);
                    if (success) changed += 1;
                }
                if (command == .GEN) try line(out, "GEN {d} new={d} updated={d}", .{ count, changed, count - changed }) else try line(out, "GENDEL {d} deleted={d} missing={d}", .{ count, changed, count - changed });
            },
            .RESIZE, .CONVERT => {
                var mode = table.mode;
                var capacity = table.capacity;
                if (command == .RESIZE) {
                    capacity = integer(words[1]);
                    try session.checkCapacity(capacity);
                    capacity = prime(capacity);
                } else mode = try session.checkedMode(words[1]);
                if (100 * table.size > state.max_load * capacity * mode.parts()) return session.fail("TOO SMALL", .{});
                const listed = try table.items(gpa);
                const replacement = (try Table.rebuild(state.allocator, gpa, listed, mode, capacity)) orelse return session.fail("REBUILD FAILED", .{});
                if (command == .RESIZE) try line(out, "RESIZE {d} -> {d}", .{ table.capacity, capacity }) else try line(out, "CONVERT {s} -> {s} cap={d}", .{ @tagName(table.mode), @tagName(mode), capacity });
                table.adopt(replacement);
            },
            .CLEAR => {
                const size = table.size;
                table.adopt(try Table.init(state.allocator, table.mode, table.capacity));
                try line(out, "CLEAR {d}", .{size});
            },
            .DUMP => try table.dump(out),
            .MAP => try table.map(gpa, out),
            .STATS => try table.statistics(gpa, out),
            .KEYS => {
                const listed = try table.items(gpa);
                std.sort.heap(Item, listed, {}, Item.less);
                try out.print("KEYS {d}", .{table.size});
                for (listed) |item| try out.print(" {f}", .{item.key});
                try out.writeByte('\n');
            },
            .TOP => {
                const limit = integer(words[1]);
                if (limit < 1 or limit > 100) return session.fail("BAD ARGUMENT", .{});
                const records = try table.costs(gpa);
                std.sort.heap(Cost, records, {}, Cost.less);
                const count = @min(limit, records.len);
                try line(out, "TOP {d}", .{count});
                for (records[0..count]) |cost| try line(out, "{f} cost={d} at={f}", .{ cost.key, cost.probes, table.position(cost.position) });
            },
            .SCAN => {
                const cursor = integer(words[1]);
                const limit = integer(words[2]);
                if (limit < 1 or limit > 100) return session.fail("BAD ARGUMENT", .{});
                if (cursor >= table.slotCount()) return session.fail("BAD CURSOR", .{});
                try table.scan(gpa, out, cursor, limit);
            },
            .CLUSTERS => try table.clusters(gpa, out),
            .DIST => try table.distribution(gpa, out),
            .COMPARE => {
                const capacity = integer(words[1]);
                try session.checkCapacity(capacity);
                try session.compare(prime(capacity));
            },
            else => unreachable,
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var header = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer header.deinit();
    var state: State = .{ .allocator = std.heap.page_allocator };
    defer state.deinit();
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = integer(try readLine(header.allocator(), &input.interface));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = gpa, .state = &state, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            try output.interface.flush();
            continue;
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
