const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const board = [_][]const u8{
        "MMONKENBIR",
        "PMTIGERJPL",
        "TGREJEDUZI",
        "SPYUTEJDEC",
        "WKAPSIDLBN",
        "KUVNGSBPRO",
        "RIBSDACBAM",
        "YWVAUAPKAH",
        "KYCGTHHESR",
        "OCCALAOKKR",
    };
    const directions = [_][2]i32{
        .{ 0, 1 },  .{ 1, 1 }, .{ 1, 0 }, .{ 1, -1 }, .{ 0, -1 }, .{ -1, -1 }, .{ -1, 0 },
        .{ -1, 1 },
    };
    const names = [_][]const u8{ "E", "SE", "S", "SW", "W", "NW", "N", "NE" };
    for ([_][]const u8{ "TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT" }) |word| {
        var found = false;
        search: for (0..10) |r| {
            for (0..10) |c| {
                for (directions, 0..) |direction, d| {
                    var matches = true;
                    for (word, 0..) |letter, k| {
                        const rr = @as(i32, @intCast(r)) + direction[0] * @as(i32, @intCast(k));
                        const cc = @as(i32, @intCast(c)) + direction[1] * @as(i32, @intCast(k));
                        if (rr < 0 or rr >= 10 or cc < 0 or cc >= 10 or board[@intCast(rr)][@intCast(cc)] != letter) {
                            matches = false;
                            break;
                        }
                    }
                    if (matches) {
                        try out.print("{s}: ({d}, {d}) {s}\n", .{ word, r, c, names[d] });
                        found = true;
                        break :search;
                    }
                }
            }
        }
        if (!found)
            try out.print("{s}: not found\n", .{word});
    }
    try out.flush();
}
