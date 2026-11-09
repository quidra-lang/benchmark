const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, n: usize) []T { return allocator.alloc(T, n) catch @panic("allocation failed"); }
pub fn zero(comptime T: type, n: usize, value: T) []T { const a = alloc(T, n); @memset(a, value); return a; }
pub fn copy(comptime T: type, a: []const T) []T { return allocator.dupe(T, a) catch @panic("allocation failed"); }
pub fn append(comptime T: type, a: *std.ArrayList(T), v: T) void { a.append(allocator, v) catch @panic("allocation failed"); }
pub fn fmt(comptime s: []const u8, a: anytype) []const u8 { return std.fmt.allocPrint(allocator, s, a) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub const Text = struct { data: std.ArrayList(u8) = .empty, pub fn put(self: *Text, comptime s: []const u8, a: anytype) void { self.data.appendSlice(allocator, fmt(s, a)) catch @panic("allocation failed"); } pub fn line(self: *Text, comptime s: []const u8, a: anytype) void { self.put(s, a); self.put("\n", .{}); } };
pub fn words(s: []const u8) []const []const u8 { var a: std.ArrayList([]const u8) = .empty; var it = std.mem.tokenizeScalar(u8, s, ' '); while (it.next()) |w| append([]const u8, &a, w); return a.items; }
pub fn number(s: []const u8) usize { return std.fmt.parseInt(usize, s, 10) catch unreachable; }
pub const Settings = struct {
    layering: []const u8 = "longest", width: usize = 4, promotion: bool = false, heuristic: []const u8 = "barycenter", sweeps: usize = 12, node_sep: i64 = 2, dummy_sep: i64 = 1, layer_gap: i64 = 3, direction: []const u8 = "TB", sifting: bool = false, reduce: bool = false, restarts: usize = 0, seed: i64 = 1,
    pub fn vertical(self: Settings) bool { return eq(self.direction, "TB") or eq(self.direction, "BT"); }
    pub fn display(self: Settings, text: *Text) void { text.line("settings layering={s} width={d} promotion={s} heuristic={s} sweeps={d} node_sep={d} dummy_sep={d} layer_gap={d} direction={s} sifting={s} reduce={s} restarts={d} seed={d}", .{self.layering, self.width, if (self.promotion) "on" else "off", self.heuristic, self.sweeps, self.node_sep, self.dummy_sep, self.layer_gap, self.direction, if (self.sifting) "on" else "off", if (self.reduce) "on" else "off", self.restarts, self.seed}); }
};
pub fn option(s: *Settings, name: []const u8, value: []const u8) bool {
    if (eq(name, "layering") or eq(name, "heuristic") or eq(name, "direction") or eq(name, "promotion") or eq(name, "sifting") or eq(name, "reduce")) {
        if (eq(name, "layering")) { if (!eq(value, "longest") and !eq(value, "coffman")) return false; s.layering = value; }
        else if (eq(name, "heuristic")) { if (!eq(value, "barycenter") and !eq(value, "median")) return false; s.heuristic = value; }
        else if (eq(name, "direction")) { if (!eq(value, "TB") and !eq(value, "BT") and !eq(value, "LR") and !eq(value, "RL")) return false; s.direction = value; }
        else { if (!eq(value, "on") and !eq(value, "off")) return false; const flag = eq(value, "on"); if (eq(name, "promotion")) s.promotion = flag else if (eq(name, "sifting")) s.sifting = flag else s.reduce = flag; } return true;
    }
    if (value.len == 0 or value.len > 10) return false; for (value) |c| if (!std.ascii.isDigit(c)) return false;
    const n = std.fmt.parseInt(i64, value, 10) catch return false;
    if (eq(name, "width")) { if (n < 1 or n > 40) return false; s.width = @intCast(n); }
    else if (eq(name, "sweeps")) { if (n > 50) return false; s.sweeps = @intCast(n); }
    else if (eq(name, "node_sep") or eq(name, "dummy_sep")) { if (n < 1 or n > 9) return false; if (eq(name, "node_sep")) s.node_sep = n else s.dummy_sep = n; }
    else if (eq(name, "layer_gap")) { if (n < 2 or n > 9) return false; s.layer_gap = n; }
    else if (eq(name, "restarts")) { if (n > 9) return false; s.restarts = @intCast(n); }
    else if (eq(name, "seed")) { if (n < 1 or n > 2147483646) return false; s.seed = n; }
    else return false; return true;
}
pub const Point = struct { row: i64, column: i64 };
pub const Vertex = struct { name: []const u8, label: []const u8, id: usize = 0, layer: usize = 0, dummy: bool = false, width: i64 = 1, left: i64 = 0, right: i64 = 0 };
pub const Edge = struct { from: usize, to: usize, a: usize = 0, b: usize = 0, reversed: bool = false, transitive: bool = false, chain: []const usize = &.{}, route: []const Point = &.{}, crossings: usize = 0, bends: usize = 0, length: usize = 0 };
pub const Segment = struct { upper: usize, lower: usize, edge: usize, marked: bool = false, track: i64 = 0 };
pub const Graph = struct { name: []const u8, settings: Settings, vertices: std.ArrayList(Vertex) = .empty, edges: std.ArrayList(Edge) = .empty, segments: std.ArrayList(Segment) = .empty, nodes: usize = 0, error_kind: ?[]const u8 = null, error_line: usize = 0, loops: usize = 0, duplicates: usize = 0, path: ?[2]usize = null,
    pub fn fail(self: *Graph, kind: []const u8, line: usize) void { self.error_kind = kind; self.error_line = line; }
};
pub fn read(io: std.Io, path: []const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited); }
pub fn write(io: std.Io, name: []const u8, text: Text) !void { try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.data.items }); }
fn find(g: Graph, id: usize) ?usize { for (g.vertices.items, 0..) |v, i| if (v.id == id) return i; return null; }
pub fn parse(params: []const u8, text: []const u8) []Graph {
    var defaults: Settings = .{}; var lines = std.mem.splitScalar(u8, params, '\n'); while (lines.next()) |line| { if (line.len == 0 or line[0] == '#') continue; const w = words(line); _ = option(&defaults, w[0], w[1]); }
    var graphs: std.ArrayList(Graph) = .empty; lines = std.mem.splitScalar(u8, text, '\n'); var line_number: usize = 0; var g: Graph = undefined;
    while (lines.next()) |line| {
        line_number += 1; if (line.len == 0 or line[0] == '#') continue; const w = words(line);
        if (eq(w[0], "GRAPH")) { g = .{ .name = w[1], .settings = defaults }; continue; }
        if (eq(w[0], "END")) {
            if (g.error_kind == null and g.vertices.items.len == 0) g.fail("no_nodes", line_number);
            if (g.error_kind == null) {
                const ids = alloc(usize, g.vertices.items.len); for (g.vertices.items, ids) |v, *id| id.* = v.id;
                std.mem.sort(Vertex, g.vertices.items, {}, struct { fn less(_: void, a: Vertex, b: Vertex) bool { return a.id < b.id; } }.less);
                for (g.edges.items) |*e| { e.from = find(g, ids[e.from]).?; e.to = find(g, ids[e.to]).?; }
                if (g.path) |path| g.path = .{find(g, ids[path[0]]).?, find(g, ids[path[1]]).?}; g.nodes = g.vertices.items.len;
                for (g.vertices.items) |*v| { v.width = @intCast(v.label.len + 2); if (g.settings.vertical()) { v.left = @divFloor(v.width - 1, 2); v.right = v.width - 1 - v.left; } }
            }
            append(Graph, &graphs, g); continue;
        }
        if (g.error_kind != null) continue;
        if (eq(w[0], "OPTION")) { if (!option(&g.settings, w[1], w[2])) g.fail("bad_option", line_number); }
        else if (eq(w[0], "NODE")) { const id = number(w[1]); if (find(g, id) != null) g.fail("duplicate_node", line_number) else if (g.vertices.items.len == 40) g.fail("too_many_nodes", line_number) else append(Vertex, &g.vertices, .{ .name = w[1], .label = w[2], .id = id }); }
        else { const a = find(g, number(w[1])); const c = find(g, number(w[2])); if (a == null or c == null) { g.fail("unknown_node", line_number); continue; }
            if (eq(w[0], "PATH")) { g.path = .{a.?, c.?}; continue; }
            if (a.? == c.?) { g.loops += 1; continue; }
            var duplicate = false; for (g.edges.items) |e| if (e.from == a.? and e.to == c.?) { duplicate = true; break; };
            if (duplicate) g.duplicates += 1 else append(Edge, &g.edges, .{ .from = a.?, .to = c.? });
        }
    }
    return graphs.items;
}
