const std = @import("std");
const d = @import("instance.zig");
const main = @import("main.zig");
pub fn dispatch(data: *const d.Instance, rule: []const u8, genes: []const usize) d.Schedule {
    var next: [14]usize = @splat(0);
    var ready: [14]i64 = @splat(0);
    var free_time: [10]i64 = @splat(0);
    const ranks = d.alloc(i64, data.operations.len);
    if (d.eq(rule, "GENES")) {
        var count: [14]usize = @splat(0);
        for (genes, 1..) |number, position| {
            ranks[data.job(number).operations[count[number]]] = d.n(position);
            count[number] += 1;
        }
    }
    const starts = d.alloc(i64, data.operations.len);
    var decisions: usize = 0;
    var ties: usize = 0;
    for (0..data.operations.len) |_| {
        var candidates: [13]usize = undefined;
        var earliest: [13]i64 = undefined;
        var count: usize = 0;
        var completion: i64 = std.math.maxInt(i64);
        var machine = data.machines;
        for (data.jobs) |job| {
            if (next[job.number] >= job.operations.len) continue;
            const id = job.operations[next[job.number]];
            const op = data.operations[id];
            const start = @max(ready[job.number], free_time[op.machine]);
            const end = start + op.duration;
            candidates[count] = id;
            earliest[count] = start;
            count += 1;
            if (end < completion or (end == completion and op.machine < machine)) {
                completion = end;
                machine = op.machine;
            }
        }
        var selected: usize = 0;
        var best: i64 = std.math.maxInt(i64);
        var conflicts: usize = 0;
        var equal: usize = 0;
        var start: i64 = 0;
        for (candidates[0..count], earliest[0..count]) |id, es| {
            const op = data.operations[id];
            if (op.machine != machine or es >= completion) continue;
            conflicts += 1;
            const value = if (d.eq(rule, "SPT")) op.duration else if (d.eq(rule, "LPT")) -op.duration else if (d.eq(rule,
                 "MWKR")) -(op.duration + op.tail) else if (d.eq(rule, "FIFO")) ready[op.job] else ranks[id];
            if (value < best) {
                selected = id;
                best = value;
                equal = 1;
                start = es;
            } else if (value == best) {
                equal += 1;
                if (op.job < data.operations[selected].job) {
                    selected = id;
                    start = es;
                }
            }
        }
        if (conflicts >= 2) decisions += 1;
        if (equal >= 2) ties += 1;
        const op = data.operations[selected];
        starts[selected] = start;
        ready[op.job] = start + op.duration;
        free_time[op.machine] = start + op.duration;
        next[op.job] += 1;
    }
    var result = main.fromStarts(data, starts);
    result.decisions = decisions;
    result.ties = ties;
    return result;
}
