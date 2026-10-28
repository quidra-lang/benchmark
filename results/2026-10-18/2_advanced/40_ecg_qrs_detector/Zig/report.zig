const c = @import("signal_io.zig");
pub fn rdiv(a: i64, b: i64) i64 {
    return @divFloor(2 * a + b, 2 * b);
}
pub fn decimal2(value: i64) []const u8 {
    const magnitude = @abs(value);
    return c.fmt("{s}{d}.{d:0>2}", .{ if (value < 0) "-" else "", magnitude / 100, magnitude % 100 });
}
pub fn decimal4(value: i64) []const u8 {
    return c.fmt("{d}.{d:0>4}", .{ @divFloor(value, 10000), @mod(value, 10000) });
}
pub fn reduced(a: i64, b: i64) []const u8 {
    var x = a;
    var y = b;
    while (y != 0) {
        const remainder = @mod(x, y);
        x = y;
        y = remainder;
    }
    return c.fmt("{d}/{d}", .{ @divFloor(a, x), @divFloor(b, x) });
}
pub fn ratio(a: i64, b: i64) []const u8 {
    return if (b == 0) c.fmt("{d}/{d} none", .{ a, b }) else c.fmt("{d}/{d} reduced={s} percent={s}",
         .{ a, b, reduced(a, b), decimal2(rdiv(10000 * a, b)) });
}
pub fn optionalNumber(value: ?i64) []const u8 {
    return if (value) |present| c.fmt("{d}", .{present}) else "-";
}
