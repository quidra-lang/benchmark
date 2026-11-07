const std = @import("std");
const b = @import("config_io.zig");
const cache_model = @import("cache.zig");
const Cache = cache_model.Cache;
const p = @import("protocol.zig");
const bus_model = @import("bus.zig");
const stats = @import("stats.zig");
const Event = struct { number: usize, core: usize, cycle: i64, address: i64 = 0, block: i64 = 0,
     operation: u8, word: usize = 0, distance: i64 = 0, line_id: usize = 0 };
const Rejection = struct { number: usize, reason: []const u8 };
const Validated = struct { events: std.ArrayList(Event) = .empty, rejected: std.ArrayList(Rejection) = .empty };
fn coreBit(core: usize) u8 {
    return @as(u8, 1) << @intCast(core);
}
fn wordBit(word: usize) u32 {
    return @as(u32, 1) << @intCast(word);
}
fn validateTrace(lines: []const []const u8, config: *const b.Config) Validated {
    var out: Validated = .{};
    var latest: i64 = 0;
    for (lines, 0..) |line, i| {
        const f = b.split(line, ' ');
        var empty = false;
        for (f) |field| if (field.len == 0) {
            empty = true;
        };
        var reason: ?[]const u8 = null;
        if ((f.len != 3 and f.len != 4) or empty) reason = "fields" else if (!b.decimalInteger(f[0],
             7)) reason = "cycle" else if (!b.decimalInteger(f[1], 1000000) or b.number(f[1]) >= b.n(config.cores)) reason = "core" else if ((!b.eq(f[2],
             "R") and !b.eq(f[2], "W") and !b.eq(f[2], "FENCE")) or (if (b.eq(f[2], "FENCE")) f.len != 3 else f.len != 4)) reason = "op" else if (!b.eq(f[2],
             "FENCE") and (!b.validHexAddress(f[3]) or @mod(b.hexValue(f[3]), 4) != 0 or b.hexValue(f[3]) > 0x7fffffff)) reason = "address" else if (b.number(f[0]) < latest) reason = "order";
        if (reason) |failure| {
            b.append(Rejection, &out.rejected, .{ .number = i + 1, .reason = failure });
            continue;
        }
        var event: Event = .{ .number = out.events.items.len + 1, .core = b.u(b.number(f[1])),
             .cycle = b.number(f[0]), .operation = if (b.eq(f[2], "FENCE")) 'F' else f[2][0] };
        latest = event.cycle;
        if (event.operation != 'F') {
            event.address = b.hexValue(f[3]);
            event.block = @divTrunc(event.address, config.line_size);
            event.word = b.u(@divTrunc(@mod(event.address, config.line_size), 4));
        }
        b.append(Event, &out.events, event);
    }
    return out;
}
const WordSharing = struct { reads: u8 = 0, writes: u8 = 0 };
const StaticLine = struct { cores: u8 = 0, writers: u8 = 0, reads: i64 = 0, writes: i64 = 0,
     words: [32]WordSharing = @splat(.{}), shared: bool = false, true_line: bool = false };
const Facts = struct {
    blocks: []const i64,
    grouped: [8]std.ArrayList(usize) = @splat(.empty),
    sharing: []StaticLine,
    fn lineId(self: *const Facts, block: i64) usize {
        var lo: usize = 0;
        var hi = self.blocks.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (self.blocks[mid] < block) lo = mid + 1 else hi = mid;
        }
        return lo;
    }
};
fn buildFacts(events: []Event, config: *const b.Config) Facts {
    var blocks: std.ArrayList(i64) = .empty;
    for (events) |event| if (event.operation != 'F') b.append(i64, &blocks, event.block);
    std.mem.sort(i64, blocks.items, {}, struct {
        fn less(_: void, left: i64, right: i64) bool {
            return left < right;
        }
    }.less);
    var count: usize = 0;
    for (blocks.items, 0..) |block, i| if (i == 0 or block != blocks.items[i - 1]) {
        blocks.items[count] = block;
        count += 1;
    };
    var out: Facts = .{ .blocks = blocks.items[0..count], .sharing = b.zero(StaticLine, count, .{}) };
    for (events, 0..) |*event, i| {
        b.append(usize, &out.grouped[event.core], i);
        if (event.operation == 'F') continue;
        event.line_id = out.lineId(event.block);
        const info = &out.sharing[event.line_id];
        const mask = coreBit(event.core);
        info.cores |= mask;
        const word = &info.words[event.word];
        if (event.operation == 'W') {
            info.writers |= mask;
            info.writes += 1;
            word.writes |= mask;
        } else {
            info.reads += 1;
            word.reads |= mask;
        }
    }
    for (out.sharing) |*info| {
        info.shared = @popCount(info.cores) >= 2 and info.writers != 0;
        for (info.words[0..b.u(@divTrunc(config.line_size, 4))]) |word| if (word.writes != 0 and @popCount(word.reads | word.writes) >= 2) {
            info.true_line = true;
        };
    }
    return out;
}
const Reuse = struct { core: usize, accesses: usize, lines: i64 = 0, cold: i64 = 0, opt: i64 = 0,
     distances: [6]i64 = @splat(0), capacities: [5]i64, lru: [5]i64 = @splat(0) };
