const std = @import("std");
const e = @import("environment.zig");
const dp = @import("dynamic_programming.zig");
const td = @import("td_learning.zig");
const mc = @import("monte_carlo.zig");
const r = @import("report.zig");
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn absolute(value: i64) i64 {
    return @intCast(@abs(value));
}
const Params = struct { gamma: i64, step_reward: i64, q: i64, floor_slip: i64, ice_slip: i64, theta: i64,
     seed: i64, rollout_seed: i64, episodes: usize, limit: usize, block: usize, planning: usize, rollouts: usize,
     gammas: []i64, slips: [][2]i64, alpha: [][2]i64, epsilon: [][2]i64 };
fn pairs(values: []const i64) [][2]i64 {
    const result = e.alloc([2]i64, values.len / 2);
    for (result, 0..) |*pair, i| pair.* = .{ values[2 * i], values[2 * i + 1] };
    return result;
}
fn readParams(io: std.Io) !Params {
    const lines = try e.readLines(io, "input/params.txt");
    var rows: [15][]i64 = undefined;
    for (lines, &rows) |line, *row| {
        const words = e.split(line, ' ');
        row.* = e.alloc(i64, words.len - 1);
        for (words[1..], row.*) |word, *value| value.* = e.number(word);
    }
    return .{ .gamma = rows[0][0], .step_reward = rows[1][0], .q = rows[2][0], .floor_slip = rows[2][1],
         .ice_slip = rows[2][2], .theta = rows[3][0], .seed = rows[12][0], .rollout_seed = rows[14][0],
         .episodes = e.u(rows[6][0]), .limit = e.u(rows[7][0]), .block = e.u(rows[8][0]), .planning = e.u(rows[11][0]),
         .rollouts = e.u(rows[13][0]), .gammas = rows[4], .slips = pairs(rows[5]), .alpha = pairs(rows[9]),
         .epsilon = pairs(rows[10]) };
}
fn schedule(values: []const [2]i64, episode: usize) i64 {
    var result: i64 = 0;
    for (values) |pair| {
        if (pair[0] > e.n(episode)) break;
        result = pair[1];
    }
    return result;
}
const method_names = [_][]const u8{ "mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q" };
const policy_names = [_][]const u8{ "value_iteration", "policy_iteration", "mc", "sarsa", "q_learning",
     "expected_sarsa", "dyna_q" };
const Episode = struct { returns: i64 = 0, steps: usize = 0, end: []const u8 = "timeout", cells: []usize = &.{} };
const Block = struct { returns: i64 = 0, steps: i64 = 0, endings: [3]i64 = @splat(0), agree: i64 = 0,
     value_error: i64 = 0, coverage: i64 = 0 };
