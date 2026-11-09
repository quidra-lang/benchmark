const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const values = [_]u32{ 7, 98000, 4096, 50301, 2718281, 123456789 };
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (values) |original| {
        var remaining = original;
        var digits: u32 = 0;
        var sum: u32 = 0;
        var reversed: u32 = 0;
        while (remaining > 0) : (remaining /= 10) {
            const digit = remaining % 10;
            digits += 1;
            sum += digit;
            reversed = reversed * 10 + digit;
        }
        try out.print("{d}: digits={d} sum={d} reversed={d}\n", .{ original, digits, sum, reversed });
    }
    try out.flush();
}
