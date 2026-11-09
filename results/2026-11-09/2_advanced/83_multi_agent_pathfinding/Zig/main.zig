const std = @import("std");
const g = @import("grid_map.zig");
const ll = @import("low_level.zig");
const c = @import("cbs.zig");
const pp = @import("prioritized.zig");
const r = @import("report.zig");
const class_names = [_][]const u8{ "cardinal", "semi_cardinal", "non_cardinal" };
const Solver = enum { pp, cbs, icbs, whca };
const solver_names = [_][]const u8{ "PP", "CBS", "ICBS", "WHCA" };
const Definition = struct { name: []const u8, solver: Solver, makespan: bool };
const Delay = struct { agent: usize, start: usize, duration: usize };
const Parameters = struct { horizon: usize = 0, hl_budget: usize = 0, ll_budget: i64 = 0, window: usize = 0,
     step: usize = 0, orders: []const []const usize = &.{}, runs: []const Definition = &.{},
     animate: []const u8 = "", frames: usize = 0, delays: []const Delay = &.{} };
fn readParameters(io: std.Io, count: usize) !Parameters {
    var out: Parameters = .{};
    var orders: std.ArrayList([]const usize) = .empty;
    var runs: std.ArrayList(Definition) = .empty;
    var delays: std.ArrayList(Delay) = .empty;
    const number_order = g.alloc(usize, count);
    for (number_order, 0..) |*id, i| id.* = i;
    g.append([]const usize, &orders, number_order);
    for (try g.readLines(io, "input/params.txt")) |line| {
        const f = g.words(line);
        if (g.eq(f[0], "HORIZON")) out.horizon = g.u(g.number(f[1])) else if (g.eq(f[0], "HL_BUDGET")) out.hl_budget = g.u(g.number(f[1])) else if (g.eq(f[0],
             "LL_BUDGET")) out.ll_budget = g.number(f[1]) else if (g.eq(f[0], "WINDOW")) {
            out.window = g.u(g.number(f[1]));
            out.step = g.u(g.number(f[2]));
        } else if (g.eq(f[0], "ORDER")) {
            const order = g.alloc(usize, count);
            for (f[1..], order) |value, *id| id.* = g.u(g.number(value));
            g.append([]const usize, &orders, order);
        } else if (g.eq(f[0], "RUN")) {
            var solver: Solver = .pp;
            for (solver_names, 0..) |name, index| if (g.eq(f[1], name)) {
                solver = @enumFromInt(index);
            };
            g.append(Definition, &runs, .{ .name = g.fmt("{s}-{s}", .{ f[1], f[2] }), .solver = solver,
                 .makespan = g.eq(f[2], "MAKESPAN") });
        } else if (g.eq(f[0], "ANIMATE")) {
            out.animate = f[1];
            out.frames = g.u(g.number(f[2]));
        } else g.append(Delay, &delays, .{ .agent = g.u(g.number(f[1])), .start = g.u(g.number(f[2])),
             .duration = g.u(g.number(f[3])) });
    }
    out.orders = orders.items;
    out.runs = runs.items;
    out.delays = delays.items;
    return out;
}
const Mdd = struct { widths: []usize, states: usize, maximum: usize };
fn mdd(grid: g.Grid, agent: g.Agent, distances: []const i64, length: usize, restrictions: *const ll.Prohibitions,
     allocator: std.mem.Allocator) Mdd {
    const cells = grid.size();
    const size = (length + 1) * cells;
    const forward = allocator.alloc(bool, size) catch @panic("allocation failed");
    defer allocator.free(forward);
    @memset(forward, false);
    const valid = allocator.alloc(bool, size) catch @panic("allocation failed");
    defer allocator.free(valid);
    @memset(valid, false);
    forward[agent.start] = true;
    for (1..length + 1) |time| for (0..cells) |source| if (forward[(time - 1) * cells + source]) {
        const destinations = grid.destinations(source);
        for (destinations.cells[0..destinations.count]) |destination| if (distances[destination] >= 0 and g.n(time) + distances[destination] <= g.n(length) and restrictions.actionAllowed(source,
             destination, time)) {
            forward[time * cells + destination] = true;
        };
    };
    valid[length * cells + agent.goal] = true;
    var time = length;
    while (time > 0) {
        time -= 1;
        for (0..cells) |source| if (forward[time * cells + source]) {
            const destinations = grid.destinations(source);
            for (destinations.cells[0..destinations.count]) |destination| if (valid[(time + 1) * cells + destination] and restrictions.actionAllowed(source,
                 destination, time + 1)) {
                valid[time * cells + source] = true;
                break;
            };
        };
    }
    const widths = allocator.alloc(usize, length + 1) catch @panic("allocation failed");
    @memset(widths, 0);
    var states: usize = 0;
    var maximum: usize = 0;
    for (0..length + 1) |layer| {
        for (valid[layer * cells .. (layer + 1) * cells]) |has| widths[layer] += @intFromBool(has);
        states += widths[layer];
        maximum = @max(maximum, widths[layer]);
    }
    return .{ .widths = widths, .states = states, .maximum = maximum };
}
fn conflictClass(conflict: c.Conflict, paths: g.Plan, restrictions: []const ll.Prohibitions,
     grid: g.Grid, agents: []const g.Agent, distances: []const []const i64, cache: *[20]?[]usize,
     allocator: std.mem.Allocator) usize {
    var fixed: usize = 0;
    for ([2]usize{ conflict.a, conflict.b }) |id| {
        const length = paths[id].len - 1;
        if (conflict.time > length) {
            fixed += 1;
            continue;
        }
        if (cache[id] == null) cache[id] = mdd(grid, agents[id], distances[id], length, &restrictions[id],
             allocator).widths;
        const widths = cache[id].?;
        const forced = widths[conflict.time] == 1 and (!conflict.edge or widths[conflict.time - 1] == 1);
        fixed += @intFromBool(forced);
    }
    return 2 - fixed;
}
const Overview = struct { free: usize, degrees: [4]usize, components: usize, shortest: []const i64,
     mdds: []const Mdd, soc: i64, makespan: i64, conflicts: []const c.Conflict, classes: [3]usize,
     vertex: usize, groups: g.Names };
