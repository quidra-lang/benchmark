const std = @import("std");
const d = @import("dataset.zig");
const distances = @import("distances.zig");
const a = @import("agglomerative.zig");
const den = @import("dendrogram.zig");
const v = @import("validation.zig");

fn real(value: ?f64) []const u8 {
    const number = value orelse return "-";
    const text = d.fmt("{d:.4}", .{number});
    return if (d.eq(text, "-0.0000")) "0.0000" else text;
}
fn fourDigit(value: f64) f64 { return d.floating(real(value)); }
fn reals(values: []const f64) []const u8 {
    var text: d.Text = .{};
    for (values, 0..) |value, index| text.add("{s}{s}", .{ if (index > 0) " " else "", real(value) });
    return text.value();
}
fn integers(values: anytype) []const u8 {
    var text: d.Text = .{};
    for (values, 0..) |value, index| text.add("{s}{d}", .{ if (index > 0) " " else "", value });
    return text.value();
}
fn ariText(fraction: v.Fraction) []const u8 { return d.fmt("{d}/{d} {s}", .{ fraction.numerator, fraction.denominator, real(fraction.value()) }); }
fn maximum(values: []const f64) f64 {
    var result = values[0];
    for (values[1..]) |value| result = @max(result, value);
    return result;
}
fn groupsOf(partition: []const usize) usize {
    var groups: usize = 0;
    for (partition) |number| groups = @max(groups, number);
    return groups;
}
fn zeroBased(partition: []const usize) []usize {
    const result = d.alloc(usize, partition.len);
    for (partition, result) |number, *value| value.* = number - 1;
    return result;
}
fn partitionAri(first: []const usize, second: []const usize) v.Fraction {
    return v.adjustedRand(v.contingency(zeroBased(first), zeroBased(second), groupsOf(first), groupsOf(second)));
}
fn pairValues(matrix: d.Matrix) []f64 {
    const count = matrix.len;
    const result = d.alloc(f64, count * (count - 1) / 2);
    var position: usize = 0;
    for (0..count) |i| {
        for (i + 1..count) |j| { result[position] = matrix[i][j]; position += 1; }
    }
    return result;
}
fn histogramBin(value: f64, upper: f64) usize { return @intFromFloat(@min(9, @floor(10 * value / upper))); }
fn clusterMembers(partition: []const usize, groups: usize) [][]usize {
    var sizes: [120]usize = @splat(0);
    for (partition) |number| sizes[number - 1] += 1;
    const members = d.alloc([]usize, groups);
    for (members, sizes[0..groups]) |*group, size| group.* = d.alloc(usize, size);
    var positions: [120]usize = @splat(0);
    for (partition, 0..) |number, index| {
        const group = number - 1;
        members[group][positions[group]] = index;
        positions[group] += 1;
    }
    return members;
}
fn centroid(vectors: d.Matrix) []f64 {
    const center = d.alloc(f64, vectors[0].len);
    for (center, 0..) |*component, feature| {
        var total: f64 = 0;
        for (vectors) |vector| total += vector[feature];
        component.* = total / d.f(vectors.len);
    }
    return center;
}
fn majorityClass(row: []const i64) usize {
    var best: usize = 0;
    for (1..row.len) |class| if (row[class] > row[best]) { best = class; };
    return best;
}
fn floatOrder(_: void, first: f64, second: f64) bool { return first < second; }
fn numberOrder(_: void, first: usize, second: usize) bool { return first < second; }
const ScoreOrder = struct { values: []const f64, descending: bool, rounded: bool = false };
fn scoreOrder(context: ScoreOrder, first: usize, second: usize) bool {
    const a_value = if (context.rounded) fourDigit(context.values[first]) else context.values[first];
    const b_value = if (context.rounded) fourDigit(context.values[second]) else context.values[second];
    if (a_value == b_value) return first < second;
    return if (context.descending) a_value > b_value else a_value < b_value;
}
const Minstd = struct {
    state: i64,
    fn draw(self: *Minstd) usize {
        self.state = @mod(48271 * self.state, 2147483647);
        return @intCast(self.state);
    }
};
const Tree = struct {
    merges: []a.Merge,
    count: usize,
    heights: []f64,
    children: []den.Children,
    order: []usize,
    members: [][]usize,
    depths: []usize,
    subtree_heights: []f64,

    fn create(merges: []a.Merge, count: usize) *Tree {
        const tree = &d.alloc(Tree, 1)[0];
        const children = den.orderedChildren(merges, count);
        tree.* = .{
            .merges = merges, .count = count, .heights = d.alloc(f64, merges.len),
            .children = children, .order = den.leafOrder(children, count),
            .members = d.alloc([]usize, 2 * count - 1), .depths = d.alloc(usize, 2 * count - 1),
            .subtree_heights = d.alloc(f64, merges.len),
        };
        for (0..count) |index| {
            tree.members[index] = d.alloc(usize, 1);
            tree.members[index][0] = index;
            tree.depths[index] = 0;
        }
        for (merges, 0..) |merge, step| {
            const node = count + step;
            const first = tree.members[merge.a];
            const second = tree.members[merge.b];
            tree.members[node] = d.alloc(usize, first.len + second.len);
            @memcpy(tree.members[node][0..first.len], first);
            @memcpy(tree.members[node][first.len..], second);
            tree.heights[step] = merge.height;
            tree.depths[node] = 1 + @max(tree.depths[merge.a], tree.depths[merge.b]);
            tree.subtree_heights[step] = @max(merge.height, @max(tree.subtreeHeight(merge.a), tree.subtreeHeight(merge.b)));
        }
        return tree;
    }
    fn root(self: *const Tree) usize { return 2 * self.count - 2; }
    fn heightOf(self: *const Tree, node: usize) f64 { return if (node < self.count) 0 else self.heights[node - self.count]; }
    fn subtreeHeight(self: *const Tree, node: usize) f64 { return if (node < self.count) 0 else self.subtree_heights[node - self.count]; }
    fn partition(self: *const Tree, selected: []const bool) []usize {
        const owners = d.sequence(self.count);
        for (selected, 0..) |chosen, step| {
            if (chosen) {
                const node = self.count + step;
                for (self.members[node]) |object| owners[object] = node;
            }
        }
        var numbers: [239]usize = @splat(0);
        var groups: usize = 0;
        for (self.order) |object| {
            if (numbers[owners[object]] == 0) { groups += 1; numbers[owners[object]] = groups; }
        }
        const result = d.alloc(usize, self.count);
        for (owners, result) |owner, *number| number.* = numbers[owner];
        return result;
    }
    fn cutAtHeight(self: *const Tree, height: f64) []usize {
        var selected: [119]bool = undefined;
        for (self.subtree_heights, 0..) |value, step| selected[step] = value <= height;
        return self.partition(selected[0..self.merges.len]);
    }
    fn cutInto(self: *const Tree, count: usize) []usize {
        var selected: [119]bool = undefined;
        for (0..self.merges.len) |step| selected[step] = step < self.count - count;
        return self.partition(selected[0..self.merges.len]);
    }
    fn cophenetic(self: *const Tree) d.Matrix {
        const matrix = d.matrix(self.count, self.count);
        for (self.merges) |merge| {
            for (self.members[merge.a]) |i| {
                for (self.members[merge.b]) |j| { matrix[i][j] = merge.height; matrix[j][i] = merge.height; }
            }
        }
        return matrix;
    }
    fn joiningHeights(self: *const Tree) []f64 {
        const heights = d.alloc(f64, self.count);
        for (self.merges) |merge| {
            if (merge.a < self.count) heights[merge.a] = merge.height;
            if (merge.b < self.count) heights[merge.b] = merge.height;
        }
        return heights;
    }
    fn collectHeights(self: *const Tree, step: usize, depth: usize, sequence: *std.ArrayList(f64)) void {
        if (depth == 0) return;
        const merge = self.merges[step];
        d.append(f64, sequence, merge.height);
        for ([_]usize{ merge.a, merge.b }) |child| if (child >= self.count) { self.collectHeights(child - self.count, depth - 1, sequence); };
    }
    fn newick(self: *const Tree, node: usize, idents: []const []const u8) []const u8 {
        if (node < self.count) return idents[node];
        const pair = self.children[node - self.count];
        const height = self.heightOf(node);
        return d.fmt("({s}:{s},{s}:{s})", .{ self.newick(pair.upper, idents), real(height - self.heightOf(pair.upper)), self.newick(pair.lower, idents), real(height - self.heightOf(pair.lower)) });
    }
};
const Evaluation = struct {
    partition: []usize,
    sizes: []usize,
    silhouette: ?f64,
    dunn: ?f64,
    wss: f64,
    ch: ?f64,
    ari: v.Fraction,
    fn text(self: Evaluation) []const u8 {
        return d.fmt("sizes {s} silhouette {s} dunn {s} wss {s} ch {s} ari {s}", .{ integers(self.sizes), real(self.silhouette), real(self.dunn), real(self.wss), real(self.ch), ariText(self.ari) });
    }
};
const LinkageResult = struct {
    method: []const u8,
    tree: *Tree,
    cophenetic: []f64,
    correlation: f64,
    height_cuts: []Evaluation,
    count_cuts: []Evaluation,
    label_partition: []usize,
};
const Study = struct {
    features: []const []const u8,
    settings: d.Settings,
    count: usize,
    idents: []const []const u8,
    labels: []const []const u8,
    classes: []const []const u8,
    targets: []usize,
    raw: d.Matrix,
    statistics: distances.Statistics,
    vectors: d.Matrix,
    delta: d.Matrix,
    distance_pairs: []f64,
    distance_max: f64,
    neighbors: []usize,
    results: []*LinkageResult,
    chosen: *LinkageResult = undefined,
    kappa: usize = 0,
    selected_cut: Evaluation = undefined,
    selected: []usize = undefined,
    members: [][]usize = undefined,
    silhouettes: []f64 = undefined,
    table: v.Table = undefined,
    majority: []usize = undefined,

    fn create(observations: d.Observations, settings: d.Settings) *Study {
        const study = &d.alloc(Study, 1)[0];
        const labels = d.alloc([]const u8, observations.labels.len);
        @memcpy(labels, observations.labels);
        std.mem.sort([]const u8, labels, {}, d.stringOrder);
        var class_count: usize = 0;
        for (labels) |label| {
            if (class_count == 0 or !d.eq(labels[class_count - 1], label)) { labels[class_count] = label; class_count += 1; }
        }
        const targets = d.alloc(usize, observations.labels.len);
        for (observations.labels, targets) |label, *target| {
            for (labels[0..class_count], 0..) |class, index| if (d.eq(class, label)) { target.* = index; break; };
        }
        const statistics = distances.featureStatistics(observations.raw);
        const vectors = if (d.eq(settings.standardize, "yes")) distances.standardize(observations.raw, statistics) else observations.raw;
        const delta = distances.distanceMatrix(vectors, settings.distance);
        const distance_pairs = pairValues(delta);
        study.* = .{
            .features = observations.features, .settings = settings, .count = observations.idents.len,
            .idents = observations.idents, .labels = observations.labels, .classes = labels[0..class_count],
            .targets = targets, .raw = observations.raw, .statistics = statistics, .vectors = vectors,
            .delta = delta, .distance_pairs = distance_pairs, .distance_max = maximum(distance_pairs),
            .neighbors = d.alloc(usize, delta.len), .results = d.alloc(*LinkageResult, settings.linkages.len),
        };
        for (study.neighbors, 0..) |*neighbor, i| neighbor.* = study.nearestNeighbor(i);
        for (settings.linkages, study.results) |method, *result| result.* = study.analyseLinkage(method);
        study.select();
        study.selected = study.selected_cut.partition;
        study.members = clusterMembers(study.selected, study.kappa);
        study.silhouettes = v.silhouetteValues(study.selected, study.kappa, delta);
        study.table = study.classTable(study.selected);
        study.majority = d.alloc(usize, study.kappa);
        for (study.table, study.majority) |row, *class| class.* = majorityClass(row);
        return study;
    }
    fn nearestNeighbor(self: *const Study, i: usize) usize {
        var best: ?usize = null;
        for (0..self.count) |j| if (i != j and (best == null or self.delta[i][j] < self.delta[i][best.?])) { best = j; };
        return best.?;
    }
    fn classTable(self: *const Study, partition: []const usize) v.Table { return v.contingency(zeroBased(partition), self.targets, groupsOf(partition), self.classes.len); }
    fn labelAri(self: *const Study, partition: []const usize) v.Fraction { return v.adjustedRand(self.classTable(partition)); }
    fn matchCount(self: *const Study, partition: []const usize) i64 {
        var matches: i64 = 0;
        for (self.classTable(partition)) |row| matches += row[majorityClass(row)];
        return matches;
    }
    fn meanSilhouette(partition: []const usize, delta: d.Matrix) ?f64 {
        const groups = groupsOf(partition);
        if (groups < 2) return null;
        return distances.sum(v.silhouetteValues(partition, groups, delta)) / d.f(partition.len);
    }
    fn centroids(self: *const Study, partition: []const usize) d.Matrix {
        const members = clusterMembers(partition, groupsOf(partition));
        const centers = d.alloc([]f64, members.len);
        for (members, centers) |group, *center| {
            const vectors = d.alloc([]f64, group.len);
            for (group, vectors) |i, *vector| vector.* = self.vectors[i];
            center.* = centroid(vectors);
        }
        return centers;
    }
    fn withinSum(self: *const Study, partition: []const usize) f64 {
        const centers = self.centroids(partition);
        var wss: f64 = 0;
        for (partition, self.vectors) |number, vector| wss += distances.squaredDistance(vector, centers[number - 1]);
        return wss;
    }
    fn dunnIndex(self: *const Study, partition: []const usize, groups: usize) ?f64 {
        var diameter: f64 = 0;
        var separation: ?f64 = null;
        for (0..self.count) |i| {
            for (i + 1..self.count) |j| {
                const value = self.delta[i][j];
                if (partition[i] == partition[j]) diameter = @max(diameter, value) else if (separation == null or value < separation.?) separation = value;
            }
        }
        return if (groups >= 2 and diameter > 0) separation.? / diameter else null;
    }
    fn evaluate(self: *const Study, partition: []usize) Evaluation {
        const groups = groupsOf(partition);
        const members = clusterMembers(partition, groups);
        const sizes = d.alloc(usize, groups);
        for (members, sizes) |group, *size| size.* = group.len;
        const wss = self.withinSum(partition);
        var ch: ?f64 = null;
        if (groups >= 2 and groups < self.count) {
            const overall = centroid(self.vectors);
            const centers = self.centroids(partition);
            var bss: f64 = 0;
            for (sizes, centers) |size, center| bss += d.f(size) * distances.squaredDistance(center, overall);
            ch = (bss / d.f(groups - 1)) / (wss / d.f(self.count - groups));
        }
        return .{ .partition = partition, .sizes = sizes, .silhouette = meanSilhouette(partition, self.delta), .dunn = self.dunnIndex(partition, groups), .wss = wss, .ch = ch, .ari = self.labelAri(partition) };
    }
    fn analyseLinkage(self: *const Study, method: []const u8) *LinkageResult {
        const tree = Tree.create(a.agglomerate(self.delta, method), self.count);
        const cophenetic = pairValues(tree.cophenetic());
        const height_cuts = d.alloc(Evaluation, self.settings.cut_heights.len);
        for (self.settings.cut_heights, height_cuts) |height, *cut| cut.* = self.evaluate(tree.cutAtHeight(height));
        const count_cuts = d.alloc(Evaluation, self.settings.cut_counts.len);
        for (self.settings.cut_counts, count_cuts) |count, *cut| cut.* = self.evaluate(tree.cutInto(count));
        const result = &d.alloc(LinkageResult, 1)[0];
        result.* = .{ .method = method, .tree = tree, .cophenetic = cophenetic, .correlation = v.correlation(self.distance_pairs, cophenetic), .height_cuts = height_cuts, .count_cuts = count_cuts, .label_partition = tree.cutInto(self.classes.len) };
        return result;
    }
    fn select(self: *Study) void {
        var chosen = self.results[0];
        var position: usize = 0;
        for (self.results) |result| {
            for (result.count_cuts, 0..) |cut, index| {
                if (cut.ari.greater(chosen.count_cuts[position].ari)) { chosen = result; position = index; }
            }
        }
        self.chosen = chosen;
        self.kappa = self.settings.cut_counts[position];
        self.selected_cut = chosen.count_cuts[position];
    }
    fn linkageTable(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.write("method,step,a,b,height,size");
        for (self.results) |result| {
            for (result.tree.merges, 1..) |merge, step| lines.add("{s},{d},{d},{d},{s},{d}", .{ result.method, step, merge.a, merge.b, real(merge.height), merge.size });
        }
        return lines;
    }
    fn clustersTable(self: *const Study) d.Lines {
        var header: d.Text = .{};
        header.write("id,label");
        for (self.results) |result| {
            for (1..self.settings.cut_heights.len + 1) |index| header.add(",{s}_h{d}", .{ result.method, index });
            for (self.settings.cut_counts) |count| header.add(",{s}_k{d}", .{ result.method, count });
        }
        var lines: d.Lines = .{};
        lines.write(header.value());
        for (0..self.count) |i| {
            var text: d.Text = .{};
            text.add("{s},{s}", .{ self.idents[i], self.labels[i] });
            for (self.results) |result| {
                for (result.height_cuts) |cut| text.add(",{d}", .{cut.partition[i]});
                for (result.count_cuts) |cut| text.add(",{d}", .{cut.partition[i]});
            }
            lines.write(text.value());
        }
        return lines;
    }
    fn dendrogramReport(self: *const Study) d.Lines {
        var report: d.Lines = .{};
        for (self.results) |result| {
            const tree = result.tree;
            const height_max = maximum(tree.heights);
            const columns = d.alloc(usize, self.settings.cut_heights.len);
            for (self.settings.cut_heights, columns) |height, *x| x.* = den.column(height, height_max, self.settings.width);
            var lines: d.Lines = .{};
            lines.add("dendrogram {s} height_max {s} width {d}", .{ result.method, real(height_max), self.settings.width });
            lines.extend(den.rows(tree.merges, tree.children, tree.order, self.idents, self.labels, height_max, columns, self.settings.width));
            for (self.settings.cut_heights, columns) |height, x| lines.add("cut {s} column {s}", .{ real(height), if (x <= self.settings.width) d.fmt("{d}", .{x}) else "-" });
            report.paragraph(lines);
        }
        return report;
    }
    fn treesReport(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        for (self.results) |result| lines.add("{s} {s};", .{ result.method, result.tree.newick(result.tree.root(), self.idents) });
        return lines;
    }
    fn pairText(self: *const Study, pair: [2]usize) []const u8 {
        return d.fmt("{s} {s} {s}", .{ real(self.delta[pair[0]][pair[1]]), self.idents[pair[0]], self.idents[pair[1]] });
    }
    fn dataPart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.add("data n {d} features {d} classes {d} distance {s} standardize {s}", .{ self.count, self.features.len, self.classes.len, self.settings.distance, self.settings.standardize });
        for (self.features, self.statistics.means, self.statistics.deviations) |name, mean, deviation| lines.add("feature {s} mean {s} sd {s}", .{ name, real(mean), real(deviation) });
        var smallest: [2]usize = .{ 0, 1 };
        var largest = smallest;
        for (0..self.count) |i| {
            for (i + 1..self.count) |j| {
                if (self.delta[i][j] < self.delta[smallest[0]][smallest[1]]) smallest = .{ i, j };
                if (self.delta[i][j] > self.delta[largest[0]][largest[1]]) largest = .{ i, j };
            }
        }
        lines.add("distances pairs {d} min {s} max {s} mean {s}", .{ self.distance_pairs.len, self.pairText(smallest), self.pairText(largest), real(distances.sum(self.distance_pairs) / d.f(self.distance_pairs.len)) });
        var nearest_total: f64 = 0;
        var reciprocal: usize = 0;
        for (self.neighbors, 0..) |neighbor, i| {
            nearest_total += self.delta[i][neighbor];
            if (i < neighbor and self.neighbors[neighbor] == i) reciprocal += 1;
        }
        lines.add("nearest_neighbors mean {s} reciprocal_pairs {d}", .{ real(nearest_total / d.f(self.count)), reciprocal });
        const labels = d.alloc(usize, self.count);
        for (self.targets, labels) |target, *number| number.* = target + 1;
        lines.add("labels {s}", .{self.evaluate(labels).text()});
        return lines;
    }
    fn correlationPart(self: *const Study) d.Lines {
        const columns = d.matrix(self.features.len, self.count);
        for (columns, 0..) |column, feature| {
            for (self.raw, column) |row, *value| value.* = row[feature];
        }
        var lines: d.Lines = .{};
        lines.add("correlation {s}", .{d.join(self.features, " ")});
        for (self.features, columns) |name, first| {
            const correlations = d.alloc(f64, columns.len);
            for (columns, correlations) |second, *value| value.* = v.correlation(first, second);
            lines.add("{s} {s}", .{ name, reals(correlations) });
        }
        return lines;
    }
    fn histogramPart(self: *const Study) d.Lines {
        var counts: [10]usize = @splat(0);
        for (self.distance_pairs) |value| counts[histogramBin(value, self.distance_max)] += 1;
        var highest: usize = 0;
        for (counts) |count| highest = @max(highest, count);
        var lines: d.Lines = .{};
        lines.write("histogram");
        for (counts, 0..) |count, bin| {
            const lower = d.f(bin) * self.distance_max / 10;
            const upper = d.f(bin + 1) * self.distance_max / 10;
            const length = count * 50 / highest;
            lines.add("{s} {s} {d}{s}{s}", .{ real(lower), real(upper), count, if (length > 0) " " else "", d.repeat('#', length) });
        }
        return lines;
    }
    fn gaps(self: *const Study, tree: *const Tree) []f64 {
        const ordered = d.alloc(f64, tree.subtree_heights.len);
        @memcpy(ordered, tree.subtree_heights);
        std.mem.sort(f64, ordered, {}, floatOrder);
        const values = d.alloc(f64, self.settings.gap_max_k - 1);
        for (values, 2..) |*value, count| value.* = ordered[self.count - count] - ordered[self.count - count - 1];
        return values;
    }
    fn inconsistencyLine(self: *const Study, tree: *const Tree, step: usize) []const u8 {
        var sequence: std.ArrayList(f64) = .empty;
        tree.collectHeights(step, self.settings.inconsistency_depth, &sequence);
        const size = sequence.items.len;
        const mean = distances.sum(sequence.items) / d.f(size);
        var deviation: f64 = 0;
        var coefficient: f64 = 0;
        if (size >= 2) {
            var squares: f64 = 0;
            for (sequence.items) |value| squares += (value - mean) * (value - mean);
            deviation = @sqrt(squares / d.f(size - 1));
            coefficient = (tree.heights[step] - mean) / deviation;
        }
        return d.fmt("step {d} height {s} mean {s} sd {s} count {d} coefficient {s}", .{ step + 1, real(tree.heights[step]), real(mean), real(deviation), size, real(coefficient) });
    }
    fn linkagePart(self: *const Study, result: *const LinkageResult) d.Lines {
        const tree = result.tree;
        var leaf_path: f64 = 0;
        for (0..self.count - 1) |row| leaf_path += self.delta[tree.order[row]][tree.order[row + 1]];
        var minimum = tree.heights[0];
        var inversions: usize = 0;
        for (tree.heights, 0..) |height, step| {
            minimum = @min(minimum, height);
            if (step > 0 and height < tree.heights[step - 1]) inversions += 1;
        }
        var lines: d.Lines = .{};
        lines.add("linkage {s}", .{result.method});
        lines.add("cophenetic {s} leaf_path {s}", .{ real(result.correlation), real(leaf_path) });
        lines.add("heights min {s} max {s} inversions {d}", .{ real(minimum), real(maximum(tree.heights)), inversions });
        for (tree.heights, 0..) |height, step| {
            if (step > 0 and height < tree.heights[step - 1]) lines.add("inversion step {d} height {s} previous {s}", .{ step + 1, real(height), real(tree.heights[step - 1]) });
        }
        const gap_values = self.gaps(tree);
        var suggested: usize = 2;
        for (3..self.settings.gap_max_k + 1) |count| if (fourDigit(gap_values[count - 2]) > fourDigit(gap_values[suggested - 2])) { suggested = count; };
        lines.add("gaps {s}", .{reals(gap_values)});
        lines.add("suggested_k {d}", .{suggested});
        const joining = tree.joiningHeights();
        const late = d.sequence(self.count);
        std.mem.sort(usize, late, ScoreOrder{ .values = joining, .descending = true }, scoreOrder);
        var late_text: d.Text = .{};
        late_text.write("late_joiners");
        for (late[0..self.settings.list_size]) |i| late_text.add(" {s}:{s}", .{ self.idents[i], real(joining[i]) });
        lines.write(late_text.value());
        var kinds: [3]usize = @splat(0);
        for (tree.merges) |merge| {
            const leaves = @as(usize, @intFromBool(merge.a < self.count)) + @as(usize, @intFromBool(merge.b < self.count));
            kinds[2 - leaves] += 1;
        }
        lines.add("merges leaf_leaf {d} leaf_cluster {d} cluster_cluster {d} depth {d}", .{ kinds[0], kinds[1], kinds[2], tree.depths[tree.root()] });
        const matches = self.matchCount(result.label_partition);
        lines.add("label_cut k {d} purity {d}/{d} {s}", .{ self.classes.len, matches, self.count, real(d.f(matches) / d.f(self.count)) });
        lines.add("inconsistency depth {s}", .{self.settings.depth_text});
        for (self.count - self.settings.inconsistency_count - 1..self.count - 1) |step| lines.write(self.inconsistencyLine(tree, step));
        for (self.settings.cut_heights, result.height_cuts) |height, cut| lines.add("cut height {s} clusters {d} {s}", .{ real(height), cut.sizes.len, cut.text() });
        for (self.settings.cut_counts, result.count_cuts) |count, cut| lines.add("cut k {d} {s}", .{ count, cut.text() });
        return lines;
    }
    fn resultOf(self: *const Study, method: []const u8) ?*LinkageResult {
        for (self.results) |result| if (d.eq(result.method, method)) return result;
        return null;
    }
    fn mstPart(self: *const Study) d.Lines {
        const single = self.resultOf("single").?;
        const edges = a.minimumSpanningTree(self.delta);
        const weights = d.alloc(f64, edges.len);
        var total: f64 = 0;
        var linked: [120][120]bool = @splat(@splat(false));
        for (edges, weights) |edge, *weight| {
            total += edge.weight;
            weight.* = edge.weight;
            linked[edge.parent][edge.child] = true;
            linked[edge.child][edge.parent] = true;
        }
        const numbers = d.sequence(edges.len);
        std.mem.sort(usize, numbers, ScoreOrder{ .values = weights, .descending = false }, scoreOrder);
        const ordered_weights = d.alloc(f64, weights.len);
        @memcpy(ordered_weights, weights);
        std.mem.sort(f64, ordered_weights, {}, floatOrder);
        var heights_match = true;
        for (ordered_weights, single.tree.heights) |weight, height| if (@abs(weight - height) > 0.000000001) { heights_match = false; };
        var nn_edges: usize = 0;
        for (self.neighbors, 0..) |neighbor, index| if (linked[index][neighbor]) { nn_edges += 1; };
        var lines: d.Lines = .{};
        lines.add("mst total {s} heights {s} nn_edges {d}/{d}", .{ real(total), if (heights_match) "match" else "mismatch", nn_edges, self.count });
        for (self.settings.cut_counts, single.count_cuts) |count, cut| {
            const components = d.sequence(self.count);
            for (numbers[0 .. self.count - count]) |number| {
                const edge = edges[number];
                const old = components[edge.child];
                const new = components[edge.parent];
                for (components) |*component| if (component.* == old) { component.* = new; };
            }
            var agrees = true;
            for (0..self.count) |i| {
                for (i + 1..self.count) |j| {
                    if ((components[i] == components[j]) != (cut.partition[i] == cut.partition[j])) agrees = false;
                }
            }
            lines.add("mst partition k {d} {s}", .{ count, if (agrees) "match" else "mismatch" });
        }
        return lines;
    }
    fn comparePart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.add("compare linkage {s} k {d}", .{ self.settings.compare_linkage, self.classes.len });
        for (distances.types) |kind| {
            const delta = distances.distanceMatrix(self.vectors, kind);
            const tree = Tree.create(a.agglomerate(delta, self.settings.compare_linkage), self.count);
            const cophenetic = v.correlation(pairValues(delta), pairValues(tree.cophenetic()));
            const partition = tree.cutInto(self.classes.len);
            lines.add("metric {s} cophenetic {s} silhouette {s} ari {s}", .{ kind, real(cophenetic), real(meanSilhouette(partition, delta)), ariText(self.labelAri(partition)) });
        }
        return lines;
    }
    fn copheneticPart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.write("cophenetic_matrix");
        lines.add("linkage {s}", .{d.join(self.settings.linkages, " ")});
        for (self.results) |first| {
            const values = d.alloc(f64, self.results.len);
            for (self.results, values) |second, *value| value.* = v.correlation(first.cophenetic, second.cophenetic);
            lines.add("{s} {s}", .{ first.method, reals(values) });
        }
        return lines;
    }
    fn agreementPart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.add("agreement k {d}", .{self.classes.len});
        lines.add("linkage {s}", .{d.join(self.settings.linkages, " ")});
        for (self.results) |first| {
            const values = d.alloc(f64, self.results.len);
            for (self.results, values) |second, *value| value.* = partitionAri(first.label_partition, second.label_partition).value();
            lines.add("{s} {s}", .{ first.method, reals(values) });
        }
        return lines;
    }
    fn summaryPart(self: *const Study) d.Lines {
        const coefficients = d.alloc(f64, self.results.len);
        for (self.results, coefficients) |result, *coefficient| coefficient.* = result.correlation;
        const ranking = d.sequence(self.results.len);
        std.mem.sort(usize, ranking, ScoreOrder{ .values = coefficients, .descending = true, .rounded = true }, scoreOrder);
        var ranking_text: d.Text = .{};
        ranking_text.write("cophenetic_ranking");
        for (ranking) |index| ranking_text.add(" {s}", .{self.results[index].method});
        var lines: d.Lines = .{};
        lines.write("summary");
        lines.write(ranking_text.value());
        for (self.settings.cut_counts, 0..) |count, position| {
            var best = self.results[0];
            for (self.results[1..]) |result| if (result.count_cuts[position].ari.greater(best.count_cuts[position].ari)) { best = result; };
            lines.add("best_ari k {d} {s} {s}", .{ count, best.method, ariText(best.count_cuts[position].ari) });
        }
        for (self.results) |result| {
            var best: usize = 0;
            for (1..self.settings.cut_counts.len) |position| {
                if (fourDigit(result.count_cuts[position].silhouette.?) > fourDigit(result.count_cuts[best].silhouette.?)) best = position;
            }
            lines.add("best_silhouette {s} k {d} {s}", .{ result.method, self.settings.cut_counts[best], real(result.count_cuts[best].silhouette) });
        }
        lines.add("selected {s} k {d}", .{ self.chosen.method, self.kappa });
        return lines;
    }
    fn validationReport(self: *const Study) d.Lines {
        var report: d.Lines = .{};
        report.paragraph(self.dataPart());
        report.paragraph(self.correlationPart());
        report.paragraph(self.histogramPart());
        for (self.results) |result| report.paragraph(self.linkagePart(result));
        if (self.resultOf("single") != null) report.paragraph(self.mstPart());
        report.paragraph(self.comparePart());
        report.paragraph(self.copheneticPart());
        report.paragraph(self.agreementPart());
        report.paragraph(self.summaryPart());
        return report;
    }
    fn clusterSeparation(self: *const Study, first: []const usize, second: []const usize) f64 {
        var best: ?f64 = null;
        for (first) |i| {
            for (second) |j| if (best == null or self.delta[i][j] < best.?) { best = self.delta[i][j]; };
        }
        return best.?;
    }
    fn clusterLines(self: *const Study, group_number: usize) d.Lines {
        const group = self.members[group_number];
        const size = group.len;
        var silhouette: f64 = 0;
        for (group) |i| silhouette += self.silhouettes[i];
        silhouette /= d.f(size);
        const majority = self.majority[group_number];
        const majority_count = self.table[group_number][majority];
        const means = d.alloc(f64, self.features.len);
        for (means, 0..) |*mean, feature| {
            var total: f64 = 0;
            for (group) |i| total += self.raw[i][feature];
            mean.* = total / d.f(size);
        }
        var medoid: ?usize = null;
        var medoid_sum: f64 = 0;
        for (group) |i| {
            var total: f64 = 0;
            for (group) |j| total += self.delta[i][j];
            if (medoid == null or total < medoid_sum) { medoid = i; medoid_sum = total; }
        }
        var widest: ?[2]usize = null;
        for (group, 0..) |i, position| {
            for (group[position + 1 ..]) |j| {
                if (widest == null or self.delta[i][j] > self.delta[widest.?[0]][widest.?[1]]) widest = .{ i, j };
            }
        }
        var nearest: ?usize = null;
        var nearest_separation: f64 = 0;
        for (self.members, 0..) |other, index| {
            if (index == group_number) continue;
            const separation = self.clusterSeparation(group, other);
            if (nearest == null or separation < nearest_separation) { nearest = index; nearest_separation = separation; }
        }
        var lines: d.Lines = .{};
        lines.add("cluster {d} size {d} silhouette {s} majority {s} purity {d}/{d} {s}", .{ group_number + 1, size, real(silhouette), self.classes[majority], majority_count, size, real(d.f(majority_count) / d.f(size)) });
        lines.add("  mean {s}", .{reals(means)});
        lines.add("  medoid {s} diameter {s} nearest {d} separation {s}", .{ self.idents[medoid.?], if (widest) |pair| self.pairText(pair) else "0.0000 - -", nearest.? + 1, real(nearest_separation) });
        return lines;
    }
    fn selectionPart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.add("selected linkage {s} k {d} ari {s} silhouette {s}", .{ self.chosen.method, self.kappa, ariText(self.selected_cut.ari), real(self.selected_cut.silhouette) });
        for (0..self.kappa) |group| lines.extend(self.clusterLines(group));
        return lines;
    }
    fn centroidPart(self: *const Study) d.Lines {
        const centers = self.centroids(self.selected);
        var lines: d.Lines = .{};
        lines.write("centroid_distances");
        for (centers, 1..) |first, group| {
            const values = d.alloc(f64, self.kappa);
            for (centers, values) |second, *value| value.* = @sqrt(distances.squaredDistance(first, second));
            lines.add("{d} {s}", .{ group, reals(values) });
        }
        return lines;
    }
    fn profilePart(self: *const Study) d.Lines {
        var name_width: usize = 0;
        for (self.features) |name| name_width = @max(name_width, name.len);
        var lines: d.Lines = .{};
        lines.write("profile_bars");
        for (self.members, 1..) |group, number| {
            lines.add("cluster {d}", .{number});
            for (self.features, 0..) |name, feature| {
                var total: f64 = 0;
                for (group) |i| total += (self.raw[i][feature] - self.statistics.means[feature]) / self.statistics.deviations[feature];
                const zeta = total / d.f(group.len);
                const length: usize = @intFromFloat(@min(10, @floor(@abs(zeta) * 4)));
                const bar = d.repeat('#', length);
                const left = if (zeta < 0) d.fmt("{s}{s}", .{ d.repeat(' ', 10 - length), bar }) else d.repeat(' ', 10);
                const right = if (zeta < 0) d.repeat(' ', 10) else d.fmt("{s}{s}", .{ bar, d.repeat(' ', 10 - length) });
                lines.add("{s}{s} {s}|{s} {s}", .{ name, d.repeat(' ', name_width - name.len), left, right, real(zeta) });
            }
        }
        return lines;
    }
    fn contingencyPart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.write("contingency");
        lines.add("cluster {s} total", .{d.join(self.classes, " ")});
        const totals = d.alloc(i64, self.classes.len);
        @memset(totals, 0);
        for (self.table, 1..) |row, group| {
            var total: i64 = 0;
            for (row, totals) |value, *column| { total += value; column.* += value; }
            lines.add("{d} {s} {d}", .{ group, integers(row), total });
        }
        lines.add("total {s} {d}", .{ integers(totals), self.count });
        const matches = self.matchCount(self.selected);
        lines.add("purity {d}/{d} {s}", .{ matches, self.count, real(d.f(matches) / d.f(self.count)) });
        return lines;
    }
    fn misplacedPart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.write("misplaced");
        var count: usize = 0;
        for (self.selected, 0..) |number, i| {
            const majority = self.majority[number - 1];
            if (self.targets[i] == majority) continue;
            count += 1;
            lines.add("{s} label {s} cluster {d} majority {s}", .{ self.idents[i], self.labels[i], number, self.classes[majority] });
        }
        lines.add("count {d}", .{count});
        return lines;
    }
    fn weakestPart(self: *const Study) d.Lines {
        const ordered = d.sequence(self.count);
        std.mem.sort(usize, ordered, ScoreOrder{ .values = self.silhouettes, .descending = false }, scoreOrder);
        var lines: d.Lines = .{};
        lines.write("weakest");
        for (ordered[0..self.settings.list_size]) |i| lines.add("{s} label {s} cluster {d} silhouette {s}", .{ self.idents[i], self.labels[i], self.selected[i], real(self.silhouettes[i]) });
        return lines;
    }
    fn featurePart(self: *const Study) d.Lines {
        const ratios = d.alloc(f64, self.features.len);
        for (ratios, 0..) |*ratio, feature| {
            var total: f64 = 0;
            for (self.vectors) |vector| total += vector[feature];
            const overall = total / d.f(self.count);
            const cluster_means = d.alloc(f64, self.kappa);
            for (self.members, cluster_means) |group, *mean| {
                var group_total: f64 = 0;
                for (group) |i| group_total += self.vectors[i][feature];
                mean.* = group_total / d.f(group.len);
            }
            var between: f64 = 0;
            for (self.members, cluster_means) |group, mean| between += d.f(group.len) * (mean - overall) * (mean - overall);
            var within: f64 = 0;
            for (self.selected, self.vectors) |number, vector| {
                const mean = cluster_means[number - 1];
                within += (vector[feature] - mean) * (vector[feature] - mean);
            }
            ratio.* = (between / d.f(self.kappa - 1)) / (within / d.f(self.count - self.kappa));
        }
        const ranking = d.sequence(self.features.len);
        std.mem.sort(usize, ranking, ScoreOrder{ .values = ratios, .descending = true, .rounded = true }, scoreOrder);
        var lines: d.Lines = .{};
        lines.write("features");
        for (ranking, 1..) |feature, rank| lines.add("{d} {s} f_ratio {s}", .{ rank, self.features[feature], real(ratios[feature]) });
        return lines;
    }
    fn classCounts(self: *const Study, tree: *const Tree, node: usize) []const u8 {
        var counts: [10]usize = @splat(0);
        for (tree.members[node]) |i| counts[self.targets[i]] += 1;
        var text: d.Text = .{};
        for (counts[0..self.classes.len], 0..) |count, index| text.add("{s}{d}", .{ if (index > 0) "/" else "", count });
        return text.value();
    }
    fn topMergesPart(self: *const Study) d.Lines {
        const tree = self.chosen.tree;
        var lines: d.Lines = .{};
        lines.write("top_merges");
        for (self.count - self.settings.inconsistency_count - 1..self.count - 1) |step| {
            const merge = tree.merges[step];
            lines.add("step {d} height {s} a {d} {d} {s} b {d} {d} {s}", .{ step + 1, real(merge.height), merge.a, tree.members[merge.a].len, self.classCounts(tree, merge.a), merge.b, tree.members[merge.b].len, self.classCounts(tree, merge.b) });
        }
        return lines;
    }
    fn dropFeaturePart(self: *const Study) d.Lines {
        var lines: d.Lines = .{};
        lines.write("drop_feature");
        for (self.features, 0..) |name, feature| {
            const reduced = d.matrix(self.count, self.features.len - 1);
            for (self.vectors, reduced) |source, target| {
                @memcpy(target[0..feature], source[0..feature]);
                @memcpy(target[feature..], source[feature + 1 ..]);
            }
            const delta = distances.distanceMatrix(reduced, self.settings.distance);
            const partition = Tree.create(a.agglomerate(delta, self.chosen.method), self.count).cutInto(self.kappa);
            lines.add("{s} ari_selected {s} ari_labels {s}", .{ name, ariText(partitionAri(partition, self.selected)), ariText(self.labelAri(partition)) });
        }
        return lines;
    }
    fn nearestCenter(vector: []const f64, centers: d.Matrix) usize {
        var best: usize = 0;
        var best_value = distances.squaredDistance(vector, centers[0]);
        for (1..centers.len) |group| {
            const value = distances.squaredDistance(vector, centers[group]);
            if (value < best_value) { best = group; best_value = value; }
        }
        return best + 1;
    }
    fn refinementPart(self: *const Study) d.Lines {
        const limit = self.settings.refine_iterations;
        const centers = self.centroids(self.selected);
        var previous = self.selected;
        var iterations = limit;
        for (1..limit + 1) |iteration| {
            const assignment = d.alloc(usize, self.count);
            for (self.vectors, assignment) |vector, *number| number.* = nearestCenter(vector, centers);
            if (std.mem.eql(usize, assignment, previous)) { iterations = iteration; break; }
            const members = clusterMembers(assignment, self.kappa);
            for (members, centers) |group, *center| {
                if (group.len == 0) continue;
                const vectors = d.alloc([]f64, group.len);
                for (group, vectors) |i, *vector| vector.* = self.vectors[i];
                center.* = centroid(vectors);
            }
            previous = assignment;
        }
        const refined = previous;
        var changed: usize = 0;
        for (self.selected, refined) |before, after| if (before != after) { changed += 1; };
        const sizes = d.alloc(usize, self.kappa);
        const members = clusterMembers(refined, self.kappa);
        for (members, sizes) |group, *size| size.* = group.len;
        var lines: d.Lines = .{};
        lines.add("refinement max_iterations {d}", .{limit});
        lines.add("iterations {d} changed {d} wss {s} -> {s}", .{ iterations, changed, real(self.withinSum(self.selected)), real(self.withinSum(refined)) });
        lines.add("sizes {s} silhouette {s}", .{ integers(sizes), real(meanSilhouette(refined, self.delta)) });
        lines.add("ari_selected {s} ari_labels {s}", .{ ariText(partitionAri(refined, self.selected)), ariText(self.labelAri(refined)) });
        return lines;
    }
    fn jaccard(self: *const Study, sample_partition: []const usize, restricted: []const usize) []f64 {
        const table = v.contingency(zeroBased(restricted), zeroBased(sample_partition), self.kappa, groupsOf(sample_partition));
        var column_sizes: [120]i64 = @splat(0);
        for (table) |row| {
            for (row, 0..) |cell, column| column_sizes[column] += cell;
        }
        const values = d.alloc(f64, self.kappa);
        for (table, values) |row, *value| {
            var size: i64 = 0;
            for (row) |cell| size += cell;
            var best: v.Fraction = .{ .numerator = 0, .denominator = 1 };
            if (size > 0) {
                for (row, 0..) |common, column| {
                    const candidate: v.Fraction = .{ .numerator = common, .denominator = size + column_sizes[column] - common };
                    if (candidate.greater(best)) best = candidate;
                }
            }
            value.* = best.value();
        }
        return values;
    }
    fn stabilityPart(self: *const Study) d.Lines {
        const settings = self.settings;
        var generator: Minstd = .{ .state = settings.seed };
        const size = self.count * settings.percent / 100;
        var ari_total: f64 = 0;
        const jaccard_totals = d.alloc(f64, self.kappa);
        @memset(jaccard_totals, 0);
        var lines: d.Lines = .{};
        lines.add("stability replicates {d} percent {d} seed {d}", .{ settings.replicates, settings.percent, settings.seed });
        for (1..settings.replicates + 1) |round| {
            const array = d.sequence(self.count);
            for (0..size) |position| {
                const next = position + generator.draw() % (self.count - position);
                std.mem.swap(usize, &array[position], &array[next]);
            }
            const sample = array[0..size];
            std.mem.sort(usize, sample, {}, numberOrder);
            const delta = d.matrix(size, size);
            for (sample, 0..) |u, row| {
                for (sample, 0..) |w, column| delta[row][column] = self.delta[u][w];
            }
            const partition = Tree.create(a.agglomerate(delta, self.chosen.method), size).cutInto(self.kappa);
            const restricted = d.alloc(usize, size);
            for (sample, restricted) |u, *number| number.* = self.selected[u];
            const ari = partitionAri(partition, restricted);
            const coefficients = self.jaccard(partition, restricted);
            ari_total += ari.value();
            for (coefficients, jaccard_totals) |coefficient, *total| total.* += coefficient;
            lines.add("replicate {d} size {d} ari {s} jaccard {s}", .{ round, size, ariText(ari), reals(coefficients) });
        }
        for (jaccard_totals) |*total| total.* /= d.f(settings.replicates);
        lines.add("mean_ari {s}", .{real(ari_total / d.f(settings.replicates))});
        lines.add("mean_jaccard {s}", .{reals(jaccard_totals)});
        return lines;
    }
    fn distanceMapPart(self: *const Study) d.Lines {
        const frame = d.fmt("+{s}+", .{d.repeat('-', self.count)});
        var lines: d.Lines = .{};
        lines.add("distance_map {s}", .{self.chosen.method});
        lines.write(frame);
        for (self.chosen.tree.order) |u| {
            var text: d.Text = .{};
            text.write("|");
            for (self.chosen.tree.order) |w| text.add("{c}", .{"@%#*+=-:. "[histogramBin(self.delta[u][w], self.distance_max)]});
            text.write("|");
            lines.write(text.value());
        }
        lines.write(frame);
        return lines;
    }
    fn profilesReport(self: *const Study) d.Lines {
        var report: d.Lines = .{};
        report.paragraph(self.selectionPart());
        report.paragraph(self.centroidPart());
        report.paragraph(self.profilePart());
        report.paragraph(self.contingencyPart());
        report.paragraph(self.misplacedPart());
        report.paragraph(self.weakestPart());
        report.paragraph(self.featurePart());
        report.paragraph(self.topMergesPart());
        report.paragraph(self.dropFeaturePart());
        report.paragraph(self.refinementPart());
        report.paragraph(self.stabilityPart());
        report.paragraph(self.distanceMapPart());
        return report;
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    d.scratch = init.gpa;
    const observations = try d.Observations.read(init.io);
    const settings = try d.Settings.read(init.io);
    const study = Study.create(observations, settings);
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try d.writeLines(init.io, "linkage.csv", study.linkageTable());
    try d.writeLines(init.io, "clusters.csv", study.clustersTable());
    try d.writeLines(init.io, "dendrogram.txt", study.dendrogramReport());
    try d.writeLines(init.io, "trees.txt", study.treesReport());
    try d.writeLines(init.io, "validation.txt", study.validationReport());
    try d.writeLines(init.io, "profiles.txt", study.profilesReport());
}
