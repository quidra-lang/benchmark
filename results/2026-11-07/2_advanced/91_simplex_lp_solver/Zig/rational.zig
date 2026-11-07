const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, n: usize) []T { return allocator.alloc(T, n) catch @panic("allocation failed"); }
pub fn copy(comptime T: type, a: []const T) []T { return allocator.dupe(T, a) catch @panic("allocation failed"); }
pub fn add(comptime T: type, a: *std.ArrayList(T), v: T) void { a.append(allocator, v) catch @panic("allocation failed"); }
pub fn fmt(comptime s: []const u8, a: anytype) []const u8 { return std.fmt.allocPrint(allocator, s, a) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn words(s: []const u8) []const []const u8 {
    var a: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, s, ' ');
    while (it.next()) |v| add([]const u8, &a, v);
    return a.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn put(self: *Text, comptime s: []const u8, a: anytype) void { self.data.appendSlice(allocator, fmt(s, a)) catch @panic("allocation failed"); }
    pub fn line(self: *Text, comptime s: []const u8, a: anytype) void { self.put(s, a); self.put("\n", .{}); }
};
pub const Q = struct {
    n: i64 = 0, d: i64 = 1,
    pub fn init(n: i64, d: i64) Q {
        if (n == 0) return .{};
        const g: i64 = @intCast(std.math.gcd(@abs(n), @abs(d)));
        return .{ .n = @divTrunc(n, g) * (if (d < 0) @as(i64, -1) else 1), .d = @divTrunc(@as(i64, @intCast(@abs(d))), g) };
    }
    pub fn int(n: i64) Q { return .{ .n = n }; }
    pub fn plus(a: Q, b: Q) Q { return init(a.n * b.d + b.n * a.d, a.d * b.d); }
    pub fn minus(a: Q, b: Q) Q { return a.plus(b.neg()); }
    pub fn mul(a: Q, b: Q) Q { return init(a.n * b.n, a.d * b.d); }
    pub fn div(a: Q, b: Q) Q { return init(a.n * b.d, a.d * b.n); }
    pub fn neg(a: Q) Q { return .{ .n = -a.n, .d = a.d }; }
    pub fn cmp(a: Q, b: Q) std.math.Order { return std.math.order(a.n * b.d, b.n * a.d); }
    pub fn floor(a: Q) i64 { return @divFloor(a.n, a.d); }
    pub fn ceil(a: Q) i64 { return -a.neg().floor(); }
    pub fn str(a: Q) []const u8 { return if (a.d == 1) fmt("{d}", .{a.n}) else fmt("{d}/{d}", .{a.n, a.d}); }
    pub fn approx(a: Q) []const u8 {
        const t = @divTrunc(@as(i64, @intCast(@abs(a.n))) * 2000000 + a.d, 2 * a.d);
        return fmt("{s}{d}.{d:0>6}", .{ if (a.n < 0 and t != 0) "-" else "", @divTrunc(t, 1000000), @mod(t, 1000000) });
    }
};
pub fn parse(s: []const u8) ?Q {
    if (s.len == 0) return null;
    const neg = s[0] == '-';
    const p = s[@intFromBool(neg)..];
    if (p.len == 0) return null;
    var n: i64 = 0; var d: i64 = 1; var sep: u8 = 0; var after: usize = 0;
    for (p, 0..) |c, i| {
        if (c == '.' or c == '/') {
            if (sep != 0 or i == 0 or i + 1 == p.len) return null;
            sep = c; if (c == '/') d = 0;
        } else if (c >= '0' and c <= '9') {
            if (sep == '/') d = d * 10 + c - '0' else n = n * 10 + c - '0';
            if (sep != 0) { after += 1; if (sep == '.') d *= 10; }
        } else return null;
    }
    if (d == 0 or (sep != 0 and after == 0)) return null;
    return Q.init(if (neg) -n else n, d);
}
pub const Bound = struct {
    value: Q = .{}, infinity: i8 = 0,
    pub fn finite(q: Q) Bound { return .{ .value = q }; }
    pub fn cmp(a: Bound, b: Bound) std.math.Order {
        if (a.infinity != b.infinity) return std.math.order(a.infinity, b.infinity);
        return if (a.infinity != 0) .eq else a.value.cmp(b.value);
    }
    pub fn str(a: Bound) []const u8 { return if (a.infinity < 0) "-inf" else if (a.infinity > 0) "inf" else a.value.str(); }
    pub fn shift(a: Bound, q: Q) Bound { return if (a.infinity != 0) a else finite(a.value.plus(q)); }
};
pub fn bound(s: []const u8) ?Bound {
    if (eq(s, "-inf")) return .{ .infinity = -1 };
    if (eq(s, "inf")) return .{ .infinity = 1 };
    return Bound.finite(parse(s) orelse return null);
}
pub fn zero(n: usize) []Q { const a = alloc(Q, n); @memset(a, .{}); return a; }
pub fn read(io: std.Io, path: []const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited); }
pub fn write(io: std.Io, name: []const u8, t: Text) !void { try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = t.data.items }); }