fn overview(grid: g.Grid, agents: []const g.Agent, distances: []const []const i64, independent: g.Plan,
     work_allocator: std.mem.Allocator) Overview {
    var free: usize = 0;
    var degrees: [4]usize = @splat(0);
    var seen: [1024]bool = @splat(false);
    var components: usize = 0;
    for (0..grid.size()) |cell| if (grid.free(cell)) {
        free += 1;
        degrees[@min(grid.degree(cell), 3)] += 1;
        if (seen[cell]) continue;
        components += 1;
        var queue: [1024]usize = undefined;
        queue[0] = cell;
        seen[cell] = true;
        var read: usize = 0;
        var count: usize = 1;
        while (read < count) : (read += 1) {
            const destinations = grid.destinations(queue[read]);
            for (destinations.cells[1..destinations.count]) |next| if (!seen[next]) {
                seen[next] = true;
                queue[count] = next;
                count += 1;
            };
        }
    };
    const shortest = g.alloc(i64, agents.len);
    const mdds = g.alloc(Mdd, agents.len);
    var soc: i64 = 0;
    var makespan: i64 = 0;
    const restrictions = g.zero(ll.Prohibitions, agents.len, .{});
    for (agents, 0..) |agent, id| {
        shortest[id] = distances[id][agent.start];
        const diagram = mdd(grid, agent, distances[id], g.u(shortest[id]), &restrictions[id], work_allocator);
        mdds[id] = .{ .widths = &.{}, .states = diagram.states, .maximum = diagram.maximum };
        work_allocator.free(diagram.widths);
        soc += shortest[id];
        makespan = @max(makespan, shortest[id]);
    }
    const conflicts = c.conflicts(independent);
    var classes: [3]usize = @splat(0);
    var vertex: usize = 0;
    var cache: [20]?[]usize = @splat(null);
    defer for (cache) |widths| {
        if (widths) |values| work_allocator.free(values);
    };
    var adjacent: [20]u32 = @splat(0);
    for (conflicts) |*conflict| {
        conflict.category = conflictClass(conflict.*, independent, restrictions, grid, agents,
             distances, &cache, work_allocator);
        classes[conflict.category] += 1;
        vertex += @intFromBool(!conflict.edge);
        adjacent[conflict.a] |= @as(u32, 1) << @intCast(conflict.b);
        adjacent[conflict.b] |= @as(u32, 1) << @intCast(conflict.a);
    }
    var groups: std.ArrayList([]const u8) = .empty;
    var visited: u32 = 0;
    for (0..agents.len) |start| {
        const bit = @as(u32, 1) << @intCast(start);
        if (visited & bit != 0 or adjacent[start] == 0) continue;
        var group = bit;
        var previous: u32 = 0;
        while (group != previous) {
            previous = group;
            for (0..agents.len) |id| if (group & (@as(u32, 1) << @intCast(id)) != 0) {
                group |= adjacent[id];
            };
        }
        visited |= group;
        var text: g.Text = .{};
        for (0..agents.len) |id| if (group & (@as(u32, 1) << @intCast(id)) != 0) text.add("{c}", .{r.agentName(id)});
        g.append([]const u8, &groups, text.value());
    }
    return .{ .free = free, .degrees = degrees, .components = components, .shortest = shortest,
         .mdds = mdds, .soc = soc, .makespan = makespan, .conflicts = conflicts, .classes = classes,
         .vertex = vertex, .groups = groups.items };
}
const Run = struct { definition: Definition, ok: bool = false, reason: []const u8 = "", paths: g.Plan = &.{},
     high_level: usize = 0, generated: ?usize = null, budget: ll.Budget, specific: g.Lines = .{},
     trace: g.Lines = .{}, ending: []const u8 = "" };
