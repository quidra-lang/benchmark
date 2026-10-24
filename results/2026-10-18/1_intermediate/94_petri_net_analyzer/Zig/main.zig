const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
const Mark = [16]i64;
const Row = [32]i64;
var failure: Text = "";
fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn yes(b: bool) Text { return if (b) "yes" else "no"; }
fn bad(gpa: Allocator, comptime format: Text, args: anytype) Error { failure = std.fmt.allocPrint(gpa, format, args) catch return error.OutOfMemory; return error.Invalid; }
fn number(s: Text, low: i64, high: i64) ?i64 {
    if (s.len == 0 or s.len > 10 or s.len > 1 and s[0] == '0') return null;
    for (s) |c| if (c < '0' or c > '9') return null;
    const n = std.fmt.parseInt(i64, s, 10) catch return null;
    return if (n >= low and n <= high) n else null;
}
const Builder = struct {
    gpa: Allocator, bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, s: Text) Error!void { try self.bytes.appendSlice(self.gpa, s); }
    fn print(self: *Builder, comptime format: Text, args: anytype) Error!void { try self.add(try std.fmt.allocPrint(self.gpa, format, args)); }
    fn line(self: *Builder, comptime format: Text, args: anytype) Error!void { try self.print(format ++ "\n", args); }
};
fn split(gpa: Allocator, s: Text, separator: u8) Error![]Text { var a: std.ArrayList(Text) = .empty; var parts = std.mem.splitScalar(u8, s, separator); while (parts.next()) |part| try a.append(gpa, part); return a.items; }
fn mark(gpa: Allocator, m: Mark, p: usize) Error!Text { var out: Builder = .{ .gpa = gpa }; try out.add("("); for (m[0..p], 0..) |v, i| { if (i > 0) try out.add(","); if (v < 0) { try out.add("w"); } else try out.print("{d}", .{v}); } try out.add(")"); return out.bytes.items; }
fn gcd(x: i64, y: i64) i64 { var a = x; var b = y; while (b != 0) { const r = @rem(a, b); a = b; b = r; } return @intCast(@abs(a)); }
fn same(a: Mark, b: Mark, p: usize) bool { return std.mem.eql(i64, a[0..p], b[0..p]); }
fn rowUnique(gpa: Allocator, rows: *std.ArrayList(Row), row: Row, width: usize) Error!void { for (rows.items) |old| if (std.mem.eql(i64, row[0..width], old[0..width])) return; try rows.append(gpa, row); }
fn rowDescending(n: usize, a: Row, b: Row) bool { for (0..n) |i| if (a[i] != b[i]) return a[i] > b[i]; return false; }
const Target = struct { low: i64, high: i64 };
const Graph = struct {
    states: []Mark, parent: []i32, via: []usize, edges: [][16]i32, count: usize = 1, found: ?usize = null, aborted: bool = false,
    fn init(gpa: Allocator, start: Mark, limit: usize) Error!Graph {
        const result: Graph = .{ .states = try gpa.alloc(Mark, limit), .parent = try gpa.alloc(i32, limit), .via = try gpa.alloc(usize, limit), .edges = try gpa.alloc([16]i32, limit) };
        result.states[0] = start; result.parent[0] = -1; for (result.edges) |*row| row.* = @splat(-1); return result;
    }
};
const Net = struct {
    gpa: Allocator, name: Text, places: [16]Text = undefined, transitions: [16]Text = undefined,
    p: usize = 0, t: usize = 0, initial: Mark = @splat(0), capacity: Mark = @splat(0), priority: Mark = @splat(0), current: Mark = @splat(0),
    pre: [16]Mark = @splat(@splat(0)), post: [16]Mark = @splat(@splat(0)), inhibitor: [16]Mark = @splat(@splat(0)),
    arcs: usize = 0, inhibitors: usize = 0, history: std.ArrayList(Mark) = .empty,
    fn place(self: *const Net, s: Text) ?usize { for (self.places[0..self.p], 0..) |name, i| if (eq(name, s)) return i; return null; }
    fn transition(self: *const Net, s: Text) ?usize { for (self.transitions[0..self.t], 0..) |name, i| if (eq(name, s)) return i; return null; }
    fn define(self: *Net, scratch: Allocator, w: []const Text) Error!void {
        const cmd = w[0]; const n = w.len - 1;
        if (!eq(cmd, "place") and !eq(cmd, "transition") and !eq(cmd, "arc") and !eq(cmd, "inhibit")) return bad(scratch, "unknown definition {s}", .{cmd});
        if (!(if (eq(cmd, "place")) n == 2 or n == 3 else if (eq(cmd, "transition")) n == 1 or n == 2 else n == 3)) return bad(scratch, "wrong number of arguments", .{});
        const a = w[1];
        if (eq(cmd, "place") or eq(cmd, "transition")) {
            if (self.place(a) != null or self.transition(a) != null) return bad(scratch, "duplicate name {s}", .{a});
            if (eq(cmd, "place")) {
                const tokens = std.fmt.parseInt(i64, w[2], 10) catch unreachable; const capacity = if (n == 3) std.fmt.parseInt(i64, w[3], 10) catch unreachable else 0;
                if (n == 3 and tokens > capacity) return bad(scratch, "tokens exceed capacity of {s}", .{a});
                self.places[self.p] = a; self.initial[self.p] = tokens; self.capacity[self.p] = capacity; self.p += 1;
            } else { self.transitions[self.t] = a; self.priority[self.t] = if (n == 2) std.fmt.parseInt(i64, w[2], 10) catch unreachable else 0; self.t += 1; }
        } else if (eq(cmd, "arc")) {
            const b = w[2]; for ([_]Text{ a, b }) |x| if (self.place(x) == null and self.transition(x) == null) return bad(scratch, "unknown node {s}", .{x});
            const pa = self.place(a); const pb = self.place(b); if ((pa != null) == (pb != null)) return bad(scratch, "arc must connect a place and a transition", .{});
            const pi = pa orelse pb.?; const ti = self.transition(if (pa != null) b else a).?; const matrix = if (pa != null) &self.pre else &self.post;
            if (matrix[pi][ti] != 0) return bad(scratch, "duplicate arc {s} {s}", .{ a, b }); matrix[pi][ti] = std.fmt.parseInt(i64, w[3], 10) catch unreachable; self.arcs += 1;
        } else {
            const pi = self.place(a) orelse return bad(scratch, "unknown place {s}", .{a}); const ti = self.transition(w[2]) orelse return bad(scratch, "unknown transition {s}", .{w[2]});
            if (self.inhibitor[pi][ti] != 0) return bad(scratch, "duplicate inhibitor {s} {s}", .{ a, w[2] }); self.inhibitor[pi][ti] = std.fmt.parseInt(i64, w[3], 10) catch unreachable; self.inhibitors += 1;
        }
    }
    fn reason(self: *const Net, scratch: Allocator, m: Mark, ti: usize) Error!?Text {
        for (0..self.p) |pi| if (m[pi] >= 0 and m[pi] < self.pre[pi][ti]) return try std.fmt.allocPrint(scratch, "insufficient tokens in {s}", .{self.places[pi]});
        for (0..self.p) |pi| if (self.inhibitor[pi][ti] > 0 and (m[pi] < 0 or m[pi] >= self.inhibitor[pi][ti])) return try std.fmt.allocPrint(scratch, "inhibited by {s}", .{self.places[pi]});
        for (0..self.p) |pi| if (self.capacity[pi] > 0 and (m[pi] < 0 or m[pi] - self.pre[pi][ti] + self.post[pi][ti] > self.capacity[pi])) return try std.fmt.allocPrint(scratch, "capacity of {s} exceeded", .{self.places[pi]});
        return null;
    }
    fn enabled(self: *const Net, m: Mark, ti: usize) bool {
        for (0..self.p) |pi| if (m[pi] >= 0 and m[pi] < self.pre[pi][ti]) return false;
        for (0..self.p) |pi| if (self.inhibitor[pi][ti] > 0 and (m[pi] < 0 or m[pi] >= self.inhibitor[pi][ti])) return false;
        for (0..self.p) |pi| if (self.capacity[pi] > 0 and (m[pi] < 0 or m[pi] - self.pre[pi][ti] + self.post[pi][ti] > self.capacity[pi])) return false;
        return true;
    }
    fn fire(self: *const Net, m: Mark, ti: usize) Mark { var result = m; for (0..self.p) |pi| if (result[pi] >= 0) { result[pi] += self.post[pi][ti] - self.pre[pi][ti]; }; return result; }
    fn commit(self: *Net, ti: usize) Error!void { try self.history.append(self.gpa, self.current); self.current = self.fire(self.current, ti); }
    fn matches(self: *const Net, m: Mark, target: ?[]const Target) bool { const a = target orelse return false; for (0..self.p) |pi| if (m[pi] < a[pi].low or a[pi].high >= 0 and m[pi] != a[pi].high) return false; return true; }
    fn graph(self: *const Net, scratch: Allocator, start: Mark, limit: usize, target: ?[]const Target) Error!Graph {
        var g = try Graph.init(scratch, start, limit); if (self.matches(start, target)) { g.found = 0; return g; }
        var q: usize = 0; while (q < g.count) : (q += 1) for (0..self.t) |ti| {
            if (!self.enabled(g.states[q], ti)) continue; const m = self.fire(g.states[q], ti); var k: usize = 0;
            while (k < g.count and !same(g.states[k], m, self.p)) : (k += 1) {}
            if (k == g.count) { if (g.count == limit) { g.aborted = true; return g; } g.states[k] = m; g.parent[k] = @intCast(q); g.via[k] = ti; g.count += 1; if (self.matches(m, target)) { g.found = k; return g; } }
            g.edges[q][ti] = @intCast(k);
        };
        return g;
    }
    fn route(self: *const Net, scratch: Allocator, g: Graph, target: usize) Error![]usize { _ = self; var result: std.ArrayList(usize) = .empty; var k = target; while (g.parent[k] >= 0) { try result.append(scratch, g.via[k]); k = @intCast(g.parent[k]); } std.mem.reverse(usize, result.items); return result.items; }
    fn pathText(self: *const Net, scratch: Allocator, indices: []const usize) Error!Text { var out: Builder = .{ .gpa = scratch }; for (indices, 0..) |ti, i| { if (i > 0) try out.add(" "); try out.add(self.transitions[ti]); } return out.bytes.items; }
    fn visit(self: *const Net, scratch: Allocator, g: Graph, start: usize, reverse: bool) Error![]bool {
        const seen = try scratch.alloc(bool, g.count); @memset(seen, false); const queue = try scratch.alloc(usize, g.count); seen[start] = true; queue[0] = start; var count: usize = 1; var q: usize = 0;
        while (q < count) : (q += 1) { const u = queue[q]; if (!reverse) { for (g.edges[u][0..self.t]) |target| if (target >= 0) { const v: usize = @intCast(target); if (!seen[v]) { seen[v] = true; queue[count] = v; count += 1; } }; } else for (0..g.count) |v| for (g.edges[v][0..self.t]) |target| if (target == @as(i32, @intCast(u)) and !seen[v]) { seen[v] = true; queue[count] = v; count += 1; }; }
        return seen;
    }
    fn reach(self: *const Net, scratch: Allocator, out: *Builder, limit: usize, display: bool) Error!void {
        const g = try self.graph(scratch, self.current, limit, null); if (g.aborted) { try out.line("reachability graph limit {d} exceeded", .{limit}); return; }
        if (display) { for (0..g.count) |i| { try out.print("M{d} {s}: ", .{ i, try mark(scratch, g.states[i], self.p) }); var first = true; for (0..self.t) |ti| if (g.edges[i][ti] >= 0) { if (!first) try out.add(" "); try out.print("{s}->M{d}", .{ self.transitions[ti], g.edges[i][ti] }); first = false; }; if (first) try out.add("dead"); try out.add("\n"); } return; }
        const closure = try scratch.alloc([]bool, g.count); for (closure, 0..) |*r, i| r.* = try self.visit(scratch, g, i, false);
        const comp = try scratch.alloc(usize, g.count); @memset(comp, std.math.maxInt(usize)); var components: usize = 0;
        for (0..g.count) |i| if (comp[i] == std.math.maxInt(usize)) { for (i..g.count) |j| if (closure[i][j] and closure[j][i]) { comp[j] = components; }; components += 1; };
        const terminal = try scratch.alloc(bool, components); @memset(terminal, true); const home = try scratch.alloc(bool, g.count); @memset(home, true);
        var maximum: Mark = @splat(0); var edges: usize = 0; var dead: usize = 0; var persistent = true;
        for (0..g.count) |i| { var degree: usize = 0; for (0..self.p) |pi| maximum[pi] = @max(maximum[pi], g.states[i][pi]); for (0..g.count) |j| home[j] = home[j] and closure[i][j]; for (0..self.t) |ti| if (g.edges[i][ti] >= 0) { const k: usize = @intCast(g.edges[i][ti]); degree += 1; edges += 1; if (comp[i] != comp[k]) terminal[comp[i]] = false; for (0..self.t) |u| if (u != ti and g.edges[i][u] >= 0 and !self.enabled(g.states[k], u)) { persistent = false; }; }; if (degree == 0) dead += 1; }
        var terminals: usize = 0; var homes: usize = 0; for (terminal) |v| if (v) { terminals += 1; }; for (home) |v| if (v) { homes += 1; };
        try out.line("reachable markings: {d}\nedges: {d}\ncomponents: {d} (terminal {d})\ndead markings: {d}", .{ g.count, edges, components, terminals, dead });
        for (0..g.count) |i| { var is_dead = true; for (g.edges[i][0..self.t]) |v| if (v >= 0) { is_dead = false; }; if (is_dead) { const pth = try self.route(scratch, g, i); try out.line("  M{d} {s} path {s}", .{ i, try mark(scratch, g.states[i], self.p), if (pth.len == 0) "empty" else try self.pathText(scratch, pth) }); } }
        var bound: i64 = 0; for (maximum[0..self.p]) |v| bound = @max(bound, v);
        try out.line("max tokens: {s}\nbound: {d}\nsafe: {s}\nhome markings: {d}\nreversible: {s}\npersistent: {s}", .{ try mark(scratch, maximum, self.p), bound, yes(bound <= 1), homes, yes(home[0]), yes(persistent) });
        try out.add("liveness: "); for (0..self.t) |ti| { const present = try scratch.alloc(bool, components); @memset(present, false); var used = false; var cycle = false; for (0..g.count) |i| if (g.edges[i][ti] >= 0) { const k: usize = @intCast(g.edges[i][ti]); used = true; present[comp[i]] = true; if (comp[i] == comp[k]) cycle = true; }; var live = true; for (terminal, present) |term, have| if (term and !have) { live = false; }; try out.print("{s}{s}={s}", .{ if (ti > 0) " " else "", self.transitions[ti], if (live) "L4" else if (cycle) "L3" else if (used) "L1" else "L0" }); } try out.add("\n");
    }
    fn cover(self: *const Net, scratch: Allocator, out: *Builder, limit: usize) Error!void {
        var g = try Graph.init(scratch, self.current, limit); const old = try scratch.alloc(bool, limit); @memset(old, false); const dead = try scratch.alloc(bool, limit); @memset(dead, false); const ancestors = try scratch.alloc(usize, limit);
        var q: usize = 0; while (q < g.count) : (q += 1) { if (old[q]) continue; var count: usize = 0; var a: i32 = @intCast(q); while (a >= 0) { ancestors[count] = @intCast(a); count += 1; a = g.parent[@intCast(a)]; } var degree: usize = 0;
            for (0..self.t) |ti| { if (!self.enabled(g.states[q], ti)) continue; degree += 1; var m = self.fire(g.states[q], ti); var j = count; while (j > 0) { j -= 1; const ancestor = ancestors[j]; var ge = true; var gt = false; for (0..self.p) |pi| { ge = ge and rank(m[pi]) >= rank(g.states[ancestor][pi]); gt = gt or rank(m[pi]) > rank(g.states[ancestor][pi]); } if (ge and gt) for (0..self.p) |pi| if (self.capacity[pi] == 0 and rank(m[pi]) > rank(g.states[ancestor][pi])) { m[pi] = -1; }; }
                if (g.count == limit) { try out.line("coverability tree limit {d} exceeded", .{limit}); return; } const k = g.count; for (g.states[0..k]) |state| if (same(state, m, self.p)) { old[k] = true; break; }; g.states[k] = m; g.parent[k] = @intCast(q); g.via[k] = ti; g.count += 1;
            } dead[q] = degree == 0;
        }
        try out.line("coverability tree nodes: {d}", .{g.count}); var maximum: Mark = @splat(0);
        for (0..g.count) |i| { try out.print("  {d} {s} ", .{ i, try mark(scratch, g.states[i], self.p) }); if (i == 0) { try out.add("root"); } else try out.print("<- {d} {s}", .{ g.parent[i], self.transitions[g.via[i]] }); if (old[i]) try out.add(" old"); if (dead[i]) try out.add(" dead"); try out.add("\n"); for (0..self.p) |pi| if (rank(g.states[i][pi]) > rank(maximum[pi])) { maximum[pi] = g.states[i][pi]; }; }
        try out.line("bounds: {s}", .{try mark(scratch, maximum, self.p)}); try out.add("unbounded: "); var first = true; for (0..self.p) |pi| if (maximum[pi] < 0) { if (!first) try out.add(" "); try out.add(self.places[pi]); first = false; }; if (first) try out.add("none"); try out.add("\n");
    }
    fn setText(self: *const Net, scratch: Allocator, mask: u32) Error!Text { var out: Builder = .{ .gpa = scratch }; try out.add("{"); var first = true; for (0..self.p) |pi| if (mask & (@as(u32, 1) << @intCast(pi)) != 0) { if (!first) try out.add(","); try out.add(self.places[pi]); first = false; }; try out.add("}"); return out.bytes.items; }
    fn sets(self: *const Net, scratch: Allocator, trap: bool) Error![]u32 {
        const limit = @as(u32, 1) << @intCast(self.p); const valid = try scratch.alloc(bool, limit); @memset(valid, false);
        var mask: u32 = 1; while (mask < limit) : (mask += 1) { valid[mask] = true; for (0..self.t) |ti| { var input = false; var output = false; for (0..self.p) |pi| if (mask & (@as(u32, 1) << @intCast(pi)) != 0) { input = input or self.post[pi][ti] > 0; output = output or self.pre[pi][ti] > 0; }; if (if (trap) output and !input else input and !output) { valid[mask] = false; break; } } }
        var result: std.ArrayList(u32) = .empty; mask = 1; while (mask < limit) : (mask += 1) { if (!valid[mask]) continue; var minimal = true; var sub = (mask - 1) & mask; while (sub > 0) : (sub = (sub - 1) & mask) if (valid[sub]) { minimal = false; break; }; if (minimal) try result.append(scratch, mask); }
        std.mem.sort(u32, result.items, {}, setLess); return result.items;
    }
    fn flows(self: *const Net, scratch: Allocator, transpose: bool) Error![]Row {
        const n = if (transpose) self.t else self.p; const m = if (transpose) self.p else self.t; var rows: std.ArrayList(Row) = .empty;
        for (0..n) |i| { var row: Row = @splat(0); for (0..m) |j| row[j] = if (transpose) self.post[j][i] - self.pre[j][i] else self.post[i][j] - self.pre[i][j]; row[m + i] = 1; try rows.append(scratch, row); }
        for (0..m) |j| { var collected: std.ArrayList(Row) = .empty; for (rows.items) |r| if (r[j] == 0) try rowUnique(scratch, &collected, r, m + n);
            for (rows.items) |r| if (r[j] > 0) { for (rows.items) |s| if (s[j] < 0) { var row: Row = @splat(0); var divisor: i64 = 0; for (0..m + n) |k| { row[k] = -s[j] * r[k] + r[j] * s[k]; divisor = gcd(divisor, row[k]); } for (0..m + n) |k| row[k] = @divTrunc(row[k], divisor); try rowUnique(scratch, &collected, row, m + n); }; };
            const supports = try scratch.alloc(u32, collected.items.len); @memset(supports, 0); for (collected.items, 0..) |r, i| for (0..n) |k| if (r[m + k] > 0) { supports[i] |= @as(u32, 1) << @intCast(k); };
            rows = .empty; for (collected.items, 0..) |r, i| { var minimal = true; for (supports) |s| if (s != supports[i] and s & supports[i] == s) { minimal = false; break; }; if (minimal) try rows.append(scratch, r); }
        }
        for (rows.items) |*row| { var coefficients: Row = @splat(0); for (0..n) |i| coefficients[i] = row[m + i]; row.* = coefficients; } std.mem.sort(Row, rows.items, n, rowDescending); return rows.items;
    }
    fn realize(self: *const Net, scratch: Allocator, counts: Row) Error!?[]usize {
        var total: usize = 0; var space: usize = 1; for (counts[0..self.t]) |c| { total += @intCast(c); space *= @as(usize, @intCast(c)) + 1; }
        const stack = try scratch.alloc(Mark, total + 1); stack[0] = self.current; const choices = try scratch.alloc(usize, total + 1); @memset(choices, 0); const path = try scratch.alloc(usize, total); const seen = try scratch.alloc(bool, space); @memset(seen, false); var used: Mark = @splat(0); var depth: usize = 0;
        while (true) { if (depth == total) return path; var chosen: ?usize = null; var ti = choices[depth]; while (ti < self.t) : (ti += 1) { choices[depth] = ti + 1; if (used[ti] >= counts[ti] or !self.enabled(stack[depth], ti)) continue; used[ti] += 1; var index: usize = 0; var factor: usize = 1; for (0..self.t) |u| { index += @as(usize, @intCast(used[u])) * factor; factor *= @as(usize, @intCast(counts[u])) + 1; } used[ti] -= 1; if (seen[index]) continue; seen[index] = true; chosen = ti; break; }
            if (chosen) |selected| { used[selected] += 1; path[depth] = selected; stack[depth + 1] = self.fire(stack[depth], selected); depth += 1; choices[depth] = 0; } else { if (depth == 0) return null; depth -= 1; used[path[depth]] -= 1; }
        }
    }
    fn invariants(self: *const Net, scratch: Allocator, out: *Builder, transpose: bool) Error!void {
        const f = try self.flows(scratch, transpose); const n = if (transpose) self.t else self.p; var covered = [_]bool{false} ** 16; var bounds: Mark = @splat(-1); try out.line("{s}-semiflows: {d}", .{ if (transpose) "T" else "P", f.len });
        for (f) |c| { try out.add("  "); var first = true; var value: i64 = 0; for (0..n) |i| if (c[i] > 0) { covered[i] = true; if (!first) try out.add(" + "); if (c[i] != 1) try out.print("{d}*", .{c[i]}); try out.add(if (transpose) self.transitions[i] else self.places[i]); first = false; if (!transpose) value += c[i] * self.current[i]; };
            if (transpose) { if (try self.realize(scratch, c)) |path| { try out.line(": realizable {s}", .{try self.pathText(scratch, path)}); } else try out.line(": not realizable", .{}); } else { try out.line(" = {d}", .{value}); for (0..n) |i| if (c[i] > 0) { const bound = @divTrunc(value, c[i]); if (bounds[i] < 0 or bound < bounds[i]) bounds[i] = bound; }; }
        }
        if (!transpose) { try out.add("bounds: ("); for (bounds[0..n], 0..) |b, i| { if (i > 0) try out.add(","); if (b < 0) { try out.add("-"); } else try out.print("{d}", .{b}); } try out.add(")\n"); }
        var all = true; for (covered[0..n]) |v| all = all and v; try out.line("{s}: {s}", .{ if (transpose) "consistent" else "conservative", yes(all) });
    }
    fn classify(self: *const Net, scratch: Allocator, out: *Builder) Error!void {
        var inputs = [_]u32{0} ** 16; var outputs = inputs; var ordinary = true; var pure = true; var sm = true; var mg = true; var fc = true; var efc = true;
        for (0..self.p) |pi| for (0..self.t) |ti| { ordinary = ordinary and self.pre[pi][ti] <= 1 and self.post[pi][ti] <= 1; pure = pure and !(self.pre[pi][ti] > 0 and self.post[pi][ti] > 0); if (self.pre[pi][ti] > 0) { inputs[ti] |= @as(u32, 1) << @intCast(pi); outputs[pi] |= @as(u32, 1) << @intCast(ti); } };
        for (0..self.t) |ti| { var count: usize = 0; for (0..self.p) |pi| if (self.post[pi][ti] > 0) { count += 1; }; sm = sm and @popCount(inputs[ti]) == 1 and count == 1; }
        for (0..self.p) |pi| { var count: usize = 0; for (0..self.t) |ti| { if (self.post[pi][ti] > 0) count += 1; if (self.pre[pi][ti] > 0 and @popCount(outputs[pi]) != 1 and @popCount(inputs[ti]) != 1) fc = false; } mg = mg and @popCount(outputs[pi]) == 1 and count == 1; for (0..self.p) |q| if (outputs[pi] & outputs[q] != 0 and outputs[pi] != outputs[q]) { efc = false; }; }
        sm = sm and ordinary; mg = mg and ordinary; fc = fc and ordinary; efc = efc and ordinary;
        const labels = [_]Text{ "ordinary", "pure", "state machine", "marked graph", "free choice", "extended free choice" }; const values = [_]bool{ ordinary, pure, sm, mg, fc, efc }; for (labels, values) |label, value| try out.line("{s}: {s}", .{ label, yes(value) });
        try out.add("commoner: "); if (!fc) { try out.line("not applicable", .{}); return; } if (self.p > 12) { try out.line("too many places", .{}); return; }
        const traps = try self.sets(scratch, true); for (try self.sets(scratch, false)) |s| { var holds = false; for (traps) |q| if (s & q == q) { for (0..self.p) |pi| if (q & (@as(u32, 1) << @intCast(pi)) != 0 and self.current[pi] > 0) { holds = true; }; }; if (!holds) { try out.line("fails at {s}", .{try self.setText(scratch, s)}); return; } } try out.line("holds", .{});
    }
    fn workflow(self: *const Net, scratch: Allocator, out: *Builder, limit: usize) Error!void {
        var sources: [16]usize = undefined; var sinks: [16]usize = undefined; var ns: usize = 0; var nt: usize = 0;
        for (0..self.p) |pi| { var input = false; var output = false; for (0..self.t) |ti| { input = input or self.post[pi][ti] > 0; output = output or self.pre[pi][ti] > 0; } if (!input) { sources[ns] = pi; ns += 1; } if (!output) { sinks[nt] = pi; nt += 1; } }
        if (ns != 1) { try out.line("workflow: no ({d} source places)", .{ns}); return; } if (nt != 1) { try out.line("workflow: no ({d} sink places)", .{nt}); return; } const i = sources[0]; const o = sinks[0];
        var adj = [_][32]bool{@splat(false)} ** 32; for (0..self.p) |pi| for (0..self.t) |ti| { adj[pi][self.p + ti] = self.pre[pi][ti] > 0; adj[self.p + ti][pi] = self.post[pi][ti] > 0; };
        const forward = structuralVisit(adj, self.p + self.t, i, false); const back = structuralVisit(adj, self.p + self.t, o, true);
        for (0..self.p + self.t) |v| if (!forward[v] or !back[v]) { try out.line("workflow: no ({s} is not on a path from {s} to {s})", .{ if (v < self.p) self.places[v] else self.transitions[v - self.p], self.places[i], self.places[o] }); return; };
        try out.line("workflow: source {s} sink {s}", .{ self.places[i], self.places[o] }); var start: Mark = @splat(0); var goal: Mark = @splat(0); start[i] = 1; goal[o] = 1; const g = try self.graph(scratch, start, limit, null);
        if (g.aborted) { try out.line("reachability graph limit {d} exceeded", .{limit}); return; } var finish: ?usize = null; var proper = true; var used = [_]bool{false} ** 16;
        for (0..g.count) |u| { if (same(g.states[u], goal, self.p)) finish = u; if (g.states[u][o] >= 1 and !same(g.states[u], goal, self.p)) proper = false; for (0..self.t) |ti| if (g.edges[u][ti] >= 0) { used[ti] = true; }; }
        var option = false; if (finish) |end| { option = true; for (try self.visit(scratch, g, end, true)) |v| option = option and v; } var live = true; for (used[0..self.t]) |v| live = live and v;
        try out.line("option to complete: {s}\nproper completion: {s}\nno dead transitions: {s}\nsound: {s}", .{ yes(option), yes(proper), yes(live), yes(option and proper and live) });
    }
    fn arcList(self: *const Net, scratch: Allocator, matrix: [16]Mark, ti: usize) Error!Text { var out: Builder = .{ .gpa = scratch }; var first = true; for (0..self.p) |pi| if (matrix[pi][ti] > 0) { if (!first) try out.add(","); try out.print("{s}:{d}", .{ self.places[pi], matrix[pi][ti] }); first = false; }; if (first) try out.add("-"); return out.bytes.items; }
    fn execute(self: *Net, scratch: Allocator, out: *Builder, w: []const Text) Error!void {
        const commands = [_]Text{ "MARKING", "RESET", "SET", "ENABLED", "FIRE", "UNDO", "SIMULATE", "CONFLICTS", "REACH", "GRAPH", "COVER", "PATH", "INCIDENCE", "PINV", "TINV", "SIPHONS", "TRAPS", "CLASSIFY", "WORKFLOW", "SHOW" }; const arity = [_]i32{ 0, 0, 2, 0, -1, 1, 3, 0, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 1, 0 };
        var cmd: usize = 0; while (cmd < commands.len and !eq(w[0], commands[cmd])) : (cmd += 1) {} if (cmd == commands.len) return bad(scratch, "unknown command {s}", .{w[0]}); if (if (arity[cmd] < 0) w.len < 2 else w.len != @as(usize, @intCast(arity[cmd])) + 1) return bad(scratch, "wrong number of arguments", .{});
        var limit: usize = 0; if (cmd == 8 or cmd == 9 or cmd == 10 or cmd == 11 or cmd == 18) limit = @intCast(number(w[1], 1, 2000) orelse return bad(scratch, "invalid limit {s}", .{w[1]}));
        switch (cmd) {
            0, 1 => { if (cmd == 1) { self.current = self.initial; self.history.clearRetainingCapacity(); } try out.line("marking {s}", .{try mark(scratch, self.current, self.p)}); },
            2 => { const pi = self.place(w[1]) orelse return bad(scratch, "unknown place {s}", .{w[1]}); const value = number(w[2], 0, 999) orelse return bad(scratch, "invalid tokens {s}", .{w[2]}); if (self.capacity[pi] > 0 and value > self.capacity[pi]) return bad(scratch, "tokens exceed capacity of {s}", .{w[1]}); self.current[pi] = value; self.history.clearRetainingCapacity(); try out.line("marking {s}", .{try mark(scratch, self.current, self.p)}); },
            3 => { try out.add("enabled: "); var first = true; for (0..self.t) |ti| if (self.enabled(self.current, ti)) { if (!first) try out.add(" "); try out.add(self.transitions[ti]); first = false; }; if (first) try out.add("none"); try out.add("\n"); },
            4 => { const sequence = try scratch.alloc(usize, w.len - 1); for (w[1..], sequence) |name, *ti| ti.* = self.transition(name) orelse return bad(scratch, "unknown transition {s}", .{name}); for (sequence, 0..) |ti, step| { if (try self.reason(scratch, self.current, ti)) |failure_reason| { try out.line("step {d}: {s} not enabled ({s}) at {s}", .{ step + 1, self.transitions[ti], failure_reason, try mark(scratch, self.current, self.p) }); return; } try self.commit(ti); } try out.line("fired {d} -> {s}", .{ sequence.len, try mark(scratch, self.current, self.p) }); },
            5 => { const k: usize = @intCast(number(w[1], 1, 1000) orelse return bad(scratch, "invalid count {s}", .{w[1]})); if (k > self.history.items.len) return bad(scratch, "cannot undo {d}: history size {d}", .{ k, self.history.items.len }); self.current = self.history.items[self.history.items.len - k]; self.history.shrinkRetainingCapacity(self.history.items.len - k); try out.line("marking {s}", .{try mark(scratch, self.current, self.p)}); },
            6 => { const steps: usize = @intCast(number(w[1], 1, 1000) orelse return bad(scratch, "invalid steps {s}", .{w[1]})); var random = number(w[2], 1, 2147483646) orelse return bad(scratch, "invalid seed {s}", .{w[2]}); if (!eq(w[3], "PRIORITY") and !eq(w[3], "RANDOM")) return bad(scratch, "invalid mode {s}", .{w[3]}); var counts = [_]usize{0} ** 16; var done: usize = 0;
                while (done < steps) : (done += 1) { var available: [16]usize = undefined; var count: usize = 0; for (0..self.t) |ti| if (self.enabled(self.current, ti)) { available[count] = ti; count += 1; }; if (count == 0) { try out.line("dead (steps={d})", .{done}); break; } var selected = available[0]; if (eq(w[3], "RANDOM")) { random = @mod(random * 48271, 2147483647); selected = available[@intCast(@mod(random, @as(i64, @intCast(count))))]; } else for (available[0..count]) |u| if (self.priority[u] > self.priority[selected]) { selected = u; }; try self.commit(selected); counts[selected] += 1; try out.line("step {d}: {s} -> {s}", .{ done + 1, self.transitions[selected], try mark(scratch, self.current, self.p) }); }
                if (done == steps) try out.line("completed (steps={d})", .{steps}); try out.add("counts: "); for (0..self.t) |ti| try out.print("{s}{s}={d}", .{ if (ti > 0) " " else "", self.transitions[ti], counts[ti] }); try out.add("\n"); },
            7 => { for (0..2) |mode| { try out.print("{s}: ", .{if (mode == 0) "structural" else "effective"}); var first = true; for (0..self.t) |u| for (u + 1..self.t) |v| { var conflict = false; if (mode == 0) { for (0..self.p) |pi| conflict = conflict or self.pre[pi][u] > 0 and self.pre[pi][v] > 0; } else conflict = self.enabled(self.current, u) and self.enabled(self.current, v) and (!self.enabled(self.fire(self.current, u), v) or !self.enabled(self.fire(self.current, v), u)); if (conflict) { if (!first) try out.add(" "); try out.print("{s}/{s}", .{ self.transitions[u], self.transitions[v] }); first = false; } }; if (first) try out.add("none"); try out.add("\n"); } },
            8, 9 => try self.reach(scratch, out, limit, cmd == 9), 10 => try self.cover(scratch, out, limit),
            11 => { const entries = try split(scratch, w[2], ','); if (entries.len != self.p) return bad(scratch, "target needs {d} entries", .{self.p}); const targets = try scratch.alloc(Target, self.p); for (entries, targets) |text, *target| { if (eq(text, "*")) { target.* = .{ .low = 0, .high = -1 }; continue; } const plus = std.mem.endsWith(u8, text, "+"); const value = number(if (plus) text[0 .. text.len - 1] else text, 0, 9999999999) orelse return bad(scratch, "invalid target entry {s}", .{text}); target.* = .{ .low = value, .high = if (plus) -1 else value }; } const g = try self.graph(scratch, self.current, limit, targets); if (g.found) |k| { const pth = try self.route(scratch, g, k); try out.print("reached {s} length={d}", .{ try mark(scratch, g.states[k], self.p), pth.len }); if (pth.len > 0) try out.print(": {s}", .{try self.pathText(scratch, pth)}); try out.add("\n"); } else if (g.aborted) { try out.line("search limit {d} exceeded", .{limit}); } else try out.line("unreachable (markings explored: {d})", .{g.count}); },
            12 => { var rows: [17][17]Text = undefined; rows[0][0] = ""; for (0..self.t) |ti| rows[0][ti + 1] = self.transitions[ti]; for (0..self.p) |pi| { rows[pi + 1][0] = self.places[pi]; for (0..self.t) |ti| rows[pi + 1][ti + 1] = try std.fmt.allocPrint(scratch, "{d}", .{self.post[pi][ti] - self.pre[pi][ti]}); } var widths = [_]usize{0} ** 17; for (rows[0 .. self.p + 1]) |r| for (r[0 .. self.t + 1], 0..) |cell, c| { widths[c] = @max(widths[c], cell.len); }; for (rows[0 .. self.p + 1]) |r| { for (r[0 .. self.t + 1], 0..) |cell, c| { if (c > 0) { try out.add("  "); for (0..widths[c] - cell.len) |_| try out.add(" "); } try out.add(cell); if (c == 0) for (0..widths[0] - cell.len) |_| try out.add(" "); } try out.add("\n"); } },
            13, 14 => try self.invariants(scratch, out, cmd == 14),
            15, 16 => { if (self.p > 12) return bad(scratch, "more than 12 places", .{}); const values = try self.sets(scratch, cmd == 16); try out.line("minimal {s}: {d}", .{ if (cmd == 16) "traps" else "siphons", values.len }); for (values) |mask| { var tokens: i64 = 0; for (0..self.p) |pi| if (mask & (@as(u32, 1) << @intCast(pi)) != 0) { tokens += self.current[pi]; }; try out.line("  {s} tokens={d}", .{ try self.setText(scratch, mask), tokens }); } },
            17 => try self.classify(scratch, out), 18 => try self.workflow(scratch, out, limit),
            19 => { for (0..self.p) |pi| try out.line("place {s} tokens={d} capacity={s}", .{ self.places[pi], self.initial[pi], if (self.capacity[pi] == 0) "none" else try std.fmt.allocPrint(scratch, "{d}", .{self.capacity[pi]}) }); for (0..self.t) |ti| try out.line("transition {s} priority={d} pre={s} post={s} inhibit={s}", .{ self.transitions[ti], self.priority[ti], try self.arcList(scratch, self.pre, ti), try self.arcList(scratch, self.post, ti), try self.arcList(scratch, self.inhibitor, ti) }); },
            else => unreachable,
        }
    }
};
fn rank(v: i64) i64 { return if (v < 0) std.math.maxInt(i64) else v; }
fn setLess(_: void, a: u32, b: u32) bool { const x = @popCount(a); const y = @popCount(b); if (x != y) return x < y; for (0..16) |i| { const bit = @as(u32, 1) << @intCast(i); if (a & bit != b & bit) return a & bit != 0; } return false; }
fn structuralVisit(adj: [32][32]bool, n: usize, start: usize, reverse: bool) [32]bool { var seen = [_]bool{false} ** 32; var queue: [32]usize = undefined; seen[start] = true; queue[0] = start; var count: usize = 1; var i: usize = 0; while (i < count) : (i += 1) for (0..n) |v| if ((if (reverse) adj[v][queue[i]] else adj[queue[i]][v]) and !seen[v]) { seen[v] = true; queue[count] = v; count += 1; }; return seen; }
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit(); const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined; var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer); const source = try input.interface.allocRemaining(gpa, .unlimited); var lines = std.mem.splitScalar(u8, source, '\n');
    const blocks = try std.fmt.parseInt(usize, std.mem.trimEnd(u8, lines.next().?, "\r"), 10);
    var output_buffer: [8192]u8 = undefined; var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    for (0..blocks) |_| {
        const header = try split(gpa, std.mem.trimEnd(u8, lines.next().?, "\r"), ' '); var net: Net = .{ .gpa = gpa, .name = header[1] };
        while (true) { const line = std.mem.trimEnd(u8, lines.next().?, "\r"); if (eq(line, "END NET")) break; net.define(gpa, try split(gpa, line, ' ')) catch |err| { if (err != error.Invalid) return err; try output.interface.writeAll(try std.fmt.allocPrint(gpa, "error: {s}\n", .{failure})); }; }
        net.current = net.initial; try output.interface.writeAll(try std.fmt.allocPrint(gpa, "net {s}: places={d} transitions={d} arcs={d} inhibitors={d}\n", .{ net.name, net.p, net.t, net.arcs, net.inhibitors }));
        const count = try std.fmt.parseInt(usize, std.mem.trimEnd(u8, lines.next().?, "\r"), 10);
        for (0..count) |_| { var command_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer command_arena.deinit(); const scratch = command_arena.allocator(); var out: Builder = .{ .gpa = scratch }; const line = std.mem.trimEnd(u8, lines.next().?, "\r"); net.execute(scratch, &out, try split(scratch, line, ' ')) catch |err| { if (err != error.Invalid) return err; out.bytes.clearRetainingCapacity(); try out.line("error: {s}", .{failure}); }; try output.interface.writeAll(out.bytes.items); }
    }
    try output.interface.flush();
}
