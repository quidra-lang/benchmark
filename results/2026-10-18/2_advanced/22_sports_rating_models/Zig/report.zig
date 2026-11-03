const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;

pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn f(value: anytype) f64 { return @floatFromInt(value); }
pub fn number(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
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
    pub fn write(self: *Text, text: []const u8) void {
        self.data.appendSlice(allocator, text) catch @panic("allocation failed");
    }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn paragraph(self: *Lines, other: Lines) void {
        if (self.data.items.len > 0) self.write("");
        self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed");
    }
};

fn gcd(a: i64, b: i64) i64 {
    var first = if (a < 0) -a else a;
    var second = if (b < 0) -b else b;
    while (second != 0) {
        const remainder = @mod(first, second);
        first = second;
        second = remainder;
    }
    return first;
}
pub const Fraction = struct {
    numerator: i64 = 0,
    denominator: i64 = 1,

    pub fn init(a: i64, b: i64) Fraction {
        const numerator = if (b < 0) -a else a;
        const denominator = if (b < 0) -b else b;
        const divisor = gcd(numerator, denominator);
        return .{ .numerator = @divTrunc(numerator, divisor), .denominator = @divTrunc(denominator, divisor) };
    }
    pub fn add(first: Fraction, second: Fraction) Fraction {
        const common = gcd(first.denominator, second.denominator);
        const left = @divTrunc(first.denominator, common);
        const right = @divTrunc(second.denominator, common);
        return init(first.numerator * right + second.numerator * left, first.denominator * right);
    }
    pub fn multiply(first: Fraction, second: Fraction) Fraction {
        const left = gcd(first.numerator, second.denominator);
        const right = gcd(second.numerator, first.denominator);
        return init(@divTrunc(first.numerator, left) * @divTrunc(second.numerator, right), @divTrunc(first.denominator, right) * @divTrunc(second.denominator, left));
    }
    pub fn divide(self: Fraction, divisor: i64) Fraction { return self.multiply(init(1, divisor)); }
    pub fn compare(first: Fraction, second: Fraction) std.math.Order {
        return std.math.order(first.numerator * second.denominator, second.numerator * first.denominator);
    }
    pub fn real(self: Fraction) f64 { return f(self.numerator) / f(self.denominator); }
    pub fn text(self: Fraction) []const u8 { return fmt("{d}/{d}", .{ self.numerator, self.denominator }); }
    pub fn fixed(self: Fraction, places: usize) []const u8 {
        const magnitude = if (self.numerator < 0) -self.numerator else self.numerator;
        var whole = @divTrunc(magnitude, self.denominator);
        var remainder = @mod(magnitude, self.denominator);
        var digits: i64 = 0;
        var scale: i64 = 1;
        for (0..places) |_| {
            remainder *= 10;
            digits = digits * 10 + @divTrunc(remainder, self.denominator);
            remainder = @mod(remainder, self.denominator);
            scale *= 10;
        }
        const parity = if (places > 0) digits else whole;
        if (remainder > self.denominator - remainder or (remainder == self.denominator - remainder and @mod(parity, 2) != 0)) digits += 1;
        if (digits == scale) { whole += 1; digits = 0; }
        const sign = if (self.numerator < 0 and (whole != 0 or digits != 0)) "-" else "";
        if (places == 0) return fmt("{s}{d}", .{ sign, whole });
        const tail = fmt("{d}", .{digits});
        var result: Text = .{};
        result.add("{s}{d}.", .{ sign, whole });
        for (tail.len..places) |_| result.write("0");
        result.write(tail);
        return result.value();
    }
    pub fn withReal(self: Fraction) []const u8 { return fmt("{s} {s}", .{ self.text(), self.fixed(4) }); }
};
pub const Comparison = struct {
    exact: bool = false,
    fraction: Fraction = .{},
    value: f64 = 0,
    pub fn compare(first: Comparison, second: Comparison) std.math.Order {
        return if (first.exact) first.fraction.compare(second.fraction) else std.math.order(first.value, second.value);
    }
};

pub fn fixed(value: f64, places: usize) []const u8 {
    const text = if (places == 2) fmt("{d:.2}", .{value}) else fmt("{d:.4}", .{value});
    if (text.len > 0 and text[0] == '-' and (std.fmt.parseFloat(f64, text) catch unreachable) == 0) return text[1..];
    return text;
}
pub fn decimalValue(value: f64, places: usize) f64 {
    return std.fmt.parseFloat(f64, fixed(value, places)) catch unreachable;
}
pub fn writeLines(io: std.Io, name: []const u8, source: Lines) !void {
    var text: Text = .{};
    for (source.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
