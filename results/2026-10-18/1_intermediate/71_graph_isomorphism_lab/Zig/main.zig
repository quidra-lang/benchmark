const std = @import("std");

const Allocator = std.mem.Allocator;

const Text = []const u8;

const Error = Allocator.Error || error{Invalid};
var failure: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
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
    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};

fn split(gpa: Allocator, text: Text, separator: u8) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    for (text, 0..) |c, i| if (c == separator) {
        try result.append(gpa, text[start..i]);
        start = i + 1;
    };
    try result.append(gpa, text[start..]);
    return result.items;
}

fn number(text: Text) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}

fn numberWord(text: Text) bool {
    if (text.len == 0 or text.len > 3 or (text.len > 1 and text[0] == '0')) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn nameWord(text: Text) bool {
    if (text.len == 0 or text.len > 8 or text[0] < 'a' or text[0] > 'z') return false;
    for (text) |c| if ((c < 'a' or c > 'z') and !std.ascii.isDigit(c)) return false;
    return true;
}

fn edgeWord(text: Text) bool {
    const at = std.mem.findScalar(u8, text, '-') orelse return false;
    return numberWord(text[0..at]) and numberWord(text[at + 1 ..]);
}

fn integers(gpa: Allocator, values: []const usize) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (values, 0..) |value, i| {
        if (i > 0) try out.add(" ");
        try out.print("{d}", .{value});
    }
    return out.result();
}

fn yes(value: bool) Text {
    return if (value) "yes" else "no";
}

fn lessNumber(_: void, a: usize, b: usize) bool {
    return a < b;
}

fn greaterNumber(_: void, a: usize, b: usize) bool {
    return a > b;
}

fn textLess(_: void, a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn sortedKeys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, textLess);
    return result.items;
}

fn compare(a: []const usize, b: []const usize) std.math.Order {
    for (0..@min(a.len, b.len)) |i| {
        const order = std.math.order(a[i], b[i]);
        if (order != .eq) return order;
    }
    return std.math.order(a.len, b.len);
}

fn colorCount(colors: []const usize) usize {
    var count: usize = 0;
    for (colors) |color| count = @max(count, color + 1);
    return count;
}

fn cellSizes(gpa: Allocator, colors: []const usize) Allocator.Error![]usize {
    const sizes = try gpa.alloc(usize, colorCount(colors));
    @memset(sizes, 0);
    for (colors) |color| sizes[color] += 1;
    return sizes;
}

const Edge = struct {
    a: usize,
    b: usize
};

const Canon = struct {
    nodes: usize = 0,
    leaves: usize = 0,
    text: Text = "",
    labels: ?[]const usize = null,
    best: std.ArrayList([]const usize) = .empty
};

const Invariants = struct {
    degrees: []usize,
    sizes: []usize,
    edges: usize,
    triangles: usize,
    components: usize,
    girth: Text,
    diameter: Text,
    radius: Text,
    bipartite: bool
};