fn fenwickAdd(tree: []i64, position: usize, value: i64) void {
    var i = position;
    while (i < tree.len) : (i += i & (~i + 1)) tree[i] += value;
}
fn fenwickSum(tree: []const i64, position: usize) i64 {
    var result: i64 = 0;
    var i = position;
    while (i > 0) : (i -= i & (~i + 1)) result += tree[i];
    return result;
}
const HeapEntry = struct { next: usize, id: usize, block: i64 };
fn farther(left: HeapEntry, right: HeapEntry) bool {
    return if (left.next != right.next) left.next > right.next else left.block < right.block;
}
const OptHeap = struct {
    items: []HeapEntry,
    count: usize = 0,
    fn push(self: *OptHeap, value: HeapEntry) void {
        var i = self.count;
        self.count += 1;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (!farther(value, self.items[parent])) break;
            self.items[i] = self.items[parent];
            i = parent;
        }
        self.items[i] = value;
    }
    fn pop(self: *OptHeap) HeapEntry {
        const result = self.items[0];
        self.count -= 1;
        const value = self.items[self.count];
        var i: usize = 0;
        while (2 * i + 1 < self.count) {
            var child = 2 * i + 1;
            if (child + 1 < self.count and farther(self.items[child + 1], self.items[child])) child += 1;
            if (!farther(self.items[child], value)) break;
            self.items[i] = self.items[child];
            i = child;
        }
        if (self.count > 0) self.items[i] = value;
        return result;
    }
};
fn reuseAnalysis(events: []Event, facts: *const Facts, config: *const b.Config, work_allocator: std.mem.Allocator) []const Reuse {
    const out = b.alloc(Reuse, config.cores);
    for (0..config.cores) |core| {
        const persistent = b.allocator;
        var arena: std.heap.ArenaAllocator = .init(work_allocator);
        defer arena.deinit();
        b.allocator = arena.allocator();
        var accesses: std.ArrayList(usize) = .empty;
        for (facts.grouped[core].items) |index| if (events[index].operation != 'F') b.append(usize, &accesses, index);
        const count = accesses.items.len;
        var row: Reuse = .{ .core = core, .accesses = count, .capacities = .{ @divTrunc(config.cap,
             4), @divTrunc(config.cap, 2), config.cap, 2 * config.cap, 4 * config.cap } };
        const tree = b.zero(i64, count + 1, 0);
        const last = b.zero(usize, facts.blocks.len, 0);
        for (accesses.items, 0..) |index, i| {
            const event = &events[index];
            const previous = last[event.line_id];
            if (previous == 0) {
                row.cold += 1;
                row.lines += 1;
            } else {
                event.distance = fenwickSum(tree, i + 1) - fenwickSum(tree, previous) + 1;
                fenwickAdd(tree, previous, -1);
                const d = event.distance;
                const bucket: usize = if (d == 1) 0 else if (d <= 4) 1 else if (d <= 16) 2 else if (d <= 64) 3 else if (d <= 256) 4 else 5;
                row.distances[bucket] += 1;
            }
            for (row.capacities, 0..) |capacity, j| if (event.distance == 0 or event.distance > capacity) {
                row.lru[j] += 1;
            };
            last[event.line_id] = i + 1;
            fenwickAdd(tree, i + 1, 1);
        }
        @memset(last, count + 1);
        const next = b.alloc(usize, count);
        const resident = b.zero(bool, facts.blocks.len, false);
        const resident_next = b.zero(usize, facts.blocks.len, 0);
        var i = count;
        while (i > 0) {
            i -= 1;
            const id = events[accesses.items[i]].line_id;
            next[i] = last[id];
            last[id] = i;
        }
        var heap: OptHeap = .{ .items = b.alloc(HeapEntry, count) };
        var residents: usize = 0;
        for (accesses.items, 0..) |index, j| {
            const event = events[index];
            const id = event.line_id;
            if (!resident[id]) {
                row.opt += 1;
                if (residents == b.u(config.cap)) {
                    while (true) {
                        const victim = heap.pop();
                        if (resident[victim.id] and resident_next[victim.id] == victim.next) {
                            resident[victim.id] = false;
                            residents -= 1;
                            break;
                        }
                    }
                }
                resident[id] = true;
                residents += 1;
            }
            resident_next[id] = next[j];
            heap.push(.{ .next = next[j], .id = id, .block = event.block });
        }
        out[core] = row;
        b.allocator = persistent;
    }
    return out;
}
const Processed = struct { number: usize, core: usize, issue: i64, address: i64, block: i64,
     latency: i64, line_id: usize, operation: u8, service: usize, miss_kind: ?usize, hit: bool };
