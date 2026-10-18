const std = @import("std");

const Node = struct {
    weight: u32,
    minimum: u8,
    symbol: ?u8 = null,
    left: ?usize = null,
    right: ?usize = null
};

fn before(a: Node, b: Node) bool {
    return if (a.weight != b.weight) a.weight < b.weight else a.minimum < b.minimum;
}

fn take(active: *[64]usize, len: *usize, nodes: *const [64]Node) usize {
    var best: usize = 0;
    for (1..len.*) |i| {
        if (before(nodes[active[i]], nodes[active[best]]))
            best = i;
    }
    const result = active[best];
    var i = best;
    while (i + 1 < len.*) : (i += 1)
        active[i] = active[i + 1];
    len.* -= 1;
    return result;
}

fn assign(nodes: *const [64]Node, index: usize, path: *[64]u8, depth: usize, codes: *[128][64]u8,
    lengths: *[128]usize) void {
    const node = nodes[index];
    if (node.symbol) |c| {
        for (path[0..depth], 0..) |bit, i|
            codes[c][i] = bit;
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
    var active: [64]usize = undefined;
    var alen: usize = 0;
    for (frequency, 0..) |freq, c| {
        if (freq > 0) {
            nodes[nlen] = .{ .weight = freq, .minimum = @intCast(c), .symbol = @intCast(c) };
            active[alen] = nlen;
            alen += 1;
            nlen += 1;
        }
    }
    while (alen > 1) {
        const left = take(&active, &alen, &nodes);
        const right = take(&active, &alen, &nodes);
        nodes[nlen] = .{
            .weight = nodes[left].weight + nodes[right].weight,
            .minimum = @min(nodes[left].minimum, nodes[right].minimum),
            .left = left,
            .right = right
        };
        active[alen] = nlen;
        alen += 1;
        nlen += 1;
    }
    var codes: [128][64]u8 = undefined;
    var lengths = [_]usize{ 0 } ** 128;
    var path: [64]u8 = undefined;
    assign(&nodes, active[0], &path, 0, &codes, &lengths);
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
