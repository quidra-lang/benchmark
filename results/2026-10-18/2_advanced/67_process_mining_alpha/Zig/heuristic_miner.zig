const d = @import("eventlog.zig");
const graph = @import("dfg.zig");
pub fn dependency(counts: *const graph.Counts, a: usize, b: usize) d.Fraction {
    return d.Fraction.init(counts[a][b] - counts[b][a], counts[a][b] + counts[b][a] + 1);
}
pub fn loopMeasure(count: i64) d.Fraction {
    return d.Fraction.init(count, count + 1);
}
pub fn splitMeasure(counts: *const graph.Counts, a: usize, b: usize, c: usize) d.Fraction {
    return d.Fraction.init(counts[b][c] + counts[c][b], counts[a][b] + counts[a][c] + 1);
}
pub fn joinMeasure(counts: *const graph.Counts, a: usize, b: usize, c: usize) d.Fraction {
    return d.Fraction.init(counts[b][c] + counts[c][b], counts[b][a] + counts[c][a] + 1);
}
