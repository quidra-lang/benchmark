const std = @import("std");

const Node = struct { key: i32, left: ?usize = null, right: ?usize = null };

fn traverse(out: *std.Io.Writer, nodes: *const [12]Node, root: ?usize, mode: usize) std.Io.Writer.Error!void {
    const i = root orelse return;
    if (mode == 1)
        try out.print(" {d}", .{nodes[i].key});
    try traverse(out, nodes, nodes[i].left, mode);
    if (mode == 0)
        try out.print(" {d}", .{nodes[i].key});
    try traverse(out, nodes, nodes[i].right, mode);
    if (mode == 2)
        try out.print(" {d}", .{nodes[i].key});
}

fn height(nodes: *const [12]Node, root: ?usize) usize {
    const i = root orelse return 0;
    return 1 + @max(height(nodes, nodes[i].left), height(nodes, nodes[i].right));
}

fn remove(nodes: *[12]Node, root: ?usize, key: i32) ?usize {
    const i = root orelse return null;
    if (key < nodes[i].key) {
        nodes[i].left = remove(nodes, nodes[i].left, key);
    } else if (key > nodes[i].key) {
        nodes[i].right = remove(nodes, nodes[i].right, key);
    } else {
        if (nodes[i].left == null)
            return nodes[i].right;
        if (nodes[i].right == null)
            return nodes[i].left;
        var successor = nodes[i].right.?;
        while (nodes[successor].left) |next|
            successor = next;
        nodes[i].key = nodes[successor].key;
        nodes[i].right = remove(nodes, nodes[i].right, nodes[successor].key);
    }
    return i;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var nodes: [12]Node = undefined;
    var len: usize = 0;
    var root: ?usize = null;
    for ([_]i32{ 50, 27, 74, 13, 39, 62, 88, 6, 31, 45, 70, 34 }) |key| {
        var link = &root;
        while (link.*) |i| {
            link = if (key < nodes[i].key) &nodes[i].left else &nodes[i].right;
        }
        nodes[len] = .{ .key = key };
        link.* = len;
        len += 1;
    }
    const labels = [_][]const u8{ "inorder:", "preorder:", "postorder:" };
    for (labels, 0..) |label, mode| {
        try out.writeAll(label);
        try traverse(out, &nodes, root, mode);
        try out.writeByte('\n');
    }
    var queue: [12]usize = undefined;
    queue[0] = root.?;
    var head: usize = 0;
    var tail: usize = 1;
    try out.writeAll("levelorder:");
    while (head < tail) {
        const i = queue[head];
        head += 1;
        try out.print(" {d}", .{nodes[i].key});
        if (nodes[i].left) |child| {
            queue[tail] = child;
            tail += 1;
        }
        if (nodes[i].right) |child| {
            queue[tail] = child;
            tail += 1;
        }
    }
    try out.print("\nheight: {d}\n", .{height(&nodes, root)});
    root = remove(&nodes, root, 6);
    root = remove(&nodes, root, 27);
    try out.writeAll("preorder after deletions:");
    try traverse(out, &nodes, root, 1);
    try out.print("\nheight after deletions: {d}\n", .{height(&nodes, root)});
    try out.flush();
}
