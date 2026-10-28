const c = @import("dataset.zig");
pub const Grid = [][]u8;
pub const Cell = struct { row: usize, column: usize };
pub fn grid(height: usize, width: usize) Grid {
    const out = c.alloc([]u8, height);
    for (out) |*row| {
        row.* = c.alloc(u8, width);
        @memset(row.*, ' ');
    }
    return out;
}
pub fn framed(source: Grid) c.Lines {
    var out: c.Lines = .{};
    const border = c.alloc(u8, source[0].len);
    @memset(border, '-');
    out.add("+{s}+", .{border});
    for (source) |row| out.add("|{s}|", .{row});
    out.add("+{s}+", .{border});
    return out;
}
fn index(fraction: f64, size: usize) usize {
    return @min(@as(usize, @intFromFloat(@floor(fraction * c.f(size)))), size - 1);
}
pub fn biplotCell(x: f64, y: f64, xlimit: f64, ylimit: f64, width: usize, height: usize) Cell {
    return .{ .row = index((ylimit - y) / (2 * ylimit), height), .column = index((x + xlimit) / (2 * xlimit), width) };
}
pub fn circleCell(x: f64, y: f64, radius: usize) Cell {
    return .{ .row = c.u(c.n(radius / 2 + 1) - @as(i64, @intFromFloat(@floor(y * c.f(radius / 2) + 0.5)))),
         .column = c.u(c.n(radius + 1) + @as(i64, @intFromFloat(@floor(x * c.f(radius) + 0.5)))) };
}
pub fn diagnosticCell(t2: f64, spe: f64, xlimit: f64, ylimit: f64, width: usize, height: usize) Cell {
    return .{ .row = height - 1 - index(spe / ylimit, height), .column = index(t2 / xlimit, width) };
}
fn sign(value: i64) i64 {
    return if (value > 0) 1 else if (value < 0) -1 else 0;
}
pub fn shaftCharacter(origin: Cell, tip: Cell) u8 {
    const dr = c.n(tip.row) - c.n(origin.row);
    const dc = c.n(tip.column) - c.n(origin.column);
    return if (2 * @abs(dr) <= @abs(dc)) '-' else if (2 * @abs(dc) <= @abs(dr)) '|' else if (dc * dr < 0) '/' else '\\';
}
pub fn shaftCells(source: Grid, origin: Cell, tip: Cell) void {
    const dr = c.n(tip.row) - c.n(origin.row);
    const dc = c.n(tip.column) - c.n(origin.column);
    const steps = @max(@abs(dc), @abs(dr));
    if (steps < 2) return;
    for (1..steps) |s| {
        const r = c.u(c.n(origin.row) + sign(dr) * @as(i64, @intCast((2 * s * @abs(dr) + steps) / (2 * steps))));
        const column = c.u(c.n(origin.column) + sign(dc) * @as(i64, @intCast((2 * s * @abs(dc) + steps) / (2 * steps))));
        source[r][column] = shaftCharacter(origin, tip);
    }
}
pub fn screeLine(length: usize, kaiser: usize, broken: usize, width: usize) []const u8 {
    const out = c.alloc(u8, width + 2);
    out[0] = '|';
    for (1..width + 1) |position| out[position] = if (position == broken) 'o' else if (position == kaiser) ':' else if (position <= length) '#' else ' ';
    out[width + 1] = '|';
    return out;
}
