const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const initial = [_][]const u8{
        "#############",
        "#S..#.......#",
        "#.#.#.###.#.#",
        "#.#...#...#.#",
        "#.###.#.###.#",
        "#...#...#...#",
        "###.#####.#.#",
        "#.......#..G#",
        "#############"
    };
    var maze: [117]u8 = undefined;
    var start: usize = 0;
    var goal: usize = 0;
    for (0..117) |i| {
        maze[i] = initial[i / 13][i % 13];
        if (maze[i] == 'S')
            start = i;
        if (maze[i] == 'G')
            goal = i;
    }
    var parent = [_]i32{ -1 } ** 117;
    parent[start] = @intCast(start);
    var queue: [117]usize = undefined;
    queue[0] = start;
    var head: usize = 0;
    var tail: usize = 1;
    const directions = [_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };
    while (head < tail) {
        const v = queue[head];
        head += 1;
        if (v == goal)
            break;
        for (directions) |d| {
            const r = @as(i32, @intCast(v / 13)) + d[0];
            const c = @as(i32, @intCast(v % 13)) + d[1];
            if (r < 0 or r >= 9 or c < 0 or c >= 13)
                continue;
            const u: usize = @intCast(r * 13 + c);
            if (maze[u] != '#' and parent[u] == - 1) {
                parent[u] = @intCast(v);
                queue[tail] = u;
                tail += 1;
            }
        }
    }
    var current = goal;
    var steps: usize = 0;
    while (current != start) {
        if (current != goal)
            maze[current] = '*';
        current = @intCast(parent[current]);
        steps += 1;
    }
    try out.print("steps: {d}\n", .{ steps });
    for (0..9) |r|
        try out.print("{s}\n", .{ maze[r * 13..r * 13 + 13] });
    try out.flush();
}
