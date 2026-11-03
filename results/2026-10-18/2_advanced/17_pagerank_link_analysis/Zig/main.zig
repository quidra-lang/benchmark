const std = @import("std");
const D = @import("graph_io.zig");
const C = @import("components.zig");
const PG = @import("pagerank.zig");
const H = @import("hits.zig");
const P = @import("report.zig");
const regions = [_][]const u8{ "CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER" };
const quantities = [_][]const u8{ "in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic" };
const Analysis = struct {
    input: *const D.Input,
    graph: D.Graph = undefined, undirected: D.Graph = undefined, inter: D.Graph = undefined, host_graph: D.Graph = undefined,
    components: C.Components = undefined, host_components: C.Components = undefined,
    index: [10000]?usize = [_]?usize{null} ** 10000,
    host_of: [500]usize = undefined, host_names: D.Strings = undefined,
    core: usize = 0, kcore: [500]usize = undefined, region: [500]usize = undefined, trust_distance: [500]i64 = undefined,
    ignored_counts: [3]usize = [_]usize{0} ** 3,
    incoming: [500]usize = [_]usize{0} ** 500, outgoing: [500]usize = [_]usize{0} ** 500,
    condensation_edges: usize = 0, condensation_depth: usize = 0,
    weak_count: usize = 0, weak_largest: usize = 0, undirected_edges: usize = 0,
    closed: usize = 0, possible: usize = 0, eligible: usize = 0, degeneracy: usize = 0,
    reachable_pairs: usize = 0, distance_sum: usize = 0, diameter: usize = 0, diameter_source: usize = 0, diameter_target: usize = 0,
    histogram: [500]usize = [_]usize{0} ** 500, average_clustering: f64 = 0,
    harmonic: [500]f64 = [_]f64{0} ** 500, trust_ratio: [500]f64 = undefined,
    pagerank: PG.Result = undefined, cheirank: PG.Result = undefined, trustrank: PG.Result = undefined,
    sweep: [5]PG.Result = undefined, demoted: PG.Result = undefined, personalized: [20]PG.Result = undefined, host_rank: PG.Result = undefined,
    global_hits: H.Result = undefined,
    order: [500]usize = undefined, rank: [500]usize = undefined, chei_rank: [500]usize = undefined,
    demoted_rank: [500]usize = undefined, host_positions: [500]usize = undefined,
    suspects: [500]bool = [_]bool{false} ** 500, suspect_hosts: [500]bool = [_]bool{false} ** 500,
    suspect_count: usize = 0, removed: usize = 0,
    ignored: D.Lines = .{}, queries: D.Lines = .{},
    fn pageIds(self: *const Analysis, nodes: []const usize) []const u8 {
        var result: D.Text = .{};
        for (nodes, 0..) |node, i| result.add("{s}{d}", .{ if (i == 0) "" else " ", self.input.pages[node].id });
        return result.value();
    }
    fn representative(self: *const Analysis, members: []const bool) usize {
        var best: ?usize = null;
        for (members, 0..) |member, v| { if (member and (best == null or self.rank[v] < self.rank[best.?])) best = v; }
        return best.?;
    }
    fn rankLines(self: *const Analysis, lines: *D.Lines, nodes: []const usize, values: []const f64) void {
        for (nodes, 1..) |node, position| {
            const page = self.input.pages[node];
            lines.add("{d} {d} {s} {s} {s}", .{ position, page.id, P.fixed(values[node], 6), page.host, page.title });
        }
    }
    fn scoreBlock(self: *const Analysis, lines: *D.Lines, name: []const u8, values: []const f64) void {
        var storage: [500]usize = undefined;
        const top = topList(values, self.input.settings.top_k, &storage);
        lines.add("{s} top {d}", .{ name, self.input.settings.top_k });
        self.rankLines(lines, top, values);
    }
    fn buildGraphs(self: *Analysis) void {
        const n = self.input.pages.len;
        var hosts: std.ArrayList([]const u8) = .empty;
        for (self.input.pages, 0..) |page, i| {
            self.index[page.id] = i;
            var found = false;
            for (hosts.items) |host| { if (D.eq(host, page.host)) found = true; }
            if (!found) D.append([]const u8, &hosts, page.host);
        }
        std.mem.sort([]const u8, hosts.items, {}, D.textLess);
        self.host_names = hosts.items;
        for (self.input.pages, 0..) |page, i| {
            for (self.host_names, 0..) |host, h| { if (D.eq(host, page.host)) { self.host_of[i] = h; break; } }
        }
        const weights = zeroWeights(n);
        const reasons = [_][]const u8{ "unknown", "self", "duplicate" };
        for (self.input.records) |record| {
            const u = self.index[record.source];
            const v = self.index[record.target];
            const reason: ?usize = if (u == null or v == null) 0 else if (u.? == v.?) 1 else if (weights[u.? * n + v.?] > 0) 2 else null;
            if (reason) |r| {
                self.ignored_counts[r] += 1;
                self.ignored.add("ignored line {d} {d},{d} {s}", .{ record.line, record.source, record.target, reasons[r] });
            } else weights[u.? * n + v.?] = 1;
        }
        self.graph = D.Graph.init(n, weights);
        const undirected = zeroWeights(n);
        const inter = zeroWeights(n);
        const host_weights = zeroWeights(self.host_names.len);
        for (0..n) |u| {
            for (self.graph.out[u]) |v| {
                undirected[u * n + v] = 1;
                undirected[v * n + u] = 1;
                if (self.host_of[u] != self.host_of[v]) {
                    inter[u * n + v] = 1;
                    host_weights[self.host_of[u] * self.host_names.len + self.host_of[v]] += 1;
                }
            }
        }
        self.undirected = D.Graph.init(n, undirected);
        self.inter = D.Graph.init(n, inter);
        self.host_graph = D.Graph.init(self.host_names.len, host_weights);
        self.host_components = C.strongComponents(self.host_graph);
    }
    fn graphStatistics(self: *Analysis) void {
        const n = self.graph.count;
        var remaining: [500]i64 = undefined;
        var removed = [_]bool{false} ** 500;
        var local_sum: f64 = 0;
        for (self.undirected.out, 0..) |neighbors, v| {
            const degree = neighbors.len;
            self.undirected_edges += degree;
            remaining[v] = D.n(degree);
            if (degree < 2) continue;
            var closed: usize = 0;
            const possible = degree * (degree - 1) / 2;
            for (neighbors, 0..) |first, i| { for (neighbors[i + 1 ..]) |second| { if (self.undirected.weights[first * n + second] > 0) closed += 1; } }
            self.closed += closed;
            self.possible += possible;
            self.eligible += 1;
            local_sum += D.real(closed) / D.real(possible);
        }
        self.undirected_edges /= 2;
        self.average_clustering = local_sum / D.real(self.eligible);
        var level: usize = 0;
        var left = n;
        while (left > 0) {
            var chosen: ?usize = null;
            for (0..n) |v| { if (!removed[v] and remaining[v] <= D.n(level)) { chosen = v; break; } }
            if (chosen == null) { level += 1; continue; }
            removed[chosen.?] = true;
            self.kcore[chosen.?] = level;
            left -= 1;
            for (self.undirected.out[chosen.?]) |child| { if (!removed[child]) remaining[child] -= 1; }
        }
        self.degeneracy = level;
        var weak_labels: [500]i64 = undefined;
        var weak_sizes = [_]usize{0} ** 500;
        self.weak_count = C.weakComponents(self.graph, weak_labels[0..n]);
        for (weak_labels[0..n]) |label| weak_sizes[@intCast(label)] += 1;
        for (weak_sizes[0..self.weak_count]) |size| self.weak_largest = @max(self.weak_largest, size);
        self.components = C.strongComponents(self.graph);
        const count = self.components.count;
        const condensation = zeroWeights(count);
        var pending = [_]usize{0} ** 500;
        var depth = [_]usize{0} ** 500;
        for (self.graph.out, 0..) |neighbors, u| {
            for (neighbors) |v| {
                const first = self.components.labels[u];
                const second = self.components.labels[v];
                if (first == second) continue;
                self.outgoing[first] += 1;
                self.incoming[second] += 1;
                if (condensation[first * count + second] == 0) { condensation[first * count + second] = 1; pending[second] += 1; self.condensation_edges += 1; }
            }
        }
        var ready: [500]usize = undefined;
        var size: usize = 0;
        for (0..count) |c| {
            if (self.components.sizes[c] > self.components.sizes[self.core]) self.core = c;
            if (pending[c] == 0) { ready[size] = c; size += 1; }
        }
        while (size > 0) {
            size -= 1;
            const u = ready[size];
            for (0..count) |v| {
                if (condensation[u * count + v] == 0) continue;
                depth[v] = @max(depth[v], depth[u] + 1);
                self.condensation_depth = @max(self.condensation_depth, depth[v]);
                pending[v] -= 1;
                if (pending[v] == 0) { ready[size] = v; size += 1; }
            }
        }
        var starts_storage: [500]bool = undefined;
        var forward_storage: [500]bool = undefined;
        var backward_storage: [500]bool = undefined;
        var from_in_storage: [500]bool = undefined;
        var to_out_storage: [500]bool = undefined;
        const starts = starts_storage[0..n];
        const forward = forward_storage[0..n];
        const backward = backward_storage[0..n];
        const from_in = from_in_storage[0..n];
        const to_out = to_out_storage[0..n];
        for (starts, 0..) |*member, v| member.* = self.components.labels[v] == self.core;
        C.reachable(self.graph, starts, false, forward);
        C.reachable(self.graph, starts, true, backward);
        for (0..n) |v| self.region[v] = if (starts[v]) 0 else if (backward[v]) 1 else if (forward[v]) 2 else 6;
        for (starts, 0..) |*member, v| member.* = self.region[v] == 1;
        C.reachable(self.graph, starts, false, from_in);
        for (starts, 0..) |*member, v| member.* = self.region[v] == 2;
        C.reachable(self.graph, starts, true, to_out);
        for (0..n) |v| { if (self.region[v] == 6) self.region[v] = if (from_in[v] and to_out[v]) 3 else if (from_in[v]) 4 else if (to_out[v]) 5 else 6; }
        for (0..n) |source| {
            @memset(starts, false);
            starts[source] = true;
            var storage: [500]i64 = undefined;
            const distances = storage[0..n];
            C.bfsDistances(self.graph, starts, distances);
            for (distances, 0..) |distance, target| {
                if (source == target or distance < 0) continue;
                const steps: usize = @intCast(distance);
                self.reachable_pairs += 1;
                self.distance_sum += steps;
                self.histogram[steps] += 1;
                self.harmonic[target] += 1 / D.real(steps);
                if (steps > self.diameter) { self.diameter = steps; self.diameter_source = source; self.diameter_target = target; }
            }
        }
    }
    fn computeScores(self: *Analysis) void {
        const n = self.graph.count;
        const settings = self.input.settings;
        const everyone_storage = [_]bool{true} ** 500;
        var trusted_storage = [_]bool{false} ** 500;
        const everyone = everyone_storage[0..n];
        const trusted = trusted_storage[0..n];
        for (settings.trusted) |id| trusted[self.index[id].?] = true;
        const weights = zeroWeights(n);
        for (0..n) |u| { for (self.graph.out[u]) |v| weights[v * n + u] = 1; }
        const reversed = D.Graph.init(n, weights);
        self.pagerank = PG.powerIteration(self.graph, everyone, settings.damping, settings.iterations, settings.tolerance);
        self.cheirank = PG.powerIteration(reversed, everyone, settings.damping, settings.iterations, settings.tolerance);
        self.trustrank = PG.powerIteration(self.graph, trusted, settings.damping, settings.iterations, settings.tolerance);
        self.global_hits = H.hits(self.inter, everyone, settings.hits_iterations);
        rankOrder(self.pagerank.values[0..n], self.order[0..n]);
        positions(self.order[0..n], self.rank[0..n]);
        var order_storage: [500]usize = undefined;
        const order = order_storage[0..n];
        rankOrder(self.cheirank.values[0..n], order);
        positions(order, self.chei_rank[0..n]);
        C.bfsDistances(self.graph, trusted, self.trust_distance[0..n]);
        for (0..n) |v| self.trust_ratio[v] = self.trustrank.values[v] / self.pagerank.values[v];
        for (settings.sweep, 0..) |damping, s| self.sweep[s] = PG.powerIteration(self.graph, everyone, damping, settings.iterations, settings.tolerance);
        for (self.order[0..settings.spam_top]) |v| {
            if (D.real(P.scaled(self.trust_ratio[v], 4)) / 10000 < settings.spam_threshold) { self.suspects[v] = true; self.suspect_count += 1; self.suspect_hosts[self.host_of[v]] = true; }
        }
        if (self.suspect_count > 0) {
            const kept = zeroWeights(n);
            for (self.graph.out, 0..) |neighbors, u| {
                for (neighbors) |v| {
                    if (self.host_of[u] == self.host_of[v] and self.suspect_hosts[self.host_of[u]]) self.removed += 1 else kept[u * n + v] = 1;
                }
            }
            const graph = D.Graph.init(n, kept);
            self.demoted = PG.powerIteration(graph, everyone, settings.damping, settings.iterations, settings.tolerance);
            rankOrder(self.demoted.values[0..n], order);
            positions(order, self.demoted_rank[0..n]);
        }
        self.host_rank = PG.powerIteration(self.host_graph, everyone_storage[0..self.host_names.len], settings.damping, settings.iterations, settings.tolerance);
        rankOrder(self.host_rank.values[0..self.host_names.len], order_storage[0..self.host_names.len]);
        positions(order_storage[0..self.host_names.len], self.host_positions[0..self.host_names.len]);
    }
    fn queryScores(self: *Analysis) void {
        const n = self.graph.count;
        const settings = self.input.settings;
        for (self.input.queries, 0..) |query, q| {
            if (q > 0) self.queries.blank();
            var heading: D.Text = .{};
            heading.add("query {d} words", .{q + 1});
            for (query.words) |word| heading.add(" {s}", .{word});
            heading.write(" seeds");
            for (query.seeds) |id| heading.add(" {d}", .{id});
            self.queries.write(heading.value());
            var matched_storage: [500]usize = undefined;
            var match_count: usize = 0;
            for (self.order[0..n]) |v| {
                if (matches(self.input.pages[v], query)) { matched_storage[match_count] = v; match_count += 1; }
            }
            const matched = matched_storage[0..match_count];
            const root = matched[0..@min(match_count, settings.root_limit)];
            var base_storage = [_]bool{false} ** 500;
            const base = base_storage[0..n];
            for (root) |v| {
                base[v] = true;
                for (self.graph.out[v][0..@min(self.graph.out[v].len, settings.neighbor_limit)]) |child| base[child] = true;
                for (self.graph.in[v][0..@min(self.graph.in[v].len, settings.neighbor_limit)]) |child| base[child] = true;
            }
            var base_count: usize = 0;
            var dropped: usize = 0;
            var link_count: usize = 0;
            const weights = zeroWeights(n);
            const reverse = zeroWeights(n);
            for (self.graph.out, 0..) |neighbors, u| {
                if (base[u]) base_count += 1;
                for (neighbors) |v| {
                    if (!base[u] or !base[v]) continue;
                    if (self.host_of[u] == self.host_of[v]) dropped += 1 else {
                        weights[u * n + v] = 1;
                        reverse[v * n + u] = 1;
                        link_count += 1;
                    }
                }
            }
            self.queries.add("matched {d} root {d} base {d} links {d} dropped_intra_host {d}", .{ match_count, root.len, base_count, link_count, dropped });
            self.queries.write("results");
            self.rankLines(&self.queries, matched[0..@min(match_count, settings.top_k)], self.pagerank.values[0..n]);
            var seed_storage = [_]bool{false} ** 500;
            var reached_storage: [500]bool = undefined;
            const seeds = seed_storage[0..n];
            const reached = reached_storage[0..n];
            for (query.seeds) |id| seeds[self.index[id].?] = true;
            self.personalized[q] = PG.powerIteration(self.graph, seeds, settings.damping, settings.iterations, settings.tolerance);
            C.reachable(self.graph, seeds, false, reached);
            var reach: usize = 0;
            for (reached) |member| { if (member) reach += 1; }
            self.queries.add("personalized reach {d} seed_mass {s}", .{ reach, P.fixed(total(self.personalized[q].values[0..n], seeds), 6) });
            var top_storage: [500]usize = undefined;
            const top = topList(self.personalized[q].values[0..n], settings.top_k, &top_storage);
            self.rankLines(&self.queries, top, self.personalized[q].values[0..n]);
            var global_overlap: usize = 0;
            for (top) |v| { if (self.rank[v] <= settings.top_k) global_overlap += 1; }
            self.queries.add("overlap_with_global {d}", .{global_overlap});
            if (link_count == 0) { self.queries.write("hits none"); continue; }
            const subgraph = D.Graph.init(n, weights);
            const reversed = D.Graph.init(n, reverse);
            const scores = H.hits(subgraph, base, settings.hits_iterations);
            var salsa_authority_storage: [500]f64 = undefined;
            var salsa_hub_storage: [500]f64 = undefined;
            const salsa_authority = salsa_authority_storage[0..n];
            const salsa_hub = salsa_hub_storage[0..n];
            salsaScores(subgraph, salsa_authority);
            salsaScores(reversed, salsa_hub);
            var authority_storage: [500]usize = undefined;
            var hub_storage: [500]usize = undefined;
            var salsa_a_storage: [500]usize = undefined;
            var salsa_h_storage: [500]usize = undefined;
            const authority_top = topList(scores.authority[0..n], settings.top_k, &authority_storage);
            const hub_top = topList(scores.hub[0..n], settings.top_k, &hub_storage);
            const salsa_a_top = topList(salsa_authority, settings.top_k, &salsa_a_storage);
            const salsa_h_top = topList(salsa_hub, settings.top_k, &salsa_h_storage);
            self.queries.write("hits authorities");
            self.rankLines(&self.queries, authority_top, scores.authority[0..n]);
            self.queries.write("hits hubs");
            self.rankLines(&self.queries, hub_top, scores.hub[0..n]);
            self.queries.write("salsa authorities");
            self.rankLines(&self.queries, salsa_a_top, salsa_authority);
            self.queries.write("salsa hubs");
            self.rankLines(&self.queries, salsa_h_top, salsa_hub);
            var hosts = [_]bool{false} ** 500;
            var host_count: usize = 0;
            for (authority_top) |v| { if (!hosts[self.host_of[v]]) { hosts[self.host_of[v]] = true; host_count += 1; } }
            self.queries.add("hits_salsa_overlap authorities {d} hubs {d} authority_hosts {d}", .{ overlap(authority_top, salsa_a_top), overlap(hub_top, salsa_h_top), host_count });
            const cited = authority_top[0];
            const citing = hub_top[0];
            var cocitation = [_]usize{0} ** 500;
            var coupling = [_]usize{0} ** 500;
            for (self.graph.in[cited]) |u| { for (self.graph.out[u]) |v| { if (v != cited) cocitation[v] += 1; } }
            for (self.graph.out[citing]) |v| { for (self.graph.in[v]) |u| { if (u != citing) coupling[u] += 1; } }
            self.queries.add("related_to {d} citing {d}", .{ self.input.pages[cited].id, self.graph.in[cited].len });
            const related = rankedCounts(cocitation[0..n], settings.top_k, &top_storage);
            for (related, 1..) |v, position| { const page = self.input.pages[v]; self.queries.add("{d} {d} {d} {s} {s}", .{ position, page.id, cocitation[v], page.host, page.title }); }
            self.queries.add("coupled_to {d} cited {d}", .{ self.input.pages[citing].id, self.graph.out[citing].len });
            const similar = rankedCounts(coupling[0..n], settings.top_k, &top_storage);
            for (similar, 1..) |v, position| { const page = self.input.pages[v]; self.queries.add("{d} {d} {d} {s} {s}", .{ position, page.id, coupling[v], page.host, page.title }); }
        }
    }
    fn graphStatsLines(self: *const Analysis) D.Lines {
        const n = self.graph.count;
        var links: usize = 0;
        var intra: usize = 0;
        var reciprocal: usize = 0;
        var max_in: usize = 0;
        var max_out: usize = 0;
        var in_distribution = [_]usize{0} ** 500;
        var out_distribution = [_]usize{0} ** 500;
        var core_distribution = [_]usize{0} ** 500;
        var dangling_storage: [500]bool = undefined;
        var no_in_storage: [500]bool = undefined;
        var most_in_storage: [500]bool = undefined;
        var most_out_storage: [500]bool = undefined;
        const dangling = dangling_storage[0..n];
        const no_in = no_in_storage[0..n];
        const most_in = most_in_storage[0..n];
        const most_out = most_out_storage[0..n];
        for (self.graph.out, 0..) |neighbors, u| {
            links += neighbors.len;
            max_in = @max(max_in, self.graph.in[u].len);
            max_out = @max(max_out, neighbors.len);
            in_distribution[self.graph.in[u].len] += 1;
            out_distribution[neighbors.len] += 1;
            core_distribution[self.kcore[u]] += 1;
            dangling[u] = neighbors.len == 0;
            no_in[u] = self.graph.in[u].len == 0;
            for (neighbors) |v| {
                if (self.host_of[u] == self.host_of[v]) intra += 1;
                if (self.graph.weights[v * n + u] > 0) reciprocal += 1;
            }
        }
        for (0..n) |u| { most_in[u] = self.graph.in[u].len == max_in; most_out[u] = self.graph.out[u].len == max_out; }
        var lines: D.Lines = .{};
        lines.add("pages {d}", .{n});
        lines.add("hosts {d}", .{self.host_names.len});
        lines.add("link_rows {d}", .{self.input.records.len});
        lines.add("links {d}", .{links});
        lines.add("ignored_unknown {d}", .{self.ignored_counts[0]});
        lines.add("ignored_self {d}", .{self.ignored_counts[1]});
        lines.add("ignored_duplicate {d}", .{self.ignored_counts[2]});
        lines.extend(self.ignored);
        lines.add("intra_host_links {d}", .{intra});
        lines.add("inter_host_links {d}", .{links - intra});
        lines.add("mean_degree {s}", .{P.fixed(D.real(links) / D.real(n), 4)});
        lines.add("reciprocity {s}", .{P.fraction(D.n(reciprocal), D.n(links))});
        var node_storage: [500]usize = undefined;
        var nodes = collect(dangling, &node_storage);
        lines.add("dangling {d}{s}{s}", .{ nodes.len, if (nodes.len == 0) "" else " ", self.pageIds(nodes) });
        nodes = collect(no_in, &node_storage);
        lines.add("no_in_links {d}{s}{s}", .{ nodes.len, if (nodes.len == 0) "" else " ", self.pageIds(nodes) });
        nodes = collect(most_in, &node_storage);
        lines.add("max_in_degree {d} pages {s}", .{ max_in, self.pageIds(nodes) });
        nodes = collect(most_out, &node_storage);
        lines.add("max_out_degree {d} pages {s}", .{ max_out, self.pageIds(nodes) });
        lines.blank();
        lines.write("in_degree_distribution");
        for (in_distribution[0..n], 0..) |count, degree| { if (count > 0) lines.add("{d} {d}", .{ degree, count }); }
        lines.blank();
        lines.write("out_degree_distribution");
        for (out_distribution[0..n], 0..) |count, degree| { if (count > 0) lines.add("{d} {d}", .{ degree, count }); }
        lines.blank();
        lines.add("undirected_links {d}", .{self.undirected_edges});
        lines.add("transitivity {s}", .{P.fraction(D.n(self.closed), D.n(self.possible))});
        lines.add("average_clustering {s} pages {d}", .{ P.fixed(self.average_clustering, 4), self.eligible });
        lines.add("degeneracy {d} pages {d}", .{ self.degeneracy, core_distribution[self.degeneracy] });
        lines.write("core_distribution");
        for (core_distribution[0..n], 0..) |count, core| { if (count > 0) lines.add("{d} {d}", .{ core, count }); }
        var singletons: usize = 0;
        for (self.components.sizes[0..self.components.count]) |size| { if (size == 1) singletons += 1; }
        lines.blank();
        lines.add("strong_components {d} largest {d} singletons {d} condensation_links {d}", .{ self.components.count, self.components.sizes[self.core], singletons, self.condensation_edges });
        lines.add("weak_components {d} largest {d}", .{ self.weak_count, self.weak_largest });
        lines.add("condensation_depth {d}", .{self.condensation_depth});
        var member_storage: [500]bool = undefined;
        const members = member_storage[0..n];
        for (0..self.components.count) |c| {
            if (self.components.sizes[c] < 2) continue;
            for (members, 0..) |*member, v| member.* = self.components.labels[v] == c;
            lines.add("scc {d} size {d} min {d} incoming {d} outgoing {d} pagerank {s}{s}", .{ c + 1, self.components.sizes[c], self.input.pages[self.components.minimum[c]].id, self.incoming[c], self.outgoing[c], P.fixed(total(self.pagerank.values[0..n], members), 6), if (self.outgoing[c] == 0) " sink" else "" });
        }
        lines.blank();
        lines.add("bowtie core_scc {d}", .{self.core + 1});
        for (regions, 0..) |name, region| {
            for (members, 0..) |*member, v| member.* = self.region[v] == region;
            nodes = collect(members, &node_storage);
            var line: D.Text = .{};
            line.add("{s} {d} pagerank {s}", .{ name, nodes.len, P.fixed(total(self.pagerank.values[0..n], members), 6) });
            if (nodes.len > 0) line.add(" top {d}", .{self.input.pages[self.representative(members)].id});
            if (nodes.len >= 1 and nodes.len <= 10) line.add(" pages {s}", .{self.pageIds(nodes)});
            lines.write(line.value());
        }
        var region_links = [_][7]usize{[_]usize{0} ** 7} ** 7;
        for (self.graph.out, 0..) |neighbors, u| { for (neighbors) |v| region_links[self.region[u]][self.region[v]] += 1; }
        lines.write("region_links");
        for (regions, 0..) |first, a| { for (regions, 0..) |second, b| { if (region_links[a][b] > 0) lines.add("{s} {s} {d}", .{ first, second, region_links[a][b] }); } }
        lines.blank();
        lines.write("distances");
        lines.add("reachable_pairs {d}", .{self.reachable_pairs});
        lines.add("average {s}", .{P.fraction(D.n(self.distance_sum), D.n(self.reachable_pairs))});
        lines.add("diameter {d} from {d} to {d}", .{ self.diameter, self.input.pages[self.diameter_source].id, self.input.pages[self.diameter_target].id });
        var cumulative: usize = 0;
        var effective = self.diameter;
        for (1..self.diameter + 1) |d| { cumulative += self.histogram[d]; if (10 * cumulative >= 9 * self.reachable_pairs) { effective = d; break; } }
        lines.add("effective_diameter {d}", .{effective});
        for (1..self.diameter + 1) |d| lines.add("{d} {d}", .{ d, self.histogram[d] });
        return lines;
    }
    fn pagerankLines(self: *const Analysis) D.Lines {
        var lines: D.Lines = .{};
        lines.write("id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance");
        for (self.input.pages, 0..) |page, v| lines.add("{d},{d},{d},{d},{s},{d},{s},{s},{d},{s},{d},{s},{s},{s},{s},{d}", .{ page.id, self.graph.in[v].len, self.graph.out[v].len, self.components.labels[v] + 1, regions[self.region[v]], self.kcore[v], P.fixed(self.harmonic[v], 6), P.fixed(self.pagerank.values[v], 6), self.rank[v], P.fixed(self.cheirank.values[v], 6), self.chei_rank[v], P.fixed(self.global_hits.authority[v], 6), P.fixed(self.global_hits.hub[v], 6), P.fixed(self.trustrank.values[v], 6), P.fixed(self.trust_ratio[v], 4), self.trust_distance[v] });
        return lines;
    }
    fn hostLines(self: *const Analysis) D.Lines {
        const n = self.graph.count;
        var lines: D.Lines = .{};
        lines.write("host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank");
        for (self.host_names, 0..) |host, h| {
            var member_storage: [500]bool = undefined;
            const members = member_storage[0..n];
            var count: usize = 0;
            var core: usize = 0;
            var internal: usize = 0;
            var outgoing: usize = 0;
            var incoming: usize = 0;
            var dangling: usize = 0;
            for (0..n) |v| {
                members[v] = self.host_of[v] == h;
                if (!members[v]) continue;
                count += 1;
                if (self.region[v] == 0) core += 1;
                if (self.graph.out[v].len == 0) dangling += 1;
                for (self.graph.out[v]) |child| { if (self.host_of[child] == h) internal += 1 else outgoing += 1; }
                for (self.graph.in[v]) |parent| { if (self.host_of[parent] != h) incoming += 1; }
            }
            const density = if (count >= 2) D.real(internal) / D.real(count * (count - 1)) else 0;
            lines.add("{s},{d},{d},{d},{s},{d},{d},{d},{s},{d},{s},{d}", .{ host, count, core, internal, P.fixed(density, 4), outgoing, incoming, dangling, P.fixed(total(self.pagerank.values[0..n], members), 6), self.input.pages[self.representative(members)].id, P.fixed(self.host_rank.values[h], 6), self.host_positions[h] });
        }
        return lines;
    }
    fn rankingLines(self: *const Analysis) D.Lines {
        const n = self.graph.count;
        const limit = self.input.settings.top_k;
        var lines: D.Lines = .{};
        self.scoreBlock(&lines, "pagerank", self.pagerank.values[0..n]);
        var dangling_storage: [500]bool = undefined;
        const dangling = dangling_storage[0..n];
        for (self.graph.out, dangling) |neighbors, *member| member.* = neighbors.len == 0;
        lines.add("dangling_mass {s}", .{P.fixed(total(self.pagerank.values[0..n], dangling), 6)});
        var top_storage: [500]usize = undefined;
        const top = topList(self.pagerank.values[0..n], limit, &top_storage);
        for (top) |v| {
            var order: [500]usize = undefined;
            var contributions: [500]f64 = undefined;
            var size: usize = 0;
            for (self.graph.in[v]) |u| {
                contributions[u] = (self.input.settings.damping * self.pagerank.values[u]) / D.real(self.graph.out[u].len);
                var p = size;
                size += 1;
                while (p > 0 and P.scaled(contributions[order[p - 1]], 6) < P.scaled(contributions[u], 6)) : (p -= 1) order[p] = order[p - 1];
                order[p] = u;
            }
            var line: D.Text = .{};
            line.add("contributors {d}", .{self.input.pages[v].id});
            for (order[0..@min(size, 3)]) |u| line.add(" {d} {s}", .{ self.input.pages[u].id, P.fixed(contributions[u], 6) });
            lines.write(line.value());
        }
        const scores = [_][]const f64{ self.cheirank.values[0..n], self.global_hits.authority[0..n], self.global_hits.hub[0..n], self.trustrank.values[0..n], self.harmonic[0..n] };
        const names = [_][]const u8{ "cheirank", "authority", "hub", "trustrank", "harmonic" };
        for (names, scores) |name, values| { lines.blank(); self.scoreBlock(&lines, name, values); }
        var series: [7][500]i64 = undefined;
        for (0..n) |v| {
            series[0][v] = D.n(self.graph.in[v].len);
            series[1][v] = P.scaled(self.pagerank.values[v], 6);
            for (scores, 2..) |values, s| series[s][v] = P.scaled(values[v], 6);
        }
        lines.blank();
        lines.write("correlation");
        for (quantities, 0..) |first, a| {
            for (quantities[a + 1 ..], a + 1..) |second, b| lines.add("{s} {s} {s}", .{ first, second, kendall(series[a][0..n], series[b][0..n]) });
        }
        lines.blank();
        lines.write("damping_sweep");
        for (self.input.settings.sweep, 0..) |damping, s| {
            const result = &self.sweep[s];
            var order_storage: [500]usize = undefined;
            var rank_storage: [500]usize = undefined;
            var keys: [500]i64 = undefined;
            const order = order_storage[0..n];
            const rank = rank_storage[0..n];
            rankOrder(result.values[0..n], order);
            positions(order, rank);
            var shared: usize = 0;
            var footrule: i64 = 0;
            var shift: usize = 0;
            for (0..n) |v| {
                if (rank[v] <= limit and self.rank[v] <= limit) shared += 1;
                footrule += D.abs(D.n(rank[v]) - D.n(self.rank[v]));
                if (D.abs(D.n(rank[v]) - D.n(self.rank[v])) > D.abs(D.n(rank[shift]) - D.n(self.rank[shift]))) shift = v;
                keys[v] = P.scaled(result.values[v], 6);
            }
            lines.add("damping {s} overlap {d} footrule {d} kendall {s} largest_shift {d} {d} {d}", .{ P.fixed(damping, 4), shared, footrule, kendall(series[1][0..n], keys[0..n]), self.input.pages[shift].id, self.rank[shift], rank[shift] });
            lines.add("top {s}", .{self.pageIds(order[0..@min(n, limit)])});
        }
        lines.blank();
        lines.add("spam top {d} threshold {s}", .{ self.input.settings.spam_top, P.fixed(self.input.settings.spam_threshold, 4) });
        for (self.order[0..n]) |v| {
            if (!self.suspects[v]) continue;
            lines.add("suspect {d} rank {d} pagerank {s} trustrank {s} trust_ratio {s} trust_distance {d} kcore {d} {s}", .{ self.input.pages[v].id, self.rank[v], P.fixed(self.pagerank.values[v], 6), P.fixed(self.trustrank.values[v], 6), P.fixed(self.trust_ratio[v], 4), self.trust_distance[v], self.kcore[v], self.input.pages[v].host });
        }
        lines.add("count {d}", .{self.suspect_count});
        lines.write("trust_by_distance");
        for (0..n + 1) |d| {
            const distance: i64 = if (d == n) -1 else D.n(d);
            var members_storage: [500]bool = undefined;
            const members = members_storage[0..n];
            var size: usize = 0;
            for (members, 0..) |*member, v| { member.* = self.trust_distance[v] == distance; if (member.*) size += 1; }
            if (size > 0) lines.add("{s} pages {d} trustrank {s} pagerank {s}", .{ if (distance < 0) "unreachable" else D.fmt("{d}", .{distance}), size, P.fixed(total(self.trustrank.values[0..n], members), 6), P.fixed(total(self.pagerank.values[0..n], members), 6) });
        }
        lines.blank();
        if (self.suspect_count == 0) lines.write("demotion none") else {
            var heading: D.Text = .{};
            heading.write("demotion hosts");
            for (self.host_names, 0..) |host, h| { if (self.suspect_hosts[h]) heading.add(" {s}", .{host}); }
            heading.add(" removed_links {d}", .{self.removed});
            lines.write(heading.value());
            const demoted_top = topList(self.demoted.values[0..n], limit, &top_storage);
            for (demoted_top, 1..) |v, position| {
                const page = self.input.pages[v];
                lines.add("{d} {d} {s} was {d} {s} {s}", .{ position, page.id, P.fixed(self.demoted.values[v], 6), self.rank[v], page.host, page.title });
            }
            for (self.order[0..n]) |v| { if (self.suspects[v]) lines.add("suspect {d} before {d} after {d}", .{ self.input.pages[v].id, self.rank[v], self.demoted_rank[v] }); }
        }
        const Edge = struct { source: usize, target: usize, weight: usize };
        var heavy: [6000]Edge = undefined;
        var edges: usize = 0;
        var reciprocal: usize = 0;
        var largest: usize = 0;
        const host_count = self.host_names.len;
        for (0..host_count) |u| {
            for (0..host_count) |v| {
                const weight = self.host_graph.weights[u * host_count + v];
                if (weight == 0) continue;
                if (self.host_graph.weights[v * host_count + u] > 0) reciprocal += 1;
                var i = edges;
                edges += 1;
                while (i > 0 and heavy[i - 1].weight < weight) : (i -= 1) heavy[i] = heavy[i - 1];
                heavy[i] = .{ .source = u, .target = v, .weight = weight };
            }
        }
        for (self.host_components.sizes[0..self.host_components.count]) |size| largest = @max(largest, size);
        lines.blank();
        lines.add("host_graph hosts {d} links {d} reciprocal {d} strong_components {d} largest {d}", .{ host_count, edges, reciprocal, self.host_components.count, largest });
        lines.add("host_links top {d}", .{limit});
        for (heavy[0..@min(edges, limit)]) |edge| lines.add("{s} {s} {d}", .{ self.host_names[edge.source], self.host_names[edge.target], edge.weight });
        return lines;
    }
    fn convergenceLines(self: *const Analysis) D.Lines {
        const settings = self.input.settings;
        const damping = P.fixed(settings.damping, 4);
        var lines: D.Lines = .{};
        lines.add("iterations {d} tolerance {s}", .{ settings.iterations, P.fixed(settings.tolerance, 10) });
        convergenceBlock(&lines, D.fmt("pagerank damping {s}", .{damping}), self.pagerank);
        convergenceBlock(&lines, D.fmt("cheirank damping {s}", .{damping}), self.cheirank);
        convergenceBlock(&lines, D.fmt("trustrank damping {s} seeds {d}", .{ damping, settings.trusted.len }), self.trustrank);
        for (settings.sweep, 0..) |value, s| convergenceBlock(&lines, D.fmt("sweep damping {s}", .{P.fixed(value, 4)}), self.sweep[s]);
        if (self.suspect_count > 0) convergenceBlock(&lines, D.fmt("demoted damping {s}", .{damping}), self.demoted);
        for (0..self.input.queries.len) |q| convergenceBlock(&lines, D.fmt("personalized query {d} damping {s}", .{ q + 1, damping }), self.personalized[q]);
        convergenceBlock(&lines, D.fmt("host_pagerank damping {s} hosts {d}", .{ damping, self.host_names.len }), self.host_rank);
        return lines;
    }
    fn writeFiles(self: *Analysis, io: std.Io) !void {
        self.buildGraphs();
        self.graphStatistics();
        self.computeScores();
        self.queryScores();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try P.writeLines(io, "graph_stats.txt", self.graphStatsLines());
        try P.writeLines(io, "pagerank.csv", self.pagerankLines());
        try P.writeLines(io, "rankings.txt", self.rankingLines());
        try P.writeLines(io, "convergence.txt", self.convergenceLines());
        try P.writeLines(io, "queries.txt", self.queries);
        try P.writeLines(io, "hosts.csv", self.hostLines());
    }
};
fn convergenceBlock(lines: *D.Lines, heading: []const u8, result: PG.Result) void {
    lines.blank();
    lines.write(heading);
    var t: usize = 10;
    while (t <= result.iterations) : (t += 10) lines.add("iteration {d} l1 {s}", .{ t, P.fixed(result.changes[t - 1], 10) });
    lines.add("converged_at {s}", .{if (result.converged_at) |step| D.fmt("{d}", .{step}) else "none"});
}
fn salsaScores(graph: D.Graph, values: []f64) void {
    const n = graph.count;
    const adjacent = zeroWeights(n);
    for (graph.out) |targets| {
        if (targets.len < 2) continue;
        for (1..targets.len) |j| { const first = targets[j - 1]; const second = targets[j]; adjacent[first * n + second] = 1; adjacent[second * n + first] = 1; }
    }
    const connections = D.Graph.init(n, adjacent);
    var labels_storage: [500]i64 = undefined;
    const labels = labels_storage[0..n];
    _ = C.weakComponents(connections, labels);
    var sizes = [_]usize{0} ** 500;
    var mass = [_]usize{0} ** 500;
    var side: usize = 0;
    for (graph.in, 0..) |neighbors, v| {
        if (neighbors.len == 0) continue;
        const label: usize = @intCast(labels[v]);
        side += 1;
        sizes[label] += 1;
        mass[label] += neighbors.len;
    }
    for (graph.in, values, 0..) |neighbors, *value, v| {
        const label: usize = @intCast(labels[v]);
        value.* = if (neighbors.len == 0) 0 else D.real(sizes[label] * neighbors.len) / D.real(side * mass[label]);
    }
}
fn matches(page: D.Page, query: D.Query) bool {
    for (query.words) |entry| {
        const exclude = entry[0] == '-';
        const word = if (exclude) entry[1..] else entry;
        var found = false;
        for (page.words) |candidate| { if (D.eq(word, candidate)) found = true; }
        if (if (exclude) found else !found) return false;
    }
    return true;
}
fn overlap(first: []const usize, second: []const usize) usize {
    var result: usize = 0;
    for (first) |a| { for (second) |b| { if (a == b) { result += 1; break; } } }
    return result;
}
fn rankedCounts(counts: []const usize, limit: usize, storage: []usize) []const usize {
    var count: usize = 0;
    for (counts, 0..) |value, v| {
        if (value == 0) continue;
        var j = count;
        count += 1;
        while (j > 0 and counts[storage[j - 1]] < value) : (j -= 1) storage[j] = storage[j - 1];
        storage[j] = v;
    }
    return storage[0..@min(count, limit)];
}
fn zeroWeights(count: usize) []usize { const result = D.alloc(usize, count * count); @memset(result, 0); return result; }
fn rankOrder(values: []const f64, order: []usize) void {
    var keys: [500]i64 = undefined;
    for (values, 0..) |value, i| {
        keys[i] = P.scaled(value, 6);
        var j = i;
        while (j > 0 and keys[order[j - 1]] < keys[i]) : (j -= 1) order[j] = order[j - 1];
        order[j] = i;
    }
}
fn positions(order: []const usize, ranks: []usize) void { for (order, 1..) |node, position| ranks[node] = position; }
fn topList(values: []const f64, limit: usize, storage: []usize) []const usize {
    var order_storage: [500]usize = undefined;
    const order = order_storage[0..values.len];
    rankOrder(values, order);
    var count: usize = 0;
    for (order) |node| { if (count == limit) break; if (P.scaled(values[node], 6) > 0) { storage[count] = node; count += 1; } }
    return storage[0..count];
}
fn collect(members: []const bool, storage: []usize) []const usize { var count: usize = 0; for (members, 0..) |member, i| { if (member) { storage[count] = i; count += 1; } } return storage[0..count]; }
fn total(values: []const f64, members: ?[]const bool) f64 { var result: f64 = 0; for (values, 0..) |value, i| { if (members == null or members.?[i]) result += value; } return result; }
fn kendall(first: []const i64, second: []const i64) []const u8 {
    var concordant: i64 = 0;
    var discordant: i64 = 0;
    for (0..first.len) |i| {
        for (i + 1..first.len) |j| {
            const dx = first[i] - first[j];
            const dy = second[i] - second[j];
            if (dx == 0 or dy == 0) continue;
            if ((dx > 0) == (dy > 0)) concordant += 1 else discordant += 1;
        }
    }
    return P.fraction(concordant - discordant, @divTrunc(D.n(first.len) * D.n(first.len - 1), 2));
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    D.allocator = arena.allocator();
    const input = try D.load(init.io);
    const analysis = try D.allocator.create(Analysis);
    analysis.* = .{ .input = &input };
    try analysis.writeFiles(init.io);
}
