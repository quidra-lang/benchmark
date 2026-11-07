const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}
pub const Clause = []const i64;
pub const Model = []const i64;
pub const Formula = struct { variables: usize = 0, clauses: std.ArrayList(Clause) = .empty };
pub const Edge = struct { a: usize, b: usize };
pub const Graph = struct { name: []const u8, error_reason: ?[]const u8 = null, vertices: usize, edges: std.ArrayList(Edge) = .empty,
     degrees: []usize };
pub fn contains(values: []const i64, value: i64) bool {
    return std.mem.indexOfScalar(i64, values, value) != null;
}
pub fn wellNumber(value: []const u8) bool {
    if (value.len == 0 or value.len > 6) return false;
    if (eq(value, "0")) return true;
    if (value[0] < '1' or value[0] > '9') return false;
    for (value) |char| if (char < '0' or char > '9') return false;
    return true;
}
pub const CnfInput = struct { formula: Formula = .{}, error_reason: ?[]const u8 = null };
pub fn readCnf(io: std.Io, name: []const u8) !CnfInput {
    var out: CnfInput = .{};
    var header = false;
    var declared: i64 = 0;
    var current: std.ArrayList(i64) = .empty;
    for (try readLines(io, fmt("input/{s}", .{name})), 1..) |line, index| {
        if (line.len > 0 and line[0] == 'c') continue;
        const tokens = words(line);
        if (tokens.len == 0) continue;
        if (eq(tokens[0], "p")) {
            if (header) {
                out.error_reason = fmt("duplicate header at line {d}", .{index});
                return out;
            }
            if (tokens.len != 4 or !eq(tokens[1], "cnf") or !wellNumber(tokens[2]) or !wellNumber(tokens[3])) {
                out.error_reason = fmt("bad header at line {d}", .{index});
                return out;
            }
            header = true;
            out.formula.variables = u(number(tokens[2]));
            declared = number(tokens[3]);
            continue;
        }
        if (!header) {
            out.error_reason = "missing header";
            return out;
        }
        for (tokens) |token| {
            const negative = token[0] == '-';
            const magnitude = if (negative) token[1..] else token;
            if (!wellNumber(magnitude) or (negative and eq(magnitude, "0"))) {
                out.error_reason = fmt("bad token {s} at line {d}", .{ token, index });
                return out;
            }
            const literal = number(token);
            if (@abs(literal) > out.formula.variables) {
                out.error_reason = fmt("literal out of range {s} at line {d}", .{ token, index });
                return out;
            }
            if (literal != 0) append(i64, &current, literal) else {
                append(Clause, &out.formula.clauses, current.items);
                current = .empty;
            }
        }
    }
    if (!header) out.error_reason = "missing header" else if (current.items.len > 0) out.error_reason = "unterminated clause" else if (n(out.formula.clauses.items.len) != declared) out.error_reason = fmt("clause count mismatch header={d} found={d}",
         .{ declared, out.formula.clauses.items.len });
    return out;
}
pub fn modelLines(model: Model) Lines {
    var lines: Lines = .{};
    var first: usize = 1;
    while (first < model.len + 1) : (first += 10) {
        var line: Text = .{};
        line.add("v", .{});
        var x = first;
        while (x < first + 10 and x < model.len + 1) : (x += 1) line.add(" {d}", .{if (x == model.len) @as(i64,
             0) else if (model[x] == 1) n(x) else -n(x)});
        lines.add("{s}", .{line.value()});
    }
    return lines;
}
