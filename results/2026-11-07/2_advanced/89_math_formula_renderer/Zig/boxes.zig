const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, n: usize) []T { return allocator.alloc(T, n) catch @panic("allocation failed"); }
pub fn create(comptime T: type, value: T) *T { const p = allocator.create(T) catch @panic("allocation failed"); p.* = value; return p; }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime s: []const u8, a: anytype) []const u8 { return std.fmt.allocPrint(allocator, s, a) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn repeat(c: u8, n: i64) []const u8 { const a = alloc(u8, @intCast(n)); @memset(a, c); return a; }
pub const Text = struct { data: std.ArrayList(u8) = .empty,
    pub fn put(self: *Text, comptime s: []const u8, a: anytype) void { self.data.appendSlice(allocator, fmt(s, a)) catch @panic("allocation failed"); }
    pub fn line(self: *Text, comptime s: []const u8, a: anytype) void { self.put(s, a); self.put("\n", .{}); }
};
pub const Type = enum { ordinary, operator, binary, relation, open, close, punctuation };
pub const Symbol = struct { name: []const u8, display: []const u8, typ: Type = .ordinary, word: bool = false, large: bool = false };
pub const greek = [_][]const u8{ "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega" };
pub fn symbol(name: []const u8) ?Symbol {
    for (greek) |g| if (eq(name, g)) return .{ .name = g, .display = g, .word = true };
    const names = [_][]const u8{ "cdot", "times", "pm", "mp", "leq", "geq", "neq", "approx", "to", "infty", "ldots", "cdots", "quad", ",", "{", "}" };
    const displays = [_][]const u8{ "*", "x", "+-", "-+", "<=", ">=", "!=", "~=", "->", "oo", "...", "...", "  ", " ", "{", "}" };
    for (names, displays, 0..) |n, display, i| if (eq(name, n)) return .{ .name = n, .display = display, .typ = if (i < 4) .binary else if (i < 9) .relation else if (i == 14) .open else if (i == 15) .close else .ordinary, .word = i == 9 };
    for ([_][]const u8{ "sin", "cos", "tan", "log", "ln", "exp", "det", "lim", "max", "min", "sum", "prod", "int" }, 0..) |n, i| if (eq(name, n)) return .{ .name = n, .display = n, .typ = .operator, .large = i >= 10 };
    return null;
}
pub const Placement = struct { box: *Box, x: i64, y: i64, role: []const u8 = "" };
pub const Stroke = struct { value: []const u8, x: i64, y: i64 };
pub const Box = struct {
    w: i64, h: i64 = 1, baseline: i64 = 0, description: []const u8,
    children: std.ArrayList(Placement) = .empty, strokes: std.ArrayList(Stroke) = .empty,
    pub fn place(self: *Box, child: *Box, x: i64, y: i64, role: []const u8) void { append(Placement, &self.children, .{ .box = child, .x = x, .y = y, .role = role }); }
    pub fn draw(self: *Box, s: []const u8, x: i64, y: i64) void { append(Stroke, &self.strokes, .{ .value = s, .x = x, .y = y }); }
};
pub fn box(description: []const u8, w: i64, h: i64, baseline: i64) *Box { return create(Box, .{ .description = description, .w = w, .h = h, .baseline = baseline }); }
pub fn atom(description: []const u8, value: []const u8) *Box { const out = box(description, @intCast(value.len), 1, 0); out.draw(value, 0, 0); return out; }
pub fn glyph(out: *Box, delimiter: []const u8, x: i64, height: i64) void {
    if (eq(delimiter, ".")) return;
    var i: i64 = 0; while (i < height) : (i += 1) {
        var c: u8 = delimiter[delimiter.len - 1];
        if (height > 1 and (eq(delimiter, "(") or eq(delimiter, "\\{"))) c = if (i == 0) '/' else if (i == height - 1) '\\' else '|';
        if (height > 1 and (eq(delimiter, ")") or eq(delimiter, "\\}"))) c = if (i == 0) '\\' else if (i == height - 1) '/' else '|';
        if (height >= 3 and i == @divFloor(height - 1, 2)) { if (eq(delimiter, "\\{")) c = '<'; if (eq(delimiter, "\\}")) c = '>'; }
        out.draw(fmt("{c}", .{c}), x, i);
    }
}
pub fn large(value: []const u8) *Box {
    const integral = eq(value, "\\int"); const out = box(fmt("atom \"{s}\"", .{value}), if (integral) 2 else 3, 3, 1);
    const lines: []const []const u8 = if (eq(value, "\\sum")) &.{"\\--", " > ", "/--"} else if (integral) &.{" /", " |", "/ "} else &.{"___", "| |", "| |"};
    for (lines, 0..) |line, i| out.draw(line, 0, @intCast(i)); return out;
}
