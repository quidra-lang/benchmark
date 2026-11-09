const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn take(comptime T: type, memory: std.mem.Allocator, count: usize) []T { return memory.alloc(T, count) catch @panic("allocation failed"); }
pub fn alloc(comptime T: type, count: usize) []T { return take(T, allocator, count); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn f(value: anytype) f64 { return @floatFromInt(value); }
pub fn number(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn split(text: []const u8, separator: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, text, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(text: []const u8) []const []const u8 {
    const result = split(text, '\n');
    return result[0 .. result.len - 1];
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed"); }
    pub fn paragraph(self: *Lines, other: Lines) void { if (self.data.items.len > 0) self.write(""); self.extend(other); }
};
pub fn realText(value: f64) []const u8 {
    const text = fmt("{d:.4}", .{value});
    return if (eq(text, "-0.0000")) text[1..] else text;
}
pub fn decimalValue(value: f64) f64 { return std.fmt.parseFloat(f64, realText(value)) catch unreachable; }
pub fn proportion(numerator: i64, denominator: i64) []const u8 { return fmt("{d}/{d} {s}", .{ numerator, denominator, realText(f(numerator) / f(denominator)) }); }
pub fn fraction(numerator: i64, denominator: i64) []const u8 {
    if (denominator == 0) return "- -";
    var first = numerator;
    var second = denominator;
    while (second != 0) {
        const remainder = @mod(first, second);
        first = second;
        second = remainder;
    }
    return proportion(@divTrunc(numerator, first), @divTrunc(denominator, first));
}
pub const Evaluation = struct {
    classes: usize,
    matrix: [8][8]usize = @splat(@splat(0)),
    total: usize,
    correct: usize = 0,
    micro_f1: f64 = 0,
    macro_f1: f64 = 0,

    fn support(self: *const Evaluation, label: usize) usize {
        var total: usize = 0;
        for (self.matrix[label][0..self.classes]) |value| total += value;
        return total;
    }
    fn predictedCount(self: *const Evaluation, label: usize) usize {
        var total: usize = 0;
        for (0..self.classes) |i| total += self.matrix[i][label];
        return total;
    }
    pub fn output(self: *const Evaluation, names: []const []const u8) Lines {
        var result: Lines = .{};
        var header: Text = .{};
        header.write("true\\predicted");
        for (names) |name| header.add(" {s}", .{name});
        result.write(header.value());
        for (names, 0..) |name, label| {
            var row: Text = .{};
            row.write(name);
            for (self.matrix[label][0..self.classes]) |value| row.add(" {d}", .{value});
            result.write(row.value());
        }
        for (names, 0..) |name, label| {
            const hits = n(self.matrix[label][label]);
            const actual = n(self.support(label));
            const predicted = n(self.predictedCount(label));
            result.add("class {s} precision {s} recall {s} f1 {s} support {d}", .{ name, fraction(hits, predicted), fraction(hits, actual), fraction(2 * hits, predicted + actual), actual });
        }
        result.add("micro_f1 {s} macro_f1 {s}", .{ realText(self.micro_f1), realText(self.macro_f1) });
        return result;
    }
};
pub fn evaluate(classes: usize, truths: []const usize, predictions: []const usize) Evaluation {
    var result: Evaluation = .{ .classes = classes, .total = truths.len };
    for (truths, predictions) |truth, predicted| result.matrix[truth][predicted] += 1;
    var scored: usize = 0;
    var sum: f64 = 0;
    for (0..classes) |label| {
        const hits = result.matrix[label][label];
        result.correct += hits;
        const denominator = result.support(label) + result.predictedCount(label);
        if (denominator > 0) { sum += f(2 * hits) / f(denominator); scored += 1; }
    }
    result.micro_f1 = f(result.correct) / f(truths.len);
    result.macro_f1 = sum / f(scored);
    return result;
}
