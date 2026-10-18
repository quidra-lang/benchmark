const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var a = [_]i32{ 52, 17, 38, 9, 61, 38, 24, 45 };
    var total: usize = 0;
    for (1..8) |i| {
        const v = a[i];
        var j = i;
        var shifts: usize = 0;
        while (j > 0 and a[j - 1] > v) {
            a[j] = a[j - 1];
            j -= 1;
            shifts += 1;
        }
        a[j] = v;
        total += shifts;
        try out.print("i={d} shifts={d}:", .{ i, shifts });
        for (a) |x|
            try out.print(" {d}", .{ x });
        try out.writeByte('\n');
    }
    try out.print("total shifts: {d}\n", .{ total });
    try out.flush();
}
