const std = @import("std");
const d = @import("document_parser.zig");
pub const Measure = struct { length: usize, slack: i64, gaps: usize, mid: bool, last: bool, previous_mid: bool };
pub fn lineClass(line: Measure) usize {
    return if (line.last) 1 else if (line.slack <= 1) 0 else if (line.slack <= 3) 1 else if (line.slack <= 6) 2 else 3;
}
pub fn lineCost(line: Measure, previous: usize, p: d.Params) i64 {
    var cost = p.line_penalty + if (line.slack < 0) p.overfull_penalty else if (line.last) @as(i64,
         0) else line.slack * line.slack;
    if (line.mid) {
        cost += p.hyphen_penalty;
        if (line.previous_mid) cost += p.double_hyphen_demerit;
    }
    if (line.last and line.previous_mid) cost += p.final_hyphen_demerit;
    if (@abs(d.n(lineClass(line)) - d.n(previous)) >= 2) cost += p.fitness_demerit;
    return cost;
}
pub const Breaking = struct { ends: []usize, cost: i64 = 0 };
pub fn breakLines(count: usize, context: anytype, comptime measure: anytype, p: d.Params, greedy: bool) Breaking {
    var ends: std.ArrayList(usize) = .empty;
    var total: i64 = 0;
    if (greedy) {
        var a: usize = 0;
        var previous: usize = 1;
        while (a < count) {
            var b = a + 1;
            if (measure(context, a, b).slack >= 0) for (b + 1..count + 1) |next| {
                if (measure(context, a, next).slack >= 0) b = next;
            };
            const line = measure(context, a, b);
            d.append(usize, &ends, b);
            total += lineCost(line, previous, p);
            previous = lineClass(line);
            a = b;
        }
        return .{ .ends = ends.items, .cost = total };
    }
    const Predecessor = struct { a: usize = 0, class: usize = 0 };
    const costs = d.alloc([4]?i64, count + 1);
    @memset(costs, @splat(null));
    const previous = d.alloc([4]Predecessor, count + 1);
    @memset(previous, @splat(.{}));
    costs[0][1] = 0;
    for (1..count + 1) |b| for (0..b) |a| {
        const line = measure(context, a, b);
        if (line.slack < 0 and b != a + 1) continue;
        const class = lineClass(line);
        for (0..4) |pc| {
            const old = costs[a][pc] orelse continue;
            const value = old + lineCost(line, pc, p);
            if (costs[b][class] == null or value < costs[b][class].?) {
                costs[b][class] = value;
                previous[b][class] = .{ .a = a, .class = pc };
            }
        }
    };
    total = costs[count][1].?;
    var b = count;
    var class: usize = 1;
    while (b > 0) {
        d.append(usize, &ends, b);
        const pair = previous[b][class];
        b = pair.a;
        class = pair.class;
    }
    std.mem.reverse(usize, ends.items);
    return .{ .ends = ends.items, .cost = total };
}
