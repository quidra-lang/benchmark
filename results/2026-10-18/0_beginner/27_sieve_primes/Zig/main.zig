const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var prime: [201]bool = @splat(true);
    prime[0] = false;
    prime[1] = false;
    for (2..201) |p| {
        if (prime[p]) {
            var m = p * 2;
            while (m <= 200) : (m += p)
                prime[m] = false;
        }
    }
    const count = std.mem.countScalar(bool, &prime, true);
    try out.print("count: {d}\n", .{count});
    var printed: usize = 0;
    for (2..201) |p| {
        if (prime[p]) {
            if (printed % 10 > 0)
                try out.writeByte(' ');
            try out.print("{d}", .{p});
            printed += 1;
            if (printed % 10 == 0 or printed == count)
                try out.writeByte('\n');
        }
    }
    try out.flush();
}
