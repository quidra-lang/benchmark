const std = @import("std");
const D = @import("transactions.zig");
const F = @import("features.zig");
const K = @import("kmeans.zig");
const V = @import("validation.zig");
const PR = @import("profiles.zig");
const P = @import("report.zig");
const criteria = [_][]const u8{ "elbow", "silhouette", "calinski_harabasz", "davies_bouldin", "hartigan" };
const Refined = struct { labels: [400]usize = undefined, centers: [10]K.Point = undefined, passes: usize = 0, transfers: usize = 0, sse: f64 = 0 };
const Run = struct { method: D.Method, number: usize, seeds: [10]usize, lloyd: K.Lloyd, refined: Refined };
const Solution = struct { k: usize = 0, labels: [400]usize = undefined, sizes: [10]usize = [_]usize{0} ** 10, members: [10][400]usize = undefined, centers: [10]K.Point = undefined, sse: f64 = 0 };
const Candidate = struct {
    k: usize = 0, runs: []Run = undefined, bests: [3]usize = undefined, best: usize = 0, votes: usize = 0,
    solution: Solution = .{}, silhouettes: [400]f64 = undefined,
    silhouette: f64 = 0, ch: f64 = 0, db: f64 = 0, elbow: f64 = 0, hartigan: f64 = 0,
    rule_numbers: [10]usize = undefined, names: [10][]const u8 = undefined,
};
const Analysis = struct {
    data: *const D.Transactions, rules: []const PR.Rule, reference_orders: []D.Order, customers: []F.Customer, scaling: F.Scaling,
    points: []K.Point, state: i64, total_spend: i64 = 0,
    candidates: [11]Candidate = [_]Candidate{.{}} ** 11,
    votes: [5]usize = undefined, k: usize = 0,
    numbers: [400]?usize = [_]?usize{null} ** 400,
    scores: [400][3]usize = undefined, codes: [400]usize = undefined, others: [400]usize = undefined,
    distances: [400]f64 = undefined, other_distances: [400]f64 = undefined,
    segment_sse: [10]f64 = [_]f64{0} ** 10,
    jaccard_total: [10]f64 = [_]f64{0} ** 10, jaccard_min: [10]f64 = [_]f64{1} ** 10,
    overall_categories: []i64 = undefined, category_present: []bool = undefined,
    segment_categories: [10][]i64 = undefined, segment_spends: [10]i64 = [_]i64{0} ** 10,
    rankings: [10][]usize = undefined, ranking_counts: [10]usize = [_]usize{0} ** 10,
    fn init(data: *const D.Transactions, rules: []const PR.Rule) Analysis {
        const orders = D.groupOrders(data, 1, data.settings.reference);
        const customers = F.eligibleCustomers(data, orders, data.settings.reference);
        const scaling = F.fitScaling(customers);
        F.standardize(customers, scaling);
        const points = D.alloc(K.Point, customers.len);
        var result: Analysis = .{ .data = data, .rules = rules, .reference_orders = orders, .customers = customers, .scaling = scaling, .points = points, .state = data.settings.seed };
        for (customers, 0..) |customer, i| { points[i] = customer.point; result.numbers[customer.file_number] = i; }
        return result;
    }
    fn pointSequence(self: *const Analysis) K.Points { return .{ .values = self.points }; }
    fn final(self: *const Analysis) *const Candidate { return &self.candidates[self.k]; }
    fn draw(self: *Analysis) i64 { self.state = @mod(48271 * self.state, 2147483647); return self.state; }
    fn initialSeeds(self: *Analysis, points: K.Points, k: usize, method: D.Method, number: usize) [10]usize {
        var seeds: [10]usize = undefined;
        var count: usize = 0;
        if (method == .forgy) {
            var chosen = [_]bool{false} ** 400;
            while (count < k) {
                const index: usize = @intCast(@mod(self.draw(), D.n(points.values.len)));
                if (!chosen[index]) { chosen[index] = true; seeds[count] = index; count += 1; }
            }
            return seeds;
        }
        if (method == .maximin) {
            const center = K.meanPoint(points);
            var spreads: [400]f64 = undefined;
            var order: [400]usize = undefined;
            for (points.values, 0..) |point, i| {
                spreads[i] = K.squaredDistance(point, center, points.dimensions);
                var j = i;
                while (j > 0 and spreads[order[j - 1]] > spreads[i]) : (j -= 1) order[j] = order[j - 1];
                order[j] = i;
            }
            seeds[0] = order[number - 1];
        } else seeds[0] = @intCast(@mod(self.draw(), D.n(points.values.len)));
        count = 1;
        while (count < k) {
            var gaps: [400]f64 = undefined;
            for (points.values, 0..) |point, i| {
                gaps[i] = K.squaredDistance(point, points.values[seeds[0]], points.dimensions);
                for (seeds[1..count]) |chosen| gaps[i] = @min(gaps[i], K.squaredDistance(point, points.values[chosen], points.dimensions));
            }
            var chosen: usize = 0;
            if (method == .maximin) {
                for (1..points.values.len) |i| { if (gaps[i] > gaps[chosen]) chosen = i; }
            } else {
                const weight = F.orderedSum(gaps[0..points.values.len]);
                const threshold = (D.real(self.draw()) / 2147483647) * weight;
                var cumulative: f64 = 0;
                var selected: ?usize = null;
                for (gaps[0..points.values.len], 0..) |gap, i| { cumulative += gap; if (cumulative > threshold) { selected = i; break; } }
                if (selected == null) { for (gaps[0..points.values.len], 0..) |gap, i| { if (gap > 0) selected = i; } }
                chosen = selected.?;
            }
            seeds[count] = chosen;
            count += 1;
        }
        return seeds;
    }
    fn clusteringRun(self: *Analysis, points: K.Points, k: usize, method: D.Method, number: usize) Run {
        const seeds = self.initialSeeds(points, k, method, number);
        var initial: [10]K.Point = undefined;
        for (seeds[0..k], 0..) |index, j| initial[j] = points.values[index];
        const result = K.lloyd(points, initial[0..k], self.data.settings.iterations);
        return .{ .method = method, .number = number, .seeds = seeds, .lloyd = result, .refined = improve(points, result.labels[0..points.values.len], k, self.data.settings.iterations) };
    }
    fn fitCandidates(self: *Analysis) void {
        const settings = self.data.settings;
        const points = self.pointSequence();
        for (settings.min_k..settings.max_k + 1) |k| {
            const candidate = &self.candidates[k];
            candidate.k = k;
            candidate.runs = D.alloc(Run, settings.methods.len * settings.restarts);
            var overall: ?usize = null;
            for (settings.methods, 0..) |method, m| {
                var best: ?usize = null;
                for (1..settings.restarts + 1) |t| {
                    const index = m * settings.restarts + t - 1;
                    candidate.runs[index] = self.clusteringRun(points, k, method, t);
                    if (best == null or P.rounded(candidate.runs[index].refined.sse) < P.rounded(candidate.runs[best.?].refined.sse)) best = index;
                }
                candidate.bests[m] = best.?;
                if (overall == null or P.rounded(candidate.runs[best.?].refined.sse) < P.rounded(candidate.runs[overall.?].refined.sse)) overall = best.?;
            }
            candidate.best = overall.?;
            candidate.solution = organize(points, candidate.runs[candidate.best].refined.labels[0..self.customers.len], k);
        }
        const table = V.distanceTable(points);
        const first = self.candidates[settings.min_k].solution.sse;
        const last = self.candidates[settings.max_k].solution.sse;
        for (settings.min_k..settings.max_k + 1) |k| {
            const candidate = &self.candidates[k];
            const solution = &candidate.solution;
            V.silhouettes(table, solution.labels[0..self.customers.len], solution.sizes[0..k], candidate.silhouettes[0..self.customers.len]);
            candidate.silhouette = F.orderedSum(candidate.silhouettes[0..self.customers.len]) / D.real(self.customers.len);
            candidate.ch = V.calinskiHarabasz(points, solution.centers[0..k], solution.sizes[0..k], solution.sse);
            candidate.db = V.daviesBouldin(points, solution.labels[0..self.customers.len], solution.centers[0..k], solution.sizes[0..k]);
            candidate.elbow = V.elbow(k, settings.min_k, settings.max_k, solution.sse, first, last);
            if (k < settings.max_k) candidate.hartigan = V.hartigan(solution.sse, self.candidates[k + 1].solution.sse, self.customers.len, k);
            for (0..k) |j| {
                const rule = PR.matchingRule(self.rules, solution.centers[j]);
                var repeats: usize = 0;
                for (candidate.rule_numbers[0..j]) |earlier| { if (earlier == rule + 1) repeats += 1; }
                candidate.rule_numbers[j] = rule + 1;
                candidate.names[j] = if (repeats == 0) self.rules[rule].name else D.fmt("{s}_{d}", .{ self.rules[rule].name, repeats + 1 });
            }
        }
        var votes = [_]usize{ settings.min_k + 1, settings.min_k, settings.min_k, settings.min_k, settings.max_k };
        for (settings.min_k..settings.max_k + 1) |k| {
            const candidate = self.candidates[k];
            if (k > settings.min_k and k < settings.max_k and P.rounded(candidate.elbow) > P.rounded(self.candidates[votes[0]].elbow)) votes[0] = k;
            if (P.rounded(candidate.silhouette) > P.rounded(self.candidates[votes[1]].silhouette)) votes[1] = k;
            if (P.rounded(candidate.ch) > P.rounded(self.candidates[votes[2]].ch)) votes[2] = k;
            if (P.rounded(candidate.db) < P.rounded(self.candidates[votes[3]].db)) votes[3] = k;
            if (k < settings.max_k and votes[4] == settings.max_k and candidate.hartigan <= 10) votes[4] = k;
        }
        self.votes = votes;
        for (votes) |k| self.candidates[k].votes += 1;
        self.k = settings.min_k;
        for (settings.min_k + 1..settings.max_k + 1) |k| {
            const candidate = self.candidates[k];
            const best = self.candidates[self.k];
            if (candidate.votes > best.votes or (candidate.votes == best.votes and P.rounded(candidate.silhouette) > P.rounded(best.silhouette))) self.k = k;
        }
    }
    fn prepareFinal(self: *Analysis) void {
        const cats = self.data.categories.len;
        const solution = &self.final().solution;
        self.overall_categories = D.alloc(i64, cats);
        self.category_present = D.alloc(bool, cats);
        @memset(self.overall_categories, 0);
        @memset(self.category_present, false);
        for (0..self.k) |j| {
            self.segment_categories[j] = D.alloc(i64, cats);
            @memset(self.segment_categories[j], 0);
            self.rankings[j] = D.alloc(usize, cats);
        }
        for (self.customers, 0..) |customer, i| {
            const own = solution.labels[i];
            self.distances[i] = @sqrt(K.squaredDistance(customer.point, solution.centers[own], 6));
            var other: ?usize = null;
            var best: f64 = 0;
            for (solution.centers[0..self.k], 0..) |center, j| {
                if (j == own) continue;
                const value = K.squaredDistance(customer.point, center, 6);
                if (other == null or value < best) { other = j; best = value; }
            }
            self.others[i] = other.?;
            self.other_distances[i] = @sqrt(best);
            var ranks = [_]usize{0} ** 3;
            for (self.customers) |candidate| {
                if (candidate.raw[0] > customer.raw[0]) ranks[0] += 1;
                if (candidate.orders.len < customer.orders.len) ranks[1] += 1;
                if (candidate.spend < customer.spend) ranks[2] += 1;
            }
            for (0..3) |s| self.scores[i][s] = 1 + 5 * ranks[s] / self.customers.len;
            self.codes[i] = 100 * self.scores[i][0] + 10 * self.scores[i][1] + self.scores[i][2];
            self.total_spend += customer.spend;
            self.segment_spends[own] += customer.spend;
            self.segment_sse[own] += K.squaredDistance(customer.point, solution.centers[own], 6);
            for (0..cats) |g| {
                self.overall_categories[g] += customer.category_spend[g];
                self.segment_categories[own][g] += customer.category_spend[g];
                if (customer.category_present[g]) self.category_present[g] = true;
            }
        }
        for (0..self.k) |j| {
            for (0..cats) |g| {
                if (self.segment_categories[j][g] <= 0) continue;
                var position = self.ranking_counts[j];
                self.ranking_counts[j] += 1;
                while (position > 0 and self.segment_categories[j][self.rankings[j][position - 1]] < self.segment_categories[j][g]) : (position -= 1) self.rankings[j][position] = self.rankings[j][position - 1];
                self.rankings[j][position] = g;
            }
        }
    }
    fn customerIds(self: *const Analysis, numbers: []const usize) []const u8 {
        var result: D.Text = .{};
        for (numbers, 0..) |number, i| result.add("{s}{s}", .{ if (i == 0) "" else " ", self.customers[number].id });
        return result.value();
    }
    fn featureLines(self: *const Analysis) D.Lines {
        var lines: D.Lines = .{};
        lines.write("customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure");
        for (self.customers) |customer| {
            var line: D.Text = .{};
            line.add("{s},{d},{d},{s},{s},{d},{d}", .{ customer.id, whole(customer.raw[0]), customer.orders.len, P.amount(customer.spend), P.realText(customer.raw[3]), whole(customer.raw[4]), whole(customer.raw[5]) });
            for (customer.point) |value| line.add(",{s}", .{P.realText(value)});
            lines.write(line.value());
        }
        return lines;
    }
    fn runLines(self: *const Analysis) D.Lines {
        const settings = self.data.settings;
        var lines: D.Lines = .{};
        for (settings.min_k..settings.max_k + 1) |k| {
            if (k > settings.min_k) lines.blank();
            const candidate = &self.candidates[k];
            lines.add("k {d}", .{k});
            for (candidate.runs) |run| lines.add("run {s} {d} seeds {s} iterations {d} converged {s} reseeds {d} sse {s} passes {d} transfers {d} refined {s}", .{ @tagName(run.method), run.number, self.customerIds(run.seeds[0..k]), run.lloyd.iterations, yesNo(run.lloyd.converged), run.lloyd.reseeds, P.realText(run.lloyd.sse), run.refined.passes, run.refined.transfers, P.realText(run.refined.sse) });
            for (candidate.bests[0..settings.methods.len]) |index| {
                const run = &candidate.runs[index];
                lines.add("best {s} restart {d} sse {s}", .{ @tagName(run.method), run.number, P.realText(run.refined.sse) });
            }
            const run = &candidate.runs[candidate.best];
            lines.add("chosen {s} restart {d} sse {s}", .{ @tagName(run.method), run.number, P.realText(run.refined.sse) });
            lines.add("sizes {s}", .{P.integers(candidate.solution.sizes[0..k])});
        }
        return lines;
    }
    fn selectionLines(self: *const Analysis) D.Lines {
        const settings = self.data.settings;
        const count = self.customers.len;
        var lines: D.Lines = .{};
        lines.write("indices");
        for (settings.min_k..settings.max_k + 1) |k| {
            const candidate = &self.candidates[k];
            lines.add("k={d} sse {s} elbow {s} silhouette {s} calinski_harabasz {s} davies_bouldin {s} hartigan {s}", .{ k, P.realText(candidate.solution.sse), P.realText(candidate.elbow), P.realText(candidate.silhouette), P.realText(candidate.ch), P.realText(candidate.db), if (k == settings.max_k) "-" else P.realText(candidate.hartigan) });
        }
        lines.blank();
        lines.write("votes");
        for (criteria, self.votes) |name, k| lines.add("{s} k={d}", .{ name, k });
        lines.add("chosen k={d} votes {d}", .{ self.k, self.final().votes });
        lines.blank();
        lines.write("segments");
        for (settings.min_k..settings.max_k + 1) |k| {
            const candidate = &self.candidates[k];
            var line: D.Text = .{};
            line.add("k={d}", .{k});
            for (0..k) |j| line.add(" {s}:{d}", .{ candidate.names[j], candidate.solution.sizes[j] });
            lines.write(line.value());
        }
        lines.blank();
        lines.write("stability");
        for (settings.min_k..settings.max_k + 1) |k| {
            const candidate = &self.candidates[k];
            var line: D.Text = .{};
            line.add("k={d}", .{k});
            for (0..settings.methods.len) |a| {
                for (a + 1..settings.methods.len) |b| {
                    const first = &candidate.runs[candidate.bests[a]];
                    const second = &candidate.runs[candidate.bests[b]];
                    line.add(" {s}:{s} {s}", .{ @tagName(first.method), @tagName(second.method), P.realText(V.adjustedRand(first.refined.labels[0..count], second.refined.labels[0..count])) });
                }
            }
            line.write(" final");
            for (candidate.bests[0..settings.methods.len]) |index| {
                const run = &candidate.runs[index];
                line.add(" {s} {s}", .{ @tagName(run.method), P.realText(V.adjustedRand(run.refined.labels[0..count], candidate.solution.labels[0..count])) });
            }
            line.add(" next {s}", .{if (k == settings.max_k) "-" else P.realText(V.adjustedRand(candidate.solution.labels[0..count], self.candidates[k + 1].solution.labels[0..count]))});
            lines.write(line.value());
        }
        return lines;
    }
    fn recommendation(self: *const Analysis, index: usize) []const u8 {
        const segment = self.final().solution.labels[index];
        for (self.rankings[segment][0..self.ranking_counts[segment]]) |g| { if (self.customers[index].category_spend[g] <= 0) return self.data.categories[g]; }
        return "-";
    }
    fn segmentLines(self: *const Analysis) D.Lines {
        var lines: D.Lines = .{};
        lines.write("customer,segment,name,distance,other,other_distance,silhouette,recommend");
        for (self.customers, 0..) |customer, i| {
            const segment = self.final().solution.labels[i];
            lines.add("{s},{d},{s},{s},{d},{s},{s},{s}", .{ customer.id, segment + 1, self.final().names[segment], P.realText(self.distances[i]), self.others[i] + 1, P.realText(self.other_distances[i]), P.realText(self.final().silhouettes[i]), self.recommendation(i) });
        }
        return lines;
    }
    fn gini(self: *const Analysis, members: ?[]const usize) f64 {
        const count = if (members) |values| values.len else self.customers.len;
        var storage: [400]i64 = undefined;
        const spends = storage[0..count];
        for (spends, 0..) |*value, i| value.* = self.customers[if (members) |values| values[i] else i].spend;
        std.mem.sort(i64, spends, {}, std.sort.asc(i64));
        var total: i64 = 0;
        var weighted: i64 = 0;
        for (spends, 1..) |spend, j| { total += spend; weighted += D.n(j) * spend; }
        return D.real(2 * weighted - D.n(count + 1) * total) / D.real(D.n(count) * total);
    }
    fn related(self: *const Analysis, members: []const usize, k: usize) []const u8 {
        if (k < self.data.settings.min_k or k > self.data.settings.max_k) return D.fmt("k={d} -", .{k});
        var counts = [_]usize{0} ** 10;
        for (members) |number| counts[self.candidates[k].solution.labels[number]] += 1;
        var best: usize = 0;
        for (1..k) |j| { if (counts[j] > counts[best]) best = j; }
        return D.fmt("k={d} segment {d} shared {d}", .{ k, best + 1, counts[best] });
    }
    fn profileBlock(self: *const Analysis, segment: usize) D.Lines {
        const solution = &self.final().solution;
        const count = solution.sizes[segment];
        const members = solution.members[segment][0..count];
        const spend = self.segment_spends[segment];
        const center = solution.centers[segment];
        const original = PR.originalScale(center, self.scaling);
        var lines: D.Lines = .{};
        lines.add("segment {d} {s} rule {d} size {d} share {s} revenue {s} revenue_share {s}", .{ segment + 1, self.final().names[segment], self.final().rule_numbers[segment], count, P.realText(D.real(count) / D.real(self.customers.len)), P.amount(spend), P.realText(D.real(spend) / D.real(self.total_spend)) });
        lines.add("  center {s}", .{P.reals(&center)});
        var value_line: D.Text = .{};
        value_line.write("  value");
        for (F.names, original) |name, value| value_line.add(" {s} {s}", .{ name, P.realText(value) });
        lines.write(value_line.value());
        var traits: [6]usize = undefined;
        for (0..6) |f| {
            var i = f;
            while (i > 0 and @abs(center[traits[i - 1]]) < @abs(center[f])) : (i -= 1) traits[i] = traits[i - 1];
            traits[i] = f;
        }
        lines.add("  traits {s}_{s} {s}_{s}", .{ if (center[traits[0]] > 0) "high" else "low", F.names[traits[0]], if (center[traits[1]] > 0) "high" else "low", F.names[traits[1]] });
        var medians: K.Point = undefined;
        var spends_storage: [400]i64 = undefined;
        const spends = spends_storage[0..count];
        for (0..6) |f| {
            var storage: [400]f64 = undefined;
            const values = storage[0..count];
            for (members, values) |number, *value| value.* = self.customers[number].raw[f];
            std.mem.sort(f64, values, {}, std.sort.asc(f64));
            medians[f] = values[(count - 1) / 2];
        }
        for (members, spends) |number, *value| value.* = self.customers[number].spend;
        std.mem.sort(i64, spends, {}, std.sort.asc(i64));
        lines.add("  median recency {d} frequency {d} monetary {s} basket {s} categories {d} tenure {d}", .{ whole(medians[0]), whole(medians[1]), P.amount(spends[(count - 1) / 2]), P.realText(medians[3]), whole(medians[4]), whole(medians[5]) });
        lines.add("  related {s} {s}", .{ self.related(members, self.k - 1), self.related(members, self.k + 1) });
        var order: [400]usize = undefined;
        for (members, 0..) |number, i| {
            var j = i;
            while (j > 0 and self.customers[order[j - 1]].spend < self.customers[number].spend) : (j -= 1) order[j] = order[j - 1];
            order[j] = number;
        }
        var top: D.Text = .{};
        top.write("  top_customers");
        for (order[0..@min(count, self.data.settings.top_customers)]) |number| top.add(" {s} {s}", .{ self.customers[number].id, P.amount(self.customers[number].spend) });
        lines.write(top.value());
        var cadence: usize = 0;
        var overdue: usize = 0;
        var bins = [_]usize{0} ** 11;
        var gap_total: f64 = 0;
        var silhouette: f64 = 0;
        var scores = [_]f64{0} ** 3;
        var distances: [400]f64 = undefined;
        var negative: usize = 0;
        var modes = [_]usize{0} ** 556;
        var mode: usize = 111;
        for (members, 0..) |number, i| {
            const customer = self.customers[number];
            const frequency = D.n(customer.orders.len);
            const recency = whole(customer.raw[0]);
            const tenure = whole(customer.raw[5]);
            if (frequency >= 2) {
                cadence += 1;
                gap_total += D.real(tenure - recency) / D.real(frequency - 1);
                if (recency * (frequency - 1) > self.data.settings.overdue_factor * (tenure - recency)) overdue += 1;
            }
            for (customer.orders) |purchase| {
                var bin: usize = 0;
                for (self.data.settings.order_bins) |boundary| { if (purchase.net >= 100 * boundary) bin += 1; }
                bins[bin] += 1;
            }
            silhouette += self.final().silhouettes[number];
            if (self.final().silhouettes[number] < 0) negative += 1;
            for (0..3) |s| scores[s] += D.real(self.scores[number][s]);
            modes[self.codes[number]] += 1;
            distances[i] = self.distances[number];
        }
        for (111..556) |code| { if (modes[code] > modes[mode]) mode = code; }
        lines.add("  cadence customers {d} mean_gap {s} overdue {d}", .{ cadence, if (cadence == 0) "-" else P.realText(gap_total / D.real(cadence)), overdue });
        lines.add("  order_sizes {s}", .{P.integers(bins[0 .. self.data.settings.order_bins.len + 1])});
        lines.add("  sse {s} share {s}", .{ P.realText(self.segment_sse[segment]), P.realText(self.segment_sse[segment] / solution.sse) });
        lines.add("  gini {s}", .{P.realText(self.gini(members))});
        var gross: i64 = 0;
        var returned: i64 = 0;
        var cancelled: usize = 0;
        for (self.reference_orders) |purchase| {
            const number = self.numbers[purchase.customer] orelse continue;
            if (solution.labels[number] != segment) continue;
            if (purchase.net <= 0) cancelled += 1;
            for (purchase.rows) |row| { if (row.amount > 0) gross += row.amount else returned -= row.amount; }
        }
        lines.add("  returns rate {s} returned {s} cancelled {d}", .{ P.realText(D.real(returned) / D.real(gross)), P.amount(returned), cancelled });
        lines.add("  silhouette {s} negative {d}", .{ P.realText(silhouette / D.real(count)), negative });
        lines.add("  rfm r {s} f {s} m {s} mode {d} {d}", .{ P.realText(scores[0] / D.real(count)), P.realText(scores[1] / D.real(count)), P.realText(scores[2] / D.real(count)), mode, modes[mode] });
        var categories: D.Text = .{};
        categories.write("  categories");
        for (self.rankings[segment][0..@min(self.ranking_counts[segment], self.data.settings.top_categories)]) |g| {
            const share = D.real(self.segment_categories[segment][g]) / D.real(spend);
            const lift = share / (D.real(self.overall_categories[g]) / D.real(self.total_spend));
            categories.add(" {s} {s} {s}", .{ self.data.categories[g], P.realText(share), P.realText(lift) });
        }
        lines.write(categories.value());
        var outliers: [400]usize = undefined;
        var outlier_count: usize = 0;
        if (count >= 2) {
            const moments = F.meanSd(distances[0..count]);
            const threshold = moments.mean + self.data.settings.outlier_sd * moments.sd;
            for (members, 0..) |number, i| { if (distances[i] > threshold) { outliers[outlier_count] = number; outlier_count += 1; } }
        }
        lines.add("  outliers {d}{s}{s}", .{ outlier_count, if (outlier_count == 0) "" else " ", self.customerIds(outliers[0..outlier_count]) });
        return lines;
    }
    fn profilesLines(self: *const Analysis) D.Lines {
        var lines: D.Lines = .{};
        lines.add("segments k={d} customers {d} revenue {s} gini {s}", .{ self.k, self.customers.len, P.amount(self.total_spend), P.realText(self.gini(null)) });
        for (0..self.k) |j| { lines.blank(); lines.extend(self.profileBlock(j)); }
        lines.blank();
        lines.add("category_mix {s}", .{segmentNumbers(self.k)});
        for (self.data.categories, 0..) |category, g| {
            if (!self.category_present[g]) continue;
            var line: D.Text = .{};
            line.write(category);
            for (0..self.k) |j| line.add(" {s}", .{P.realText(D.real(self.segment_categories[j][g]) / D.real(self.segment_spends[j]))});
            lines.write(line.value());
        }
        lines.blank();
        lines.add("rfm_recency {s}", .{segmentNumbers(self.k)});
        for (0..5) |offset| {
            const score = 5 - offset;
            var counts = [_]usize{0} ** 10;
            for (0..self.customers.len) |i| { if (self.scores[i][0] == score) counts[self.final().solution.labels[i]] += 1; }
            lines.add("r={d} {s}", .{ score, P.integers(counts[0..self.k]) });
        }
        lines.add("ari rfm_codes {s}", .{P.realText(V.adjustedRand(self.codes[0..self.customers.len], self.final().solution.labels[0..self.customers.len]))});
        lines.blank();
        lines.write("center_distances");
        for (self.final().solution.centers[0..self.k], 0..) |center, j| {
            var distances: [10]f64 = undefined;
            for (self.final().solution.centers[0..self.k], 0..) |other, o| distances[o] = @sqrt(K.squaredDistance(center, other, 6));
            lines.add("{d} {s}", .{ j + 1, P.reals(distances[0..self.k]) });
        }
        return lines;
    }
    fn subsamples(self: *Analysis) void {
        const n = self.customers.len;
        const size = n * self.data.settings.percent / 100;
        for (0..self.data.settings.subsamples) |_| {
            var order_storage: [400]usize = undefined;
            const order = order_storage[0..n];
            for (order, 0..) |*number, i| number.* = i;
            for (0..size) |t| {
                const j = t + @as(usize, @intCast(@mod(self.draw(), D.n(n - t))));
                std.mem.swap(usize, &order[t], &order[j]);
            }
            const sample = order[0..size];
            std.mem.sort(usize, sample, {}, std.sort.asc(usize));
            var storage: [400]K.Point = undefined;
            const points = storage[0..size];
            for (sample, points) |number, *point| point.* = self.points[number];
            const result = K.lloyd(.{ .values = points }, self.final().solution.centers[0..self.k], self.data.settings.iterations);
            for (0..self.k) |segment| {
                var best: f64 = 0;
                for (0..self.k) |j| {
                    var both: usize = 0;
                    var either: usize = 0;
                    for (sample, 0..) |number, i| {
                        const expected = self.final().solution.labels[number] == segment;
                        const actual = result.labels[i] == j;
                        if (expected and actual) both += 1;
                        if (expected or actual) either += 1;
                    }
                    const value = if (either == 0) 0 else D.real(both) / D.real(either);
                    best = @max(best, value);
                }
                self.jaccard_total[segment] += best;
                self.jaccard_min[segment] = @min(self.jaccard_min[segment], best);
            }
        }
    }
    fn robustnessLines(self: *Analysis) D.Lines {
        const settings = self.data.settings;
        const n = self.customers.len;
        var lines: D.Lines = .{};
        lines.add("subsamples {d} size {d}", .{ settings.subsamples, n * settings.percent / 100 });
        for (0..self.k) |j| lines.add("segment {d} {s} mean_jaccard {s} min_jaccard {s}", .{ j + 1, self.final().names[j], P.realText(self.jaccard_total[j] / D.real(settings.subsamples)), P.realText(self.jaccard_min[j]) });
        lines.blank();
        lines.write("ablation");
        for (F.names, 0..) |name, omitted| {
            var storage: [400]K.Point = undefined;
            const points = storage[0..n];
            for (self.points, points) |original, *point| {
                point.* = [_]f64{0} ** 6;
                var component: usize = 0;
                for (0..6) |f| { if (f != omitted) { point[component] = original[f]; component += 1; } }
            }
            const run = self.clusteringRun(.{ .values = points, .dimensions = 5 }, self.k, .maximin, 1);
            lines.add("without {s} seeds {s} iterations {d} converged {s} transfers {d} sse {s} ari {s}", .{ name, self.customerIds(run.seeds[0..self.k]), run.lloyd.iterations, yesNo(run.lloyd.converged), run.refined.transfers, P.realText(run.refined.sse), P.realText(V.adjustedRand(run.refined.labels[0..n], self.final().solution.labels[0..n])) });
        }
        const count = self.final().solution.sizes[0];
        const members = self.final().solution.members[0][0..count];
        var storage: [400]K.Point = undefined;
        const points = storage[0..count];
        for (members, points) |number, *point| point.* = self.points[number];
        const run = self.clusteringRun(.{ .values = points }, 2, .maximin, 1);
        const split = organize(.{ .values = points }, run.refined.labels[0..count], 2);
        const seeds = [_]usize{ members[run.seeds[0]], members[run.seeds[1]] };
        lines.blank();
        lines.add("drilldown segment 1 {s} size {d} seeds {s} iterations {d} converged {s} transfers {d}", .{ self.final().names[0], count, self.customerIds(&seeds), run.lloyd.iterations, yesNo(run.lloyd.converged), run.refined.transfers });
        lines.add("sse before {s} after {s} gain {s}", .{ P.realText(self.segment_sse[0]), P.realText(run.refined.sse), P.realText(self.segment_sse[0] - run.refined.sse) });
        for (0..2) |j| lines.add("part {d} size {d} center {s}", .{ j + 1, split.sizes[j], P.reals(&split.centers[j]) });
        return lines;
    }
    fn trackingLines(self: *const Analysis) D.Lines {
        const settings = self.data.settings;
        const solution = &self.final().solution;
        var lines: D.Lines = .{};
        lines.add("periods {d} days {d}", .{ settings.periods, settings.period_days });
        for (1..settings.periods + 1) |q| {
            const first = settings.reference - D.n(q) * settings.period_days + 1;
            const last = settings.reference - D.n(q - 1) * settings.period_days;
            var revenue = [_]i64{0} ** 10;
            var active = [_]usize{0} ** 10;
            var acquired = [_]usize{0} ** 10;
            for (self.customers, 0..) |customer, i| {
                const segment = solution.labels[i];
                var buyer = false;
                for (customer.orders) |purchase| {
                    if (purchase.day >= first and purchase.day <= last) { revenue[segment] += purchase.net; buyer = true; }
                }
                if (buyer) active[segment] += 1;
                const initial = settings.reference - whole(customer.raw[5]);
                if (initial >= first and initial <= last) acquired[segment] += 1;
            }
            var line: D.Text = .{};
            line.add("period {d} days {d} {d} revenue", .{ q, first, last });
            for (revenue[0..self.k]) |value| line.add(" {s}", .{P.amount(value)});
            line.add(" active {s} acquired {s}", .{ P.integers(active[0..self.k]), P.integers(acquired[0..self.k]) });
            lines.write(line.value());
        }
        const snapshot_orders = D.groupOrders(self.data, 1, settings.snapshot);
        const snapshot = F.eligibleCustomers(self.data, snapshot_orders, settings.snapshot);
        F.standardize(snapshot, self.scaling);
        var previous: [400]usize = undefined;
        @memset(&previous, self.k);
        var lost: usize = 0;
        for (snapshot) |customer| {
            var best = K.squaredDistance(customer.point, solution.centers[0], 6);
            var chosen: usize = 0;
            for (solution.centers[1..self.k], 1..) |center, j| {
                const distance = K.squaredDistance(customer.point, center, 6);
                if (distance < best) { best = distance; chosen = j; }
            }
            previous[customer.file_number] = chosen;
            if (self.numbers[customer.file_number] == null) lost += 1;
        }
        var migration = [_][10]usize{[_]usize{0} ** 10} ** 11;
        var stayed: usize = 0;
        var moved: usize = 0;
        var fresh: usize = 0;
        var changes: D.Lines = .{};
        for (self.customers, 0..) |customer, i| {
            const current = solution.labels[i];
            const old = previous[customer.file_number];
            migration[old][current] += 1;
            if (old == self.k) fresh += 1 else if (old == current) stayed += 1 else {
                moved += 1;
                changes.add("{s} {d} {d}", .{ customer.id, old + 1, current + 1 });
            }
        }
        lines.blank();
        lines.add("migration day {d} customers {d}", .{ settings.snapshot, snapshot.len });
        lines.add("from\\to {s}", .{segmentNumbers(self.k)});
        for (0..self.k + 1) |old| lines.add("{s} {s}", .{ if (old == self.k) "none" else D.fmt("{d}", .{old + 1}), P.integers(migration[old][0..self.k]) });
        lines.write("moved_customers");
        lines.extend(changes);
        lines.add("stayed {d} moved {d} new {d} lost {d}", .{ stayed, moved, fresh, lost });
        const outcome = D.groupOrders(self.data, settings.reference + 1, settings.reference + settings.outcome_days);
        var purchases = [_]i64{0} ** 400;
        for (outcome) |purchase| { if (purchase.net > 0) purchases[purchase.customer] += purchase.net; }
        lines.blank();
        lines.add("outcome days {d} {d}", .{ settings.reference + 1, settings.reference + settings.outcome_days });
        for (0..self.k) |segment| {
            const count = solution.sizes[segment];
            var buyers: usize = 0;
            var spend: i64 = 0;
            for (solution.members[segment][0..count]) |number| {
                const value = purchases[self.customers[number].file_number];
                if (value > 0) { buyers += 1; spend += value; }
            }
            lines.add("segment {d} {s} size {d} buyers {d} rate {s} revenue {s} per_customer {s}", .{ segment + 1, self.final().names[segment], count, buyers, P.realText(D.real(buyers) / D.real(count)), P.amount(spend), P.realText((D.real(spend) / 100) / D.real(count)) });
        }
        var outsiders: usize = 0;
        var spend: i64 = 0;
        for (0..self.data.ids.len) |c| { if (self.numbers[c] == null and purchases[c] > 0) { outsiders += 1; spend += purchases[c]; } }
        lines.add("unsegmented buyers {d} revenue {s}", .{ outsiders, P.amount(spend) });
        return lines;
    }
    fn summaryLines(self: *const Analysis) D.Lines {
        var used: usize = 0;
        var returns: usize = 0;
        var later: usize = 0;
        var valid: usize = 0;
        var excluded: usize = 0;
        for (self.data.rows) |row| {
            if (row.day <= self.data.settings.reference) { used += 1; if (row.amount < 0) returns += 1; }
            else later += 1;
        }
        for (self.reference_orders) |purchase| { if (purchase.net > 0) valid += 1; }
        var ids: D.Text = .{};
        for (self.data.ids, 0..) |id, c| {
            if (self.numbers[c] == null) { ids.add("{s}{s}", .{ if (excluded == 0) "" else " ", id }); excluded += 1; }
        }
        var lines: D.Lines = .{};
        lines.add("rows {d} duplicates {d} zero {d} used {d} returns {d} later {d}", .{ self.data.row_count, self.data.duplicates, self.data.free_rows, used, returns, later });
        lines.add("orders {d} valid {d} cancelled {d}", .{ self.reference_orders.len, valid, self.reference_orders.len - valid });
        lines.add("customers {d} clustered {d} excluded {d}", .{ self.data.ids.len, self.customers.len, excluded });
        lines.add("excluded_ids {s}", .{if (excluded == 0) "-" else ids.value()});
        lines.blank();
        for (self.data.categories, 0..) |category, g| {
            if (!self.category_present[g]) continue;
            var buyers: usize = 0;
            for (self.customers) |customer| { if (customer.category_spend[g] > 0) buyers += 1; }
            lines.add("category {s} revenue {s} share {s} customers {d}", .{ category, P.amount(self.overall_categories[g]), P.realText(D.real(self.overall_categories[g]) / D.real(self.total_spend)), buyers });
        }
        lines.blank();
        for (F.names, 0..) |name, f| lines.add("feature {s} transform {s} raw_mean {s} raw_sd {s} mean {s} sd {s}", .{ name, if (f >= 1 and f <= 3) "sqrt" else "none", P.realText(self.scaling.raw_mean[f]), P.realText(self.scaling.raw_sd[f]), P.realText(self.scaling.mean[f]), P.realText(self.scaling.sd[f]) });
        lines.blank();
        lines.write("correlation recency frequency monetary basket categories tenure");
        for (F.names, 0..) |name, a| {
            var values: [6]f64 = undefined;
            for (0..6) |b| values[b] = F.correlation(self.pointSequence(), a, b);
            lines.add("{s} {s}", .{ name, P.reals(&values) });
        }
        return lines;
    }
    fn writeFiles(self: *Analysis, io: std.Io) !void {
        self.fitCandidates();
        self.prepareFinal();
        self.subsamples();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try P.writeLines(io, "features.csv", self.featureLines());
        try P.writeLines(io, "runs.txt", self.runLines());
        try P.writeLines(io, "selection.txt", self.selectionLines());
        try P.writeLines(io, "segments.csv", self.segmentLines());
        try P.writeLines(io, "profiles.txt", self.profilesLines());
        try P.writeLines(io, "robustness.txt", self.robustnessLines());
        try P.writeLines(io, "tracking.txt", self.trackingLines());
        try P.writeLines(io, "summary.txt", self.summaryLines());
    }
};
fn whole(value: f64) i64 { return @intFromFloat(value); }
fn segmentNumbers(k: usize) []const u8 { var values: [10]usize = undefined; for (values[0..k], 1..) |*value, i| value.* = i; return P.integers(values[0..k]); }
fn yesNo(flag: bool) []const u8 { return if (flag) "yes" else "no"; }
fn improve(points: K.Points, original: []const usize, k: usize, limit: usize) Refined {
    var result: Refined = .{};
    const labels = result.labels[0..original.len];
    const centers = result.centers[0..k];
    @memcpy(labels, original);
    var sizes = K.clusterSizes(labels, k);
    K.clusterCenters(points, labels, centers);
    while (result.passes < limit) {
        var changes: usize = 0;
        result.passes += 1;
        for (points.values, 0..) |point, i| {
            const own = labels[i];
            if (sizes[own] == 1) continue;
            const removal = (D.real(sizes[own]) / D.real(sizes[own] - 1)) * K.squaredDistance(point, centers[own], points.dimensions);
            var target: ?usize = null;
            var cost: f64 = 0;
            for (0..k) |q| {
                if (q == own) continue;
                const insertion = (D.real(sizes[q]) / D.real(sizes[q] + 1)) * K.squaredDistance(point, centers[q], points.dimensions);
                if (target == null or insertion < cost) { target = q; cost = insertion; }
            }
            if (cost < removal) {
                labels[i] = target.?;
                sizes[own] -= 1;
                sizes[target.?] += 1;
                centers[own] = K.clusterCenter(points, labels, own);
                centers[target.?] = K.clusterCenter(points, labels, target.?);
                changes += 1;
                result.transfers += 1;
            }
        }
        if (changes == 0) break;
    }
    K.clusterCenters(points, labels, centers);
    result.sse = K.sumSquared(points, labels, centers);
    return result;
}
fn organize(points: K.Points, labels: []const usize, k: usize) Solution {
    var result: Solution = .{ .k = k };
    var groups: [10][400]usize = undefined;
    var sizes = [_]usize{0} ** 10;
    var order: [10]usize = undefined;
    for (labels, 0..) |label, i| { groups[label][sizes[label]] = i; sizes[label] += 1; }
    for (0..k) |j| {
        var i = j;
        while (i > 0 and (sizes[order[i - 1]] < sizes[j] or (sizes[order[i - 1]] == sizes[j] and groups[order[i - 1]][0] > groups[j][0]))) : (i -= 1) order[i] = order[i - 1];
        order[i] = j;
    }
    for (order[0..k], 0..) |group, j| {
        result.sizes[j] = sizes[group];
        for (groups[group][0..sizes[group]], 0..) |number, i| { result.members[j][i] = number; result.labels[number] = j; }
    }
    K.clusterCenters(points, result.labels[0..labels.len], result.centers[0..k]);
    result.sse = K.sumSquared(points, result.labels[0..labels.len], result.centers[0..k]);
    return result;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    D.allocator = arena.allocator();
    const data = try D.load(init.io);
    const rules = try PR.readRules(init.io);
    const analysis = try D.allocator.create(Analysis);
    analysis.* = Analysis.init(&data, rules);
    try analysis.writeFiles(init.io);
}
