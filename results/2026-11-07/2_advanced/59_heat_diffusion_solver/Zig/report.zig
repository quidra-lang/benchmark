const std = @import("std");
const c = @import("mesh.zig");
pub fn real(value: f64, digits: usize) []const u8 {
    const text = switch (digits) {
        2 => c.fmt("{d:.2}", .{value}),
        3 => c.fmt("{d:.3}", .{value}),
        4 => c.fmt("{d:.4}", .{value}),
        6 => c.fmt("{d:.6}", .{value}),
        else => unreachable,
    };
    if (text.len > 0 and text[0] == '-') {
        var zero = true;
        for (text[1..]) |ch| {
            if (ch != '0' and ch != '.') zero = false;
        }
        if (zero) return text[1..];
    }
    return text;
}
pub fn time(milliseconds: i64) []const u8 {
    return c.fmt("{d}.{d:0>3}", .{ @divTrunc(milliseconds, 1000), @mod(milliseconds, 1000) });
}
pub fn hottest(field: []const f64) usize {
    var out: usize = 0;
    for (field, 0..) |value, i| if (value > field[out]) {
        out = i;
    };
    return out;
}
pub fn summary(prefix: []const u8, mesh: c.Mesh, field: []const f64) []const u8 {
    var minimum = field[0];
    var total: f64 = 0;
    for (field) |value| {
        minimum = @min(minimum, value);
        total += value;
    }
    const point = hottest(field);
    return c.fmt("{s} max {s} at {s} min {s} mean {s}", .{ prefix, real(field[point], 2), mesh.coordinates(point),
         real(minimum, 2), real(total / c.f(mesh.count), 2) });
}
pub fn fieldLines(lines: *c.Lines, mesh: c.Mesh, field: []const f64) void {
    for (0..mesh.height) |row| {
        var text: c.Text = .{};
        for (0..mesh.width) |column| text.add("{s}{s}", .{ if (column > 0) " " else "", real(field[mesh.cell(row,
             column)], 2) });
        lines.add("{s}", .{text.value()});
    }
}
pub fn isotherms(lines: *c.Lines, prefix: []const u8, mesh: c.Mesh, field: []const f64, bands: []const f64) void {
    var counts = [_]usize{0} ** 10;
    const digits = c.alloc(usize, field.len);
    @memset(digits, 0);
    for (field, 0..) |value, point| {
        for (bands) |boundary| digits[point] += @intFromBool(boundary <= value);
        counts[digits[point]] += 1;
    }
    var heading: c.Text = .{};
    heading.add("{s} counts", .{prefix});
    for (counts[0 .. bands.len + 1]) |count| heading.add(" {d}", .{count});
    lines.add("{s}", .{heading.value()});
    const peak = hottest(field);
    for (0..mesh.height) |row| {
        var text: c.Text = .{};
        for (0..mesh.width) |column| {
            const point = mesh.cell(row, column);
            text.add("{c}", .{if (point == peak) @as(u8, '*') else @as(u8, @intCast('0' + digits[point]))});
        }
        lines.add("{s}", .{text.value()});
    }
}
pub fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
