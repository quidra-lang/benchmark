const std = @import("std");
const d = @import("eventlog.zig");
const graph = @import("dfg.zig");
pub const Candidate = struct { first: u16, second: u16 };
pub fn extendPair(pair: Candidate, activity: usize, side: usize, relations: *const graph.Relations) ?Candidate {
    const group = if (side == 0) pair.first else pair.second;
    const other = if (side == 0) pair.second else pair.first;
    const bit = d.bit(activity);
    if (group & bit != 0 or relations[activity][activity] != .unrelated) return null;
    for (0..12) |i| {
        if (group & d.bit(i) != 0 and relations[activity][i] != .unrelated) return null;
        if (other & d.bit(i) != 0 and (if (side == 0) relations[activity][i] else relations[i][activity]) != .forward) return null;
    }
    var out = pair;
    if (side == 0) out.first |= bit else out.second |= bit;
    return out;
}
fn maskOrder(a: u16, b: u16) std.math.Order {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < 12 and a & d.bit(i) == 0) : (i += 1) {}
        while (j < 12 and b & d.bit(j) == 0) : (j += 1) {}
        if (i == 12 or j == 12) return if (i == j) .eq else if (i == 12) .lt else .gt;
        if (i != j) return if (i < j) .lt else .gt;
        i += 1;
        j += 1;
    }
}
pub fn pairLess(_: void, a: Candidate, b: Candidate) bool {
    const first = maskOrder(a.first, b.first);
    return if (first == .eq) maskOrder(a.second, b.second) == .lt else first == .lt;
}
pub fn triangleCounts(log: []const graph.Trace) graph.Counts {
    var out: graph.Counts = std.mem.zeroes(graph.Counts);
    for (log) |trace| {
        var i: usize = 0;
        while (i + 2 < trace.activities.len) : (i += 1) {
            const a = trace.activities[i];
            const b = trace.activities[i + 1];
            if (a == trace.activities[i + 2] and a != b) out[a][b] += trace.weight;
        }
    }
    return out;
}
pub fn plusRelation(counts: *const graph.Counts, triangles: *const graph.Counts, a: usize, b: usize) graph.Relation {
    const forward = counts[a][b] > 0;
    const backward = counts[b][a] > 0;
    const loop = a != b and triangles[a][b] > 0 and triangles[b][a] > 0;
    if (forward and (!backward or loop)) return .forward;
    if (backward and (!forward or loop)) return .backward;
    return if (forward and backward) .parallel else .unrelated;
}
