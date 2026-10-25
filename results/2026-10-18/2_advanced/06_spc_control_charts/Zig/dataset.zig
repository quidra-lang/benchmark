const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, values: []const T) []T { return allocator.dupe(T, values) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub fn split(text: []const u8, delimiter: u8) Strings { var parts: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, delimiter); while (it.next()) |part| append([]const u8, &parts, part); return parts.items; }
pub fn lines(text: []const u8) Strings { const parts = split(text, '\n'); return parts[0..parts.len - 1]; }
pub fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn natural(text: []const u8) usize { return @intCast(integer(text)); }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn number(text: []const u8) f64 { return std.fmt.parseFloat(f64, text) catch unreachable; }
pub fn repeated(byte: u8, count: usize) []const u8 { const text = alloc(u8, count); @memset(text, byte); return text; }
pub fn sequence(first: usize, last: usize) []usize { const result = alloc(usize, if (last >= first) last - first + 1 else 0); for (result, first..) |*value, i| value.* = i; return result; }
pub fn contains(numbers: []const usize, value: usize) bool { return std.mem.findScalar(usize, numbers, value) != null; }
pub const Settings = struct { characteristic: []const u8, lsl: i64, usl: i64, target: i64, n: usize, m: usize, passes: usize, rules: [7][]const usize, k: f64, h: f64, lambda: f64, e: f64, span: usize, gap: usize, z: f64, bin: i64, window: usize, step: usize };
pub const Lot = struct { number: usize, inspected: i64, defectives: i64, defects: i64 };
pub const Constants = struct { a2: f64, a3: f64, b3: f64, b4: f64, d3: f64, d4: f64, d2: f64, c4: f64 };
pub fn constants(n: usize) Constants {
    const rows: [9][8]f64 = .{
        .{ 1.880, 2.659, 0, 3.267, 0, 3.267, 1.128, 0.7979 },
        .{ 1.023, 1.954, 0, 2.568, 0, 2.574, 1.693, 0.8862 },
        .{ 0.729, 1.628, 0, 2.266, 0, 2.282, 2.059, 0.9213 },
        .{ 0.577, 1.427, 0, 2.089, 0, 2.114, 2.326, 0.9400 },
        .{ 0.483, 1.287, 0.030, 1.970, 0, 2.004, 2.534, 0.9515 },
        .{ 0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594 },
        .{ 0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650 },
        .{ 0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693 },
        .{ 0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727 },
    };
    const r = rows[n - 2];
    return .{ .a2 = r[0], .a3 = r[1], .b3 = r[2], .b4 = r[3], .d3 = r[4], .d4 = r[5], .d2 = r[6], .c4 = r[7] };
}
pub fn settings(text: []const u8) Settings {
    var result: Settings = undefined;
    var rule: usize = 0;
    for (lines(text)) |line| {
        const f = split(line, ' ');
        if (eq(f[0], "rules")) { const values = alloc(usize, f.len - 2); for (f[2..], values) |field, *value| value.* = natural(field); result.rules[rule] = values; rule += 1; }
        else if (eq(f[0], "characteristic")) result.characteristic = f[1]
        else if (eq(f[0], "lsl")) result.lsl = integer(f[1])
        else if (eq(f[0], "usl")) result.usl = integer(f[1])
        else if (eq(f[0], "target")) result.target = integer(f[1])
        else if (eq(f[0], "subgroup_size")) result.n = natural(f[1])
        else if (eq(f[0], "phase1_subgroups")) result.m = natural(f[1])
        else if (eq(f[0], "max_passes")) result.passes = natural(f[1])
        else if (eq(f[0], "cusum_k")) result.k = number(f[1])
        else if (eq(f[0], "cusum_h")) result.h = number(f[1])
        else if (eq(f[0], "ewma_lambda")) result.lambda = number(f[1])
        else if (eq(f[0], "ewma_l")) result.e = number(f[1])
        else if (eq(f[0], "ma_span")) result.span = natural(f[1])
        else if (eq(f[0], "event_gap")) result.gap = natural(f[1])
        else if (eq(f[0], "ci_z")) result.z = number(f[1])
        else if (eq(f[0], "histogram_bin")) result.bin = integer(f[1])
        else if (eq(f[0], "rolling_window")) result.window = natural(f[1])
        else if (eq(f[0], "rolling_step")) result.step = natural(f[1]);
    }
    return result;
}
pub fn measurements(text: []const u8) []const i64 { var result: std.ArrayList(i64) = .empty; for (lines(text)[1..]) |line| append(i64, &result, integer(split(line, ',')[2])); return result.items; }
pub fn attributes(text: []const u8) []const Lot { var result: std.ArrayList(Lot) = .empty; for (lines(text)[1..]) |line| { const f = split(line, ','); append(Lot, &result, .{ .number = natural(f[0]), .inspected = integer(f[1]), .defectives = integer(f[2]), .defects = integer(f[3]) }); } return result.items; }
