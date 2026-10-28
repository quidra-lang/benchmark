const std = @import("std");
const d = @import("song_parser.zig");
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(d.allocator, d.fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        d.append([]const u8, &self.data, d.fmt(pattern, args));
    }
    pub fn extend(self: *Lines, other: Lines) void {
        for (other.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn hex(value: anytype, width: usize) []const u8 {
    const text = d.fmt("{X}", .{value});
    const out = d.alloc(u8, @max(width, text.len));
    @memset(out, '0');
    @memcpy(out[out.len - text.len ..], text);
    return out;
}
pub fn aligned(value: anytype, width: usize) []const u8 {
    const text = d.fmt("{d}", .{value});
    const out = d.alloc(u8, @max(width, text.len));
    @memset(out, ' ');
    @memcpy(out[out.len - text.len ..], text);
    return out;
}
pub fn adler32(samples: []const i64) i64 {
    var a: i64 = 1;
    var b: i64 = 0;
    for (samples) |value| {
        a = @mod(a + value, 65521);
        b = @mod(b + a, 65521);
    }
    return b * 65536 + a;
}
pub fn integerSqrt(value: i64) i64 {
    var lo: i64 = 0;
    var hi = value + 1;
    while (lo + 1 < hi) {
        const middle = @divTrunc(lo + hi, 2);
        if (middle <= @divTrunc(value, middle)) lo = middle else hi = middle;
    }
    return lo;
}
pub const Stats = struct { peak: i64 = 0, rms: i64 = 0, crossings: i64 = 0, minimum: i64, maximum: i64 };
pub fn statistics(samples: []const i64) Stats {
    var out: Stats = .{ .minimum = samples[0], .maximum = samples[0] };
    var squares: i64 = 0;
    for (samples, 0..) |sample, i| {
        const centered = sample - 128;
        out.peak = @max(out.peak, @as(i64, @intCast(@abs(centered))));
        out.minimum = @min(out.minimum, sample);
        out.maximum = @max(out.maximum, sample);
        squares += centered * centered;
        if (i > 0 and ((samples[i - 1] < 128) != (sample < 128))) out.crossings += 1;
    }
    out.rms = integerSqrt(@divTrunc(squares, d.n(samples.len)));
    return out;
}
pub fn sampleDump(samples: []const i64) Lines {
    var out: Lines = .{};
    var start: usize = 0;
    while (start < samples.len) : (start += 32) {
        var line: Text = .{};
        for (samples[start..@min(start + 32, samples.len)]) |sample| line.add("{s}", .{hex(sample, 2)});
        out.add("{s}", .{line.value()});
    }
    return out;
}
pub fn write(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
