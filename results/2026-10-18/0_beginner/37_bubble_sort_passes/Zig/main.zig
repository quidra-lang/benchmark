const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var a = [_]i32{ 27, 64, 13, 88, 41, 5, 72, 36 };
    var total: usize = 0;
    for (1..8) |pass| {
        var swapped = false;
        for (0..8 - pass) |j| {
            if (a[j] > a[j + 1]) {
                const t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
                total += 1;
                swapped = true;
            }
        }
        try out.print("pass {d}:", .{ pass });
        for (a) |v|
            try out.print(" {d}", .{ v });
        try out.writeByte('\n');
        if (!swapped)
            break;
    }
    try out.print("swaps: {d}\n", .{ total });
    try out.flush();
}