const Graph = struct {
    n: usize,
    adjacent: [16]u16 = @splat(0),
    canonical: ?*Canon = null,
    fn has(self: *const Graph, a: usize, b: usize) bool {
        return self.adjacent[a] & (@as(u16, 1) << @as(u4, @intCast(b))) != 0;
    }
    fn join(self: *Graph, a: usize, b: usize) void {
        self.adjacent[a] |= @as(u16, 1) << @as(u4, @intCast(b));
        self.adjacent[b] |= @as(u16, 1) << @as(u4, @intCast(a));
    }
    fn edges(self: *const Graph, gpa: Allocator) Allocator.Error![]Edge {
        var result: std.ArrayList(Edge) = .empty;
        for (0..self.n) |a| for (a + 1..self.n) |b| if (self.has(a, b)) {
            try result.append(gpa, .{ .a = a, .b = b });
        };
        return result.items;
    }
    fn leafText(self: *const Graph, gpa: Allocator, labels: []const usize) Allocator.Error!Text {
        const reverse = try gpa.alloc(usize, self.n);
        for (labels, 0..) |label, v| reverse[label] = v;
        const text = try gpa.alloc(u8, self.n * (self.n - 1) / 2);
        var at: usize = 0;
        for (0..self.n) |a| for (a + 1..self.n) |b| {
            text[at] = if (self.has(reverse[a], reverse[b])) '1' else '0';
            at += 1;
        };
        return text;
    }
    fn canon(self: *Graph, gpa: Allocator) Error!*Canon {
        if (self.canonical) |cached| return cached;
        const result = try gpa.create(Canon);
        result.* = .{};
        const initial = try refine(gpa, self, try degreeColors(gpa, self));
        try visitCanonical(gpa, self, result, initial.colors);
        self.canonical = result;
        return result;
    }
    fn invariants(self: *const Graph, gpa: Allocator) Error!Invariants {
        const degrees = try gpa.alloc(usize, self.n);
        for (self.adjacent[0..self.n], 0..) |mask, i| degrees[i] = @popCount(mask);
        std.mem.sort(usize, degrees, {}, greaterNumber);
        var triangles: usize = 0;
        for (0..self.n) |a| for (a + 1..self.n) |b| for (b + 1..self.n) |c| if (self.has(a, b) and self.has(a, c) and self.has(b, c)) {
            triangles += 1;
        };
        var sizes: std.ArrayList(usize) = .empty;
        var reached: [16]bool = @splat(false);
        var coloring: [16]i8 = @splat(0);
        var shortest: usize = 0;
        var diameter: usize = 0;
        var radius = self.n;
        var bipartite = true;
        for (0..self.n) |start| {
            var distance: [16]i32 = @splat(-1);
            var parent: [16]i32 = @splat(-1);
            var queue: std.ArrayList(usize) = .empty;
            distance[start] = 0;
            try queue.append(gpa, start);
            var at: usize = 0;
            var eccentricity: usize = 0;
            while (at < queue.items.len) : (at += 1) {
                const v = queue.items[at];
                eccentricity = @max(eccentricity, @as(usize, @intCast(distance[v])));
                for (0..self.n) |w| {
                    if (!self.has(v, w)) continue;
                    if (distance[w] < 0) {
                        distance[w] = distance[v] + 1;
                        parent[w] = @intCast(v);
                        try queue.append(gpa, w);
                    }
                    else if (parent[v] != @as(i32, @intCast(w))) {
                        const length: usize = @intCast(distance[v] + distance[w] + 1);
                        if (shortest == 0 or length < shortest) shortest = length;
                    }
                }
            }
            if (!reached[start]) {
                try sizes.append(gpa, queue.items.len);
                for (queue.items) |v| reached[v] = true;
                coloring[start] = 1;
                var pending: std.ArrayList(usize) = .empty;
                try pending.append(gpa, start);
                var position: usize = 0;
                while (position < pending.items.len) : (position += 1) {
                    const v = pending.items[position];
                    for (0..self.n) |w| if (self.has(v, w)) {
                        if (coloring[w] == 0) {
                            coloring[w] = -coloring[v];
                            try pending.append(gpa, w);
                        }
                        else if (coloring[w] == coloring[v]) bipartite = false;
                    };
                }
            }
            diameter = @max(diameter, eccentricity);
            radius = @min(radius, eccentricity);
        }
        std.mem.sort(usize, sizes.items, {}, greaterNumber);
        return .{ .degrees = degrees, .sizes = sizes.items, .edges = (try self.edges(gpa)).len, .triangles = triangles, .components = sizes.items.len,
            .girth = if (shortest == 0) "none" else try std.fmt.allocPrint(gpa, "{d}", .{shortest}),
            .diameter = if (sizes.items.len == 1) try std.fmt.allocPrint(gpa, "{d}", .{diameter}) else "INF",
            .radius = if (sizes.items.len == 1) try std.fmt.allocPrint(gpa, "{d}", .{radius}) else "INF", .bipartite = bipartite };
    }
    fn clique(self: *const Graph, gpa: Allocator) Error![]usize {
        var best: []usize = &.{};
        const limit = @as(u32, 1) << @as(u5, @intCast(self.n));
        var mask: u32 = 1;
        while (mask < limit) : (mask += 1) {
            if (@popCount(mask) < best.len) continue;
            var vertices: std.ArrayList(usize) = .empty;
            var valid = true;
            for (0..self.n) |v| if (mask & (@as(u32, 1) << @as(u5, @intCast(v))) != 0) {
                try vertices.append(gpa, v);
                if (mask & ~(@as(u32, self.adjacent[v]) | (@as(u32, 1) << @as(u5, @intCast(v)))) != 0) {
                    valid = false;
                    break;
                }
            };
            if (valid and (vertices.items.len > best.len or compare(vertices.items, best) == .lt)) best = vertices.items;
        }
        return best;
    }
    fn chromatic(self: *const Graph, gpa: Allocator) Error!struct {
        count: usize,
        colors: []usize
    }
    {
        const colors = try gpa.alloc(usize, self.n);
        for (1..self.n + 1) |limit| if (colorSearch(self, colors, 0, limit)) return .{ .count = limit, .colors = colors };
        unreachable;
    }
};

