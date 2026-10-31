const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const numbers = [_][]const u8{
        "688126340316",
        "0128469655154",
        "92181914514156",
        "177332430060552",
        "7982377590420309",
        "9884593615513906",
    };
    for (numbers) |number| {
        var sum: u32 = 0;
        for (number, 0..) |c, i| {
            var v: u32 = c - '0';
            if ((number.len - i) % 2 == 0) {
                v *= 2;
                if (v > 9)
                    v -= 9;
            }
            sum += v;
        }
        try out.print("{s}: ", .{number});
        if (sum % 10 == 0) {
            try out.writeAll("valid\n");
        } else {
            const without = sum - (number[number.len - 1] - '0');
            const expected = (10 - without % 10) % 10;
            try out.print("invalid (expected check digit {d})\n", .{expected});
        }
    }
    try out.flush();
}
