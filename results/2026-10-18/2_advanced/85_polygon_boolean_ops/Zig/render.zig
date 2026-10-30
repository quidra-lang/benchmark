const r = @import("rational.zig");
const rings = @import("rings.zig");
pub const Drawing = struct { lines: r.Lines, counts: [4]usize };
pub fn grid(polygons: rings.Polygons, operands: ?[2]rings.Sequence, x0: i64, y0: i64, width: i64,
     height: i64, columns: usize, rows: usize) Drawing {
    var out: Drawing = .{ .lines = .{}, .counts = @splat(0) };
    for (0..rows) |row| {
        const cells = r.alloc(u8, columns);
        const y = r.Fraction.integer(y0).add(r.Fraction.init((2 * r.n(rows - 1 - row) + 1) * height, 2));
        for (cells, 0..) |*character, column| {
            const x = r.Fraction.integer(x0).add(r.Fraction.init((2 * r.n(column) + 1) * width, 2));
            const point: r.Point = .{ .x = x, .y = y };
            var inside = false;
            for (polygons) |polygon| if (rings.interior(polygon, point)) {
                inside = !inside;
            };
            if (inside) character.* = '#' else if (operands) |pair| {
                const first = rings.interior(pair[0], point);
                const second = rings.interior(pair[1], point);
                character.* = if (first and second) '+' else if (first) 'a' else if (second) 'b' else '.';
            } else character.* = '.';
            switch (character.*) {
                '#' => out.counts[0] += 1,
                'a' => out.counts[1] += 1,
                'b' => out.counts[2] += 1,
                '+' => out.counts[3] += 1,
                else => {},
            }
        }
        out.lines.add("{s}", .{cells});
    }
    return out;
}
