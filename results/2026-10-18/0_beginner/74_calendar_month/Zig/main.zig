const std = @import("std");

fn leap(y: u32) bool {
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0);
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names = [_][]const u8{
        "January", "February", "March",     "April",   "May",      "June",
        "July",    "August",   "September", "October", "November", "December",
    };
    const lengths = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    for ([_][2]u32{ .{ 2024, 2 }, .{ 2026, 8 }, .{ 2026, 11 } }, 0..) |p, k| {
        const year = p[0];
        const month = p[1];
        const prior_year = year - 1;
        var days: u32 = 365 * prior_year + prior_year / 4 - prior_year / 100 + prior_year / 400;
        for (1..month) |m|
            days += if (m == 2 and leap(year)) @as(u32, 29) else lengths[m - 1];
        const offset = (days + 1) % 7;
        const last = if (month == 2 and leap(year)) @as(u32, 29) else lengths[month - 1];
        if (k > 0)
            try out.writeByte('\n');
        try out.print("{s} {d}\nSu Mo Tu We Th Fr Sa\n", .{ names[month - 1], year });
        try out.splatByteAll(' ', offset * 3);
        var day: u32 = 1;
        while (day <= last) : (day += 1) {
            try out.print("{d:>2}", .{day});
            if ((offset + day - 1) % 7 == 6 or day == last) {
                try out.writeByte('\n');
            } else {
                try out.writeByte(' ');
            }
        }
    }
    try out.flush();
}
