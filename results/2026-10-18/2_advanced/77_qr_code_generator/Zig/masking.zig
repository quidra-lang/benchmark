const m = @import("matrix.zig");
const b = @import("bitstream.zig");
pub fn condition(mask: i64, x: i64, y: i64) bool {
    return switch (mask) {
        0 => @mod(x + y, 2) == 0,
        1 => @mod(y, 2) == 0,
        2 => @mod(x, 3) == 0,
        3 => @mod(x + y, 3) == 0,
        4 => @mod(@divTrunc(y, 2) + @divTrunc(x, 3), 2) == 0,
        5 => @mod(x * y, 2) + @mod(x * y, 3) == 0,
        6 => @mod(@mod(x * y, 2) + @mod(x * y, 3), 2) == 0,
        else => @mod(@mod(x + y, 2) + @mod(x * y, 3), 2) == 0,
    };
}
pub fn apply(symbol: m.Matrix, positions: m.Positions, mask: i64) m.Matrix {
    var out = symbol;
    for (positions) |point| if (condition(mask, point.x, point.y)) out.flip(point.x, point.y);
    return out;
}
pub const Penalty = struct {
    n1: i64 = 0,
    n2: i64 = 0,
    n3: i64 = 0,
    n4: i64 = 0,
    pub fn total(self: Penalty) i64 {
        return self.n1 + self.n2 + self.n3 + self.n4;
    }
};
pub fn penalties(symbol: *const m.Matrix) Penalty {
    var out: Penalty = .{};
    const n = symbol.size;
    for (0..2) |orientation| for (0..b.u(n)) |fixed| {
        var row: [57]u8 = @splat(0);
        for (0..b.u(n)) |i| row[i] = if (orientation == 0) symbol.cells[fixed][i] else symbol.cells[i][fixed];
        var run: i64 = 1;
        for (1..b.u(n)) |i| {
            if (row[i] == row[i - 1]) run += 1 else {
                if (run >= 5) out.n1 += run - 2;
                run = 1;
            }
        }
        if (run >= 5) out.n1 += run - 2;
        for (0..b.u(n - 10)) |i| {
            var pattern: i64 = 0;
            for (0..11) |j| pattern = pattern * 2 + row[i + j];
            if (pattern == 0x5d0 or pattern == 0x05d) out.n3 += 40;
        }
    };
    var dark: i64 = 0;
    for (0..b.u(n)) |y| for (0..b.u(n)) |x| {
        const value = symbol.cells[y][x];
        dark += value;
        if (x + 1 < b.u(n) and y + 1 < b.u(n) and value == symbol.cells[y][x + 1] and value == symbol.cells[y + 1][x] and value == symbol.cells[y + 1][x + 1]) out.n2 += 3;
    };
    out.n4 = 10 * @divTrunc(b.n(@abs(20 * dark - 10 * n * n)), n * n);
    return out;
}
