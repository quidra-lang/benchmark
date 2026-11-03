const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn member(text: Text, choices: []const Text) bool {
    for (choices) |item| if (equal(text, item)) return true;
    return false;
}
fn u(value: Int) usize {
    return @intCast(value);
}
fn gcd(rawA: Int, rawB: Int) Int {
    var a = if (rawA < 0) -rawA else rawA;
    var b = rawB;
    while (b != 0) {
        const next = @rem(a, b);
        a = b;
        b = next;
    }
    return a;
}
const Rational = struct {
    n: Int = 0,
    d: Int = 1,
    fn init(rawN: Int, rawD: Int) Rational {
        const n = if (rawD < 0) -rawN else rawN;
        const d = if (rawD < 0) -rawD else rawD;
        const common = gcd(n, d);
        return .{ .n = @divTrunc(n, common), .d = @divTrunc(d, common) };
    }
    fn add(a: Rational, b: Rational) Rational {
        return init(a.n * b.d + b.n * a.d, a.d * b.d);
    }
    fn sub(a: Rational, b: Rational) Rational {
        return init(a.n * b.d - b.n * a.d, a.d * b.d);
    }
    fn mul(a: Rational, b: Rational) Rational {
        return init(a.n * b.n, a.d * b.d);
    }
    fn div(a: Rational, b: Rational) Rational {
        return init(a.n * b.d, a.d * b.n);
    }
    fn neg(a: Rational) Rational {
        return .{ .n = -a.n, .d = a.d };
    }
    fn compare(a: Rational, b: Rational) std.math.Order {
        return std.math.order(a.n * b.d, b.n * a.d);
    }
    fn text(a: Rational, gpa: Allocator) Error!Text {
        return if (a.d == 1) try std.fmt.allocPrint(gpa, "{d}", .{a.n}) else try std.fmt.allocPrint(gpa, "{d}/{d}", .{ a.n, a.d });
    }
    fn value(a: Rational, gpa: Allocator) Error!Text {
        const absolute = if (a.n < 0) -a.n else a.n;
        const scaled = @divTrunc(absolute * 1000000, a.d);
        return std.fmt.allocPrint(gpa, "{s} ({s}{d}.{d:0>6})", .{ try a.text(gpa), if (a.n < 0) "-" else "", @divTrunc(scaled, 1000000), @mod(scaled, 1000000) });
    }
};
const zero: Rational = .{};
const one: Rational = .{ .n = 1 };
fn digits(text: Text) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn integer(text: Text) Int {
    return std.fmt.parseInt(Int, text, 10) catch unreachable;
}
fn parseNumber(raw: Text) ?Rational {
    var text = raw;
    var multiplier = one;
    if (std.mem.endsWith(u8, text, "meg")) {
        multiplier = .{ .n = 1000000 };
        text = text[0 .. text.len - 3];
    } else if (std.mem.endsWith(u8, text, "k")) {
        multiplier = .{ .n = 1000 };
        text = text[0 .. text.len - 1];
    } else if (std.mem.endsWith(u8, text, "m")) {
        multiplier = .{ .n = 1, .d = 1000 };
        text = text[0 .. text.len - 1];
    } else if (std.mem.endsWith(u8, text, "u")) {
        multiplier = .{ .n = 1, .d = 1000000 };
        text = text[0 .. text.len - 1];
    }
    const negative = std.mem.startsWith(u8, text, "-");
    if (negative) text = text[1..];
    var result: Rational = undefined;
    if (digits(text)) {
        result = Rational.init(integer(text), 1);
    } else if (std.mem.findScalar(u8, text, '.')) |position| {
        const a = text[0..position];
        const b = text[position + 1 ..];
        if (!digits(a) or !digits(b)) return null;
        var denominator: Int = 1;
        for (b) |_| denominator *= 10;
        result = Rational.init(integer(a) * denominator + integer(b), denominator);
    } else if (std.mem.findScalar(u8, text, '/')) |position| {
        const a = text[0..position];
        const b = text[position + 1 ..];
        if (!digits(a) or !digits(b) or integer(b) == 0) return null;
        result = Rational.init(integer(a), integer(b));
    } else return null;
    result = result.mul(multiplier);
    return if (negative) result.neg() else result;
}
fn validNode(name: Text) bool {
    if (equal(name, "0")) return true;
    if (name.len == 0 or name.len > 8 or name[0] < 'a' or name[0] > 'z') return false;
    for (name) |c| if (!(c >= 'a' and c <= 'z' or std.ascii.isDigit(c))) return false;
    return true;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.print(format ++ "\n", args);
    }
};
fn sortedKeys(gpa: Allocator, map: anytype) Error![]const Text {
    var list: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |name| try list.append(gpa, name.*);
    std.mem.sort(Text, list.items, {}, struct {
        fn less(_: void, a: Text, b: Text) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return list.items;
}
fn words(gpa: Allocator, text: Text) Error![]const Text {
    var list: std.ArrayList(Text) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |item| try list.append(gpa, item);
    return list.items;
}
const Element = struct {
    name: Text,
    kind: u8,
    n1: Text,
    n2: Text,
    c1: Text = "",
    c2: Text = "",
    reference: Text = "",
    value: Rational,
    fn voltageSource(e: Element) bool {
        return e.kind == 'V' or e.kind == 'E' or e.kind == 'H';
    }
    fn independent(e: Element) bool {
        return e.kind == 'V' or e.kind == 'I';
    }
    fn terminals(e: Element) [4]Text {
        return .{ e.n1, e.n2, e.c1, e.c2 };
    }
};
const Union = struct {
    nodes: []const Text,
    indices: std.StringHashMapUnmanaged(usize) = .empty,
    parents: []usize,
    fn init(gpa: Allocator, nodes: []const Text) Error!Union {
        var result: Union = .{ .nodes = nodes, .parents = try gpa.alloc(usize, nodes.len) };
        for (nodes, 0..) |name, i| {
            result.parents[i] = i;
            try result.indices.put(gpa, name, i);
        }
        return result;
    }
    fn root(self: *Union, id: usize) usize {
        if (self.parents[id] != id) self.parents[id] = self.root(self.parents[id]);
        return self.parents[id];
    }
    fn group(self: *Union, name: Text) usize {
        return self.root(self.indices.get(name).?);
    }
    fn join(self: *Union, a: Text, b: Text) void {
        const x = self.group(a);
        const y = self.group(b);
        self.parents[@max(x, y)] = @min(x, y);
    }
};
fn zeroVector(gpa: Allocator, n: usize) Error![]Rational {
    const result = try gpa.alloc(Rational, n);
    @memset(result, zero);
    return result;
}
fn solve(gpa: Allocator, a: []const Rational, b: []const Rational) Error!?[]Rational {
    const n = b.len;
    const rows = try gpa.alloc(Rational, n * (n + 1));
    for (0..n) |i| {
        @memcpy(rows[i * (n + 1) .. i * (n + 1) + n], a[i * n .. (i + 1) * n]);
        rows[i * (n + 1) + n] = b[i];
    }
    for (0..n) |k| {
        var pivot = k;
        while (pivot < n and rows[pivot * (n + 1) + k].n == 0) pivot += 1;
        if (pivot == n) return null;
        if (pivot != k) for (0..n + 1) |j| {
            const old = rows[k * (n + 1) + j];
            rows[k * (n + 1) + j] = rows[pivot * (n + 1) + j];
            rows[pivot * (n + 1) + j] = old;
        };
        const divisor = rows[k * (n + 1) + k];
        for (0..n + 1) |j| rows[k * (n + 1) + j] = rows[k * (n + 1) + j].div(divisor);
        for (0..n) |i| {
            if (i == k) continue;
            const factor = rows[i * (n + 1) + k];
            if (factor.n != 0) for (0..n + 1) |j| {
                rows[i * (n + 1) + j] = rows[i * (n + 1) + j].sub(factor.mul(rows[k * (n + 1) + j]));
            };
        }
    }
    const result = try zeroVector(gpa, n);
    for (result, 0..) |*value, i| value.* = rows[i * (n + 1) + n];
    return result;
}
const Equations = struct {
    gpa: Allocator,
    a: []Rational,
    b: []Rational,
    nodes: []const Text,
    names: []const Text,
    labels: []const Text,
    sources: []const Text,
    indices: std.StringHashMapUnmanaged(usize),
    fn add(self: *Equations, row: Text, column: Text, value: Rational) void {
        if (equal(row, "0") or equal(column, "0")) return;
        const index = self.indices.get(row).? * self.b.len + self.indices.get(column).?;
        self.a[index] = self.a[index].add(value);
    }
    fn rhs(self: *const Equations, vector: []Rational, row: Text, value: Rational) void {
        if (!equal(row, "0")) {
            const index = self.indices.get(row).?;
            vector[index] = vector[index].add(value);
        }
    }
    fn potential(self: *const Equations, solution: []const Rational, node: Text) Rational {
        return if (equal(node, "0")) zero else solution[self.indices.get(node).?];
    }
    fn voltage(self: *const Equations, solution: []const Rational, a: Text, b: Text) Rational {
        return self.potential(solution, a).sub(self.potential(solution, b));
    }
    fn current(self: *const Equations, solution: []const Rational, e: Element) Rational {
        return switch (e.kind) {
            'R' => self.voltage(solution, e.n1, e.n2).div(e.value),
            'I' => e.value,
            'G' => e.value.mul(self.voltage(solution, e.c1, e.c2)),
            'F' => e.value.mul(solution[self.indices.get(e.reference).?]),
            else => solution[self.indices.get(e.name).?],
        };
    }
    fn injection(self: *const Equations, a: Text, b: Text) Error![]Rational {
        const vector = try zeroVector(self.gpa, self.b.len);
        self.rhs(vector, a, one);
        self.rhs(vector, b, one.neg());
        return (try solve(self.gpa, self.a, vector)).?;
    }
    fn alone(self: *const Equations, e: Element, value: Rational) Error![]Rational {
        const vector = try zeroVector(self.gpa, self.b.len);
        if (e.kind == 'V') {
            self.rhs(vector, e.name, value);
        } else {
            self.rhs(vector, e.n1, value.neg());
            self.rhs(vector, e.n2, value);
        }
        return (try solve(self.gpa, self.a, vector)).?;
    }
};
const Resistor = struct { name: Text = "", a: Text, b: Text, value: Rational };
fn reachable(gpa: Allocator, start: Text, edges: []const Resistor) Error!std.StringHashMapUnmanaged(void) {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    try seen.put(gpa, start, {});
    var changed = true;
    while (changed) {
        changed = false;
        for (edges) |edge| {
            if (seen.contains(edge.a) and !seen.contains(edge.b)) {
                try seen.put(gpa, edge.b, {});
                changed = true;
            }
            if (seen.contains(edge.b) and !seen.contains(edge.a)) {
                try seen.put(gpa, edge.a, {});
                changed = true;
            }
        }
    }
    return seen;
}
const counts = [_]struct { name: Text, count: usize }{
    .{ .name = ".OP", .count = 0 },       .{ .name = ".CURRENT", .count = 1 },       .{ .name = ".VOLTAGE", .count = 2 },  .{ .name = ".POWER", .count = 0 },  .{ .name = ".KCL", .count = 1 },
    .{ .name = ".THEVENIN", .count = 2 }, .{ .name = ".NORTON", .count = 2 },        .{ .name = ".MAXPOWER", .count = 2 }, .{ .name = ".TF", .count = 2 },     .{ .name = ".SENS", .count = 1 },
    .{ .name = ".ZPARAM", .count = 4 },   .{ .name = ".SUPERPOSITION", .count = 1 }, .{ .name = ".SWEEP", .count = 5 },    .{ .name = ".MATRIX", .count = 0 }, .{ .name = ".REQ", .count = 2 },
    .{ .name = ".REDUCE", .count = 2 },   .{ .name = ".CHECK", .count = 0 },         .{ .name = ".ALTER", .count = 2 },    .{ .name = ".DELETE", .count = 1 }, .{ .name = ".CLEAR", .count = 0 },
    .{ .name = ".NODES", .count = 0 },    .{ .name = ".PRINT", .count = 0 },
};
const Circuit = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Builder,
    elements: std.ArrayList(Element) = .empty,
    fn bad(self: *Circuit, comptime format: Text, args: anytype) Error {
        failure = std.fmt.allocPrint(self.scratch, format, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn getNodes(self: *Circuit, includeGround: bool, forceGround: bool) Error![]const Text {
        var set: std.StringHashMapUnmanaged(void) = .empty;
        if (forceGround) try set.put(self.scratch, "0", {});
        for (self.elements.items) |e| for (e.terminals()) |node| {
            if (node.len > 0 and (includeGround or !equal(node, "0"))) try set.put(self.scratch, node, {});
        };
        return sortedKeys(self.scratch, set);
    }
    fn checkNode(self: *Circuit, name: Text) Error!void {
        if (equal(name, "0")) return;
        for (try self.getNodes(false, false)) |item| if (equal(name, item)) return;
        return self.bad("unknown node {s}", .{name});
    }
    fn elementIndex(self: *Circuit, name: Text) Error!usize {
        for (self.elements.items, 0..) |e, i| if (equal(e.name, name)) return i;
        return self.bad("unknown element {s}", .{name});
    }
    fn parseValue(self: *Circuit, text: Text) Error!Rational {
        return parseNumber(text) orelse return self.bad("invalid value {s}", .{text});
    }
    fn addElement(self: *Circuit, fields: []const Text) Error!void {
        const name = fields[0];
        const kind = name[0];
        if (std.mem.findScalar(u8, "RVIEGFH", kind) == null) return self.bad("unknown element type {s}", .{name});
        const expected: usize = if (kind == 'E' or kind == 'G') 6 else if (kind == 'F' or kind == 'H') 5 else 4;
        if (fields.len != expected) return self.bad("wrong field count for {s}", .{name});
        for (self.elements.items) |e| if (equal(e.name, name)) return self.bad("duplicate element {s}", .{name});
        const nodeCount: usize = if (kind == 'E' or kind == 'G') 4 else 2;
        for (fields[1 .. nodeCount + 1]) |item| if (!validNode(item)) return self.bad("invalid node {s}", .{item});
        var element: Element = .{ .name = name, .kind = kind, .n1 = fields[1], .n2 = fields[2], .value = zero };
        if (kind == 'E' or kind == 'G') {
            element.c1 = fields[3];
            element.c2 = fields[4];
        }
        if (kind == 'F' or kind == 'H') {
            element.reference = fields[3];
            var found = false;
            for (self.elements.items) |e| if (equal(e.name, element.reference) and e.kind == 'V') {
                found = true;
                break;
            };
            if (!found) return self.bad("unknown voltage source {s}", .{element.reference});
        }
        element.value = try self.parseValue(fields[fields.len - 1]);
        if (kind == 'R' and element.value.n <= 0) return self.bad("nonpositive resistance {s}", .{name});
        try self.elements.append(self.gpa, element);
    }
    fn floating(self: *Circuit) Error![]const Text {
        const nodes = try self.getNodes(true, true);
        var groups = try Union.init(self.scratch, nodes);
        for (self.elements.items) |e| if (e.kind == 'R' or e.voltageSource()) groups.join(e.n1, e.n2);
        var result: std.ArrayList(Text) = .empty;
        for (nodes) |name| if (!equal(name, "0") and groups.group(name) != groups.group("0")) try result.append(self.scratch, name);
        return result.items;
    }
    fn sourceLoops(self: *Circuit) Error![]const Text {
        var groups = try Union.init(self.scratch, try self.getNodes(true, true));
        var result: std.ArrayList(Text) = .empty;
        for (self.elements.items) |e| if (e.voltageSource()) {
            if (groups.group(e.n1) == groups.group(e.n2)) try result.append(self.scratch, e.name);
            groups.join(e.n1, e.n2);
        };
        return result.items;
    }
    fn structure(self: *Circuit) Error!void {
        if ((try self.getNodes(false, false)).len == 0) return self.bad("no nodes", .{});
        const floatingNodes = try self.floating();
        if (floatingNodes.len > 0) return self.bad("floating node {s}", .{floatingNodes[0]});
        const loops = try self.sourceLoops();
        if (loops.len > 0) return self.bad("voltage source loop at {s}", .{loops[0]});
    }
    fn build(self: *Circuit) Error!Equations {
        const nodes = try self.getNodes(false, false);
        var names: std.ArrayList(Text) = .empty;
        var labels: std.ArrayList(Text) = .empty;
        var sources: std.ArrayList(Text) = .empty;
        var indices: std.StringHashMapUnmanaged(usize) = .empty;
        for (nodes) |name| {
            try indices.put(self.scratch, name, names.items.len);
            try names.append(self.scratch, try std.fmt.allocPrint(self.scratch, "V({s})", .{name}));
            try labels.append(self.scratch, name);
        }
        for (self.elements.items) |e| if (e.voltageSource()) {
            try indices.put(self.scratch, e.name, names.items.len);
            try names.append(self.scratch, try std.fmt.allocPrint(self.scratch, "I({s})", .{e.name}));
            try labels.append(self.scratch, e.name);
            try sources.append(self.scratch, e.name);
        };
        var m: Equations = .{ .gpa = self.scratch, .nodes = nodes, .names = names.items, .labels = labels.items, .sources = sources.items, .indices = indices, .a = try zeroVector(self.scratch, names.items.len * names.items.len), .b = try zeroVector(self.scratch, names.items.len) };
        for (self.elements.items) |e| {
            const w = e.value;
            switch (e.kind) {
                'R' => {
                    const g = one.div(w);
                    m.add(e.n1, e.n1, g);
                    m.add(e.n2, e.n2, g);
                    m.add(e.n1, e.n2, g.neg());
                    m.add(e.n2, e.n1, g.neg());
                },
                'I' => {
                    m.rhs(m.b, e.n1, w.neg());
                    m.rhs(m.b, e.n2, w);
                },
                'G' => {
                    m.add(e.n1, e.c1, w);
                    m.add(e.n2, e.c2, w);
                    m.add(e.n1, e.c2, w.neg());
                    m.add(e.n2, e.c1, w.neg());
                },
                'F' => {
                    m.add(e.n1, e.reference, w);
                    m.add(e.n2, e.reference, w.neg());
                },
                else => {
                    m.add(e.n1, e.name, one);
                    m.add(e.name, e.n1, one);
                    m.add(e.n2, e.name, one.neg());
                    m.add(e.name, e.n2, one.neg());
                    if (e.kind == 'V') {
                        m.rhs(m.b, e.name, w);
                    } else if (e.kind == 'E') {
                        m.add(e.name, e.c1, w.neg());
                        m.add(e.name, e.c2, w);
                    } else m.add(e.name, e.reference, w.neg());
                },
            }
        }
        return m;
    }
    fn resistance(self: *Circuit, rawA: Text, rawB: Text) Error!void {
        const nodes = try self.getNodes(true, true);
        var groups = try Union.init(self.scratch, nodes);
        for (self.elements.items) |e| if (e.kind == 'V') groups.join(e.n1, e.n2);
        const a = nodes[groups.group(rawA)];
        const b = nodes[groups.group(rawB)];
        if (equal(a, b)) {
            try self.out.line("Req = {s}", .{try zero.value(self.scratch)});
            return;
        }
        var edges: std.ArrayList(Resistor) = .empty;
        for (self.elements.items) |e| if (e.kind == 'R') {
            const x = nodes[groups.group(e.n1)];
            const y = nodes[groups.group(e.n2)];
            if (!equal(x, y)) try edges.append(self.scratch, .{ .a = x, .b = y, .value = e.value });
        };
        const component = try reachable(self.scratch, a, edges.items);
        if (!component.contains(b)) {
            try self.out.line("Req = INFINITE", .{});
            return;
        }
        var indices: std.StringHashMapUnmanaged(usize) = .empty;
        for (try sortedKeys(self.scratch, component)) |name| if (!equal(name, b)) try indices.put(self.scratch, name, indices.count());
        const n = indices.count();
        const matrix = try zeroVector(self.scratch, n * n);
        const rhs = try zeroVector(self.scratch, n);
        for (edges.items) |edge| {
            if (!component.contains(edge.a)) continue;
            const g = one.div(edge.value);
            const x = indices.get(edge.a);
            const y = indices.get(edge.b);
            if (x) |i| matrix[i * n + i] = matrix[i * n + i].add(g);
            if (y) |j| matrix[j * n + j] = matrix[j * n + j].add(g);
            if (x != null and y != null) {
                matrix[x.? * n + y.?] = matrix[x.? * n + y.?].sub(g);
                matrix[y.? * n + x.?] = matrix[y.? * n + x.?].sub(g);
            }
        }
        rhs[indices.get(a).?] = one;
        const solution = (try solve(self.scratch, matrix, rhs)).?;
        try self.out.line("Req = {s}", .{try solution[indices.get(a).?].value(self.scratch)});
    }
    fn reduce(self: *Circuit, a: Text, b: Text) Error!void {
        if (equal(a, b)) {
            try self.out.line("Req = {s}", .{try zero.value(self.scratch)});
            return;
        }
        var list: std.ArrayList(Resistor) = .empty;
        for (self.elements.items) |e| if (e.kind == 'R') try list.append(self.scratch, .{ .name = e.name, .a = e.n1, .b = e.n2, .value = e.value });
        const component = try reachable(self.scratch, a, list.items);
        if (!component.contains(b)) {
            try self.out.line("Req = INFINITE", .{});
            return;
        }
        var kept: std.ArrayList(Resistor) = .empty;
        for (list.items) |edge| if (component.contains(edge.a)) try kept.append(self.scratch, edge);
        list = kept;
        var serial: usize = 0;
        while (true) {
            var selfLoop: ?usize = null;
            for (list.items, 0..) |edge, i| if (equal(edge.a, edge.b)) {
                selfLoop = i;
                break;
            };
            if (selfLoop) |index| {
                try self.out.line("remove {s}", .{list.orderedRemove(index).name});
                continue;
            }
            var degrees: std.StringHashMapUnmanaged(usize) = .empty;
            for (list.items) |edge| {
                try degrees.put(self.scratch, edge.a, (degrees.get(edge.a) orelse 0) + 1);
                try degrees.put(self.scratch, edge.b, (degrees.get(edge.b) orelse 0) + 1);
            }
            const internal = try sortedKeys(self.scratch, degrees);
            var dangling: ?Text = null;
            for (internal) |name| if (!equal(name, a) and !equal(name, b) and degrees.get(name).? == 1) {
                dangling = name;
                break;
            };
            if (dangling) |name| {
                for (list.items, 0..) |edge, i| if (equal(edge.a, name) or equal(edge.b, name)) {
                    try self.out.line("remove {s}", .{list.orderedRemove(i).name});
                    break;
                };
                continue;
            }
            var pair: ?[2]usize = null;
            outer: for (list.items, 0..) |x, i| {
                for (list.items[i + 1 ..], i + 1..) |y, j| {
                    if (equal(x.a, y.a) and equal(x.b, y.b) or equal(x.a, y.b) and equal(x.b, y.a)) {
                        pair = .{ i, j };
                        break :outer;
                    }
                }
            }
            var middle: ?Text = null;
            if (pair == null) {
                for (internal) |name| if (!equal(name, a) and !equal(name, b) and degrees.get(name).? == 2) {
                    middle = name;
                    break;
                };
                if (middle) |name| {
                    var matches: std.ArrayList(usize) = .empty;
                    for (list.items, 0..) |edge, i| if (equal(edge.a, name) or equal(edge.b, name)) try matches.append(self.scratch, i);
                    pair = .{ matches.items[0], matches.items[1] };
                } else break;
            }
            const indices = pair.?;
            const x = list.items[indices[0]];
            const y = list.items[indices[1]];
            serial += 1;
            const name = try std.fmt.allocPrint(self.scratch, "#{d}", .{serial});
            const value = if (middle == null) x.value.mul(y.value).div(x.value.add(y.value)) else x.value.add(y.value);
            const first = if (middle) |nodeName| (if (equal(x.a, nodeName)) x.b else x.a) else x.a;
            const second = if (middle) |nodeName| (if (equal(y.a, nodeName)) y.b else y.a) else x.b;
            try self.out.line("{s} = {s} {s} {s} = {s}", .{ name, x.name, if (middle == null) "||" else "+", y.name, try value.value(self.scratch) });
            _ = list.orderedRemove(indices[1]);
            _ = list.orderedRemove(indices[0]);
            try list.append(self.scratch, .{ .name = name, .a = first, .b = second, .value = value });
        }
        if (list.items.len == 1) {
            try self.out.line("Req = {s}", .{try list.items[0].value.value(self.scratch)});
        } else try self.out.line("not series-parallel: {d} resistors remain", .{list.items.len});
    }
    fn command(self: *Circuit, fields: []const Text) Error!void {
        const name = fields[0];
        const args = fields[1..];
        var expected: ?usize = null;
        for (counts) |entry| if (equal(entry.name, name)) {
            expected = entry.count;
            break;
        };
        if (expected == null) return self.bad("unknown command {s}", .{name});
        if (args.len != expected.?) return self.bad("wrong argument count for {s}", .{name});
        if (equal(name, ".ALTER")) {
            const index = try self.elementIndex(args[0]);
            const value = try self.parseValue(args[1]);
            const e = self.elements.items[index];
            if (e.kind == 'R' and value.n <= 0) return self.bad("nonpositive resistance {s}", .{e.name});
            try self.out.line("altered {s}: {s} -> {s}", .{ e.name, try e.value.text(self.scratch), try value.text(self.scratch) });
            self.elements.items[index].value = value;
            return;
        }
        if (equal(name, ".DELETE")) {
            const index = try self.elementIndex(args[0]);
            for (self.elements.items) |e| if ((e.kind == 'F' or e.kind == 'H') and equal(e.reference, args[0])) return self.bad("{s} is referenced by {s}", .{ args[0], e.name });
            _ = self.elements.orderedRemove(index);
            try self.out.line("deleted {s}", .{args[0]});
            return;
        }
        if (equal(name, ".CLEAR")) {
            try self.out.line("cleared {d} elements", .{self.elements.items.len});
            self.elements.clearRetainingCapacity();
            return;
        }
        if (equal(name, ".PRINT")) {
            if (self.elements.items.len == 0) try self.out.line("empty netlist", .{});
            for (self.elements.items) |e| {
                try self.out.print("{s} {s} {s} ", .{ e.name, e.n1, e.n2 });
                if (e.kind == 'E' or e.kind == 'G') try self.out.print("{s} {s} ", .{ e.c1, e.c2 });
                if (e.kind == 'F' or e.kind == 'H') try self.out.print("{s} ", .{e.reference});
                try self.out.line("{s}", .{try e.value.text(self.scratch)});
            }
            return;
        }
        if (equal(name, ".NODES")) {
            const nodes = try self.getNodes(true, false);
            if (nodes.len == 0) try self.out.line("no nodes", .{});
            for (nodes) |node| {
                try self.out.print("{s}:", .{node});
                for (self.elements.items) |e| for (e.terminals()) |terminal| {
                    if (equal(terminal, node)) {
                        try self.out.print(" {s}", .{e.name});
                        break;
                    }
                };
                try self.out.add("\n");
            }
            return;
        }
        if (equal(name, ".CHECK")) {
            const nodes = try self.getNodes(false, false);
            if (nodes.len == 0) {
                try self.out.line("no nodes", .{});
                return;
            }
            var found = false;
            for (nodes) |node| {
                var degree: usize = 0;
                for (self.elements.items) |e| {
                    if (equal(e.n1, node)) degree += 1;
                    if (equal(e.n2, node)) degree += 1;
                }
                if (degree < 2) {
                    try self.out.line("dangling node {s}", .{node});
                    found = true;
                }
            }
            for (try self.floating()) |node| {
                try self.out.line("floating node {s}", .{node});
                found = true;
            }
            for (try self.sourceLoops()) |source| {
                try self.out.line("voltage source loop at {s}", .{source});
                found = true;
            }
            if (!found) {
                const m = try self.build();
                try self.out.line("{s}", .{if (try solve(self.scratch, m.a, m.b) == null) "singular matrix" else "ok"});
            }
            return;
        }
        if (equal(name, ".REQ") or equal(name, ".REDUCE")) {
            try self.checkNode(args[0]);
            try self.checkNode(args[1]);
            if (equal(name, ".REQ")) {
                try self.resistance(args[0], args[1]);
            } else try self.reduce(args[0], args[1]);
            return;
        }
        if (equal(name, ".SWEEP")) {
            const index = try self.elementIndex(args[0]);
            const from = try self.parseValue(args[1]);
            const to = try self.parseValue(args[2]);
            const step = try self.parseValue(args[3]);
            try self.checkNode(args[4]);
            if (step.n <= 0) return self.bad("invalid sweep step", .{});
            if (from.compare(to) == .gt) return self.bad("invalid sweep range", .{});
            const ratio = to.sub(from).div(step);
            const points = @divTrunc(ratio.n, ratio.d) + 1;
            if (points > 20) return self.bad("too many sweep points", .{});
            if (self.elements.items[index].kind == 'R' and from.n <= 0) return self.bad("nonpositive resistance {s}", .{args[0]});
            try self.structure();
            var temporary: Circuit = .{ .gpa = self.scratch, .scratch = self.scratch, .out = self.out };
            try temporary.elements.appendSlice(self.scratch, self.elements.items);
            var k: Int = 0;
            while (k < points) : (k += 1) {
                const value = from.add(step.mul(.{ .n = k }));
                temporary.elements.items[index].value = value;
                const m = try temporary.build();
                if (try solve(self.scratch, m.a, m.b)) |solution| {
                    try self.out.line("{s} = {s}: V({s}) = {s}", .{ args[0], try value.text(self.scratch), args[4], try m.potential(solution, args[4]).value(self.scratch) });
                } else try self.out.line("{s} = {s}: singular matrix", .{ args[0], try value.text(self.scratch) });
            }
            return;
        }
        if (equal(name, ".CURRENT")) {
            _ = try self.elementIndex(args[0]);
        } else if (equal(name, ".TF")) {
            try self.checkNode(args[0]);
            const index = try self.elementIndex(args[1]);
            if (!self.elements.items[index].independent()) return self.bad("not an independent source {s}", .{args[1]});
        } else for (args) |node| try self.checkNode(node);
        try self.structure();
        const m = try self.build();
        if (equal(name, ".MATRIX")) {
            try self.out.add("unknowns:");
            for (m.names) |unknown| try self.out.print(" {s}", .{unknown});
            try self.out.add("\n");
            for (m.labels, 0..) |label, i| {
                try self.out.print("{s}:", .{label});
                for (0..m.b.len) |j| try self.out.print(" {s}", .{try m.a[i * m.b.len + j].text(self.scratch)});
                try self.out.line(" | {s}", .{try m.b[i].text(self.scratch)});
            }
            return;
        }
        const solution = (try solve(self.scratch, m.a, m.b)) orelse return self.bad("singular matrix", .{});
        if (equal(name, ".OP")) {
            for (m.nodes) |node| try self.out.line("V({s}) = {s}", .{ node, try m.potential(solution, node).value(self.scratch) });
            for (m.sources) |source| try self.out.line("I({s}) = {s}", .{ source, try solution[m.indices.get(source).?].value(self.scratch) });
        } else if (equal(name, ".CURRENT")) {
            const e = self.elements.items[try self.elementIndex(args[0])];
            try self.out.line("I({s}) = {s}", .{ e.name, try m.current(solution, e).value(self.scratch) });
        } else if (equal(name, ".VOLTAGE")) {
            try self.out.line("V({s},{s}) = {s}", .{ args[0], args[1], try m.voltage(solution, args[0], args[1]).value(self.scratch) });
        } else if (equal(name, ".POWER")) {
            var absorbed = zero;
            var delivered = zero;
            var total = zero;
            for (self.elements.items) |e| {
                const power = m.voltage(solution, e.n1, e.n2).mul(m.current(solution, e));
                try self.out.line("P({s}) = {s}", .{ e.name, try power.value(self.scratch) });
                if (power.n > 0) absorbed = absorbed.add(power);
                if (power.n < 0) delivered = delivered.add(power.neg());
                total = total.add(power);
            }
            try self.out.line("absorbed = {s}", .{try absorbed.value(self.scratch)});
            try self.out.line("delivered = {s}", .{try delivered.value(self.scratch)});
            try self.out.line("total = {s}", .{try total.value(self.scratch)});
        } else if (equal(name, ".KCL")) {
            var sum = zero;
            for (self.elements.items) |e| if (equal(e.n1, args[0]) or equal(e.n2, args[0])) {
                var current = zero;
                if (!equal(e.n1, e.n2)) {
                    current = m.current(solution, e);
                    if (equal(e.n2, args[0])) current = current.neg();
                }
                try self.out.line("I({s}) leaving {s} = {s}", .{ e.name, args[0], try current.value(self.scratch) });
                sum = sum.add(current);
            };
            try self.out.line("sum = {s}", .{try sum.value(self.scratch)});
        } else if (member(name, &.{ ".THEVENIN", ".NORTON", ".MAXPOWER" })) {
            const vth = m.voltage(solution, args[0], args[1]);
            const rth = m.voltage(try m.injection(args[0], args[1]), args[0], args[1]);
            if (equal(name, ".NORTON")) {
                if (rth.n == 0) return self.bad("zero thevenin resistance", .{});
                try self.out.line("In = {s}", .{try vth.div(rth).value(self.scratch)});
                try self.out.line("Rn = {s}", .{try rth.value(self.scratch)});
            } else if (equal(name, ".MAXPOWER")) {
                if (rth.n <= 0) return self.bad("nonpositive thevenin resistance", .{});
                try self.out.line("RL = {s}", .{try rth.value(self.scratch)});
                try self.out.line("Pmax = {s}", .{try vth.mul(vth).div((Rational{ .n = 4 }).mul(rth)).value(self.scratch)});
            } else {
                try self.out.line("Vth = {s}", .{try vth.value(self.scratch)});
                try self.out.line("Rth = {s}", .{try rth.value(self.scratch)});
            }
        } else if (equal(name, ".TF")) {
            const source = self.elements.items[try self.elementIndex(args[1])];
            const unit = try m.alone(source, one);
            try self.out.line("gain = {s}", .{try m.potential(unit, args[0]).value(self.scratch)});
            if (source.kind == 'V') {
                const current = unit[m.indices.get(source.name).?];
                if (current.n == 0) {
                    try self.out.line("input resistance = INFINITE", .{});
                } else try self.out.line("input resistance = {s}", .{try one.neg().div(current).value(self.scratch)});
            } else try self.out.line("input resistance = {s}", .{try m.voltage(unit, source.n2, source.n1).value(self.scratch)});
            try self.out.line("output resistance = {s}", .{try m.potential(try m.injection(args[0], "0"), args[0]).value(self.scratch)});
        } else if (equal(name, ".SENS")) {
            for (self.elements.items) |e| {
                const rhs = try zeroVector(self.scratch, m.b.len);
                switch (e.kind) {
                    'R' => {
                        const value = m.current(solution, e).div(e.value);
                        m.rhs(rhs, e.n1, value);
                        m.rhs(rhs, e.n2, value.neg());
                    },
                    'I' => {
                        m.rhs(rhs, e.n1, one.neg());
                        m.rhs(rhs, e.n2, one);
                    },
                    'G', 'F' => {
                        const value = if (e.kind == 'G') m.voltage(solution, e.c1, e.c2) else solution[m.indices.get(e.reference).?];
                        m.rhs(rhs, e.n1, value.neg());
                        m.rhs(rhs, e.n2, value);
                    },
                    'V' => m.rhs(rhs, e.name, one),
                    'E' => m.rhs(rhs, e.name, m.voltage(solution, e.c1, e.c2)),
                    'H' => m.rhs(rhs, e.name, solution[m.indices.get(e.reference).?]),
                    else => unreachable,
                }
                try self.out.line("dV({s})/d{s} = {s}", .{ args[0], e.name, try m.potential((try solve(self.scratch, m.a, rhs)).?, args[0]).value(self.scratch) });
            }
        } else if (equal(name, ".ZPARAM")) {
            const z1 = try m.injection(args[0], args[1]);
            const z2 = try m.injection(args[2], args[3]);
            try self.out.line("z11 = {s}", .{try m.voltage(z1, args[0], args[1]).value(self.scratch)});
            try self.out.line("z12 = {s}", .{try m.voltage(z2, args[0], args[1]).value(self.scratch)});
            try self.out.line("z21 = {s}", .{try m.voltage(z1, args[2], args[3]).value(self.scratch)});
            try self.out.line("z22 = {s}", .{try m.voltage(z2, args[2], args[3]).value(self.scratch)});
        } else if (equal(name, ".SUPERPOSITION")) {
            var total = zero;
            for (self.elements.items) |e| if (e.independent()) {
                const value = m.potential(try m.alone(e, e.value), args[0]);
                try self.out.line("{s}: V({s}) = {s}", .{ e.name, args[0], try value.value(self.scratch) });
                total = total.add(value);
            };
            try self.out.line("total: V({s}) = {s}", .{ args[0], try total.value(self.scratch) });
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    var unused: Builder = .{ .gpa = gpa };
    var circuit: Circuit = .{ .gpa = gpa, .scratch = gpa, .out = &unused };
    var lineNumber: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        lineNumber += 1;
        if (equal(line, ".END")) break;
        if (line.len == 0 or line[0] == '*') continue;
        var commandArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer commandArena.deinit();
        const scratch = commandArena.allocator();
        var out: Builder = .{ .gpa = scratch };
        circuit.scratch = scratch;
        circuit.out = &out;
        const fields = try words(scratch, line);
        const result = if (line[0] == '.') circuit.command(fields) else circuit.addElement(fields);
        result catch |err| {
            if (err != error.Invalid) return err;
            out.bytes.clearRetainingCapacity();
            try out.line("error: line {d}: {s}", .{ lineNumber, failure });
        };
        try output.interface.writeAll(out.bytes.items);
    }
    try output.interface.flush();
}
