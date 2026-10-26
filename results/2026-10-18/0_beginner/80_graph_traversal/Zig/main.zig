const std = @import("std");

fn dfs(graph: *const [9][9]bool, v: usize, visited: *[9]bool, order: *[9]usize, len: *usize) void {
    visited[v] = true;
    order[len.*] = v;
    len.* += 1;
    for (0..9) |u| {
        if (graph[v][u] and !visited[u])
            dfs(graph, u, visited, order, len);
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var graph: [9][9]bool = @splat(@splat(false));
    const edges = [_][2]usize{
        .{ 5, 0 }, .{ 3, 8 }, .{ 7, 2 }, .{ 1, 6 }, .{ 0, 2 },
        .{ 5, 3 }, .{ 7, 5 }, .{ 6, 4 }, .{ 8, 7 },
    };
    for (edges) |e| {
        graph[e[0]][e[1]] = true;
        graph[e[1]][e[0]] = true;
    }
    var visited: [9]bool = @splat(false);
    var order: [9]usize = undefined;
    var len: usize = 0;
    dfs(&graph, 0, &visited, &order, &len);
    try out.writeAll("DFS:");
    for (order[0..len]) |v|
        try out.print(" {d}", .{v});
    try out.writeAll("\nBFS:");
    visited = @splat(false);
    var queue: [9]usize = undefined;
    queue[0] = 0;
    var head: usize = 0;
    var tail: usize = 1;
    visited[0] = true;
    while (head < tail) {
        const v = queue[head];
        head += 1;
        try out.print(" {d}", .{v});
        for (0..9) |u| {
            if (graph[v][u] and !visited[u]) {
                visited[u] = true;
                queue[tail] = u;
                tail += 1;
            }
        }
    }
    visited = @splat(false);
    var components: [9][9]usize = undefined;
    var sizes: [9]usize = undefined;
    var count: usize = 0;
    for (0..9) |v| {
        if (!visited[v]) {
            len = 0;
            dfs(&graph, v, &visited, &components[count], &len);
            sizes[count] = len;
            std.mem.sort(usize, components[count][0..len], {}, std.sort.asc(usize));
            count += 1;
        }
    }
    try out.print("\ncomponents: {d}\n", .{count});
    for (0..count) |i| {
        try out.print("component {d}:", .{i + 1});
        for (components[i][0..sizes[i]]) |v|
            try out.print(" {d}", .{v});
        try out.writeByte('\n');
    }
    try out.flush();
}
