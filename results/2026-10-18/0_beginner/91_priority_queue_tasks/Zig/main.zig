const std = @import("std");

const Task = struct { name: []const u8, priority: u32, sequence: usize };

fn compare(_: void, a: Task, b: Task) std.math.Order {
    return if (a.priority != b.priority)
        std.math.order(a.priority, b.priority)
    else
        std.math.order(a.sequence, b.sequence);
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const operations = [_][]const u8{
        "add email 3",
        "add backup 5",
        "add deploy 1",
        "run",
        "add report 3",
        "add test 2",
        "add lint 3",
        "run",
        "run",
        "add cleanup 5",
        "add review 2",
        "run",
        "add build 1",
        "add docs 4",
        "run",
        "run",
    };
    var heap: std.PriorityQueue(Task, void, compare) = .empty;
    defer heap.deinit(std.heap.page_allocator);
    var sequence: usize = 0;
    for (operations) |operation| {
        var tokens = std.mem.splitScalar(u8, operation, ' ');
        const op = tokens.next().?;
        if (std.mem.eql(u8, op, "add")) {
            const name = tokens.next().?;
            const priority = try std.fmt.parseInt(u32, tokens.next().?, 10);
            try heap.push(std.heap.page_allocator, .{ .name = name, .priority = priority, .sequence = sequence });
            sequence += 1;
        } else {
            const task = heap.pop().?;
            try out.print("run: {s} (priority {d})\n", .{ task.name, task.priority });
        }
    }
    try out.writeAll("remaining:");
    while (heap.pop()) |task| {
        try out.print(" {s}", .{task.name});
    }
    try out.writeByte('\n');
    try out.flush();
}