const Learning = struct { q: e.Table, visits: e.Table, policy: []usize, episodes: []Episode, blocks: []Block };
fn endingIndex(end: []const u8) usize {
    return if (equal(end, "goal")) 0 else if (equal(end, "pit")) 1 else 2;
}
fn visitTotal(visits: e.Table, state: usize) i64 {
    var total: i64 = 0;
    for (visits[state]) |count| total += count;
    return total;
}
fn learn(model: e.Model, p: Params, optimal: dp.Iteration, method: usize) Learning {
    const w = model.world;
    const q = e.zero([4]i64, w.states.len);
    const visits = e.zero([4]i64, w.states.len);
    const sums = e.zero([4]i64, w.states.len);
    const counts = e.zero([4]i64, w.states.len);
    const episodes = e.alloc(Episode, p.episodes);
    @memset(episodes, .{});
    const blocks = e.alloc(Block, p.episodes / p.block);
    @memset(blocks, .{});
    var dyna = td.Dyna.init(w.states.len);
    var random: e.Random = .{ .value = p.seed };
    const sample_buffer = e.alloc(mc.Sample, p.limit);
    for (1..p.episodes + 1) |episode| {
        const alpha = schedule(p.alpha, episode);
        const epsilon = schedule(p.epsilon, episode);
        var state = w.index[w.start].?;
        var action = if (method == 1) td.choose(q, state, epsilon, &random) else @as(usize, 0);
        const record = &episodes[episode - 1];
        if (episode == p.episodes) {
            record.cells = e.alloc(usize, p.limit + 1);
            record.cells[0] = w.start;
        }
        var sample_count: usize = 0;
        for (0..p.limit) |_| {
            if (method != 1) action = td.choose(q, state, epsilon, &random);
            const outcome = e.step(model, state, action, &random);
            const next_state = w.index[outcome.cell];
            visits[state][action] += 1;
            var next_action: usize = 0;
            if (method == 0) {
                sample_buffer[sample_count] = .{ .state = state, .action = action, .reward = outcome.reward };
                sample_count += 1;
            } else {
                var future: i64 = 0;
                if (next_state) |next| {
                    if (method == 1) {
                        next_action = td.choose(q, next, epsilon, &random);
                        future = q[next][next_action];
                    } else future = td.nextValue(q, next, epsilon, method == 3);
                }
                td.update(model, q, state, action, outcome.cell, outcome.reward, p.gamma, alpha, future);
                if (method == 4) {
                    dyna.record(state, action, outcome.cell, outcome.reward);
                    dyna.plan(model, q, p.planning, p.gamma, alpha, &random);
                }
            }
            record.returns += outcome.reward;
            record.steps += 1;
            if (episode == p.episodes) record.cells[record.steps] = outcome.cell;
            record.end = e.ending(w, outcome.cell);
            if (e.terminal(w, outcome.cell)) break;
            state = next_state.?;
            if (method == 1) action = next_action;
        }
        if (episode == p.episodes) record.cells = record.cells[0 .. record.steps + 1];
        if (method == 0) mc.update(sample_buffer[0..sample_count], q, sums, counts, p.gamma);
        if (episode % p.block == 0) {
            const block = &blocks[episode / p.block - 1];
            for (episodes[episode - p.block .. episode]) |record_| {
                block.returns += record_.returns;
                block.steps += e.n(record_.steps);
                block.endings[endingIndex(record_.end)] += 1;
            }
            for (q, 0..) |row, s| {
                const a = dp.firstMaximum(row);
                if (a == optimal.policy[s]) block.agree += 1;
                block.value_error += absolute(row[a] - optimal.values[s]);
                if (visitTotal(visits, s) > 0) block.coverage += 1;
            }
            block.value_error = @divFloor(block.value_error, e.n(q.len));
        }
    }
    return .{ .q = q, .visits = visits, .policy = dp.greedy(q), .episodes = episodes, .blocks = blocks };
}
const Path = struct {
    cells: []usize,
    end: []const u8,
    fn steps(self: Path) usize {
        return self.cells.len - 1;
    }
};
fn path(w: *const e.World, policy: []const usize, origin: usize, limit: usize) Path {
    var cells: std.ArrayList(usize) = .empty;
    e.append(usize, &cells, origin);
    const seen = e.zero(bool, w.cells.len);
    seen[origin] = true;
    while (true) {
        const state = w.index[cells.items[cells.items.len - 1]].?;
        const next = w.moves[state][policy[state]];
        const repeated = seen[next];
        e.append(usize, &cells, next);
        if (e.terminal(w, next)) return .{ .cells = cells.items, .end = e.ending(w, next) };
        if (repeated) return .{ .cells = cells.items, .end = "loop" };
        if (cells.items.len - 1 >= limit) return .{ .cells = cells.items, .end = "limit" };
        seen[next] = true;
    }
}
fn distances(model: e.Model) []i64 {
    const w = model.world;
    const distance = e.alloc(i64, w.cells.len);
    @memset(distance, -1);
    distance[w.start] = 0;
    var queue: std.ArrayList(usize) = .empty;
    e.append(usize, &queue, w.start);
    var front: usize = 0;
    while (front < queue.items.len) : (front += 1) {
        const cell = queue.items[front];
        if (e.terminal(w, cell)) continue;
        for (0..4) |action| {
            const transitions = model.transitions(w.index[cell].?, action);
            for (transitions.items()) |t| if (distance[t.cell] < 0) {
                distance[t.cell] = distance[cell] + 1;
                e.append(usize, &queue, t.cell);
            };
        }
    }
    return distance;
}
fn differences(a: []const usize, b: []const usize) usize {
    var count: usize = 0;
    for (a, b) |x, y| if (x != y) {
        count += 1;
    };
    return count;
}
fn absorption(model: e.Model, policy: []const usize, limit: usize) [4]i64 {
    const w = model.world;
    var goal = e.zero(i64, policy.len);
    var pit = e.zero(i64, policy.len);
    var expected = e.zero(i64, policy.len);
    var ng = e.alloc(i64, policy.len);
    var np = e.alloc(i64, policy.len);
    var ne = e.alloc(i64, policy.len);
    const d: i64 = 100000000;
    for (0..limit) |_| {
        for (policy, 0..) |action, s| {
            var g: i64 = 0;
            var p: i64 = 0;
            var ex: i64 = 0;
            const transitions = model.transitions(s, action);
            for (transitions.items()) |t| {
                g += t.weight * if (w.index[t.cell]) |next| goal[next] else if (w.cells[t.cell] == 'G') d else 0;
                p += t.weight * if (w.index[t.cell]) |next| pit[next] else if (w.cells[t.cell] == 'P') d else 0;
                ex += t.weight * if (w.index[t.cell]) |next| expected[next] else 0;
            }
            ng[s] = @divFloor(g, model.q);
            np[s] = @divFloor(p, model.q);
            ne[s] = d + @divFloor(ex, model.q);
        }
        std.mem.swap([]i64, &goal, &ng);
        std.mem.swap([]i64, &pit, &np);
        std.mem.swap([]i64, &expected, &ne);
    }
    const start = w.index[w.start].?;
    return .{ @divFloor(goal[start], 10000), @divFloor(pit[start], 10000), @divFloor(d - goal[start] - pit[start],
         10000), @divFloor(expected[start], 10000) };
}
fn behaviour(model: e.Model, policy: []const usize, p: Params) dp.Evaluation {
    const values = e.zero(i64, policy.len);
    const epsilon = schedule(p.epsilon, p.episodes);
    var sweeps: usize = 0;
    while (true) {
        sweeps += 1;
        var delta: i64 = 0;
        for (policy, 0..) |action, s| {
            var sum: i64 = 0;
            for (0..4) |a| sum += (epsilon + if (a == action) 4 * (1000 - epsilon) else @as(i64, 0)) * dp.bellman(model,
                 values, s, a, p.gamma);
            const value = @divFloor(sum, 4000);
            delta = @max(delta, absolute(value - values[s]));
            values[s] = value;
        }
        if (delta <= p.theta) return .{ .values = values, .sweeps = sweeps };
    }
}
const Rollouts = struct { returns: i64 = 0, discounted: i64 = 0, steps: i64 = 0, endings: [3]i64 = @splat(0),
     terminals: []i64, sorted_returns: []i64 };
