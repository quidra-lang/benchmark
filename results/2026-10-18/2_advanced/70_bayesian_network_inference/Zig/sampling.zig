const d = @import("network_io.zig");
const learning = @import("learning.zig");
pub const Minstd = struct {
    state: i64,
    pub fn uniform(self: *Minstd) f64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return d.f(self.state) / 2147483647;
    }
};
pub fn choose(probabilities: []const f64, random: *Minstd) usize {
    const uniform = random.uniform();
    var cumulative: f64 = 0;
    for (probabilities, 0..) |probability, state| {
        cumulative += probability;
        if (uniform < cumulative) return state;
    }
    return probabilities.len - 1;
}
pub const Weighted = struct { assignment: d.Assignment, weight: f64 };
pub fn weightedSample(topological: []const usize, network: d.Network, cpts: []const d.CPT,
     evidence: []const d.Observation, random: *Minstd) Weighted {
    var out: Weighted = .{ .assignment = [_]usize{0} ** 15, .weight = 1 };
    for (topological) |variable| {
        const row = cpts[variable].rows[learning.parentRow(network.parents[variable], out.assignment, network.sizes)];
        if (d.evidenceState(evidence, variable)) |state| {
            out.assignment[variable] = state;
            out.weight *= row[state];
        } else out.assignment[variable] = choose(row[0..network.sizes[variable]], random);
    }
    return out;
}
