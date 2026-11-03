const std = @import("std");
const d = @import("instance.zig");
const Minstd = @import("minstd.zig").Minstd;
const main = @import("main.zig");
pub fn decode(data: *const d.Instance, genes: []const usize) d.Schedule {
    var next: [14]usize = @splat(0);
    var ready: [14]i64 = @splat(0);
    var free_time: [10]i64 = @splat(0);
    const starts = d.alloc(i64, data.operations.len);
    for (genes) |number| {
        const id = data.job(number).operations[next[number]];
        next[number] += 1;
        const op = data.operations[id];
        starts[id] = @max(ready[number], free_time[op.machine]);
        ready[number] = starts[id] + op.duration;
        free_time[op.machine] = starts[id] + op.duration;
    }
    return main.fromStarts(data, starts);
}
pub fn tournament(random: *Minstd, values: []const i64, size: usize) usize {
    var best: ?usize = null;
    for (0..size) |_| {
        const index = random.below(values.len);
        if (best == null or values[index] < values[best.?] or (values[index] == values[best.?] and index < best.?)) best = index;
    }
    return best.?;
}
fn child(first: []const usize, second: []const usize, selected: [14]bool) []usize {
    const result = d.alloc(usize, first.len);
    @memset(result, 0);
    for (first, result) |gene, *value| if (selected[gene]) {
        value.* = gene;
    };
    var next: usize = 0;
    for (second) |gene| if (!selected[gene]) {
        while (result[next] != 0) next += 1;
        result[next] = gene;
        next += 1;
    };
    return result;
}
pub fn crossover(random: *Minstd, data: *const d.Instance, first: []const usize, second: []const usize) [2][]usize {
    var selected: [14]bool = @splat(false);
    for (data.jobs) |job| selected[job.number] = random.below(2) == 0;
    return .{ child(first, second, selected), child(second, first, selected) };
}
pub fn swapMutation(random: *Minstd, genes: []usize) void {
    const a = random.below(genes.len);
    const b = random.below(genes.len);
    std.mem.swap(usize, &genes[a], &genes[b]);
}
pub fn insertionMutation(random: *Minstd, genes: []usize) void {
    const a = random.below(genes.len);
    const b = random.below(genes.len);
    const value = genes[a];
    if (a < b) std.mem.copyForwards(usize, genes[a..b], genes[a + 1 .. b + 1]) else if (a > b) std.mem.copyBackwards(usize,
         genes[b + 1 .. a + 1], genes[b..a]);
    genes[b] = value;
}
