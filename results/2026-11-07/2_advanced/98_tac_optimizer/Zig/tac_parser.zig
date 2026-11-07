const std = @import("std");
pub const Text = []const u8;
pub const Allocator = std.mem.Allocator;
pub fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
pub fn less(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; }
pub fn variable(s: Text) bool { return s.len > 0 and s[0] != '-' and !std.ascii.isDigit(s[0]); }
pub fn number(s: Text) i64 { return std.fmt.parseInt(i64, s, 10) catch unreachable; }
pub const Kind = enum { copy, bin, load, store, goto, @"if", param, call, @"return", read, print };
pub const Instruction = struct {
    kind: Kind, dest: Text = "", a: Text = "", b: Text = "", op: Text = "", array: Text = "", target: Text = "", count: usize = 0, labels: []const Text = &.{},
    pub fn used(i: Instruction) [2]Text { return switch (i.kind) { .copy, .load, .param, .@"return", .print => .{i.a, ""}, .bin, .@"if", .store => .{i.a, i.b}, else => .{"", ""} }; }
    pub fn operand(i: *Instruction, index: usize) *Text { return if (index == 0) &i.a else &i.b; }
    pub fn expression(i: Instruction, a: Allocator) !?Text { return switch (i.kind) { .bin => try std.fmt.allocPrint(a, "{s}{s}{s}", .{i.a, i.op, i.b}), .load => try std.fmt.allocPrint(a, "{s}[{s}]", .{i.array, i.a}), else => null }; }
    pub fn text(i: Instruction, a: Allocator) !Text {
        return switch (i.kind) {
            .copy => std.fmt.allocPrint(a, "{s} = {s}", .{i.dest, i.a}), .bin => std.fmt.allocPrint(a, "{s} = {s} {s} {s}", .{i.dest, i.a, i.op, i.b}),
            .load => std.fmt.allocPrint(a, "{s} = {s}[{s}]", .{i.dest, i.array, i.a}), .store => std.fmt.allocPrint(a, "{s}[{s}] = {s}", .{i.array, i.a, i.b}),
            .goto => std.fmt.allocPrint(a, "goto {s}", .{i.target}), .@"if" => std.fmt.allocPrint(a, "if {s} {s} {s} goto {s}", .{i.a, i.op, i.b, i.target}),
            .param => std.fmt.allocPrint(a, "param {s}", .{i.a}), .call => if (i.dest.len > 0) std.fmt.allocPrint(a, "{s} = call {s} {d}", .{i.dest, i.target, i.count}) else std.fmt.allocPrint(a, "call {s} {d}", .{i.target, i.count}),
            .@"return" => if (i.a.len == 0) "return" else std.fmt.allocPrint(a, "return {s}", .{i.a}), .read => std.fmt.allocPrint(a, "read {s}", .{i.dest}), .print => std.fmt.allocPrint(a, "print {s}", .{i.a}),
        };
    }
};
pub const Function = struct { name: Text, params: []const Text, code: []Instruction, temporaries: usize = 0, preheaders: usize = 0 };
pub const Array = struct { name: Text, size: usize };
pub const Program = struct { arrays: []const Array, functions: []Function };
pub const Buffer = struct { a: Allocator, data: std.ArrayList(u8) = .empty,
    pub fn add(b: *Buffer, s: Text) !void { try b.data.appendSlice(b.a, s); }
    pub fn print(b: *Buffer, comptime f: Text, args: anytype) !void { try b.add(try std.fmt.allocPrint(b.a, f, args)); }
    pub fn line(b: *Buffer, s: Text) !void { try b.add(s); try b.add("\n"); }
};
fn bracket(s: Text) struct { array: Text, index: Text } { const p = std.mem.indexOfScalar(u8, s, '[').?; return .{ .array = s[0..p], .index = s[p + 1..s.len - 1] }; }
pub fn parse(a: Allocator, text: Text) !Program {
    var arrays: std.ArrayList(Array) = .empty; var functions: std.ArrayList(Function) = .empty; var code: std.ArrayList(Instruction) = .empty; var labels: std.ArrayList(Text) = .empty;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var words: std.ArrayList(Text) = .empty; var it = std.mem.tokenizeScalar(u8, line, ' '); while (it.next()) |word| try words.append(a, word); const w = words.items; if (w.len == 0 or w[0][0] == '#') continue;
        if (eq(w[0], "array")) { try arrays.append(a, .{ .name = w[1], .size = @intCast(number(w[2])) }); continue; }
        if (eq(w[0], "func")) { try functions.append(a, .{ .name = w[1], .params = w[2..], .code = &.{} }); code = .empty; continue; }
        if (eq(w[0], "end")) { functions.items[functions.items.len - 1].code = code.items; continue; }
        if (w.len == 1 and w[0][w[0].len - 1] == ':') { try labels.append(a, w[0][0..w[0].len - 1]); continue; }
        var ins: Instruction = undefined;
        if (eq(w[0], "goto")) ins = .{ .kind = .goto, .target = w[1] }
        else if (eq(w[0], "if")) ins = .{ .kind = .@"if", .a = w[1], .op = w[2], .b = w[3], .target = w[5] }
        else if (eq(w[0], "return")) ins = .{ .kind = .@"return", .a = if (w.len == 2) w[1] else "" }
        else if (eq(w[0], "read")) ins = .{ .kind = .read, .dest = w[1] }
        else if (eq(w[0], "print") or eq(w[0], "param")) ins = .{ .kind = if (eq(w[0], "print")) .print else .param, .a = w[1] }
        else if (eq(w[0], "call")) ins = .{ .kind = .call, .target = w[1], .count = @intCast(number(w[2])) }
        else if (std.mem.indexOfScalar(u8, w[0], '[') != null) { const v = bracket(w[0]); ins = .{ .kind = .store, .array = v.array, .a = v.index, .b = w[2] }; }
        else if (eq(w[2], "call")) ins = .{ .kind = .call, .dest = w[0], .target = w[3], .count = @intCast(number(w[4])) }
        else if (w.len == 5) ins = .{ .kind = .bin, .dest = w[0], .a = w[2], .op = w[3], .b = w[4] }
        else if (std.mem.indexOfScalar(u8, w[2], '[') != null) { const v = bracket(w[2]); ins = .{ .kind = .load, .dest = w[0], .array = v.array, .a = v.index }; }
        else ins = .{ .kind = .copy, .dest = w[0], .a = w[2] };
        if (ins.a.len > 0 and !variable(ins.a)) ins.a = try std.fmt.allocPrint(a, "{d}", .{number(ins.a)});
        if (ins.b.len > 0 and !variable(ins.b)) ins.b = try std.fmt.allocPrint(a, "{d}", .{number(ins.b)});
        ins.labels = labels.items; labels = .empty; try code.append(a, ins);
    }
    return .{ .arrays = arrays.items, .functions = functions.items };
}
pub fn functionText(b: *Buffer, f: Function) !void { try b.print("func {s}", .{f.name}); for (f.params) |p| try b.print(" {s}", .{p}); try b.add("\n"); for (f.code) |i| { for (i.labels) |label| try b.print("{s}:\n", .{label}); try b.print("    {s}\n", .{try i.text(b.a)}); } try b.line("end"); }
pub fn programText(b: *Buffer, p: Program) !void { for (p.arrays) |ar| try b.print("array {s} {d}\n", .{ar.name, ar.size}); for (p.functions, 0..) |f, i| { if (i > 0 or p.arrays.len > 0) try b.add("\n"); try functionText(b, f); } }
pub fn calculate(op: Text, a: i64, b: i64) i64 { if (eq(op, "+")) return a + b; if (eq(op, "-")) return a - b; if (eq(op, "*")) return a * b; if (eq(op, "/")) return @divTrunc(a, b); if (eq(op, "%")) return @rem(a, b); return @intFromBool(if (eq(op, "<")) a < b else if (eq(op, "<=")) a <= b else if (eq(op, ">")) a > b else if (eq(op, ">=")) a >= b else if (eq(op, "==")) a == b else a != b); }