fn solvePp(run: *Run, grid: g.Grid, agents: []const g.Agent, distances: []const []const i64,
     params: Parameters, work_allocator: std.mem.Allocator) void {
    var answer_order: usize = 0;
    for (params.orders, 1..) |order, number| {
        run.high_level += 1;
        const before = run.budget.expansions;
        const result = pp.tryOrder(grid, agents, distances, params.horizon, order, &run.budget, work_allocator);
        for (result.attempts) |attempt| if (attempt.path) |path| {
            run.trace.add("order {d} agent {c} cost {d} expansions {d}", .{ number, r.agentName(attempt.agent),
                 path.len - 1, attempt.expansions });
        } else run.trace.add("order {d} agent {c} failed expansions {d}", .{ number, r.agentName(attempt.agent),
             attempt.expansions });
        if (result.aborted) {
            run.reason = "ll_budget";
            break;
        }
        const names = g.alloc(u8, order.len);
        for (order, names) |id, *name| name.* = r.agentName(id);
        const planned = result.attempts.len - @intFromBool(result.failed != null);
        if (result.paths) |paths| {
            run.specific.add("order {d} {s} planned {d} expansions {d} ok", .{ number, names,
                 planned, run.budget.expansions - before });
            run.ok = true;
            run.paths = paths;
            answer_order = number;
            break;
        } else run.specific.add("order {d} {s} planned {d} expansions {d} failed {c}", .{ number,
             names, planned, run.budget.expansions - before, r.agentName(result.failed.?) });
    }
    if (run.ok) run.ending = g.fmt("end OK order {d}", .{answer_order}) else {
        if (run.reason.len == 0) run.reason = "orders";
        run.ending = g.fmt("end FAIL {s}", .{run.reason});
    }
}
fn applyConstraint(base: []const ll.Prohibitions, addition: c.Constraint) []const ll.Prohibitions {
    const copied = g.dupe(ll.Prohibitions, base);
    copied[addition.agent] = copied[addition.agent].clone();
    const restrictions = &copied[addition.agent];
    if (addition.edge) restrictions.forbidMove(addition.u, addition.v, addition.time) else restrictions.forbidState(addition.u,
         addition.time);
    return copied;
}
fn chooseSplit(node: *const c.Node, improved: bool, grid: g.Grid, agents: []const g.Agent,
     distances: []const []const i64, work_allocator: std.mem.Allocator) c.Conflict {
    if (!improved) return node.conflicts[0];
    var cache: [20]?[]usize = @splat(null);
    defer for (cache) |widths| {
        if (widths) |values| work_allocator.free(values);
    };
    var best = node.conflicts[0];
    best.category = 3;
    for (node.conflicts) |conflict| {
        const category = conflictClass(conflict, node.paths, node.constraints, grid, agents,
             distances, &cache, work_allocator);
        if (category < best.category) {
            best = conflict;
            best.category = category;
        }
    }
    return best;
}
fn orderedConstraints(node: *const c.Node, grid: g.Grid) []const c.Constraint {
    var out: std.ArrayList(c.Constraint) = .empty;
    for (node.constraints, 0..) |*restriction, id| {
        var states = restriction.states.keyIterator();
        while (states.next()) |key| {
            const cell: usize = @intCast(key.* % 1024);
            g.append(c.Constraint, &out, .{ .agent = id, .edge = false, .u = cell, .v = cell,
                 .time = @intCast(key.* / 1024) });
        }
        var moves = restriction.moves.keyIterator();
        while (moves.next()) |key| g.append(c.Constraint, &out, .{ .agent = id, .edge = true,
             .u = @intCast((key.* / 1024) % 1024), .v = @intCast(key.* % 1024), .time = @intCast(key.* / (1024 * 1024)) });
    }
    std.mem.sort(c.Constraint, out.items, grid, struct {
        fn less(context: g.Grid, a: c.Constraint, b: c.Constraint) bool {
            if (a.agent != b.agent) return a.agent < b.agent;
            if (a.time != b.time) return a.time < b.time;
            if (a.edge != b.edge) return !a.edge;
            const ac = [4]usize{ a.u % context.width, a.u / context.width, a.v % context.width, a.v / context.width };
            const bc = [4]usize{ b.u % context.width, b.u / context.width, b.v % context.width, b.v / context.width };
            for (ac, bc) |x, y| if (x != y) return x < y;
            return false;
        }
    }.less);
    return out.items;
}
fn solveCbs(run: *Run, grid: g.Grid, agents: []const g.Agent, distances: []const []const i64,
     params: Parameters, work_allocator: std.mem.Allocator) void {
    const improved = run.definition.solver == .icbs;
    const empty = g.zero(ll.Prohibitions, agents.len, .{});
    const paths = g.alloc(g.Path, agents.len);
    for (agents, 0..) |agent, id| {
        const result = ll.search(grid, agent, distances[id], agent.start, 0, &empty[id], params.horizon,
             &run.budget, false, work_allocator);
        if (result.status == .aborted) {
            run.reason = "ll_budget";
            run.generated = 0;
            run.specific.add("search expanded 0 generated 0 pruned 0 open 0", .{});
            if (improved) run.specific.add("classes cardinal 0 semi_cardinal 0 non_cardinal 0", .{});
            run.ending = "end FAIL ll_budget";
            return;
        }
        paths[id] = result.path;
    }
    var open: c.Heap = .{};
    open.push(c.newNode(paths, empty, 0, 0, null, run.definition.makespan));
    var generated: usize = 1;
    var expanded: usize = 0;
    var pruned: usize = 0;
    var classifications: [3]usize = @splat(0);
    var reason: []const u8 = "exhausted";
    var answer: ?*c.Node = null;
    while (open.items.items.len > 0) {
        const node = open.pop();
        if (node.conflicts.len == 0) {
            answer = node;
            break;
        }
        if (expanded == params.hl_budget) {
            reason = "hl_budget";
            break;
        }
        expanded += 1;
        const conflict = chooseSplit(node, improved, grid, agents, distances, work_allocator);
        if (improved) classifications[conflict.category] += 1;
        var children: [2]?usize = @splat(null);
        var aborted = false;
        for (c.split(conflict), 0..) |branch, side| {
            const restrictions = applyConstraint(node.constraints, branch);
            const id = branch.agent;
            const result = ll.search(grid, agents[id], distances[id], agents[id].start, 0,
                 &restrictions[id], params.horizon, &run.budget, false, work_allocator);
            if (result.status == .aborted) {
                aborted = true;
                break;
            }
            if (result.status == .no_path) {
                pruned += 1;
                continue;
            }
            const new_paths = g.dupe(g.Path, node.paths);
            new_paths[id] = result.path;
            const child = c.newNode(new_paths, restrictions, generated, node.depth + 1, node.number,
                 run.definition.makespan);
            open.push(child);
            children[side] = generated;
            generated += 1;
        }
        if (aborted) {
            reason = "ll_budget";
            break;
        }
        run.trace.add("expand {d} node {d} parent {s} depth {d} cost {d} conflicts {d} split {s}{s} children {s} {s}",
             .{ expanded, node.number, if (node.parent) |parent| g.fmt("{d}", .{parent}) else "-",
             node.depth, node.cost, node.conflicts.len, r.conflictText(conflict, grid), if (improved) g.fmt(" class {s}",
             .{class_names[conflict.category]}) else "", if (children[0]) |child| g.fmt("{d}",
             .{child}) else "-", if (children[1]) |child| g.fmt("{d}", .{child}) else "-" });
    }
    run.high_level = expanded;
    run.generated = generated;
    run.specific.add("search expanded {d} generated {d} pruned {d} open {d}", .{ expanded,
         generated, pruned, open.items.items.len });
    if (improved) run.specific.add("classes cardinal {d} semi_cardinal {d} non_cardinal {d}",
         .{ classifications[0], classifications[1], classifications[2] });
    if (answer) |node| {
        run.ok = true;
        run.paths = node.paths;
        run.specific.add("solution node {d} depth {d}", .{ node.number, node.depth });
        for (orderedConstraints(node, grid)) |constraint| if (constraint.edge) {
            run.specific.add("constraint {c} edge {s} {s} t {d}", .{ r.agentName(constraint.agent),
                 r.cellText(constraint.u, grid), r.cellText(constraint.v, grid), constraint.time });
        } else run.specific.add("constraint {c} vertex {s} t {d}", .{ r.agentName(constraint.agent),
             r.cellText(constraint.u, grid), constraint.time });
        run.ending = g.fmt("end OK node {d} cost {d}", .{ node.number, node.cost });
    } else {
        run.reason = reason;
        run.ending = g.fmt("end FAIL {s}", .{reason});
    }
}
fn solveWhca(run: *Run, grid: g.Grid, agents: []const g.Agent, distances: []const []const i64,
     params: Parameters, work_allocator: std.mem.Allocator) void {
    const current = g.alloc(usize, agents.len);
    const executed = g.zero(std.ArrayList(usize), agents.len, .empty);
    for (agents, 0..) |agent, id| {
        current[id] = agent.start;
        g.append(usize, &executed[id], agent.start);
    }
    var time: usize = 0;
    var rounds: usize = 0;
    while (true) {
        var done = true;
        for (agents, current) |agent, cell| done = done and agent.goal == cell;
        if (done) break;
        if (time >= params.horizon) {
            run.reason = "timeout";
            break;
        }
        rounds += 1;
        var restrictions: ll.Prohibitions = .{};
        var order: [20]usize = undefined;
        var count: usize = 0;
        for ([2]bool{ false, true }) |at_goal| for (agents, current, 0..) |agent, cell, id| if ((agent.goal == cell) == at_goal) {
            order[count] = id;
            count += 1;
        };
        const plans = g.alloc(g.Path, agents.len);
        var failed = false;
        for (order[0..count]) |id| {
            const result = ll.search(grid, agents[id], distances[id], current[id], time, &restrictions,
                 time + params.window, &run.budget, true, work_allocator);
            if (result.status == .aborted) {
                run.reason = "ll_budget";
                failed = true;
                break;
            }
            if (result.status == .no_path) {
                run.trace.add("round {d} time {d} agent {c} blocked expansions {d}", .{ rounds,
                     time, r.agentName(id), result.expansions });
                run.reason = "blocked";
                failed = true;
                break;
            }
            const extended = g.alloc(usize, params.window + 1);
            @memcpy(extended[0..result.path.len], result.path);
            @memset(extended[result.path.len..], result.path[result.path.len - 1]);
            plans[id] = extended;
            run.trace.add("round {d} time {d} agent {c} moves {s} expansions {d}", .{ rounds,
                 time, r.agentName(id), r.actionString(extended, grid), result.expansions });
            restrictions.reserve(extended, time, false);
        }
        if (failed) break;
        for (0..agents.len) |id| {
            for (plans[id][1 .. params.step + 1]) |cell| g.append(usize, &executed[id], cell);
            current[id] = plans[id][params.step];
        }
        time += params.step;
    }
    run.high_level = rounds;
    run.specific.add("window {d} step {d} rounds {d}", .{ params.window, params.step, rounds });
    if (run.reason.len > 0) run.ending = g.fmt("end FAIL {s}", .{run.reason}) else {
        const paths = g.alloc(g.Path, agents.len);
        for (executed, agents, paths) |path, agent, *result| {
            var length = path.items.len;
            while (length > 1 and path.items[length - 1] == agent.goal and path.items[length - 2] == agent.goal) length -= 1;
            result.* = path.items[0..length];
        }
        run.ok = true;
        run.paths = paths;
        run.ending = g.fmt("end OK rounds {d}", .{rounds});
    }
}

