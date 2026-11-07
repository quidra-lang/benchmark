const std = @import("std");
const b = @import("bids_io.zig");
fn gcd(first: i64, second: i64) i64 {
    var a: i64 = @intCast(@abs(first));
    var c: i64 = @intCast(@abs(second));
    while (c != 0) {
        const next = @mod(a, c);
        a = c;
        c = next;
    }
    return a;
}
pub const Fraction = struct {
    numerator: i64 = 0,
    denominator: i64 = 1,
    pub fn init(numerator: i64, denominator: i64) Fraction {
        const divisor = gcd(numerator, denominator);
        const sign: i64 = if (denominator < 0) -1 else 1;
        return .{ .numerator = sign * @divTrunc(numerator, divisor), .denominator = sign * @divTrunc(denominator,
             divisor) };
    }
    pub fn integer(value: i64) Fraction {
        return .{ .numerator = value };
    }
    pub fn add(self: Fraction, other: Fraction) Fraction {
        const divisor = gcd(self.denominator, other.denominator);
        const left = @divTrunc(self.denominator, divisor);
        const right = @divTrunc(other.denominator, divisor);
        return init(self.numerator * right + other.numerator * left, left * other.denominator);
    }
    pub fn subtract(self: Fraction, other: Fraction) Fraction {
        return self.add(.{ .numerator = -other.numerator, .denominator = other.denominator });
    }
    pub fn multiply(self: Fraction, other: Fraction) Fraction {
        const first = gcd(self.numerator, other.denominator);
        const second = gcd(other.numerator, self.denominator);
        return init(@divTrunc(self.numerator, first) * @divTrunc(other.numerator, second),
             @divTrunc(self.denominator, second) * @divTrunc(other.denominator, first));
    }
    pub fn divide(self: Fraction, other: Fraction) Fraction {
        return self.multiply(init(other.denominator, other.numerator));
    }
    pub fn scale(self: Fraction, value: i64) Fraction {
        return self.multiply(integer(value));
    }
    pub fn less(self: Fraction, other: Fraction) bool {
        return @as(i128, self.numerator) * other.denominator < @as(i128, other.numerator) * self.denominator;
    }
    pub fn text(self: Fraction) []const u8 {
        return if (self.denominator == 1) b.fmt("{d}", .{self.numerator}) else b.fmt("{d}/{d}",
             .{ self.numerator, self.denominator });
    }
};
pub fn bundle(mask: u16, items: []const b.Item, separator: []const u8) []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (items, 0..) |item, index| if (mask & b.bit(index) != 0) b.append([]const u8, &names, item.name);
    return if (names.items.len == 0) "-" else b.join(names.items, separator);
}
pub fn numbers(bids: []const b.Bid) []const u8 {
    if (bids.len == 0) return "-";
    const ordered = b.dupe(b.Bid, bids);
    std.mem.sort(b.Bid, ordered, {}, struct {
        fn less(_: void, a: b.Bid, c: b.Bid) bool {
            return a.number < c.number;
        }
    }.less);
    var parts: std.ArrayList([]const u8) = .empty;
    for (ordered) |bid| b.append([]const u8, &parts, b.fmt("{d}", .{bid.number}));
    return b.join(parts.items, "+");
}
pub fn write(io: std.Io, name: []const u8, lines: b.Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: b.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = b.fmt("output/{s}", .{name}), .data = out.value() });
}