fn makeGraph(gpa: Allocator, n: usize) Allocator.Error!*Graph {
    const g = try gpa.create(Graph);
    g.* = .{ .n = n };
    return g;
}

fn degreeColors(gpa: Allocator, g: *const Graph) Allocator.Error![]usize {
    const degrees = try gpa.alloc(usize, g.n);
    const ordered = try gpa.alloc(usize, g.n);
    for (g.adjacent[0..g.n], 0..) |mask, i| {
        degrees[i] = @popCount(mask);
        ordered[i] = degrees[i];
    }
    std.mem.sort(usize, ordered, {}, lessNumber);
    var unique: std.ArrayList(usize) = .empty;
    for (ordered) |degree| if (unique.items.len == 0 or unique.items[unique.items.len - 1] != degree) {
        try unique.append(gpa, degree);
    };
    for (degrees) |*degree| for (unique.items, 0..) |value, i| {
        if (value == degree.*) {
            degree.* = i;
            break;
        }
    };
    return degrees;
}

const Refinement = struct {
    colors: []usize,
    rounds: usize
};

fn signatureLess(signatures: [][]usize, a: usize, b: usize) bool {
    return compare(signatures[a], signatures[b]) == .lt;
}

fn refine(gpa: Allocator, g: *const Graph, initial: []const usize) Error!Refinement {
    var current = try gpa.dupe(usize, initial);
    var rounds: usize = 0;
    while (true) {
        const signatures = try gpa.alloc([]usize, g.n);
        const vertices = try gpa.alloc(usize, g.n);
        for (0..g.n) |v| {
            var neighbors: std.ArrayList(usize) = .empty;
            for (0..g.n) |w| if (g.has(v, w)) {
                try neighbors.append(gpa, current[w]);
            };
            std.mem.sort(usize, neighbors.items, {}, lessNumber);
            signatures[v] = try gpa.alloc(usize, neighbors.items.len + 1);
            signatures[v][0] = current[v];
            @memcpy(signatures[v][1..], neighbors.items);
            vertices[v] = v;
        }
        std.mem.sort(usize, vertices, signatures, signatureLess);
        const next = try gpa.alloc(usize, g.n);
        var color: usize = 0;
        for (vertices, 0..) |v, i| {
            if (i > 0 and compare(signatures[v], signatures[vertices[i - 1]]) != .eq) color += 1;
            next[v] = color;
        }
        if (color + 1 == colorCount(current)) return .{ .colors = current, .rounds = rounds };
        current = next;
        rounds += 1;
    }
}

fn individualize(gpa: Allocator, colors: []const usize, vertex: usize) Allocator.Error![]usize {
    const result = try gpa.dupe(usize, colors);
    const selected = colors[vertex];
    for (colors, 0..) |color, v| if (v != vertex and color >= selected) {
        result[v] += 1;
    };
    return result;
}

fn visitCanonical(gpa: Allocator, g: *const Graph, result: *Canon, colors: []const usize) Error!void {
    result.nodes += 1;
    const sizes = try cellSizes(gpa, colors);
    if (sizes.len == g.n) {
        result.leaves += 1;
        const text = try g.leafText(gpa, colors);
        if (result.labels == null or std.mem.order(u8, text, result.text) == .gt) {
            result.text = text;
            result.labels = try gpa.dupe(usize, colors);
            result.best = .empty;
        }
        if (equal(text, result.text)) try result.best.append(gpa, try gpa.dupe(usize, colors));
        return;
    }
    var selected: usize = 0;
    var size = g.n + 1;
    for (sizes, 0..) |count, color| if (count > 1 and count < size) {
        selected = color;
        size = count;
    };
    for (colors, 0..) |color, v| if (color == selected) {
        const next = try refine(gpa, g, try individualize(gpa, colors, v));
        try visitCanonical(gpa, g, result, next.colors);
    };
}

fn relabel(gpa: Allocator, g: *const Graph, permutation: []const usize) Allocator.Error!*Graph {
    const result = try makeGraph(gpa, g.n);
    for (try g.edges(gpa)) |edge| result.join(permutation[edge.a], permutation[edge.b]);
    return result;
}

fn colorSearch(g: *const Graph, colors: []usize, v: usize, limit: usize) bool {
    if (v == g.n) return true;
    for (0..limit) |color| {
        var valid = true;
        for (0..v) |w| if (g.has(v, w) and colors[w] == color) {
            valid = false;
            break;
        };
        if (valid) {
            colors[v] = color;
            if (colorSearch(g, colors, v + 1, limit)) return true;
        }
    }
    return false;
}