const PathStats = struct { cost: usize, extra: i64, waits: usize = 0, turns: usize = 0, arrive: usize = 0,
     leave: usize = 0, actions: []const u8 };
const Metrics = struct { soc: i64, makespan: i64, cost: i64, ratio: []const u8, agents: []const PathStats,
     sum_extra: i64 = 0, max_extra: i64 = 0, waits: usize = 0, turns: usize = 0, arrivals: []const usize,
     traffic: []const usize, cell_waits: []const usize, hotspots: []const usize };
fn planStatistics(paths: g.Plan, agents: []const g.Agent, info: Overview, grid: g.Grid, makespan: bool) Metrics {
    const per_agent = g.alloc(PathStats, agents.len);
    const soc = c.planCost(paths, false);
    const span = c.planCost(paths, true);
    const cost = if (makespan) span else soc;
    const traffic = g.zero(usize, grid.size(), 0);
    const cell_waits = g.zero(usize, grid.size(), 0);
    const arrivals = g.zero(usize, g.u(span) + 1, 0);
    var out: Metrics = .{ .soc = soc, .makespan = span, .cost = cost, .ratio = r.fraction(cost,
         if (makespan) info.makespan else info.soc), .agents = per_agent, .arrivals = arrivals,
         .traffic = traffic, .cell_waits = cell_waits, .hotspots = &.{} };
    for (paths, agents, 0..) |path, agent, id| {
        var stats: PathStats = .{ .cost = path.len - 1, .extra = g.n(path.len - 1) - info.shortest[id],
             .actions = r.actionString(path, grid) };
        var arrived = false;
        var previous: ?u8 = null;
        var visited: [1024]bool = @splat(false);
        for (path, 0..) |cell, time| {
            visited[cell] = true;
            if (!arrived and cell == agent.goal) {
                stats.arrive = time;
                arrived = true;
            }
            if (time == 0) continue;
            const action = r.action(path[time - 1], cell, grid);
            if (action == '.') {
                stats.waits += 1;
                cell_waits[cell] += 1;
            } else {
                if (previous) |direction| stats.turns += @intFromBool(direction != action);
                previous = action;
            }
            stats.leave += @intFromBool(path[time - 1] == agent.goal and cell != agent.goal);
        }
        for (visited[0..grid.size()], traffic) |has, *count| count.* += @intFromBool(has);
        for (arrivals[path.len - 1 ..]) |*count| count.* += 1;
        per_agent[id] = stats;
        out.sum_extra += stats.extra;
        out.max_extra = @max(out.max_extra, stats.extra);
        out.waits += stats.waits;
        out.turns += stats.turns;
    }
    var hotspots: std.ArrayList(usize) = .empty;
    for (traffic, 0..) |count, cell| if (count > 0) g.append(usize, &hotspots, cell);
    std.mem.sort(usize, hotspots.items, traffic, struct {
        fn less(counts: []usize, a: usize, b: usize) bool {
            return if (counts[a] == counts[b]) a < b else counts[a] > counts[b];
        }
    }.less);
    out.hotspots = hotspots.items[0..@min(5, hotspots.items.len)];
    return out;
}
const Validation = struct { start: usize = 0, goal: usize = 0, moves: usize = 0, vertex: usize = 0,
     edge: usize = 0, follows: usize = 0, conflicts: []const c.Conflict = &.{} };
