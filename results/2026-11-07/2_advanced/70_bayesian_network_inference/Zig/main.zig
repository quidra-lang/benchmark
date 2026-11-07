const std = @import("std");
const d = @import("network_io.zig");
const learning = @import("learning.zig");
const factors = @import("factors.zig");
const elimination = @import("elimination.zig");
const sampling = @import("sampling.zig");
const f = d.f;
const n = d.n;
const u = d.u;
const contains = factors.contains;
const united = factors.united;
const difference = factors.difference;
const observed = factors.observed;
const entryCount = factors.entryCount;
const decode = factors.decode;
const zero = [_]usize{0} ** 15;
fn real(value: f64) []const u8 {
    const text = d.fmt("{d:.4}", .{value});
    return if (d.eq(text, "-0.0000")) "0.0000" else text;
}
fn yes(value: bool) []const u8 {
    return if (value) "yes" else "no";
}
fn addBlock(out: *d.Lines, lines: d.Lines) void {
    if (out.data.items.len > 0) out.add("", .{});
    out.extend(lines);
}
fn less(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn canonical(values: []const usize) []const usize {
    const out = d.dupe(usize, values);
    std.mem.sort(usize, out, {}, less);
    return out;
}
const Params = struct { alpha: f64, given: bool, order: []const usize, limit: usize, seed: i64, sources: []const bool };
fn parameters(input: d.Input) Params {
    const lines = input.settings;
    const names = input.network.names;
    const row = d.words(lines[2]);
    const order = d.alloc(usize, row.len - 1);
    for (row[1..], order) |name, *variable| variable.* = d.indexOf(names, name);
    const sources = d.alloc(bool, names.len);
    for (sources, 0..) |*source, i| source.* = d.eq(d.words(lines[5 + i])[2], "GIVEN");
    return .{ .alpha = d.decimal(d.words(lines[0])[1]), .given = d.eq(d.words(lines[1])[1],
         "GIVEN"), .order = order, .limit = u(d.number(d.words(lines[3])[1])), .seed = d.number(d.words(lines[4])[1]),
         .sources = sources };
}
const SumResult = struct { distribution: factors.Factor, probability: f64, marginals: [15][4]f64 = [_][4]f64{[_]f64{0} ** 4} ** 15 };
const Posterior = struct { relevant: []const usize, eliminate: []const usize, initial: []const factors.Factor,
     plans: [2]elimination.Plan, result: SumResult };
const Enumeration = struct { count: usize, verdict: []const u8 };
const Answer = struct { answer: d.Lines, steps: d.Lines };
const Query = struct { variables: []const usize, evidence: []const d.Observation };
const Family = struct { variable: usize, parents: []const usize, score: f64 };
const Study = struct {
    input: d.Input,
    network: d.Network,
    p: Params,
    random: sampling.Minstd,
    variables: []const usize,
    topological: []const usize = &.{},
    depths: [15]usize = [_]usize{0} ** 15,
    children: [15][]const usize = [_][]const usize{&.{}} ** 15,
    ancestors: [15][]const usize = [_][]const usize{&.{}} ** 15,
    descendants: [15][]const usize = [_][]const usize{&.{}} ** 15,
    spouses: [15][]const usize = [_][]const usize{&.{}} ** 15,
    blankets: [15][]const usize = [_][]const usize{&.{}} ** 15,
    counts: []d.Counts,
    learned: []d.CPT,
    cpts: []d.CPT,
    likelihoods: []f64,
    parameter_counts: []usize,
    cpt_factors: []factors.Factor,
    families: std.ArrayList(Family) = .empty,
    fn init(input: d.Input) Study {
        const network = input.network;
        const p = parameters(input);
        const variables = d.alloc(usize, network.names.len);
        for (variables, 0..) |*variable, i| variable.* = i;
        var out: Study = .{ .input = input, .network = network, .p = p, .random = .{ .state = p.seed },
             .variables = variables, .counts = d.alloc(d.Counts, variables.len), .learned = d.alloc(d.CPT,
             variables.len), .cpts = d.alloc(d.CPT, variables.len), .likelihoods = d.alloc(f64,
             variables.len), .parameter_counts = d.alloc(usize, variables.len), .cpt_factors = d.alloc(factors.Factor,
             variables.len) };
        for (variables) |v| {
            var children: std.ArrayList(usize) = .empty;
            for (variables) |child| if (contains(network.parents[child], v)) d.append(usize, &children, child);
            out.children[v] = children.items;
        }
        var topological: std.ArrayList(usize) = .empty;
        var selected = [_]bool{false} ** 15;
        while (topological.items.len < variables.len) {
            for (variables) |v| {
                if (selected[v]) continue;
                var ready = true;
                for (network.parents[v]) |parent| ready = ready and selected[parent];
                if (ready) {
                    d.append(usize, &topological, v);
                    selected[v] = true;
                    break;
                }
            }
        }
        out.topological = topological.items;
        for (out.topological) |v| for (network.parents[v]) |parent| {
            out.depths[v] = @max(out.depths[v], out.depths[parent] + 1);
        };
        for (variables) |v| {
            out.ancestors[v] = out.closure(network.parents[v], network.parents);
            out.descendants[v] = out.closure(out.children[v], out.children[0..variables.len]);
            const immediate = united(network.parents[v], out.children[v]);
            var all_parents: []const usize = &.{};
            for (out.children[v]) |child| all_parents = united(all_parents, network.parents[child]);
            out.spouses[v] = difference(difference(all_parents, immediate), &.{v});
            out.blankets[v] = united(immediate, out.spouses[v]);
            out.counts[v] = learning.countSamples(v, network.parents[v], input.samples, network.sizes);
            out.learned[v] = learning.learn(out.counts[v], p.alpha);
            out.cpts[v] = if (p.sources[v]) network.expert[v].? else out.learned[v];
            out.likelihoods[v] = learning.logLikelihood(out.counts[v], out.cpts[v]);
            out.parameter_counts[v] = learning.parameterCount(out.counts[v]);
            out.cpt_factors[v] = factors.cptFactor(v, network.parents[v], out.cpts[v], network.sizes);
        }
        return out;
    }
    fn closure(self: *const Study, initial: []const usize, links: []const []const usize) []const usize {
        var reached = [_]bool{false} ** 15;
        var pending: std.ArrayList(usize) = .empty;
        for (initial) |v| if (!reached[v]) {
            reached[v] = true;
            d.append(usize, &pending, v);
        };
        while (pending.pop()) |v| for (links[v]) |neighbor| {
            if (!reached[neighbor]) {
                reached[neighbor] = true;
                d.append(usize, &pending, neighbor);
            }
        };
        var out: std.ArrayList(usize) = .empty;
        for (self.variables) |v| if (reached[v]) d.append(usize, &out, v);
        return out.items;
    }
    fn sequence(self: *const Study, variables: []const usize) []const u8 {
        if (variables.len == 0) return "-";
        var text: d.Text = .{};
        for (variables, 0..) |v, i| text.add("{s}{s}", .{ if (i == 0) "" else " ", self.network.names[v] });
        return text.value();
    }
    fn assignmentText(self: *const Study, assignment: d.Assignment, variables: []const usize) []const u8 {
        if (variables.len == 0) return "-";
        var text: d.Text = .{};
        for (variables, 0..) |v, i| text.add("{s}{s}={s}", .{ if (i == 0) "" else " ", self.network.names[v],
             self.network.states[v][assignment[v]] });
        return text.value();
    }
    fn evidence(self: *const Study, fields: []const []const u8) []const d.Observation {
        const out = d.alloc(d.Observation, fields.len);
        for (fields, out) |field, *entry| {
            const equal = std.mem.indexOfScalar(u8, field, '=').?;
            const variable = d.indexOf(self.network.names, field[0..equal]);
            entry.* = .{ .variable = variable, .state = d.indexOf(self.network.states[variable], field[equal + 1 ..]) };
        }
        return out;
    }
    fn queryParts(self: *const Study, fields: []const []const u8) Query {
        var separator = fields.len;
        for (fields, 0..) |field, i| if (d.eq(field, "|")) {
            separator = i;
            break;
        };
        const query = d.alloc(usize, separator);
        for (fields[0..separator], query) |name, *variable| variable.* = d.indexOf(self.network.names, name);
        return .{ .variables = query, .evidence = if (separator < fields.len) self.evidence(fields[separator + 1 ..]) else &.{} };
    }
    fn plans(self: *const Study, initial: []const factors.Factor, eliminate: []const usize) [2]elimination.Plan {
        return .{ elimination.makePlan(initial, eliminate, false, self.p.order, self.network.sizes),
             elimination.makePlan(initial, eliminate, true, self.p.order, self.network.sizes) };
    }
    fn sumResult(self: *const Study, initial: []const factors.Factor, plan: elimination.Plan,
         query: []const usize) SumResult {
        const final = elimination.execute(initial, plan, self.network.sizes, false).final;
        const probability = learning.total(final.values);
        const values = d.dupe(f64, final.values);
        for (values) |*value| value.* /= probability;
        var out: SumResult = .{ .distribution = .{ .variables = final.variables, .values = values,
             .sizes = final.sizes }, .probability = probability };
        for (values, 0..) |value, row| {
            const assignment = decode(row, final.variables, self.network.sizes, zero);
            for (query) |v| out.marginals[v][assignment[v]] += value;
        }
        return out;
    }
    fn posterior(self: *const Study, query: []const usize, evidence: []const d.Observation) Posterior {
        const relevant = self.closure(united(query, observed(evidence)), self.network.parents);
        const eliminate = difference(difference(relevant, query), observed(evidence));
        const initial = d.alloc(factors.Factor, relevant.len);
        for (relevant, initial) |v, *factor| factor.* = self.cpt_factors[v].reduced(evidence);
        const orders = self.plans(initial, eliminate);
        return .{ .relevant = relevant, .eliminate = eliminate, .initial = initial, .plans = orders,
             .result = self.sumResult(initial, orders[@intFromBool(self.p.given)], query) };
    }
    fn joint(self: *const Study, assignment: d.Assignment, scope: []const usize) f64 {
        var probability: f64 = 1;
        for (scope) |v| probability *= self.cpts[v].rows[learning.parentRow(self.network.parents[v],
             assignment, self.network.sizes)][assignment[v]];
        return probability;
    }
    fn queryEnumeration(self: *const Study, result: Posterior, query_values: []const usize,
         evidence: []const d.Observation) Enumeration {
        const free = difference(result.relevant, observed(evidence));
        const count = entryCount(free, self.network.sizes);
        if (count > self.p.limit) return .{ .count = count, .verdict = "skipped" };
        const query = canonical(query_values);
        const values = d.alloc(f64, entryCount(query, self.network.sizes));
        @memset(values, 0);
        var initial = zero;
        for (evidence) |entry| initial[entry.variable] = entry.state;
        for (0..count) |row| {
            const assignment = decode(row, free, self.network.sizes, initial);
            values[learning.parentRow(query, assignment, self.network.sizes)] += self.joint(assignment,
                 result.relevant);
        }
        const probability = learning.total(values);
        var agree = @abs(@log(probability) - @log(result.result.probability)) <= 1e-9;
        for (values, result.result.distribution.values) |value, posterior_value| agree = agree and @abs(value / probability - posterior_value) <= 1e-9;
        return .{ .count = count, .verdict = if (agree) "agree" else "disagree" };
    }
    fn eliminationLines(self: *const Study, relevant: []const usize, eliminate: []const usize,
         plans: [2]elimination.Plan, agreement: bool, enumeration: Enumeration) d.Lines {
        var out: d.Lines = .{};
        out.add("relevant {s}", .{self.sequence(relevant)});
        out.add("pruned {s}", .{self.sequence(difference(self.variables, relevant))});
        out.add("eliminate {s}", .{self.sequence(eliminate)});
        for (plans, 0..) |plan, method| {
            out.add("order {s}", .{if (method == 0) "minfill" else "given"});
            for (plan.steps) |step| out.add("step {s} fill {d} scope {s} entries {d}", .{ self.network.names[step.variable],
                 step.fill, self.sequence(step.scope), step.size });
            out.add("cost max {d} total {d}", .{ plan.maximum, plan.total });
        }
        out.add("used {s}", .{if (self.p.given) "given" else "minfill"});
        out.add("orders_agree {s}", .{yes(agreement)});
        out.add("enumeration {d} {s}", .{ enumeration.count, enumeration.verdict });
        return out;
    }
    fn marginalLines(self: *const Study, prefix: []const u8, query: []const usize, marginals: [15][4]f64) d.Lines {
        var out: d.Lines = .{};
        for (query) |v| {
            var row: d.Text = .{};
            row.add("{s} {s}", .{ prefix, self.network.names[v] });
            for (self.network.states[v], 0..) |state_name, state| row.add(" {s} {s}", .{ state_name,
                 real(marginals[v][state]) });
            out.add("{s}", .{row.value()});
        }
        return out;
    }
    fn answerQuery(self: *const Study, query: Query) Answer {
        const result = self.posterior(query.variables, query.evidence);
        var out: d.Lines = .{};
        out.add("log_evidence {s}", .{real(@log(result.result.probability))});
        if (query.evidence.len > 0) {
            var conflict: f64 = 0;
            for (query.evidence) |entry| conflict += @log(self.posterior(&.{}, &.{entry}).result.probability);
            conflict -= @log(result.result.probability);
            out.add("conflict {s}", .{real(conflict)});
        }
        if (query.variables.len >= 2) for (result.result.distribution.values, 0..) |value, row| {
            const distribution = result.result.distribution;
            out.add("joint {s} {s}", .{ self.assignmentText(decode(row, distribution.variables,
                 self.network.sizes, zero), distribution.variables), real(value) });
        };
        out.extend(self.marginalLines("marginal", query.variables, result.result.marginals));
        for (query.evidence, 0..) |entry, removed| {
            var reduced: std.ArrayList(d.Observation) = .empty;
            for (query.evidence, 0..) |item, i| if (i != removed) d.append(d.Observation, &reduced, item);
            const without = self.posterior(query.variables, reduced.items);
            var shift: f64 = 0;
            for (query.variables) |v| for (0..self.network.sizes[v]) |state| {
                shift = @max(shift, @abs(result.result.marginals[v][state] - without.result.marginals[v][state]));
            };
            out.add("drop {s}={s} shift {s}", .{ self.network.names[entry.variable], self.network.states[entry.variable][entry.state],
                 real(shift) });
        }
        const first = self.sumResult(result.initial, result.plans[0], query.variables);
        const second = self.sumResult(result.initial, result.plans[1], query.variables);
        var agreement = @abs(@log(first.probability) - @log(second.probability)) <= 1e-9;
        for (first.distribution.values, second.distribution.values) |a, b| agreement = agreement and @abs(a - b) <= 1e-9;
        return .{ .answer = out, .steps = self.eliminationLines(result.relevant, result.eliminate,
             result.plans, agreement, self.queryEnumeration(result, query.variables, query.evidence)) };
    }
    fn answerMpe(self: *const Study, evidence: []const d.Observation) Answer {
        const initial = d.alloc(factors.Factor, self.cpt_factors.len);
        for (self.cpt_factors, initial) |factor, *value| value.* = factor.reduced(evidence);
        const eliminate = difference(self.variables, observed(evidence));
        const plans = self.plans(initial, eliminate);
        var maxima: [2]f64 = undefined;
        var assignments: [2]d.Assignment = undefined;
        for (plans, 0..) |plan, method| {
            const executed = elimination.execute(initial, plan, self.network.sizes, true);
            maxima[method] = executed.final.values[0];
            assignments[method] = elimination.traceback(executed, self.network.sizes);
            for (evidence) |entry| assignments[method][entry.variable] = entry.state;
        }
        const method: usize = @intFromBool(self.p.given);
        const maximum = maxima[method];
        const assignment = assignments[method];
        const probability = if (evidence.len == 0) @as(f64, 1) else self.posterior(&.{}, evidence).result.probability;
        var out: d.Lines = .{};
        out.add("assignment {s}", .{self.assignmentText(assignment, self.variables)});
        out.add("log_joint {s}", .{real(@log(maximum))});
        out.add("log_evidence {s}", .{real(@log(probability))});
        out.add("posterior {s}", .{real(maximum / probability)});
        for (eliminate) |v| {
            const plan = elimination.makePlan(initial, difference(eliminate, &.{v}), self.p.given,
                 self.p.order, self.network.sizes);
            const factor = elimination.execute(initial, plan, self.network.sizes, true).final;
            var alternative: ?usize = null;
            for (0..self.network.sizes[v]) |state| if (state != assignment[v] and (alternative == null or factor.values[state] > factor.values[alternative.?])) {
                alternative = state;
            };
            out.add("margin {s} {s} {s}", .{ self.network.names[v], self.network.states[v][alternative.?],
                 real(@log(maximum) - @log(factor.values[alternative.?])) });
        }
        const agreement = std.mem.eql(usize, &assignments[0], &assignments[1]) and @abs(@log(maxima[0]) - @log(maxima[1])) <= 1e-9;
        const count = entryCount(eliminate, self.network.sizes);
        var enumeration: Enumeration = .{ .count = count, .verdict = "skipped" };
        if (count <= self.p.limit) {
            var best: f64 = -1;
            var best_assignment = zero;
            var initial_assignment = zero;
            for (evidence) |entry| initial_assignment[entry.variable] = entry.state;
            for (0..count) |row| {
                const candidate = decode(row, eliminate, self.network.sizes, initial_assignment);
                const value = self.joint(candidate, self.variables);
                if (value > best) {
                    best = value;
                    best_assignment = candidate;
                }
            }
            enumeration.verdict = if (std.mem.eql(usize, &best_assignment, &assignment) and @abs(@log(best) - @log(maximum)) <= 1e-9) "agree" else "disagree";
        }
        return .{ .answer = out, .steps = self.eliminationLines(self.variables, eliminate,
             plans, agreement, enumeration) };
    }
    fn answerSample(self: *Study, number: usize, query: Query, counts: []const usize) struct { answer: d.Lines,
         csv: d.Lines } {
        const exact = self.posterior(query.variables, query.evidence).result.marginals;
        var out = self.marginalLines("exact", query.variables, exact);
        var csv: d.Lines = .{};
        var weights = [_][4]f64{[_]f64{0} ** 4} ** 15;
        var weight: f64 = 0;
        var squared_weight: f64 = 0;
        var checkpoint: usize = 0;
        for (1..counts[counts.len - 1] + 1) |index| {
            const current = sampling.weightedSample(self.topological, self.network, self.cpts,
                 query.evidence, &self.random);
            weight += current.weight;
            squared_weight += current.weight * current.weight;
            for (query.variables) |v| weights[v][current.assignment[v]] += current.weight;
            if (index != counts[checkpoint]) continue;
            var maximum_error: f64 = 0;
            for (query.variables) |v| for (0..self.network.sizes[v]) |state| {
                const estimate = weights[v][state] / weight;
                const error_value = @abs(estimate - exact[v][state]);
                maximum_error = @max(maximum_error, error_value);
                csv.add("{d},{d},{s},{s},{s},{s},{s}", .{ number, index, self.network.names[v],
                     self.network.states[v][state], real(estimate), real(exact[v][state]),
                     real(error_value) });
            };
            out.add("after {d} weight {s} ess {s} max_error {s}", .{ index, real(weight), real(weight * weight / squared_weight),
                 real(maximum_error) });
            checkpoint += 1;
        }
        return .{ .answer = out, .csv = csv };
    }
    fn answerPredict(self: *const Study, variable: usize) d.Lines {
        const size = self.network.sizes[variable];
        var confusion = [_][4]i64{[_]i64{0} ** 4} ** 4;
        var likelihood: f64 = 0;
        for (self.input.samples) |sample| {
            var assignment = sample;
            var probabilities: [4]f64 = undefined;
            for (0..size) |state| {
                assignment[variable] = state;
                var value = self.cpts[variable].rows[learning.parentRow(self.network.parents[variable],
                     assignment, self.network.sizes)][state];
                for (self.children[variable]) |child| value *= self.cpts[child].rows[learning.parentRow(self.network.parents[child],
                     assignment, self.network.sizes)][assignment[child]];
                probabilities[state] = value;
            }
            const denominator = learning.total(probabilities[0..size]);
            for (probabilities[0..size]) |*value| value.* /= denominator;
            var predicted: usize = 0;
            for (1..size) |state| if (probabilities[state] > probabilities[predicted]) {
                predicted = state;
            };
            const actual = sample[variable];
            confusion[actual][predicted] += 1;
            likelihood += @log(probabilities[actual]);
        }
        var correct: i64 = 0;
        for (0..size) |state| correct += confusion[state][state];
        var out: d.Lines = .{};
        out.add("blanket {s}", .{self.sequence(self.blankets[variable])});
        out.add("accuracy {d}/{d} {s}", .{ correct, self.input.samples.len, real(f(correct) / f(self.input.samples.len)) });
        out.add("log_loss {s}", .{real(-likelihood / f(self.input.samples.len))});
        var row: d.Text = .{};
        row.add("predicted", .{});
        for (self.network.states[variable]) |name| row.add(" {s}", .{name});
        out.add("{s}", .{row.value()});
        for (self.network.states[variable], 0..) |name, actual| {
            row = .{};
            row.add("actual {s}", .{name});
            for (confusion[actual][0..size]) |count| row.add(" {d}", .{count});
            out.add("{s}", .{row.value()});
        }
        return out;
    }
    fn reachable(self: *const Study, x: []const usize, z: []const usize) []const usize {
        const ancestors = self.closure(z, self.network.parents);
        const Position = struct { variable: usize, direction: usize };
        var visited = [_][2]bool{[_]bool{false} ** 2} ** 15;
        var pending: std.ArrayList(Position) = .empty;
        for (canonical(x)) |v| {
            visited[v][0] = true;
            d.append(Position, &pending, .{ .variable = v, .direction = 0 });
        }
        var front: usize = 0;
        while (front < pending.items.len) : (front += 1) {
            const position = pending.items[front];
            const v = position.variable;
            var up: []const usize = &.{};
            var down: []const usize = &.{};
            if (position.direction == 0 and !contains(z, v)) {
                up = self.network.parents[v];
                down = self.children[v];
            } else if (position.direction == 1) {
                if (!contains(z, v)) down = self.children[v];
                if (contains(ancestors, v)) up = self.network.parents[v];
            }
            for ([_][]const usize{ up, down }, 0..) |next, direction| for (next) |variable| {
                if (!visited[variable][direction]) {
                    visited[variable][direction] = true;
                    d.append(Position, &pending, .{ .variable = variable, .direction = direction });
                }
            };
        }
        var out: std.ArrayList(usize) = .empty;
        for (self.variables) |v| if ((visited[v][0] or visited[v][1]) and !contains(x, v) and !contains(z,
             v)) d.append(usize, &out, v);
        return out.items;
    }
    const CountEntry = struct { key: usize, count: i64 };
    fn countLess(_: void, a: CountEntry, b: CountEntry) bool {
        return a.key < b.key;
    }
    fn countAssignments(self: *const Study, scope: []const usize) []const CountEntry {
        const values = d.alloc(CountEntry, self.input.samples.len);
        for (self.input.samples, values) |sample, *value| value.* = .{ .key = learning.parentRow(scope,
             sample, self.network.sizes), .count = 1 };
        std.mem.sort(CountEntry, values, {}, countLess);
        var count: usize = 0;
        for (values) |value| {
            if (count > 0 and values[count - 1].key == value.key) values[count - 1].count += 1 else {
                values[count] = value;
                count += 1;
            }
        }
        return values[0..count];
    }
    fn lookup(values: []const CountEntry, key: usize) i64 {
        var first: usize = 0;
        var last = values.len;
        while (first < last) {
            const middle = first + (last - first) / 2;
            if (values[middle].key < key) first = middle + 1 else last = middle;
        }
        return values[first].count;
    }
    fn answerDsep(self: *const Study, x: []const usize, y: []const usize, z_values: []const usize) d.Lines {
        const reached = self.reachable(x, z_values);
        var separated = true;
        for (y) |v| if (contains(reached, v)) {
            separated = false;
        };
        const z = canonical(z_values);
        const scope = united(united(x, y), z);
        const xz = united(x, z);
        const yz = united(y, z);
        const counts = self.countAssignments(scope);
        const count_xz = self.countAssignments(xz);
        const count_yz = self.countAssignments(yz);
        const count_z = self.countAssignments(z);
        var information: f64 = 0;
        for (counts) |entry| {
            const assignment = decode(entry.key, scope, self.network.sizes, zero);
            const nxz = lookup(count_xz, learning.parentRow(xz, assignment, self.network.sizes));
            const nyz = lookup(count_yz, learning.parentRow(yz, assignment, self.network.sizes));
            const nz = lookup(count_z, learning.parentRow(z, assignment, self.network.sizes));
            const argument = f(entry.count * nz) / f(nxz * nyz);
            information += (f(entry.count) / f(self.input.samples.len)) * @log(argument);
        }
        const degrees = (entryCount(x, self.network.sizes) - 1) * (entryCount(y, self.network.sizes) - 1) * entryCount(z,
             self.network.sizes);
        var out: d.Lines = .{};
        out.add("result {s}", .{if (separated) "separated" else "connected"});
        out.add("reachable {s}", .{self.sequence(reached)});
        out.add("data cmi {s} g2 {s} df {d}", .{ real(information), real(2 * f(self.input.samples.len) * information),
             degrees });
        return out;
    }
    fn answerBlanket(self: *const Study, variable: usize) d.Lines {
        const rest = difference(self.variables, united(self.blankets[variable], &.{variable}));
        const reached = self.reachable(&.{variable}, self.blankets[variable]);
        var separated = true;
        for (rest) |v| if (contains(reached, v)) {
            separated = false;
        };
        var out: d.Lines = .{};
        out.add("parents {s}", .{self.sequence(self.network.parents[variable])});
        out.add("children {s}", .{self.sequence(self.children[variable])});
        out.add("spouses {s}", .{self.sequence(self.spouses[variable])});
        out.add("blanket {s}", .{self.sequence(self.blankets[variable])});
        out.add("rest {s}", .{self.sequence(rest)});
        out.add("rest_separated {s}", .{yes(separated)});
        return out;
    }
    fn path(self: *const Study, start: usize, finish: usize, ignored: ?[2]usize) ?[]const usize {
        var visited = [_]bool{false} ** 15;
        var previous = [_]?usize{null} ** 15;
        var pending: std.ArrayList(usize) = .empty;
        d.append(usize, &pending, start);
        visited[start] = true;
        var front: usize = 0;
        while (front < pending.items.len) : (front += 1) {
            const v = pending.items[front];
            for (self.children[v]) |child| {
                if ((ignored != null and ignored.?[0] == v and ignored.?[1] == child) or visited[child]) continue;
                visited[child] = true;
                previous[child] = v;
                if (child == finish) {
                    var result: std.ArrayList(usize) = .empty;
                    var current: ?usize = finish;
                    while (current) |node| {
                        d.append(usize, &result, node);
                        current = previous[node];
                    }
                    for (0..result.items.len / 2) |i| std.mem.swap(usize, &result.items[i],
                         &result.items[result.items.len - i - 1]);
                    return result.items;
                }
                d.append(usize, &pending, child);
            }
        }
        return null;
    }
    fn family(self: *Study, variable: usize, parent_set: []const usize) f64 {
        const parents = canonical(parent_set);
        for (self.families.items) |entry| if (entry.variable == variable and std.mem.eql(usize,
             entry.parents, parents)) return entry.score;
        const score = learning.familyScore(variable, parents, self.input.samples, self.network.sizes, self.p.alpha);
        d.append(Family, &self.families, .{ .variable = variable, .parents = parents, .score = score });
        return score;
    }
    fn answerEdge(self: *Study, operation: []const u8, x: usize, y: usize) d.Lines {
        var out: d.Lines = .{};
        const exists = contains(self.network.parents[y], x);
        if (d.eq(operation, "ADD") and exists) {
            out.add("result exists", .{});
            return out;
        }
        if (!d.eq(operation, "ADD") and !exists) {
            out.add("result missing", .{});
            return out;
        }
        var route: ?[]const usize = null;
        var first: usize = 0;
        if (d.eq(operation, "ADD")) {
            route = self.path(y, x, null);
            first = x;
        } else if (d.eq(operation, "REVERSE")) {
            route = self.path(x, y, .{ x, y });
            first = y;
        }
        if (route) |cycle| {
            var row: d.Text = .{};
            row.add("result cycle {s}", .{self.network.names[first]});
            for (cycle) |v| row.add(" -> {s}", .{self.network.names[v]});
            out.add("{s}", .{row.value()});
            return out;
        }
        const before_y = self.family(y, self.network.parents[y]);
        const parents_y = if (d.eq(operation, "ADD")) united(self.network.parents[y], &.{x}) else difference(self.network.parents[y],
             &.{x});
        const after_y = self.family(y, parents_y);
        var change = after_y - before_y;
        out.add("result ok", .{});
        out.add("family {s} before {s} after {s}", .{ self.network.names[y], real(before_y), real(after_y) });
        if (d.eq(operation, "REVERSE")) {
            const before_x = self.family(x, self.network.parents[x]);
            const after_x = self.family(x, united(self.network.parents[x], &.{y}));
            change = (after_y - before_y) + (after_x - before_x);
            out.add("family {s} before {s} after {s}", .{ self.network.names[x], real(before_x), real(after_x) });
        }
        out.add("delta {s} {s}", .{ real(change), if (change > 0) "improves" else "worsens" });
        return out;
    }
    fn cptLines(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        for (self.variables) |v| {
            out.add("variable {s} source {s}", .{ self.network.names[v], if (self.p.sources[v]) "GIVEN" else "LEARNED" });
            var row: d.Text = .{};
            row.add("states", .{});
            for (self.network.states[v]) |name| row.add(" {s}", .{name});
            out.add("{s}", .{row.value()});
            out.add("parents {s}", .{self.sequence(self.network.parents[v])});
            for (self.counts[v].rows, 0..) |counts, r| {
                row = .{};
                const assignment = decode(r, self.network.parents[v], self.network.sizes, zero);
                row.add("row {s} counts", .{self.assignmentText(assignment, self.network.parents[v])});
                for (counts[0..self.network.sizes[v]]) |count| row.add(" {d}", .{count});
                row.add(" probs", .{});
                for (self.cpts[v].rows[r][0..self.network.sizes[v]]) |value| row.add(" {s}", .{real(value)});
                out.add("{s}", .{row.value()});
            }
            const bic = self.likelihoods[v] - f(self.parameter_counts[v]) * @log(f(self.input.samples.len)) / 2;
            out.add("loglik {s} parameters {d} bic {s}", .{ real(self.likelihoods[v]), self.parameter_counts[v],
                 real(bic) });
            const model = self.posterior(&.{v}, &.{});
            row = .{};
            row.add("marginal model", .{});
            for (model.result.marginals[v][0..self.network.sizes[v]]) |value| row.add(" {s}", .{real(value)});
            row.add(" data", .{});
            for (0..self.network.sizes[v]) |state| {
                var count: i64 = 0;
                for (self.counts[v].rows) |counts| count += counts[state];
                row.add(" {s}", .{real(f(count) / f(self.input.samples.len))});
            }
            out.add("{s}", .{row.value()});
            if (!self.p.sources[v]) {
                var difference_text: []const u8 = "-";
                if (self.network.expert[v]) |expert| {
                    var maximum: f64 = 0;
                    for (self.learned[v].rows, expert.rows) |learned, given| for (0..self.network.sizes[v]) |state| {
                        maximum = @max(maximum, @abs(learned[state] - given[state]));
                    };
                    difference_text = real(maximum);
                }
                out.add("given_difference {s}", .{difference_text});
            }
            out.add("", .{});
        }
        const likelihood = learning.total(self.likelihoods);
        var parameters_count: usize = 0;
        for (self.parameter_counts) |count| parameters_count += count;
        out.add("network samples {d} pseudocount {s} loglik {s} parameters {d} bic {s}", .{ self.input.samples.len,
             real(self.p.alpha), real(likelihood), parameters_count, real(likelihood - f(parameters_count) * @log(f(self.input.samples.len)) / 2) });
        return out;
    }
    fn structureSummary(self: *const Study) d.Lines {
        const plans = self.plans(self.cpt_factors, self.variables);
        var widths = [_]usize{0} ** 2;
        for (plans, 0..) |plan, method| for (plan.steps) |step| {
            widths[method] = @max(widths[method], step.scope.len - 1);
        };
        const graph = elimination.interactionGraph(self.cpt_factors);
        var moral_edges: usize = 0;
        var edges: usize = 0;
        var roots: std.ArrayList(usize) = .empty;
        var leaves: std.ArrayList(usize) = .empty;
        for (self.variables) |v| {
            edges += self.network.parents[v].len;
            if (self.network.parents[v].len == 0) d.append(usize, &roots, v);
            if (self.children[v].len == 0) d.append(usize, &leaves, v);
            for (v + 1..self.variables.len) |w| moral_edges += @intFromBool(graph.neighbors[v] & d.bit(w) != 0);
        }
        var out: d.Lines = .{};
        out.add("variables {d} edges {d}", .{ self.variables.len, edges });
        out.add("topological_order {s}", .{self.sequence(self.topological)});
        out.add("roots {s}", .{self.sequence(roots.items)});
        out.add("leaves {s}", .{self.sequence(leaves.items)});
        out.add("moral_edges {d} width minfill {d} given {d}", .{ moral_edges, widths[0], widths[1] });
        for (self.variables) |v| out.add("variable {s} states {d} parents {d} children {d} depth {d} ancestors {d} descendants {d} blanket {d}",
             .{ self.network.names[v], self.network.sizes[v], self.network.parents[v].len,
             self.children[v].len, self.depths[v], self.ancestors[v].len, self.descendants[v].len,
             self.blankets[v].len });
        return out;
    }
    fn save(io: std.Io, name: []const u8, lines: d.Lines) !void {
        var text: d.Text = .{};
        for (lines.data.items) |line| text.add("{s}\n", .{line});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
    }
    fn run(self: *Study, io: std.Io) !void {
        const cpts = self.cptLines();
        var answers: d.Lines = .{};
        var steps: d.Lines = .{};
        var structure = self.structureSummary();
        var csv: d.Lines = .{};
        csv.add("query,samples,variable,state,estimate,exact,abs_error", .{});
        for (self.input.queries, 1..) |query_line, number| {
            const fields = d.words(query_line);
            const kind = fields[0];
            var heading: d.Lines = .{};
            heading.add("query {d} {s}", .{ number, query_line });
            if (d.eq(kind, "QUERY") or d.eq(kind, "MPE")) {
                const result = if (d.eq(kind, "QUERY")) self.answerQuery(self.queryParts(fields[1..])) else self.answerMpe(self.evidence(fields[1..]));
                var answer: d.Lines = .{};
                answer.extend(heading);
                answer.extend(result.answer);
                addBlock(&answers, answer);
                var order: d.Lines = .{};
                order.extend(heading);
                order.extend(result.steps);
                addBlock(&steps, order);
            } else if (d.eq(kind, "SAMPLE")) {
                var separator: usize = 1;
                while (!d.eq(fields[separator], "COUNTS")) separator += 1;
                const counts = d.alloc(usize, fields.len - separator - 1);
                for (fields[separator + 1 ..], counts) |value, *count| count.* = u(d.number(value));
                const result = self.answerSample(number, self.queryParts(fields[1..separator]), counts);
                heading.extend(result.answer);
                addBlock(&answers, heading);
                csv.extend(result.csv);
            } else if (d.eq(kind, "PREDICT")) {
                heading.extend(self.answerPredict(d.indexOf(self.network.names, fields[1])));
                addBlock(&answers, heading);
            } else {
                var result: d.Lines = undefined;
                if (d.eq(kind, "DSEP")) {
                    var groups = [_]std.ArrayList(usize){.empty} ** 3;
                    var group: usize = 0;
                    for (fields[1..]) |field| {
                        if (d.eq(field, "|")) group += 1 else d.append(usize, &groups[group],
                             d.indexOf(self.network.names, field));
                    }
                    result = self.answerDsep(groups[0].items, groups[1].items, groups[2].items);
                } else if (d.eq(kind, "BLANKET")) result = self.answerBlanket(d.indexOf(self.network.names,
                     fields[1])) else result = self.answerEdge(fields[1], d.indexOf(self.network.names,
                     fields[2]), d.indexOf(self.network.names, fields[3]));
                heading.extend(result);
                addBlock(&structure, heading);
            }
        }
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try save(io, "cpts.txt", cpts);
        try save(io, "structure.txt", structure);
        try save(io, "answers.txt", answers);
        try save(io, "elimination.txt", steps);
        try save(io, "sampling.csv", csv);
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    var study = Study.init(try d.readInputs(init.io));
    try study.run(init.io);
}