const Dsu = struct {
    parents: []usize,
    fn init(gpa: Allocator, n: usize) Allocator.Error!Dsu {
        const parents = try gpa.alloc(usize, n);
        for (parents, 0..) |*parent, i| parent.* = i;
        return .{ .parents = parents };
    }
    fn find(self: *Dsu, x: usize) usize {
        if (self.parents[x] != x) self.parents[x] = self.find(self.parents[x]);
        return self.parents[x];
    }
    fn unite(self: *Dsu, a: usize, b: usize) void {
        const x = self.find(a);
        const y = self.find(b);
        if (x != y) self.parents[y] = x;
    }
    fn groups(self: *Dsu, gpa: Allocator) Allocator.Error![][]usize {
        var lists: std.ArrayList(std.ArrayList(usize)) = .empty;
        const where = try gpa.alloc(?usize, self.parents.len);
        @memset(where, null);
        for (0..self.parents.len) |i| {
            const root = self.find(i);
            if (where[root] == null) {
                where[root] = lists.items.len;
                try lists.append(gpa, .empty);
            }
            try lists.items[where[root].?].append(gpa, i);
        }
        const result = try gpa.alloc([]usize, lists.items.len);
        for (lists.items, 0..) |list, i| result[i] = list.items;
        return result;
    }
};

const Example = struct {
    mapping: []usize,
    induced: bool
};

const Embeddings = struct {
    gpa: Allocator,
    pattern: *const Graph,
    target: *const Graph,
    mapping: []usize,
    used: []bool,
    count: usize = 0,
    induced: usize = 0,
    examples: std.ArrayList(Example) = .empty,
    fn visit(self: *Embeddings, v: usize, is_induced: bool) Error!void {
        if (v == self.pattern.n) {
            self.count += 1;
            if (is_induced) self.induced += 1;
            if (self.examples.items.len < 5) try self.examples.append(self.gpa, .{ .mapping = try self.gpa.dupe(usize, self.mapping), .induced = is_induced });
            return;
        }
        for (0..self.target.n) |w| {
            if (self.used[w]) continue;
            var valid = true;
            var next_induced = is_induced;
            for (0..v) |u| {
                if (self.pattern.has(u, v) and !self.target.has(self.mapping[u], w)) {
                    valid = false;
                    break;
                }
                if (!self.pattern.has(u, v) and self.target.has(self.mapping[u], w)) next_induced = false;
            }
            if (valid) {
                self.mapping[v] = w;
                self.used[w] = true;
                try self.visit(v + 1, next_induced);
                self.used[w] = false;
            }
        }
    }
};

const command_names = [_]Text{ "GRAPH", "CYCLE", "PATH", "COMPLETE", "BIPARTITE", "STAR", "WHEEL", "PETERSEN", "HYPERCUBE", "CIRCULANT", "GRID", "COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE", "DELETE", "LIST", "SHOW", "INVARIANTS", "REFINE", "CANON", "ISO", "AUT", "SUBISO", "CLASSIFY" };

const Command = enum {
    graph,
    cycle,
    path,
    complete,
    bipartite,
    star,
    wheel,
    petersen,
    hypercube,
    circulant,
    grid,
    complement,
    line,
    product,
    union_graph,
    relabel,
    induced,
    canonize,
    delete,
    list,
    show,
    invariants,
    refine,
    canon,
    iso,
    aut,
    subiso,
    classify
};

