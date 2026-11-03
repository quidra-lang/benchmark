const std = @import("std");
const D = @import("dataset.zig");
const I = @import("impurity.zig");
pub const Split = struct { attribute: usize, point: i64 };
pub const Surrogate = struct { split: Split, forward: bool, score: i64 };
pub const Candidate = struct { split: Split, left: D.Rows = .{}, right: D.Rows = .{}, value: I.Fraction = .{ .numerator = 0, .denominator = 1 } };
pub const Node = struct {
    number: usize, depth: usize, stats: I.Statistics,
    split: ?Split = null, default_left: bool = true,
    surrogates: [11]Surrogate = undefined, surrogate_count: usize = 0,
    left: ?*Node = null, right: ?*Node = null,
};
pub const Splits = struct { values: [500]Split = undefined, len: usize = 0 };
pub fn goesLeft(data: *const D.Dataset, split: Split, row: *const D.Row) bool {
    const value = row.values[split.attribute];
    return if (data.attributes[split.attribute].integer) 2 * value <= split.point else value == split.point;
}
pub fn candidates(data: *const D.Dataset, rows: D.Rows, attribute: usize) Splits {
    var values: [500]i64 = undefined;
    for (rows.slice(), 0..) |row, i| values[i] = row.values[attribute];
    std.mem.sort(i64, values[0..rows.len], {}, std.sort.asc(i64));
    var count: usize = 0;
    for (0..rows.len) |i| {
        if (i > 0 and values[i] == values[i - 1]) continue;
        values[count] = values[i];
        count += 1;
    }
    var result: Splits = .{};
    if (count < 2) return result;
    result.len = if (data.attributes[attribute].integer) count - 1 else count;
    for (0..result.len) |i| result.values[i] = .{ .attribute = attribute, .point = if (data.attributes[attribute].integer) values[i] + values[i + 1] else values[i] };
    return result;
}
pub const Builder = struct {
    data: *const D.Dataset,
    pub fn bestForAttribute(self: *const Builder, rows: D.Rows, attribute: usize) ?Candidate {
        var best: ?Candidate = null;
        const found = candidates(self.data, rows, attribute);
        for (found.values[0..found.len]) |split| {
            var candidate: Candidate = .{ .split = split };
            for (rows.slice()) |row| { if (goesLeft(self.data, split, row)) candidate.left.add(row) else candidate.right.add(row); }
            if (candidate.left.len < self.data.settings.min_leaf or candidate.right.len < self.data.settings.min_leaf) continue;
            candidate.value = I.evaluationValue(I.statistics(candidate.left, self.data.classes.len), I.statistics(candidate.right, self.data.classes.len));
            if (best == null or I.compare(candidate.value, best.?.value) > 0) best = candidate;
        }
        return best;
    }
    fn findSurrogates(self: *const Builder, rows: D.Rows, primary: Candidate, node: *Node) void {
        var retained: [12]Surrogate = undefined;
        var count: usize = 0;
        for (0..self.data.attributes.len) |attribute| {
            if (attribute == primary.split.attribute) continue;
            var best: ?Surrogate = null;
            const found = candidates(self.data, rows, attribute);
            for (found.values[0..found.len]) |split| {
                var agreement: i64 = 0;
                for (rows.slice()) |row| { if (goesLeft(self.data, split, row) == goesLeft(self.data, primary.split, row)) agreement += 1; }
                const reverse = D.n(rows.len) - agreement;
                const current: Surrogate = .{ .split = split, .forward = agreement >= reverse, .score = @max(agreement, reverse) };
                if (best == null or current.score > best.?.score) best = current;
            }
            if (best) |chosen| {
                if (chosen.score <= D.n(@max(primary.left.len, primary.right.len))) continue;
                var i = count;
                count += 1;
                while (i > 0 and retained[i - 1].score < chosen.score) : (i -= 1) retained[i] = retained[i - 1];
                retained[i] = chosen;
            }
        }
        node.surrogate_count = @min(count, self.data.settings.max_surrogates);
        @memcpy(node.surrogates[0..node.surrogate_count], retained[0..node.surrogate_count]);
    }
    pub fn grow(self: *const Builder, rows: D.Rows, number: usize, depth: usize) *Node {
        const node = D.create(Node, .{ .number = number, .depth = depth, .stats = I.statistics(rows, self.data.classes.len) });
        if (node.stats.errors == 0 or depth == self.data.settings.max_depth or rows.len < self.data.settings.min_split) return node;
        var best: ?Candidate = null;
        for (0..self.data.attributes.len) |attribute| {
            if (self.bestForAttribute(rows, attribute)) |candidate| { if (best == null or I.compare(candidate.value, best.?.value) > 0) best = candidate; }
        }
        const chosen = best orelse return node;
        if (!I.improves(chosen.value, node.stats)) return node;
        node.split = chosen.split;
        node.default_left = chosen.left.len >= chosen.right.len;
        self.findSurrogates(rows, chosen, node);
        node.left = self.grow(chosen.left, 2 * number, depth + 1);
        node.right = self.grow(chosen.right, 2 * number + 1, depth + 1);
        return node;
    }
};
