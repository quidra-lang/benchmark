const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;

fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
fn asU(value: i64) usize {
    return @intCast(value);
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn ceil(n: i64, d: i64) i64 {
    return @divTrunc(n + d - 1, d);
}
fn letter(id: usize) u8 {
    return @as(u8, @intCast(id)) + 64;
}
fn descItem(_: void, a: Item, b: Item) bool {
    if (a.size != b.size) return a.size > b.size;
    return a.id < b.id;
}
fn ascNumber(_: void, a: i64, b: i64) bool {
    return a < b;
}
const Item = struct {
    id: usize,
    size: i64,
};
const Bin = struct {
    items: std.ArrayList(Item) = .empty,
    load: i64 = 0,
    category: ?i64 = null,

    fn put(self: *Bin, gpa: Allocator, item: Item) Allocator.Error!void {
        try self.items.append(gpa, item);
        self.load += item.size;
    }
    fn copy(self: Bin, gpa: Allocator) Allocator.Error!Bin {
        var result: Bin = .{ .load = self.load, .category = self.category };
        try result.items.appendSlice(gpa, self.items.items);
        return result;
    }
};
const Step = struct {
    item: Item,
    destination: usize,
    inspected: usize,
    opened: bool,
    closed: ?usize,
    category: ?i64,
};
const Packing = struct {
    method: []const u8,
    parameter: i64,
    bins: std.ArrayList(Bin) = .empty,
    steps: std.ArrayList(Step) = .empty,
    inspections: usize = 0,
    closes: usize = 0,

    fn header(self: *const Packing, out: *std.Io.Writer, capacity: i64, total: i64) std.Io.Writer.Error!void {
        try out.writeAll(self.method);
        if (eq(self.method, "HARMONIC") or eq(self.method, "KBOUNDED"))
            try out.print(" k={d}", .{self.parameter});
        try out.print(" bins={d} inspections={d} waste={d}", .{
            self.bins.items.len, self.inspections,
            @as(i64, @intCast(self.bins.items.len)) * capacity - total,
        });
        if (eq(self.method, "KBOUNDED")) try out.print(" closes={d}", .{self.closes});
        try out.writeAll("\n");
    }
};
const BoundRow = struct {
    alpha: i64,
    j1: usize,
    j2: usize,
    j3: usize,
    value: i64,
};
const Bound = struct {
    l1: i64,
    l2: i64,
    rows: std.ArrayList(BoundRow),
};
fn descending(gpa: Allocator, items: []const Item) Allocator.Error!std.ArrayList(Item) {
    var result: std.ArrayList(Item) = .empty;
    try result.appendSlice(gpa, items);
    std.mem.sort(Item, result.items, {}, descItem);
    return result;
}
fn cloneBins(gpa: Allocator, bins: []const Bin) Allocator.Error!std.ArrayList(Bin) {
    var result: std.ArrayList(Bin) = .empty;
    for (bins) |bin| try result.append(gpa, try bin.copy(gpa));
    return result;
}
fn pack(gpa: Allocator, items: []const Item, capacity: i64, method: []const u8, parameter: i64) Allocator.Error!Packing {
    var result: Packing = .{ .method = method, .parameter = parameter };
    var sorted: std.ArrayList(Item) = .empty;
    const offline = eq(method, "FFD") or eq(method, "BFD") or eq(method, "WFD");
    if (offline) sorted = try descending(gpa, items);
    const ordered = if (offline) sorted.items else items;
    var active: std.ArrayList(usize) = .empty;
    var current: [51]?usize = @splat(null);

    for (ordered) |item| {
        const before = result.inspections;
        var destination: ?usize = null;
        var closed: ?usize = null;
        var category: ?i64 = null;
        const size = item.size;

        if (eq(method, "NEXTFIT")) {
            if (result.bins.items.len > 0) {
                result.inspections += 1;
                const index = result.bins.items.len - 1;
                if (result.bins.items[index].load + size <= capacity) destination = index;
            }
        } else if (eq(method, "HARMONIC")) {
            category = @min(@divTrunc(capacity, size), parameter);
            if (current[asU(category.?)]) |index| {
                result.inspections += 1;
                if (result.bins.items[index].load + size <= capacity) destination = index;
            }
        } else if (eq(method, "FIRSTFIT") or eq(method, "FFD") or eq(method, "KBOUNDED")) {
            if (eq(method, "KBOUNDED")) {
                for (active.items) |index| {
                    result.inspections += 1;
                    if (result.bins.items[index].load + size <= capacity) {
                        destination = index;
                        break;
                    }
                }
            } else {
                for (result.bins.items, 0..) |bin, index| {
                    result.inspections += 1;
                    if (bin.load + size <= capacity) {
                        destination = index;
                        break;
                    }
                }
            }
        } else {
            result.inspections += result.bins.items.len;
            var smallest: ?usize = null;
            var second_smallest: ?usize = null;
            var largest: ?usize = null;
            for (result.bins.items, 0..) |bin, index| {
                if (bin.load + size > capacity) continue;
                if (smallest == null or bin.load < result.bins.items[smallest.?].load) {
                    second_smallest = smallest;
                    smallest = index;
                } else if (second_smallest == null or bin.load < result.bins.items[second_smallest.?].load) {
                    second_smallest = index;
                }
                if (largest == null or bin.load > result.bins.items[largest.?].load) largest = index;
            }
            if (eq(method, "BESTFIT") or eq(method, "BFD")) {
                destination = largest;
            } else if (eq(method, "ALMOSTWORST")) {
                destination = if (second_smallest) |index| index else smallest;
            } else {
                destination = smallest;
            }
        }
        const opened = destination == null;
        if (opened) {
            if (eq(method, "KBOUNDED") and active.items.len == asU(parameter)) {
                var index_in_active: usize = 0;
                for (active.items, 0..) |index, position| {
                    const earlier = active.items[index_in_active];
                    if (result.bins.items[index].load > result.bins.items[earlier].load) index_in_active = position;
                }
                closed = active.orderedRemove(index_in_active);
                result.closes += 1;
            }
            destination = result.bins.items.len;
            try result.bins.append(gpa, .{ .category = category });
            if (eq(method, "KBOUNDED")) try active.append(gpa, destination.?);
            if (category) |class| current[asU(class)] = destination.?;
        }
        try result.bins.items[destination.?].put(gpa, item);
        try result.steps.append(gpa, .{
            .item = item,
            .destination = destination.?,
            .inspected = result.inspections - before,
            .opened = opened,
            .closed = closed,
            .category = category,
        });
    }
    return result;
}
fn bounds(gpa: Allocator, items: []const Item, capacity: i64) Allocator.Error!Bound {
    var thresholds: std.ArrayList(i64) = .empty;
    try thresholds.append(gpa, 0);
    var total: i64 = 0;
    for (items) |item| {
        total += item.size;
        if (2 * item.size <= capacity) {
            var seen = false;
            for (thresholds.items) |v| {
                if (v == item.size) {
                    seen = true;
                    break;
                }
            }
            if (!seen) try thresholds.append(gpa, item.size);
        }
    }
    std.mem.sort(i64, thresholds.items, {}, ascNumber);
    var result: Bound = .{ .l1 = ceil(total, capacity), .l2 = 0, .rows = .empty };
    for (thresholds.items) |alpha| {
        var j1: usize = 0;
        var j2: usize = 0;
        var j3: usize = 0;
        var middle: i64 = 0;
        var small: i64 = 0;
        for (items) |item| {
            const size = item.size;
            if (size > capacity - alpha) {
                j1 += 1;
            } else if (2 * size > capacity) {
                j2 += 1;
                middle += size;
            }
            if (2 * size <= capacity and size >= alpha) {
                j3 += 1;
                small += size;
            }
        }
        const excess = small - (@as(i64, @intCast(j2)) * capacity - middle);
        const value = @as(i64, @intCast(j1 + j2)) + (if (excess > 0) ceil(excess, capacity) else @as(i64, 0));
        result.l2 = @max(result.l2, value);
        try result.rows.append(gpa, .{ .alpha = alpha, .j1 = j1, .j2 = j2, .j3 = j3, .value = value });
    }
    return result;
}
const Search = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    items: std.ArrayList(Item),
    capacity: i64,
    limit: usize,
    lower: i64,
    best: std.ArrayList(Bin),
    live: std.ArrayList(Bin) = .empty,
    nodes: usize = 0,
    status: ?[]const u8 = null,
    remaining: [41]i64 = @splat(0),

    fn init(gpa: Allocator, out: *std.Io.Writer, items: []const Item, capacity: i64, limit: usize, lower: i64, incumbent: []const Bin) Allocator.Error!Search {
        const ordered = try descending(gpa, items);
        var search: Search = .{
            .gpa = gpa, .out = out, .items = ordered,
            .capacity = capacity, .limit = limit, .lower = lower,
            .best = try cloneBins(gpa, incumbent),
        };
        var i = items.len;
        while (i > 0) {
            i -= 1;
            search.remaining[i] = search.remaining[i + 1] + ordered.items[i].size;
        }
        return search;
    }
    fn visit(self: *Search, index: usize) Error!void {
        if (self.nodes == self.limit) {
            self.status = "limit";
            return;
        }
        self.nodes += 1;
        const count = self.live.items.len;
        const used = self.remaining[0] - self.remaining[index];
        const free = @as(i64, @intCast(count)) * self.capacity - used;
        const excess = self.remaining[index] - free;
        const minimum = @as(i64, @intCast(count)) + (if (excess > 0) ceil(excess, self.capacity) else @as(i64, 0));
        if (minimum >= @as(i64, @intCast(self.best.items.len))) return;
        if (index == self.items.items.len) {
            self.best = try cloneBins(self.gpa, self.live.items);
            try self.out.print("IMPROVE bins={d} nodes={d}\n", .{ count, self.nodes });
            if (@as(i64, @intCast(count)) == self.lower) self.status = "bound";
            return;
        }
        const item = self.items.items[index];
        var seen: [40]i64 = undefined;
        var seen_length: usize = 0;
        for (0..count) |bin_index| {
            var bin = &self.live.items[bin_index];
            const old_load = bin.load;
            var duplicated = false;
            for (seen[0..seen_length]) |load| {
                if (load == old_load) {
                    duplicated = true;
                    break;
                }
            }
            if (duplicated) continue;
            seen[seen_length] = old_load;
            seen_length += 1;
            if (old_load + item.size > self.capacity) continue;
            try bin.put(self.gpa, item);
            try self.visit(index + 1);
            bin = &self.live.items[bin_index];
            bin.items.items.len -= 1;
            bin.load = old_load;
            if (self.status != null) return;
        }
        if (count + 1 < self.best.items.len) {
            var bin: Bin = .{};
            try bin.put(self.gpa, item);
            try self.live.append(self.gpa, bin);
            try self.visit(index + 1);
            self.live.items.len -= 1;
        }
    }
};
const Move = struct {
    item: Item,
    destination: usize,
};
const CutPiece = struct {
    size: i64,
    demand: i64,
};
const Pattern = struct {
    counts: [6]i64 = @splat(0),
    trim: i64,
};
fn descPiece(_: void, a: CutPiece, b: CutPiece) bool {
    return a.size > b.size;
}
const PatternSearch = struct {
    gpa: Allocator,
    bar_length: i64,
    pieces: []const CutPiece,
    patterns: std.ArrayList(Pattern) = .empty,
    counts: [6]i64 = @splat(0),

    fn visit(self: *PatternSearch, index: usize, remaining: i64) Allocator.Error!void {
        const maximum = @divTrunc(remaining, self.pieces[index].size);
        if (index + 1 == self.pieces.len) {
            self.counts[index] = maximum;
            try self.patterns.append(self.gpa, .{
                .counts = self.counts,
                .trim = remaining - maximum * self.pieces[index].size,
            });
            return;
        }
        var quantity = maximum;
        while (true) {
            self.counts[index] = quantity;
            try self.visit(index + 1, remaining - quantity * self.pieces[index].size);
            if (quantity == 0) break;
            quantity -= 1;
        }
    }
};
const Rect = struct {
    id: usize,
    w: i64,
    h: i64,
};
const Placement = struct {
    rect: Rect,
    x: i64,
    y: i64,
    w: i64,
    h: i64,
    rotated: bool = false,
};
const Shelf = struct {
    bottom: i64,
    height: i64,
    used: i64 = 0,
    items: std.ArrayList(Placement) = .empty,
};
const Free = struct {
    x: i64,
    y: i64,
    w: i64,
    h: i64,
};
const Sheet = struct {
    free: std.ArrayList(Free) = .empty,
    placed: std.ArrayList(Placement) = .empty,
    area: i64 = 0,
};
fn shelfDescending(_: void, a: Rect, b: Rect) bool {
    if (a.h != b.h) return a.h > b.h;
    if (a.w != b.w) return a.w > b.w;
    return a.id < b.id;
}
fn areaDescending(_: void, a: Rect, b: Rect) bool {
    if (a.w * a.h != b.w * b.h) return a.w * a.h > b.w * b.h;
    return a.id < b.id;
}

