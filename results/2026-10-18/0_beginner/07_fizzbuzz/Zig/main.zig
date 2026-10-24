const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (1..31) |number| {
        if (number % 15 == 0) {
            try out.writeAll("FizzBuzz\n");
        } else if (number % 3 == 0) {
            try out.writeAll("Fizz\n");
        } else if (number % 5 == 0) {
            try out.writeAll("Buzz\n");
        } else {
            try out.print("{d}\n", .{ number });
        }
    }
    try out.flush();
}
