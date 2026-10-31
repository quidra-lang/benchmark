const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub var backing: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn create(comptime T: type, value: T) *T { const result = allocator.create(T) catch @panic("allocation failed"); result.* = value; return result; }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn tempAppend(comptime T: type, list: *std.ArrayList(T), temporary: std.mem.Allocator, value: T) void { list.append(temporary, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn int(value: anytype) i64 { return @intCast(value); }
pub fn index(value: i64) usize { return @intCast(value); }
pub fn parse(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn split(text: []const u8, delimiter: u8) []const []const u8 { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, delimiter); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) []const []const u8 { const result = split(text, '\n'); return result[0..result.len - 1]; }
pub fn join(parts: []const []const u8, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn byte(self: *Text, ch: u8) void { append(u8, &self.data, ch); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn extend(self: *Lines, other: Lines) void { for (other.data.items) |line| self.write(line); }
    pub fn content(self: Lines) []const u8 { var text: Text = .{}; for (self.data.items) |line| { text.write(line); text.byte('\n'); } return text.value(); }
};
pub fn gcd(a: i64, b: i64) i64 { var first = a; var second = b; while (second != 0) { const remainder = @mod(first, second); first = second; second = remainder; } return first; }
pub fn dec(a: i64, b: i64, places: usize) []const u8 { if (b == 0) return "-"; var scale: i64 = 1; for (0..places) |_| scale *= 10; const z = @divFloor(2 * a * scale + b, 2 * b); const tail = fmt("{d}", .{@mod(z, scale)}); var text: Text = .{}; text.add("{d}.", .{@divFloor(z, scale)}); for (tail.len..places) |_| text.byte('0'); text.write(tail); return text.value(); }
pub fn frac(a: i64, b: i64) []const u8 { if (b == 0) return "-"; const divisor = gcd(a, b); return fmt("{d}/{d}", .{ @divExact(a, divisor), @divExact(b, divisor) }); }
pub const Fraction = struct {
    n: i64, d: i64,
    pub fn init(n: i64, d: i64) Fraction { const divisor = gcd(n, d); return .{ .n = @divExact(n, divisor), .d = @divExact(d, divisor) }; }
    pub fn mul(self: Fraction, other: Fraction) Fraction { const a = gcd(self.n, other.d); const b = gcd(other.n, self.d); return init(@divExact(self.n, a) * @divExact(other.n, b), @divExact(self.d, b) * @divExact(other.d, a)); }
    pub fn add(self: Fraction, other: Fraction) Fraction { const common = gcd(self.d, other.d); return init(self.n * @divExact(other.d, common) + other.n * @divExact(self.d, common), @divExact(self.d, common) * other.d); }
    pub fn text(self: Fraction) []const u8 { return frac(self.n, self.d); }
};
pub fn percentile(times: []const i64, q: i64) i64 { return times[index(@divFloor(q * int(times.len) + 99, 100) - 1)]; }
pub fn histogram(times: []const i64, width: i64) Lines { const first = @divFloor(times[0], width); const counts = alloc(i64, index(@divFloor(times[times.len - 1], width) - first + 1)); @memset(counts, 0); for (times) |time| counts[index(@divFloor(time, width) - first)] += 1; var largest: i64 = 0; for (counts) |count| largest = @max(largest, count); var result: Lines = .{}; for (counts, 0..) |count, i| { const low = (first + int(i)) * width; const stars = index(@divFloor(80 * count + largest, 2 * largest)); var text: Text = .{}; text.add("  {d}-{d} {d}", .{ low, low + width - 1, count }); if (stars > 0) { text.byte(' '); for (0..stars) |_| text.byte('*'); } result.write(text.value()); } return result; }
