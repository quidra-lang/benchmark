const std = @import("std");
const h = @import("heap.zig");
const mutator = @import("mutator.zig");
const mark = @import("mark_sweep.zig");
const copying = @import("copying.zig");
const generational = @import("generational.zig");
fn reachable(heap: *const h.Heap) []bool {
    const marks = h.alloc(bool, heap.objects.items.len);
    @memset(marks, false);
    var stack: std.ArrayList(usize) = .empty;
    for (heap.roots.items) |root| if (root != 0 and !marks[root - 1]) {
        marks[root - 1] = true;
        h.append(usize, &stack, root);
    };
    while (stack.items.len > 0) {
        const id = stack.items[stack.items.len - 1];
        stack.items.len -= 1;
        for (heap.get(id).fields) |value| if (value != 0 and !marks[value - 1]) {
            marks[value - 1] = true;
            h.append(usize, &stack, value);
        };
    }
    return marks;
}
fn amount(heap: *const h.Heap, ids: []const bool) h.Pair {
    var pair: h.Pair = .{};
    for (heap.objects.items, ids) |object, included| if (included) pair.add(object.size());
    return pair;
}
fn slot(heap: *const h.Heap, index: i64) usize {
    return if (index < 0) 0 else heap.roots.items[h.u(index)];
}
fn executePlain(heap: *h.Heap, command: mutator.Command) void {
    const args = command.args;
    switch (command.kind) {
        .ALLOC => {
            const id = heap.objects.items.len + 1;
            h.append(h.Object, &heap.objects, h.Object.init(id, h.u(args[0]), h.u(args[1]), 0));
            h.append(usize, &heap.roots, id);
        },
        .PUSH => h.append(usize, &heap.roots, slot(heap, args[0])),
        .LOAD => h.append(usize, &heap.roots, heap.get(heap.roots.items[h.u(args[0])]).fields[h.u(args[1])]),
        .POP => heap.roots.items.len -= h.u(args[0]),
        .SET => heap.object(heap.roots.items[h.u(args[0])]).fields[h.u(args[1])] = slot(heap, args[2]),
        .OVERWRITE => heap.roots.items[h.u(args[0])] = slot(heap, args[1]),
        .CHECKPOINT => {},
    }
}
const Checkpoint = struct { label: []const u8, line: usize, roots: usize, live: h.Pair, allocated: h.Pair,
     phase: h.Pair, survivors: h.Pair };
