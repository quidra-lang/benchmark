const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var graph: [7][7]u32 = @splat(@splat(0));
    const edges = [_][3]usize{
        .{ 0, 1, 7 }, .{ 0, 2, 3 }, .{ 0, 3, 9 }, .{ 1, 2, 2 }, .{ 2, 4, 6 }, .{ 1, 3, 3 },
        .{ 3, 4, 4 }, .{ 3, 5, 5 }, .{ 4, 5, 3 }, .{ 4, 6, 8 }, .{ 5, 6, 4 },
    };
    for (edges) |e| {
        graph[e[0]][e[1]] = @intCast(e[2]);
        graph[e[1]][e[0]] = @intCast(e[2]);
    }
    var distance: [7]u32 = @splat(1000000);
    distance[0] = 0;
    var previous: [7]usize = @splat(0);
    var done: [7]bool = @splat(false);
    for (0..7) |_| {
        var best: ?usize = null;
        for (0..7) |i| {
            if (!done[i] and (best == null or distance[i] < distance[best.?]))
                best = i;
        }
        const u = best.?;
        done[u] = true;
        for (0..7) |v| {
            if (graph[u][v] > 0 and distance[u] + graph[u][v] < distance[v]) {
                distance[v] = distance[u] + graph[u][v];
                previous[v] = u;
            }
        }
    }
    for (0..7) |v| {
        try out.print("{c}: distance={d} path=", .{ 'A' + @as(u8, @intCast(v)), distance[v] });
        var path: [7]usize = undefined;
        var len: usize = 0;
        var u = v;
        while (true) {
            path[len] = u;
            len += 1;
            if (u == 0)
                break;
            u = previous[u];
        }
        std.mem.reverse(usize, path[0..len]);
        for (path[0..len], 0..) |vertex, i| {
            if (i > 0)
                try out.writeByte('-');
            try out.writeByte('A' + @as(u8, @intCast(vertex)));
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
