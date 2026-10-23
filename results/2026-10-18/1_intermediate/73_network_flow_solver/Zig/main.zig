const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn number(text: Text) Int {
    return std.fmt.parseInt(Int, text, 10) catch unreachable;
}
fn index(text: Text) usize {
    return @intCast(number(text));
}
fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}
fn split(gpa: Allocator, text: Text, separator: u8) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = std.mem.splitScalar(u8, text, separator);
    while (iterator.next()) |part| try result.append(gpa, part);
    return result.items;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
};
fn yes(value: bool) Text {
    return if (value) "yes" else "no";
}
const Edge = struct {
    from: usize, to: usize, capacity: Int, cost: Int = 0, lower: Int = 0, flow: Int = 0,
};
const Augmentation = struct {
    path: []const i32, amount: Int, stage: usize = 0, unit: Int = 0,
};
const Piece = struct {
    path: []const i32, amount: Int, cycle: bool,
};
const Search = struct {
    levels: []?usize, parents: []i32,
};
const Maximum = struct {
    paths: []Augmentation, phases: usize,
};
const Cheapest = struct {
    paths: []Augmentation, total: Int, cost: Int,
};
const Balances = struct {
    incoming: []Int, outgoing: []Int,
};
const Graph = struct {
    names: std.ArrayList(Text) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    fn copy(self: *const Graph, gpa: Allocator) Allocator.Error!Graph {
        var result: Graph = .{};
        try result.names.appendSlice(gpa, self.names.items);
        try result.edges.appendSlice(gpa, self.edges.items);
        for (result.edges.items) |*edge| edge.flow = 0;
        return result;
    }
    fn arcs(self: *const Graph, gpa: Allocator, vertex: usize) Allocator.Error![]i32 {
        var result: std.ArrayList(i32) = .empty;
        for (self.edges.items, 0..) |edge, i| {
            if (edge.from == vertex) try result.append(gpa, @intCast(i + 1));
        }
        for (self.edges.items, 0..) |edge, i| {
            if (edge.to == vertex) try result.append(gpa, -@as(i32, @intCast(i + 1)));
        }
        return result.items;
    }
    fn edgeIndex(arc: i32) usize {
        return @intCast(@abs(arc) - 1);
    }
    fn endpoints(self: *const Graph, arc: i32) struct { from: usize, to: usize } {
        const edge = self.edges.items[edgeIndex(arc)];
        return if (arc > 0) .{ .from = edge.from, .to = edge.to } else .{ .from = edge.to, .to = edge.from };
    }
    fn residual(self: *const Graph, arc: i32) Int {
        const edge = self.edges.items[edgeIndex(arc)];
        return if (arc > 0) edge.capacity - edge.flow else edge.flow;
    }
    fn arcCost(self: *const Graph, arc: i32) Int {
        const edge = self.edges.items[edgeIndex(arc)];
        return if (arc > 0) edge.cost else -edge.cost;
    }
    fn push(self: *Graph, path: []const i32, amount: Int) void {
        for (path) |arc| self.edges.items[edgeIndex(arc)].flow += if (arc > 0) amount else -amount;
    }
    fn bottleneck(self: *const Graph, path: []const i32) Int {
        var result = self.residual(path[0]);
        for (path[1..]) |arc| result = @min(result, self.residual(arc));
        return result;
    }
    fn bfs(self: *const Graph, gpa: Allocator, source: usize, threshold: Int) Allocator.Error!Search {
        const levels = try gpa.alloc(?usize, self.names.items.len);
        const parents = try gpa.alloc(i32, self.names.items.len);
        @memset(levels, null);
        levels[source] = 0;
        var queue: std.ArrayList(usize) = .empty;
        try queue.append(gpa, source);
        var at: usize = 0;
        while (at < queue.items.len) : (at += 1) {
            const vertex = queue.items[at];
            for (try self.arcs(gpa, vertex)) |arc| {
                const target = self.endpoints(arc).to;
                if (self.residual(arc) >= threshold and levels[target] == null) {
                    levels[target] = levels[vertex].? + 1;
                    parents[target] = arc;
                    try queue.append(gpa, target);
                }
            }
        }
        return .{ .levels = levels, .parents = parents };
    }
    fn buildPath(self: *const Graph, gpa: Allocator, source: usize, target: usize, parents: []const i32) Allocator.Error![]i32 {
        var result: std.ArrayList(i32) = .empty;
        var current = target;
        while (current != source) {
            const arc = parents[current];
            try result.append(gpa, arc);
            current = self.endpoints(arc).from;
        }
        std.mem.reverse(i32, result.items);
        return result.items;
    }
    fn augment(self: *Graph, gpa: Allocator, source: usize, target: usize, threshold: Int) Allocator.Error!?Augmentation {
        const found = try self.bfs(gpa, source, threshold);
        if (found.levels[target] == null) return null;
        const route = try self.buildPath(gpa, source, target, found.parents);
        const amount = self.bottleneck(route);
        self.push(route, amount);
        return .{ .path = route, .amount = amount, .stage = @intCast(threshold) };
    }
    fn maximum(self: *Graph, gpa: Allocator, source: usize, target: usize, mode: Text) Allocator.Error!Maximum {
        var result: std.ArrayList(Augmentation) = .empty;
        var phases: usize = 0;
        if (equal(mode, "DINIC")) {
            const adjacency = try gpa.alloc([]i32, self.names.items.len);
            for (adjacency, 0..) |*list, vertex| list.* = try self.arcs(gpa, vertex);
            while (true) {
                const found = try self.bfs(gpa, source, 1);
                if (found.levels[target] == null) break;
                phases += 1;
                const pointers = try gpa.alloc(usize, self.names.items.len);
                @memset(pointers, 0);
                var route: std.ArrayList(i32) = .empty;
                var vertex = source;
                while (true) {
                    if (vertex == target) {
                        const amount = self.bottleneck(route.items);
                        self.push(route.items, amount);
                        try result.append(gpa, .{ .path = try gpa.dupe(i32, route.items), .amount = amount, .stage = phases });
                        route.clearRetainingCapacity();
                        vertex = source;
                    } else if (pointers[vertex] == adjacency[vertex].len) {
                        if (vertex == source) break;
                        const arc = route.pop().?;
                        vertex = self.endpoints(arc).from;
                        pointers[vertex] += 1;
                    } else {
                        const arc = adjacency[vertex][pointers[vertex]];
                        const next = self.endpoints(arc).to;
                        if (self.residual(arc) > 0 and found.levels[next] != null and found.levels[next].? == found.levels[vertex].? + 1) {
                            try route.append(gpa, arc);
                            vertex = next;
                        } else pointers[vertex] += 1;
                    }
                }
            }
            return .{ .paths = result.items, .phases = phases };
        }
        var threshold: Int = 1;
        if (equal(mode, "SCALING")) {
            var largest: Int = 0;
            for (self.edges.items) |edge| largest = @max(largest, edge.capacity);
            while (threshold * 2 <= largest) threshold *= 2;
        }
        while (threshold > 0) : (threshold = @divTrunc(threshold, 2)) {
            while (try self.augment(gpa, source, target, threshold)) |pushed| try result.append(gpa, pushed);
        }
        return .{ .paths = result.items, .phases = phases };
    }
    fn negativeCycle(self: *const Graph, gpa: Allocator, use_lower: bool) Allocator.Error!bool {
        const distance = try gpa.alloc(Int, self.names.items.len);
        @memset(distance, 0);
        for (0..self.names.items.len) |_| {
            var changed = false;
            for (self.edges.items) |edge| {
                const capacity = edge.capacity - if (use_lower) edge.lower else 0;
                if (capacity > 0 and distance[edge.to] > distance[edge.from] + edge.cost) {
                    distance[edge.to] = distance[edge.from] + edge.cost;
                    changed = true;
                }
            }
            if (!changed) return false;
        }
        return self.names.items.len > 0;
    }
    fn shortest(self: *const Graph, gpa: Allocator, source: usize) Allocator.Error!struct { distance: []?Int, parents: []i32 } {
        const distance = try gpa.alloc(?Int, self.names.items.len);
        const parents = try gpa.alloc(i32, self.names.items.len);
        @memset(distance, null);
        distance[source] = 0;
        var usable: std.ArrayList(i32) = .empty;
        for (0..self.edges.items.len) |i| {
            const arc: i32 = @intCast(i + 1);
            if (self.residual(arc) > 0) try usable.append(gpa, arc);
        }
        for (0..self.edges.items.len) |i| {
            const arc = -@as(i32, @intCast(i + 1));
            if (self.residual(arc) > 0) try usable.append(gpa, arc);
        }
        while (true) {
            var changed = false;
            for (usable.items) |arc| {
                const ends = self.endpoints(arc);
                if (distance[ends.from]) |value| {
                    const candidate = value + self.arcCost(arc);
                    if (distance[ends.to] == null or candidate < distance[ends.to].?) {
                        distance[ends.to] = candidate;
                        parents[ends.to] = arc;
                        changed = true;
                    }
                }
            }
            if (!changed) return .{ .distance = distance, .parents = parents };
        }
    }
    fn minimumCost(self: *Graph, gpa: Allocator, source: usize, target: usize, limit: ?Int) Allocator.Error!Cheapest {
        var paths: std.ArrayList(Augmentation) = .empty;
        var total: Int = 0;
        var cost: Int = 0;
        while (limit == null or total < limit.?) {
            const found = try self.shortest(gpa, source);
            const unit = found.distance[target] orelse break;
            const route = try self.buildPath(gpa, source, target, found.parents);
            var amount = self.bottleneck(route);
            if (limit) |value| amount = @min(amount, value - total);
            self.push(route, amount);
            total += amount;
            cost += amount * unit;
            try paths.append(gpa, .{ .path = route, .amount = amount, .unit = unit });
        }
        return .{ .paths = paths.items, .total = total, .cost = cost };
    }
    fn balances(self: *const Graph, gpa: Allocator) Allocator.Error!Balances {
        const incoming = try gpa.alloc(Int, self.names.items.len);
        const outgoing = try gpa.alloc(Int, self.names.items.len);
        @memset(incoming, 0);
        @memset(outgoing, 0);
        for (self.edges.items) |edge| {
            outgoing[edge.from] += edge.flow;
            incoming[edge.to] += edge.flow;
        }
        return .{ .incoming = incoming, .outgoing = outgoing };
    }
    fn value(self: *const Graph, source: usize) Int {
        var result: Int = 0;
        for (self.edges.items) |edge| {
            if (edge.from == source) result += edge.flow;
            if (edge.to == source) result -= edge.flow;
        }
        return result;
    }
    fn totalCost(self: *const Graph) Int {
        var result: Int = 0;
        for (self.edges.items) |edge| result += edge.flow * edge.cost;
        return result;
    }
    fn notation(self: *const Graph, gpa: Allocator, route: []const i32, original_edges: ?usize) Allocator.Error!Text {
        var out: Builder = .{ .gpa = gpa };
        try out.add(self.names.items[self.endpoints(route[0]).from]);
        for (route) |arc| {
            const magnitude: usize = @intCast(@abs(arc));
            if (original_edges != null and magnitude > original_edges.?) continue;
            try out.print(" {s}{d} {s}", .{ if (arc > 0) @as(Text, "+") else "-", magnitude, self.names.items[self.endpoints(arc).to] });
        }
        return out.bytes.items;
    }
    fn decompose(self: *const Graph, gpa: Allocator) Allocator.Error![]Piece {
        const remaining = try gpa.alloc(Int, self.edges.items.len);
        const balance = try gpa.alloc(Int, self.names.items.len);
        @memset(balance, 0);
        for (self.edges.items, 0..) |edge, i| {
            remaining[i] = edge.flow;
            balance[edge.from] += edge.flow;
            balance[edge.to] -= edge.flow;
        }
        var result: std.ArrayList(Piece) = .empty;
        while (true) {
            var first: ?usize = null;
            for (remaining, 0..) |flow, i| {
                if (flow > 0) { first = i; break; }
            }
            var source = self.edges.items[first orelse return result.items].from;
            for (balance, 0..) |amount, vertex| {
                if (amount > 0) { source = vertex; break; }
            }
            var vertices: std.ArrayList(usize) = .empty;
            var route: std.ArrayList(i32) = .empty;
            try vertices.append(gpa, source);
            while (true) {
                const vertex = vertices.items[vertices.items.len - 1];
                var chosen: usize = 0;
                for (self.edges.items, 0..) |edge, i| {
                    if (edge.from == vertex and remaining[i] > 0) { chosen = i; break; }
                }
                try route.append(gpa, @intCast(chosen + 1));
                const target = self.edges.items[chosen].to;
                if (std.mem.findScalar(usize, vertices.items, target)) |repeated| {
                    const cycle = try gpa.dupe(i32, route.items[repeated..]);
                    var amount = remaining[edgeIndex(cycle[0])];
                    for (cycle) |arc| amount = @min(amount, remaining[edgeIndex(arc)]);
                    for (cycle) |arc| remaining[edgeIndex(arc)] -= amount;
                    try result.append(gpa, .{ .path = cycle, .amount = amount, .cycle = true });
                    break;
                }
                try vertices.append(gpa, target);
                if (balance[target] < 0) {
                    var amount = @min(balance[source], -balance[target]);
                    for (route.items) |arc| amount = @min(amount, remaining[edgeIndex(arc)]);
                    for (route.items) |arc| remaining[edgeIndex(arc)] -= amount;
                    balance[source] -= amount;
                    balance[target] += amount;
                    try result.append(gpa, .{ .path = route.items, .amount = amount, .cycle = false });
                    break;
                }
            }
        }
    }
};

