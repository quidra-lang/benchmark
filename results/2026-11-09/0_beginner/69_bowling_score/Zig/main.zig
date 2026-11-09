const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const games = [_][]const u32{
        &.{ 8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2 },
        &.{ 3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5 },
        &.{ 5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5 },
        &.{ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10 },
        &.{ 10, 9, 1, 10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10 },
    };
    for (games, 0..) |rolls, g| {
        var index: usize = 0;
        var total: u32 = 0;
        try out.print("game {d}:", .{g + 1});
        for (0..10) |frame| {
            if (frame == 9) {
                for (rolls[index..]) |v|
                    total += v;
            } else if (rolls[index] == 10) {
                total += 10 + rolls[index + 1] + rolls[index + 2];
                index += 1;
            } else {
                const pair = rolls[index] + rolls[index + 1];
                total += pair;
                if (pair == 10)
                    total += rolls[index + 2];
                index += 2;
            }
            try out.print(" {d}", .{total});
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
