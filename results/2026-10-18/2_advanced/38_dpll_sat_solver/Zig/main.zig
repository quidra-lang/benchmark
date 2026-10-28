const std = @import("std");
const c = @import("cnf_io.zig");
const enc = @import("encoders.zig");
const prep = @import("preprocess.zig");
const dpll = @import("dpll.zig");
const report = @import("report.zig");
const Solution = struct {
    reduced: prep.Reduced,
    models: std.ArrayList(c.Model) = .empty,
    stats: dpll.Statistics = .{},
    trace: c.Lines = .{},
    rounds: usize = 0,
    removed: usize = 0,
    stop: []const u8 = "preprocess",
    fn status(self: Solution) []const u8 {
        return if (self.models.items.len > 0) "SAT" else "UNSAT";
    }
};
fn solve(formula: c.Formula, limit: usize) Solution {
    var out: Solution = .{ .reduced = prep.preprocess(formula, limit == 1) };
    out.removed = out.reduced.removedCount();
    if (out.reduced.conflict) return out;
    var clauses: c.Formula = .{ .variables = formula.variables };
    for (out.reduced.clauses.items) |clause| c.append(c.Clause, &clauses.clauses, clause.literals);
    while (out.models.items.len < limit) {
        out.rounds += 1;
        const round = dpll.round(clauses);
        out.stats.add(round.stats);
        if (out.rounds == 1) out.trace = round.events;
        if (!round.sat) {
            out.stop = "all";
            return out;
        }
        const model = c.dupe(i64, round.values);
        var block: std.ArrayList(i64) = .empty;
        for (1..formula.variables + 1) |x| {
            if (out.reduced.fixed[x] >= 0) model[x] = out.reduced.fixed[x] else c.append(i64, &block,
                 if (model[x] == 1) -c.n(x) else c.n(x));
        }
        c.append(c.Model, &out.models, model);
        c.append(c.Clause, &clauses.clauses, block.items);
    }
    out.stop = "limit";
    return out;
}
fn edgeLess(_: void, a: c.Edge, b: c.Edge) bool {
    return if (a.a != b.a) a.a < b.a else a.b < b.b;
}
fn readGraphs(io: std.Io) !std.StringHashMap(c.Graph) {
    var graphs = std.StringHashMap(c.Graph).init(c.allocator);
    const lines = try c.readLines(io, "input/graphs.txt");
    var i: usize = 0;
    while (i < lines.len) : (i += 1) {
        if (lines[i].len == 0 or lines[i][0] == '#') continue;
        const header = c.words(lines[i]);
        const vertices = c.u(c.number(header[2]));
        var graph: c.Graph = .{ .name = header[1], .vertices = vertices, .degrees = c.alloc(usize, vertices + 1) };
        @memset(graph.degrees, 0);
        i += 1;
        while (i < lines.len and !c.eq(lines[i], "END")) : (i += 1) {
            if (graph.error_reason != null) continue;
            const tokens = c.words(lines[i]);
            var reason: ?[]const u8 = null;
            if (tokens.len != 2 or !c.wellNumber(tokens[0]) or !c.wellNumber(tokens[1])) reason = "bad edge line" else {
                const a = c.u(c.number(tokens[0]));
                const b = c.u(c.number(tokens[1]));
                if (a < 1 or a > vertices or b < 1 or b > vertices) reason = "vertex out of range" else if (a == b) reason = "self loop" else {
                    const edge: c.Edge = .{ .a = @min(a, b), .b = @max(a, b) };
                    for (graph.edges.items) |earlier| if (earlier.a == edge.a and earlier.b == edge.b) {
                        reason = "duplicate edge";
                    };
                    if (reason == null) {
                        c.append(c.Edge, &graph.edges, edge);
                        graph.degrees[a] += 1;
                        graph.degrees[b] += 1;
                    }
                }
            }
            if (reason) |why| graph.error_reason = c.fmt("{s} at line {d}", .{ why, i + 1 });
        }
        std.mem.sort(c.Edge, graph.edges.items, {}, edgeLess);
        try graphs.put(graph.name, graph);
    }
    return graphs;
}
fn degreeLess(graph: c.Graph, a: usize, b: usize) bool {
    return if (graph.degrees[a] != graph.degrees[b]) graph.degrees[a] > graph.degrees[b] else a < b;
}
fn greedy(graph: c.Graph) []i64 {
    const order = c.alloc(usize, graph.vertices);
    for (order, 1..) |*vertex, index| vertex.* = index;
    std.mem.sort(usize, order, graph, degreeLess);
    const colors = c.alloc(i64, graph.vertices + 1);
    @memset(colors, 0);
    for (order) |vertex| {
        var used = std.mem.zeroes([31]bool);
        for (graph.edges.items) |edge| {
            if (edge.a == vertex) used[c.u(colors[edge.b])] = true;
            if (edge.b == vertex) used[c.u(colors[edge.a])] = true;
        }
        var color: usize = 1;
        while (used[color]) color += 1;
        colors[vertex] = c.n(color);
    }
    return colors[1..];
}
fn maximum(values: []const i64) i64 {
    var greatest: i64 = 0;
    for (values) |value| greatest = @max(greatest, value);
    return greatest;
}
fn graphLine(graph: c.Graph) []const u8 {
    var degree: usize = 0;
    for (graph.degrees) |value| degree = @max(degree, value);
    return c.fmt("graph vertices={d} edges={d} max_degree={d} greedy={d}", .{ graph.vertices, graph.edges.items.len,
         degree, maximum(greedy(graph)) });
}
const Command = enum { solve, enumerate, core, queens, pigeon, color, chromatic };
const command_names = [_][]const u8{ "SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC" };
const Job = struct { command: Command = .solve, error_reason: ?[]const u8 = null, a: usize = 0, b: usize = 0,
     limit: usize = 1, graph: ?c.Graph = null, formula: c.Formula = .{} };