fn validatePlan(paths: g.Plan, agents: []const g.Agent, grid: g.Grid) Validation {
    var out: Validation = .{};
    for (paths, agents) |path, agent| {
        out.start += @intFromBool(path[0] != agent.start);
        out.goal += @intFromBool(path[path.len - 1] != agent.goal);
        for (path[0 .. path.len - 1], path[1..]) |source, destination| {
            const destinations = grid.destinations(source);
            out.moves += @intFromBool(std.mem.indexOfScalar(usize, destinations.cells[0..destinations.count],
                 destination) == null);
        }
    }
    out.conflicts = c.conflicts(paths);
    for (out.conflicts) |conflict| {
        if (conflict.edge) out.edge += 1 else out.vertex += 1;
    }
    const maximum = g.u(c.planCost(paths, true));
    for (1..maximum + 1) |time| for (paths, 0..) |first, a| {
        const past_a = c.position(first, time - 1);
        const next_a = c.position(first, time);
        if (past_a == next_a) continue;
        for (paths, 0..) |second, b| if (a != b and next_a == c.position(second, time - 1) and c.position(second,
             time) != past_a) {
            out.follows += 1;
        };
    };
    return out;
}
fn validationLines(out: *g.Lines, name: []const u8, validation: Validation, grid: g.Grid, baseline: bool) void {
    const valid = validation.start + validation.goal + validation.moves + validation.vertex + validation.edge == 0;
    out.add("plan {s} verdict {s} start {d} goal {d} moves {d} vertex {d} edge {d} follows {d}",
         .{ name, if (valid) "VALID" else "INVALID", validation.start, validation.goal, validation.moves,
         validation.vertex, validation.edge, validation.follows });
    for (validation.conflicts) |conflict| {
        if (baseline) out.add("  {s} {s}", .{ r.conflictText(conflict, grid), class_names[conflict.category] }) else out.add("  {s}",
             .{r.conflictText(conflict, grid)});
    }
}
const Execution = struct { deadlock: ?usize = null, blocked: usize = 0, finish: []const usize = &.{},
     soc: i64 = 0, makespan: i64 = 0 };
