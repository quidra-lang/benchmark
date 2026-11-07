const std = @import("std");
const d = @import("instance.zig");
pub const Chart = struct { scale: i64, columns: usize, lines: d.Lines };
fn row(data: *const d.Instance, schedule: d.Schedule, operations: []const usize, critical: []const bool,
     label: []const u8, job_row: bool, scale: i64, columns: usize) []const u8 {
    var text: d.Text = .{};
    text.add("{s}{s} |", .{ label, "    "[0 .. 4 - label.len] });
    for (0..columns) |column| {
        var overlap: i64 = 0;
        var selected: ?usize = null;
        for (operations) |id| {
            const amount = @min(schedule.finish[id], d.n(column + 1) * scale) - @max(schedule.start[id], d.n(column) * scale);
            if (amount > overlap or (amount == overlap and amount > 0 and (selected == null or schedule.start[id] < schedule.start[selected.?]))) {
                overlap = amount;
                selected = id;
            }
        }
        var mark: u8 = '.';
        if (selected) |id| {
            const op = data.operations[id];
            mark = if (job_row) '0' + @as(u8, @intCast((op.machine + 1) % 10)) else @as(u8, if (critical[id]) 'a' else 'A') + @as(u8,
                 @intCast(op.job - 1));
        }
        text.add("{c}", .{mark});
    }
    text.add("|", .{});
    return text.value();
}
pub fn gantt(data: *const d.Instance, schedule: d.Schedule, path: []const usize, width: usize) Chart {
    var scale: i64 = 0;
    var power: i64 = 1;
    while (scale == 0) : (power *= 10) for ([_]i64{ 1, 2, 5 }) |multiplier| {
        const value = power * multiplier;
        if (@divTrunc(schedule.makespan + value - 1, value) <= d.n(width)) {
            scale = value;
            break;
        }
    };
    const columns = d.u(@divTrunc(schedule.makespan + scale - 1, scale));
    var lines: d.Lines = .{};
    var time: d.Text = .{};
    time.add("time", .{});
    var column: usize = 0;
    while (column < columns) : (column += 10) {
        while (time.value().len < 6 + column) time.add(" ", .{});
        time.add("{d}", .{d.n(column) * scale});
    }
    lines.add("{s}", .{time.value()});
    var rule: d.Text = .{};
    rule.add("      ", .{});
    for (0..columns) |index| rule.add("{c}", .{@as(u8, if (index % 10 == 0) '+' else '-')});
    lines.add("{s}", .{rule.value()});
    const critical = d.alloc(bool, data.operations.len);
    @memset(critical, false);
    for (path) |id| critical[id] = true;
    for (schedule.order, 1..) |operations, machine| lines.add("{s}", .{row(data, schedule, operations,
         critical, d.fmt("M{d}", .{machine}), false, scale, columns)});
    var busy: d.Text = .{};
    busy.add("busy |", .{});
    for (0..columns) |index| {
        var count: usize = 0;
        for (data.operations, 0..) |_, id| if (schedule.start[id] <= d.n(index) * scale and d.n(index) * scale < schedule.finish[id]) {
            count += 1;
        };
        busy.add("{c}", .{@as(u8, if (count == 10) 'X' else '0' + @as(u8, @intCast(count)))});
    }
    busy.add("|", .{});
    lines.add("{s}", .{busy.value()});
    for (data.jobs) |job| lines.add("{s}", .{row(data, schedule, job.operations, critical, d.fmt("J{d}",
         .{job.number}), true, scale, columns)});
    return .{ .scale = scale, .columns = columns, .lines = lines };
}