const Lab = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    capacity: ?i64 = null,
    items: std.ArrayList(Item) = .empty,
    total: i64 = 0,
    reason: []const u8 = "",

    fn fail(self: *Lab, message: []const u8) Error {
        self.reason = message;
        return error.BadCommand;
    }
    fn failNumber(self: *Lab, message: []const u8, index: usize) Error!void {
        self.reason = try std.fmt.allocPrint(self.gpa, "{s} {d}", .{ message, index });
        return error.BadCommand;
    }
    fn printBin(self: *Lab, number_: usize, bin: Bin, cap: i64, classified: bool, over: bool) std.Io.Writer.Error!void {
        try self.out.print("BIN {d} load={d}/{d} items=", .{ number_, bin.load, cap });
        for (bin.items.items, 0..) |item, index| {
            if (index != 0) try self.out.writeAll(" ");
            try self.out.print("{d}:{d}", .{ item.id, item.size });
        }
        if (classified) try self.out.print(" class={d}", .{bin.category.?});
        if (over) try self.out.writeAll(" OVER");
        try self.out.writeAll("\n");
    }
    fn printBins(self: *Lab, bins: []const Bin, cap: i64, classified: bool) std.Io.Writer.Error!void {
        for (bins, 0..) |bin, index| try self.printBin(index + 1, bin, cap, classified, false);
    }
    fn outputMethod(self: *Lab, method: []const u8, parameter: i64) Error!void {
        const result = try pack(self.gpa, self.items.items, self.capacity.?, method, parameter);
        try result.header(self.out, self.capacity.?, self.total);
        try self.printBins(result.bins.items, self.capacity.?, eq(method, "HARMONIC"));
    }
    fn outputTrace(self: *Lab, method: []const u8, parameter: i64) Error!void {
        const result = try pack(self.gpa, self.items.items, self.capacity.?, method, parameter);
        try self.out.writeAll("TRACE ");
        try result.header(self.out, self.capacity.?, self.total);
        for (result.steps.items, 0..) |step, index| {
            try self.out.print("STEP {d} item={d}:{d} bin={d} inspected={d}", .{
                index + 1, step.item.id, step.item.size, step.destination + 1, step.inspected,
            });
            if (step.opened) try self.out.writeAll(" new");
            if (step.closed) |closed| try self.out.print(" closed={d}", .{closed + 1});
            if (step.category) |class| try self.out.print(" class={d}", .{class});
            try self.out.writeAll("\n");
        }
    }
    fn outputReduce(self: *Lab, method: []const u8, parameter: i64) Error!void {
        var result = try pack(self.gpa, self.items.items, self.capacity.?, method, parameter);
        const before = result.bins.items.len;
        var events: std.ArrayList([]const u8) = .empty;
        while (true) {
            var removed = false;
            var order: std.ArrayList(usize) = .empty;
            for (result.bins.items, 0..) |_, index| try order.append(self.gpa, index);
            const Ctx = struct {
                bins: []const Bin,
                fn less(ctx: @This(), a: usize, b: usize) bool {
                    if (ctx.bins[a].load != ctx.bins[b].load) return ctx.bins[a].load < ctx.bins[b].load;
                    return a < b;
                }
            };
            std.mem.sort(usize, order.items, Ctx{ .bins = result.bins.items }, Ctx.less);
            for (order.items) |source| {
                var loads: [40]i64 = @splat(0);
                for (result.bins.items, 0..) |bin, index| loads[index] = bin.load;
                const sorted = try descending(self.gpa, result.bins.items[source].items.items);
                var moves: std.ArrayList(Move) = .empty;
                var can_remove = true;
                for (sorted.items) |item| {
                    var destination: ?usize = null;
                    for (result.bins.items, 0..) |_, index| {
                        if (index == source or loads[index] + item.size > self.capacity.?) continue;
                        if (destination == null or loads[index] > loads[destination.?])
                            destination = index;
                    }
                    if (destination == null) {
                        can_remove = false;
                        break;
                    }
                    loads[destination.?] += item.size;
                    try moves.append(self.gpa, .{ .item = item, .destination = destination.? });
                }
                if (!can_remove) continue;
                var line: std.Io.Writer.Allocating = .init(self.gpa);
                try line.writer.print("ELIMINATE bin={d} load={d} moves=", .{
                    source + 1, result.bins.items[source].load,
                });
                for (moves.items, 0..) |move, index| {
                    if (index > 0) try line.writer.writeAll(" ");
                    try line.writer.print("{d}:{d}->{d}", .{ move.item.id, move.item.size, move.destination + 1 });
                    try result.bins.items[move.destination].put(self.gpa, move.item);
                }
                try events.append(self.gpa, try self.gpa.dupe(u8, line.writer.buffered()));
                _ = result.bins.orderedRemove(source);
                removed = true;
                break;
            }
            if (!removed) break;
        }
        try self.out.writeAll("REDUCE ");
        try self.out.writeAll(method);
        if (eq(method, "HARMONIC") or eq(method, "KBOUNDED"))
            try self.out.print(" k={d}", .{parameter});
        try self.out.print(" before={d} after={d} eliminated={d}\n",
            .{ before, result.bins.items.len, before - result.bins.items.len });
        for (events.items) |event| try self.out.print("{s}\n", .{event});
        try self.printBins(result.bins.items, self.capacity.?, eq(method, "HARMONIC"));
    }
    fn outputBounds(self: *Lab) Error!void {
        const result = try bounds(self.gpa, self.items.items, self.capacity.?);
        try self.out.print("BOUNDS total={d} L1={d} L2={d}\n", .{ self.total, result.l1, result.l2 });
        for (result.rows.items) |row|
            try self.out.print("ALPHA {d} j1={d} j2={d} j3={d} bound={d}\n", .{
                row.alpha, row.j1, row.j2, row.j3, row.value,
            });
    }
    fn outputCompare(self: *Lab, parameter: i64) Error!void {
        const methods = [_][]const u8{
            "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
            "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD",
        };
        const lower = try bounds(self.gpa, self.items.items, self.capacity.?);
        var packings: [10]Packing = undefined;
        for (methods, 0..) |method, i| {
            packings[i] = try pack(self.gpa, self.items.items, self.capacity.?, method, parameter);
        }
        const Ctx = struct {
            fn less(_: void, a: Packing, b: Packing) bool {
                if (a.bins.items.len != b.bins.items.len) return a.bins.items.len < b.bins.items.len;
                return std.mem.order(u8, a.method, b.method) == .lt;
            }
        };
        std.mem.sort(Packing, &packings, {}, Ctx.less);
        try self.out.print("COMPARE k={d} L1={d} L2={d}\n", .{ parameter, lower.l1, lower.l2 });
        for (packings) |result| {
            try self.out.print("{s} bins={d} gap={d} waste={d} inspections={d}\n", .{
                result.method, result.bins.items.len,
                @as(i64, @intCast(result.bins.items.len)) - lower.l2,
                @as(i64, @intCast(result.bins.items.len)) * self.capacity.? - self.total,
                result.inspections,
            });
        }
    }
    fn outputExact(self: *Lab, limit: i64) Error!void {
        if (limit == 0) return self.fail("BAD PARAMETER");
        if (self.items.items.len >= 21) return self.fail("TOO MANY ITEMS");
        const ffd = try pack(self.gpa, self.items.items, self.capacity.?, "FFD", 0);
        const lower = try bounds(self.gpa, self.items.items, self.capacity.?);
        try self.out.print("EXACT ffd={d} L2={d}\n", .{ ffd.bins.items.len, lower.l2 });
        var search = try Search.init(self.gpa, self.out, self.items.items, self.capacity.?, asU(limit), lower.l2, ffd.bins.items);
        if (@as(i64, @intCast(ffd.bins.items.len)) == lower.l2) {
            search.status = "bound";
        } else {
            try search.visit(0);
        }
        try self.out.print("RESULT bins={d} nodes={d} status={s}\n", .{
            search.best.items.len, search.nodes, search.status orelse "complete",
        });
        try self.printBins(search.best.items, self.capacity.?, false);
    }
    fn outputCheck(self: *Lab, values: []const []const u8) Error!void {
        if (values.len != self.items.items.len) return self.fail("BAD ASSIGNMENT");
        var labels: [40]i64 = @splat(0);
        var distinct: std.ArrayList(i64) = .empty;
        var result: [40]Bin = undefined;
        for (values, 0..) |text, i| {
            const label = number(text);
            if (label == 0) return self.fail("BAD ASSIGNMENT");
            labels[i] = label;
            var has = false;
            for (distinct.items) |existing| {
                if (existing == label) { has = true; break; }
            }
            if (!has) try distinct.append(self.gpa, label);
        }
        std.mem.sort(i64, distinct.items, {}, ascNumber);
        for (0..distinct.items.len) |index| result[index] = .{};
        for (labels[0..values.len], 0..) |label, i| {
            for (distinct.items, 0..) |candidate, j| {
                if (candidate == label) {
                    try result[j].put(self.gpa, self.items.items[i]);
                    break;
                }
            }
        }
        var over: usize = 0;
        for (result[0..distinct.items.len]) |bin| {
            if (bin.load > self.capacity.?) over += 1;
        }
        const lower = try bounds(self.gpa, self.items.items, self.capacity.?);
        try self.out.print("CHECK bins={d} over={d} L2={d} status={s}\n", .{
            distinct.items.len, over, lower.l2, if (over == 0) "valid" else "invalid",
        });
        for (result[0..distinct.items.len], 0..) |bin, i|
            try self.printBin(asU(distinct.items[i]), bin, self.capacity.?, false, bin.load > self.capacity.?);
    }
    fn coverLines(self: *Lab, name: []const u8, bins: []const Bin) Error!void {
        var covered: std.ArrayList(Bin) = .empty;
        var rest: ?Bin = null;
        for (bins) |bin| {
            if (bin.load >= self.capacity.?) {
                try covered.append(self.gpa, bin);
            } else {
                rest = bin;
            }
        }
        try self.out.print("{s} covered={d} rest={d}\n", .{
            name, covered.items.len, if (rest) |bin| bin.load else @as(i64, 0),
        });
        try self.printBins(covered.items, self.capacity.?, false);
        if (rest) |bin| {
            try self.out.writeAll("REST items=");
            for (bin.items.items, 0..) |item, index| {
                if (index > 0) try self.out.writeAll(" ");
                try self.out.print("{d}:{d}", .{ item.id, item.size });
            }
            try self.out.writeAll("\n");
        }
    }
    fn outputCover(self: *Lab) Error!void {
        try self.out.print("COVER total={d} upper={d}\n", .{ self.total, @divTrunc(self.total, self.capacity.?) });
        var dnf: std.ArrayList(Bin) = .empty;
        for (self.items.items) |item| {
            if (dnf.items.len == 0 or dnf.items[dnf.items.len - 1].load >= self.capacity.?)
                try dnf.append(self.gpa, .{});
            try dnf.items[dnf.items.len - 1].put(self.gpa, item);
        }
        try self.coverLines("DNF", dnf.items);
        const sorted = try descending(self.gpa, self.items.items);
        var bigsmall: std.ArrayList(Bin) = .empty;
        var left: usize = 0;
        var right: usize = sorted.items.len;
        while (left < right) {
            var bin: Bin = .{};
            try bin.put(self.gpa, sorted.items[left]);
            left += 1;
            while (bin.load < self.capacity.? and left < right) {
                right -= 1;
                try bin.put(self.gpa, sorted.items[right]);
            }
            try bigsmall.append(self.gpa, bin);
        }
        try self.coverLines("BIGSMALL", bigsmall.items);
    }
    fn machineLines(self: *Lab, machines: []const Bin) Error!void {
        for (machines, 0..) |bin, index| {
            try self.out.print("MACHINE {d} load={d} items=", .{ index + 1, bin.load });
            if (bin.items.items.len == 0) {
                try self.out.writeAll("-");
            } else {
                for (bin.items.items, 0..) |item, j| {
                    if (j > 0) try self.out.writeAll(" ");
                    try self.out.print("{d}:{d}", .{ item.id, item.size });
                }
            }
            try self.out.writeAll("\n");
        }
    }
    fn outputMultifit(self: *Lab, count: i64) Error!void {
        if (count == 0) return self.fail("BAD PARAMETER");
        var largest: i64 = 0;
        for (self.items.items) |item| largest = @max(largest, item.size);
        var lo = @max(ceil(self.total, count), largest);
        var hi = @max(ceil(2 * self.total, count), largest);
        try self.out.print("MULTIFIT m={d} lower={d} upper={d}\n", .{ count, lo, hi });
        while (lo < hi) {
            const mid = @divTrunc(lo + hi, 2);
            const p = try pack(self.gpa, self.items.items, mid, "FFD", 0);
            const ok = p.bins.items.len <= asU(count);
            try self.out.print("TRY cap={d} bins={d} {s}\n", .{
                mid, p.bins.items.len, if (ok) "ok" else "fail",
            });
            if (ok) hi = mid else lo = mid + 1;
        }
        var machines = (try pack(self.gpa, self.items.items, hi, "FFD", 0)).bins;
        while (machines.items.len < asU(count)) try machines.append(self.gpa, .{});
        var makespan: i64 = 0;
        for (machines.items) |bin| makespan = @max(makespan, bin.load);
        try self.out.print("RESULT cap={d} makespan={d}\n", .{ hi, makespan });
        try self.machineLines(machines.items);
        var lpt: std.ArrayList(Bin) = .empty;
        for (0..asU(count)) |_| try lpt.append(self.gpa, .{});
        const sorted = try descending(self.gpa, self.items.items);
        for (sorted.items) |item| {
            var destination: usize = 0;
            for (lpt.items, 0..) |bin, j| {
                if (bin.load < lpt.items[destination].load) destination = j;
            }
            try lpt.items[destination].put(self.gpa, item);
        }
        makespan = 0;
        for (lpt.items) |bin| makespan = @max(makespan, bin.load);
        try self.out.print("LPT makespan={d}\n", .{makespan});
        try self.machineLines(lpt.items);
    }
    fn outputCutstock(self: *Lab, args: []const []const u8) Error!void {
        const length = number(args[0]);
        if (length == 0) return self.fail("BAD CAPACITY");
        var pieces: std.ArrayList(CutPiece) = .empty;
        for (args[1..], 0..) |token, i| {
            const separator = std.mem.indexOfScalar(u8, token, ':').?;
            const size = number(token[0..separator]);
            const demand = number(token[separator + 1 ..]);
            if (size == 0 or size > length or demand == 0) return self.failNumber("BAD PIECE", i + 1);
            for (pieces.items) |piece| {
                if (piece.size == size) return self.failNumber("DUPLICATE PIECE", i + 1);
            }
            try pieces.append(self.gpa, .{ .size = size, .demand = demand });
        }
        std.mem.sort(CutPiece, pieces.items, {}, descPiece);
        var enumerator: PatternSearch = .{
            .gpa = self.gpa, .bar_length = length, .pieces = pieces.items,
        };
        try enumerator.visit(0, length);
        const patterns = enumerator.patterns.items;
        var uses: [60]i64 = @splat(0);
        var remaining: [6]i64 = @splat(0);
        var cut: [6]i64 = @splat(0);
        for (pieces.items, 0..) |piece, index| remaining[index] = piece.demand;
        while (true) {
            var pending = false;
            for (remaining[0..pieces.items.len]) |need| {
                if (need > 0) { pending = true; break; }
            }
            if (!pending) break;
            var chosen: usize = 0;
            var best: i64 = -1;
            for (patterns, 0..) |pattern, index| {
                var usefulness: i64 = 0;
                for (pieces.items, 0..) |_, k| usefulness += @min(pattern.counts[k], remaining[k]);
                if (usefulness > best) {
                    best = usefulness;
                    chosen = index;
                }
            }
            uses[chosen] += 1;
            for (pieces.items, 0..) |_, k| remaining[k] = @max(0, remaining[k] - patterns[chosen].counts[k]);
        }
        var quantity: i64 = 0;
        for (pieces.items, 0..) |piece, index| {
            quantity += piece.size * piece.demand;
            for (patterns, 0..) |pattern, j| cut[index] += uses[j] * pattern.counts[index];
        }
        try self.out.print("CUTSTOCK L={d} pieces={d} patterns={d}\n", .{
            length, pieces.items.len, patterns.len,
        });
        for (patterns, 0..) |pattern, index| {
            try self.out.print("PATTERN {d} ", .{index + 1});
            var printed = false;
            for (pieces.items, 0..) |piece, i| {
                if (pattern.counts[i] == 0) continue;
                if (printed) try self.out.writeAll("+");
                try self.out.print("{d}x{d}", .{ pattern.counts[i], piece.size });
                printed = true;
            }
            try self.out.print(" rest={d}\n", .{pattern.trim});
        }
        var bars: i64 = 0;
        var trim: i64 = 0;
        for (patterns, 0..) |pattern, index| {
            if (uses[index] != 0) try self.out.print("USE {d} bars={d}\n", .{index + 1, uses[index]});
            bars += uses[index];
            trim += uses[index] * pattern.trim;
        }
        var total_cut: i64 = 0;
        var total_demand: i64 = 0;
        for (pieces.items, 0..) |piece, index| {
            try self.out.print("PIECE {d} demand={d} cut={d}\n", .{ piece.size, piece.demand, cut[index] });
            total_cut += cut[index];
            total_demand += piece.demand;
        }
        try self.out.print("TOTAL bars={d} trim={d} surplus={d} waste={d}\n", .{
            bars, trim, total_cut - total_demand, bars * length - quantity,
        });
        var individual: std.ArrayList(Item) = .empty;
        for (pieces.items) |piece| {
            for (0..asU(piece.demand)) |_| {
                try individual.append(self.gpa, .{ .id = individual.items.len + 1, .size = piece.size });
            }
        }
        const comparison = try pack(self.gpa, individual.items, length, "FIRSTFIT", 0);
        const b: i64 = @intCast(comparison.bins.items.len);
        try self.out.print("FFD bars={d} waste={d}\nLOWER bars={d}\n", .{
            b, b * length - quantity, ceil(quantity, length),
        });
    }
    fn drawing(self: *Lab, width: i64, height: i64, placements: []const Placement) std.Io.Writer.Error!void {
        var y = height;
        while (y > 0) {
            y -= 1;
            var row: [40]u8 = @splat('.');
            for (placements) |p| {
                if (y < p.y or y >= p.y + p.h) continue;
                for (asU(p.x)..asU(p.x + p.w)) |x| row[x] = letter(p.rect.id);
            }
            try self.out.writeAll(row[0..asU(width)]);
            try self.out.writeAll("\n");
        }
    }
    fn parseRects(self: *Lab, args: []const []const u8) Allocator.Error!std.ArrayList(Rect) {
        var rectangles: std.ArrayList(Rect) = .empty;
        for (args, 0..) |token, index| {
            const separator = std.mem.indexOfScalar(u8, token, 'x').?;
            try rectangles.append(self.gpa, .{
                .id = index + 1, .w = number(token[0..separator]), .h = number(token[separator + 1 ..]),
            });
        }
        return rectangles;
    }
    fn outputShelfMethod(self: *Lab, method: []const u8, width: i64, rectangles: []const Rect, area: i64) Error!void {
        var shelves: std.ArrayList(Shelf) = .empty;
        var placements: std.ArrayList(Placement) = .empty;
        for (rectangles) |rect| {
            var chosen: ?usize = null;
            if (eq(method, "NFDH")) {
                if (shelves.items.len > 0 and shelves.items[shelves.items.len - 1].used + rect.w <= width)
                    chosen = shelves.items.len - 1;
            } else {
                for (shelves.items, 0..) |shelf, index| {
                    if (shelf.used + rect.w > width) continue;
                    if (chosen == null or (eq(method, "BFDH") and shelf.used > shelves.items[chosen.?].used))
                        chosen = index;
                    if (eq(method, "FFDH")) break;
                }
            }
            if (chosen == null) {
                const bottom: i64 = if (shelves.items.len == 0) 0 else
                    shelves.items[shelves.items.len - 1].bottom + shelves.items[shelves.items.len - 1].height;
                chosen = shelves.items.len;
                try shelves.append(self.gpa, .{ .bottom = bottom, .height = rect.h });
            }
            const shelf = &shelves.items[chosen.?];
            const placement: Placement = .{
                .rect = rect, .x = shelf.used, .y = shelf.bottom, .w = rect.w, .h = rect.h,
            };
            try shelf.items.append(self.gpa, placement);
            try placements.append(self.gpa, placement);
            shelf.used += rect.w;
        }
        const height = shelves.items[shelves.items.len - 1].bottom + shelves.items[shelves.items.len - 1].height;
        try self.out.print("{s} height={d} shelves={d} util={d}\n", .{
            method, height, shelves.items.len, @divTrunc(area * 100, width * height),
        });
        for (shelves.items, 0..) |shelf, index| {
            try self.out.print("LEVEL {d} y={d} h={d} used={d} items=", .{
                index + 1, shelf.bottom, shelf.height, shelf.used,
            });
            for (shelf.items.items, 0..) |p, j| {
                if (j != 0) try self.out.writeAll(" ");
                try self.out.print("{c}@{d}", .{ letter(p.rect.id), p.x });
            }
            try self.out.writeAll("\n");
        }
        try self.drawing(width, height, placements.items);
    }
    fn outputShelf(self: *Lab, args: []const []const u8) Error!void {
        const width = number(args[0]);
        if (width == 0) return self.fail("BAD CAPACITY");
        var rectangles = try self.parseRects(args[1..]);
        var area: i64 = 0;
        for (rectangles.items) |rect| {
            if (rect.w == 0 or rect.h == 0 or rect.w > width) return self.failNumber("BAD RECT", rect.id);
            area += rect.w * rect.h;
        }
        std.mem.sort(Rect, rectangles.items, {}, shelfDescending);
        try self.out.print("SHELF W={d} rects={d} area={d}\n", .{ width, rectangles.items.len, area });
        for ([_][]const u8{ "NFDH", "FFDH", "BFDH" }) |method|
            try self.outputShelfMethod(method, width, rectangles.items, area);
        var heights: [40]i64 = @splat(0);
        var placements: std.ArrayList(Placement) = .empty;
        for (rectangles.items) |rect| {
            var chosen_x: usize = 0;
            var chosen_y: i64 = std.math.maxInt(i64);
            for (0..asU(width - rect.w + 1)) |x| {
                var y: i64 = 0;
                for (x..x + asU(rect.w)) |position| y = @max(y, heights[position]);
                if (y < chosen_y) {
                    chosen_y = y;
                    chosen_x = x;
                }
            }
            for (chosen_x..chosen_x + asU(rect.w)) |position| heights[position] = chosen_y + rect.h;
            try placements.append(self.gpa, .{
                .rect = rect, .x = @intCast(chosen_x), .y = chosen_y, .w = rect.w, .h = rect.h,
            });
        }
        var height: i64 = 0;
        for (heights[0..asU(width)]) |value| height = @max(height, value);
        try self.out.print("SKYLINE height={d} util={d}\n", .{
            height, @divTrunc(area * 100, width * height),
        });
        for (placements.items) |p|
            try self.out.print("PLACE {c} x={d} y={d} w={d} h={d}\n", .{
                letter(p.rect.id), p.x, p.y, p.w, p.h,
            });
        try self.drawing(width, height, placements.items);
    }
    fn outputGuillotine(self: *Lab, args: []const []const u8) Error!void {
        const width = number(args[0]);
        const height = number(args[1]);
        if (width == 0 or height == 0) return self.fail("BAD CAPACITY");
        const mode = args[2];
        const rule = args[3];
        const rotate = eq(mode, "ROTATE");
        var rectangles = try self.parseRects(args[4..]);
        for (rectangles.items) |rect| {
            const fits = rect.w <= width and rect.h <= height;
            const rotated = rotate and rect.h <= width and rect.w <= height;
            if (rect.w == 0 or rect.h == 0 or (!fits and !rotated))
                return self.failNumber("BAD RECT", rect.id);
        }
        std.mem.sort(Rect, rectangles.items, {}, areaDescending);
        var sheets: std.ArrayList(Sheet) = .empty;
        var rotated_count: usize = 0;
        var area: i64 = 0;
        for (rectangles.items) |rect| {
            var chosen_sheet: ?usize = null;
            var chosen_free: usize = 0;
            var smallest_area: i64 = std.math.maxInt(i64);
            for (sheets.items, 0..) |sheet, si| {
                for (sheet.free.items, 0..) |free, fi| {
                    const fits = rect.w <= free.w and rect.h <= free.h;
                    const fits_rotated = rotate and rect.h <= free.w and rect.w <= free.h;
                    if (!fits and !fits_rotated) continue;
                    const candidate_area = free.w * free.h;
                    if (chosen_sheet == null or (eq(rule, "BEST") and candidate_area < smallest_area)) {
                        chosen_sheet = si;
                        chosen_free = fi;
                        smallest_area = candidate_area;
                    }
                    if (eq(rule, "FIRST")) break;
                }
                if (eq(rule, "FIRST") and chosen_sheet != null) break;
            }
            if (chosen_sheet == null) {
                var sheet: Sheet = .{};
                try sheet.free.append(self.gpa, .{ .x = 0, .y = 0, .w = width, .h = height });
                chosen_sheet = sheets.items.len;
                try sheets.append(self.gpa, sheet);
                chosen_free = 0;
            }
            const sheet = &sheets.items[chosen_sheet.?];
            const free = sheet.free.orderedRemove(chosen_free);
            const was_rotated = !(rect.w <= free.w and rect.h <= free.h);
            const pw = if (was_rotated) rect.h else rect.w;
            const ph = if (was_rotated) rect.w else rect.h;
            if (was_rotated) rotated_count += 1;
            area += rect.w * rect.h;
            sheet.area += rect.w * rect.h;
            try sheet.placed.append(self.gpa, .{
                .rect = rect, .x = free.x, .y = free.y, .w = pw,
                .h = ph, .rotated = was_rotated,
            });
            const rw = free.w - pw;
            const rh = free.h - ph;
            const top: Free = .{
                .x = free.x, .y = free.y + ph,
                .w = if (rw <= rh) free.w else pw,
                .h = rh,
            };
            const right: Free = .{
                .x = free.x + pw, .y = free.y,
                .w = rw, .h = if (rw <= rh) ph else free.h,
            };
            if (top.w > 0 and top.h > 0) try sheet.free.append(self.gpa, top);
            if (right.w > 0 and right.h > 0) try sheet.free.append(self.gpa, right);
        }
        try self.out.print("GUILLOTINE W={d} H={d} mode={s} rule={s} rects={d} sheets={d} rotated={d} util={d}\n", .{
            width, height, mode, rule, rectangles.items.len, sheets.items.len,
            rotated_count, @divTrunc(area * 100, @as(i64, @intCast(sheets.items.len)) * width * height),
        });
        for (sheets.items, 0..) |sheet, index| {
            try self.out.print("SHEET {d} placed={d} area={d}\n", .{
                index + 1, sheet.placed.items.len, sheet.area,
            });
            for (sheet.placed.items) |p| {
                try self.out.print("PLACE {c} x={d} y={d} w={d} h={d}", .{
                    letter(p.rect.id), p.x, p.y, p.w, p.h,
                });
                if (p.rotated) try self.out.writeAll(" rotated");
                try self.out.writeAll("\n");
            }
            try self.out.writeAll("FREE ");
            if (sheet.free.items.len == 0) {
                try self.out.writeAll("none");
            } else {
                for (sheet.free.items, 0..) |free, j| {
                    if (j > 0) try self.out.writeAll(" ");
                    try self.out.print("{d},{d},{d}x{d}", .{ free.x, free.y, free.w, free.h });
                }
            }
            try self.out.writeAll("\n");
            try self.drawing(width, height, sheet.placed.items);
        }
    }
    fn execute(self: *Lab, args: []const []const u8) Error!void {
        const command = args[0];
        if (eq(command, "ITEMS")) {
            const capacity = number(args[1]);
            if (capacity == 0) return self.fail("BAD CAPACITY");
            var candidate: std.ArrayList(Item) = .empty;
            var total: i64 = 0;
            for (args[2..], 0..) |text, index| {
                const size = number(text);
                if (size == 0 or size > capacity) return self.failNumber("BAD ITEM", index + 1);
                try candidate.append(self.gpa, .{ .id = index + 1, .size = size });
                total += size;
            }
            self.items = candidate;
            self.capacity = capacity;
            self.total = total;
            try self.out.print("ITEMS count={d} capacity={d} total={d}\n", .{
                candidate.items.len, capacity, total,
            });
            return;
        } else if (eq(command, "RANDOM")) {
            const count = number(args[1]);
            const capacity = number(args[2]);
            var seed = number(args[3]);
            if (count == 0 or count > 40) return self.fail("BAD COUNT");
            if (capacity == 0) return self.fail("BAD CAPACITY");
            if (seed == 0 or seed >= 2147483647) return self.fail("BAD SEED");
            var candidate: std.ArrayList(Item) = .empty;
            var total: i64 = 0;
            for (0..asU(count)) |index| {
                seed = @mod(48271 * seed, 2147483647);
                const size = @mod(seed, capacity) + 1;
                try candidate.append(self.gpa, .{ .id = index + 1, .size = size });
                total += size;
            }
            self.items = candidate;
            self.capacity = capacity;
            self.total = total;
            try self.out.print("RANDOM count={d} capacity={d} total={d}\nSIZES", .{
                count, capacity, total,
            });
            for (candidate.items) |item| try self.out.print(" {d}", .{item.size});
            try self.out.writeAll("\n");
            return;
        } else if (eq(command, "CUTSTOCK")) {
            return self.outputCutstock(args[1..]);
        } else if (eq(command, "SHELF")) {
            return self.outputShelf(args[1..]);
        } else if (eq(command, "GUILLOTINE")) {
            return self.outputGuillotine(args[1..]);
        }
        if (self.capacity == null) return self.fail("NO ITEMS");
        if (eq(command, "TRACE") or eq(command, "REDUCE")) {
            const method = args[1];
            const parameter = if (eq(method, "HARMONIC") or eq(method, "KBOUNDED"))
                number(args[2]) else @as(i64, 0);
            if ((eq(method, "HARMONIC") or eq(method, "KBOUNDED")) and parameter == 0)
                return self.fail("BAD PARAMETER");
            if (eq(command, "TRACE")) return self.outputTrace(method, parameter);
            return self.outputReduce(method, parameter);
        }
        if (eq(command, "BOUNDS")) return self.outputBounds();
        if (eq(command, "COMPARE")) {
            const parameter = number(args[1]);
            if (parameter == 0) return self.fail("BAD PARAMETER");
            return self.outputCompare(parameter);
        }
        if (eq(command, "EXACT")) return self.outputExact(number(args[1]));
        if (eq(command, "CHECK")) return self.outputCheck(args[1..]);
        if (eq(command, "COVER")) return self.outputCover();
        if (eq(command, "MULTIFIT")) return self.outputMultifit(number(args[1]));
        const parameter = if (eq(command, "HARMONIC") or eq(command, "KBOUNDED"))
            number(args[1]) else @as(i64, 0);
        if ((eq(command, "HARMONIC") or eq(command, "KBOUNDED")) and parameter == 0)
            return self.fail("BAD PARAMETER");
        return self.outputMethod(command, parameter);
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [16384]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var lab = Lab{ .gpa = gpa, .out = &output.interface };
    const first = (try input.interface.takeDelimiter('\n')).?;
    const commands = asU(number(first));
    for (0..commands) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |part| try words.append(gpa, part);
        lab.execute(words.items) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{lab.reason});
        };
    }
    try output.interface.flush();
}
