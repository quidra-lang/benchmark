const std = @import("std");
const c = @import("predicates.zig");
pub const Grid = [][]u8;
pub fn canvas(width: usize, height: usize) Grid {
    const out = c.alloc([]u8, height);
    for (out) |*row| {
        row.* = c.alloc(u8, width);
        @memset(row.*, ' ');
    }
    return out;
}
pub fn mapPoint(point: c.Point, width: usize, height: usize) c.Pair {
    return .{ .a = c.u(@divFloor(2 * point.x * c.n(width - 1) + 1000, 2000)), .b = height - 1 - c.u(@divFloor(2 * point.y * c.n(height - 1) + 1000,
         2000)) };
}
pub fn mapCenter(point: c.Center, width: usize, height: usize) c.Pair {
    return .{ .a = c.u(@divFloor(2 * point.x * c.n(width - 1) + 1000 * point.d, 2000 * point.d)),
         .b = height - 1 - c.u(@divFloor(2 * point.y * c.n(height - 1) + 1000 * point.d, 2000 * point.d)) };
}
pub fn drawLine(grid: Grid, start: c.Pair, end: c.Pair, character: u8) void {
    var x = c.n(start.a);
    var y = c.n(start.b);
    const dx = @as(i64, @intCast(@abs(c.n(end.a) - x)));
    const dy = -@as(i64, @intCast(@abs(c.n(end.b) - y)));
    const sx: i64 = if (x < c.n(end.a)) 1 else -1;
    const sy: i64 = if (y < c.n(end.b)) 1 else -1;
    var e = dx + dy;
    while (true) {
        grid[c.u(y)][c.u(x)] = character;
        if (x == c.n(end.a) and y == c.n(end.b)) break;
        const e2 = 2 * e;
        if (e2 >= dy) {
            e += dy;
            x += sx;
        }
        if (e2 <= dx) {
            e += dx;
            y += sy;
        }
    }
}
pub fn voronoiPlot(points: []const c.Point, width: usize, height: usize) Grid {
    const out = canvas(width, height);
    const owners = c.alloc([]usize, height);
    for (owners) |*row| row.* = c.alloc(usize, width);
    for (0..height) |r| for (0..width) |column| {
        var best: i64 = 0;
        var owner: usize = 0;
        for (points, 0..) |point, s| {
            const x = (c.n(column) * 1000 - point.x * c.n(width - 1)) * c.n(height - 1);
            const y = (c.n(height - 1 - r) * 1000 - point.y * c.n(height - 1)) * c.n(width - 1);
            const value = x * x + y * y;
            if (s == 0 or value < best) {
                best = value;
                owner = s;
            }
        }
        owners[r][column] = owner;
    };
    for (0..height) |r| for (0..width) |column| {
        if ((column + 1 < width and owners[r][column] != owners[r][column + 1]) or (r + 1 < height and owners[r][column] != owners[r + 1][column])) out[r][column] = '#';
    };
    for (points) |point| {
        const cell = mapPoint(point, width, height);
        out[cell.b][cell.a] = 'o';
    }
    return out;
}
pub fn framed(grid: Grid) c.Lines {
    var out: c.Lines = .{};
    const border = c.alloc(u8, grid[0].len);
    @memset(border, '-');
    out.add("+{s}+", .{border});
    for (grid) |row| out.add("|{s}|", .{row});
    out.add("+{s}+", .{border});
    return out;
}
