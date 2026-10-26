const std = @import("std");
const D = @import("dataset.zig");
const R = @import("resampling.zig");
const T = @import("tests.zig");
const P = @import("report.zig");
const Minstd = @import("minstd.zig").Minstd;
const group_names = [_][]const u8{ "mean", "median", "trimmed_mean", "sd" };
const pair_names = [_][]const u8{ "mean_diff", "median_ratio", "hodges_lehmann", "cohen_d" };
const test_names = [_][]const u8{ "mean", "median", "ranksum", "absdev" };
const Summary = struct {
    estimate: f64, average: f64, se: f64, bias: f64, low: f64, high: f64, basic_low: f64, basic_high: f64,
    values: []const f64, ordered: []f64,
    fn init(estimate: f64, values: []const f64, low_rank: usize, high_rank: usize) Summary {
        const ordered = D.copy(f64, values);
        std.mem.sort(f64, ordered, {}, std.sort.asc(f64));
        const spread = R.meanAndSe(values);
        const low = ordered[low_rank - 1];
        const high = ordered[high_rank - 1];
        return .{ .estimate = estimate, .average = spread.average, .se = spread.se, .bias = spread.average - estimate, .low = low, .high = high, .basic_low = 2 * estimate - high, .basic_high = 2 * estimate - low, .values = values, .ordered = ordered };
    }
    fn csv(self: Summary, name: []const u8, statistic: []const u8) []const u8 {
        return D.fmt("{s},{s},{s},{s},{s},{s},{s},{s},{s}", .{ name, statistic, P.realText(self.estimate), P.realText(self.se), P.realText(self.bias), P.realText(self.low), P.realText(self.high), P.realText(self.basic_low), P.realText(self.basic_high) });
    }
    fn interval(self: Summary) []const u8 {
        return D.fmt("se {s} bias {s} percentile {s} {s} basic {s} {s}", .{ P.realText(self.se), P.realText(self.bias), P.realText(self.low), P.realText(self.high), P.realText(self.basic_low), P.realText(self.basic_high) });
    }
};
const GroupResult = struct { indices: []usize, samples: []i64, ordinary: [4]Summary, balanced: [4]Summary };
const PairResult = struct { first: usize, second: usize, name: []const u8, summaries: [4]Summary, extremes: [4]i64 = [_]i64{0} ** 4 };
const Jackknife = struct {
    average: f64, variance: f64, bias: f64, se: f64,
    fn init(estimate: f64, values: []const f64) Jackknife {
        const average = R.sequentialSum(values) / D.real(values.len);
        var squares: f64 = 0;
        for (values) |value| { const difference = value - average; squares += difference * difference; }
        const variance = D.real(values.len - 1) * squares / D.real(values.len);
        return .{ .average = average, .variance = variance, .bias = D.real(values.len - 1) * (average - estimate), .se = @sqrt(variance) };
    }
};
const Tally = struct {
    observed: i64, extreme: i64 = 0, greater: i64 = 0,
    fn count(self: *Tally, value: i64) void {
        if (D.abs(value) >= D.abs(self.observed)) self.extreme += 1;
        if (value >= self.observed) self.greater += 1;
    }
    fn text(self: Tally, offset: i64, denominator: i64) []const u8 {
        return D.fmt("extreme {d} greater {d} p_two {s} p_greater {s}", .{ self.extreme, self.greater, P.pValue(self.extreme + offset, denominator), P.pValue(self.greater + offset, denominator) });
    }
};
const Study = struct {
    data: *const D.Dataset, generator: Minstd, low_rank: usize, high_rank: usize, z_low: f64,
    groups: []GroupResult, pairs: []PairResult, paired_mean: Summary = undefined, paired_correlation: Summary = undefined,
    fn init(data: *const D.Dataset) Study {
        const low_rank: usize = @intCast(@divTrunc(D.n(data.settings.bootstrap + 1) * (100 - data.settings.confidence), 200));
        return .{ .data = data, .generator = .{ .state = data.settings.seed }, .low_rank = low_rank, .high_rank = data.settings.bootstrap + 1 - low_rank, .z_low = R.phiInverse(D.real(100 - data.settings.confidence) / 200), .groups = D.alloc(GroupResult, data.groups.len), .pairs = D.alloc(PairResult, data.pairs.len) };
    }
    fn summarize(self: *const Study, estimate: f64, values: []const f64) Summary { return Summary.init(estimate, values, self.low_rank, self.high_rank); }
    fn replicate(self: *const Study, group: usize, number: usize) []const i64 {
        const size = self.data.groups[group].values.len;
        return self.groups[group].samples[number * size .. (number + 1) * size];
    }
    fn bootstraps(self: *Study) void {
        const count = self.data.settings.bootstrap;
        for (self.data.groups, self.groups) |group, *result| {
            const original = group.values;
            result.indices = R.ordinaryIndices(&self.generator, original.len, count);
            result.samples = D.alloc(i64, original.len * count);
            var columns: [4][]f64 = undefined;
            for (&columns) |*column| column.* = D.alloc(f64, count);
            for (0..count) |r| {
                const sample = R.chosen(original, result.indices[r * original.len .. (r + 1) * original.len], result.samples[r * original.len .. (r + 1) * original.len]);
                const statistics = R.groupStatistics(sample);
                for (0..4) |s| columns[s][r] = statistics[s];
            }
            const estimates = R.groupStatistics(original);
            for (0..4) |s| result.ordinary[s] = self.summarize(estimates[s], columns[s]);
        }
        for (self.data.groups, self.groups) |group, *result| {
            const indices = R.balancedIndices(&self.generator, group.values.len, count);
            var columns: [4][]f64 = undefined;
            for (&columns) |*column| column.* = D.alloc(f64, count);
            for (0..count) |r| {
                var storage: [80]i64 = undefined;
                const statistics = R.groupStatistics(R.chosen(group.values, indices[r * group.values.len .. (r + 1) * group.values.len], &storage));
                for (0..4) |s| columns[s][r] = statistics[s];
            }
            for (0..4) |s| result.balanced[s] = self.summarize(result.ordinary[s].estimate, columns[s]);
        }
        const means = D.alloc(f64, count);
        const correlations = D.alloc(f64, count);
        for (0..count) |r| {
            var indices: [60]usize = undefined;
            var x: [60]i64 = undefined;
            var y: [60]i64 = undefined;
            var d: [60]i64 = undefined;
            const selected = indices[0..self.data.before.len];
            R.resampleIndices(&self.generator, selected.len, selected);
            means[r] = R.mean(R.chosen(self.data.differences, selected, &d));
            correlations[r] = R.correlation(R.chosen(self.data.before, selected, &x), R.chosen(self.data.after, selected, &y));
        }
        self.paired_mean = self.summarize(R.mean(self.data.differences), means);
        self.paired_correlation = self.summarize(R.correlation(self.data.before, self.data.after), correlations);
        for (self.data.pairs, self.pairs) |pair, *result| {
            result.* = .{ .first = pair.first, .second = pair.second, .name = D.fmt("{s}-{s}", .{ self.data.groups[pair.first].name, self.data.groups[pair.second].name }), .summaries = undefined };
            var columns: [4][]f64 = undefined;
            for (&columns) |*column| column.* = D.alloc(f64, count);
            for (0..count) |r| {
                const statistics = R.pairStatistics(self.replicate(pair.first, r), self.replicate(pair.second, r));
                for (0..4) |s| columns[s][r] = statistics[s];
            }
            const estimates = R.pairStatistics(self.data.groups[pair.first].values, self.data.groups[pair.second].values);
            for (0..4) |s| result.summaries[s] = self.summarize(estimates[s], columns[s]);
        }
    }
    fn descriptiveLines(self: *const Study) D.Lines {
        var combined: [320]i64 = undefined;
        var count: usize = 0;
        for (self.data.groups) |group| { @memcpy(combined[count .. count + group.values.len], group.values); count += group.values.len; }
        var low = minimum(combined[0..count]);
        var high = maximum(combined[0..count]);
        var lines: D.Lines = .{};
        lines.add("groups {d} observations {d}", .{ self.data.groups.len, count });
        for (self.data.groups) |group| lines.extend(describe("group", group.name, group.values, low, high, true));
        @memcpy(combined[0..self.data.before.len], self.data.before);
        @memcpy(combined[self.data.before.len .. 2 * self.data.before.len], self.data.after);
        low = minimum(combined[0 .. 2 * self.data.before.len]);
        high = maximum(combined[0 .. 2 * self.data.before.len]);
        lines.add("paired subjects {d}", .{self.data.before.len});
        lines.extend(describe("series", "before", self.data.before, low, high, false));
        lines.extend(describe("series", "after", self.data.after, low, high, false));
        lines.extend(describe("series", "diff", self.data.differences, minimum(self.data.differences), maximum(self.data.differences), false));
        return lines;
    }
    fn bootstrapLines(self: *const Study) D.Lines {
        var lines: D.Lines = .{};
        lines.write("group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi");
        for (self.data.groups, self.groups) |group, result| {
            for (0..4) |s| lines.write(result.ordinary[s].csv(group.name, group_names[s]));
            for (0..4) |s| lines.write(result.balanced[s].csv(group.name, D.fmt("balanced_{s}", .{group_names[s]})));
        }
        for (self.pairs) |pair| { for (0..4) |s| lines.write(pair.summaries[s].csv(pair.name, pair_names[s])); }
        return lines;
    }
    fn groupJackknife(self: *const Study, group: usize) D.Lines {
        const sample = self.data.groups[group].values;
        const bootstrap = self.groups[group];
        const count = self.data.settings.bootstrap;
        var deleted: [4][80]f64 = undefined;
        for (0..sample.len) |i| {
            var storage: [80]i64 = undefined;
            const statistics = R.groupStatistics(R.without(sample, i, &storage));
            for (0..4) |s| deleted[s][i] = statistics[s];
        }
        var jackknives: [4]Jackknife = undefined;
        var lines: D.Lines = .{};
        lines.add("group {s} n {d}", .{ self.data.groups[group].name, sample.len });
        for (0..4) |s| {
            jackknives[s] = Jackknife.init(bootstrap.ordinary[s].estimate, deleted[s][0..sample.len]);
            const jack = jackknives[s];
            lines.add("jackknife {s} estimate {s} average {s} bias {s} se {s}", .{ group_names[s], P.realText(bootstrap.ordinary[s].estimate), P.realText(jack.average), P.realText(jack.bias), P.realText(jack.se) });
        }
        for (0..4) |s| {
            const summary = bootstrap.ordinary[s];
            var below_count: usize = 0;
            for (summary.values) |value| { if (value < summary.estimate) below_count += 1; }
            const z0 = R.phiInverse(D.real(below_count) / D.real(count));
            var squares: f64 = 0;
            var cubes: f64 = 0;
            for (deleted[s][0..sample.len]) |value| {
                const difference = jackknives[s].average - value;
                squares += difference * difference;
                cubes += difference * difference * difference;
            }
            const acceleration = cubes / (6 * squares * @sqrt(squares));
            const first = clampRank(@intFromFloat(@floor(D.real(count + 1) * bcaAlpha(z0, acceleration, self.z_low))), count);
            const second = clampRank(D.n(count + 1) - @as(i64, @intFromFloat(@floor(D.real(count + 1) * (1 - bcaAlpha(z0, acceleration, -self.z_low))))), count);
            lines.add("bca {s} below {d} z0 {s} acceleration {s} ranks {d} {d} interval {s} {s}", .{ group_names[s], below_count, P.realText(z0), P.realText(acceleration), first, second, P.realText(summary.ordered[first - 1]), P.realText(summary.ordered[second - 1]) });
        }
        const omitted = D.alloc(usize, sample.len * count);
        var omitted_counts = [_]usize{0} ** 80;
        for (0..count) |r| {
            var seen = [_]bool{false} ** 80;
            for (bootstrap.indices[r * sample.len .. (r + 1) * sample.len]) |index| seen[index] = true;
            for (0..sample.len) |i| {
                if (!seen[i]) { omitted[i * count + omitted_counts[i]] = r; omitted_counts[i] += 1; }
            }
        }
        var errors: [4][80]f64 = undefined;
        for (0..4) |s| {
            for (0..sample.len) |i| {
                var values: [2000]f64 = undefined;
                for (omitted[i * count .. i * count + omitted_counts[i]], 0..) |r, j| values[j] = bootstrap.ordinary[s].values[r];
                errors[s][i] = R.meanAndSe(values[0..omitted_counts[i]]).se;
            }
            const spread = Jackknife.init(0, errors[s][0..sample.len]);
            lines.add("after_bootstrap {s} se {s} average {s} se_of_se {s}", .{ group_names[s], P.realText(bootstrap.ordinary[s].se), P.realText(spread.average), P.realText(spread.se) });
        }
        var smallest = count;
        var largest: usize = 0;
        var order: [80]usize = undefined;
        const total = R.sum(sample);
        for (0..sample.len) |i| {
            smallest = @min(smallest, omitted_counts[i]);
            largest = @max(largest, omitted_counts[i]);
            const magnitude = D.abs(D.n(sample.len) * sample[i] - total);
            var j = i;
            while (j > 0 and D.abs(D.n(sample.len) * sample[order[j - 1]] - total) < magnitude) : (j -= 1) order[j] = order[j - 1];
            order[j] = i;
        }
        lines.add("without min {d} max {d}", .{ smallest, largest });
        for (order[0..5], 1..) |index, rank| {
            const size = omitted_counts[index];
            var shifted_storage: [2000]f64 = undefined;
            const shifted = shifted_storage[0..size];
            for (omitted[index * count .. index * count + size], shifted) |r, *value| value.* = bootstrap.ordinary[0].values[r] - bootstrap.ordinary[0].estimate;
            std.mem.sort(f64, shifted, {}, std.sort.asc(f64));
            const influence = D.real(sample.len - 1) * (jackknives[0].average - deleted[0][index]);
            lines.add("influence {d} obs {d} value {s} l {s} without {d} se {s} q05 {s} q50 {s} q95 {s}", .{ rank, index + 1, P.realText(D.real(sample[index]) / 100), P.realText(influence), size, P.realText(errors[0][index]), P.realText(shifted[(5 * size + 99) / 100 - 1]), P.realText(shifted[(50 * size + 99) / 100 - 1]), P.realText(shifted[(95 * size + 99) / 100 - 1]) });
        }
        return lines;
    }
    fn pairJackknife(self: *const Study, pair: PairResult) D.Lines {
        const x = self.data.groups[pair.first].values;
        const y = self.data.groups[pair.second].values;
        var deleted: [2][4][80]f64 = undefined;
        for (0..x.len) |i| {
            var storage: [80]i64 = undefined;
            const statistics = R.pairStatistics(R.without(x, i, &storage), y);
            for (0..4) |s| deleted[0][s][i] = statistics[s];
        }
        for (0..y.len) |i| {
            var storage: [80]i64 = undefined;
            const statistics = R.pairStatistics(x, R.without(y, i, &storage));
            for (0..4) |s| deleted[1][s][i] = statistics[s];
        }
        var lines: D.Lines = .{};
        for (0..4) |s| {
            var bias: f64 = 0;
            var variance: f64 = 0;
            for (0..2) |part| {
                const jack = Jackknife.init(pair.summaries[s].estimate, deleted[part][s][0 .. if (part == 0) x.len else y.len]);
                bias += jack.bias;
                variance += jack.variance;
            }
            lines.add("pair {s} {s} estimate {s} bias {s} se {s}", .{ pair.name, pair_names[s], P.realText(pair.summaries[s].estimate), P.realText(bias), P.realText(@sqrt(variance)) });
        }
        return lines;
    }
    fn jackknifeLines(self: *const Study) D.Lines {
        var lines: D.Lines = .{};
        for (0..self.groups.len) |g| lines.extend(self.groupJackknife(g));
        for (self.pairs) |pair| lines.extend(self.pairJackknife(pair));
        return lines;
    }
    fn histogram(self: *const Study, name: []const u8, statistic: []const u8, summary: Summary) D.Lines {
        const bins = self.data.settings.bins;
        const low = summary.ordered[0];
        const high = summary.ordered[summary.ordered.len - 1];
        var counts = [_]usize{0} ** 40;
        for (summary.values) |value| counts[P.binNumber(value, low, high, bins) - 1] += 1;
        var top: usize = 0;
        for (counts[0..bins]) |count| top = @max(top, count);
        const estimate = if (summary.estimate >= low and summary.estimate <= high) P.binNumber(summary.estimate, low, high, bins) else 0;
        const first = P.binNumber(summary.low, low, high, bins);
        const last = P.binNumber(summary.high, low, high, bins);
        var lines: D.Lines = .{};
        lines.add("histogram {s} {s} min {s} max {s} width {s} top {d} estimate_bin {s}", .{ name, statistic, P.realText(low), P.realText(high), P.realText((high - low) / D.real(bins)), top, if (estimate == 0) "none" else D.fmt("{d}", .{estimate}) });
        var convergence: D.Text = .{};
        convergence.write("convergence");
        for (1..5) |quarter| {
            const size = quarter * summary.values.len / 4;
            convergence.add(" {d}:{s}", .{ size, P.realText(R.meanAndSe(summary.values[0..size]).se) });
        }
        lines.write(convergence.value());
        for (0..bins) |i| {
            var line: D.Text = .{};
            line.add("bin {d} {s} {d}", .{ i + 1, P.realText(low + (high - low) * D.real(i) / D.real(bins)), counts[i] });
            if (counts[i] > 0) line.add(" {s}", .{P.bar(counts[i], top)});
            if (i + 1 == first) line.write(" L");
            if (i + 1 == estimate) line.write(" E");
            if (i + 1 == last) line.write(" H");
            lines.write(line.value());
        }
        return lines;
    }
    fn histogramLines(self: *const Study) D.Lines {
        var lines: D.Lines = .{};
        for (self.data.groups, self.groups) |group, result| { for (0..4) |s| lines.extend(self.histogram(group.name, group_names[s], result.ordinary[s])); }
        for (self.pairs) |pair| { for (0..4) |s| lines.extend(self.histogram(pair.name, pair_names[s], pair.summaries[s])); }
        return lines;
    }
    fn permutationLines(self: *Study, pair: *PairResult) D.Lines {
        const x = self.data.groups[pair.first].values;
        const y = self.data.groups[pair.second].values;
        const count = x.len + y.len;
        var combined_storage: [160]i64 = undefined;
        var rank_storage: [160]i64 = undefined;
        var order_storage: [160]usize = undefined;
        const combined = combined_storage[0..count];
        const order = order_storage[0..count];
        @memcpy(combined[0..x.len], x);
        @memcpy(combined[x.len..], y);
        const ranks = T.doubledRanks(combined, &rank_storage);
        for (order, 0..) |*index, i| index.* = i;
        const observed = splitStatistics(combined, ranks, order, x.len);
        var tallies: [4]Tally = undefined;
        for (0..4) |s| tallies[s] = .{ .observed = observed[s] };
        for (0..self.data.settings.permutations) |_| {
            for (order, 0..) |*index, i| index.* = i;
            self.generator.shuffle(order);
            const statistics = splitStatistics(combined, ranks, order, x.len);
            for (0..4) |s| tallies[s].count(statistics[s]);
        }
        const rank_total = R.sum(ranks[0..x.len]);
        const denominator = D.n(self.data.settings.permutations + 1);
        var lines: D.Lines = .{};
        lines.add("permutation n {d} {d} perms {d}", .{ x.len, y.len, self.data.settings.permutations });
        lines.add("mean diff {s} {s}", .{ P.realText(R.meanDifference(x, y)), tallies[0].text(1, denominator) });
        lines.add("median diff {s} {s}", .{ P.realText(D.real(observed[1]) / 200), tallies[1].text(1, denominator) });
        lines.add("ranksum w {s} u {s} {s}", .{ P.realText(D.real(rank_total) / 2), P.realText(D.real(rank_total - D.n(x.len) * D.n(x.len + 1)) / 2), tallies[2].text(1, denominator) });
        lines.add("absdev diff {s} {s}", .{ P.realText(D.real(observed[3]) / D.real(200 * D.n(x.len) * D.n(y.len))), tallies[3].text(1, denominator) });
        for (0..4) |s| pair.extremes[s] = tallies[s].extreme;
        return lines;
    }
    fn powerLine(self: *Study, pair: PairResult) []const u8 {
        const x = self.data.groups[pair.first].values;
        const y = self.data.groups[pair.second].values;
        const settings = self.data.settings;
        const count = x.len + y.len;
        var rejections: i64 = 0;
        for (0..settings.simulations) |_| {
            var indices_storage: [80]usize = undefined;
            var combined_storage: [160]i64 = undefined;
            var shuffled_storage: [160]i64 = undefined;
            var order_storage: [160]usize = undefined;
            const combined = combined_storage[0..count];
            const order = order_storage[0..count];
            R.resampleIndices(&self.generator, x.len, indices_storage[0..x.len]);
            _ = R.chosen(x, indices_storage[0..x.len], combined[0..x.len]);
            R.resampleIndices(&self.generator, y.len, indices_storage[0..y.len]);
            _ = R.chosen(y, indices_storage[0..y.len], combined[x.len..]);
            const observed = D.abs(T.contrast(combined[0..x.len], combined[x.len..]));
            var extreme: i64 = 0;
            for (0..settings.inner_permutations) |_| {
                for (order, 0..) |*index, i| index.* = i;
                self.generator.shuffle(order);
                const shuffled = R.chosen(combined, order, &shuffled_storage);
                if (D.abs(T.contrast(shuffled[0..x.len], shuffled[x.len..])) >= observed) extreme += 1;
            }
            if (100 * (extreme + 1) <= (100 - settings.confidence) * D.n(settings.inner_permutations + 1)) rejections += 1;
        }
        const power = D.real(rejections) / D.real(settings.simulations);
        return D.fmt("power sims {d} perms {d} rejections {d} power {s} se {s}", .{ settings.simulations, settings.inner_permutations, rejections, P.realText(power), P.realText(@sqrt(power * (1 - power) / D.real(settings.simulations))) });
    }
    fn exactLines(self: *const Study, pair: PairResult) D.Lines {
        const q = self.data.settings.pilot;
        const x = self.data.groups[pair.first].values[0..q];
        const y = self.data.groups[pair.second].values[0..q];
        var combined_storage: [16]i64 = undefined;
        var rank_storage: [16]i64 = undefined;
        var absolute: [12870]i64 = undefined;
        var choice_storage: [8]usize = undefined;
        const combined = combined_storage[0 .. 2 * q];
        const choice = choice_storage[0..q];
        @memcpy(combined[0..q], x);
        @memcpy(combined[q..], y);
        const ranks = T.doubledRanks(combined, &rank_storage);
        const total = R.sum(combined);
        const rank_total = R.sum(ranks[0..q]);
        var means: Tally = .{ .observed = T.contrast(x, y) };
        var rank_sums: Tally = .{ .observed = rank_total - D.n(q) * D.n(2 * q + 1) };
        for (choice, 0..) |*index, i| index.* = i;
        var splits: usize = 0;
        while (true) {
            var chosen_total: i64 = 0;
            var chosen_ranks: i64 = 0;
            for (choice) |index| { chosen_total += combined[index]; chosen_ranks += ranks[index]; }
            const value = D.n(q) * chosen_total - D.n(q) * (total - chosen_total);
            means.count(value);
            rank_sums.count(chosen_ranks - D.n(q) * D.n(2 * q + 1));
            absolute[splits] = D.abs(value);
            splits += 1;
            if (!T.nextChoice(choice, 2 * q)) break;
        }
        std.mem.sort(i64, absolute[0..splits], {}, std.sort.asc(i64));
        var cumulative: usize = 0;
        var attained: usize = 0;
        var position = splits;
        var critical: i64 = 0;
        while (position > 0) {
            const value = absolute[position - 1];
            while (position > 0 and absolute[position - 1] == value) { position -= 1; cumulative += 1; }
            if (100 * D.n(cumulative) > (100 - self.data.settings.confidence) * D.n(splits)) break;
            attained = cumulative;
            critical = value;
        }
        var lines: D.Lines = .{};
        lines.add("exact size {d} splits {d}", .{ q, splits });
        lines.add("mean diff {s} {s}", .{ P.realText(R.meanDifference(x, y)), means.text(0, D.n(splits)) });
        lines.add("ranksum w {s} u {s} {s}", .{ P.realText(D.real(rank_total) / 2), P.realText(D.real(rank_total - D.n(q) * D.n(q + 1)) / 2), rank_sums.text(0, D.n(splits)) });
        if (attained > 0) lines.add("critical diff {s} attained {s}", .{ P.realText(D.real(critical) / D.real(100 * D.n(q) * D.n(q))), P.pValue(D.n(attained), D.n(splits)) })
        else lines.write("critical diff none attained none");
        return lines;
    }
    fn studentizedLines(self: *const Study, pair: PairResult) D.Lines {
        const x = self.data.groups[pair.first].values;
        const y = self.data.groups[pair.second].values;
        const sx = R.sd(x);
        const sy = R.sd(y);
        const vx = sx * sx / D.real(x.len);
        const vy = sy * sy / D.real(y.len);
        const se0 = @sqrt(vx + vy);
        const estimate = pair.summaries[0].estimate;
        const statistic = estimate / se0;
        var value_storage: [2000]f64 = undefined;
        const values = value_storage[0..self.data.settings.bootstrap];
        var extreme: i64 = 0;
        for (values, 0..) |*value, r| {
            const first = self.groups[pair.first].ordinary[3].values[r];
            const second = self.groups[pair.second].ordinary[3].values[r];
            value.* = (pair.summaries[0].values[r] - estimate) / @sqrt(first * first / D.real(x.len) + second * second / D.real(y.len));
            if (@abs(value.*) >= @abs(statistic)) extreme += 1;
        }
        std.mem.sort(f64, values, {}, std.sort.asc(f64));
        const low = estimate - values[self.high_rank - 1] * se0;
        const high = estimate - values[self.low_rank - 1] * se0;
        const degrees = (vx + vy) * (vx + vy) / (vx * vx / D.real(x.len - 1) + vy * vy / D.real(y.len - 1));
        var greater: i64 = 0;
        var equal: i64 = 0;
        for (x) |first| { for (y) |second| { if (first > second) greater += 1; if (first == second) equal += 1; } }
        const d = R.cohenD(x, y);
        const hedges = d * (1 - 3 / D.real(4 * (x.len + y.len - 2) - 1));
        const cles = D.real(2 * greater + equal) / D.real(2 * D.n(x.len) * D.n(y.len));
        var lines: D.Lines = .{};
        lines.add("bootstrap_t t {s} df {s} extreme {d} p {s} interval {s} {s}", .{ P.realText(statistic), P.realText(degrees), extreme, P.pValue(extreme + 1, D.n(self.data.settings.bootstrap + 1)), P.realText(low), P.realText(high) });
        lines.add("effect pooled_sd {s} cohen_d {s} hedges_g {s} cles {s}", .{ P.realText(R.pooledSd(x, y)), P.realText(d), P.realText(hedges), P.realText(cles) });
        return lines;
    }
    fn holmLines(self: *const Study) D.Lines {
        const denominator = D.n(self.data.settings.permutations + 1);
        var lines: D.Lines = .{};
        for (0..4) |s| {
            var storage: [6]usize = undefined;
            const order = storage[0..self.pairs.len];
            for (0..order.len) |i| {
                var j = i;
                while (j > 0 and self.pairs[order[j - 1]].extremes[s] > self.pairs[i].extremes[s]) : (j -= 1) order[j] = order[j - 1];
                order[j] = i;
            }
            var adjusted: i64 = 0;
            for (order, 0..) |index, rank| {
                const pair = self.pairs[index];
                const numerator = pair.extremes[s] + 1;
                adjusted = @max(adjusted, @min(denominator, D.n(self.pairs.len - rank) * numerator));
                const reject = 100 * adjusted <= (100 - self.data.settings.confidence) * denominator;
                lines.add("holm {s} rank {d} {s} {s} p {s} adjusted {s} {s}", .{ test_names[s], rank + 1, self.data.groups[pair.first].name, self.data.groups[pair.second].name, P.pValue(numerator, denominator), P.pValue(adjusted, denominator), if (reject) "reject" else "retain" });
            }
        }
        return lines;
    }
    fn pairedLines(self: *const Study) D.Lines {
        const differences = self.data.differences;
        var positive: usize = 0;
        var negative: usize = 0;
        for (differences) |value| { if (value > 0) positive += 1; if (value < 0) negative += 1; }
        const average = R.mean(differences);
        const deviation = R.sd(differences);
        const r = self.paired_correlation.estimate;
        const z = 0.5 * @log((1 + r) / (1 - r));
        const half = -self.z_low / @sqrt(D.real(differences.len - 3));
        var lines: D.Lines = .{};
        lines.add("paired subjects {d} positive {d} negative {d} zero {d}", .{ differences.len, positive, negative, differences.len - positive - negative });
        lines.add("paired before {s} after {s} diff {s} sd_diff {s} t {s} dz {s}", .{ P.realText(R.mean(self.data.before)), P.realText(R.mean(self.data.after)), P.realText(average), P.realText(deviation), P.realText(average / (deviation / @sqrt(D.real(differences.len)))), P.realText(average / deviation) });
        lines.add("paired_bootstrap {s}", .{self.paired_mean.interval()});
        lines.add("correlation r {s} {s} fisher {s} {s}", .{ P.realText(r), self.paired_correlation.interval(), P.realText(hyperbolicTangent(z - half)), P.realText(hyperbolicTangent(z + half)) });
        return lines;
    }
    fn signFlipLines(self: *Study) D.Lines {
        const differences = self.data.differences;
        var absolute: [60]i64 = undefined;
        var rank_storage: [60]i64 = undefined;
        var signed_storage: [60]i64 = undefined;
        var count: usize = 0;
        for (differences) |value| { if (value != 0) { absolute[count] = D.abs(value); count += 1; } }
        const ranks = T.doubledRanks(absolute[0..count], &rank_storage);
        const signed_ranks = signed_storage[0..differences.len];
        var position: usize = 0;
        var plus: i64 = 0;
        for (differences, signed_ranks) |value, *rank| {
            rank.* = if (value == 0) 0 else if (value > 0) ranks[position] else -ranks[position];
            if (value != 0) position += 1;
            if (rank.* > 0) plus += rank.*;
        }
        var means: Tally = .{ .observed = R.sum(differences) };
        var rank_sums: Tally = .{ .observed = R.sum(signed_ranks) };
        for (0..self.data.settings.permutations) |_| {
            var total: i64 = 0;
            var rank_total: i64 = 0;
            for (differences, signed_ranks) |value, rank| {
                const sign: i64 = if (@mod(self.generator.draw(), 2) == 1) -1 else 1;
                total += sign * value;
                rank_total += sign * rank;
            }
            means.count(total);
            rank_sums.count(rank_total);
        }
        var lines: D.Lines = .{};
        lines.add("signflip flips {d}", .{self.data.settings.permutations});
        lines.add("mean diff {s} {s}", .{ P.realText(R.mean(differences)), means.text(1, D.n(self.data.settings.permutations + 1)) });
        lines.add("signedrank w_plus {s} {s}", .{ P.realText(D.real(plus) / 2), rank_sums.text(1, D.n(self.data.settings.permutations + 1)) });
        return lines;
    }
    fn anovaLines(self: *Study) D.Lines {
        const group_count = self.data.groups.len;
        var sample_storage: [4][]const i64 = undefined;
        var sizes_storage: [4]usize = undefined;
        var combined_storage: [320]i64 = undefined;
        var count: usize = 0;
        const samples = sample_storage[0..group_count];
        const sizes = sizes_storage[0..group_count];
        for (self.data.groups, 0..) |group, g| {
            samples[g] = group.values;
            sizes[g] = group.values.len;
            @memcpy(combined_storage[count .. count + sizes[g]], group.values);
            count += sizes[g];
        }
        const combined = combined_storage[0..count];
        const original = T.anova(samples);
        const eta = original.between / (original.between + original.within);
        const msw = original.within / D.real(count - group_count);
        const omega = (original.between - D.real(group_count - 1) * msw) / (original.between + original.within + msw);
        const eta_values = D.alloc(f64, self.data.settings.bootstrap);
        for (eta_values, 0..) |*value, r| {
            var replicates: [4][]const i64 = undefined;
            for (0..group_count) |g| replicates[g] = self.replicate(g, r);
            const trial = T.anova(replicates[0..group_count]);
            value.* = trial.between / (trial.between + trial.within);
        }
        const eta_summary = self.summarize(eta, eta_values);
        var weights: [4]f64 = undefined;
        var weight_total: f64 = 0;
        var weighted_total: f64 = 0;
        for (samples, 0..) |sample, g| {
            const deviation = R.sd(sample);
            weights[g] = D.real(sample.len) / (deviation * deviation);
            weight_total += weights[g];
            weighted_total += weights[g] * original.means[g];
        }
        const center = weighted_total / weight_total;
        var aw: f64 = 0;
        var lambda: f64 = 0;
        for (0..group_count) |g| {
            const difference = original.means[g] - center;
            const remaining = 1 - weights[g] / weight_total;
            aw += weights[g] * (difference * difference);
            lambda += remaining * remaining / D.real(sizes[g] - 1);
        }
        aw /= D.real(group_count - 1);
        const welch = aw / (1 + D.real(2 * (group_count - 2)) * lambda / D.real(group_count * group_count - 1));
        const degrees = D.real(group_count * group_count - 1) / (3 * lambda);
        var rank_storage: [320]i64 = undefined;
        const ranks = T.doubledRanks(combined, &rank_storage);
        const frequencies = T.valueCounts(combined);
        var ties: i64 = 0;
        var tie_groups: usize = 0;
        for (frequencies.counts[0..frequencies.len]) |t| { if (t >= 2) { ties += t * t * t - t; tie_groups += 1; } }
        const n = D.n(count);
        const correction = 1 - D.real(ties) / D.real(n * n * n - n);
        var rank_groups: [4][]const i64 = undefined;
        const h = T.kruskal(T.divide(ranks, sizes, &rank_groups), correction);
        var lines: D.Lines = .{};
        lines.add("anova groups {d} observations {d} ssb {s} ssw {s} df {d} {d} f {s} eta_squared {s} omega_squared {s}", .{ group_count, count, P.realText(original.between), P.realText(original.within), group_count - 1, count - group_count, P.realText(original.f), P.realText(eta), P.realText(omega) });
        lines.add("eta_bootstrap {s}", .{eta_summary.interval()});
        lines.add("welch f {s} df {d} {s}", .{ P.realText(welch), group_count - 1, P.realText(degrees) });
        lines.add("kruskal h {s} tie_groups {d}", .{ P.realText(h), tie_groups });
        var comparison_storage: [6]Comparison = undefined;
        var pair_count: usize = 0;
        for (0..group_count) |i| {
            for (i + 1..group_count) |j| {
                comparison_storage[pair_count] = .{ .first = i, .second = j, .numerator = D.abs(T.contrast(samples[i], samples[j])), .denominator = D.n(sizes[i]) * D.n(sizes[j]) };
                pair_count += 1;
            }
        }
        const comparisons = comparison_storage[0..pair_count];
        var f_extreme: i64 = 0;
        var h_extreme: i64 = 0;
        for (0..self.data.settings.permutations) |_| {
            var order_storage: [320]usize = undefined;
            var shuffled_storage: [320]i64 = undefined;
            var shuffled_rank_storage: [320]i64 = undefined;
            var trial_storage: [4][]const i64 = undefined;
            const order = order_storage[0..count];
            for (order, 0..) |*index, i| index.* = i;
            self.generator.shuffle(order);
            const trial_samples = T.divide(R.chosen(combined, order, &shuffled_storage), sizes, &trial_storage);
            const trial = T.anova(trial_samples);
            if (trial.f >= original.f - 0.000000001 * original.f) f_extreme += 1;
            if (T.kruskal(T.divide(R.chosen(ranks, order, &shuffled_rank_storage), sizes, &rank_groups), correction) >= h - 0.000000001 * h) h_extreme += 1;
            var numerators: [6]i64 = undefined;
            var largest: usize = 0;
            for (comparisons, 0..) |pair, p| {
                numerators[p] = D.abs(T.contrast(trial_samples[pair.first], trial_samples[pair.second]));
                if (numerators[p] * comparisons[largest].denominator > numerators[largest] * pair.denominator) largest = p;
            }
            for (comparisons, 0..) |*pair, p| {
                if (numerators[p] >= pair.numerator) pair.extreme += 1;
                if (numerators[largest] * pair.denominator >= pair.numerator * comparisons[largest].denominator) pair.maximum += 1;
            }
        }
        const denominator = D.n(self.data.settings.permutations + 1);
        lines.add("anova_permutation perms {d} f_extreme {d} f_p {s} h_extreme {d} h_p {s}", .{ self.data.settings.permutations, f_extreme, P.pValue(f_extreme + 1, denominator), h_extreme, P.pValue(h_extreme + 1, denominator) });
        for (comparisons) |pair| lines.add("pairwise {s} {s} diff {s} extreme {d} p {s} maxt {d} adjusted {s}", .{ self.data.groups[pair.first].name, self.data.groups[pair.second].name, P.realText(R.meanDifference(samples[pair.first], samples[pair.second])), pair.extreme, P.pValue(pair.extreme + 1, denominator), pair.maximum, P.pValue(pair.maximum + 1, denominator) });
        return lines;
    }
    fn run(self: *Study, io: std.Io) !void {
        self.bootstraps();
        var tests: D.Lines = .{};
        for (self.pairs) |*pair| {
            tests.add("compare {s} {s}", .{ self.data.groups[pair.first].name, self.data.groups[pair.second].name });
            tests.extend(self.permutationLines(pair));
            tests.write(self.powerLine(pair.*));
            tests.extend(self.exactLines(pair.*));
            tests.extend(self.studentizedLines(pair.*));
        }
        tests.extend(self.holmLines());
        tests.extend(self.pairedLines());
        tests.extend(self.signFlipLines());
        tests.extend(self.anovaLines());
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try P.writeLines(io, "descriptives.txt", self.descriptiveLines());
        try P.writeLines(io, "bootstrap.csv", self.bootstrapLines());
        try P.writeLines(io, "jackknife.txt", self.jackknifeLines());
        try P.writeLines(io, "tests.txt", tests);
        try P.writeLines(io, "histograms.txt", self.histogramLines());
    }
};
const Comparison = struct { first: usize, second: usize, numerator: i64, denominator: i64, extreme: i64 = 0, maximum: i64 = 0 };
fn clampRank(rank: i64, count: usize) usize { return @intCast(@min(@max(rank, 1), D.n(count))); }
fn bcaAlpha(z0: f64, acceleration: f64, z: f64) f64 { return R.phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z))); }
fn hyperbolicTangent(value: f64) f64 { const e = @exp(2 * value); return (e - 1) / (e + 1); }
fn splitStatistics(values: []const i64, ranks: []const i64, order: []const usize, size: usize) [4]i64 {
    var storage: [160]i64 = undefined;
    const shuffled = R.chosen(values, order, &storage);
    const first = shuffled[0..size];
    const second = shuffled[size..];
    var rank_total: i64 = 0;
    for (order[0..size]) |index| rank_total += ranks[index];
    const first_median = R.doubledMedian(first);
    const second_median = R.doubledMedian(second);
    var first_deviation: i64 = 0;
    var second_deviation: i64 = 0;
    for (first) |value| first_deviation += D.abs(2 * value - first_median);
    for (second) |value| second_deviation += D.abs(2 * value - second_median);
    return .{ T.contrast(first, second), first_median - second_median, rank_total - D.n(size) * D.n(values.len + 1), D.n(second.len) * first_deviation - D.n(first.len) * second_deviation };
}
fn minimum(values: []const i64) i64 { var result = values[0]; for (values[1..]) |value| result = @min(result, value); return result; }
fn maximum(values: []const i64) i64 { var result = values[0]; for (values[1..]) |value| result = @max(result, value); return result; }
fn boxPosition(value: i64, low: i64, high: i64) usize {
    const delta = 100 * (high - low);
    return @intCast(@divTrunc(120 * (value - 100 * low) + delta, 2 * delta));
}
fn describe(kind: []const u8, name: []const u8, sample: []const i64, low: i64, high: i64, stems: bool) D.Lines {
    var ordered_storage: [80]i64 = undefined;
    var wins_storage: [80]i64 = undefined;
    var inside: [80]i64 = undefined;
    var outliers: [80]usize = undefined;
    const ordered = ordered_storage[0..sample.len];
    @memcpy(ordered, sample);
    std.mem.sort(i64, ordered, {}, std.sort.asc(i64));
    const wins = R.winsorized(sample, &wins_storage);
    const center = R.mean(sample);
    const moment = R.moments(sample);
    const q1 = R.quantileNumerator(sample, 25);
    const q3 = R.quantileNumerator(sample, 75);
    var out_count: usize = 0;
    var in_count: usize = 0;
    for (sample, 0..) |value, i| {
        if (200 * value < 5 * q1 - 3 * q3 or 200 * value > 5 * q3 - 3 * q1) { outliers[out_count] = i + 1; out_count += 1; }
        else { inside[in_count] = value; in_count += 1; }
    }
    const w1 = minimum(inside[0..in_count]);
    const w2 = maximum(inside[0..in_count]);
    var band = [_]u8{'.'} ** 61;
    @memset(band[boxPosition(100 * w1, low, high) .. boxPosition(100 * w2, low, high) + 1], '-');
    @memset(band[boxPosition(q1, low, high) .. boxPosition(q3, low, high) + 1], '=');
    band[boxPosition(R.quantileNumerator(sample, 50), low, high)] = '|';
    for (outliers[0..out_count]) |number| band[boxPosition(100 * sample[number - 1], low, high)] = 'o';
    var lines: D.Lines = .{};
    lines.add("{s} {s}", .{ kind, name });
    lines.add("n {d}", .{sample.len});
    lines.add("mean {s}", .{P.realText(center)});
    lines.add("median {s}", .{P.realText(R.median(sample))});
    lines.add("trimmed_mean {s} trim {d}", .{ P.realText(R.trimmedMean(sample)), sample.len / 10 });
    lines.add("winsorized_mean {s} winsorized_sd {s}", .{ P.realText(R.mean(wins)), P.realText(R.sd(wins)) });
    lines.add("sd {s}", .{P.realText(moment.sd)});
    lines.add("se_mean {s}", .{P.realText(moment.sd / @sqrt(D.real(sample.len)))});
    lines.add("cv {s}", .{P.realText(moment.sd / center)});
    lines.add("skewness {s}", .{P.realText(moment.third / (moment.second * @sqrt(moment.second)))});
    lines.add("kurtosis {s}", .{P.realText(moment.fourth / (moment.second * moment.second) - 3)});
    lines.add("mad {s}", .{P.realText(R.mad(sample))});
    lines.add("min {s}", .{P.realText(D.real(ordered[0]) / 100)});
    lines.add("q1 {s}", .{P.realText(D.real(q1) / 10000)});
    lines.add("q3 {s}", .{P.realText(D.real(q3) / 10000)});
    lines.add("iqr {s}", .{P.realText(D.real(q3 - q1) / 10000)});
    lines.add("max {s}", .{P.realText(D.real(ordered[ordered.len - 1]) / 100)});
    lines.add("percentiles p05 {s} p10 {s} p90 {s} p95 {s}", .{ P.realText(D.real(R.quantileNumerator(sample, 5)) / 10000), P.realText(D.real(R.quantileNumerator(sample, 10)) / 10000), P.realText(D.real(R.quantileNumerator(sample, 90)) / 10000), P.realText(D.real(R.quantileNumerator(sample, 95)) / 10000) });
    lines.add("whiskers {s} {s}", .{ P.realText(D.real(w1) / 100), P.realText(D.real(w2) / 100) });
    lines.add("outliers {s}", .{P.numberList(outliers[0..out_count])});
    lines.add("box {s}", .{band});
    if (stems) {
        var stem = @divTrunc(ordered[0], 100);
        while (stem <= @divTrunc(ordered[ordered.len - 1], 100)) : (stem += 1) {
            var leaves: [80]u8 = undefined;
            var count: usize = 0;
            for (ordered) |value| {
                if (@divTrunc(value, 100) == stem) { leaves[count] = @intCast('0' + @divTrunc(@mod(value, 100), 10)); count += 1; }
            }
            lines.add("stem {d}{s}{s}", .{ stem, if (count == 0) "" else " ", leaves[0..count] });
        }
    }
    return lines;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    D.allocator = arena.allocator();
    const data = try D.load(init.io);
    var study = Study.init(&data);
    try study.run(init.io);
}