const Lab = struct {
    gpa: Allocator,
    out: Builder,
    graphs: std.StringHashMapUnmanaged(*Graph) = .empty,
    fn automorphisms(self: *Lab, name: Text, g: *Graph) Error!void {
        const gpa = self.gpa;
        const data = try g.canon(gpa);
        const edges = try g.edges(gpa);
        var vertices = try Dsu.init(gpa, g.n);
        var edge_sets = try Dsu.init(gpa, edges.len);
        const reverse = try gpa.alloc(usize, g.n);
        for (data.labels.?, 0..) |label, v| reverse[label] = v;
        for (data.best.items) |labeling| {
            const sigma = try gpa.alloc(usize, g.n);
            for (labeling, 0..) |label, v| {
                sigma[v] = reverse[label];
                vertices.unite(v, sigma[v]);
            }
            for (edges, 0..) |edge, i| {
                const a = @min(sigma[edge.a], sigma[edge.b]);
                const b = @max(sigma[edge.a], sigma[edge.b]);
                for (edges, 0..) |mapped, j| if (a == mapped.a and b == mapped.b) {
                    edge_sets.unite(i, j);
                    break;
                };
            }
        }
        const vertex_orbits = try vertices.groups(gpa);
        const edge_orbits = try edge_sets.groups(gpa);
        try self.out.line("aut {s} order {d}", .{ name, data.best.items.len });
        try self.out.line("vertex orbits {d}", .{vertex_orbits.len});
        for (vertex_orbits) |orbit| try self.out.line("orbit {s}", .{try integers(gpa, orbit)});
        try self.out.line("edge orbits {d}", .{edge_orbits.len});
        for (edge_orbits) |orbit| {
            try self.out.add("orbit");
            for (orbit) |index| try self.out.print(" {d}-{d}", .{ edges[index].a, edges[index].b });
            try self.out.add("\n");
        }
        try self.out.line("transitive vertex {s} edge {s}", .{ yes(vertex_orbits.len == 1), yes(edge_orbits.len == 1) });
    }
    fn subiso(self: *Lab, a_name: Text, b_name: Text, pattern: *Graph, target: *Graph) Error!void {
        const gpa = self.gpa;
        var search: Embeddings = .{ .gpa = gpa, .pattern = pattern, .target = target, .mapping = try gpa.alloc(usize, pattern.n), .used = try gpa.alloc(bool, target.n) };
        @memset(search.used, false);
        if (pattern.n <= target.n) try search.visit(0, true);
        const group_order = (try pattern.canon(gpa)).best.items.len;
        try self.out.line("subiso {s} {s} embeddings {d} induced {d}", .{ a_name, b_name, search.count, search.induced });
        try self.out.line("copies {d} induced {d}", .{ search.count / group_order, search.induced / group_order });
        for (search.examples.items) |example| try self.out.line("embedding {s}{s}", .{ try integers(gpa, example.mapping), if (example.induced) " induced" else "" });
    }
    fn classify(self: *Lab, n: usize) Error!void {
        const gpa = self.gpa;
        if (n == 0) return bad(gpa, "bad value", .{});
        if (n > 5) return bad(gpa, "too large", .{});
        var current: std.StringHashMapUnmanaged(void) = .empty;
        const zero = try gpa.alloc(u8, n * (n - 1) / 2);
        @memset(zero, '0');
        try current.put(gpa, zero, {});
        var levels: std.ArrayList([]Text) = .empty;
        var total: usize = 0;
        for (0..n * (n - 1) / 2 + 1) |_| {
            const level = try sortedKeys(gpa, current);
            try levels.append(gpa, level);
            total += level.len;
            var next: std.StringHashMapUnmanaged(void) = .empty;
            for (level) |text| {
                const source = try makeGraph(gpa, n);
                var index: usize = 0;
                for (0..n) |a| for (a + 1..n) |b| {
                    if (text[index] == '1') source.join(a, b);
                    index += 1;
                };
                for (0..n) |a| for (a + 1..n) |b| if (!source.has(a, b)) {
                    const changed = try makeGraph(gpa, n);
                    changed.adjacent = source.adjacent;
                    changed.join(a, b);
                    try next.put(gpa, (try changed.canon(gpa)).text, {});
                };
            }
            current = next;
        }
        try self.out.line("classify {d} total {d}", .{ n, total });
        for (levels.items, 0..) |level, m| {
            try self.out.print("edges {d} count {d}", .{ m, level.len });
            for (level) |text| try self.out.print(" {s}", .{if (text.len == 0) "-" else text});
            try self.out.add("\n");
        }
    }
    fn command(self: *Lab, words: []const Text) Error!void {
        const gpa = self.gpa;
        const name = words[0];
        const args = words[1..];
        var found: ?Command = null;
        for (command_names, 0..) |candidate, i| if (equal(candidate, name)) {
            found = @enumFromInt(i);
            break;
        };
        const cmd = found orelse return bad(gpa, "unknown command {s}", .{name});
        const defining = @intFromEnum(cmd) < 18;
        var minimum: usize = 1;
        var maximum: ?usize = 1;
        switch (cmd) {
            .list => {
                minimum = 0;
                maximum = 0;
            }, .graph, .relabel, .refine => {
                minimum = if (cmd == .refine) 1 else 2;
                maximum = null;
            },
            .circulant, .induced => {
                minimum = 3;
                maximum = null;
            }, .bipartite, .grid, .product, .union_graph => {
                minimum = 3;
                maximum = 3;
            },
            .cycle, .path, .complete, .star, .wheel, .hypercube, .complement, .line, .canonize, .iso, .subiso => {
                minimum = 2;
                maximum = 2;
            }, else => {
            },
        }
        if (args.len < minimum or (maximum != null and args.len > maximum.?)) return bad(gpa, "bad arguments", .{});
        const name_positions = try gpa.alloc(bool, args.len);
        @memset(name_positions, false);
        if (defining) name_positions[0] = true;
        const existing: []const usize = switch (cmd) {
            .complement, .line, .relabel, .induced, .canonize => &.{1}, .product, .union_graph => &.{ 1, 2 }, .delete, .show, .invariants, .refine, .canon, .aut => &.{0}, .iso, .subiso => &.{ 0, 1 }, else => &.{}
        };
        for (existing) |i| name_positions[i] = true;
        for (args, 0..) |arg, i| {
            const valid = if (name_positions[i]) nameWord(arg) else if (cmd == .graph and i > 1) edgeWord(arg) else numberWord(arg);
            if (!valid) return bad(gpa, "bad arguments", .{});
        }
        for (existing) |i| if (!self.graphs.contains(args[i])) return bad(gpa, "no graph {s}", .{args[i]});
        var g: *Graph = undefined;
        if (defining) {
            switch (cmd) {
                .graph, .cycle, .path, .complete, .star, .wheel, .hypercube, .circulant => {
                    var n = number(args[1]);
                    const lower: usize = if (cmd == .cycle or cmd == .circulant or cmd == .wheel) 3 else 1;
                    const upper: usize = if (cmd == .wheel or cmd == .star) 15 else if (cmd == .hypercube) 4 else 16;
                    if (n < lower) return bad(gpa, "bad value", .{});
                    if (n > upper) return bad(gpa, "too large", .{});
                    if (cmd == .star or cmd == .wheel) n += 1 else if (cmd == .hypercube) n = @as(usize, 1) << @as(u6, @intCast(n));
                    g = try makeGraph(gpa, n);
                    switch (cmd) {
                        .graph => for (args[2..]) |word| {
                            const at = std.mem.findScalar(u8, word, '-').?;
                            const a = number(word[0..at]);
                            const b = number(word[at + 1 ..]);
                            if (a >= n or b >= n or a == b) return bad(gpa, "bad edge {s}", .{word});
                            if (g.has(a, b)) return bad(gpa, "duplicate edge {s}", .{word});
                            g.join(a, b);
                        },
                        .cycle => for (0..n) |v| g.join(v, (v + 1) % n), .path => for (0..n - 1) |v| g.join(v, v + 1),
                        .complete => for (0..n) |a| {
                            for (a + 1..n) |b| g.join(a, b);
                        },
                        .star, .wheel => for (1..n) |v| {
                            g.join(0, v);
                            if (cmd == .wheel) g.join(v, if (v + 1 == n) 1 else v + 1);
                        },
                        .hypercube => for (0..n) |v| {
                            var bit: usize = 1;
                            while (bit < n) : (bit <<= 1) g.join(v, v ^ bit);
                        },
                        .circulant => {
                            var previous: usize = 0;
                            for (args[2..]) |word| {
                                const jump = number(word);
                                if (jump <= previous or 2 * jump > n) return bad(gpa, "bad value", .{});
                                for (0..n) |v| g.join(v, (v + jump) % n);
                                previous = jump;
                            }
                        },
                        else => unreachable,
                    }
                },
                .bipartite, .grid => {
                    const a = number(args[1]);
                    const b = number(args[2]);
                    if (a == 0 or b == 0) return bad(gpa, "bad value", .{});
                    const n = if (cmd == .grid) a * b else a + b;
                    if (n > 16) return bad(gpa, "too large", .{});
                    g = try makeGraph(gpa, n);
                    for (0..a) |x| for (0..b) |y| {
                        if (cmd == .bipartite) g.join(x, a + y) else {
                            if (y + 1 < b) g.join(x * b + y, x * b + y + 1);
                            if (x + 1 < a) g.join(x * b + y, (x + 1) * b + y);
                        }
                    };
                },
                .petersen => {
                    g = try makeGraph(gpa, 10);
                    for (0..5) |i| {
                        g.join(i, (i + 1) % 5);
                        g.join(i, i + 5);
                        g.join(i + 5, 5 + (i + 2) % 5);
                    }
                },
                .complement => {
                    const a = self.graphs.get(args[1]).?;
                    g = try makeGraph(gpa, a.n);
                    for (0..a.n) |x| for (x + 1..a.n) |y| if (!a.has(x, y)) {
                        g.join(x, y);
                    };
                },
                .line => {
                    const edges = try self.graphs.get(args[1]).?.edges(gpa);
                    if (edges.len == 0) return bad(gpa, "no edges", .{});
                    if (edges.len > 16) return bad(gpa, "too large", .{});
                    g = try makeGraph(gpa, edges.len);
                    for (edges, 0..) |a, i| for (i + 1..edges.len) |j| {
                        const b = edges[j];
                        if (a.a == b.a or a.a == b.b or a.b == b.a or a.b == b.b) g.join(i, j);
                    };
                },
                .product, .union_graph => {
                    const a = self.graphs.get(args[1]).?;
                    const b = self.graphs.get(args[2]).?;
                    const n = if (cmd == .product) a.n * b.n else a.n + b.n;
                    if (n > 16) return bad(gpa, "too large", .{});
                    g = try makeGraph(gpa, n);
                    if (cmd == .union_graph) {
                        for (try a.edges(gpa)) |edge| g.join(edge.a, edge.b);
                        for (try b.edges(gpa)) |edge| g.join(edge.a + a.n, edge.b + a.n);
                    }
                    else {
                        for (0..a.n) |x| for (try b.edges(gpa)) |edge| {
                            g.join(x * b.n + edge.a, x * b.n + edge.b);
                        };
                        for (0..b.n) |y| for (try a.edges(gpa)) |edge| {
                            g.join(edge.a * b.n + y, edge.b * b.n + y);
                        };
                    }
                },
                .relabel, .induced => {
                    const a = self.graphs.get(args[1]).?;
                    if (cmd == .relabel and args.len - 2 != a.n) return bad(gpa, "bad permutation", .{});
                    const values = try gpa.alloc(usize, args.len - 2);
                    const seen = try gpa.alloc(bool, a.n);
                    @memset(seen, false);
                    for (args[2..], 0..) |word, i| {
                        const value = number(word);
                        if (value >= a.n or seen[value]) return bad(gpa, "{s}", .{if (cmd == .relabel) "bad permutation" else "bad vertices"});
                        seen[value] = true;
                        values[i] = value;
                    }
                    if (cmd == .relabel) g = try relabel(gpa, a, values) else {
                        g = try makeGraph(gpa, values.len);
                        for (values, 0..) |x, i| for (i + 1..values.len) |j| if (a.has(x, values[j])) {
                            g.join(i, j);
                        };
                    }
                },
                .canonize => {
                    const source = self.graphs.get(args[1]).?;
                    g = try relabel(gpa, source, (try source.canon(gpa)).labels.?);
                },
                else => unreachable,
            }
            const action: Text = if (self.graphs.contains(args[0])) "redefined" else "defined";
            try self.graphs.put(gpa, args[0], g);
            try self.out.line("{s} {s} n {d} m {d}", .{ action, args[0], g.n, (try g.edges(gpa)).len });
            return;
        }
        if (existing.len > 0) g = self.graphs.get(args[0]).?;
        switch (cmd) {
            .delete => {
                _ = self.graphs.remove(args[0]);
                try self.out.line("deleted {s}", .{args[0]});
            },
            .list => {
                const names = try sortedKeys(gpa, self.graphs);
                try self.out.line("graphs {d}", .{names.len});
                for (names) |graph_name| {
                    const value = self.graphs.get(graph_name).?;
                    try self.out.line("{s} n {d} m {d}", .{ graph_name, value.n, (try value.edges(gpa)).len });
                }
            },
            .show => {
                try self.out.line("graph {s} n {d} m {d}", .{ args[0], g.n, (try g.edges(gpa)).len });
                for (0..g.n) |v| {
                    try self.out.print("{d}:", .{v});
                    for (0..g.n) |w| if (g.has(v, w)) {
                        try self.out.print(" {d}", .{w});
                    };
                    try self.out.add("\n");
                }
            },
            .invariants => {
                const data = try g.invariants(gpa);
                try self.out.line("invariants {s}", .{args[0]});
                try self.out.line("degrees {s}", .{try integers(gpa, data.degrees)});
                try self.out.line("edges {d} triangles {d}", .{ data.edges, data.triangles });
                try self.out.line("components {d} sizes {s}", .{ data.components, try integers(gpa, data.sizes) });
                try self.out.line("girth {s} diameter {s} radius {s}", .{ data.girth, data.diameter, data.radius });
                try self.out.line("bipartite {s}", .{yes(data.bipartite)});
                if (g.n > 12) try self.out.add("clique -\nchromatic -\n") else {
                    const clique = try g.clique(gpa);
                    const chromatic = try g.chromatic(gpa);
                    try self.out.line("clique {d} {s}", .{ clique.len, try integers(gpa, clique) });
                    try self.out.line("chromatic {d} {s}", .{ chromatic.count, try integers(gpa, chromatic.colors) });
                }
            },
            .refine => {
                for (args[1..]) |word| if (number(word) >= g.n) return bad(gpa, "bad vertices", .{});
                var state = try refine(gpa, g, try degreeColors(gpa, g));
                for (args[1..]) |word| {
                    const v = number(word);
                    if ((try cellSizes(gpa, state.colors))[state.colors[v]] == 1) return bad(gpa, "singleton {d}", .{v});
                    const next = try refine(gpa, g, try individualize(gpa, state.colors, v));
                    state = .{ .colors = next.colors, .rounds = state.rounds + next.rounds };
                }
                try self.out.line("refine {s} rounds {d} cells {d}", .{ args[0], state.rounds, colorCount(state.colors) });
                for (0..colorCount(state.colors)) |color| {
                    try self.out.print("{d}:", .{color});
                    for (state.colors, 0..) |c, v| if (c == color) {
                        try self.out.print(" {d}", .{v});
                    };
                    try self.out.add("\n");
                }
            },
            .canon => {
                const data = try g.canon(gpa);
                try self.out.line("canon {s} nodes {d} leaves {d}", .{ args[0], data.nodes, data.leaves });
                try self.out.line("labels {s}", .{try integers(gpa, data.labels.?)});
                try self.out.line("string {s}", .{if (data.text.len == 0) "-" else data.text});
            },
            .iso => {
                const b = self.graphs.get(args[1]).?;
                const a_data = try g.invariants(gpa);
                const b_data = try b.invariants(gpa);
                var message: ?Text = null;
                if (g.n != b.n) message = try std.fmt.allocPrint(gpa, "vertices {d} {d}", .{ g.n, b.n })
                else if (a_data.edges != b_data.edges) message = try std.fmt.allocPrint(gpa, "edges {d} {d}", .{ a_data.edges, b_data.edges })
                else if (compare(a_data.degrees, b_data.degrees) != .eq) message = "degrees"
                else if (a_data.triangles != b_data.triangles) message = try std.fmt.allocPrint(gpa, "triangles {d} {d}", .{ a_data.triangles, b_data.triangles })
                else if (a_data.components != b_data.components) message = try std.fmt.allocPrint(gpa, "components {d} {d}", .{ a_data.components, b_data.components })
                else if (!equal(a_data.girth, b_data.girth)) message = try std.fmt.allocPrint(gpa, "girth {s} {s}", .{ a_data.girth, b_data.girth })
                else if (!equal(a_data.diameter, b_data.diameter)) message = try std.fmt.allocPrint(gpa, "diameter {s} {s}", .{ a_data.diameter, b_data.diameter })
                else if (a_data.bipartite != b_data.bipartite) message = try std.fmt.allocPrint(gpa, "bipartite {s} {s}", .{ yes(a_data.bipartite), yes(b_data.bipartite) })
                else {
                    const ac = try refine(gpa, g, try degreeColors(gpa, g));
                    const bc = try refine(gpa, b, try degreeColors(gpa, b));
                    if (ac.rounds != bc.rounds or compare(try cellSizes(gpa, ac.colors), try cellSizes(gpa, bc.colors)) != .eq) message = "refinement" else if (!equal((try g.canon(gpa)).text, (try b.canon(gpa)).text)) message = "canonical";
                }
                if (message) |text| try self.out.line("not isomorphic {s}", .{text}) else {
                    const a = try g.canon(gpa);
                    const other = try b.canon(gpa);
                    const reverse = try gpa.alloc(usize, b.n);
                    const mapping = try gpa.alloc(usize, g.n);
                    for (other.labels.?, 0..) |label, v| reverse[label] = v;
                    for (a.labels.?, 0..) |label, v| mapping[v] = reverse[label];
                    try self.out.add("isomorphic\n");
                    try self.out.line("mapping {s}", .{try integers(gpa, mapping)});
                }
            },
            .aut => try self.automorphisms(args[0], g), .subiso => try self.subiso(args[0], args[1], g, self.graphs.get(args[1]).?), .classify => try self.classify(number(args[0])), else => unreachable,
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    const lines = try split(gpa, text, '\n');
    const n = number(lines[0]);
    var lab: Lab = .{ .gpa = gpa, .out = .{ .gpa = gpa } };
    for (lines[1..n + 1]) |line| {
        lab.command(try split(gpa, line, ' ')) catch |err| {
            if (err != error.Invalid) return err;
            try lab.out.line("error: {s}", .{failure});
        };
    }
    try output.interface.writeAll(lab.out.result());
    try output.interface.flush();
}
