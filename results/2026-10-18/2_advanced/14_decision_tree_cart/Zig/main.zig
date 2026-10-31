const std = @import("std");
const D = @import("dataset.zig");
const I = @import("impurity.zig");
const B = @import("tree_builder.zig");
const P = @import("pruning.zig");
const E = @import("evaluation.zig");
const Model = enum { grown, pruned, depth, cost_complexity, bagging };
const Minstd = struct {
    state: i64,
    fn draw(self: *Minstd) i64 { self.state = @mod(48271 * self.state, 2147483647); return self.state; }
};
fn halfText(value: i64) []const u8 { return D.fmt("{d}.{d}", .{ @divFloor(value, 2), 5 * @mod(value, 2) }); }
fn splitText(data: *const D.Dataset, split: B.Split, left: bool) []const u8 {
    const attribute = data.attributes[split.attribute];
    if (attribute.integer) return D.fmt("{s} {s} {s}", .{ attribute.name, if (left) "<=" else ">", halfText(split.point) });
    return D.fmt("{s} {s} {s}", .{ attribute.name, if (left) "=" else "!=", attribute.values[@intCast(split.point)] });
}
const Condition = struct { attribute: usize, lower: ?i64 = null, upper: ?i64 = null, equal: ?i64 = null, excluded: [8]bool = [_]bool{false} ** 8 };
const Conditions = struct {
    values: [12]Condition = undefined, len: usize = 0,
    fn slice(self: *const Conditions) []const Condition { return self.values[0..self.len]; }
    fn remove(self: Conditions, index: usize) Conditions {
        var result = self;
        result.len -= 1;
        var i = index;
        while (i < result.len) : (i += 1) result.values[i] = result.values[i + 1];
        return result;
    }
};
const Rule = struct { leaf: *const B.Node, conditions: Conditions = .{}, generalized: Conditions = .{}, removed: [12]usize = undefined, removed_count: usize = 0 };
const Analysis = struct {
    data: *const D.Dataset, train: D.Rows, validation: D.Rows, test: D.Rows,
    builder: B.Builder, root: *B.Node, grown: E.Tree, pruned: E.Tree,
    decisions: [500]P.Decision = undefined, decision_count: usize = 0,
    grown_routes: [300]E.Route = undefined, pruned_routes: [300]E.Route = undefined,
    rules: [500]Rule = undefined, rule_count: usize = 0,
    predictions: [5][300]usize = undefined,
    test_votes: [300][6]i64 = [_][6]i64{[_]i64{0} ** 6} ** 300,
    cross_lines: D.Lines = .{}, depth_lines: D.Lines = .{}, complexity_lines: D.Lines = .{}, bag_lines: D.Lines = .{},
    fn init(data: *const D.Dataset) Analysis {
        const train = D.rowSequence(data.train);
        const validation = D.rowSequence(data.validation);
        const builder: B.Builder = .{ .data = data };
        const root = builder.grow(train, 1, 0);
        const pruning = P.reducedError(data, root, validation);
        var result: Analysis = .{
            .data = data, .train = train, .validation = validation, .test = D.rowSequence(data.test), .builder = builder, .root = root,
            .grown = .{ .root = root }, .pruned = pruning.tree, .decision_count = pruning.count,
        };
        @memcpy(result.decisions[0..pruning.count], pruning.decisions[0..pruning.count]);
        for (result.test.slice(), 0..) |row, i| {
            result.grown_routes[i] = result.grown.route(data, row);
            result.pruned_routes[i] = result.pruned.route(data, row);
        }
        result.modelPredictions(.grown, &result.grown);
        result.modelPredictions(.pruned, &result.pruned);
        result.crossValidation();
        result.complexitySelection();
        result.bagging();
        var splits: [10]B.Split = undefined;
        var directions: [10]bool = undefined;
        result.collectRules(root, &splits, &directions, 0);
        for (result.rules[0..result.rule_count]) |*rule| result.generalize(rule);
        return result;
    }
    fn accuracy(self: *const Analysis, tree: *const E.Tree, rows: D.Rows) []const u8 { return E.ratio(tree.correct(self.data, rows), D.n(rows.len)); }
    fn modelPredictions(self: *Analysis, model: Model, tree: *const E.Tree) void {
        for (self.test.slice(), 0..) |row, i| self.predictions[@intFromEnum(model)][i] = tree.predict(self.data, row);
    }
    fn atDepth(root: *const B.Node, depth: usize) E.Tree {
        var tree: E.Tree = .{ .root = root };
        const nodes = tree.preorder(null);
        for (nodes.slice()) |node| { if (node.split != null and node.depth == depth) tree.cuts[node.number] = true; }
        return tree;
    }
    fn crossValidation(self: *Analysis) void {
        var roots: [500]*B.Node = undefined;
        const folds = self.data.settings.folds;
        const size = self.train.len;
        var total: i64 = 0;
        self.cross_lines.add("cross_validation folds {d}", .{folds});
        for (0..folds) |f| {
            const first = f * size / folds;
            const end = (f + 1) * size / folds;
            var training: D.Rows = .{};
            var held: D.Rows = .{};
            for (self.train.slice(), 0..) |row, i| { if (i >= first and i < end) held.add(row) else training.add(row); }
            roots[f] = self.builder.grow(training, 1, 0);
            const tree: E.Tree = .{ .root = roots[f] };
            const correct = tree.correct(self.data, held);
            total += correct;
            self.cross_lines.add("fold {d} rows {d}-{d} leaves {d} correct {s}", .{ f + 1, first + 1, end, tree.leaves(null).len, E.ratio(correct, D.n(held.len)) });
        }
        self.cross_lines.add("cv accuracy {s}", .{E.ratio(total, D.n(size))});
        self.depth_lines.write("depth_selection");
        var selected: usize = 0;
        var maximum: i64 = -1;
        for (0..self.data.settings.max_depth + 1) |depth| {
            var correct: i64 = 0;
            for (roots[0..folds], 0..) |root, f| {
                const tree = atDepth(root, depth);
                var held: D.Rows = .{};
                for (self.train.slice()[f * size / folds .. (f + 1) * size / folds]) |row| held.add(row);
                correct += tree.correct(self.data, held);
            }
            const tree = atDepth(self.root, depth);
            if (correct > maximum) { maximum = correct; selected = depth; }
            self.depth_lines.add("depth {d} leaves {d} cv {s} train {s} validation {s} test {s}", .{ depth, tree.leaves(null).len, E.ratio(correct, D.n(size)), self.accuracy(&tree, self.train), self.accuracy(&tree, self.validation), self.accuracy(&tree, self.test) });
        }
        const tree = atDepth(self.root, selected);
        self.depth_lines.add("selected depth {d} leaves {d} test {s}", .{ selected, tree.leaves(null).len, self.accuracy(&tree, self.test) });
        self.modelPredictions(.depth, &tree);
    }
    fn complexitySelection(self: *Analysis) void {
        const sequence = P.costComplexity(self.root);
        var selected: usize = 0;
        var minimum = D.n(self.validation.len) + 1;
        self.complexity_lines.write("cost_complexity");
        for (sequence, 0..) |entry, i| {
            const errors = D.n(self.validation.len) - entry.tree.correct(self.data, self.validation);
            if (errors <= minimum) { minimum = errors; selected = i; }
            self.complexity_lines.add("subtree {d} alpha {s} leaves {d} train_errors {d} validation_errors {d}", .{ i, E.fraction(.{ .numerator = entry.alpha.numerator, .denominator = entry.alpha.denominator * D.n(self.train.len) }, 6), entry.tree.leaves(null).len, entry.tree.trainingErrors(), errors });
        }
        const tree = sequence[selected].tree;
        self.complexity_lines.add("selected subtree {d} leaves {d} test {s}", .{ selected, tree.leaves(null).len, self.accuracy(&tree, self.test) });
        self.modelPredictions(.cost_complexity, &tree);
    }
    fn bagging(self: *Analysis) void {
        var generator: Minstd = .{ .state = self.data.settings.bag_seed };
        var votes = [_][6]i64{[_]i64{0} ** 6} ** 500;
        self.bag_lines.add("bagging trees {d} seed {d}", .{ self.data.settings.bag_trees, generator.state });
        for (0..self.data.settings.bag_trees) |b| {
            var sample: D.Rows = .{};
            var sampled = [_]bool{false} ** 500;
            var distinct: usize = 0;
            for (0..self.train.len) |_| {
                const index: usize = @intCast(@mod(generator.draw(), D.n(self.train.len)));
                sample.add(self.train.values[index]);
                if (!sampled[index]) { sampled[index] = true; distinct += 1; }
            }
            const tree: E.Tree = .{ .root = self.builder.grow(sample, 1, 0) };
            var count: i64 = 0;
            var correct: i64 = 0;
            for (self.train.slice(), 0..) |row, i| {
                if (sampled[i]) continue;
                const prediction = tree.predict(self.data, row);
                votes[i][prediction] += 1;
                count += 1;
                if (prediction == row.label) correct += 1;
            }
            for (self.test.slice(), 0..) |row, i| self.test_votes[i][tree.predict(self.data, row)] += 1;
            self.bag_lines.add("bag {d} distinct {d} leaves {d} oob {s}", .{ b + 1, distinct, tree.leaves(null).len, E.ratio(correct, count) });
        }
        var voted: i64 = 0;
        var correct: i64 = 0;
        for (self.train.slice(), 0..) |row, i| {
            var total: i64 = 0;
            for (votes[i][0..self.data.classes.len]) |vote| total += vote;
            if (total == 0) continue;
            voted += 1;
            if (I.majority(votes[i][0..self.data.classes.len]) == row.label) correct += 1;
        }
        self.bag_lines.add("oob accuracy {s} unvoted {d}", .{ E.ratio(correct, voted), D.n(self.train.len) - voted });
        for (0..self.test.len) |i| self.predictions[@intFromEnum(Model.bagging)][i] = I.majority(self.test_votes[i][0..self.data.classes.len]);
        self.bag_lines.extend(E.classification(self.data, "bagging test", self.test, self.predictions[@intFromEnum(Model.bagging)][0..self.test.len]));
    }
    fn collectRules(self: *Analysis, node: *const B.Node, splits: *[10]B.Split, directions: *[10]bool, depth: usize) void {
        if (!self.pruned.isLeaf(node)) {
            splits[depth] = node.split.?;
            directions[depth] = true;
            self.collectRules(node.left.?, splits, directions, depth + 1);
            directions[depth] = false;
            self.collectRules(node.right.?, splits, directions, depth + 1);
            return;
        }
        var rule: Rule = .{ .leaf = node };
        for (self.data.attributes, 0..) |attribute, a| {
            var condition: Condition = .{ .attribute = a };
            var found = false;
            for (splits[0..depth], directions[0..depth]) |split, left| {
                if (split.attribute != a) continue;
                found = true;
                if (attribute.integer) {
                    if (left) condition.upper = if (condition.upper) |upper| @min(upper, split.point) else split.point
                    else condition.lower = if (condition.lower) |lower| @max(lower, split.point) else split.point;
                } else if (left) condition.equal = split.point
                else condition.excluded[@intCast(split.point)] = true;
            }
            if (found) { rule.conditions.values[rule.conditions.len] = condition; rule.conditions.len += 1; }
        }
        self.rules[self.rule_count] = rule;
        self.rule_count += 1;
    }
    fn holds(self: *const Analysis, condition: Condition, row: *const D.Row) bool {
        const value = row.values[condition.attribute];
        if (value < 0) return false;
        if (self.data.attributes[condition.attribute].integer) return (condition.lower == null or 2 * value > condition.lower.?) and (condition.upper == null or 2 * value <= condition.upper.?);
        return if (condition.equal) |equal| value == equal else !condition.excluded[@intCast(value)];
    }
    fn coverage(self: *const Analysis, conditions: Conditions, rows: D.Rows, label: usize) I.Fraction {
        var result: I.Fraction = .{ .numerator = 0, .denominator = 0 };
        for (rows.slice()) |row| {
            var covered = true;
            for (conditions.slice()) |condition| { if (!self.holds(condition, row)) covered = false; }
            if (!covered) continue;
            result.denominator += 1;
            if (row.label == label) result.numerator += 1;
        }
        return result;
    }
    fn laplace(self: *const Analysis, conditions: Conditions, label: usize) I.Fraction {
        var result = self.coverage(conditions, self.validation, label);
        result.numerator += 1;
        result.denominator += D.n(self.data.classes.len);
        return result;
    }
    fn generalize(self: *const Analysis, rule: *Rule) void {
        rule.generalized = rule.conditions;
        while (rule.generalized.len > 0) {
            const current = self.laplace(rule.generalized, rule.leaf.stats.prediction);
            var best: ?I.Fraction = null;
            var chosen: usize = 0;
            for (0..rule.generalized.len) |i| {
                const estimate = self.laplace(rule.generalized.remove(i), rule.leaf.stats.prediction);
                if (best == null or I.compare(estimate, best.?) > 0) { best = estimate; chosen = i; }
            }
            if (I.compare(best.?, current) < 0) break;
            rule.removed[rule.removed_count] = rule.generalized.values[chosen].attribute;
            rule.removed_count += 1;
            rule.generalized = rule.generalized.remove(chosen);
        }
    }
    fn conditionText(self: *const Analysis, condition: Condition) []const u8 {
        const attribute = self.data.attributes[condition.attribute];
        if (attribute.integer) {
            if (condition.lower != null and condition.upper != null) return D.fmt("{s} < {s} <= {s}", .{ halfText(condition.lower.?), attribute.name, halfText(condition.upper.?) });
            if (condition.lower) |lower| return D.fmt("{s} > {s}", .{ attribute.name, halfText(lower) });
            return D.fmt("{s} <= {s}", .{ attribute.name, halfText(condition.upper.?) });
        }
        if (condition.equal) |equal| return D.fmt("{s} = {s}", .{ attribute.name, attribute.values[@intCast(equal)] });
        var names: D.Text = .{};
        var count: usize = 0;
        for (attribute.values, 0..) |name, i| {
            if (!condition.excluded[i]) continue;
            names.add("{s}{s}", .{ if (count > 0) "," else "", name });
            count += 1;
        }
        return if (count == 1) D.fmt("{s} != {s}", .{ attribute.name, names.value() }) else D.fmt("{s} not in {{{s}}}", .{ attribute.name, names.value() });
    }
    fn conditionsText(self: *const Analysis, conditions: Conditions) []const u8 {
        if (conditions.len == 0) return "true";
        var result: D.Text = .{};
        for (conditions.slice(), 0..) |condition, i| result.add("{s}{s}", .{ if (i > 0) " and " else "", self.conditionText(condition) });
        return result.value();
    }
    fn nodeLines(self: *const Analysis, tree: *const E.Tree, node: *const B.Node, condition: []const u8, result: *D.Lines) void {
        var line: D.Text = .{};
        for (0..2 * node.depth) |_| line.write(" ");
        line.add("{d} {s} n {d} counts {s}", .{ node.number, condition, node.stats.size, E.countsText(node.stats.counts[0..self.data.classes.len]) });
        if (tree.isLeaf(node)) line.add(" leaf {s}", .{self.data.classes[node.stats.prediction]});
        result.write(line.value());
        if (!tree.isLeaf(node)) {
            self.nodeLines(tree, node.left.?, splitText(self.data, node.split.?, true), result);
            self.nodeLines(tree, node.right.?, splitText(self.data, node.split.?, false), result);
        }
    }
    fn treeLines(self: *const Analysis, tree: *const E.Tree) D.Lines {
        var result: D.Lines = .{};
        self.nodeLines(tree, tree.root, "root", &result);
        result.write("");
        const nodes = tree.preorder(null);
        const leaves = tree.leaves(null);
        const depth = tree.depth();
        result.add("nodes {d} leaves {d} depth {d} errors {s}", .{ nodes.len, leaves.len, depth, E.ratio(tree.trainingErrors(), D.n(self.train.len)) });
        for (0..depth + 1) |level| {
            var count: i64 = 0;
            var leaf_count: i64 = 0;
            var rows: i64 = 0;
            var errors: i64 = 0;
            for (nodes.slice()) |node| {
                if (node.depth != level) continue;
                count += 1;
                if (tree.isLeaf(node)) { leaf_count += 1; rows += node.stats.size; errors += node.stats.errors; }
            }
            result.add("level {d} nodes {d} leaves {d} rows {d} errors {d}", .{ level, count, leaf_count, rows, errors });
        }
        return result;
    }
    fn rootLines(self: *const Analysis) D.Lines {
        var found: [12]B.Candidate = undefined;
        var count: usize = 0;
        for (0..self.data.attributes.len) |attribute| {
            const candidate = self.builder.bestForAttribute(self.train, attribute) orelse continue;
            var i = count;
            count += 1;
            while (i > 0 and I.compare(candidate.value, found[i - 1].value) > 0) : (i -= 1) found[i] = found[i - 1];
            found[i] = candidate;
        }
        var result: D.Lines = .{};
        result.add("root candidates n {d} counts {s}", .{ self.train.len, E.countsText(self.root.stats.counts[0..self.data.classes.len]) });
        for (found[0..count], 1..) |candidate, rank| {
            const size = D.real(self.train.len);
            const gain = D.real(candidate.value.numerator) / D.real(candidate.value.denominator) / size - D.real(self.root.stats.squares) / (size * size);
            result.add("{d} {s} left {d} right {d} gain {s}", .{ rank, splitText(self.data, candidate.split, true), candidate.left.len, candidate.right.len, E.realText(gain, 6) });
        }
        return result;
    }
    fn surrogateLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        result.write("surrogates");
        const nodes = self.grown.preorder(null);
        for (nodes.slice()) |node| {
            const primary = node.split orelse continue;
            var listed: D.Text = .{};
            for (node.surrogates[0..node.surrogate_count], 0..) |surrogate, i| listed.add("{s}{s} {s} {d}/{d}", .{ if (i > 0) " ; " else "", splitText(self.data, surrogate.split, true), if (surrogate.forward) "left" else "right", surrogate.score, node.stats.size });
            result.add("node {d} split {s} default {s} surrogates {s}", .{ node.number, splitText(self.data, primary, true), if (node.default_left) "left" else "right", if (node.surrogate_count > 0) listed.value() else "none" });
        }
        return result;
    }
    fn pruningLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        var count: usize = 0;
        result.add("reduced_error_pruning validation {d}", .{self.validation.len});
        for (self.decisions[0..self.decision_count]) |decision| {
            if (decision.pruned) count += 1;
            result.add("node {d} depth {d} rows {d} leaf {d} subtree {d} {s}", .{ decision.node.number, decision.node.depth, decision.rows, decision.leaf_error, decision.subtree_error, if (decision.pruned) "pruned" else "kept" });
        }
        result.add("examined {d} pruned {d} kept {d}", .{ self.decision_count, count, self.decision_count - count });
        return result;
    }
    fn predictionLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        result.write("id,predicted,actual,grown,leaf,path,missing");
        for (self.test.slice(), 0..) |row, i| {
            const route = self.pruned_routes[i];
            var path: D.Text = .{};
            var missing: usize = 0;
            for (route.path[0 .. route.len + 1], 0..) |node, j| path.add("{s}{d}", .{ if (j > 0) "-" else "", node.number });
            for (route.steps[0..route.len]) |step| { if (step.method != .primary) missing += 1; }
            result.add("{s},{s},{s},{s},{d},{s},{d}", .{ row.id, self.data.classes[route.leaf.stats.prediction], self.data.classes[row.label], self.data.classes[self.grown_routes[i].leaf.stats.prediction], route.leaf.number, path.value(), missing });
        }
        return result;
    }
    fn ruleSections(self: *const Analysis) [3]D.Lines {
        var original: D.Lines = .{};
        var generalized: D.Lines = .{};
        var wrong: D.Lines = .{};
        var numbers = [_]usize{0} ** 2048;
        original.add("rules {d}", .{self.rule_count});
        generalized.add("generalized {d}", .{self.rule_count});
        for (self.rules[0..self.rule_count], 1..) |rule, number| {
            const label = rule.leaf.stats.prediction;
            numbers[rule.leaf.number] = number;
            var hits: i64 = 0;
            var count: i64 = 0;
            for (self.test.slice(), 0..) |row, i| {
                if (self.pruned_routes[i].leaf != rule.leaf) continue;
                count += 1;
                if (row.label == label) hits += 1;
            }
            original.add("rule {d} node {d} if {s} then {s} train {s} test {s}", .{ number, rule.leaf.number, self.conditionsText(rule.conditions), self.data.classes[label], E.ratio(rule.leaf.stats.counts[label], rule.leaf.stats.size), E.ratio(hits, count) });
            const validation = self.coverage(rule.generalized, self.validation, label);
            const test = self.coverage(rule.generalized, self.test, label);
            var removed: D.Text = .{};
            for (rule.removed[0..rule.removed_count], 0..) |attribute, i| removed.add("{s}{s}", .{ if (i > 0) "," else "", self.data.attributes[attribute].name });
            generalized.add("general {d} if {s} then {s} removed {s} laplace {s} validation {d}/{d} test {d}/{d}", .{ number, self.conditionsText(rule.generalized), self.data.classes[label], if (rule.removed_count > 0) removed.value() else "none", E.fraction(self.laplace(rule.generalized, label), 4), validation.numerator, validation.denominator, test.numerator, test.denominator });
        }
        for (self.test.slice(), 0..) |row, i| {
            const route = self.pruned_routes[i];
            if (route.leaf.stats.prediction == row.label) continue;
            var explanation: D.Text = .{};
            for (route.steps[0..route.len], 0..) |step, j| explanation.add("{s}{s}{s}", .{ if (j > 0) "; " else "", splitText(self.data, step.node.split.?, step.left), if (step.method == .primary) "" else if (step.method == .surrogate) " [surrogate]" else " [default]" });
            wrong.add("{s} actual {s} predicted {s} rule {d} path {s}", .{ row.id, self.data.classes[row.label], self.data.classes[route.leaf.stats.prediction], numbers[route.leaf.number], if (route.len > 0) explanation.value() else "root" });
        }
        var mistakes: D.Lines = .{};
        mistakes.add("misclassified {d}", .{wrong.data.items.len});
        mistakes.extend(wrong);
        return .{ original, generalized, mistakes };
    }
    fn dataLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        result.add("data train {d} validation {d} test {d} attributes {d} classes {d} target {s}", .{ self.train.len, self.validation.len, self.test.len, self.data.attributes.len, self.data.classes.len, self.data.target });
        const train = I.statistics(self.train, self.data.classes.len);
        const validation = I.statistics(self.validation, self.data.classes.len);
        const test = I.statistics(self.test, self.data.classes.len);
        for (self.data.classes, 0..) |class, k| result.add("class {s} train {d} validation {d} test {d}", .{ class, train.counts[k], validation.counts[k], test.counts[k] });
        var val_missing = [_]i64{0} ** 12;
        var test_missing = [_]i64{0} ** 12;
        var vm: i64 = 0;
        var tm: i64 = 0;
        for (self.validation.slice()) |row| {
            for (row.values[0..self.data.attributes.len], 0..) |value, i| { if (value < 0) { val_missing[i] += 1; vm += 1; } }
        }
        for (self.test.slice()) |row| {
            for (row.values[0..self.data.attributes.len], 0..) |value, i| { if (value < 0) { test_missing[i] += 1; tm += 1; } }
        }
        result.add("missing validation {d} test {d}", .{ vm, tm });
        for (self.data.attributes, 0..) |attribute, i| result.add("missing {s} validation {d} test {d}", .{ attribute.name, val_missing[i], test_missing[i] });
        return result;
    }
    fn summaryLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        const trees = [_]E.Tree{ self.grown, self.pruned };
        const names = [_][]const u8{ "grown", "pruned" };
        for (trees, names) |tree, name| result.add("{s} nodes {d} leaves {d} depth {d} train {s} validation {s} test {s}", .{ name, tree.preorder(null).len, tree.leaves(null).len, tree.depth(), self.accuracy(&tree, self.train), self.accuracy(&tree, self.validation), self.accuracy(&tree, self.test) });
        return result;
    }
    fn routingLines(self: *const Analysis) D.Lines {
        var tallies = [_][3]i64{[_]i64{0} ** 3} ** 2048;
        for (self.pruned_routes[0..self.test.len]) |route| {
            for (route.steps[0..route.len]) |step| tallies[step.node.number][@intFromEnum(step.method)] += 1;
        }
        var result: D.Lines = .{};
        result.write("routing pruned test");
        const nodes = self.pruned.preorder(null);
        for (nodes.slice()) |node| {
            if (self.pruned.isLeaf(node)) continue;
            const tally = tallies[node.number];
            result.add("node {d} rows {d} primary {d} surrogate {d} default {d}", .{ node.number, tally[0] + tally[1] + tally[2], tally[0], tally[1], tally[2] });
        }
        for (0..2) |incomplete| {
            var rows: D.Rows = .{};
            for (self.test.slice()) |row| {
                var missing = false;
                for (row.values[0..self.data.attributes.len]) |value| { if (value < 0) missing = true; }
                if (missing == (incomplete == 1)) rows.add(row);
            }
            result.add("{s} rows {d} correct {s}", .{ if (incomplete == 1) "incomplete" else "complete", rows.len, self.accuracy(&self.pruned, rows) });
        }
        return result;
    }
    fn mcnemarLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        result.write("mcnemar pruned test");
        for ([_]Model{ .grown, .depth, .cost_complexity, .bagging }) |model| {
            var b: i64 = 0;
            var c: i64 = 0;
            for (self.test.slice(), 0..) |row, i| {
                const first = self.predictions[@intFromEnum(Model.pruned)][i] == row.label;
                const second = self.predictions[@intFromEnum(model)][i] == row.label;
                if (first and !second) b += 1;
                if (second and !first) c += 1;
            }
            const absolute = if (b > c) b - c else c - b;
            const difference = @max(0, absolute - 1);
            const numerator = difference * difference;
            result.add("versus {s} b {d} c {d} statistic {s} significant {s}", .{ @tagName(model), b, c, E.fraction(.{ .numerator = numerator, .denominator = if (b + c > 0) b + c else 1 }, 4), if (1000 * numerator > 3841 * (b + c)) "yes" else "no" });
        }
        return result;
    }
    fn aucLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        for ([_]Model{ .grown, .pruned, .bagging }) |model| {
            var scores: [300][6]i64 = undefined;
            var denominators: [300]i64 = undefined;
            for (0..self.test.len) |i| {
                if (model == .bagging) {
                    scores[i] = self.test_votes[i];
                    denominators[i] = D.n(self.data.settings.bag_trees);
                } else {
                    const leaf = if (model == .grown) self.grown_routes[i].leaf else self.pruned_routes[i].leaf;
                    scores[i] = leaf.stats.counts;
                    denominators[i] = leaf.stats.size;
                }
            }
            var line: D.Text = .{};
            line.add("auc {s}", .{@tagName(model)});
            var macro: f64 = 0;
            var available: usize = 0;
            for (self.data.classes, 0..) |class, k| {
                var positives: i64 = 0;
                var wins: i64 = 0;
                for (self.test.slice(), 0..) |positive, p| {
                    if (positive.label != k) continue;
                    positives += 1;
                    for (self.test.slice(), 0..) |negative, n| {
                        if (negative.label == k) continue;
                        const order = I.compare(.{ .numerator = scores[p][k], .denominator = denominators[p] }, .{ .numerator = scores[n][k], .denominator = denominators[n] });
                        if (order > 0) wins += 2 else if (order == 0) wins += 1;
                    }
                }
                const denominator = 2 * positives * (D.n(self.test.len) - positives);
                line.add(" {s} {s}", .{ class, E.fraction(.{ .numerator = wins, .denominator = denominator }, 4) });
                if (denominator > 0) { macro += D.real(wins) / D.real(denominator); available += 1; }
            }
            line.add(" macro {s}", .{if (available > 0) E.realText(macro / D.real(available), 4) else "-"});
            result.write(line.value());
        }
        return result;
    }
    fn learningLines(self: *const Analysis) D.Lines {
        var result: D.Lines = .{};
        result.write("learning_curve");
        for (self.data.settings.curve) |size| {
            var training = self.train;
            training.len = size;
            const root = self.builder.grow(training, 1, 0);
            const tree: E.Tree = .{ .root = root };
            const pruning = P.reducedError(self.data, root, self.validation);
            result.add("size {d} grown leaves {d} test {s} pruned leaves {d} test {s}", .{ size, tree.leaves(null).len, self.accuracy(&tree, self.test), pruning.tree.leaves(null).len, self.accuracy(&pruning.tree, self.test) });
        }
        return result;
    }
    fn impurityLines(self: *const Analysis, title: []const u8, tree: *const E.Tree) D.Lines {
        var importance = [_]f64{0} ** 12;
        var splits = [_]usize{0} ** 12;
        var shares: [12]f64 = undefined;
        var rounded: [12]i64 = undefined;
        var order: [12]usize = undefined;
        const nodes = tree.preorder(null);
        for (nodes.slice()) |node| {
            if (tree.isLeaf(node)) continue;
            const attribute = node.split.?.attribute;
            importance[attribute] += I.decrease(node.stats, node.left.?.stats, node.right.?.stats);
            splits[attribute] += 1;
        }
        var total: f64 = 0;
        for (importance[0..self.data.attributes.len]) |value| total += value;
        for (0..self.data.attributes.len) |attribute| {
            shares[attribute] = if (total == 0) 0 else importance[attribute] / total;
            rounded[attribute] = @intFromFloat(@round(shares[attribute] * 10000));
            var i = attribute;
            while (i > 0 and rounded[order[i - 1]] < rounded[attribute]) : (i -= 1) order[i] = order[i - 1];
            order[i] = attribute;
        }
        var result: D.Lines = .{};
        result.add("impurity {s}", .{title});
        for (order[0..self.data.attributes.len], 1..) |attribute, rank| result.add("{d} {s} decrease {s} share {s} splits {d}", .{ rank, self.data.attributes[attribute].name, E.realText(importance[attribute] / D.real(self.train.len), 4), E.realText(shares[attribute], 4), splits[attribute] });
        return result;
    }
    fn permutationLines(self: *const Analysis) D.Lines {
        var generator: Minstd = .{ .state = self.data.settings.permutation_seed };
        const repeats = self.data.settings.repeats;
        const base = self.pruned.correct(self.data, self.test);
        var counts: [12][10]i64 = undefined;
        var drops: [12]i64 = undefined;
        var order: [12]usize = undefined;
        for (0..self.data.attributes.len) |attribute| {
            var total: i64 = 0;
            for (0..repeats) |repeat| {
                var values: [300]i64 = undefined;
                for (self.test.slice(), 0..) |row, i| values[i] = row.values[attribute];
                var i = self.test.len;
                while (i > 1) : (i -= 1) {
                    const j: usize = @intCast(@mod(generator.draw(), D.n(i)));
                    const saved = values[i - 1];
                    values[i - 1] = values[j];
                    values[j] = saved;
                }
                var correct: i64 = 0;
                for (self.test.slice(), 0..) |row, index| {
                    var changed = row.*;
                    changed.values[attribute] = values[index];
                    if (self.pruned.predict(self.data, &changed) == changed.label) correct += 1;
                }
                counts[attribute][repeat] = correct;
                total += correct;
            }
            drops[attribute] = D.n(repeats) * base - total;
            var i = attribute;
            while (i > 0 and drops[order[i - 1]] < drops[attribute]) : (i -= 1) order[i] = order[i - 1];
            order[i] = attribute;
        }
        var result: D.Lines = .{};
        result.add("permutation pruned test repeats {d} seed {d} base {s}", .{ repeats, self.data.settings.permutation_seed, E.ratio(base, D.n(self.test.len)) });
        for (order[0..self.data.attributes.len], 1..) |attribute, rank| result.add("{d} {s} correct {s} drop {s}", .{ rank, self.data.attributes[attribute].name, E.countsText(counts[attribute][0..repeats]), E.fraction(.{ .numerator = drops[attribute], .denominator = D.n(repeats * self.test.len) }, 4) });
        return result;
    }
    fn writeFiles(self: *const Analysis, io: std.Io) !void {
        const directory = std.Io.Dir.cwd();
        try directory.createDirPath(io, "output");
        try writeSections(io, "tree.txt", &.{ self.rootLines(), self.treeLines(&self.grown), self.surrogateLines() });
        try writeSections(io, "pruned_tree.txt", &.{ self.pruningLines(), self.treeLines(&self.pruned) });
        try writeSections(io, "predictions.csv", &.{self.predictionLines()});
        const rule_sections = self.ruleSections();
        try writeSections(io, "rules.txt", &rule_sections);
        try writeSections(io, "evaluation.txt", &.{
            self.dataLines(), self.summaryLines(),
            E.classification(self.data, "grown test", self.test, self.predictions[@intFromEnum(Model.grown)][0..self.test.len]),
            E.classification(self.data, "pruned test", self.test, self.predictions[@intFromEnum(Model.pruned)][0..self.test.len]),
            self.routingLines(), self.cross_lines, self.depth_lines, self.complexity_lines, self.bag_lines, self.mcnemarLines(), self.aucLines(), self.learningLines(),
        });
        try writeSections(io, "importance.txt", &.{ self.impurityLines("grown", &self.grown), self.impurityLines("pruned", &self.pruned), self.permutationLines() });
    }
};
fn writeSections(io: std.Io, name: []const u8, sections: []const D.Lines) !void {
    var text: D.Text = .{};
    for (sections, 0..) |section, i| {
        if (i > 0) text.write("\n");
        for (section.data.items) |line| text.add("{s}\n", .{line});
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = D.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    D.allocator = arena.allocator();
    const data = try D.load(init.io);
    const analysis = try D.allocator.create(Analysis);
    analysis.* = Analysis.init(&data);
    try analysis.writeFiles(init.io);
}
