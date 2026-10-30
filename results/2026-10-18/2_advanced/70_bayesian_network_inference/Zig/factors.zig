const std = @import("std");
const d = @import("network_io.zig");
const learning = @import("learning.zig");
pub fn contains(variables: []const usize, variable: usize) bool {
    return std.mem.indexOfScalar(usize, variables, variable) != null;
}
pub fn united(a: []const usize, b: []const usize) []const usize {
    var present = [_]bool{false} ** 15;
    for (a) |variable| present[variable] = true;
    for (b) |variable| present[variable] = true;
    var out: std.ArrayList(usize) = .empty;
    for (present, 0..) |found, variable| if (found) d.append(usize, &out, variable);
    return out.items;
}
pub fn difference(a: []const usize, b: []const usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    for (a) |variable| if (!contains(b, variable)) d.append(usize, &out, variable);
    return out.items;
}
pub fn observed(evidence: []const d.Observation) []const usize {
    var present = [_]bool{false} ** 15;
    for (evidence) |entry| present[entry.variable] = true;
    var out: std.ArrayList(usize) = .empty;
    for (present, 0..) |found, variable| if (found) d.append(usize, &out, variable);
    return out.items;
}
pub fn entryCount(variables: []const usize, sizes: []const usize) usize {
    var count: usize = 1;
    for (variables) |variable| count *= sizes[variable];
    return count;
}
pub fn decode(index_value: usize, variables: []const usize, sizes: []const usize, initial: d.Assignment) d.Assignment {
    var index = index_value;
    var assignment = initial;
    var i = variables.len;
    while (i > 0) {
        i -= 1;
        const variable = variables[i];
        assignment[variable] = index % sizes[variable];
        index /= sizes[variable];
    }
    return assignment;
}
pub const Factor = struct {
    variables: []const usize,
    values: []const f64,
    sizes: []const usize,
    pub fn value(self: Factor, assignment: d.Assignment) f64 {
        return self.values[learning.parentRow(self.variables, assignment, self.sizes)];
    }
    pub fn reduced(self: Factor, evidence: []const d.Observation) Factor {
        const variables = difference(self.variables, observed(evidence));
        const values = d.alloc(f64, entryCount(variables, self.sizes));
        var initial = [_]usize{0} ** 15;
        for (evidence) |entry| initial[entry.variable] = entry.state;
        for (values, 0..) |*result, row| result.* = self.value(decode(row, variables, self.sizes, initial));
        return .{ .variables = variables, .values = values, .sizes = self.sizes };
    }
    pub fn multiplied(self: Factor, other: Factor) Factor {
        const variables = united(self.variables, other.variables);
        const values = d.alloc(f64, entryCount(variables, self.sizes));
        for (values, 0..) |*result, row| {
            const assignment = decode(row, variables, self.sizes, [_]usize{0} ** 15);
            result.* = self.value(assignment) * other.value(assignment);
        }
        return .{ .variables = variables, .values = values, .sizes = self.sizes };
    }
    pub fn eliminate(self: Factor, variable: usize, maximize: bool) Factor {
        const variables = difference(self.variables, &.{variable});
        const values = d.alloc(f64, entryCount(variables, self.sizes));
        for (values, 0..) |*result, row| {
            var assignment = decode(row, variables, self.sizes, [_]usize{0} ** 15);
            var value_result: f64 = 0;
            for (0..self.sizes[variable]) |state| {
                assignment[variable] = state;
                const candidate = self.value(assignment);
                if (maximize) {
                    if (state == 0 or candidate > value_result) value_result = candidate;
                } else value_result += candidate;
            }
            result.* = value_result;
        }
        return .{ .variables = variables, .values = values, .sizes = self.sizes };
    }
};
pub fn cptFactor(variable: usize, parents: []const usize, cpt: d.CPT, sizes: []const usize) Factor {
    const variables = united(parents, &.{variable});
    const values = d.alloc(f64, entryCount(variables, sizes));
    for (values, 0..) |*value, row| {
        const assignment = decode(row, variables, sizes, [_]usize{0} ** 15);
        value.* = cpt.rows[learning.parentRow(parents, assignment, sizes)][assignment[variable]];
    }
    return .{ .variables = variables, .values = values, .sizes = sizes };
}
pub fn multiply(initial: []const Factor, sizes: []const usize) Factor {
    if (initial.len == 0) return .{ .variables = &.{}, .values = &.{1}, .sizes = sizes };
    var out = initial[0];
    for (initial[1..]) |factor| out = out.multiplied(factor);
    return out;
}
