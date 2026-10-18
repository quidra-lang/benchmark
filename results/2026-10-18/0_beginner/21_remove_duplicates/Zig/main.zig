const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const values = [_]i32{ 12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9 };
    var unique: [values.len]i32 = undefined;
    var count: usize = 0;
    for (values) |v| {
        var found = false;
        for (unique[0..count]) |u| {
            if (u == v) {
                found = true;
                break;
            }
        }
        if (!found) {
            unique[count] = v;
            count += 1;
        }
    }
    for (unique[0..count], 0..) |v, i| {
        if (i > 0)
            try out.writeByte(' ');
        try out.print("{d}", .{ v });
    }
    try out.print("\nremoved: {d}\n", .{ values.len - count });
    try out.flush();
}
