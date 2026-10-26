const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const p = [_][2]i32{
        .{ 12, -7 }, .{ -33, 25 }, .{ 41, 18 },  .{ -8, -44 }, .{ 27, 39 }, .{ -46, -12 },
        .{ 5, 14 },  .{ 36, -29 }, .{ -19, 47 }, .{ -2, 3 },
    };
    var nearest: i32 = std.math.maxInt(i32);
    var farthest: i32 = -1;
    var near_pair: [2]usize = undefined;
    var far_pair: [2]usize = undefined;
    for (0..p.len) |i| {
        for (i + 1..p.len) |j| {
            const dx = p[i][0] - p[j][0];
            const dy = p[i][1] - p[j][1];
            const d = dx * dx + dy * dy;
            if (d < nearest) {
                nearest = d;
                near_pair = .{ i, j };
            }
            if (d > farthest) {
                farthest = d;
                far_pair = .{ i, j };
            }
        }
    }
    try out.print("closest: P{d} P{d} {d:.4}\nfarthest: P{d} P{d} {d:.4}\n", .{
        near_pair[0], near_pair[1], @sqrt(@as(f64, @floatFromInt(nearest))),
        far_pair[0],  far_pair[1],  @sqrt(@as(f64, @floatFromInt(farthest))),
    });
    try out.flush();
}
