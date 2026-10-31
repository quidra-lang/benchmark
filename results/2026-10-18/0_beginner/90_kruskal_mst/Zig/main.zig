const std = @import("std");

fn less(_: void, a: [3]usize, b: [3]usize) bool {
    return a[2] < b[2];
}

fn find(parent: *[8]usize, initial: usize) usize {
    var v = initial;
    while (parent[v] != v) {
        parent[v] = parent[parent[v]];
        v = parent[v];
    }
    return v;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var edges = [_][3]usize{
        .{ 0, 1, 7 },  .{ 2, 0, 4 },  .{ 1, 2, 9 },  .{ 1, 3, 14 }, .{ 3, 2, 6 },  .{ 2, 4, 3 },
        .{ 4, 3, 5 },  .{ 5, 3, 11 }, .{ 4, 6, 16 }, .{ 6, 5, 8 },  .{ 7, 5, 12 }, .{ 6, 7, 2 },
        .{ 7, 4, 10 },
    };
    std.mem.sort([3]usize, &edges, {}, less);
    var parent: [8]usize = undefined;
    for (0..8) |i|
        parent[i] = i;
    var accepted: usize = 0;
    var skipped: usize = 0;
    var total: usize = 0;
    for (edges) |e| {
        const a = find(&parent, e[0]);
        const b = find(&parent, e[1]);
        if (a == b) {
            skipped += 1;
            continue;
        }
        parent[a] = b;
        accepted += 1;
        total += e[2];
        try out.print("{c}-{c} {d}\n", .{
            'A' + @as(u8, @intCast(@min(e[0], e[1]))),
            'A' + @as(u8, @intCast(@max(e[0], e[1]))),
            e[2],
        });
        if (accepted == 7)
            break;
    }
    try out.print("total weight: {d}\nskipped: {d}\n", .{ total, skipped });
    try out.flush();
}