const WordCommunication = struct { writer: ?usize = null, readers: u8 = 0 };
const DynamicLine = struct { writer: ?usize = null, handoffs: i64 = 0, sharing_misses: [2]i64 = @splat(0),
     words: [32]WordCommunication = @splat(.{}) };
const L2Stats = struct { lookups: i64 = 0, hits: i64 = 0, misses: i64 = 0, flushes: i64 = 0,
     writebacks: i64 = 0, evictions: i64 = 0, dirty_evictions: i64 = 0 };
const Simulation = struct {
    arena: std.heap.ArenaAllocator,
    config: *const b.Config,
    scenario: *const b.Scenario,
    events: []const Event,
    facts: *const Facts,
    l1: [8]Cache = undefined,
    l2: Cache,
    bus: bus_model.Bus,
    cores: [8]stats.CoreStats = @splat(.{}),
    total: stats.CoreStats = .{},
    l2_stats: L2Stats = .{},
    processed: std.ArrayList(Processed) = .empty,
    watch: b.Lines = .{},
    dynamic: []DynamicLine = &.{},
    communications: [8][8]i64 = std.mem.zeroes([8][8]i64),
    indices: [8]usize = @splat(0),
    ready: [8]i64 = @splat(0),
    write_completion: [8]i64 = @splat(0),
    invalidations: [8][]u32 = undefined,
    primary: bool,
    fn lineStates(self: *const Simulation, block: i64) [9]u8 {
        var states: [9]u8 = @splat(0);
        for (0..self.config.cores) |core| states[core] = self.l1[core].state(block);
        states[self.config.cores] = self.l2.state(block);
        return states;
    }
    fn issueTransaction(self: *Simulation, core: usize, kind: p.TransactionKind, block: i64,
         requested: i64) *bus_model.Transaction {
        const tx = self.bus.assign(core, kind, block, requested);
        self.cores[core].bus[@intFromEnum(kind)] += 1;
        if (kind == .wb) self.l2_stats.writebacks += 1;
        return tx;
    }
    fn snoopOthers(self: *Simulation, tx: *bus_model.Transaction, word: usize, id: usize) void {
        for (0..self.config.cores) |core| {
            if (core == tx.core) continue;
            const cache = &self.l1[core];
            const old = cache.state(tx.block);
            if (old == 'I') continue;
            const transition = p.snoop(self.scenario.protocol, old, tx.kind);
            tx.snoop_old[core] = old;
            tx.snoop_new[core] = transition.state;
            tx.snoop_hits += 1;
            if (transition.state == 'I') {
                _ = cache.remove(tx.block);
                tx.invalidations += 1;
                self.cores[tx.core].snoop[0] += 1;
                self.cores[core].snoop[1] += 1;
                self.invalidations[core][id] = wordBit(word);
            } else cache.change(tx.block, transition.state);
            if (transition.supply) {
                tx.supplier = core;
                self.cores[core].snoop[2] += 1;
            }
            tx.flushed = tx.flushed or transition.flush;
        }
        if (tx.flushed) self.l2_stats.flushes += 1;
    }
    fn accessL2(self: *Simulation, tx: *bus_model.Transaction) void {
        self.l2_stats.lookups += 1;
        if (self.l2.state(tx.block) != 'I') {
            tx.l2_hit = true;
            self.l2_stats.hits += 1;
            self.l2.touch(tx.block);
        } else {
            self.l2_stats.misses += 1;
            if (self.l2.fill(tx.block, 'C')) |victim| {
                tx.evicted = victim.block;
                tx.dirty_eviction = victim.state == 'D';
                self.l2_stats.evictions += 1;
                for (0..self.config.cores) |core| {
                    const old = self.l1[core].state(victim.block);
                    if (old == 'I') continue;
                    _ = self.l1[core].remove(victim.block);
                    tx.copies[core] = old;
                    self.cores[core].snoop[3] += 1;
                    tx.dirty_eviction = tx.dirty_eviction or p.dirty(old);
                }
                if (tx.dirty_eviction) self.l2_stats.dirty_evictions += 1;
            }
        }
        if (tx.flushed or tx.kind == .wr) self.l2.change(tx.block, 'D');
    }
    fn runTransaction(self: *Simulation, core: usize, kind: p.TransactionKind, event: Event,
         requested: i64) struct { completion: i64, service: usize } {
        const tx = self.issueTransaction(core, kind, event.block, requested);
        self.snoopOthers(tx, event.word, event.line_id);
        if (kind != .upgr) self.accessL2(tx);
        var completion = tx.start + self.config.tb;
        var service: usize = undefined;
        if (kind == .upgr) service = 1 else if (kind == .wr) {
            service = 2;
            completion += self.config.t2 + (if (tx.l2_hit) @as(i64, 0) else self.config.tm);
        } else if (tx.supplier != null) service = 3 else if (tx.l2_hit) {
            service = 4;
            completion += self.config.t2;
        } else {
            service = 5;
            completion += self.config.t2 + self.config.tm;
        }
        return .{ .completion = completion, .service = service };
    }
    fn communicate(self: *Simulation, event: Event) void {
        const info = &self.dynamic[event.line_id];
        const word = &info.words[event.word];
        const core = coreBit(event.core);
        if (event.operation == 'W') {
            if (info.writer) |former| if (former != event.core) {
                info.handoffs += 1;
            };
            info.writer = event.core;
            word.writer = event.core;
            word.readers = 0;
        } else if (word.writer) |writer| if (writer != event.core and word.readers & core == 0) {
            self.communications[writer][event.core] += 1;
            word.readers |= core;
        };
    }
    fn access(self: *Simulation, event: Event, issue: i64) void {
        const config = self.config;
        const core = event.core;
        const id = event.line_id;
        const cache = &self.l1[core];
        const count = &self.cores[core];
        var before: [8][9]u8 = undefined;
        if (self.primary) for (config.watch.items, 0..) |block, i| {
            before[i] = self.lineStates(block);
        };
        const old = cache.state(event.block);
        const hit = old != 'I';
        count.accesses += 1;
        if (event.operation == 'R') count.reads += 1 else count.writes += 1;
        if (hit) count.hits += 1 else count.misses += 1;
        var other = false;
        for (0..config.cores) |k| if (k != core and self.l1[k].state(event.block) != 'I') {
            other = true;
        };
        const transition = p.requester(self.scenario.protocol, old, event.operation, other);
        var miss_kind: ?usize = null;
        if (hit) cache.touch(event.block) else {
            const record = self.invalidations[core][id];
            if (event.distance == 0) miss_kind = 0 else if (record != 0) {
                miss_kind = 3;
                const sharing: usize = if (record & wordBit(event.word) != 0) 0 else 1;
                count.miss_counts[4 + sharing] += 1;
                if (self.primary) self.dynamic[id].sharing_misses[sharing] += 1;
            } else miss_kind = if (event.distance > config.cap) 1 else 2;
            count.miss_counts[miss_kind.?] += 1;
        }
        if (event.operation == 'W') for (0..config.cores) |k| if (k != core and self.invalidations[k][id] != 0) {
            self.invalidations[k][id] |= wordBit(event.word);
        };
        if (self.primary) self.communicate(event);
        var completion = issue + config.t1;
        var service: usize = 0;
        if (transition.transaction) |kind| {
            const result = self.runTransaction(core, kind, event, issue + config.t1);
            completion = result.completion;
            service = result.service;
        }
        if (old != 'I') cache.change(event.block, transition.state) else if (transition.state != 'I') {
            const victim = cache.fill(event.block, transition.state);
            self.invalidations[core][id] = 0;
            if (victim) |entry| if (p.dirty(entry.state)) {
                _ = self.issueTransaction(core, .wb, entry.block, self.bus.free);
                self.l2.touch(entry.block);
                self.l2.change(entry.block, 'D');
            };
        }
        const latency = completion - issue;
        count.service[service] += 1;
        count.latency += latency;
        if (event.operation == 'R') {
            count.read_latency += latency;
            self.ready[core] = completion;
        } else {
            count.write_latency += latency;
            self.ready[core] = issue + config.t1;
            self.write_completion[core] = @max(self.write_completion[core], completion);
        }
        count.finish = @max(count.finish, completion);
        b.append(Processed, &self.processed, .{ .number = event.number, .core = core, .issue = issue,
             .address = event.address, .block = event.block, .latency = latency, .line_id = id,
             .operation = event.operation, .service = service, .miss_kind = miss_kind, .hit = hit });
        if (self.primary) for (config.watch.items, 0..) |block, i| {
            const after = self.lineStates(block);
            if (block != event.block and std.mem.eql(u8, &before[i], &after)) continue;
            var columns: std.ArrayList([]const u8) = .empty;
            for (0..config.cores) |k| b.append([]const u8, &columns, b.fmt("c{d}:{c}", .{ k, after[k] }));
            self.watch.add("{d} {d} c{d} {c} {s} line {s} {s} L2:{c}", .{ event.number, issue,
                 core, event.operation, b.hexAddress(event.address), b.hexAddress(block * config.line_size),
                 b.join(columns.items, " "), after[config.cores] });
        };
    }
    fn run(self: *Simulation) void {
        const config = self.config;
        for (0..config.cores) |core| {
            self.l1[core] = Cache.init(config.l1_sets, config.l1_ways, self.scenario.l1);
            self.invalidations[core] = b.zero(u32, self.facts.blocks.len, 0);
        }
        self.l2 = Cache.init(config.l2_sets, config.l2_ways, self.scenario.l2);
        if (self.primary) self.dynamic = b.zero(DynamicLine, self.facts.blocks.len, .{});
        while (true) {
            var chosen: ?usize = null;
            var issue: i64 = 0;
            for (0..config.cores) |core| if (self.indices[core] < self.facts.grouped[core].items.len) {
                const event = self.events[self.facts.grouped[core].items[self.indices[core]]];
                const candidate = @max(event.cycle, self.ready[core]);
                if (chosen == null or candidate < issue) {
                    chosen = core;
                    issue = candidate;
                }
            };
            const core = chosen orelse break;
            const event = self.events[self.facts.grouped[core].items[self.indices[core]]];
            self.indices[core] += 1;
            if (event.operation == 'F') {
                const completion = @max(issue, self.write_completion[core]);
                const count = &self.cores[core];
                count.fences += 1;
                count.fence_stall += completion - issue;
                count.finish = @max(count.finish, completion);
                self.ready[core] = completion;
            } else self.access(event, issue);
        }
        self.total = stats.totalCounters(self.cores[0..config.cores]);
    }
};
fn traceConfig(config: *const b.Config, trace: []const []const u8, validated: Validated) b.Lines {
    var out: b.Lines = .{};
    out.add("trace lines {d} accepted {d} rejected {d}", .{ trace.len, validated.events.items.len,
         validated.rejected.items.len });
    for (validated.rejected.items) |rejected| out.add("reject line {d} {s}", .{ rejected.number, rejected.reason });
    out.add("geometry cores {d} line {d} l1 {d} {d} sets {d} l2 {d} {d} sets {d}", .{ config.cores,
         config.line_size, config.l1_size, config.l1_ways, config.l1_sets, config.l2_size,
         config.l2_ways, config.l2_sets });
    out.add("latency l1 {d} l2 {d} memory {d} bus {d}", .{ config.t1, config.t2, config.tm, config.tb });
    return out;
}
fn reuseLines(reuse: []const Reuse, config: *const b.Config) b.Lines {
    var out: b.Lines = .{};
    for (reuse) |row| {
        out.add("reuse c{d} accesses {d} lines {d} distance {s} cold {d}", .{ row.core, row.accesses,
             row.lines, stats.rangeCounts(&.{ "1", "2-4", "5-16", "17-64", "65-256", "257+" },
             &row.distances), row.cold });
        var mrc: std.ArrayList([]const u8) = .empty;
        for (row.capacities, row.lru) |capacity, misses| b.append([]const u8, &mrc, b.fmt("{d}:{d}",
             .{ capacity, misses }));
        out.add("mrc c{d} lru {s} opt {d}:{d}", .{ row.core, b.join(mrc.items, " "), config.cap, row.opt });
    }
    return out;
}
fn scenarioReport(state: *const Simulation) b.Lines {
    const config = state.config;
    const total = state.total;
    const l2 = state.l2_stats;
    var out: b.Lines = .{};
    out.add("scenario {s} {s} {s} {s}", .{ state.scenario.name, b.protocol_names[@intFromEnum(state.scenario.protocol)],
         b.replacement_names[@intFromEnum(state.scenario.l1)], b.replacement_names[@intFromEnum(state.scenario.l2)] });
    for (state.cores[0..config.cores], 0..) |count, core| out.extend(stats.sixLines(b.fmt("c{d}", .{core}), count));
    out.extend(stats.sixLines("total", total));
    out.add("l2 lookups {d} hits {d} misses {d} flushes {d} writebacks {d} evictions {d} dirty_evictions {d}",
         .{ l2.lookups, l2.hits, l2.misses, l2.flushes, l2.writebacks, l2.evictions, l2.dirty_evictions });
    const transactions = b.n(state.bus.transactions.items.len);
    const busy = config.tb * transactions;
    out.add("bus transactions {d} busy {d} wait {d} utilization {s}", .{ transactions, busy,
         state.bus.wait, stats.decimal(100 * busy, total.finish) });
    out.add("traffic command_bytes {d} data_bytes {d} memory_bytes {d}", .{ 8 * transactions,
         config.line_size * (total.bus[0] + total.bus[1] + total.bus[4]) + 4 * total.bus[3],
         config.line_size * (l2.misses + l2.dirty_evictions) });
    var probes: i64 = 0;
    var hits: i64 = 0;
    var fanout: [8]i64 = @splat(0);
    for (state.bus.transactions.items) |tx| if (tx.kind != .wb) {
        probes += b.n(config.cores) - 1;
        hits += tx.snoop_hits;
        if (tx.kind != .rd) fanout[tx.invalidations] += 1;
    };
    var names: std.ArrayList([]const u8) = .empty;
    for (0..config.cores) |core| b.append([]const u8, &names, b.fmt("{d}", .{core}));
    out.add("snoops probes {d} hits {d} fanout {s}", .{ probes, hits, stats.rangeCounts(names.items,
         fanout[0..config.cores]) });
    var histogram: [6]i64 = @splat(0);
    for (state.processed.items) |access| {
        const value = access.latency;
        const bucket: usize = if (value == 1) 0 else if (value <= 9) 1 else if (value <= 29) 2 else if (value <= 99) 3 else if (value <= 299) 4 else 5;
        histogram[bucket] += 1;
    }
    out.add("latencies reads {d} writes {d} histogram {s}", .{ total.read_latency, total.write_latency,
         stats.rangeCounts(&.{ "1", "2-9", "10-29", "30-99", "100-299", "300+" }, &histogram) });
    return out;
}
fn ranking(states: []const *Simulation) b.Lines {
    const ordered = b.dupe(*Simulation, states);
    std.mem.sort(*Simulation, ordered, {}, struct {
        fn less(_: void, left: *Simulation, right: *Simulation) bool {
            if (left.total.finish != right.total.finish) return left.total.finish < right.total.finish;
            if (left.bus.transactions.items.len != right.bus.transactions.items.len) return left.bus.transactions.items.len < right.bus.transactions.items.len;
            return left.scenario.order < right.scenario.order;
        }
    }.less);
    var out: b.Lines = .{};
    out.add("ranking", .{});
    for (ordered, 0..) |state, i| out.add("{d} {s} finish {d} transactions {d} amat {s} {s}",
         .{ i + 1, state.scenario.name, state.total.finish, state.bus.transactions.items.len,
         stats.fraction(state.total.latency, state.total.accesses), stats.decimal(state.total.latency,
         state.total.accesses) });
    return out;
}
const Hot = struct { block: i64 = 0, types: [5]i64 = @splat(0), transactions: i64 = 0, misses: i64 = 0,
     coherence: i64 = 0, invalidations: i64 = 0, cores: u8 = 0 };
