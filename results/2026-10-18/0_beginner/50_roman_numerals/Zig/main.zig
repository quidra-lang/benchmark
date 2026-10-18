const std = @import("std");

fn romanValue(c: u8) i32 {
    return switch (c) {
        'I' => 1,
        'V' => 5,
        'X' => 10,
        'L' => 50,
        'C' => 100,
        'D' => 500,
        'M' => 1000,
        else => unreachable
    };
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const values = [_]i32{ 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
    const symbols = [_][]const u8{ "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV",
        "I" };
    for ([_]i32{ 9, 14, 49, 94, 444, 1994, 2768, 3999 }) |n| {
        var remaining = n;
        var roman: [32]u8 = undefined;
        var len: usize = 0;
        for (values, symbols) |value, symbol| {
            while (remaining >= value) {
                @memcpy(roman[len..][0..symbol.len], symbol);
                len += symbol.len;
                remaining -= value;
            }
        }
        var decoded: i32 = 0;
        for (roman[0..len], 0..) |c, i| {
            const v = romanValue(c);
            decoded += if (i + 1 < len and v < romanValue(roman[i + 1])) - v else v;
        }
        try out.print("{d} -> {s} -> {d}\n", .{ n, roman[0..len], decoded });
    }
    try out.flush();
}
