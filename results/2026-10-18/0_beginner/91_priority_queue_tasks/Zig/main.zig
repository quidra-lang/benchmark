const std = @import("std");

const Task = struct {
    name: []const u8,
    priority: u32,
    sequence: usize
};

fn before(a: Task, b: Task) bool {
    return if (a.priority != b.priority) a.priority < b.priority else a.sequence < b.sequence;
}

const Heap = struct {
    items: [16]Task = undefined,
    len: usize = 0,

    fn push(self: *Heap, task: Task) void {
        var i = self.len;
        self.len += 1;
        self.items[i] = task;
        while (i > 0) {
            const p = (i - 1) / 2;
            if (!before(self.items[i], self.items[p]))
                break;
            const t = self.items[i];
            self.items[i] = self.items[p];
            self.items[p] = t;
            i = p;
        }
    }

    fn pop(self: *Heap) Task {
        const result = self.items[0];
        self.len -= 1;
        if (self.len > 0) {
            self.items[0] = self.items[self.len];
            var i: usize = 0;
            while (2 * i + 1 < self.len) {
                var child = 2 * i + 1;
                if (child + 1 < self.len and before(self.items[child + 1], self.items[child]))
                    child += 1;
                if (!before(self.items[child], self.items[i]))
                    break;
                const t = self.items[i];
                self.items[i] = self.items[child];
                self.items[child] = t;
                i = child;
            }
        }
        return result;
    }
};

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
        "run"
    };
    var heap = Heap{};
    var sequence: usize = 0;
    for (operations) |operation| {
        var tokens = std.mem.splitScalar(u8, operation, ' ');
        const op = tokens.next().?;
        if (std.mem.eql(u8, op, "add")) {
            const name = tokens.next().?;
            const priority = try std.fmt.parseInt(u32, tokens.next().?, 10);
            heap.push(.{ .name = name, .priority = priority, .sequence = sequence });
            sequence += 1;
        } else {
            const task = heap.pop();
            try out.print("run: {s} (priority {d})\n", .{ task.name, task.priority });
        }
    }
    try out.writeAll("remaining:");
    while (heap.len > 0) {
        const task = heap.pop();
        try out.print(" {s}", .{ task.name });
    }
    try out.writeByte('\n');
    try out.flush();
}
