const std = @import("std");
const c = @import("bitio.zig");
const Node = struct { weight: usize, minimum: usize, left: ?usize = null, right: ?usize = null, symbol: ?usize = null };
fn nodeLess(nodes: []const Node, a: usize, b: usize) bool {
    return if (nodes[a].weight != nodes[b].weight) nodes[a].weight < nodes[b].weight else nodes[a].minimum < nodes[b].minimum;
}
fn treeLengths(frequencies: []const usize) []usize {
    var nodes: std.ArrayList(Node) = .empty;
    var queue: std.ArrayList(usize) = .empty;
    const lengths = c.alloc(usize, frequencies.len);
    @memset(lengths, 0);
    for (frequencies, 0..) |frequency, symbol| if (frequency > 0) {
        c.append(usize, &queue, nodes.items.len);
        c.append(Node, &nodes, .{ .weight = frequency, .minimum = symbol, .symbol = symbol });
    };
    if (queue.items.len == 0) return lengths;
    if (queue.items.len == 1) {
        lengths[nodes.items[queue.items[0]].symbol.?] = 1;
        return lengths;
    }
    while (queue.items.len > 1) {
        std.mem.sort(usize, queue.items, @as([]const Node, nodes.items), nodeLess);
        const a = queue.orderedRemove(0);
        const b = queue.orderedRemove(0);
        c.append(usize, &queue, nodes.items.len);
        c.append(Node, &nodes, .{ .weight = nodes.items[a].weight + nodes.items[b].weight, .minimum = @min(nodes.items[a].minimum,
             nodes.items[b].minimum), .left = a, .right = b });
    }
    const Entry = struct { node: usize, depth: usize };
    var stack: std.ArrayList(Entry) = .empty;
    c.append(Entry, &stack, .{ .node = queue.items[0], .depth = 0 });
    while (stack.pop()) |entry| {
        const node = nodes.items[entry.node];
        if (node.symbol) |symbol| lengths[symbol] = entry.depth else {
            c.append(Entry, &stack, .{ .node = node.right.?, .depth = entry.depth + 1 });
            c.append(Entry, &stack, .{ .node = node.left.?, .depth = entry.depth + 1 });
        }
    }
    return lengths;
}
pub const Huffman = struct { lengths: []const usize, halvings: usize = 0 };
pub fn lengths(frequencies: []const usize, maximum: usize) Huffman {
    const current = c.dupe(usize, frequencies);
    var halvings: usize = 0;
    while (true) {
        const result = treeLengths(current);
        if (std.mem.max(usize, result) <= maximum) return .{ .lengths = result, .halvings = halvings };
        for (current) |*frequency| frequency.* = (frequency.* + 1) / 2;
        halvings += 1;
    }
}
fn codeLess(values: []const usize, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] < values[b] else a < b;
}
pub fn canonicalCodes(length_values: []const usize) []u32 {
    const codes = c.alloc(u32, length_values.len);
    @memset(codes, 0);
    var order: std.ArrayList(usize) = .empty;
    for (length_values, 0..) |length, symbol| if (length > 0) c.append(usize, &order, symbol);
    std.mem.sort(usize, order.items, length_values, codeLess);
    var code: u32 = 0;
    var previous: usize = 0;
    for (order.items) |symbol| {
        if (previous > 0) code = (code + 1) << @as(u5, @intCast(length_values[symbol] - previous));
        codes[symbol] = code;
        previous = length_values[symbol];
    }
    return codes;
}