const Step = struct { scheduled: usize, cell: usize, required: [20]i64 = @splat(-1) };
fn delayedExecution(paths: g.Plan, params: Parameters) Execution {
    const steps = g.alloc([]Step, paths.len);
    for (paths, steps) |path, *entries| {
        var sequence: std.ArrayList(Step) = .empty;
        g.append(Step, &sequence, .{ .scheduled = 0, .cell = path[0] });
        for (path[1..], 1..) |cell, time| if (cell != path[time - 1]) g.append(Step, &sequence,
             .{ .scheduled = time, .cell = cell });
        entries.* = sequence.items;
    }
    for (steps, 0..) |entries, i| for (entries[1..]) |*step| {
        for (steps, 0..) |other, j| {
            if (i == j) continue;
            for (other, 0..) |earlier, k| if (earlier.cell == step.cell and earlier.scheduled < step.scheduled) {
                step.required[j] = @max(step.required[j], g.n(k));
            };
        }
    };
    const progress = g.zero(usize, paths.len, 0);
    const finish = g.zero(usize, paths.len, 0);
    var holds: usize = 0;
    var time: usize = 0;
    while (true) {
        var done = true;
        for (steps, progress) |entries, position| done = done and position == entries.len - 1;
        if (done) break;
        var advance: [20]bool = @splat(false);
        var advanced: usize = 0;
        var stopped_count: usize = 0;
        for (steps, progress, 0..) |entries, position, id| {
            if (position == entries.len - 1) continue;
            var stopped = false;
            for (params.delays) |delay| stopped = stopped or (delay.agent == id and delay.start <= time and time < delay.start + delay.duration);
            if (stopped) {
                stopped_count += 1;
                continue;
            }
            var allowed = true;
            for (progress, entries[position + 1].required[0..paths.len]) |other, required| allowed = allowed and g.n(other) > required;
            if (allowed) {
                advance[id] = true;
                advanced += 1;
            } else holds += 1;
        }
        if (advanced == 0 and stopped_count == 0) return .{ .deadlock = time, .blocked = holds };
        for (advance[0..paths.len], 0..) |move, id| if (move) {
            progress[id] += 1;
            finish[id] = time + 1;
        };
        time += 1;
    }
    var out: Execution = .{ .blocked = holds, .finish = finish };
    for (finish) |value| {
        out.soc += g.n(value);
        out.makespan = @max(out.makespan, g.n(value));
    }
    return out;
}
fn instanceLines(grid: g.Grid, agents: []const g.Agent, info: Overview) g.Lines {
    var out: g.Lines = .{};
    out.add("instance width {d} height {d} free {d} agents {d}", .{ grid.width, grid.height, info.free, agents.len });
    out.add("map isolated {d} dead_ends {d} corridors {d} junctions {d} components {d}", .{ info.degrees[0],
         info.degrees[1], info.degrees[2], info.degrees[3], info.components });
    for (agents, info.shortest, info.mdds) |agent, shortest, diagram| out.add("agent {c} start {s} goal {s} distance {d} mdd {d} width {d}",
         .{ agent.name, r.cellText(agent.start, grid), r.cellText(agent.goal, grid), shortest,
         diagram.states, diagram.maximum });
    out.add("lower_bound soc {d} makespan {d}", .{ info.soc, info.makespan });
    out.add("independent conflicts {d} vertex {d} edge {d} cardinal {d} semi_cardinal {d} non_cardinal {d}",
         .{ info.conflicts.len, info.vertex, info.conflicts.len - info.vertex, info.classes[0],
         info.classes[1], info.classes[2] });
    out.add("groups {s}", .{if (info.groups.len == 0) "-" else g.join(info.groups, " ")});
    return out;
}
fn solutionBlock(run: Run, grid: g.Grid, metrics: ?Metrics, execution: ?Execution) g.Lines {
    var out: g.Lines = .{};
    const definition = run.definition;
    const solver = solver_names[@intFromEnum(definition.solver)];
    const cost_function = if (definition.makespan) "MAKESPAN" else "SOC";
    if (run.ok) {
        const m = metrics.?;
        out.add("run {s} solver {s} cost_function {s} result OK cost {d} soc {d} makespan {d} ratio {s}",
             .{ definition.name, solver, cost_function, m.cost, m.soc, m.makespan, m.ratio });
    } else out.add("run {s} solver {s} cost_function {s} result FAIL reason {s}", .{ definition.name,
         solver, cost_function, run.reason });
    out.extend(run.specific);
    if (!run.ok) return out;
    const m = metrics.?;
    const e = execution.?;
    for (m.agents, 0..) |agent, id| out.add("agent {c} cost {d} extra {d} waits {d} turns {d} arrive {d} leave {d} moves {s}",
         .{ r.agentName(id), agent.cost, agent.extra, agent.waits, agent.turns, agent.arrive,
         agent.leave, agent.actions });
    var arrivals: g.Text = .{};
    arrivals.add("arrivals", .{});
    for (m.arrivals) |count| arrivals.add(" {d}", .{count});
    out.add("{s}", .{arrivals.value()});
    var hotspots: g.Text = .{};
    hotspots.add("hotspots", .{});
    for (m.hotspots) |cell| hotspots.add(" {s}:{d}", .{ r.cellText(cell, grid), m.traffic[cell] });
    out.add("{s}", .{hotspots.value()});
    if (e.deadlock) |time| out.add("execution deadlock time {d}", .{time}) else {
        var finish: g.Text = .{};
        for (e.finish) |time| finish.add(" {d}", .{time});
        out.add("execution soc {d} makespan {d} blocked {d} finish{s}", .{ e.soc, e.makespan,
             e.blocked, finish.value() });
    }
    return out;
}
fn statsLine(run: Run, metrics: ?Metrics, execution: ?Execution) []const u8 {
    const definition = run.definition;
    var values: std.ArrayList([]const u8) = .empty;
    for ([5][]const u8{ definition.name, solver_names[@intFromEnum(definition.solver)], if (definition.makespan) "MAKESPAN" else "SOC",
         if (run.ok) "OK" else "FAIL", if (run.ok) "-" else run.reason }) |value| g.append([]const u8,
         &values, value);
    if (metrics) |m| {
        for ([7]i64{ m.cost, m.soc, m.makespan, m.sum_extra, m.max_extra, g.n(m.waits), g.n(m.turns) }) |value| g.append([]const u8,
             &values, g.fmt("{d}", .{value}));
        const e = execution.?;
        if (e.deadlock == null) {
            g.append([]const u8, &values, g.fmt("{d}", .{e.soc}));
            g.append([]const u8, &values, g.fmt("{d}", .{e.makespan}));
        } else for (0..2) |_| g.append([]const u8, &values, "-");
    } else for (0..9) |_| g.append([]const u8, &values, "-");
    g.append([]const u8, &values, g.fmt("{d}", .{run.high_level}));
    g.append([]const u8, &values, if (run.generated) |count| g.fmt("{d}", .{count}) else "-");
    g.append([]const u8, &values, g.fmt("{d}", .{run.budget.searches}));
    g.append([]const u8, &values, g.fmt("{d}", .{run.budget.expansions}));
    return r.csvLine(values.items);
}
fn pictureLines(out: *g.Lines, grid: g.Grid, cells: []const u8) void {
    for (0..grid.height) |y| out.add("{s}", .{cells[y * grid.width .. (y + 1) * grid.width]});
}
fn animation(run: Run, grid: g.Grid, agents: []const g.Agent, params: Parameters, metrics: ?Metrics) g.Lines {
    var out: g.Lines = .{};
    if (!run.ok) {
        out.add("run {s} FAIL", .{run.definition.name});
        return out;
    }
    out.add("run {s} frames {d}", .{ run.definition.name, params.frames });
    const cells = g.alloc(u8, grid.size());
    for (0..params.frames) |time| {
        for (grid.rows, 0..) |row, y| @memcpy(cells[y * grid.width .. (y + 1) * grid.width], row);
        for (agents) |agent| cells[agent.goal] = agent.name + 32;
        var done: usize = 0;
        var moving: usize = 0;
        for (run.paths, agents) |path, agent| {
            cells[c.position(path, time)] = agent.name;
            if (time >= path.len - 1) done += 1 else if (time >= 1 and c.position(path, time) != c.position(path,
                 time - 1)) moving += 1;
        }
        out.add("", .{});
        out.add("frame {d} done {d} moving {d} waiting {d}", .{ time, done, moving, agents.len - done - moving });
        pictureLines(&out, grid, cells);
    }
    const m = metrics.?;
    for ([2][]const usize{ m.traffic, m.cell_waits }, [2][]const u8{ "traffic", "waits" }) |counts, name| {
        out.add("", .{});
        out.add("{s}", .{name});
        for (0..grid.size()) |cell| {
            const count = counts[cell];
            cells[cell] = if (!grid.free(cell)) '@' else if (count == 0) '.' else if (count <= 9) '0' + @as(u8,
                 @intCast(count)) else '+';
        }
        pictureLines(&out, grid, cells);
    }
    return out;
}
const Completed = struct { name: []const u8, index: usize, ok: bool, soc: i64 = 0, makespan: i64 = 0 };
fn appendSummary(out: *g.Lines, runs: []const Completed) void {
    var successful: std.ArrayList(Completed) = .empty;
    var best_soc: i64 = std.math.maxInt(i64);
    var best_span: i64 = std.math.maxInt(i64);
    for (runs) |run| if (run.ok) {
        g.append(Completed, &successful, run);
        best_soc = @min(best_soc, run.soc);
        best_span = @min(best_span, run.makespan);
    };
    out.add("", .{});
    out.add("summary ok {d} failed {d}", .{ successful.items.len, runs.len - successful.items.len });
    if (successful.items.len == 0) return;
    var soc_names: g.Text = .{};
    var span_names: g.Text = .{};
    for (successful.items) |run| {
        if (run.soc == best_soc) soc_names.add(" {s}", .{run.name});
        if (run.makespan == best_span) span_names.add(" {s}", .{run.name});
    }
    out.add("best_soc {d}{s}", .{ best_soc, soc_names.value() });
    out.add("best_makespan {d}{s}", .{ best_span, span_names.value() });
    std.mem.sort(Completed, successful.items, {}, struct {
        fn less(_: void, a: Completed, b: Completed) bool {
            if (a.soc != b.soc) return a.soc < b.soc;
            if (a.makespan != b.makespan) return a.makespan < b.makespan;
            return a.index < b.index;
        }
    }.less);
    var ranking: g.Text = .{};
    ranking.add("ranking", .{});
    for (successful.items) |run| ranking.add(" {s}", .{run.name});
    out.add("{s}", .{ranking.value()});
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    g.allocator = arena.allocator();
    const grid = try g.read(init.io);
    const agents = try g.readAgents(init.io, grid);
    const params = try readParameters(init.io, agents.len);
    const distances = g.alloc([]const i64, agents.len);
    for (agents, distances) |agent, *distance| distance.* = grid.distanceTable(agent.goal);
    const baseline = g.alloc(g.Path, agents.len);
    var independent_budget: ll.Budget = .{};
    const unrestricted: ll.Prohibitions = .{};
    for (agents, 0..) |agent, id| baseline[id] = ll.search(grid, agent, distances[id], agent.start,
         0, &unrestricted, params.horizon, &independent_budget, false, init.gpa).path;
    const info = overview(grid, agents, distances, baseline, init.gpa);
    var solutions = instanceLines(grid, agents, info);
    var validation: g.Lines = .{};
    var baseline_validation = validatePlan(baseline, agents, grid);
    baseline_validation.conflicts = info.conflicts;
    validationLines(&validation, "INDEPENDENT", baseline_validation, grid, true);
    var statistics: g.Lines = .{};
    statistics.add("run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions",
         .{});
    var trace: g.Lines = .{};
    var frames: g.Lines = .{};
    const completed = g.alloc(Completed, params.runs.len);
    for (params.runs, 0..) |definition, index| {
        const persistent = g.allocator;
        var work: std.heap.ArenaAllocator = .init(init.gpa);
        defer work.deinit();
        g.allocator = work.allocator();
        var run: Run = .{ .definition = definition, .budget = .{ .limit = params.ll_budget } };
        switch (definition.solver) {
            .pp => solvePp(&run, grid, agents, distances, params, init.gpa),
            .cbs, .icbs => solveCbs(&run, grid, agents, distances, params, init.gpa),
            .whca => solveWhca(&run, grid, agents, distances, params, init.gpa),
        }
        const metrics: ?Metrics = if (run.ok) planStatistics(run.paths, agents, info, grid,
             definition.makespan) else null;
        const execution: ?Execution = if (run.ok) delayedExecution(run.paths, params) else null;
        const block = solutionBlock(run, grid, metrics, execution);
        const stats = statsLine(run, metrics, execution);
        var checked: g.Lines = .{};
        if (run.ok) validationLines(&checked, definition.name, validatePlan(run.paths, agents,
             grid), grid, false) else checked.add("plan {s} verdict NONE", .{definition.name});
        const selected = g.eq(definition.name, params.animate);
        const animated = if (selected) animation(run, grid, agents, params, metrics) else g.Lines{};
        g.allocator = persistent;
        solutions.add("", .{});
        solutions.extend(block);
        statistics.add("{s}", .{stats});
        validation.extend(checked);
        if (index > 0) trace.add("", .{});
        trace.add("run {s}", .{definition.name});
        trace.extend(run.trace);
        trace.add("{s}", .{run.ending});
        if (selected) frames.extend(animated);
        completed[index] = .{ .name = definition.name, .index = index, .ok = run.ok, .soc = if (metrics) |m| m.soc else 0,
             .makespan = if (metrics) |m| m.makespan else 0 };
    }
    appendSummary(&solutions, completed);
    try r.write(init.io, "solutions.txt", solutions);
    try r.write(init.io, "stats.csv", statistics);
    try r.write(init.io, "validation.txt", validation);
    try r.write(init.io, "trace.txt", trace);
    try r.write(init.io, "frames.txt", frames);
}
