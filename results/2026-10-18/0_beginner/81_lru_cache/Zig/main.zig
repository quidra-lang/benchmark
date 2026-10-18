const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var cache: [3]u8 = undefined;
    var len: usize = 0;
    var hits: u32 = 0;
    var misses: u32 = 0;
    for ("BACBDABEADDCAEB") |key| {
        const found = std.mem.findScalar(u8, cache[0..len], key);
        try out.print("{c}: ", .{ key });
        var position: usize = 0;
        if (found) |i| {
            hits += 1;
            position = i;
            try out.writeAll("hit");
        } else {
            misses += 1;
            try out.writeAll("miss");
            if (len == 3) {
                try out.print(", evict {c}", .{ cache[2] });
                position = 2;
            } else {
                position = len;
                len += 1;
            }
        }
        std.mem.copyBackwards(u8, cache[1..position + 1], cache[0..position]);
        cache[0] = key;
        try out.writeAll(" [");
        for (cache[0..len], 0..) |c, i| {
            if (i > 0)
                try out.writeByte(' ');
            try out.writeByte(c);
        }
        try out.writeAll("]\n");
    }
    try out.print("hits: {d} misses: {d}\n", .{ hits, misses });
    try out.flush();
}