const MatchPair = struct { left: usize, right: usize };
const Matching = struct {
    pairs: []const MatchPair, mates_a: []?usize, mates_b: []?usize,
    fn attempt(self: *Matching, a: usize, examined: []bool) bool {
        for (self.pairs) |pair| {
            const b = pair.right;
            if (pair.left == a and !examined[b]) {
                examined[b] = true;
                if (self.mates_b[b] == null or self.attempt(self.mates_b[b].?, examined)) {
                    self.mates_a[a] = b;
                    self.mates_b[b] = a;
                    return true;
                }
            }
        }
        return false;
    }
};
const Assignment = struct {
    gpa: Allocator, words: []const Text, size: usize, maximize: bool,
    mapping: []usize, used: []bool, best: ?[]usize = null, optimum: Int = 0, count: usize = 0,
    fn visit(self: *Assignment, row: usize, total: Int) Allocator.Error!void {
        if (row == self.size) {
            if (self.best == null or (if (self.maximize) total > self.optimum else total < self.optimum)) {
                self.optimum = total;
                self.count = 0;
                self.best = try self.gpa.dupe(usize, self.mapping);
            }
            if (total == self.optimum) self.count += 1;
            return;
        }
        for (0..self.size) |column| {
            const text = self.words[3 + row * self.size + column];
            if (!self.used[column] and !equal(text, "x")) {
                self.mapping[row] = column;
                self.used[column] = true;
                try self.visit(row + 1, total + number(text));
                self.used[column] = false;
            }
        }
    }
};
const Owner = enum { none, flow, circulation };
const Network = struct {
    gpa: Allocator, out: *Builder, graph: Graph = .{}, demands: std.ArrayList(Int) = .empty,
    owner: Owner = .none, source: usize = 0, target: usize = 0,
    fn vertex(self: *Network, name: Text) Error!usize {
        for (self.graph.names.items, 0..) |candidate, i| if (equal(candidate, name)) return i;
        return bad(self.gpa, "UNKNOWN NODE {s}", .{name});
    }
    fn endpointsCheck(self: *Network, a: Text, b: Text) Error!struct { source: usize, target: usize } {
        const source = try self.vertex(a);
        const target = try self.vertex(b);
        if (source == target) return bad(self.gpa, "SAME NODE", .{});
        return .{ .source = source, .target = target };
    }
    fn start(self: *Network, source: usize, target: usize) Int {
        if (self.owner != .flow or self.source != source or self.target != target) {
            for (self.graph.edges.items) |*edge| edge.flow = 0;
        }
        self.owner = .flow;
        self.source = source;
        self.target = target;
        return self.graph.value(source);
    }
    fn flowList(self: *Network) Allocator.Error!void {
        for (self.graph.edges.items, 0..) |edge, i| try self.out.line("FLOW {d} {s} {s} {d}/{d}", .{
            i + 1, self.graph.names.items[edge.from], self.graph.names.items[edge.to], edge.flow, edge.capacity });
    }
    fn matching(self: *Network, scratch: Allocator, w: []const Text) Error!void {
        const left = try split(scratch, w[1], ',');
        const right = try split(scratch, w[2], ',');
        var used_names: std.StringHashMapUnmanaged(void) = .empty;
        for (left) |name| {
            if (used_names.contains(name)) return bad(self.gpa, "DUPLICATE VERTEX {s}", .{name});
            try used_names.put(scratch, name, {});
        }
        for (right) |name| {
            if (used_names.contains(name)) return bad(self.gpa, "DUPLICATE VERTEX {s}", .{name});
            try used_names.put(scratch, name, {});
        }
        var pairs: std.ArrayList(MatchPair) = .empty;
        if (!equal(w[3], "-")) {
            for (try split(scratch, w[3], ',')) |text| {
                const fields = try split(scratch, text, '-');
                var a: ?usize = null;
                var b: ?usize = null;
                for (left, 0..) |name, i| if (equal(name, fields[0])) { a = i; break; };
                if (a == null) return bad(self.gpa, "UNKNOWN VERTEX {s}", .{fields[0]});
                for (right, 0..) |name, i| if (equal(name, fields[1])) { b = i; break; };
                if (b == null) return bad(self.gpa, "UNKNOWN VERTEX {s}", .{fields[1]});
                for (pairs.items) |pair| {
                    if (pair.left == a.? and pair.right == b.?) return bad(self.gpa, "DUPLICATE PAIR {s}", .{text});
                }
                try pairs.append(scratch, .{ .left = a.?, .right = b.? });
            }
        }
        var match: Matching = .{ .pairs = pairs.items, .mates_a = try scratch.alloc(?usize, left.len), .mates_b = try scratch.alloc(?usize, right.len) };
        @memset(match.mates_a, null);
        @memset(match.mates_b, null);
        for (0..left.len) |a| {
            const examined = try scratch.alloc(bool, right.len);
            @memset(examined, false);
            _ = match.attempt(a, examined);
        }
        const marked_a = try scratch.alloc(bool, left.len);
        const marked_b = try scratch.alloc(bool, right.len);
        @memset(marked_a, false);
        @memset(marked_b, false);
        var queue: std.ArrayList(usize) = .empty;
        var size: usize = 0;
        for (match.mates_a, 0..) |mate, a| {
            if (mate == null) { marked_a[a] = true; try queue.append(scratch, a); } else size += 1;
        }
        var at: usize = 0;
        while (at < queue.items.len) : (at += 1) {
            const a = queue.items[at];
            for (pairs.items) |pair| {
                const b = pair.right;
                if (pair.left == a and (match.mates_a[a] == null or b != match.mates_a[a].?) and !marked_b[b]) {
                    marked_b[b] = true;
                    if (match.mates_b[b]) |mate| {
                        if (!marked_a[mate]) { marked_a[mate] = true; try queue.append(scratch, mate); }
                    }
                }
            }
        }
        try self.out.line("MATCH size={d} left={d} right={d}", .{ size, left.len, right.len });
        for (match.mates_a, 0..) |mate, a| {
            if (mate) |b| try self.out.line("PAIR {s} {s}", .{ left[a], right[b] });
        }
        try self.out.add("FREE ");
        try self.commaNames(left, match.mates_a, null);
        try self.out.add(" ");
        try self.commaNames(right, match.mates_b, null);
        try self.out.add("\n");
        var cover_count: usize = 0;
        for (marked_a) |marked| if (!marked) { cover_count += 1; };
        for (marked_b) |marked| if (marked) { cover_count += 1; };
        try self.out.print("COVER size={d}", .{cover_count});
        for (left, 0..) |name, a| if (!marked_a[a]) { try self.out.print(" {s}", .{name}); };
        for (right, 0..) |name, b| if (marked_b[b]) { try self.out.print(" {s}", .{name}); };
        try self.out.add("\n");
        if (queue.items.len > 0) {
            try self.out.add("HALL ");
            try self.commaNames(left, null, marked_a);
            try self.out.add(" ");
            try self.commaNames(right, null, marked_b);
            try self.out.add("\n");
        }
    }
    fn commaNames(self: *Network, names: []const Text, mates: ?[]const ?usize, marked: ?[]const bool) Allocator.Error!void {
        var count: usize = 0;
        for (names, 0..) |name, i| {
            const include = if (mates) |values| values[i] == null else marked.?[i];
            if (include) {
                if (count > 0) try self.out.add(",");
                try self.out.add(name);
                count += 1;
            }
        }
        if (count == 0) try self.out.add("-");
    }
    fn assignment(self: *Network, scratch: Allocator, w: []const Text) Error!void {
        const size = index(w[2]);
        if (size < 1 or size > 8) return bad(self.gpa, "BAD SIZE", .{});
        if (w.len - 3 != size * size) return bad(self.gpa, "BAD LENGTH", .{});
        var search: Assignment = .{ .gpa = scratch, .words = w, .size = size, .maximize = equal(w[1], "MAX"),
            .mapping = try scratch.alloc(usize, size), .used = try scratch.alloc(bool, size) };
        @memset(search.used, false);
        try search.visit(0, 0);
        const best = search.best orelse {
            try self.out.line("ASSIGN {s} n={d} infeasible", .{ w[1], size });
            return;
        };
        try self.out.line("ASSIGN {s} n={d} total={d} optimal={d}", .{ w[1], size, search.optimum, search.count });
        for (best, 0..) |column, row| try self.out.line("MATE {d} {d} {s}", .{ row + 1, column + 1, w[3 + row * size + column] });
    }
    fn command(self: *Network, scratch: Allocator, w: []const Text) Error!void {
        const cmd = w[0];
        if (equal(cmd, "NODE")) {
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            for (self.graph.names.items) |name| try seen.put(scratch, name, {});
            for (w[1..]) |name| {
                if (seen.contains(name)) return bad(self.gpa, "DUPLICATE NODE {s}", .{name});
                try seen.put(scratch, name, {});
            }
            if (self.graph.names.items.len + w.len - 1 > 20) return bad(self.gpa, "TOO MANY NODES", .{});
            for (w[1..]) |name| {
                try self.graph.names.append(self.gpa, name);
                try self.demands.append(self.gpa, 0);
            }
            try self.out.line("NODE added={d} total={d}", .{ w.len - 1, self.graph.names.items.len });
        } else if (equal(cmd, "EDGE")) {
            const a = try self.vertex(w[1]);
            const b = try self.vertex(w[2]);
            if (a == b) return bad(self.gpa, "SELF LOOP", .{});
            if (self.graph.edges.items.len == 60) return bad(self.gpa, "TOO MANY EDGES", .{});
            const cost: Int = if (w.len == 5) number(w[4]) else 0;
            try self.graph.edges.append(self.gpa, .{ .from = a, .to = b, .capacity = number(w[3]), .cost = cost });
            try self.out.line("EDGE {d} {s} {s} cap={s} cost={d}", .{ self.graph.edges.items.len, w[1], w[2], w[3], cost });
        } else if (equal(cmd, "LOWER") or equal(cmd, "CAP") or equal(cmd, "COST")) {
            const id = index(w[1]);
            if (id < 1 or id > self.graph.edges.items.len) return bad(self.gpa, "UNKNOWN EDGE {s}", .{w[1]});
            const edge = &self.graph.edges.items[id - 1];
            const amount = number(w[2]);
            if (equal(cmd, "LOWER")) {
                if (amount > edge.capacity) return bad(self.gpa, "BAD BOUND", .{});
                edge.lower = amount;
                try self.out.line("LOWER {d} low={d} cap={d}", .{ id, amount, edge.capacity });
            } else if (equal(cmd, "CAP")) {
                if (amount < edge.lower) return bad(self.gpa, "BAD BOUND", .{});
                if (amount < edge.flow) return bad(self.gpa, "BELOW FLOW", .{});
                edge.capacity = amount;
                try self.out.line("CAP {d} low={d} cap={d}", .{ id, edge.lower, amount });
            } else {
                edge.cost = amount;
                try self.out.line("COST {d} cost={d}", .{ id, amount });
            }
        } else if (equal(cmd, "DEMAND")) {
            const at = try self.vertex(w[1]);
            self.demands.items[at] = number(w[2]);
            var total: Int = 0;
            for (self.demands.items) |demand| total += demand;
            try self.out.line("DEMAND {s} {s} total={d}", .{ w[1], w[2], total });
        } else if (equal(cmd, "RESET")) {
            var changed: usize = 0;
            for (self.graph.edges.items) |*edge| {
                if (edge.flow != 0) changed += 1;
                edge.flow = 0;
            }
            self.owner = .none;
            try self.out.line("RESET edges={d}", .{changed});
        } else if (equal(cmd, "CLEAR")) {
            try self.out.line("CLEAR nodes={d} edges={d}", .{ self.graph.names.items.len, self.graph.edges.items.len });
            self.graph = .{};
            self.demands = .empty;
            self.owner = .none;
        } else if (equal(cmd, "SHOW")) {
            const g = &self.graph;
            try self.out.line("NETWORK nodes={d} edges={d}", .{ g.names.items.len, g.edges.items.len });
            switch (self.owner) {
                .none => try self.out.add("STATE none\n"),
                .circulation => try self.out.line("STATE circulation cost={d}", .{g.totalCost()}),
                .flow => try self.out.line("STATE flow {s} {s} value={d} cost={d}", .{
                    g.names.items[self.source], g.names.items[self.target], g.value(self.source), g.totalCost() }),
            }
            const balance = try g.balances(scratch);
            for (g.names.items, 0..) |name, i| try self.out.line("NODE {s} demand={d} out={d} in={d}", .{
                name, self.demands.items[i], balance.outgoing[i], balance.incoming[i] });
            for (g.edges.items, 0..) |edge, i| try self.out.line("EDGE {d} {s} {s} cap={d} cost={d} low={d} flow={d}", .{
                i + 1, g.names.items[edge.from], g.names.items[edge.to], edge.capacity, edge.cost, edge.lower, edge.flow });
        } else if (equal(cmd, "AUGMENT") or equal(cmd, "MAXFLOW") or equal(cmd, "DINIC") or equal(cmd, "SCALING") or
            equal(cmd, "MINCUT") or equal(cmd, "SENSITIVITY") or equal(cmd, "MINCOST") or equal(cmd, "DISJOINT")) {
            const ends = try self.endpointsCheck(w[1], w[2]);
            const source = ends.source;
            const target = ends.target;
            const g = &self.graph;
            if (equal(cmd, "SENSITIVITY")) {
                var base = try g.copy(scratch);
                _ = try base.maximum(scratch, source, target, "MAXFLOW");
                const value = base.value(source);
                const up = try scratch.alloc(bool, g.edges.items.len);
                const down = try scratch.alloc(bool, g.edges.items.len);
                @memset(down, false);
                var ups: usize = 0;
                var downs: usize = 0;
                for (g.edges.items, 0..) |edge, i| {
                    var increased = try g.copy(scratch);
                    increased.edges.items[i].capacity += 1;
                    _ = try increased.maximum(scratch, source, target, "MAXFLOW");
                    up[i] = increased.value(source) > value;
                    if (up[i]) ups += 1;
                    if (edge.capacity > 0) {
                        var decreased = try g.copy(scratch);
                        decreased.edges.items[i].capacity -= 1;
                        _ = try decreased.maximum(scratch, source, target, "MAXFLOW");
                        down[i] = decreased.value(source) < value;
                        if (down[i]) downs += 1;
                    }
                }
                try self.out.line("SENSITIVITY {s} {s} value={d} up={d} down={d}", .{ w[1], w[2], value, ups, downs });
                for (g.edges.items, 0..) |edge, i| {
                    if (up[i] or down[i]) try self.out.line("CRITICAL {d} {s} {s} up={s} down={s}", .{
                        i + 1, g.names.items[edge.from], g.names.items[edge.to], yes(up[i]), yes(down[i]) });
                }
            } else if (equal(cmd, "MINCOST")) {
                if (try g.negativeCycle(scratch, false)) return bad(self.gpa, "NEGATIVE CYCLE", .{});
                const limit: ?Int = if (equal(w[3], "MAX")) null else number(w[3]);
                var working = try g.copy(scratch);
                const found = try working.minimumCost(scratch, source, target, limit);
                if (limit != null and found.total < limit.?) {
                    try self.out.line("MINCOST {s} {s} k={s} infeasible max={d}", .{ w[1], w[2], w[3], found.total });
                    return;
                }
                for (g.edges.items, working.edges.items) |*edge, computed| edge.flow = computed.flow;
                self.owner = .flow;
                self.source = source;
                self.target = target;
                try self.out.line("MINCOST {s} {s} k={s} flow={d} cost={d}", .{ w[1], w[2], w[3], found.total, found.cost });
                for (found.paths, 0..) |pushed, i| try self.out.line("AUG {d} amount={d} cost={d} {s}", .{
                    i + 1, pushed.amount, pushed.unit, try working.notation(scratch, pushed.path, null) });
                try self.flowList();
            } else if (equal(cmd, "DISJOINT")) {
                var working: Graph = .{};
                const entrances = try scratch.alloc(usize, g.names.items.len);
                const exits = try scratch.alloc(usize, g.names.items.len);
                for (g.names.items, 0..) |name, i| {
                    entrances[i] = working.names.items.len;
                    try working.names.append(scratch, name);
                    exits[i] = entrances[i];
                    if (equal(w[3], "VERTEX") and i != source and i != target) {
                        exits[i] = working.names.items.len;
                        try working.names.append(scratch, name);
                    }
                }
                for (g.edges.items) |edge| try working.edges.append(scratch, .{
                    .from = exits[edge.from], .to = entrances[edge.to], .capacity = if (edge.capacity > 0) 1 else 0 });
                if (equal(w[3], "VERTEX")) {
                    for (0..g.names.items.len) |i| {
                        if (i != source and i != target) try working.edges.append(scratch, .{ .from = entrances[i], .to = exits[i], .capacity = 1 });
                    }
                }
                _ = try working.maximum(scratch, entrances[source], entrances[target], "MAXFLOW");
                const parts = try working.decompose(scratch);
                var count: usize = 0;
                for (parts) |part| if (!part.cycle) { count += 1; };
                try self.out.line("DISJOINT {s} {s} {s} count={d}", .{ w[1], w[2], w[3], count });
                count = 0;
                for (parts) |part| {
                    if (!part.cycle) {
                        count += 1;
                        try self.out.line("PATH {d} {s}", .{ count, try working.notation(scratch, part.path, g.edges.items.len) });
                    }
                }
            } else {
                const initial = self.start(source, target);
                if (equal(cmd, "AUGMENT")) {
                    if (try g.augment(scratch, source, target, 1)) |pushed| {
                        try self.out.line("AUGMENT {s} {s} value={d} amount={d} {s}", .{
                            w[1], w[2], g.value(source), pushed.amount, try g.notation(scratch, pushed.path, null) });
                    } else try self.out.line("AUGMENT {s} {s} value={d} none", .{ w[1], w[2], g.value(source) });
                } else {
                    const found = try g.maximum(scratch, source, target, cmd);
                    if (equal(cmd, "MINCUT")) {
                        const reached = try g.bfs(scratch, source, 1);
                        var count: usize = 0;
                        for (g.edges.items) |edge| {
                            if (reached.levels[edge.from] != null and reached.levels[edge.to] == null) count += 1;
                        }
                        try self.out.line("MINCUT {s} {s} value={d} edges={d}", .{ w[1], w[2], g.value(source), count });
                        try self.out.add("SOURCE");
                        for (g.names.items, 0..) |name, i| if (reached.levels[i] != null) { try self.out.print(" {s}", .{name}); };
                        try self.out.add("\nSINK");
                        for (g.names.items, 0..) |name, i| if (reached.levels[i] == null) { try self.out.print(" {s}", .{name}); };
                        try self.out.add("\n");
                        for (g.edges.items, 0..) |edge, i| {
                            if (reached.levels[edge.from] != null and reached.levels[edge.to] == null) try self.out.line("CUT {d} {s} {s} {d}", .{
                                i + 1, g.names.items[edge.from], g.names.items[edge.to], edge.capacity });
                        }
                    } else {
                        try self.out.print("{s} {s} {s} value={d} start={d}", .{ cmd, w[1], w[2], g.value(source), initial });
                        if (equal(cmd, "DINIC")) try self.out.print(" phases={d}", .{found.phases});
                        try self.out.line(" paths={d}", .{found.paths.len});
                        for (found.paths, 0..) |pushed, i| {
                            try self.out.print("AUG {d}", .{i + 1});
                            if (equal(cmd, "DINIC")) try self.out.print(" phase={d}", .{pushed.stage});
                            if (equal(cmd, "SCALING")) try self.out.print(" delta={d}", .{pushed.stage});
                            try self.out.line(" amount={d} {s}", .{ pushed.amount, try g.notation(scratch, pushed.path, null) });
                        }
                        try self.flowList();
                    }
                }
            }
        } else if (equal(cmd, "DECOMPOSE")) {
            const parts = try self.graph.decompose(scratch);
            var paths: usize = 0;
            var cycles: usize = 0;
            for (parts) |part| {
                if (part.cycle) cycles += 1 else paths += 1;
            }
            try self.out.line("DECOMPOSE paths={d} cycles={d}", .{ paths, cycles });
            paths = 0;
            cycles = 0;
            for (parts) |part| {
                if (part.cycle) cycles += 1 else paths += 1;
                try self.out.line("{s} {d} amount={d} {s}", .{ if (part.cycle) @as(Text, "CYCLE") else "PATH",
                    if (part.cycle) cycles else paths, part.amount, try self.graph.notation(scratch, part.path, null) });
            }
        } else if (equal(cmd, "VERIFY")) {
            var violations: std.ArrayList(Text) = .empty;
            const g = &self.graph;
            for (g.edges.items, 0..) |edge, i| {
                if (edge.flow < edge.lower) try violations.append(scratch, try std.fmt.allocPrint(scratch,
                    "LOW {d} flow={d} low={d}", .{ i + 1, edge.flow, edge.lower }));
            }
            const balance = try g.balances(scratch);
            for (g.names.items, 0..) |name, i| {
                if (self.owner == .flow and (i == self.source or i == self.target)) continue;
                const need = if (self.owner == .flow) @as(Int, 0) else self.demands.items[i];
                const net = balance.incoming[i] - balance.outgoing[i];
                if (net != need) try violations.append(scratch, try std.fmt.allocPrint(scratch, "BALANCE {s} net={d} need={d}", .{ name, net, need }));
            }
            if (violations.items.len == 0) try self.out.add("VERIFY ok\n") else {
                try self.out.line("VERIFY violations={d}", .{violations.items.len});
                for (violations.items) |text| try self.out.line("{s}", .{text});
            }
        } else if (equal(cmd, "CIRCULATION")) {
            const g = &self.graph;
            if (equal(w[1], "MINCOST") and try g.negativeCycle(scratch, true)) return bad(self.gpa, "NEGATIVE CYCLE", .{});
            var total: Int = 0;
            for (self.demands.items) |demand| total += demand;
            if (total != 0) {
                try self.out.line("CIRCULATION infeasible unbalanced={d}", .{total});
                return;
            }
            var working = try g.copy(scratch);
            const residual = try scratch.dupe(Int, self.demands.items);
            const source = g.names.items.len;
            const target = source + 1;
            try working.names.appendSlice(scratch, &.{ "SS", "TT" });
            for (g.edges.items, 0..) |edge, i| {
                working.edges.items[i].capacity -= edge.lower;
                residual[edge.to] -= edge.lower;
                residual[edge.from] += edge.lower;
            }
            for (residual, 0..) |amount, i| {
                if (amount < 0) try working.edges.append(scratch, .{ .from = source, .to = i, .capacity = -amount });
            }
            var required: Int = 0;
            var sink_edges: std.ArrayList(usize) = .empty;
            for (residual, 0..) |amount, i| {
                if (amount > 0) {
                    try sink_edges.append(scratch, working.edges.items.len);
                    try working.edges.append(scratch, .{ .from = i, .to = target, .capacity = amount });
                    required += amount;
                }
            }
            if (equal(w[1], "ANY")) {
                _ = try working.maximum(scratch, source, target, "MAXFLOW");
            } else _ = try working.minimumCost(scratch, source, target, null);
            var achieved: Int = 0;
            for (sink_edges.items) |i| achieved += working.edges.items[i].flow;
            if (achieved < required) {
                try self.out.line("CIRCULATION infeasible required={d} achieved={d}", .{ required, achieved });
                try self.out.add("CUT");
                const reached = try working.bfs(scratch, source, 1);
                for (g.names.items, 0..) |name, i| if (reached.levels[i] != null) { try self.out.print(" {s}", .{name}); };
                try self.out.add("\n");
            } else {
                for (g.edges.items, 0..) |*edge, i| edge.flow = edge.lower + working.edges.items[i].flow;
                self.owner = .circulation;
                try self.out.line("CIRCULATION feasible required={d} cost={d}", .{ required, g.totalCost() });
                try self.flowList();
            }
        } else if (equal(cmd, "MATCH")) {
            try self.matching(scratch, w);
        } else if (equal(cmd, "ASSIGN")) {
            try self.assignment(scratch, w);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var input_lines = std.mem.splitScalar(u8, text, '\n');
    const count = index(input_lines.next().?);
    var out: Builder = .{ .gpa = gpa };
    var network: Network = .{ .gpa = gpa, .out = &out };
    for (0..count) |_| {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();
        const words = try split(scratch, input_lines.next().?, ' ');
        network.command(scratch, words) catch |err| switch (err) {
            error.Invalid => try out.line("ERROR {s}", .{failure}),
            else => return err,
        };
    }
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
