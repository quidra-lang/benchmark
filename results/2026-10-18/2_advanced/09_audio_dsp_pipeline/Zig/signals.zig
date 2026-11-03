const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, source: []const T) []T { return allocator.dupe(T, source) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn int(value: anytype) i64 { return @intCast(value); }
pub fn index(value: i64) usize { return @intCast(value); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn split(text: []const u8, separator: u8) []const []const u8 { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, separator); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) []const []const u8 { const result = split(text, '\n'); return result[0..result.len - 1]; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn byte(self: *Text, ch: u8) void { append(u8, &self.data, ch); }
    pub fn spaces(self: *Text, count: usize) void { for (0..count) |_| self.byte(' '); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn extend(self: *Lines, other: Lines) void { for (other.data.items) |line| self.write(line); }
    pub fn content(self: Lines) []const u8 { var text: Text = .{}; for (self.data.items) |line| { text.write(line); text.byte('\n'); } return text.value(); }
};
pub const Signal = struct { name: []const u8, rate: i64, samples: []const i64, origin: []const u8 = "input", ingredients: []const *const Signal = &.{} };
pub fn create(signal: Signal) *const Signal { const result = allocator.create(Signal) catch @panic("allocation failed"); result.* = signal; return result; }
pub const Result = struct { samples: []const i64, clipped: i64 };
pub fn rdiv(a: i64, b: i64) i64 { return @divFloor(2 * a + b, 2 * b); }
pub fn saturate(counter: *i64, value: i64) i64 { const limited = @max(-32768, @min(32767, value)); if (limited != value) counter.* += 1; return limited; }
pub fn peak(samples: []const i64) i64 { var result: i64 = 0; for (samples) |value| result = @max(result, abs(value)); return result; }
pub fn sum(samples: []const i64) i64 { var result: i64 = 0; for (samples) |value| result += value; return result; }
pub fn read(text: []const u8) []const *const Signal {
    const all = lines(text); var result: std.ArrayList(*const Signal) = .empty; var i: usize = 0;
    while (i < all.len) { const header = split(all[i], ' '); const count = std.fmt.parseInt(usize, header[3], 10) catch unreachable; const samples = alloc(i64, count); i += 1; var n: usize = 0;
        while (n < count) : (i += 1) { for (split(all[i], ' ')) |token| { samples[n] = std.fmt.parseInt(i64, token, 10) catch unreachable; n += 1; } }
        append(*const Signal, &result, create(.{ .name = header[1], .rate = std.fmt.parseInt(i64, header[2], 10) catch unreachable, .samples = samples }));
    }
    return result.items;
}
pub fn format(signal: *const Signal) Lines {
    var result: Lines = .{}; result.add("SIGNAL {s} {d} {d}", .{ signal.name, signal.rate, signal.samples.len }); var first: usize = 0;
    while (first < signal.samples.len) : (first += 16) { var text: Text = .{}; for (signal.samples[first..@min(first + 16, signal.samples.len)], 0..) |value, i| { if (i > 0) text.byte(' '); text.add("{d}", .{value}); } result.write(text.value()); }
    return result;
}
pub fn impulse(count: usize, position: usize, amplitude: i64) []const i64 { const result = alloc(i64, count); @memset(result, 0); result[position] = amplitude; return result; }
pub fn step(count: usize, position: usize, amplitude: i64) []const i64 { const result = alloc(i64, count); for (result, 0..) |*value, i| value.* = if (i >= position) amplitude else 0; return result; }
pub fn noise(count: usize, seed: i64) []const i64 { const result = alloc(i64, count); var state = seed; for (result) |*value| { state = @mod(48271 * state, 2147483647); value.* = @mod(state, 65536) - 32768; } return result; }
