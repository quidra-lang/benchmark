const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for ([_]u64{ 84, 9973, 15625, 1001, 123456, 48000, 999958, 999999 }) |n| {
        try out.print("{d} = ", .{ n });
        var remaining = n;
        var d: u64 = 2;
        var first = true;
        while (d * d <= remaining) : (d += 1) {
            var exponent: u32 = 0;
            while (remaining % d == 0) {
                remaining /= d;
                exponent += 1;
            }
            if (exponent > 0) {
                if (!first)
                    try out.writeAll(" * ");
                first = false;
                try out.print("{d}", .{ d });
                if (exponent > 1)
                    try out.print("^{d}", .{ exponent });
            }
        }
        if (remaining > 1) {
            if (!first)
                try out.writeAll(" * ");
            try out.print("{d}", .{ remaining });
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
