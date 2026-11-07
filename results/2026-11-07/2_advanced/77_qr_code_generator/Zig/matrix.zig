const std = @import("std");
const b = @import("bitstream.zig");
pub const Point = struct { x: i64, y: i64 };
pub const Positions = []const Point;
pub const Matrix = struct {
    size: i64 = 0,
    cells: [57][57]u8 = std.mem.zeroes([57][57]u8),
    pub fn at(self: *const Matrix, x: i64, y: i64) u8 {
        return self.cells[b.u(y)][b.u(x)];
    }
    pub fn set(self: *Matrix, x: i64, y: i64, value: i64) void {
        self.cells[b.u(y)][b.u(x)] = @intCast(value);
    }
    pub fn flip(self: *Matrix, x: i64, y: i64) void {
        self.cells[b.u(y)][b.u(x)] ^= 1;
    }
};
pub const data: u8 = 0;
pub const function: u8 = 1;
pub const format: u8 = 2;
pub const version_area: u8 = 3;
fn bitLength(value: i64) i64 {
    var n = value;
    var count: i64 = 0;
    while (n != 0) {
        n >>= 1;
        count += 1;
    }
    return count;
}
fn remainder(value: i64, divisor: i64) i64 {
    var n = value;
    const degree = bitLength(divisor);
    while (bitLength(n) >= degree) n ^= divisor << @intCast(bitLength(n) - degree);
    return n;
}
pub fn formatInformation(level: usize, mask: i64) i64 {
    const indicators = [_]i64{ 1, 0, 3, 2 };
    const shifted = (8 * indicators[level] + mask) << 10;
    return (shifted + remainder(shifted, 0x537)) ^ 0x5412;
}
pub fn versionInformation(version: i64) i64 {
    const shifted = version << 12;
    return shifted + remainder(shifted, 0x1f25);
}
pub fn formatPositions(n: i64) [2]Positions {
    var first: std.ArrayList(Point) = .empty;
    var second: std.ArrayList(Point) = .empty;
    for (0..6) |i| b.append(Point, &first, .{ .x = 8, .y = b.n(i) });
    for ([_]Point{ .{ .x = 8, .y = 7 }, .{ .x = 8, .y = 8 }, .{ .x = 7, .y = 8 } }) |point| b.append(Point,
         &first, point);
    for (9..15) |i| b.append(Point, &first, .{ .x = 14 - b.n(i), .y = 8 });
    for (0..8) |i| b.append(Point, &second, .{ .x = n - 1 - b.n(i), .y = 8 });
    for (8..15) |i| b.append(Point, &second, .{ .x = 8, .y = n - 15 + b.n(i) });
    return .{ first.items, second.items };
}
pub fn versionPositions(n: i64) [2]Positions {
    var first: std.ArrayList(Point) = .empty;
    var second: std.ArrayList(Point) = .empty;
    for (0..18) |i| {
        const point: Point = .{ .x = n - 11 + b.n(i % 3), .y = b.n(i / 3) };
        b.append(Point, &first, point);
        b.append(Point, &second, .{ .x = point.y, .y = point.x });
    }
    return .{ first.items, second.items };
}
pub fn writeValue(symbol: *Matrix, positions: Positions, value: i64) void {
    for (positions, 0..) |point, i| symbol.set(point.x, point.y, (value >> @intCast(i)) & 1);
}
pub fn readValue(symbol: *const Matrix, positions: Positions) i64 {
    var value: i64 = 0;
    for (positions, 0..) |point, i| value |= @as(i64, symbol.at(point.x, point.y)) << @intCast(i);
    return value;
}
pub const Geometry = struct {
    symbol: Matrix,
    areas: Matrix,
    order: Positions = &.{},
    indices: [57][57]i64 = @splat(@splat(-1)),
    pub fn functionModules(self: *const Geometry) i64 {
        return self.symbol.size * self.symbol.size - b.n(self.order.len);
    }
};
pub fn readingOrder(areas: *const Matrix) Positions {
    var out: std.ArrayList(Point) = .empty;
    var columns: std.ArrayList(i64) = .empty;
    const n = areas.size;
    var right = n - 1;
    while (right >= 8) : (right -= 2) b.append(i64, &columns, right);
    for ([_]i64{ 5, 3, 1 }) |column| b.append(i64, &columns, column);
    for (columns.items, 0..) |column, pair| for (0..b.u(n)) |row| {
        const y = if (pair % 2 == 0) n - 1 - b.n(row) else b.n(row);
        for ([_]i64{ column, column - 1 }) |x| if (areas.at(x, y) == data) b.append(Point, &out, .{ .x = x, .y = y });
    };
    return out.items;
}
fn set(g: *Geometry, x: i64, y: i64, value: bool, area: u8) void {
    g.symbol.set(x, y, @intFromBool(value));
    g.areas.set(x, y, area);
}
pub fn functionMatrix(version: i64, alignments: b.Words) Geometry {
    const n = 17 + 4 * version;
    var g: Geometry = .{ .symbol = .{ .size = n }, .areas = .{ .size = n } };
    for ([_]Point{ .{ .x = 3, .y = 3 }, .{ .x = n - 4, .y = 3 }, .{ .x = 3, .y = n - 4 } }) |center| {
        var dy: i64 = -4;
        while (dy <= 4) : (dy += 1) {
            var dx: i64 = -4;
            while (dx <= 4) : (dx += 1) {
                const x = center.x + dx;
                const y = center.y + dy;
                const d = @max(@abs(dx), @abs(dy));
                if (x >= 0 and x < n and y >= 0 and y < n) set(&g, x, y, d == 0 or d == 1 or d == 3, function);
            }
        }
    }
    var i: i64 = 8;
    while (i <= n - 9) : (i += 1) {
        set(&g, 6, i, @mod(i, 2) == 0, function);
        set(&g, i, 6, @mod(i, 2) == 0, function);
    }
    if (alignments.len > 0) for (alignments) |cy| for (alignments) |cx| {
        const first = alignments[0];
        const last = alignments[alignments.len - 1];
        if ((cx == first and (cy == first or cy == last)) or (cx == last and cy == first)) continue;
        var dy: i64 = -2;
        while (dy <= 2) : (dy += 1) {
            var dx: i64 = -2;
            while (dx <= 2) : (dx += 1) set(&g, cx + dx, cy + dy, @max(@abs(dx), @abs(dy)) != 1, function);
        }
    };
    set(&g, 8, n - 8, true, function);
    for (formatPositions(n)) |positions| for (positions) |point| set(&g, point.x, point.y, false, format);
    if (version >= 7) for (versionPositions(n)) |positions| {
        for (positions) |point| g.areas.set(point.x, point.y, version_area);
        writeValue(&g.symbol, positions, versionInformation(version));
    };
    g.order = readingOrder(&g.areas);
    for (g.order, 0..) |point, index| g.indices[b.u(point.y)][b.u(point.x)] = b.n(index);
    return g;
}