fn validate(io: std.Io, tokens: []const []const u8, graphs: std.StringHashMap(c.Graph)) !Job {
    var job: Job = .{};
    var known = false;
    for (command_names, 0..) |name, i| if (c.eq(tokens[0], name)) {
        known = true;
        job.command = @enumFromInt(i);
        break;
    };
    if (!known) {
        job.error_reason = c.fmt("unknown command {s}", .{tokens[0]});
        return job;
    }
    const arguments = [_]usize{ 1, 2, 1, 2, 3, 3, 2 };
    if (tokens.len != arguments[@intFromEnum(job.command)] + 1) {
        job.error_reason = "wrong argument count";
        return job;
    }
    const file = job.command == .solve or job.command == .enumerate or job.command == .core;
    const graph = job.command == .color or job.command == .chromatic;
    for (tokens[1..], 1..) |token, i| {
        if (i == 1 and file) {
            var valid = token.len >= 5 and token.len <= 24 and std.mem.endsWith(u8, token, ".cnf");
            if (valid) for (token[0 .. token.len - 4]) |char| {
                if (!((char >= 'a' and char <= 'z') or (char >= '0' and char <= '9') or char == '_')) valid = false;
            };
            if (!valid) {
                job.error_reason = c.fmt("bad file name {s}", .{token});
                return job;
            }
        } else if (i == 1 and graph) {
            if (graphs.get(token)) |found| {
                if (found.error_reason) |reason| job.error_reason = c.fmt("invalid graph {s}: {s}",
                     .{ token, reason }) else job.graph = found;
            } else job.error_reason = c.fmt("unknown graph {s}", .{token});
            if (job.error_reason != null) return job;
        } else {
            if (!c.wellNumber(token)) {
                job.error_reason = c.fmt("bad number {s}", .{token});
                return job;
            }
            const value = c.u(c.number(token));
            const limit = (job.command == .enumerate and i == 2) or (job.command == .queens and i == 2) or ((job.command == .pigeon or job.command == .color) and i == 3);
            const upper: usize = if (limit) 200 else if (graph) 6 else 8;
            if (value < 1 or value > upper) {
                job.error_reason = c.fmt("out of range {s}", .{token});
                return job;
            }
            if (limit) job.limit = value else if (job.command == .pigeon and i == 2) job.b = value else job.a = value;
        }
    }
    if (file) {
        const input = try c.readCnf(io, tokens[1]);
        job.formula = input.formula;
        job.error_reason = input.error_reason;
    } else if (job.command == .queens) job.formula = enc.queens(job.a) else if (job.command == .pigeon) job.formula = enc.pigeon(job.a,
         job.b) else if (job.command == .color) job.formula = enc.color(job.graph.?, job.a);
    return job;
}
fn trueCount(clause: c.Clause, model: c.Model) usize {
    var count: usize = 0;
    for (clause) |literal| if (model[@intCast(@abs(literal))] == @as(i64, @intFromBool(literal > 0))) {
        count += 1;
    };
    return count;
}
fn satisfied(formula: c.Formula, model: c.Model) bool {
    for (formula.clauses.items) |clause| if (trueCount(clause, model) == 0) return false;
    return true;
}
fn analysis(lines: *c.Lines, formula: c.Formula, solution: Solution, extended: bool) void {
    if (solution.models.items.len == 0) return;
    var bad_model: usize = 0;
    var bad_clause: usize = 0;
    for (solution.models.items, 1..) |model, i| {
        for (formula.clauses.items, 1..) |clause, j| if (trueCount(clause, model) == 0) {
            bad_model = i;
            bad_clause = j;
            break;
        };
        if (bad_model != 0) break;
    }
    if (bad_model != 0) lines.add("verify failed model={d} clause={d}", .{ bad_model, bad_clause }) else {
        var counts = std.mem.zeroes([201]i64);
        for (formula.clauses.items) |clause| counts[trueCount(clause, solution.models.items[0])] += 1;
        lines.add("verify ok models={d} clauses={d} true_literals={s}", .{ solution.models.items.len,
             formula.clauses.items.len, report.frequencyList(&counts) });
    }
    const model = c.dupe(i64, solution.models.items[0]);
    var flips: std.ArrayList(i64) = .empty;
    for (1..formula.variables + 1) |x| {
        model[x] = 1 - model[x];
        if (satisfied(formula, model)) c.append(i64, &flips, c.n(x));
        model[x] = 1 - model[x];
    }
    lines.add("flips safe={d} variables={s}", .{ flips.items.len, report.numberList(flips.items) });
    if (extended and solution.models.items.len >= 2) {
        var pairs: usize = 0;
        var minimum: usize = formula.variables;
        var greatest: usize = 0;
        for (solution.models.items, 0..) |a, i| for (solution.models.items[i + 1 ..]) |b| {
            var distance: usize = 0;
            for (a[1..], b[1..]) |x, y| if (x != y) {
                distance += 1;
            };
            pairs += 1;
            minimum = @min(minimum, distance);
            greatest = @max(greatest, distance);
        };
        lines.add("diversity pairs={d} min_distance={d} max_distance={d}", .{ pairs, minimum, greatest });
    }
    if (extended and c.eq(solution.stop, "all")) {
        var backbone: std.ArrayList(i64) = .empty;
        for (1..formula.variables + 1) |x| {
            var same = true;
            for (solution.models.items) |other| if (other[x] != model[x]) {
                same = false;
            };
            if (same) c.append(i64, &backbone, if (model[x] == 1) c.n(x) else -c.n(x));
        }
        lines.add("backbone size={d} literals={s}", .{ backbone.items.len, report.numberList(backbone.items) });
    }
}
fn searchLine(stats: dpll.Statistics) []const u8 {
    return c.fmt("search decisions={d} propagations={d} conflicts={d} max_depth={d}", .{ stats.decisions,
         stats.propagations, stats.conflicts, stats.max_depth });
}
fn coreLine(formula: c.Formula) []const u8 {
    const keep = c.alloc(bool, formula.clauses.items.len);
    @memset(keep, true);
    var tests: dpll.Statistics = .{};
    for (0..keep.len) |i| {
        const saved = c.allocator;
        var arena = std.heap.ArenaAllocator.init(saved);
        c.allocator = arena.allocator();
        var trial: c.Formula = .{ .variables = formula.variables };
        for (formula.clauses.items, 0..) |clause, j| if (keep[j] and j != i) c.append(c.Clause, &trial.clauses, clause);
        const result = solve(trial, 1);
        tests.add(result.stats);
        if (result.models.items.len == 0) keep[i] = false;
        c.allocator = saved;
        arena.deinit();
    }
    var core: std.ArrayList(i64) = .empty;
    for (keep, 1..) |retained, index| if (retained) c.append(i64, &core, c.n(index));
    return c.fmt("core size={d} decisions={d} conflicts={d} clauses={s}", .{ core.items.len, tests.decisions,
         tests.conflicts, report.numberList(core.items) });
}
fn regularResult(lines: *c.Lines, job: Job, solution: Solution) void {
    const formula = job.formula;
    const reduced = solution.reduced;
    if (job.command == .color) lines.add("{s}", .{graphLine(job.graph.?)});
    var lengths = std.mem.zeroes([201]i64);
    var literals: usize = 0;
    for (formula.clauses.items) |clause| {
        lengths[clause.len] += 1;
        literals += clause.len;
    }
    lines.add("formula variables={d} clauses={d} literals={d} lengths={s}", .{ formula.variables,
         formula.clauses.items.len, literals, report.frequencyList(&lengths) });
    lines.add("preprocess pure={s} tautologies={d} duplicate_literals={d} unit_fixed={d} unit_removed={d} subsumed={d} pure_fixed={d} pure_removed={d} removed={d}",
         .{ if (reduced.pure) "on" else "off", reduced.tautologies, reduced.duplicate_literals, reduced.unit_fixed,
         reduced.unit_removed, reduced.subsumed, reduced.pure_fixed, reduced.pure_removed, solution.removed });
    var records: [4][]const u8 = undefined;
    for (reduced.removed, &records) |record, *value| {
        const sorted = c.dupe(i64, record.items);
        std.mem.sort(i64, sorted, {}, std.sort.asc(i64));
        value.* = report.numberList(sorted);
    }
    lines.add("removed_clauses tautology={s} unit={s} subsumed={s} pure={s}", .{ records[0], records[1],
         records[2], records[3] });
    if (reduced.conflict) lines.add("simplified empty_clause={d}", .{reduced.empty_clause}) else {
        @memset(&lengths, 0);
        literals = 0;
        for (reduced.clauses.items) |clause| {
            lengths[clause.literals.len] += 1;
            literals += clause.literals.len;
        }
        var fixed: std.ArrayList(i64) = .empty;
        for (1..formula.variables + 1) |x| if (reduced.fixed[x] >= 0) c.append(i64, &fixed, if (reduced.fixed[x] == 1) c.n(x) else -c.n(x));
        lines.add("simplified clauses={d} literals={d} lengths={s} fixed={d} active={d}", .{ reduced.clauses.items.len,
             literals, report.frequencyList(&lengths), fixed.items.len, formula.variables - fixed.items.len });
        lines.add("fixed literals={s}", .{report.numberList(fixed.items)});
    }
    lines.add("result {s} models={d} rounds={d} stop={s}", .{ solution.status(), solution.models.items.len,
         solution.rounds, solution.stop });
    lines.add("{s}", .{searchLine(solution.stats)});
    if (solution.rounds > 0) {
        var trace: c.Text = .{};
        for (solution.trace.data.items[0..@min(12, solution.trace.data.items.len)], 0..) |event, i| trace.add("{s}{s}",
             .{ if (i == 0) "" else " ", event });
        if (solution.trace.data.items.len > 12) trace.add(" +{d}", .{solution.trace.data.items.len - 12});
        lines.add("trace {s}", .{if (trace.value().len == 0) "-" else trace.value()});
    }
    analysis(lines, formula, solution, true);
    if (job.command == .core and solution.models.items.len == 0) lines.add("{s}", .{coreLine(formula)});
}
const BoardClass = struct { canonical: []const i64, orbit: usize = 0, found: usize = 0, first: usize };
fn sequenceLess(a: []const i64, b: []const i64) bool {
    return std.mem.order(i64, a, b) == .lt;
}
fn queenCanonical(columns: []const i64) struct { canonical: []const i64, orbit: usize } {
    const n = c.n(columns.len);
    var boards: [8][]i64 = undefined;
    for (&boards) |*board| board.* = c.alloc(i64, columns.len);
    for (columns, 1..) |column, row| {
        const r = c.n(row);
        const positions = [8][2]i64{ .{ r, column }, .{ column, n + 1 - r }, .{ n + 1 - r, n + 1 - column },
             .{ n + 1 - column, r }, .{ r, n + 1 - column }, .{ n + 1 - r, column }, .{ column, r },
             .{ n + 1 - column, n + 1 - r } };
        for (positions, boards) |position, board| board[c.u(position[0] - 1)] = position[1];
    }
    var smallest: usize = 0;
    var orbit: usize = 0;
    for (boards, 0..) |board, i| {
        var first = true;
        for (boards[0..i]) |earlier| if (std.mem.eql(i64, board, earlier)) {
            first = false;
        };
        if (first) orbit += 1;
        if (sequenceLess(board, boards[smallest])) smallest = i;
    }
    return .{ .canonical = boards[smallest], .orbit = orbit };
}
fn colorCanonical(colors: []const i64) []i64 {
    var names = std.mem.zeroes([31]i64);
    var count: i64 = 0;
    const out = c.alloc(i64, colors.len);
    for (colors, out) |color, *canonical| {
        if (names[c.u(color)] == 0) {
            count += 1;
            names[c.u(color)] = count;
        }
        canonical.* = names[c.u(color)];
    }
    return out;
}
fn puzzleBoard(index: usize, job: Job, solution: Solution, colors: usize) c.Lines {
    var lines: c.Lines = .{};
    const queens = job.command == .queens;
    const pigeon = job.command == .pigeon;
    if (queens) lines.add("QUEENS job={d} n={d}", .{ index, job.a }) else if (pigeon) lines.add("PIGEON job={d} pigeons={d} holes={d}",
         .{ index, job.a, job.b }) else {
        const graph = job.graph.?;
        lines.add("{s} job={d} graph={s} vertices={d} edges={d} colors={d}", .{ command_names[@intFromEnum(job.command)],
             index, graph.name, graph.vertices, graph.edges.items.len, colors });
        const coloring = greedy(graph);
        lines.add("greedy used={d} colors={s}", .{ maximum(coloring), report.numberList(coloring) });
    }
    var classes: std.ArrayList(BoardClass) = .empty;
    for (solution.models.items, 1..) |model, i| {
        const positions = enc.decode(model, if (queens or pigeon) job.a else job.graph.?.vertices,
             if (queens) job.a else if (pigeon) job.b else colors);
        if (pigeon) {
            var empty: std.ArrayList(i64) = .empty;
            for (1..job.b + 1) |h| if (!c.contains(positions, c.n(h))) c.append(i64, &empty, c.n(h));
            lines.add("assignment {d} holes={s} empty={s}", .{ i, report.numberList(positions), report.numberList(empty.items) });
            continue;
        }
        const canonical = if (queens) queenCanonical(positions) else .{ .canonical = @as([]const i64,
             colorCanonical(positions)), .orbit = @as(usize, 0) };
        var category: usize = 0;
        while (category < classes.items.len and !std.mem.eql(i64, classes.items[category].canonical,
             canonical.canonical)) category += 1;
        const first = category == classes.items.len;
        if (first) c.append(BoardClass, &classes, .{ .canonical = canonical.canonical, .orbit = canonical.orbit, .first = i });
        classes.items[category].found += 1;
        if (queens) {
            lines.add("solution {d} columns={s} class={d}", .{ i, report.numberList(positions), category + 1 });
            if (first) lines.extend(report.boardLines(positions));
        } else {
            const sizes = c.alloc(i64, colors);
            @memset(sizes, 0);
            for (positions) |color| sizes[c.u(color - 1)] += 1;
            var used: usize = 0;
            for (sizes) |size| if (size > 0) {
                used += 1;
            };
            lines.add("coloring {d} colors={s} used={d} sizes={s} class={d}", .{ i, report.numberList(positions),
                 used, report.numberList(sizes), category + 1 });
        }
    }
    for (classes.items, 1..) |category, i| {
        if (queens) lines.add("class {d} orbit={d} found={d} first={d} canonical={s}", .{ i, category.orbit,
             category.found, category.first, report.numberList(category.canonical) }) else lines.add("class {d} found={d} first={d} canonical={s}",
             .{ i, category.found, category.first, report.numberList(category.canonical) });
    }
    if (pigeon) {
        var expected: usize = if (job.a <= job.b) 1 else 0;
        if (expected > 0) for (0..job.a) |i| {
            expected *= job.b - i;
        };
        lines.add("summary assignments={d} stop={s} expected={d}", .{ solution.models.items.len, solution.stop, expected });
    } else lines.add("summary {s}={d} stop={s} classes={d}", .{ if (queens) "solutions" else "colorings",
         solution.models.items.len, solution.stop, classes.items.len });
    return lines;
}
const Record = struct { index: usize, command: Command, sat: bool, stats: dpll.Statistics, variables: usize,
     clauses: usize, removed: usize, models: usize, rounds: usize };
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const graphs = try readGraphs(init.io);
    var results: c.Lines = .{};
    var models: c.Lines = .{};
    var boards: c.Lines = .{};
    var csv: c.Lines = .{};
    csv.add("job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds", .{});
    var records: std.ArrayList(Record) = .empty;
    var index: usize = 0;
    var errors: usize = 0;
    for (try c.readLines(init.io, "input/jobs.txt")) |raw| {
        if (raw.len == 0 or raw[0] == '#') continue;
        index += 1;
        const header = c.fmt("JOB {d} {s}", .{ index, raw });
        var result: c.Lines = .{};
        result.add("{s}", .{header});
        var job = try validate(init.io, c.words(raw), graphs);
        if (job.error_reason) |reason| {
            result.add("error {s}", .{reason});
            report.paragraph(&results, result);
            errors += 1;
            continue;
        }
        var solution: Solution = undefined;
        var colors = job.a;
        if (job.command == .chromatic) {
            result.add("{s}", .{graphLine(job.graph.?)});
            var aggregate: dpll.Statistics = .{};
            var removed: usize = 0;
            var rounds: usize = 0;
            colors = 1;
            while (colors <= job.a) : (colors += 1) {
                job.formula = enc.color(job.graph.?, colors);
                solution = solve(job.formula, 1);
                aggregate.add(solution.stats);
                removed += solution.removed;
                rounds += solution.rounds;
                result.add("attempt k={d} clauses={d} removed={d} result={s} stop={s} decisions={d} propagations={d} conflicts={d} max_depth={d}",
                     .{ colors, job.formula.clauses.items.len, solution.removed, solution.status(),
                     solution.stop, solution.stats.decisions, solution.stats.propagations, solution.stats.conflicts,
                     solution.stats.max_depth });
                if (solution.models.items.len > 0) break;
            }
            colors = @min(colors, job.a);
            result.add("result {s} chromatic={s} attempts={d}", .{ solution.status(), if (solution.models.items.len == 0) "-" else c.fmt("{d}",
                 .{colors}), colors });
            solution.stats = aggregate;
            solution.removed = removed;
            solution.rounds = rounds;
            result.add("{s}", .{searchLine(aggregate)});
            analysis(&result, job.formula, solution, false);
        } else {
            solution = solve(job.formula, job.limit);
            regularResult(&result, job, solution);
        }
        report.paragraph(&results, result);
        if (solution.models.items.len > 0) {
            var entries: c.Lines = .{};
            entries.add("{s}", .{header});
            for (solution.models.items, 1..) |model, i| {
                entries.add("model {d}", .{i});
                entries.extend(c.modelLines(model));
            }
            report.paragraph(&models, entries);
        }
        if (job.command == .queens or job.command == .pigeon or job.command == .color or job.command == .chromatic) report.paragraph(&boards,
             puzzleBoard(index, job, solution, colors));
        const record: Record = .{ .index = index, .command = job.command, .sat = solution.models.items.len > 0,
             .stats = solution.stats, .variables = job.formula.variables, .clauses = job.formula.clauses.items.len,
             .removed = solution.removed, .models = solution.models.items.len, .rounds = solution.rounds };
        c.append(Record, &records, record);
        csv.add("{d},{s},{s},{d},{d},{d},{d},{d},{d},{d},{d},{d}", .{ index, command_names[@intFromEnum(job.command)],
             solution.status(), record.variables, record.clauses, record.removed, record.stats.decisions,
             record.stats.propagations, record.stats.conflicts, record.stats.max_depth, record.models,
             record.rounds });
    }
    var totals: dpll.Statistics = .{};
    var sat: usize = 0;
    var model_total: usize = 0;
    var round_total: usize = 0;
    var removed_total: usize = 0;
    for (records.items) |record| {
        sat += @intFromBool(record.sat);
        totals.add(record.stats);
        model_total += record.models;
        round_total += record.rounds;
        removed_total += record.removed;
    }
    var summary: c.Lines = .{};
    summary.add("SUMMARY jobs={d} sat={d} unsat={d} error={d}", .{ index, sat, records.items.len - sat, errors });
    summary.add("totals models={d} rounds={d} decisions={d} propagations={d} conflicts={d} removed_clauses={d}",
         .{ model_total, round_total, totals.decisions, totals.propagations, totals.conflicts, removed_total });
    for (command_names, 0..) |name, command| {
        var count: usize = 0;
        var command_sat: usize = 0;
        var stats: dpll.Statistics = .{};
        for (records.items) |record| if (@intFromEnum(record.command) == command) {
            count += 1;
            command_sat += @intFromBool(record.sat);
            stats.add(record.stats);
        };
        if (count > 0) summary.add("command {s} jobs={d} sat={d} unsat={d} decisions={d} propagations={d} conflicts={d}",
             .{ name, count, command_sat, count - command_sat, stats.decisions, stats.propagations,
             stats.conflicts });
    }
    if (records.items.len > 0) {
        var hardest = records.items[0];
        var deepest = hardest;
        var busiest = hardest;
        for (records.items) |record| {
            if (record.stats.conflicts > hardest.stats.conflicts) hardest = record;
            if (record.stats.max_depth > deepest.stats.max_depth) deepest = record;
            if (record.stats.propagations > busiest.stats.propagations) busiest = record;
        }
        summary.add("hardest job={d} conflicts={d}", .{ hardest.index, hardest.stats.conflicts });
        summary.add("deepest job={d} max_depth={d}", .{ deepest.index, deepest.stats.max_depth });
        summary.add("busiest job={d} propagations={d}", .{ busiest.index, busiest.stats.propagations });
    }
    report.paragraph(&results, summary);
    try report.write(init.io, "results.txt", results);
    try report.write(init.io, "models.txt", models);
    try report.write(init.io, "boards.txt", boards);
    try report.write(init.io, "stats.csv", csv);
}
