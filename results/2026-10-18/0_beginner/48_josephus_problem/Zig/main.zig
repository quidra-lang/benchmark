const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for ([_][2]usize{ .{ 7, 3 }, .{ 10, 2 }, .{ 41, 3 } }) |p| {
        var people: [41]usize = undefined;
        for (0..p[0]) |i|
            people[i] = i + 1;
        var len = p[0];
        var index: usize = 0;
        var survivor: usize = 0;
        try out.print("n={d} k={d}:", .{ p[0], p[1] });
        while (len > 0) {
            index = (index + p[1] - 1) % len;
            survivor = people[index];
            try out.print(" {d}", .{ survivor });
            var j = index;
            while (j + 1 < len) : (j += 1)
                people[j] = people[j + 1];
            len -= 1;
        }
        try out.print("\nsurvivor: {d}\n", .{ survivor });
    }
    try out.flush();
}
