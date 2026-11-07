const b = @import("bitstream.zig");
const Matrix = @import("matrix.zig").Matrix;
pub fn symbolLines(symbol: *const Matrix) b.Lines {
    var lines: b.Lines = .{};
    for (0..b.u(symbol.size)) |y| {
        const row = b.alloc(u8, b.u(symbol.size));
        for (row, 0..) |*pixel, x| pixel.* = if (symbol.cells[y][x] != 0) '#' else '.';
        lines.add("{s}", .{row});
    }
    return lines;
}
pub fn pbmText(symbol: *const Matrix, quiet: i64, scale: i64) []const u8 {
    const width = (symbol.size + 2 * quiet) * scale;
    var out: b.Text = .{};
    out.add("P1\n{d} {d}\n", .{ width, width });
    for (0..b.u(width)) |py| {
        const row = b.alloc(u8, b.u(width));
        for (row, 0..) |*pixel, px| {
            const x = @divTrunc(b.n(px), scale) - quiet;
            const y = @divTrunc(b.n(py), scale) - quiet;
            pixel.* = if (x >= 0 and x < symbol.size and y >= 0 and y < symbol.size and symbol.at(x,
                 y) != 0) '1' else '0';
        }
        out.add("{s}\n", .{row});
    }
    return out.value();
}
