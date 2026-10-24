const std = @import("std");

fn topological(out: *std.Io.Writer, names: []const []const u8, edges: []const [2]usize, cycle: bool) std.Io.Writer.Error!void {
    var indegree = [_]usize{ 0 } ** 8;
    var taken = [_]bool{ false } ** 8;
    for (edges) |e|
        indegree[e[1]] += 1;
    try out.writeAll("order: ");
    var count: usize = 0;
    while (true) {
        var best: ?usize = null;
        for (names, 0..) |name, i| {
            if (!taken[i] and indegree[i] == 0) {
                if (best == null or std.mem.order(u8, name, names[best.?]) == .lt)
                    best = i;
            }
        }
        const v = best orelse break;
        if (count > 0)
            try out.writeAll(" -> ");
        try out.writeAll(names[v]);
        count += 1;
        taken[v] = true;
        for (edges) |e| {
            if (e[0] == v)
                indegree[e[1]] -= 1;
        }
    }
    try out.writeByte('\n');
    if (cycle) {
        try out.writeAll("cycle:");
        var remaining: [8][]const u8 = undefined;
        var len: usize = 0;
        for (names, 0..) |name, i| {
            if (!taken[i]) {
                remaining[len] = name;
                len += 1;
            }
        }
        std.mem.sort([]const u8, remaining[0..len], {}, nameLess);
        for (remaining[0..len]) |name|
            try out.print(" {s}", .{ name });
        try out.writeByte('\n');
    }
}

fn nameLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names1 = [_][]const u8{
        "physics",
        "algebra",
        "graphics",
        "programming",
        "statistics",
        "calculus",
        "databases",
        "algorithms"
    };
    const edges1 = [_][2]usize{
        .{ 5, 0 },
        .{ 1, 5 },
        .{ 3, 7 },
        .{ 1, 4 },
        .{ 7, 6 },
        .{ 4, 6 },
        .{ 5, 2 },
        .{ 7, 2 },
        .{ 0, 2 }
    };
    const names2 = [_][]const u8{ "music", "ecology", "art", "geology", "biology", "chemistry" };
    const edges2 = [_][2]usize{ .{ 0, 2 }, .{ 2, 1 }, .{ 4, 5 }, .{ 5, 1 }, .{ 1, 3 }, .{ 3, 5 } };
    try topological(out, &names1, &edges1, false);
    try topological(out, &names2, &edges2, true);
    try out.flush();
}
