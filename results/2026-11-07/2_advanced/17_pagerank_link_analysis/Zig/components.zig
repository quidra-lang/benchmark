const D = @import("graph_io.zig");
pub const Components = struct { count: usize = 0, labels: [500]usize = undefined, sizes: [500]usize = [_]usize{0} ** 500, minimum: [500]usize = undefined };
pub fn strongComponents(graph: D.Graph) Components {
    var order = [_]i64{-1} ** 500;
    var low: [500]usize = undefined;
    var stack: [500]usize = undefined;
    var stack_size: usize = 0;
    var counter: usize = 0;
    var on_stack = [_]bool{false} ** 500;
    var result: Components = .{};
    const Frame = struct { node: usize, next: usize = 0 };
    var work: [500]Frame = undefined;
    for (0..graph.count) |root| {
        if (order[root] >= 0) continue;
        order[root] = D.n(counter);
        low[root] = counter;
        counter += 1;
        stack[stack_size] = root;
        stack_size += 1;
        on_stack[root] = true;
        var depth: usize = 1;
        work[0] = .{ .node = root };
        while (depth > 0) {
            const frame = &work[depth - 1];
            const node = frame.node;
            if (frame.next < graph.out[node].len) {
                const child = graph.out[node][frame.next];
                frame.next += 1;
                if (order[child] < 0) {
                    order[child] = D.n(counter);
                    low[child] = counter;
                    counter += 1;
                    stack[stack_size] = child;
                    stack_size += 1;
                    on_stack[child] = true;
                    work[depth] = .{ .node = child };
                    depth += 1;
                } else if (on_stack[child]) low[node] = @min(low[node], @as(usize, @intCast(order[child])));
                continue;
            }
            depth -= 1;
            if (depth > 0) low[work[depth - 1].node] = @min(low[work[depth - 1].node], low[node]);
            if (D.n(low[node]) == order[node]) {
                var minimum = graph.count;
                while (true) {
                    stack_size -= 1;
                    const member = stack[stack_size];
                    on_stack[member] = false;
                    result.labels[member] = result.count;
                    result.sizes[result.count] += 1;
                    minimum = @min(minimum, member);
                    if (member == node) break;
                }
                result.minimum[result.count] = minimum;
                result.count += 1;
            }
        }
    }
    var ranking: [500]usize = undefined;
    var mapping: [500]usize = undefined;
    var sizes: [500]usize = undefined;
    var minima: [500]usize = undefined;
    for (0..result.count) |c| {
        var j = c;
        while (j > 0 and result.minimum[ranking[j - 1]] > result.minimum[c]) : (j -= 1) ranking[j] = ranking[j - 1];
        ranking[j] = c;
    }
    for (ranking[0..result.count], 0..) |old, c| { mapping[old] = c; sizes[c] = result.sizes[old]; minima[c] = result.minimum[old]; }
    for (result.labels[0..graph.count]) |*label| label.* = mapping[label.*];
    @memcpy(result.sizes[0..result.count], sizes[0..result.count]);
    @memcpy(result.minimum[0..result.count], minima[0..result.count]);
    return result;
}
pub fn reachable(graph: D.Graph, starts: []const bool, reverse: bool, seen: []bool) void {
    var stack: [500]usize = undefined;
    var count: usize = 0;
    @memset(seen, false);
    for (starts, 0..) |start, i| { if (start) { seen[i] = true; stack[count] = i; count += 1; } }
    while (count > 0) {
        count -= 1;
        const node = stack[count];
        for (if (reverse) graph.in[node] else graph.out[node]) |child| {
            if (!seen[child]) { seen[child] = true; stack[count] = child; count += 1; }
        }
    }
}
pub fn bfsDistances(graph: D.Graph, starts: []const bool, distances: []i64) void {
    var queue: [500]usize = undefined;
    var head: usize = 0;
    var count: usize = 0;
    for (starts, 0..) |start, i| { distances[i] = if (start) 0 else -1; if (start) { queue[count] = i; count += 1; } }
    while (head < count) {
        const node = queue[head];
        head += 1;
        for (graph.out[node]) |child| {
            if (distances[child] < 0) { distances[child] = distances[node] + 1; queue[count] = child; count += 1; }
        }
    }
}
pub fn weakComponents(graph: D.Graph, labels: []i64) usize {
    @memset(labels, -1);
    var count: usize = 0;
    for (0..graph.count) |root| {
        if (labels[root] >= 0) continue;
        var stack: [500]usize = undefined;
        var size: usize = 1;
        stack[0] = root;
        labels[root] = D.n(count);
        while (size > 0) {
            size -= 1;
            const node = stack[size];
            for (0..2) |reverse| {
                for (if (reverse == 1) graph.in[node] else graph.out[node]) |child| {
                    if (labels[child] < 0) { labels[child] = D.n(count); stack[size] = child; size += 1; }
                }
            }
        }
        count += 1;
    }
    return count;
}