const Reference = struct {
    heap: *h.Heap,
    commands: []const mutator.Command,
    errors: []const mutator.Command,
    death: []usize,
    lifetime: []i64,
    birth: []i64,
    checkpoints: []const Checkpoint,
    counts: [7]usize = @splat(0),
    allocated: h.Pair = .{},
    peak: h.Pair = .{},
    ending: h.Pair = .{},
    peak_line: usize = 0,
    line_count: usize,
    fn analyze(source: []const mutator.Command) Reference {
        var reference: Reference = .{ .heap = h.create(h.Heap, .{ .size = 0, .collector = .{ .name = "",
             .kind = .MARK_SWEEP } }), .commands = &.{}, .errors = &.{}, .death = h.alloc(usize, source.len),
             .lifetime = h.alloc(i64, source.len), .birth = h.alloc(i64, source.len), .checkpoints = &.{},
             .line_count = source.len };
        @memset(reference.death, 0);
        @memset(reference.lifetime, 0);
        var commands: std.ArrayList(mutator.Command) = .empty;
        var errors: std.ArrayList(mutator.Command) = .empty;
        var checkpoints: std.ArrayList(Checkpoint) = .empty;
        var phase_first: usize = 1;
        var phase: h.Pair = .{};
        const heap = reference.heap;
        for (source) |raw| {
            var command = raw;
            const roots = heap.roots.items.len;
            const kind = command.kind;
            const a = command.args;
            if (command.reason == null) {
                var invalid = ((kind == .ALLOC or kind == .PUSH or kind == .LOAD) and roots == 64) or (kind == .POP and a[0] > h.n(roots));
                if (kind == .LOAD or kind == .SET or kind == .OVERWRITE) invalid = invalid or a[0] >= h.n(roots);
                const r = if (kind == .PUSH) a[0] else if (kind == .SET) a[2] else if (kind == .OVERWRITE) a[1] else -1;
                if (r >= h.n(roots)) invalid = true;
                if (invalid) command.reason = "stack" else if ((kind == .LOAD or kind == .SET) and heap.roots.items[h.u(a[0])] == 0) command.reason = "null" else if ((kind == .LOAD or kind == .SET) and a[1] >= h.n(heap.get(heap.roots.items[h.u(a[0])]).p)) command.reason = "field" else if (kind == .CHECKPOINT) {
                    for (checkpoints.items) |checkpoint| if (h.eq(checkpoint.label, command.label)) {
                        command.reason = "duplicate";
                        break;
                    };
                }
            }
            if (command.reason != null) {
                h.append(mutator.Command, &errors, command);
                continue;
            }
            if (kind == .ALLOC) {
                command.object = heap.objects.items.len + 1;
                reference.birth[heap.objects.items.len] = reference.allocated.words;
                reference.allocated.add(h.u(1 + a[0] + a[1]));
                phase.add(h.u(1 + a[0] + a[1]));
            }
            if (kind == .CHECKPOINT) command.checkpoint = checkpoints.items.len;
            executePlain(heap, command);
            h.append(mutator.Command, &commands, command);
            reference.counts[@intFromEnum(kind)] += 1;
            const live = reachable(heap);
            reference.ending = amount(heap, live);
            for (heap.objects.items, live, 0..) |object, alive, index| if (reference.death[index] == 0 and !alive) {
                reference.death[index] = command.line;
                reference.lifetime[index] = reference.allocated.words - reference.birth[index] - h.n(object.size());
            };
            if (reference.ending.words > reference.peak.words) {
                reference.peak = reference.ending;
                reference.peak_line = command.line;
            }
            if (kind == .CHECKPOINT) {
                var survivors: h.Pair = .{};
                for (heap.objects.items, live) |object, alive| if (object.id >= phase_first and alive) survivors.add(object.size());
                h.append(Checkpoint, &checkpoints, .{ .label = command.label, .line = command.line,
                     .roots = heap.roots.items.len, .live = reference.ending, .allocated = reference.allocated,
                     .phase = phase, .survivors = survivors });
                phase = .{};
                phase_first = heap.objects.items.len + 1;
            }
        }
        reference.commands = commands.items;
        reference.errors = errors.items;
        reference.checkpoints = checkpoints.items;
        return reference;
    }
    fn report(self: *const Reference) h.Lines {
        var out: h.Lines = .{};
        out.add("script lines {d} valid {d} errors {d}", .{ self.line_count, self.commands.len, self.errors.len });
        for (self.errors) |command| out.add("error line {d} {s}", .{ command.line, command.reason.? });
        var commands: h.Text = .{};
        commands.add("commands", .{});
        for (self.counts, 0..) |count, index| commands.add(" {s} {d}", .{ @tagName(@as(mutator.Kind,
             @enumFromInt(index))), count });
        out.add("{s}", .{commands.value()});
        const sizes = h.alloc(usize, self.heap.objects.items.len);
        for (self.heap.objects.items, sizes) |object, *size| size.* = object.size();
        out.add("allocated objects {d} words {d} sizes {s}", .{ self.allocated.count, self.allocated.words,
             h.classTable(sizes) });
        out.add("peak_live objects {d} words {d} line {d}", .{ self.peak.count, self.peak.words, self.peak_line });
        out.add("end_live objects {d} words {d} stack {d}", .{ self.ending.count, self.ending.words, self.heap.roots.items.len });
        var lifetimes: [6]usize = @splat(0);
        for (self.heap.objects.items, 0..) |_, index| {
            const value = self.lifetime[index];
            lifetimes[if (self.death[index] == 0) 5 else if (value < 64) 0 else if (value < 256) 1 else if (value < 1024) 2 else if (value < 4096) 3 else 4] += 1;
        }
        out.add("lifetimes 0-63 {d} 64-255 {d} 256-1023 {d} 1024-4095 {d} 4096+ {d} live {d}", .{ lifetimes[0],
             lifetimes[1], lifetimes[2], lifetimes[3], lifetimes[4], lifetimes[5] });
        for (self.checkpoints) |checkpoint| out.add("checkpoint {s} line {d} stack {d} live {s} allocated {s} phase {s} survivors {s} survival {s}",
             .{ checkpoint.label, checkpoint.line, checkpoint.roots, checkpoint.live.text(), checkpoint.allocated.text(),
             checkpoint.phase.text(), checkpoint.survivors.text(), h.pct(checkpoint.survivors.words,
             checkpoint.phase.words) });
        return out;
    }
};
const Pause = struct { line: usize, work: i64, freed: h.Pair, collection: bool };
const PauseStats = struct { work: i64 = 0, freed: i64 = 0, maximum: i64 = 0, p50: []const u8 = "-", p90: []const u8 = "-" };
fn integerLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn pauseStats(pauses: []const Pause) PauseStats {
    var result: PauseStats = .{};
    const values = h.alloc(i64, pauses.len);
    for (pauses, values) |pause, *value| {
        result.work += pause.work;
        result.freed += pause.freed.words;
        result.maximum = @max(result.maximum, pause.work);
        value.* = pause.work;
    }
    if (pauses.len > 0) {
        std.mem.sort(i64, values, {}, integerLess);
        result.p50 = h.fmt("{d}", .{values[(50 * values.len + 99) / 100 - 1]});
        result.p90 = h.fmt("{d}", .{values[(90 * values.len + 99) / 100 - 1]});
    }
    return result;
}
const Segment = struct { end: i64, mutator: i64, active: bool };
const Timeline = struct {
    segments: std.ArrayList(Segment) = .empty,
    total: i64 = 0,
    mutator_units: i64 = 0,
    fn add(self: *Timeline, active: bool, length: i64) void {
        if (length == 0) return;
        self.total += length;
        if (active) self.mutator_units += length;
        const segment: Segment = .{ .end = self.total, .mutator = self.mutator_units, .active = active };
        if (self.segments.items.len > 0 and self.segments.items[self.segments.items.len - 1].active == active) self.segments.items[self.segments.items.len - 1] = segment else h.append(Segment,
             &self.segments, segment);
    }
    fn prefix(self: *const Timeline, time: i64) i64 {
        if (time <= 0) return 0;
        var first: usize = 0;
        var end = self.segments.items.len;
        while (first < end) {
            const middle = first + (end - first) / 2;
            if (self.segments.items[middle].end < time) first = middle + 1 else end = middle;
        }
        const before = if (first > 0) self.segments.items[first - 1].mutator else 0;
        const start = if (first > 0) self.segments.items[first - 1].end else 0;
        return before + if (self.segments.items[first].active) time - start else 0;
    }
    fn evaluate(self: *const Timeline, start: i64, width: i64, best: *i64) void {
        if (start < 0 or start + width > self.total) return;
        best.* = @min(best.*, self.prefix(start + width) - self.prefix(start));
    }
    fn mmu(self: *const Timeline, width: i64) []const u8 {
        if (width > self.total) return "-";
        var best = width;
        self.evaluate(0, width, &best);
        self.evaluate(self.total - width, width, &best);
        for (self.segments.items) |segment| {
            self.evaluate(segment.end, width, &best);
            self.evaluate(segment.end - width, width, &best);
        }
        return h.pct(best, width);
    }
};
const Cascade = struct { freed: h.Pair = .{}, work: i64 = 0, line: usize };
const Cycles = struct {
    heap: *const h.Heap,
    garbage: []const bool,
    parent: []usize,
    index: []i64,
    low: []i64,
    active: []bool,
    cyclic: []bool,
    stack: std.ArrayList(usize) = .empty,
    next: i64 = 0,
    fn find(self: *Cycles, id_: usize) usize {
        var root = id_;
        while (self.parent[root] != root) root = self.parent[root];
        var id = id_;
        while (self.parent[id] != id) {
            const next = self.parent[id];
            self.parent[id] = root;
            id = next;
        }
        return root;
    }
    fn visit(self: *Cycles, id: usize) void {
        self.index[id] = self.next;
        self.low[id] = self.next;
        self.next += 1;
        h.append(usize, &self.stack, id);
        self.active[id] = true;
        const object = self.heap.objects.items[id];
        for (object.fields) |value| {
            if (value == 0 or !self.garbage[value - 1]) continue;
            const target = value - 1;
            if (self.index[target] < 0) {
                self.visit(target);
                self.low[id] = @min(self.low[id], self.low[target]);
            } else if (self.active[target]) self.low[id] = @min(self.low[id], self.index[target]);
        }
        if (self.low[id] != self.index[id]) return;
        var first = self.stack.items.len - 1;
        while (self.stack.items[first] != id) first -= 1;
        var cycle = self.stack.items.len - first > 1;
        if (!cycle) for (object.fields) |value| if (value == id + 1) {
            cycle = true;
        };
        while (self.stack.items.len > first) {
            const value = self.stack.items[self.stack.items.len - 1];
            self.stack.items.len -= 1;
            self.active[value] = false;
            self.cyclic[value] = cycle;
        }
    }
};
const Run = struct {
    config: *const mutator.Config,
    reference: *const Reference,
    heap: *h.Heap,
    collections: std.ArrayList(h.Collection) = .empty,
    pauses: std.ArrayList(Pause) = .empty,
    timeline: Timeline = .{},
    leaks: h.Lines = .{},
    observations: []h.Lines,
    increments: i64 = 0,
    decrements: i64 = 0,
    cascades: std.ArrayList(Cascade) = .empty,
    peak_used: i64 = 0,
    oom_line: usize = 0,
    oom_size: usize = 0,
    fn init(config: *const mutator.Config, reference: *const Reference, collector: h.Collector) *Run {
        const observations = h.alloc(h.Lines, reference.checkpoints.len);
        @memset(observations, .{});
        return h.create(Run, .{ .config = config, .reference = reference, .heap = h.create(h.Heap,
             .{ .size = config.heap, .collector = collector }), .observations = observations });
    }
    fn retain(self: *Run, id: usize) void {
        if (id != 0) {
            self.heap.object(id).references += 1;
            self.increments += 1;
        }
    }
    fn release(self: *Run, id: usize, cascade: *Cascade) void {
        var stack: std.ArrayList(usize) = .empty;
        if (id != 0) h.append(usize, &stack, id);
        while (stack.items.len > 0) {
            const current = stack.items[stack.items.len - 1];
            stack.items.len -= 1;
            const object = self.heap.object(current);
            self.decrements += 1;
            object.references -= 1;
            if (object.references != 0) continue;
            object.present = false;
            cascade.freed.add(object.size());
            cascade.work += h.n(1 + object.p);
            var field = object.fields.len;
            while (field > 0) {
                field -= 1;
                if (object.fields[field] != 0) h.append(usize, &stack, object.fields[field]);
            }
        }
    }
    fn garbage(self: *const Run, live: []const bool) []bool {
        const result = h.alloc(bool, self.heap.objects.items.len);
        for (self.heap.objects.items, live, result) |object, alive, *value| value.* = object.present and !alive;
        return result;
    }
    fn leakReport(self: *const Run, title: []const u8, garbage: []const bool) h.Lines {
        const count = self.heap.objects.items.len;
        var context: Cycles = .{ .heap = self.heap, .garbage = garbage, .parent = h.alloc(usize, count),
             .index = h.alloc(i64, count), .low = h.alloc(i64, count), .active = h.alloc(bool, count),
             .cyclic = h.alloc(bool, count) };
        @memset(context.index, -1);
        @memset(context.active, false);
        @memset(context.cyclic, false);
        for (context.parent, 0..) |*value, id| value.* = id;
        for (self.heap.objects.items, garbage, 0..) |object, included, id| if (included) {
            for (object.fields) |value| if (value != 0 and garbage[value - 1]) {
                context.parent[context.find(id)] = context.find(value - 1);
            };
        };
        for (garbage, 0..) |included, id| if (included and context.index[id] < 0) context.visit(id);
        const seen = h.alloc(bool, count);
        @memset(seen, false);
        var groups: std.ArrayList(usize) = .empty;
        for (garbage, 0..) |included, id| if (included) {
            const root = context.find(id);
            if (!seen[root]) {
                seen[root] = true;
                h.append(usize, &groups, root);
            }
        };
        const all = amount(self.heap, garbage);
        var out: h.Lines = .{};
        out.add("{s} groups {d} objects {d} words {d}", .{ title, groups.items.len, all.count, all.words });
        for (groups.items, 1..) |root, number| {
            var pair: h.Pair = .{};
            var died: usize = 0;
            var cycle_count: usize = 0;
            var ids: h.Text = .{};
            for (self.heap.objects.items, garbage, 0..) |object, included, id| if (included and context.find(id) == root) {
                pair.add(object.size());
                died = @max(died, self.reference.death[id]);
                if (context.cyclic[id]) cycle_count += 1;
                ids.add(" {d}{s}", .{ id + 1, if (context.cyclic[id]) "*" else "" });
            };
            out.add("group {d} objects {d} words {d} cycle {d} died {d} ids{s}", .{ number, pair.count,
                 pair.words, cycle_count, died, ids.value() });
        }
        return out;
    }
    fn collect(self: *Run, kind: []const u8, line: usize, request: usize) bool {
        var record: h.Collection = .{ .number = self.collections.items.len + 1, .line = line, .request = request, .kind = kind };
        record.before = h.freeAmount(self.heap);
        var complete = true;
        if (h.eq(kind, "sweep")) mark.collectSweep(self.heap, &record) else if (h.eq(kind, "compact")) mark.collectCompact(self.heap,
             &record) else if (h.eq(kind, "copy")) copying.collect(self.heap, &record) else if (h.eq(kind,
             "backup")) {
            mark.mark(self.heap, &record);
            const garbage = h.alloc(bool, self.heap.objects.items.len);
            for (self.heap.objects.items, garbage) |object, *value| value.* = object.present and !object.marked;
            self.leaks.extend(self.leakReport(h.fmt("backup {d} line {d}", .{ record.number, line }), garbage));
            mark.sweep(self.heap, &record, false);
            for (self.heap.objects.items, garbage) |object, included| if (included) {
                for (object.fields) |value| if (value != 0 and self.heap.get(value).marked) {
                    self.heap.object(value).references -= 1;
                    self.decrements += 1;
                };
            };
        } else complete = generational.collect(self.heap, &record);
        if (!complete) return false;
        record.after = h.freeAmount(self.heap);
        h.append(h.Collection, &self.collections, record);
        h.append(Pause, &self.pauses, .{ .line = line, .work = record.work, .freed = record.freed, .collection = true });
        self.timeline.add(false, record.work);
        return true;
    }
    fn allocationAddress(self: *const Run, size: usize) ?usize {
        const heap = self.heap;
        const kind = heap.collector.kind;
        if (kind == .MARK_SWEEP or kind == .REFCOUNT) return h.firstFit(heap, size, 0, heap.size);
        const capacity = if (kind == .COPYING) heap.size / 2 else if (kind == .GENERATIONAL) heap.collector.young / 2 else heap.size;
        return if (heap.top + size <= heap.base + capacity) heap.top else null;
    }
    fn generationalKind(self: *const Run, second: bool) []const u8 {
        var largest: usize = 0;
        for (h.rangeBlocks(self.heap, self.heap.collector.young, self.heap.size)) |block| largest = @max(largest, block.length);
        return if (largest < self.heap.top - self.heap.base) (if (second) "full" else "major") else (if (second) "tenure" else "minor");
    }
    fn allocate(self: *Run, command: mutator.Command) bool {
        const size = h.u(1 + command.args[0] + command.args[1]);
        var address = self.allocationAddress(size);
        if (address == null) {
            if (self.heap.collector.kind == .GENERATIONAL) {
                if (!self.collect(self.generationalKind(false), command.line, size)) return false;
                address = self.allocationAddress(size);
                if (address == null) {
                    if (!self.collect(self.generationalKind(true), command.line, size)) return false;
                    address = self.allocationAddress(size);
                }
            } else {
                const kind = switch (self.heap.collector.kind) {
                    .MARK_SWEEP => "sweep",
                    .MARK_COMPACT => "compact",
                    .COPYING => "copy",
                    .REFCOUNT => "backup",
                    .GENERATIONAL => unreachable,
                };
                _ = self.collect(kind, command.line, size);
                address = self.allocationAddress(size);
            }
        }
        if (address == null) return false;
        h.append(h.Object, &self.heap.objects, h.Object.init(command.object, h.u(command.args[0]),
             h.u(command.args[1]), address.?));
        if (self.heap.collector.kind != .MARK_SWEEP and self.heap.collector.kind != .REFCOUNT) self.heap.top = address.? + size;
        if (self.heap.collector.kind == .REFCOUNT) self.retain(command.object);
        h.append(usize, &self.heap.roots, command.object);
        self.peak_used = @max(self.peak_used, h.used(self.heap));
        return true;
    }
    fn observe(self: *Run, command: mutator.Command) void {
        const heap = self.heap;
        const live = reachable(heap);
        const dead = self.garbage(live);
        var all: h.Pair = .{};
        for (heap.objects.items) |object| if (object.present) all.add(object.size());
        const out = &self.observations[command.checkpoint];
        out.add("heap objects {s} reachable {s} garbage {s}", .{ all.text(), amount(heap, live).text(),
             amount(heap, dead).text() });
        const blocks = h.freeBlocks(heap);
        const free = h.freeAmount(heap);
        const sizes = h.alloc(usize, blocks.len);
        for (blocks, sizes) |block, *size| size.* = block.length;
        out.add("free total {d} largest {d} blocks {d} sizes {s} fragmentation {s}", .{ free[0], free[1],
             blocks.len, h.classTable(sizes), h.pct(free[0] - free[1], free[0]) });
        var pointers: i64 = 0;
        var forward: i64 = 0;
        var backward: i64 = 0;
        var distance: i64 = 0;
        for (heap.objects.items, live) |object, alive| if (alive) {
            for (object.fields) |value| if (value != 0) {
                pointers += 1;
                const delta = h.n(heap.get(value).address) - h.n(object.address);
                if (delta > 0) forward += 1;
                if (delta < 0) backward += 1;
                distance += @intCast(@abs(delta));
            };
        };
        out.add("locality pointers {d} forward {d} backward {d} mean_distance {s}", .{ pointers, forward,
             backward, if (pointers == 0) "-" else h.dec2(distance, pointers) });
        if (heap.collector.kind == .GENERATIONAL) {
            var young: h.Pair = .{};
            var old: h.Pair = .{};
            var ages: [4]usize = @splat(0);
            var remembered: usize = 0;
            for (heap.objects.items) |object| {
                if (heap.remembered[object.id - 1]) remembered += 1;
                if (!object.present) continue;
                if (object.address < heap.collector.young) {
                    young.add(object.size());
                    ages[@min(3, object.age)] += 1;
                } else old.add(object.size());
            }
            out.add("generations young {s} old {s} remembered {d} ages 0:{d} 1:{d} 2:{d} 3+:{d}",
                 .{ young.text(), old.text(), remembered, ages[0], ages[1], ages[2], ages[3] });
        }
        var draw = false;
        for (self.config.maps) |label| if (h.eq(label, command.label)) {
            draw = true;
        };
        if (draw) {
            const map = h.heapMap(heap, live);
            var first: usize = 0;
            while (first < heap.size) : (first += self.config.width) out.add("{d:0>4} {s}", .{ first,
                 map[first .. first + self.config.width] });
        }
    }
    fn execute(self: *Run) void {
        for (self.reference.commands) |command| {
            var cascade: Cascade = .{ .line = command.line };
            const heap = self.heap;
            const a = command.args;
            const rc = heap.collector.kind == .REFCOUNT;
            switch (command.kind) {
                .ALLOC => if (!self.allocate(command)) {
                    self.oom_line = command.line;
                    self.oom_size = h.u(1 + a[0] + a[1]);
                    break;
                },
                .PUSH, .LOAD => {
                    const value = if (command.kind == .PUSH) slot(heap, a[0]) else heap.get(heap.roots.items[h.u(a[0])]).fields[h.u(a[1])];
                    if (rc) self.retain(value);
                    h.append(usize, &heap.roots, value);
                },
                .POP => for (0..h.u(a[0])) |_| {
                    const value = heap.roots.items[heap.roots.items.len - 1];
                    heap.roots.items.len -= 1;
                    if (rc) self.release(value, &cascade);
                },
                .SET => {
                    const target = heap.roots.items[h.u(a[0])];
                    const value = slot(heap, a[2]);
                    const before = heap.get(target).fields[h.u(a[1])];
                    if (heap.collector.kind == .GENERATIONAL) generational.barrier(heap, target, value);
                    if (rc) self.retain(value);
                    heap.object(target).fields[h.u(a[1])] = value;
                    if (rc) self.release(before, &cascade);
                },
                .OVERWRITE => {
                    const value = slot(heap, a[1]);
                    const before = heap.roots.items[h.u(a[0])];
                    if (rc) self.retain(value);
                    heap.roots.items[h.u(a[0])] = value;
                    if (rc) self.release(before, &cascade);
                },
                .CHECKPOINT => {},
            }
            self.timeline.add(true, if (command.kind == .ALLOC) 1 + a[0] + a[1] else 1);
            if (cascade.freed.count > 0) {
                h.append(Cascade, &self.cascades, cascade);
                h.append(Pause, &self.pauses, .{ .line = command.line, .work = cascade.work, .freed = cascade.freed,
                     .collection = false });
                self.timeline.add(false, cascade.work);
            }
            if (command.kind == .CHECKPOINT) self.observe(command);
        }
        if (self.heap.collector.kind == .REFCOUNT and self.oom_line == 0) self.leaks.extend(self.leakReport("end",
             self.garbage(reachable(self.heap))));
    }
    fn collectionReport(self: *const Run) h.Lines {
        var out: h.Lines = .{};
        out.add("collector {s} {s}", .{ self.heap.collector.name, @tagName(self.heap.collector.kind) });
        for (self.collections.items) |record| out.add("{d} line {d} size {d} kind {s} live {s} freed {s} moved {s} promoted {s} stack {d} work {d} before {d} {d} after {d} {d}",
             .{ record.number, record.line, record.request, record.kind, record.live.text(), record.freed.text(),
             record.moved.text(), record.promoted.text(), record.stack, record.work, record.before[0],
             record.before[1], record.after[0], record.after[1] });
        const stats = pauseStats(self.pauses.items);
        out.add("totals collections {d} pauses {d} work {d} freed {d} pause p50 {s} p90 {s} max {d}",
             .{ self.collections.items.len, self.pauses.items.len, stats.work, stats.freed, stats.p50,
             stats.p90, stats.maximum });
        var utilization: h.Text = .{};
        utilization.add("utilization {s} mmu", .{h.pct(self.timeline.mutator_units, self.timeline.total)});
        for (self.config.windows) |width| utilization.add(" {d}:{s}", .{ width, self.timeline.mmu(width) });
        out.add("{s}", .{utilization.value()});
        if (self.heap.collector.kind == .GENERATIONAL) {
            var line: h.Text = .{};
            line.add("generational", .{});
            for ([_][]const u8{ "minor", "major", "tenure", "full" }) |kind| {
                var count: usize = 0;
                var work: i64 = 0;
                for (self.collections.items) |record| if (h.eq(record.kind, kind)) {
                    count += 1;
                    work += record.work;
                };
                line.add(" {s} {d} {d}", .{ kind, count, work });
            }
            var promotions: h.Pair = .{};
            for (self.collections.items) |record| promotions.merge(record.promoted);
            line.add(" promoted {s} barrier {d} remembered {d}", .{ promotions.text(), self.heap.barriers, self.heap.remembers });
            out.add("{s}", .{line.value()});
        }
        if (self.heap.collector.kind == .REFCOUNT) {
            var freed: h.Pair = .{};
            var largest: ?Cascade = null;
            for (self.cascades.items) |cascade| {
                freed.merge(cascade.freed);
                if (largest == null or cascade.work > largest.?.work) largest = cascade;
            }
            out.add("refcount increments {d} decrements {d} cascades {d} freed {s} max_cascade {d} {d} line {s}",
                 .{ self.increments, self.decrements, self.cascades.items.len, freed.text(), if (largest) |value| value.freed.count else 0,
                 if (largest) |value| value.work else 0, if (largest) |value| h.fmt("{d}", .{value.line}) else "-" });
        }
        var previous: usize = 0;
        for (self.reference.checkpoints, self.observations) |checkpoint, observation| {
            if (observation.data.items.len == 0) {
                out.add("phase {s} out_of_memory", .{checkpoint.label});
                continue;
            }
            var phase: std.ArrayList(Pause) = .empty;
            var count: usize = 0;
            for (self.pauses.items) |pause| if (pause.line > previous and pause.line <= checkpoint.line) {
                h.append(Pause, &phase, pause);
                if (pause.collection) count += 1;
            };
            const stats_ = pauseStats(phase.items);
            out.add("phase {s} collections {d} pauses {d} work {d} freed {d} max_pause {d}", .{ checkpoint.label,
                 count, phase.items.len, stats_.work, stats_.freed, stats_.maximum });
            previous = checkpoint.line;
        }
        if (self.oom_line > 0) out.add("status out_of_memory line {d} size {d}", .{ self.oom_line,
             self.oom_size }) else out.add("status completed", .{});
        return out;
    }
    fn summary(self: *const Run) []const u8 {
        const stats = pauseStats(self.pauses.items);
        var live: i64 = 0;
        var moved: i64 = 0;
        var moved_objects: usize = 0;
        var max_moves: usize = 0;
        for (self.collections.items) |record| {
            live += record.live.count;
            moved += record.moved.count;
        }
        for (self.heap.objects.items) |object| {
            if (object.moves > 0) moved_objects += 1;
            max_moves = @max(max_moves, object.moves);
        }
        var text: h.Text = .{};
        text.add("{s},{s},{s},{d},{d},{d},{d},{d},{d},{d},{d},{s},{s},{d},{d}", .{ self.heap.collector.name,
             @tagName(self.heap.collector.kind), if (self.oom_line > 0) "out_of_memory" else "completed",
             self.collections.items.len, self.pauses.items.len, live, moved, moved_objects, max_moves,
             stats.freed, stats.work, stats.p50, stats.p90, stats.maximum, self.peak_used });
        if (self.oom_line > 0) text.add(",-,-,-,-", .{}) else {
            const free = h.freeAmount(self.heap);
            text.add(",{d},{d},{d},{s}", .{ h.used(self.heap), free[0], free[1], h.pct(free[0] - free[1], free[0]) });
        }
        return text.value();
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    h.allocator = arena.allocator();
    const config = try mutator.readConfig(init.io);
    const source = try mutator.readCommands(init.io);
    const reference = Reference.analyze(source);
    try h.writeLines(init.io, "mutator.txt", reference.report());
    const runs = h.alloc(*Run, config.collectors.len);
    for (config.collectors, runs) |collector, *run| {
        run.* = Run.init(&config, &reference, collector);
        run.*.execute();
    }
    var maps: h.Lines = .{};
    for (reference.checkpoints, 0..) |checkpoint, index| for (runs) |run| {
        if (maps.data.items.len > 0) maps.blank();
        maps.add("checkpoint {s} line {d} collector {s}", .{ checkpoint.label, checkpoint.line, run.heap.collector.name });
        if (run.observations[index].data.items.len == 0) maps.add("out_of_memory", .{}) else maps.extend(run.observations[index]);
    };
    try h.writeLines(init.io, "heap_maps.txt", maps);
    var collections: h.Lines = .{};
    var summary: h.Lines = .{};
    var leaks: h.Lines = .{};
    summary.add("collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation",
         .{});
    for (runs, 0..) |run, index| {
        if (index > 0) collections.blank();
        collections.extend(run.collectionReport());
        summary.add("{s}", .{run.summary()});
        if (run.heap.collector.kind == .REFCOUNT) {
            if (leaks.data.items.len > 0) leaks.blank();
            leaks.add("collector {s}", .{run.heap.collector.name});
            leaks.extend(run.leaks);
            if (run.oom_line > 0) leaks.add("status out_of_memory", .{});
        }
    }
    if (leaks.data.items.len == 0) leaks.add("none", .{});
    try h.writeLines(init.io, "collections.txt", collections);
    try h.writeLines(init.io, "summary.csv", summary);
    try h.writeLines(init.io, "leaks.txt", leaks);
}
