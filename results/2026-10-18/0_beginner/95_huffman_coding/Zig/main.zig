const std = @import("std");

const Node = struct {
    weight: u32,
    minimum: u8,
    symbol: ?u8 = null,
    left: ?usize = null,
    right: ?usize = null
};

fn compare(nodes: *const [64]Node, a: usize, b: usize) std.math.Order {
    return if (nodes[a].weight != nodes[b].weight)
        std.math.order(nodes[a].weight, nodes[b].weight)
    else
        std.math.order(nodes[a].minimum, nodes[b].minimum);
}

fn assign(nodes: *const [64]Node, index: usize, path: *[64]u8, depth: usize, codes: *[128][64]u8,
    lengths: *[128]usize) void {
    const node = nodes[index];
    if (node.symbol) |c| {
        @memcpy(codes[c][0..depth], path[0..depth]);
        lengths[c] = depth;
        return;
    }
    path[depth] = '0';
    assign(nodes, node.left.?, path, depth + 1, codes, lengths);
    path[depth] = '1';
    assign(nodes, node.right.?, path, depth + 1, codes, lengths);
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const text = "she sells sea shells by the sea shore";
    var frequency = [_]u32{ 0 } ** 128;
    for (text) |c|
        frequency[c] += 1;
    var nodes: [64]Node = undefined;
    var nlen: usize = 0;
    var active = std.PriorityQueue(usize, *const [64]Node, compare).initContext(&nodes);
    defer active.deinit(std.heap.page_allocator);
    for (frequency, 0..) |freq, c| {
        if (freq > 0) {
            nodes[nlen] = .{ .weight = freq, .minimum = @intCast(c), .symbol = @intCast(c) };
            try active.push(std.heap.page_allocator, nlen);
            nlen += 1;
        }
    }
    while (active.count() > 1) {
        const left = active.pop().?;
        const right = active.pop().?;
        nodes[nlen] = .{
            .weight = nodes[left].weight + nodes[right].weight,
            .minimum = @min(nodes[left].minimum, nodes[right].minimum),
            .left = left,
            .right = right
        };
        try active.push(std.heap.page_allocator, nlen);
        nlen += 1;
    }
    var codes: [128][64]u8 = undefined;
    var lengths = [_]usize{ 0 } ** 128;
    var path: [64]u8 = undefined;
    assign(&nodes, active.pop().?, &path, 0, &codes, &lengths);
    var bits: usize = 0;
    for (frequency, 0..) |freq, c| {
        if (freq > 0) {
            try out.print("'{c}' freq={d} code={s}\n", .{ @as(u8, @intCast(c)), freq, codes[c][0..lengths[c]] });
            bits += @as(usize, freq) * lengths[c];
        }
    }
    try out.print("encoded bits: {d}\nfixed 8-bit: {d}\n", .{ bits, text.len * 8 });
    try out.flush();
}
