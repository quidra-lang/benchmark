const std = @import("std");
const d = @import("data_io.zig");
pub fn real(value: f64, comptime digits: usize) []const u8 {
    const text = d.fmt("{d:." ++ std.fmt.comptimePrint("{d}", .{digits}) ++ "}", .{value});
    if (text.len > 0 and text[0] == '-') {
        var zero = true;
        for (text[1..]) |c| {
            if (c != '0' and c != '.') zero = false;
        }
        if (zero) return text[1..];
    }
    return text;
}
pub fn curvePlot(cases: []const i64, fitted: []const f64) d.Lines {
    var maximum = cases[0];
    for (cases) |value| maximum = @max(maximum, value);
    const width = d.fmt("{d}", .{maximum}).len;
    var observed: [70]usize = undefined;
    var predicted: [70]usize = undefined;
    var day: [70]usize = undefined;
    for (0..70) |x| {
        day[x] = 1 + x * (cases.len - 1) / 69;
        observed[x] = @min(19, d.u(@divTrunc(20 * cases[day[x] - 1], maximum)));
        predicted[x] = @min(19, @as(usize, @intFromFloat(@floor(20 * fitted[day[x] - 1] / d.f(maximum)))));
    }
    var out: d.Lines = .{};
    out.add("plot observed o fitted * both # days 1 {d} max {d}", .{ cases.len, maximum });
    var y: usize = 20;
    while (y > 0) {
        y -= 1;
        var row: d.Text = .{};
        const label = d.fmt("{d}", .{@divTrunc(maximum * d.n(y), 20)});
        for (0..width - label.len) |_| row.add(" ", .{});
        row.add("{s} |", .{label});
        for (0..70) |x| row.add("{c}", .{@as(u8, if (observed[x] == y) (if (predicted[x] == y) '#' else 'o') else (if (predicted[x] == y) '*' else '.'))});
        out.add("{s}", .{row.value()});
    }
    var axis: d.Text = .{};
    for (0..width + 1) |_| axis.add(" ", .{});
    axis.add("+", .{});
    for (0..70) |x| axis.add("{c}", .{@as(u8, if (x % 10 == 0) '+' else '-')});
    out.add("{s}", .{axis.value()});
    var labels: [70]u8 = [_]u8{' '} ** 70;
    var x: usize = 0;
    while (x <= 60) : (x += 10) {
        const label = d.fmt("{d}", .{day[x]});
        @memcpy(labels[x..][0..label.len], label);
    }
    var length: usize = 70;
    while (length > 0 and labels[length - 1] == ' ') length -= 1;
    var row: d.Text = .{};
    for (0..width + 2) |_| row.add(" ", .{});
    row.add("{s}", .{labels[0..length]});
    out.add("{s}", .{row.value()});
    return out;
}
