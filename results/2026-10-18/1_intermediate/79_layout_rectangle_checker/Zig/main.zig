const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn number(s: Text) Int {
    return std.fmt.parseInt(Int, s, 10) catch unreachable;
}
fn u(n: Int) usize {
    return @intCast(n);
}
fn si(n: usize) Int {
    return @intCast(n);
}
fn abs(n: Int) Int {
    return if (n < 0) -n else n;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        try self.print(format ++ "\n", args);
    }
};
fn words(gpa: Allocator, text: Text) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |word| try result.append(gpa, word);
    return result.items;
}
fn join(gpa: Allocator, list: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (list, 0..) |item, i| {
        if (i > 0) try out.add(separator);
        try out.add(item);
    }
    return out.bytes.items;
}
const Geometry = struct { x1: Int, y1: Int, x2: Int, y2: Int };
const Rectangle = struct { name: Text, layer: Text, r: Geometry };
const RelationKind = enum { overlap, edge, corner, separate };
const Relation = struct { r: Geometry, ox: Int, oy: Int, gap: Int, kind: RelationKind, direction: Text = "" };
fn notation(gpa: Allocator, r: Geometry) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "({d},{d})-({d},{d})", .{ r.x1, r.y1, r.x2, r.y2 });
}
fn point(gpa: Allocator, x: Int, y: Int) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "({d},{d})", .{ x, y });
}
fn area(r: Geometry) Int {
    return (r.x2 - r.x1) * (r.y2 - r.y1);
}
fn encloses(a: Geometry, b: Geometry) bool {
    return a.x1 <= b.x1 and a.y1 <= b.y1 and a.x2 >= b.x2 and a.y2 >= b.y2;
}
fn compare(a: Geometry, b: Geometry) Relation {
    const r: Geometry = .{ .x1 = @max(a.x1, b.x1), .y1 = @max(a.y1, b.y1), .x2 = @min(a.x2, b.x2), .y2 = @min(a.y2, b.y2) };
    const ox = r.x2 - r.x1;
    const oy = r.y2 - r.y1;
    const kind: RelationKind = if (ox > 0 and oy > 0) .overlap else if (ox == 0 and oy == 0) .corner else if (ox >= 0 and oy >= 0) .edge else .separate;
    return .{ .r = r, .ox = ox, .oy = oy, .gap = @max(0, @max(-ox, -oy)), .kind = kind, .direction = if (ox < 0 and oy < 0) "diagonal" else if (ox < 0) "x" else "y" };
}
fn connected(a: Rectangle, b: Rectangle) bool {
    const r = compare(a.r, b.r);
    return equal(a.layer, b.layer) and (r.kind == .overlap or r.kind == .edge);
}
fn margins(a: Geometry, b: Geometry) [4]Int {
    return .{ b.x1 - a.x1, b.y1 - a.y1, a.x2 - b.x2, a.y2 - b.y2 };
}
fn minimum(values: [4]Int) Int {
    var result = values[0];
    for (values[1..]) |value| result = @min(result, value);
    return result;
}
fn decimal(gpa: Allocator, numerator: Int, denominator: Int) Allocator.Error!Text {
    const h = @divTrunc(numerator * 100, denominator);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>2}", .{ @divTrunc(h, 100), @mod(h, 100) });
}
fn bounds(list: []const Rectangle) Geometry {
    var r = list[0].r;
    for (list[1..]) |item| {
        r.x1 = @min(r.x1, item.r.x1);
        r.y1 = @min(r.y1, item.r.y1);
        r.x2 = @max(r.x2, item.r.x2);
        r.y2 = @max(r.y2, item.r.y2);
    }
    return r;
}
fn rectangleLess(_: void, a: Rectangle, b: Rectangle) bool {
    return std.mem.order(u8, a.name, b.name) == .lt;
}
fn intLess(_: void, a: Int, b: Int) bool {
    return a < b;
}
fn distinct(gpa: Allocator, list: []Int) Allocator.Error![]Int {
    std.mem.sort(Int, list, {}, intLess);
    var result: std.ArrayList(Int) = .empty;
    for (list) |value| if (result.items.len == 0 or value != result.items[result.items.len - 1]) try result.append(gpa, value);
    return result.items;
}
const Cell = struct { x: usize, y: usize };
const Hole = struct { r: Geometry, area: Int = 0, ax: Int, ay: Int };
fn holeLess(_: void, a: Hole, b: Hole) bool {
    return a.ay < b.ay or a.ay == b.ay and a.ax < b.ax;
}
fn pieceLess(_: void, a: Geometry, b: Geometry) bool {
    return a.y1 < b.y1 or a.y1 == b.y1 and a.x1 < b.x1;
}
const Grid = struct {
    xs: []const Int,
    ys: []const Int,
    counts: []i32,
    fn w(self: Grid) usize {
        return if (self.xs.len == 0) 0 else self.xs.len - 1;
    }
    fn h(self: Grid) usize {
        return if (self.ys.len == 0) 0 else self.ys.len - 1;
    }
    fn count(self: Grid, x: usize, y: usize) i32 {
        return self.counts[y * self.xs.len + x];
    }
    fn build(gpa: Allocator, list: []const Rectangle) Allocator.Error!Grid {
        var xs: std.ArrayList(Int) = .empty;
        var ys: std.ArrayList(Int) = .empty;
        for (list) |item| {
            try xs.appendSlice(gpa, &.{ item.r.x1, item.r.x2 });
            try ys.appendSlice(gpa, &.{ item.r.y1, item.r.y2 });
        }
        const xx = try distinct(gpa, xs.items);
        const yy = try distinct(gpa, ys.items);
        const counts = try gpa.alloc(i32, xx.len * yy.len);
        @memset(counts, 0);
        for (list) |item| {
            const a = std.mem.findScalar(Int, xx, item.r.x1).?;
            const b = std.mem.findScalar(Int, yy, item.r.y1).?;
            const c = std.mem.findScalar(Int, xx, item.r.x2).?;
            const d = std.mem.findScalar(Int, yy, item.r.y2).?;
            counts[b * xx.len + a] += 1;
            counts[b * xx.len + c] -= 1;
            counts[d * xx.len + a] -= 1;
            counts[d * xx.len + c] += 1;
        }
        for (0..yy.len) |y| {
            for (0..xx.len) |x| {
                const index = y * xx.len + x;
                if (y > 0) counts[index] += counts[index - xx.len];
                if (x > 0) counts[index] += counts[index - 1];
                if (y > 0 and x > 0) counts[index] -= counts[index - xx.len - 1];
            }
        }
        return .{ .xs = xx, .ys = yy, .counts = counts };
    }
    fn covered(self: Grid, k: i32, window: ?Geometry) Int {
        var total: Int = 0;
        for (0..self.h()) |y| {
            for (0..self.w()) |x| {
                if (self.count(x, y) < k) continue;
                var r: Geometry = .{ .x1 = self.xs[x], .y1 = self.ys[y], .x2 = self.xs[x + 1], .y2 = self.ys[y + 1] };
                if (window) |clip| r = compare(r, clip).r;
                if (r.x1 < r.x2 and r.y1 < r.y2) total += area(r);
            }
        }
        return total;
    }
    fn perimeter(self: Grid) Int {
        var total: Int = 0;
        for (0..self.h()) |y| {
            for (0..self.w()) |x| {
                if (self.count(x, y) == 0) continue;
                const width = self.xs[x + 1] - self.xs[x];
                const height = self.ys[y + 1] - self.ys[y];
                if (x == 0 or self.count(x - 1, y) == 0) total += height;
                if (x + 1 == self.w() or self.count(x + 1, y) == 0) total += height;
                if (y == 0 or self.count(x, y - 1) == 0) total += width;
                if (y + 1 == self.h() or self.count(x, y + 1) == 0) total += width;
            }
        }
        return total;
    }
    fn empty(self: Grid, gpa: Allocator) Allocator.Error!?Geometry {
        var best: ?Geometry = null;
        const blocked = try gpa.alloc(bool, self.h());
        for (0..self.w()) |left| {
            @memset(blocked, false);
            for (left..self.w()) |right| {
                for (blocked, 0..) |*value, y| value.* = value.* or self.count(right, y) > 0;
                var y: usize = 0;
                while (y < blocked.len) {
                    if (blocked[y]) {
                        y += 1;
                        continue;
                    }
                    const start = y;
                    while (y < blocked.len and !blocked[y]) y += 1;
                    const r: Geometry = .{ .x1 = self.xs[left], .y1 = self.ys[start], .x2 = self.xs[right + 1], .y2 = self.ys[y] };
                    if (best == null or area(r) > area(best.?) or area(r) == area(best.?) and (r.x1 < best.?.x1 or r.x1 == best.?.x1 and (r.y1 < best.?.y1 or r.y1 == best.?.y1 and r.x2 - r.x1 < best.?.x2 - best.?.x1))) best = r;
                }
            }
        }
        return best;
    }
    fn holes(self: Grid, gpa: Allocator) Allocator.Error![]Hole {
        var result: std.ArrayList(Hole) = .empty;
        const seen = try gpa.alloc(bool, self.counts.len);
        @memset(seen, false);
        for (0..self.h()) |y| {
            for (0..self.w()) |x| {
                const first = y * self.xs.len + x;
                if (self.count(x, y) > 0 or seen[first]) continue;
                var queue: std.ArrayList(Cell) = .empty;
                try queue.append(gpa, .{ .x = x, .y = y });
                seen[first] = true;
                var outside = false;
                var hole: Hole = .{ .r = .{ .x1 = self.xs[x], .y1 = self.ys[y], .x2 = self.xs[x + 1], .y2 = self.ys[y + 1] }, .ax = self.xs[x], .ay = self.ys[y] };
                var i: usize = 0;
                while (i < queue.items.len) : (i += 1) {
                    const p = queue.items[i];
                    if (p.x == 0 or p.y == 0 or p.x + 1 == self.w() or p.y + 1 == self.h()) outside = true;
                    hole.area += (self.xs[p.x + 1] - self.xs[p.x]) * (self.ys[p.y + 1] - self.ys[p.y]);
                    hole.r.x1 = @min(hole.r.x1, self.xs[p.x]);
                    hole.r.y1 = @min(hole.r.y1, self.ys[p.y]);
                    hole.r.x2 = @max(hole.r.x2, self.xs[p.x + 1]);
                    hole.r.y2 = @max(hole.r.y2, self.ys[p.y + 1]);
                    if (self.ys[p.y] < hole.ay or self.ys[p.y] == hole.ay and self.xs[p.x] < hole.ax) {
                        hole.ax = self.xs[p.x];
                        hole.ay = self.ys[p.y];
                    }
                    for ([_][2]Int{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |delta| {
                        const a = si(p.x) + delta[0];
                        const b = si(p.y) + delta[1];
                        if (a < 0 or a >= si(self.w()) or b < 0 or b >= si(self.h())) continue;
                        const index = u(b) * self.xs.len + u(a);
                        if (!seen[index] and self.count(u(a), u(b)) == 0) {
                            seen[index] = true;
                            try queue.append(gpa, .{ .x = u(a), .y = u(b) });
                        }
                    }
                }
                if (!outside) try result.append(gpa, hole);
            }
        }
        std.mem.sort(Hole, result.items, {}, holeLess);
        return result.items;
    }
    fn pieces(self: Grid, gpa: Allocator) Allocator.Error![]Geometry {
        var active: std.ArrayList(Geometry) = .empty;
        var result: std.ArrayList(Geometry) = .empty;
        for (0..self.h()) |y| {
            var current: std.ArrayList(Geometry) = .empty;
            const matched = try gpa.alloc(bool, active.items.len);
            @memset(matched, false);
            var x: usize = 0;
            while (x < self.w()) {
                if (self.count(x, y) == 0) {
                    x += 1;
                    continue;
                }
                const start = x;
                while (x < self.w() and self.count(x, y) > 0) x += 1;
                var r: Geometry = .{ .x1 = self.xs[start], .y1 = self.ys[y], .x2 = self.xs[x], .y2 = self.ys[y + 1] };
                for (active.items, 0..) |old, i| if (old.x1 == r.x1 and old.x2 == r.x2) {
                    r.y1 = old.y1;
                    matched[i] = true;
                    break;
                };
                try current.append(gpa, r);
            }
            for (active.items, 0..) |r, i| if (!matched[i]) try result.append(gpa, r);
            active = current;
        }
        try result.appendSlice(gpa, active.items);
        std.mem.sort(Geometry, result.items, {}, pieceLess);
        return result.items;
    }
};
fn names(gpa: Allocator, list: []const Rectangle) Allocator.Error!Text {
    var result: std.ArrayList(Text) = .empty;
    for (list) |item| try result.append(gpa, item.name);
    return if (result.items.len == 0) "none" else try join(gpa, result.items, " ");
}
fn nets(gpa: Allocator, list: []const Rectangle) Allocator.Error![][]Rectangle {
    var result: std.ArrayList([]Rectangle) = .empty;
    const seen = try gpa.alloc(bool, list.len);
    @memset(seen, false);
    for (list, 0..) |item, index| {
        if (seen[index]) continue;
        var group: std.ArrayList(Rectangle) = .empty;
        try group.append(gpa, item);
        seen[index] = true;
        var i: usize = 0;
        while (i < group.items.len) : (i += 1) {
            for (list, 0..) |candidate, j| if (!seen[j] and connected(group.items[i], candidate)) {
                seen[j] = true;
                try group.append(gpa, candidate);
            };
        }
        std.mem.sort(Rectangle, group.items, {}, rectangleLess);
        try result.append(gpa, group.items);
    }
    return result.items;
}
const Violation = struct { a: Text, b: Text, gap: Int, direction: Text };
fn violationLess(_: void, a: Violation, b: Violation) bool {
    const first = std.mem.order(u8, a.a, b.a);
    return a.gap < b.gap or a.gap == b.gap and (first == .lt or first == .eq and std.mem.order(u8, a.b, b.b) == .lt);
}
fn spacing(gpa: Allocator, list: []const Rectangle, s: Int) Allocator.Error![]Violation {
    var result: std.ArrayList(Violation) = .empty;
    for (list, 0..) |a, i| {
        for (list[i + 1 ..]) |b| {
            const r = compare(a.r, b.r);
            if (r.kind == .corner or r.kind == .separate and r.gap < s) try result.append(gpa, .{ .a = a.name, .b = b.name, .gap = r.gap, .direction = if (r.kind == .corner) "corner" else r.direction });
        }
    }
    std.mem.sort(Violation, result.items, {}, violationLess);
    return result.items;
}
const RuleKind = enum { enclose, spacing, width };
const Rule = struct { kind: RuleKind, inner: Text, outer: Text = "", value: Int };
fn ruleLess(_: void, a: Rule, b: Rule) bool {
    if (a.kind != b.kind) return @backingInt(a.kind) < @backingInt(b.kind);
    const inner = std.mem.order(u8, a.inner, b.inner);
    return inner == .lt or inner == .eq and std.mem.order(u8, a.outer, b.outer) == .lt;
}
const Snapshot = struct { rectangles: []const Rectangle, command: Text };
const Checker = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Builder,
    rectangles: std.StringHashMapUnmanaged(Rectangle) = .empty,
    rules: std.StringHashMapUnmanaged(Rule) = .empty,
    history: std.ArrayList(Snapshot) = .empty,
    fn fail(self: *Checker, comptime format: Text, args: anytype) Error {
        failure = std.fmt.allocPrint(self.gpa, "error: " ++ format, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn get(self: *Checker, name: Text) Error!Rectangle {
        return self.rectangles.get(name) orelse return self.fail("unknown rectangle {s}", .{name});
    }
    fn list(self: *Checker, layer: ?Text) Allocator.Error![]Rectangle {
        var result: std.ArrayList(Rectangle) = .empty;
        var iterator = self.rectangles.valueIterator();
        while (iterator.next()) |item| if (layer == null or equal(item.layer, layer.?)) try result.append(self.scratch, item.*);
        std.mem.sort(Rectangle, result.items, {}, rectangleLess);
        return result.items;
    }
    fn require(self: *Checker, layer: Text) Error![]Rectangle {
        const result = try self.list(layer);
        if (result.len == 0) return self.fail("no rectangles on {s}", .{layer});
        return result;
    }
    fn remember(self: *Checker, line: Text) Error!void {
        try self.history.append(self.gpa, .{ .rectangles = try self.gpa.dupe(Rectangle, try self.list(null)), .command = line });
    }
    fn checkBounds(self: *Checker, r: Geometry) Error!void {
        if (abs(r.x1) > 10000 or abs(r.y1) > 10000 or abs(r.x2) > 10000 or abs(r.y2) > 10000) return self.fail("out of bounds", .{});
    }
    fn violationLines(self: *Checker, violations: []const Violation) Error!void {
        for (violations) |v| try self.out.line("{s} {s} gap {d} {s}", .{ v.a, v.b, v.gap, v.direction });
    }
    fn command(self: *Checker, line: Text) Error!void {
        const tokens = try words(self.scratch, line);
        const commandName = tokens[0];
        const args = tokens[1..];
        if (equal(commandName, "ADD")) {
            if (self.rectangles.contains(args[0])) return self.fail("duplicate rectangle {s}", .{args[0]});
            const item: Rectangle = .{ .name = args[0], .layer = args[1], .r = .{ .x1 = number(args[2]), .y1 = number(args[3]), .x2 = number(args[4]), .y2 = number(args[5]) } };
            if (item.r.x1 >= item.r.x2 or item.r.y1 >= item.r.y2) return self.fail("invalid rectangle", .{});
            try self.checkBounds(item.r);
            try self.remember(line);
            try self.rectangles.put(self.gpa, item.name, item);
            try self.out.line("added {s} {s} {s}", .{ item.name, item.layer, try notation(self.scratch, item.r) });
            return;
        }
        if (oneOf(commandName, &.{ "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE" })) {
            const original = try self.get(args[0]);
            var item = original;
            if (equal(commandName, "COPY")) {
                if (self.rectangles.contains(args[1])) return self.fail("duplicate rectangle {s}", .{args[1]});
                item.name = args[1];
                const dx = number(args[2]);
                const dy = number(args[3]);
                item.r.x1 += dx;
                item.r.x2 += dx;
                item.r.y1 += dy;
                item.r.y2 += dy;
                try self.checkBounds(item.r);
                try self.remember(line);
                try self.rectangles.put(self.gpa, item.name, item);
                try self.out.line("copied {s} to {s} {s}", .{ original.name, item.name, try notation(self.scratch, item.r) });
            } else if (equal(commandName, "MOVE")) {
                const dx = number(args[1]);
                const dy = number(args[2]);
                item.r.x1 += dx;
                item.r.x2 += dx;
                item.r.y1 += dy;
                item.r.y2 += dy;
                try self.checkBounds(item.r);
                try self.remember(line);
                try self.rectangles.put(self.gpa, item.name, item);
                try self.out.line("moved {s} to {s}", .{ item.name, try notation(self.scratch, item.r) });
            } else if (equal(commandName, "RESIZE")) {
                const width = number(args[1]);
                const height = number(args[2]);
                if (width <= 0 or height <= 0) return self.fail("invalid size", .{});
                item.r.x2 = item.r.x1 + width;
                item.r.y2 = item.r.y1 + height;
                try self.checkBounds(item.r);
                try self.remember(line);
                try self.rectangles.put(self.gpa, item.name, item);
                try self.out.line("resized {s} to {s}", .{ item.name, try notation(self.scratch, item.r) });
            } else if (equal(commandName, "SPLIT")) {
                if (self.rectangles.contains(args[3])) return self.fail("duplicate rectangle {s}", .{args[3]});
                const pos = number(args[2]);
                const horizontal = equal(args[1], "x");
                if (horizontal and (pos <= item.r.x1 or pos >= item.r.x2) or !horizontal and (pos <= item.r.y1 or pos >= item.r.y2)) return self.fail("cut outside {s}", .{item.name});
                var other = item;
                other.name = args[3];
                if (horizontal) {
                    item.r.x2 = pos;
                    other.r.x1 = pos;
                } else {
                    item.r.y2 = pos;
                    other.r.y1 = pos;
                }
                try self.remember(line);
                try self.rectangles.put(self.gpa, item.name, item);
                try self.rectangles.put(self.gpa, other.name, other);
                try self.out.line("split {s} at {s}={d}: {s} {s}, {s} {s}", .{ item.name, args[1], pos, item.name, try notation(self.scratch, item.r), other.name, try notation(self.scratch, other.r) });
            } else if (equal(commandName, "LAYER")) {
                if (equal(item.layer, args[1])) return self.fail("already on {s}", .{item.layer});
                item.layer = args[1];
                try self.remember(line);
                try self.rectangles.put(self.gpa, item.name, item);
                try self.out.line("layer {s} {s} -> {s}", .{ item.name, original.layer, item.layer });
            } else {
                try self.remember(line);
                _ = self.rectangles.remove(item.name);
                try self.out.line("deleted {s}", .{item.name});
            }
            return;
        }
        if (equal(commandName, "UNDO")) {
            const previous = self.history.pop() orelse return self.fail("nothing to undo", .{});
            self.rectangles.clearRetainingCapacity();
            for (previous.rectangles) |item| try self.rectangles.put(self.gpa, item.name, item);
            try self.out.line("undo: {s}", .{previous.command});
            return;
        }
        if (equal(commandName, "LIST")) {
            try self.out.line("rectangles: {d}", .{self.rectangles.count()});
            for (try self.list(null)) |item| try self.out.line("{s} {s} {s} {d}x{d}", .{ item.name, item.layer, try notation(self.scratch, item.r), item.r.x2 - item.r.x1, item.r.y2 - item.r.y1 });
            return;
        }
        if (equal(commandName, "INFO")) {
            const item = try self.get(args[0]);
            try self.out.line("{s} {s} {s} {d}x{d} area {d}", .{ item.name, item.layer, try notation(self.scratch, item.r), item.r.x2 - item.r.x1, item.r.y2 - item.r.y1, area(item.r) });
            for ([_]Text{ "overlaps", "touches", "corners", "encloses", "enclosed by" }, 0..) |heading, index| {
                var selected: std.ArrayList(Rectangle) = .empty;
                for (try self.list(null)) |other| {
                    if (equal(other.name, item.name)) continue;
                    const r = compare(item.r, other.r);
                    const matched = if (index == 3) encloses(item.r, other.r) else if (index == 4) encloses(other.r, item.r) else equal(item.layer, other.layer) and r.kind == @as(RelationKind, @fromBackingInt(@intCast(index)));
                    if (matched) try selected.append(self.scratch, other);
                }
                try self.out.line("{s}: {s}", .{ heading, try names(self.scratch, selected.items) });
            }
            return;
        }
        if (equal(commandName, "LAYERS")) {
            var layers: std.StringHashMapUnmanaged(void) = .empty;
            for (try self.list(null)) |item| try layers.put(self.scratch, item.layer, {});
            const layerNames = try sortedKeys(self.scratch, layers);
            try self.out.line("layers: {d}", .{layerNames.len});
            for (layerNames) |layer| {
                const rectangles = try self.list(layer);
                const g = try Grid.build(self.scratch, rectangles);
                try self.out.line("{s}: {d} rectangles, area {d}, nets {d}", .{ layer, rectangles.len, g.covered(1, null), (try nets(self.scratch, rectangles)).len });
            }
            return;
        }
        if (equal(commandName, "OVERLAPS")) {
            try self.overlapsCommand(args);
            return;
        }
        if (oneOf(commandName, &.{ "INTERSECT", "ADJACENT", "ENCLOSE", "PATH" })) {
            const a = try self.get(args[0]);
            const b = try self.get(args[1]);
            if (equal(a.name, b.name)) return self.fail("same rectangle {s}", .{a.name});
            if (equal(commandName, "PATH")) {
                if (!equal(a.layer, b.layer)) return self.fail("different layers", .{});
                try self.path(a, b);
                return;
            }
            const r = compare(a.r, b.r);
            if (equal(commandName, "INTERSECT")) {
                switch (r.kind) {
                    .overlap => try self.out.line("intersect {s} {s}: {s} area {d}", .{ a.name, b.name, try notation(self.scratch, r.r), r.ox * r.oy }),
                    .edge => try self.out.line("intersect {s} {s}: segment {s} length {d}", .{ a.name, b.name, try notation(self.scratch, r.r), r.ox + r.oy }),
                    .corner => try self.out.line("intersect {s} {s}: point {s}", .{ a.name, b.name, try point(self.scratch, r.r.x1, r.r.y1) }),
                    .separate => try self.out.line("intersect {s} {s}: none, gap {d}", .{ a.name, b.name, r.gap }),
                }
            } else if (equal(commandName, "ADJACENT")) {
                switch (r.kind) {
                    .overlap => try self.out.line("adjacent {s} {s}: overlapping", .{ a.name, b.name }),
                    .corner => try self.out.line("adjacent {s} {s}: corner only at {s}", .{ a.name, b.name, try point(self.scratch, r.r.x1, r.r.y1) }),
                    .separate => try self.out.line("adjacent {s} {s}: not adjacent", .{ a.name, b.name }),
                    .edge => {
                        const direction = if (r.ox == 0) (if (a.r.x2 == r.r.x1) "west" else "east") else (if (a.r.y2 == r.r.y1) "south" else "north");
                        try self.out.line("adjacent {s} {s}: {s} is {s} of {s}, edge {s}, length {d}", .{ a.name, b.name, a.name, direction, b.name, try notation(self.scratch, r.r), r.ox + r.oy });
                    },
                }
            } else {
                const m = margins(a.r, b.r);
                try self.out.print("enclose {s} {s}: {s}, margins left {d} bottom {d} right {d} top {d}", .{ a.name, b.name, if (minimum(m) >= 0) "yes" else "no", m[0], m[1], m[2], m[3] });
                if (minimum(m) >= 0) try self.out.print(", min {d}", .{minimum(m)});
                try self.out.add("\n");
            }
            return;
        }
        if (equal(commandName, "AT")) {
            const x = number(args[0]);
            const y = number(args[1]);
            var parts: std.ArrayList(Text) = .empty;
            for (try self.list(null)) |item| {
                const r = item.r;
                if (x < r.x1 or x > r.x2 or y < r.y1 or y > r.y2) continue;
                const vertical = x == r.x1 or x == r.x2;
                const horizontal = y == r.y1 or y == r.y2;
                const pos = if (vertical and horizontal) "corner" else if (vertical or horizontal) "edge" else "inside";
                try parts.append(self.scratch, try std.fmt.allocPrint(self.scratch, "{s} {s} {s}", .{ item.name, item.layer, pos }));
            }
            try self.out.line("at {s}: {s}", .{ try point(self.scratch, x, y), if (parts.items.len == 0) "none" else try join(self.scratch, parts.items, ", ") });
            return;
        }
        if (equal(commandName, "NEAREST")) {
            const item = try self.get(args[0]);
            var best: ?Rectangle = null;
            var gap: Int = 0;
            for (try self.list(item.layer)) |other| {
                if (equal(item.name, other.name)) continue;
                const value = compare(item.r, other.r).gap;
                if (best == null or value < gap) {
                    best = other;
                    gap = value;
                }
            }
            if (best) |other| {
                try self.out.line("nearest {s}: {s} gap {d}", .{ item.name, other.name, gap });
            } else try self.out.line("nearest {s}: none", .{item.name});
            return;
        }
        if (equal(commandName, "RULE")) {
            const kind: RuleKind = if (equal(args[0], "SPACING")) .spacing else if (equal(args[0], "WIDTH")) .width else .enclose;
            const r: Rule = .{ .kind = kind, .inner = args[1], .outer = if (kind == .enclose) args[2] else "", .value = number(args[if (kind == .enclose) @as(usize, 3) else 2]) };
            if (kind == .enclose and equal(r.inner, r.outer)) return self.fail("same layer {s}", .{r.inner});
            const key = try std.fmt.allocPrint(self.gpa, "{s}:{s}:{s}", .{ @tagName(kind), r.inner, r.outer });
            try self.rules.put(self.gpa, key, r);
            if (kind == .enclose) {
                try self.out.line("rule enclose {s} {s} {d}", .{ r.inner, r.outer, r.value });
            } else try self.out.line("rule {s} {s} {d}", .{ @tagName(kind), r.inner, r.value });
            return;
        }
        if (equal(commandName, "CHECK")) {
            try self.check();
            return;
        }
        const layer = args[if (equal(commandName, "COVER")) @as(usize, 1) else 0];
        const rectangles = try self.require(layer);
        const g = try Grid.build(self.scratch, rectangles);
        if (equal(commandName, "AREA")) {
            try self.out.line("area {s}: {d}", .{ layer, g.covered(1, null) });
        } else if (equal(commandName, "COVER")) {
            const k = number(args[0]);
            try self.out.line("cover {s} >= {d}: {d}", .{ layer, k, g.covered(@intCast(k), null) });
        } else if (equal(commandName, "PERIMETER")) {
            try self.out.line("perimeter {s}: {d}", .{ layer, g.perimeter() });
        } else if (equal(commandName, "NETS")) {
            const groups = try nets(self.scratch, rectangles);
            try self.out.line("nets {s}: {d}", .{ layer, groups.len });
            for (groups, 0..) |group, i| {
                const unionGrid = try Grid.build(self.scratch, group);
                try self.out.line("net {d}: {s} area {d}", .{ i + 1, try names(self.scratch, group), unionGrid.covered(1, null) });
            }
        } else if (equal(commandName, "DRC")) {
            const s = number(args[1]);
            const violations = try spacing(self.scratch, rectangles, s);
            try self.out.line("drc {s} spacing {d}: {d} violations", .{ layer, s, violations.len });
            try self.violationLines(violations);
        } else if (equal(commandName, "BBOX")) {
            const r = bounds(rectangles);
            try self.out.line("bbox {s}: {s} {d}x{d}, {d} rectangles, density {s}%", .{ layer, try notation(self.scratch, r), r.x2 - r.x1, r.y2 - r.y1, rectangles.len, try decimal(self.scratch, 100 * g.covered(1, null), area(r)) });
        } else if (equal(commandName, "DENSITY")) {
            try self.density(layer, rectangles, g, number(args[1]));
        } else if (equal(commandName, "RENDER")) {
            const r: Geometry = .{ .x1 = number(args[1]), .y1 = number(args[2]), .x2 = number(args[3]), .y2 = number(args[4]) };
            if (r.x1 >= r.x2 or r.y1 >= r.y2) return self.fail("invalid window", .{});
            if (r.x2 - r.x1 > 60 or r.y2 - r.y1 > 40) return self.fail("window too large", .{});
            try self.out.line("render {s} {s}", .{ layer, try notation(self.scratch, r) });
            var y = r.y2;
            while (y > r.y1) {
                y -= 1;
                var x = r.x1;
                while (x < r.x2) : (x += 1) {
                    var count: usize = 0;
                    for (rectangles) |item| if (x >= item.r.x1 and x < item.r.x2 and y >= item.r.y1 and y < item.r.y2) {
                        count += 1;
                    };
                    try self.out.bytes.append(self.gpa, if (count == 0) '.' else if (count >= 10) '*' else @as(u8, '0') + @as(u8, @intCast(count)));
                }
                try self.out.add("\n");
            }
        } else if (equal(commandName, "EMPTY")) {
            if (try g.empty(self.scratch)) |r| {
                try self.out.line("empty {s}: {s} area {d}", .{ layer, try notation(self.scratch, r), area(r) });
            } else try self.out.line("empty {s}: none", .{layer});
        } else if (equal(commandName, "HOLES")) {
            const holes = try g.holes(self.scratch);
            try self.out.line("holes {s}: {d}", .{ layer, holes.len });
            for (holes, 0..) |hole, i| try self.out.line("hole {d}: area {d}, bbox {s}", .{ i + 1, hole.area, try notation(self.scratch, hole.r) });
        } else if (equal(commandName, "MERGE")) {
            const pieces = try g.pieces(self.scratch);
            try self.out.line("merge {s}: {d} pieces", .{ layer, pieces.len });
            for (pieces) |r| try self.out.line("{s}", .{try notation(self.scratch, r)});
        }
    }
    fn overlapsCommand(self: *Checker, args: []const Text) Error!void {
        const rectangles = if (args.len > 0) try self.require(args[0]) else try self.list(null);
        const Pair = struct { a: Rectangle, b: Rectangle, r: Relation };
        var pairs: std.ArrayList(Pair) = .empty;
        for (rectangles, 0..) |a, i| {
            for (rectangles[i + 1 ..]) |b| {
                const r = compare(a.r, b.r);
                if (equal(a.layer, b.layer) and r.kind == .overlap) try pairs.append(self.scratch, .{ .a = a, .b = b, .r = r });
            }
        }
        std.mem.sort(Pair, pairs.items, {}, struct {
            fn less(_: void, a: Pair, b: Pair) bool {
                const layer = std.mem.order(u8, a.a.layer, b.a.layer);
                const first = std.mem.order(u8, a.a.name, b.a.name);
                return layer == .lt or layer == .eq and (first == .lt or first == .eq and std.mem.order(u8, a.b.name, b.b.name) == .lt);
            }
        }.less);
        if (args.len == 0) {
            try self.out.line("overlaps all layers: {d}", .{pairs.items.len});
        } else try self.out.line("overlaps {s}: {d}", .{ args[0], pairs.items.len });
        for (pairs.items) |pair| {
            if (args.len == 0) try self.out.print("{s} ", .{pair.a.layer});
            try self.out.line("{s} {s} {s} area {d}", .{ pair.a.name, pair.b.name, try notation(self.scratch, pair.r.r), pair.r.ox * pair.r.oy });
        }
    }
    fn path(self: *Checker, a: Rectangle, b: Rectangle) Error!void {
        var queue: std.ArrayList(Rectangle) = .empty;
        try queue.append(self.scratch, a);
        var parents: std.StringHashMapUnmanaged(Text) = .empty;
        try parents.put(self.scratch, a.name, "");
        const rectangles = try self.list(a.layer);
        var i: usize = 0;
        while (i < queue.items.len) : (i += 1) {
            for (rectangles) |item| if (!parents.contains(item.name) and connected(queue.items[i], item)) {
                try parents.put(self.scratch, item.name, queue.items[i].name);
                try queue.append(self.scratch, item);
            };
        }
        if (!parents.contains(b.name)) {
            try self.out.line("path {s} {s}: none", .{ a.name, b.name });
            return;
        }
        var parts: std.ArrayList(Text) = .empty;
        var name = b.name;
        while (name.len > 0) {
            try parts.append(self.scratch, name);
            name = parents.get(name).?;
        }
        std.mem.reverse(Text, parts.items);
        try self.out.line("path {s} {s}: {s} ({d} steps)", .{ a.name, b.name, try join(self.scratch, parts.items, " -> "), parts.items.len - 1 });
    }
    fn density(self: *Checker, layer: Text, rectangles: []const Rectangle, g: Grid, width: Int) Error!void {
        const r = bounds(rectangles);
        const columns = @divTrunc(r.x2 - r.x1 + width - 1, width);
        const rows = @divTrunc(r.y2 - r.y1 + width - 1, width);
        if (columns > 20 or rows > 20) return self.fail("too many windows", .{});
        const values = try self.scratch.alloc(Int, u(columns * rows));
        var lowest: Int = 0;
        var highest: Int = 0;
        var lowX: Int = 0;
        var lowY: Int = 0;
        var highX: Int = 0;
        var highY: Int = 0;
        var y: Int = 0;
        while (y < rows) : (y += 1) {
            var x: Int = 0;
            while (x < columns) : (x += 1) {
                const tile: Geometry = .{ .x1 = r.x1 + x * width, .y1 = r.y1 + y * width, .x2 = r.x1 + (x + 1) * width, .y2 = r.y1 + (y + 1) * width };
                const value = g.covered(1, tile);
                values[u(y * columns + x)] = value;
                if (x == 0 and y == 0 or value < lowest) {
                    lowest = value;
                    lowX = x;
                    lowY = y;
                }
                if (x == 0 and y == 0 or value > highest) {
                    highest = value;
                    highX = x;
                    highY = y;
                }
            }
        }
        try self.out.line("density {s} window {d}: {d}x{d}", .{ layer, width, columns, rows });
        y = rows;
        while (y > 0) {
            y -= 1;
            var x: Int = 0;
            while (x < columns) : (x += 1) {
                if (x > 0) try self.out.add(" ");
                try self.out.print("{d}", .{@divTrunc(100 * values[u(y * columns + x)], width * width)});
            }
            try self.out.add("\n");
        }
        try self.out.line("min {s}% at {s}", .{ try decimal(self.scratch, 100 * lowest, width * width), try point(self.scratch, r.x1 + lowX * width, r.y1 + lowY * width) });
        try self.out.line("max {s}% at {s}", .{ try decimal(self.scratch, 100 * highest, width * width), try point(self.scratch, r.x1 + highX * width, r.y1 + highY * width) });
    }
    fn check(self: *Checker) Error!void {
        if (self.rules.count() == 0) return self.fail("no rules", .{});
        var rules: std.ArrayList(Rule) = .empty;
        var iterator = self.rules.valueIterator();
        while (iterator.next()) |r| try rules.append(self.scratch, r.*);
        std.mem.sort(Rule, rules.items, {}, ruleLess);
        var total: usize = 0;
        for (rules.items) |r| {
            const rectangles = try self.list(r.inner);
            var lines: std.ArrayList(Text) = .empty;
            switch (r.kind) {
                .spacing => for (try spacing(self.scratch, rectangles, r.value)) |v| {
                    try lines.append(self.scratch, try std.fmt.allocPrint(self.scratch, "{s} {s} gap {d} {s}", .{ v.a, v.b, v.gap, v.direction }));
                },
                .width => for (rectangles) |item| {
                    const width = @min(item.r.x2 - item.r.x1, item.r.y2 - item.r.y1);
                    if (width < r.value) try lines.append(self.scratch, try std.fmt.allocPrint(self.scratch, "{s} width {d}", .{ item.name, width }));
                },
                .enclose => {
                    const outer = try self.list(r.outer);
                    for (rectangles) |item| {
                        var best: ?Int = null;
                        for (outer) |other| {
                            const value = minimum(margins(other.r, item.r));
                            best = if (best) |old| @max(old, value) else value;
                        }
                        if (best == null) {
                            try lines.append(self.scratch, try std.fmt.allocPrint(self.scratch, "{s} best margin none", .{item.name}));
                        } else if (best.? < r.value) {
                            try lines.append(self.scratch, try std.fmt.allocPrint(self.scratch, "{s} best margin {d}", .{ item.name, best.? }));
                        }
                    }
                },
            }
            if (r.kind == .enclose) {
                try self.out.line("enclose {s} {s} {d}: {d} violations", .{ r.inner, r.outer, r.value, lines.items.len });
            } else try self.out.line("{s} {s} {d}: {d} violations", .{ @tagName(r.kind), r.inner, r.value, lines.items.len });
            for (lines.items) |line| try self.out.line("{s}", .{line});
            total += lines.items.len;
        }
        try self.out.line("check: {d} violations in {d} rules", .{ total, rules.items.len });
    }
};
fn oneOf(s: Text, choices: []const Text) bool {
    for (choices) |choice| if (equal(s, choice)) return true;
    return false;
}
fn sortedKeys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, struct {
        fn less(_: void, a: Text, b: Text) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return result.items;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count = u(number(std.mem.trimEnd(u8, lines.next().?, "\r")));
    var out: Builder = .{ .gpa = gpa };
    var c: Checker = .{ .gpa = gpa, .scratch = gpa, .out = &out };
    for (0..count) |_| {
        const line = std.mem.trimEnd(u8, lines.next().?, "\r");
        var temporary = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer temporary.deinit();
        c.scratch = temporary.allocator();
        c.command(line) catch |err| {
            if (err != error.Invalid) return err;
            try out.line("{s}", .{failure});
        };
    }
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