fn integerLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn rollout(model: e.Model, policy: []const usize, p: Params) Rollouts {
    const w = model.world;
    var result: Rollouts = .{ .terminals = e.zero(i64, w.terminals.len), .sorted_returns = e.alloc(i64, p.rollouts) };
    var random: e.Random = .{ .value = p.rollout_seed };
    const rewards = e.alloc(i64, p.limit);
    for (result.sorted_returns) |*return_| {
        var state = w.index[w.start].?;
        var last = w.start;
        var total: i64 = 0;
        var length: usize = 0;
        for (0..p.limit) |_| {
            const outcome = e.step(model, state, policy[state], &random);
            last = outcome.cell;
            total += outcome.reward;
            rewards[length] = outcome.reward;
            length += 1;
            if (e.terminal(w, last)) break;
            state = w.index[last].?;
        }
        result.returns += total;
        result.discounted += mc.discounted(rewards[0..length], p.gamma);
        result.steps += e.n(length);
        result.endings[endingIndex(e.ending(w, last))] += 1;
        if (w.terminal_index[last]) |terminal_index| result.terminals[terminal_index] += 1;
        return_.* = total;
    }
    std.mem.sort(i64, result.sorted_returns, {}, integerLess);
    return result;
}
fn policyLines(model: e.Model, policy: []const usize, learning: ?Learning, limit: usize) r.Lines {
    const w = model.world;
    var out = r.policyGrid(w, policy);
    const route = path(w, policy, w.start, limit);
    out.add("path {s} steps {d} {s}", .{ route.end, route.steps(), r.cells(w, route.cells) });
    var counts = std.mem.zeroes([4]i64);
    var risk: i64 = 0;
    const basins = e.alloc([]const u8, policy.len);
    for (policy, w.states, 0..) |action, cell, state| {
        counts[action] += 1;
        var risky = false;
        const transitions = model.transitions(state, action);
        for (transitions.items()) |t| if (w.cells[t.cell] == 'P') {
            risky = true;
        };
        if (risky) risk += 1;
        const nominal = path(w, policy, cell, limit);
        basins[state] = if (equal(nominal.end, "goal") or equal(nominal.end, "pit")) e.fmt("{c}",
             .{@as(u8, 'a') + @as(u8, @intCast(w.terminal_index[nominal.cells[nominal.cells.len - 1]].?))}) else "*";
    }
    out.add("actions N {d} E {d} S {d} W {d} risk {d}", .{ counts[0], counts[1], counts[2], counts[3], risk });
    out.add("basins", .{});
    out.extend(r.grid(w, basins, ""));
    if (learning) |method| {
        out.add("visits", .{});
        const fields = e.alloc([]const u8, policy.len);
        for (fields, 0..) |*field, state| {
            const count = visitTotal(method.visits, state);
            field.* = if (count == 0) "0" else e.fmt("{d}", .{e.fmt("{d}", .{count}).len});
        }
        out.extend(r.grid(w, fields, ""));
    }
    return out;
}
const Visit = struct { state: usize, visits: i64 };
fn visitLess(_: void, a: Visit, b: Visit) bool {
    return if (a.visits != b.visits) a.visits > b.visits else a.state < b.state;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    e.allocator = arena.allocator();
    const w = try e.readWorld(init.io);
    const p = try readParams(init.io);
    const model: e.Model = .{ .world = &w, .q = p.q, .floor_slip = p.floor_slip, .ice_slip = p.ice_slip,
         .step_reward = p.step_reward };
    const optimal = dp.valueIteration(model, p.gamma, p.theta);
    const inplace = dp.inPlace(model, p.gamma, p.theta);
    const pi = dp.policyIteration(model, p.gamma, p.theta);
    const start = w.index[w.start].?;
    var learning: [5]Learning = undefined;
    for (&learning, 0..) |*method, i| method.* = learn(model, p, optimal, i);
    const policies = [7][]usize{ optimal.policy, pi.policy, learning[0].policy, learning[1].policy,
         learning[2].policy, learning[3].policy, learning[4].policy };
    var rollouts: [7]Rollouts = undefined;
    for (policies, &rollouts) |policy, *trials| trials.* = rollout(model, policy, p);
    const distance = distances(model);
    var value_parts: [10]r.Lines = @splat(.{});
    var kinds = std.mem.zeroes([5]i64);
    for (w.cells) |c| kinds[if (c == '#') @as(usize, 0) else if (c == '.' or c == 'S') 1 else if (c == '~') 2 else if (c == 'G') 3 else 4] += 1;
    var reachable: usize = 0;
    for (w.states) |cell| if (distance[cell] >= 0) {
        reachable += 1;
    };
    value_parts[0].add("world rows {d} cols {d} states {d} walls {d} floor {d} ice {d} goals {d} pits {d}",
         .{ w.rows, w.cols, w.states.len, kinds[0], kinds[1], kinds[2], kinds[3], kinds[4] });
    value_parts[0].add("start {s} reachable {d}", .{ r.cell(&w, w.start), reachable });
    for (w.terminals) |cell| value_parts[0].add("terminal {s} {s} reward {d} distance {s}", .{ r.cell(&w,
         cell), e.ending(&w, cell), w.rewards[cell], if (distance[cell] < 0) "-" else e.fmt("{d}",
         .{distance[cell]}) });
    value_parts[1].add("value_iteration gamma {d} theta {s} iterations {d}", .{ p.gamma, r.fixed(p.theta), optimal.deltas.len });
    for (optimal.deltas, 1..) |delta, iteration| value_parts[1].add("iteration {d} max_change {s}",
         .{ iteration, r.fixed(delta) });
    value_parts[2].add("optimal_values", .{});
    value_parts[2].extend(r.valueGrid(&w, optimal.values));
    value_parts[3].add("optimal_action_counts", .{});
    const counts = e.alloc([]const u8, w.states.len);
    const sets = e.alloc([]const u8, w.states.len);
    var ties: usize = 0;
    for (optimal.actions, counts, sets) |row, *count, *set| {
        const best = row[dp.firstMaximum(row)];
        var actions: r.Text = .{};
        for (row, 0..) |value, action| if (value == best) actions.add("{c}", .{"NESW"[action]});
        set.* = actions.value();
        count.* = e.fmt("{d}", .{set.len});
        if (set.len > 1) ties += 1;
    }
    value_parts[3].extend(r.grid(&w, counts, ""));
    value_parts[4].add("ties {d}", .{ties});
    for (sets, w.states) |set, cell| if (set.len > 1) value_parts[4].add("tie {s} {s}", .{ r.cell(&w, cell), set });
    var pair_count: usize = 0;
    var equal_values: usize = 0;
    var mirrored: usize = 0;
    const mirror = [4]usize{ 0, 3, 2, 1 };
    for (w.states, 0..) |cell, state| {
        const col = cell % w.cols;
        const other = (cell / w.cols) * w.cols + w.cols - 1 - col;
        if (col >= w.cols - 1 - col or w.index[other] == null) continue;
        pair_count += 1;
        const target = w.index[other].?;
        if (optimal.values[state] == optimal.values[target]) equal_values += 1;
        if (optimal.policy[target] == mirror[optimal.policy[state]]) mirrored += 1;
    }
    value_parts[4].add("symmetry pairs {d} equal_values {d} mirrored_actions {d}", .{ pair_count, equal_values, mirrored });
    value_parts[5].add("policy_iteration rounds {d}", .{pi.rounds.len});
    var pi_sweeps: usize = 0;
    for (pi.rounds, 1..) |round, i| {
        pi_sweeps += round.sweeps;
        value_parts[5].add("round {d} sweeps {d} changed {d} value_start {s}", .{ i, round.sweeps,
             round.changed, r.fixed(round.start) });
    }
    value_parts[6].add("policy_iteration_values", .{});
    value_parts[6].extend(r.valueGrid(&w, pi.values));
    var maximum: i64 = -1;
    var at: usize = 0;
    for (pi.values, optimal.values, 0..) |a, b, state| if (absolute(a - b) > maximum) {
        maximum = absolute(a - b);
        at = state;
    };
    value_parts[7].add("comparison policy_differences {d} max_value_difference {s} at {s}", .{ differences(pi.policy,
         optimal.policy), r.fixed(maximum), r.cell(&w, w.states[at]) });
    value_parts[7].add("backups value_iteration {d} in_place_iterations {d} in_place {d} policy_iteration {d}",
         .{ optimal.deltas.len * w.states.len * 4, inplace.sweeps, inplace.sweeps * w.states.len * 4,
         pi_sweeps * w.states.len + pi.rounds.len * w.states.len * 4 });
    value_parts[8].add("gamma_sweep", .{});
    for (p.gammas) |gamma| {
        const result = dp.valueIteration(model, gamma, p.theta);
        const route = path(&w, result.policy, w.start, p.limit);
        value_parts[8].add("gamma {d} iterations {d} value_start {s} path {s} steps {d} last {s} differences {d}",
             .{ gamma, result.deltas.len, r.fixed(result.values[start]), route.end, route.steps(),
             r.cell(&w, route.cells[route.cells.len - 1]), differences(result.policy, optimal.policy) });
    }
    value_parts[9].add("slip_sweep", .{});
    for (p.slips) |slip| {
        var changed = model;
        changed.floor_slip = slip[0];
        changed.ice_slip = slip[1];
        const result = dp.valueIteration(changed, p.gamma, p.theta);
        const route = path(&w, result.policy, w.start, p.limit);
        value_parts[9].add("slip {d} {d} iterations {d} value_start {s} path {s} steps {d} last {s} differences {d}",
             .{ slip[0], slip[1], result.deltas.len, r.fixed(result.values[start]), route.end, route.steps(),
             r.cell(&w, route.cells[route.cells.len - 1]), differences(result.policy, optimal.policy) });
    }
    var policy_parts: [7]r.Lines = @splat(.{});
    for (policies, &policy_parts, 0..) |policy, *part, i| {
        part.add("{s}", .{policy_names[i]});
        part.extend(policyLines(model, policy, if (i >= 2) learning[i - 2] else null, p.limit));
    }
    var tables: r.Lines = .{};
    tables.add("method,row,col,action,value,visits", .{});
    tables.extend(r.qRows(&w, "value_iteration", optimal.actions, null));
    var curves: r.Lines = .{};
    curves.add("method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage", .{});
    for (learning, method_names) |method, name| {
        tables.extend(r.qRows(&w, name, method.q, method.visits));
        for (method.blocks, 1..) |block, i| curves.add("{s},{d},{s},{s},{d},{d},{d},{d},{s},{d}",
             .{ name, i, r.average(block.returns, p.block), r.average(block.steps, p.block), block.endings[0],
             block.endings[1], block.endings[2], block.agree, r.fixed(block.value_error), block.coverage });
    }
    var evaluation: [14]r.Lines = @splat(.{});
    evaluation[0].add("summary states {d} start {s} rollouts {d} step_limit {d}", .{ w.states.len,
         r.cell(&w, w.start), p.rollouts, p.limit });
    const headings = [_][2][]const u8{ .{ "policies", "policy agree optimal_actions value_start sweeps max_gap at" },
         .{ "improvement", "policy changed value_start agree" }, .{ "absorption", "policy p_goal p_pit p_timeout expected_steps" },
         .{ "behaviour", "method epsilon value_start sweeps" }, .{ "q_errors", "method mean_abs max_abs at unvisited tied" },
         .{ "q_action_errors", "method N E S W" }, .{ "rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max" },
         .{ "terminals", "" }, .{ "agreement", "policy value_iteration policy_iteration mc sarsa q_learning expected_sarsa dyna_q" },
         .{ "training", "method steps goals pits timeouts best_block best_mean last_mean reach" },
         .{ "visited", "" }, .{ "last_episodes", "" }, .{ "phases", "" } };
    for (headings, evaluation[1..]) |heading, *part| {
        part.add("{s}", .{heading[0]});
        if (heading[1].len > 0) part.add("{s}", .{heading[1]});
    }
    var terminal_header: r.Text = .{};
    terminal_header.add("policy", .{});
    for (w.terminals) |cell| terminal_header.add(" {s}", .{r.cell(&w, cell)});
    evaluation[8].add("{s}", .{terminal_header.value()});
    for (policies, rollouts, 0..) |policy, trials, i| {
        const evaluated = dp.evaluate(model, policy, e.zero(i64, w.states.len), p.gamma, p.theta);
        var agree: usize = 0;
        var optimal_actions: usize = 0;
        var max_gap = optimal.values[0] - evaluated.values[0];
        var gap_at: usize = 0;
        for (policy, 0..) |action, state| {
            if (action == optimal.policy[state]) agree += 1;
            if (optimal.actions[state][action] == optimal.actions[state][optimal.policy[state]]) optimal_actions += 1;
            const gap = optimal.values[state] - evaluated.values[state];
            if (gap > max_gap) {
                max_gap = gap;
                gap_at = state;
            }
        }
        evaluation[1].add("{s} {d} {d} {s} {d} {s} {s}", .{ policy_names[i], agree, optimal_actions,
             r.fixed(evaluated.values[start]), evaluated.sweeps, r.fixed(max_gap), r.cell(&w, w.states[gap_at]) });
        const improved = dp.greedy(dp.actionValues(model, evaluated.values, p.gamma));
        const improved_value = dp.evaluate(model, improved, e.zero(i64, w.states.len), p.gamma, p.theta);
        evaluation[2].add("{s} {d} {s} {d}", .{ policy_names[i], differences(policy, improved), r.fixed(improved_value.values[start]),
             w.states.len - differences(improved, optimal.policy) });
        const absorbed = absorption(model, policy, p.limit);
        evaluation[3].add("{s} {s} {s} {s} {s}", .{ policy_names[i], r.fixed(absorbed[0]), r.fixed(absorbed[1]),
             r.fixed(absorbed[2]), r.fixed(absorbed[3]) });
        evaluation[7].add("{s} {s} {s} {s} {d} {d} {d} {d} {d} {d}", .{ policy_names[i], r.average(trials.returns,
             p.rollouts), r.fixed(@divFloor(trials.discounted, e.n(p.rollouts))), r.average(trials.steps,
             p.rollouts), trials.endings[0], trials.endings[1], trials.endings[2], trials.sorted_returns[0],
             trials.sorted_returns[(p.rollouts - 1) / 2], trials.sorted_returns[p.rollouts - 1] });
        var terminal_line: r.Text = .{};
        terminal_line.add("{s}", .{policy_names[i]});
        for (trials.terminals) |count| terminal_line.add(" {d}", .{count});
        evaluation[8].add("{s}", .{terminal_line.value()});
        var agreement_line: r.Text = .{};
        agreement_line.add("{s}", .{policy_names[i]});
        for (policies) |other| agreement_line.add(" {d}", .{w.states.len - differences(policy, other)});
        evaluation[9].add("{s}", .{agreement_line.value()});
        if (i < 2) continue;
        const method_index = i - 2;
        const method = learning[method_index];
        const name = method_names[method_index];
        const behavior = behaviour(model, policy, p);
        evaluation[4].add("{s} {d} {s} {d}", .{ name, schedule(p.epsilon, p.episodes), r.fixed(behavior.values[start]),
             behavior.sweeps });
        var errors: i64 = 0;
        var max_error: i64 = -1;
        var error_at: usize = 0;
        var unvisited: usize = 0;
        var tied: usize = 0;
        var action_errors = std.mem.zeroes([4]i64);
        var action_counts = std.mem.zeroes([4]i64);
        for (method.q, 0..) |row, state| {
            const best = row[dp.firstMaximum(row)];
            const value_error = absolute(best - optimal.values[state]);
            errors += value_error;
            if (value_error > max_error) {
                max_error = value_error;
                error_at = state;
            }
            if (visitTotal(method.visits, state) == 0) unvisited += 1;
            var count: usize = 0;
            for (row, 0..) |value, action| {
                if (value == best) count += 1;
                if (method.visits[state][action] > 0) {
                    action_errors[action] += absolute(value - optimal.actions[state][action]);
                    action_counts[action] += 1;
                }
            }
            if (count > 1) tied += 1;
        }
        evaluation[5].add("{s} {s} {s} {s} {d} {d}", .{ name, r.fixed(@divFloor(errors, e.n(w.states.len))),
             r.fixed(max_error), r.cell(&w, w.states[error_at]), unvisited, tied });
        var action_line: r.Text = .{};
        action_line.add("{s}", .{name});
        for (action_errors, action_counts) |error_, count| action_line.add(" {s}", .{if (count == 0) "-" else r.fixed(@divFloor(error_,
             count))});
        evaluation[6].add("{s}", .{action_line.value()});
        var steps_total: i64 = 0;
        var endings = std.mem.zeroes([3]i64);
        for (method.episodes) |episode| {
            steps_total += e.n(episode.steps);
            endings[endingIndex(episode.end)] += 1;
        }
        var best_block: usize = 0;
        var reach: ?usize = null;
        for (method.blocks, 0..) |block, b| {
            if (block.returns > method.blocks[best_block].returns) best_block = b;
            if (reach == null and 10 * e.n(p.rollouts) * block.returns >= 9 * e.n(p.block) * rollouts[0].returns) reach = b + 1;
        }
        evaluation[10].add("{s} {d} {d} {d} {d} {d} {s} {s} {s}", .{ name, steps_total, endings[0],
             endings[1], endings[2], best_block + 1, r.average(method.blocks[best_block].returns,
             p.block), r.average(method.blocks[method.blocks.len - 1].returns, p.block), if (reach) |b| e.fmt("{d}",
             .{b}) else "-" });
        const visits = e.alloc(Visit, w.states.len);
        for (visits, 0..) |*visit, state| visit.* = .{ .state = state, .visits = visitTotal(method.visits, state) };
        std.mem.sort(Visit, visits, {}, visitLess);
        evaluation[11].add("{s} {s}:{d} {s}:{d} {s}:{d}", .{ name, r.cell(&w, w.states[visits[0].state]),
             visits[0].visits, r.cell(&w, w.states[visits[1].state]), visits[1].visits, r.cell(&w,
             w.states[visits[2].state]), visits[2].visits });
        const last = method.episodes[method.episodes.len - 1];
        evaluation[12].add("{s} return {d} steps {d} end {s} {s}", .{ name, last.returns, last.steps,
             last.end, r.cells(&w, last.cells) });
        var phases: std.ArrayList(i64) = .empty;
        for (p.alpha) |pair| e.append(i64, &phases, pair[0]);
        for (p.epsilon) |pair| e.append(i64, &phases, pair[0]);
        std.mem.sort(i64, phases.items, {}, integerLess);
        var unique: usize = 0;
        for (phases.items) |value| if (unique == 0 or value != phases.items[unique - 1]) {
            phases.items[unique] = value;
            unique += 1;
        };
        phases.items.len = unique;
        e.append(i64, &phases, e.n(p.episodes) + 1);
        for (0..phases.items.len - 1) |phase| {
            const first = e.u(phases.items[phase]);
            const last_episode = e.u(phases.items[phase + 1]) - 1;
            var returns: i64 = 0;
            var steps_: i64 = 0;
            var goals: i64 = 0;
            for (method.episodes[first - 1 .. last_episode]) |episode| {
                returns += episode.returns;
                steps_ += e.n(episode.steps);
                if (equal(episode.end, "goal")) goals += 1;
            }
            evaluation[13].add("{s} {d}-{d} alpha {d} epsilon {d} mean_return {s} mean_steps {s} goals {d}",
                 .{ name, first, last_episode, schedule(p.alpha, first), schedule(p.epsilon, first),
                 r.average(returns, last_episode - first + 1), r.average(steps_, last_episode - first + 1),
                 goals });
        }
    }
    try r.write(init.io, "values.txt", r.parts(&value_parts));
    try r.write(init.io, "policies.txt", r.parts(&policy_parts));
    try r.write(init.io, "q_tables.csv", tables);
    try r.write(init.io, "learning_curves.csv", curves);
    try r.write(init.io, "evaluation.txt", r.parts(&evaluation));
}
