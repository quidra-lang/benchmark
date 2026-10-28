const c = @import("dataset.zig");
const estimators = @import("estimators.zig");
pub fn curves(curves_: []const []const estimators.KMRow, maximums: []const i64, params: c.Params) c.Lines {
    const width = params.plot_width;
    const height = params.plot_height;
    const time = params.plot_time;
    const cells = c.alloc(u8, height * width);
    @memset(cells, 0);
    for (curves_, maximums, 0..) |curve, maximum, group| {
        var previous: ?usize = null;
        for (0..width) |column| {
            const t = c.n(column) * @divFloor(time, c.n(width));
            if (t > maximum) break;
            const survival = estimators.rowAt(curve, t).survival;
            const band = @min(height - 1, @as(usize, @intFromFloat(@floor(survival * c.f(height)))));
            const mask = @as(u8, 1) << @as(u3, @intCast(group));
            cells[band * width + column] |= mask;
            if (previous != null and previous.? > band + 1) for (band + 1..previous.?) |q| {
                cells[q * width + column] |= mask;
            };
            previous = band;
        }
    }
    var out: c.Lines = .{};
    out.add("km_plot width {d} height {d} time {d}", .{ width, height, time });
    var legend: c.Text = .{};
    legend.add("legend", .{});
    for (params.groups, 0..) |name, group| legend.add(" {c} {s}", .{ 'A' + @as(u8, @intCast(group)), name });
    out.add("{s}", .{legend.value()});
    const rule = c.alloc(u8, width);
    @memset(rule, '-');
    out.add("   +{s}+", .{rule});
    var remaining = height;
    while (remaining > 0) {
        remaining -= 1;
        const band = remaining;
        const marks = c.alloc(u8, width);
        for (marks, 0..) |*mark, column| {
            const mask = cells[band * width + column];
            if (mask == 0) mark.* = ' ' else if ((mask & (mask - 1)) != 0) mark.* = '*' else {
                var group: usize = 0;
                while ((mask >> @as(u3, @intCast(group))) != 1) group += 1;
                mark.* = 'A' + @as(u8, @intCast(group));
            }
        }
        out.add("{d: >3}|{s}|", .{ 100 * band / height, marks });
    }
    out.add("   +{s}+", .{rule});
    out.add("time 0 to {d} days, {d} days per column", .{ time, @divFloor(time, c.n(width)) });
    return out;
}