fn hotLines(state: *const Simulation) b.Lines {
    const records = b.zero(Hot, state.facts.blocks.len, .{});
    for (records, state.facts.blocks) |*record, block| record.block = block;
    for (state.bus.transactions.items) |tx| {
        const h = &records[state.facts.lineId(tx.block)];
        h.transactions += 1;
        h.types[@intFromEnum(tx.kind)] += 1;
        h.invalidations += b.n(tx.invalidations);
        h.cores |= coreBit(tx.core);
    }
    for (state.processed.items) |access| if (access.miss_kind) |kind| {
        records[access.line_id].misses += 1;
        if (kind == 3) records[access.line_id].coherence += 1;
    };
    var ordered: std.ArrayList(*Hot) = .empty;
    for (records) |*record| if (record.transactions > 0) b.append(*Hot, &ordered, record);
    std.mem.sort(*Hot, ordered.items, {}, struct {
        fn less(_: void, left: *Hot, right: *Hot) bool {
            return if (left.transactions != right.transactions) left.transactions > right.transactions else left.block < right.block;
        }
    }.less);
    var out: b.Lines = .{};
    out.add("hot {s}", .{state.scenario.name});
    for (ordered.items[0..@min(state.config.top, ordered.items.len)], 0..) |h, i| {
        var values: std.ArrayList([]const u8) = .empty;
        for (p.transaction_names, h.types) |name, count| b.append([]const u8, &values, b.fmt("{s} {d}",
             .{ name, count }));
        out.add("{d} {s} transactions {d} {s} misses {d} coherence {d} invalidations {d} cores {s}",
             .{ i + 1, b.hexAddress(h.block * state.config.line_size), h.transactions, b.join(values.items,
             " "), h.misses, h.coherence, h.invalidations, stats.coreString(h.cores) });
    }
    return out;
}
fn intervalRows(state: *const Simulation) b.Lines {
    const width = state.config.interval;
    const count = b.u(@divTrunc(state.total.finish, width) + 1);
    const Interval = struct { accesses: [8]i64 = @splat(0), misses: i64 = 0, transactions: i64 = 0, busy: i64 = 0 };
    const rows = b.zero(Interval, count, .{});
    for (state.processed.items) |access| {
        const row = &rows[b.u(@divTrunc(access.issue, width))];
        row.accesses[access.core] += 1;
        row.misses += @intFromBool(!access.hit);
    }
    for (state.bus.transactions.items) |tx| {
        const first = tx.start;
        const last = first + state.config.tb;
        rows[b.u(@divTrunc(first, width))].transactions += 1;
        var bucket = @divTrunc(first, width);
        while (bucket <= @divTrunc(last - 1, width) and bucket < b.n(count)) : (bucket += 1) rows[b.u(bucket)].busy += @max(@as(i64,
             0), @min(last, (bucket + 1) * width) - @max(first, bucket * width));
    }
    var out: b.Lines = .{};
    out.add("intervals {s} {d}", .{ state.scenario.name, width });
    for (rows, 0..) |row, i| {
        var accesses: std.ArrayList([]const u8) = .empty;
        for (row.accesses[0..state.config.cores]) |amount| b.append([]const u8, &accesses, b.fmt("{d}", .{amount}));
        out.add("{d} {d}-{d} accesses {s} misses {d} transactions {d} busy {d} utilization {s}",
             .{ i, b.n(i) * width, (b.n(i) + 1) * width - 1, b.join(accesses.items, " "), row.misses,
             row.transactions, row.busy, stats.decimal(100 * row.busy, width) });
    }
    return out;
}
fn slowestRows(state: *const Simulation) b.Lines {
    const ordered = b.dupe(Processed, state.processed.items);
    std.mem.sort(Processed, ordered, {}, struct {
        fn less(_: void, left: Processed, right: Processed) bool {
            return if (left.latency != right.latency) left.latency > right.latency else left.number < right.number;
        }
    }.less);
    var out: b.Lines = .{};
    out.add("slowest {s}", .{state.scenario.name});
    for (ordered[0..@min(state.config.top, ordered.len)], 0..) |access, i| out.add("{d} event {d} cycle {d} c{d} {c} {s} latency {d} service {s}",
         .{ i + 1, access.number, access.issue, access.core, access.operation, b.hexAddress(access.address),
         access.latency, stats.service_names[access.service] });
    return out;
}
fn regionFor(address: i64, config: *const b.Config) usize {
    for (config.regions.items, 0..) |region, i| if (region.first <= address and address <= region.last) return i;
    return config.regions.items.len;
}
fn regionRows(state: *const Simulation) b.Lines {
    const RegionStats = struct { accesses: i64 = 0, reads: i64 = 0, writes: i64 = 0, hits: i64 = 0,
         latency: i64 = 0, transactions: i64 = 0, misses: [4]i64 = @splat(0) };
    var rows: [17]RegionStats = @splat(.{});
    for (state.processed.items) |access| {
        const row = &rows[regionFor(access.address, state.config)];
        row.accesses += 1;
        if (access.operation == 'R') row.reads += 1 else row.writes += 1;
        row.latency += access.latency;
        if (access.hit) row.hits += 1 else row.misses[access.miss_kind.?] += 1;
    }
    for (state.bus.transactions.items) |tx| rows[regionFor(tx.block * state.config.line_size,
         state.config)].transactions += 1;
    var out: b.Lines = .{};
    out.add("regions {s}", .{state.scenario.name});
    for (rows[0 .. state.config.regions.items.len + 1], 0..) |row, i| {
        var misses: std.ArrayList([]const u8) = .empty;
        for (stats.miss_names, row.misses) |kind, count| b.append([]const u8, &misses, b.fmt("{s} {d}",
             .{ kind, count }));
        out.add("{s} accesses {d} reads {d} writes {d} hits {d} {s} transactions {d} latency {d} amat {s}",
             .{ if (i < state.config.regions.items.len) state.config.regions.items[i].name else "other",
             row.accesses, row.reads, row.writes, row.hits, b.join(misses.items, " "), row.transactions,
             row.latency, if (row.accesses > 0) b.fmt("{s} {s}", .{ stats.fraction(row.latency,
             row.accesses), stats.decimal(row.latency, row.accesses) }) else "-" });
    }
    return out;
}
fn sharingOutput(facts: *const Facts, state: *const Simulation) b.Lines {
    var out: b.Lines = .{};
    var count: i64 = 0;
    var true_lines: i64 = 0;
    var true_misses: i64 = 0;
    var false_misses: i64 = 0;
    for (facts.blocks, facts.sharing, 0..) |block, info, id| {
        if (!info.shared) continue;
        count += 1;
        true_lines += @intFromBool(info.true_line);
        const dynamic = state.dynamic[id];
        const t = dynamic.sharing_misses[0];
        const f = dynamic.sharing_misses[1];
        true_misses += t;
        false_misses += f;
        var words: std.ArrayList([]const u8) = .empty;
        for (info.words[0..b.u(@divTrunc(state.config.line_size, 4))], 0..) |word, i| if (word.reads != 0 or word.writes != 0) b.append([]const u8,
             &words, b.fmt("w{d}={s}/{s}", .{ i, stats.coreString(word.reads), stats.coreString(word.writes) }));
        out.add("{s} {s} cores {s} writers {s} reads {d} writes {d} handoffs {d} coherence {d} true {d} false {d} words {s}",
             .{ b.hexAddress(block * state.config.line_size), if (info.true_line) "true" else "false",
             stats.coreString(info.cores), stats.coreString(info.writers), info.reads, info.writes,
             dynamic.handoffs, t + f, t, f, b.join(words.items, " ") });
    }
    out.add("lines {d} true_lines {d} false_lines {d} coherence {d} true {d} false {d}", .{ count,
         true_lines, count - true_lines, true_misses + false_misses, true_misses, false_misses });
    out.add("communication", .{});
    for (0..state.config.cores) |core| {
        var values: std.ArrayList([]const u8) = .empty;
        for (state.communications[core][0..state.config.cores]) |value| b.append([]const u8,
             &values, b.fmt("{d}", .{value}));
        out.add("c{d} {s}", .{ core, b.join(values.items, " ") });
    }
    return out;
}
fn cacheRows(cache: *const Cache, label: []const u8, line_size: i64) b.Lines {
    var out: b.Lines = .{};
    for (cache.sets, 0..) |set, row| {
        var ways: std.ArrayList([]const u8) = .empty;
        for (set.entries[0..cache.ways]) |entry| b.append([]const u8, &ways, if (entry) |value| b.fmt("{s}:{c}",
             .{ b.hexAddress(value.block * line_size), value.state }) else "-");
        out.add("{s} {d} {s} {s} {s} fills {d} evictions {d}", .{ label, row, b.join(ways.items,
             " "), @tagName(cache.replacement), cache.order(row), set.fills, set.evictions });
    }
    return out;
}
fn finalStateOutput(state: *const Simulation) b.Lines {
    var out: b.Lines = .{};
    const in_l1 = b.zero(bool, state.facts.blocks.len, false);
    var in_l1_count: i64 = 0;
    for (state.l1[0..state.config.cores], 0..) |*cache, core| {
        out.extend(cacheRows(cache, b.fmt("c{d}", .{core}), state.config.line_size));
        var counts: [256]i64 = @splat(0);
        var total: i64 = 0;
        for (cache.sets) |set| for (set.entries[0..cache.ways]) |entry| if (entry) |value| {
            total += 1;
            counts[value.state] += 1;
            const id = state.facts.lineId(value.block);
            if (!in_l1[id]) {
                in_l1[id] = true;
                in_l1_count += 1;
            }
        };
        out.add("c{d} lines {d} M {d} O {d} E {d} S {d} V {d}", .{ core, total, counts['M'],
             counts['O'], counts['E'], counts['S'], counts['V'] });
    }
    out.extend(cacheRows(&state.l2, "L2", state.config.line_size));
    var dirty_count: i64 = 0;
    var clean_count: i64 = 0;
    for (state.l2.sets) |set| for (set.entries[0..state.l2.ways]) |entry| if (entry) |value| {
        dirty_count += @intFromBool(value.state == 'D');
        clean_count += @intFromBool(value.state == 'C');
    };
    out.add("L2 lines {d} dirty {d} clean {d} in_l1 {d}", .{ dirty_count + clean_count, dirty_count,
         clean_count, in_l1_count });
    return out;
}
fn section(out: *b.Lines, rows: b.Lines) void {
    if (out.data.items.len > 0) out.add("", .{});
    out.extend(rows);
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    b.allocator = arena.allocator();
    const config = try b.readConfig(init.io);
    const trace = try b.readLines(init.io, "input/trace.txt");
    const validated = validateTrace(trace, &config);
    const facts = buildFacts(validated.events.items, &config);
    const reuse = reuseAnalysis(validated.events.items, &facts, &config, init.gpa);
    var states: std.ArrayList(*Simulation) = .empty;
    defer {
        for (states.items) |state| state.arena.deinit();
    }
    var primary: *Simulation = undefined;
    for (config.scenarios.items) |*scenario| {
        const state = b.create(Simulation, .{ .arena = .init(init.gpa), .config = &config,
             .scenario = scenario, .events = validated.events.items, .facts = &facts, .l2 = undefined,
             .bus = .{ .latency = config.tb }, .primary = b.eq(scenario.name, config.primary) });
        const persistent = b.allocator;
        b.allocator = state.arena.allocator();
        state.run();
        b.allocator = persistent;
        if (state.primary) primary = state;
        b.append(*Simulation, &states, state);
    }
    var statistics: b.Lines = .{};
    section(&statistics, traceConfig(&config, trace, validated));
    section(&statistics, reuseLines(reuse, &config));
    for (states.items) |state| section(&statistics, scenarioReport(state));
    section(&statistics, ranking(states.items));
    section(&statistics, hotLines(primary));
    section(&statistics, intervalRows(primary));
    section(&statistics, slowestRows(primary));
    section(&statistics, regionRows(primary));
    try b.writeLines(init.io, "stats.txt", statistics);
    var transactions: b.Lines = .{};
    for (primary.bus.transactions.items) |tx| transactions.add("{s}", .{primary.bus.logLine(tx,
         config.line_size, config.cores)});
    try b.writeLines(init.io, "bus_log.txt", transactions);
    try b.writeLines(init.io, "watch.txt", primary.watch);
    try b.writeLines(init.io, "sharing.txt", sharingOutput(&facts, primary));
    try b.writeLines(init.io, "final_state.txt", finalStateOutput(primary));
}
