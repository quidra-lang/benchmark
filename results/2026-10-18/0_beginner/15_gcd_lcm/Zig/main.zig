const std = @import("std");

fn gcd(first: u64, second: u64) u64 {
    var a = first;
    var b = second;
    while (b != 0) {
        const r = a % b;
        a = b;
        b = r;
    }
    return a;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const pairs = [_][2]u64{
        .{ 48, 180 },
        .{ 1071, 462 },
        .{ 7, 91 },
        .{ 13, 97 },
        .{ 36288, 98280 }
    };
    for (pairs) |p| {
        const g = gcd(p[0], p[1]);
        const l = (p[0] / g) * p[1];
        try out.print("gcd({d}, {d}) = {d}, lcm({d}, {d}) = {d}\n", .{ p[0], p[1], g, p[0], p[1], l });
    }
    try out.flush();
}
