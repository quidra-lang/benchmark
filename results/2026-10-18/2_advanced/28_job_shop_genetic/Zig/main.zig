const std = @import("std");
const d = @import("instance.zig");
const Minstd = @import("minstd.zig").Minstd;
const dispatch = @import("dispatch_rules.zig").dispatch;
const genetic = @import("genetic.zig");
const gantt = @import("gantt.zig").gantt;
const rules = [_][]const u8{ "SPT", "LPT", "MWKR", "FIFO" };
const TimeContext = struct { data: *const d.Instance, schedule: d.Schedule };
fn timeOrder(context: TimeContext, a: usize, b: usize) bool {
    const s = context.schedule;
    return if (s.start[a] != s.start[b]) s.start[a] < s.start[b] else context.data.operations[a].job < context.data.operations[b].job;
}
fn chronological(data: *const d.Instance, schedule: d.Schedule) []usize {
    const ids = d.alloc(usize, data.operations.len);
    for (ids, 0..) |*id, index| id.* = index;
    std.mem.sort(usize, ids, TimeContext{ .data = data, .schedule = schedule }, timeOrder);
    return ids;
}
pub fn fromStarts(data: *const d.Instance, starts: []const i64) d.Schedule {
    const count = data.operations.len;
    var schedule: d.Schedule = .{ .start = d.dupe(i64, starts), .finish = d.alloc(i64, count), .previous = d.alloc(?usize,
         count), .next = d.alloc(?usize, count), .order = d.alloc([]usize, data.machines) };
    @memset(schedule.previous, null);
    @memset(schedule.next, null);
    for (data.operations, 0..) |op, id| {
        schedule.finish[id] = starts[id] + op.duration;
        schedule.makespan = @max(schedule.makespan, schedule.finish[id]);
    }
    var sequences: [10]std.ArrayList(usize) = @splat(.empty);
    for (chronological(data, schedule)) |id| {
        const sequence = &sequences[data.operations[id].machine];
        if (sequence.items.len > 0) {
            const previous = sequence.items[sequence.items.len - 1];
            schedule.previous[id] = previous;
            schedule.next[previous] = id;
        }
        d.append(usize, sequence, id);
    }
    for (schedule.order, sequences[0..data.machines]) |*sequence, list| sequence.* = list.items;
    return schedule;
}
fn scheduleOrder(data: *const d.Instance, order: d.Order, inflated: ?usize) d.Schedule {
    const count = data.operations.len;
    var schedule: d.Schedule = .{ .start = d.alloc(i64, count), .finish = d.alloc(i64, count), .previous = d.alloc(?usize,
         count), .next = d.alloc(?usize, count), .order = order };
    @memset(schedule.start, -1);
    @memset(schedule.previous, null);
    @memset(schedule.next, null);
    for (order) |sequence| for (sequence[1..], 1..) |id, index| {
        schedule.previous[id] = sequence[index - 1];
        schedule.next[sequence[index - 1]] = id;
    };
    var remaining = count;
    while (remaining > 0) for (data.operations, 0..) |op, id| {
        if (schedule.start[id] >= 0) continue;
        const a = op.previous;
        const b = schedule.previous[id];
        if ((a != null and schedule.start[a.?] < 0) or (b != null and schedule.start[b.?] < 0)) continue;
        const duration = op.duration + if (inflated != null and op.machine == inflated.?) @divTrunc(op.duration + 9, 10) else 0;
        schedule.start[id] = @max(if (a) |previous| schedule.finish[previous] else 0, if (b) |previous| schedule.finish[previous] else 0);
        schedule.finish[id] = schedule.start[id] + duration;
        schedule.makespan = @max(schedule.makespan, schedule.finish[id]);
        remaining -= 1;
    };
    return schedule;
}
fn chromosome(data: *const d.Instance, schedule: d.Schedule) []usize {
    const ids = chronological(data, schedule);
    const genes = d.alloc(usize, ids.len);
    for (ids, genes) |id, *gene| gene.* = data.operations[id].job;
    return genes;
}
const Params = struct {
    seed: i64,
    population: usize,
    generations: usize,
    tournament: usize,
    elites: usize,
    iterations: usize,
    tenure: usize,
    width: usize,
    cross: [2]i64,
    swap: [2]i64,
    insert: [2]i64,
    checkpoints: []const usize,
    fn read(io: std.Io) !Params {
        const lines = try d.readLines(io, "ga_params.txt");
        var fields: [12][]const []const u8 = undefined;
        for (lines, &fields) |line, *field| field.* = d.split(line, ' ')[1..];
        const checkpoints = d.alloc(usize, fields[8].len);
        for (fields[8], checkpoints) |text, *value| value.* = d.u(d.number(text));
        return .{ .seed = d.number(fields[0][0]), .population = d.u(d.number(fields[1][0])), .generations = d.u(d.number(fields[2][0])),
             .tournament = d.u(d.number(fields[3][0])), .cross = fraction(fields[4][0]), .swap = fraction(fields[5][0]),
             .insert = fraction(fields[6][0]), .elites = d.u(d.number(fields[7][0])), .checkpoints = checkpoints,
             .iterations = d.u(d.number(fields[9][0])), .tenure = d.u(d.number(fields[10][0])), .width = d.u(d.number(fields[11][0])) };
    }
};
fn fraction(text: []const u8) [2]i64 {
    const pair = d.split(text, '/');
    return .{ d.number(pair[0]), d.number(pair[1]) };
}
fn percent(a: i64, b: i64) []const u8 {
    const value = @divTrunc(2000 * a + b, 2 * b);
    return d.fmt("{d}.{d}%", .{ @divTrunc(value, 10), @mod(value, 10) });
}
const Analysis = struct { path: []usize, blocks: []const []const usize, bottleneck: usize, paths: i64,
     slack: []i64, free_slack: []i64 };
fn analyze(data: *const d.Instance, schedule: d.Schedule) Analysis {
    var end: ?usize = null;
    for (data.operations, 0..) |op, id| if (schedule.finish[id] == schedule.makespan and (end == null or op.job < data.operations[end.?].job)) {
        end = id;
    };
    var path: std.ArrayList(usize) = .empty;
    var current = end.?;
    while (true) {
        d.append(usize, &path, current);
        if (schedule.start[current] == 0) break;
        const previous = schedule.previous[current];
        current = if (previous != null and schedule.finish[previous.?] == schedule.start[current]) previous.? else data.operations[current].previous.?;
    }
    std.mem.reverse(usize, path.items);
    var blocks: std.ArrayList([]const usize) = .empty;
    var first: usize = 0;
    var counts: [10]usize = @splat(0);
    for (path.items, 0..) |id, index| {
        counts[data.operations[id].machine] += 1;
        if (index + 1 == path.items.len or data.operations[id].machine != data.operations[path.items[index + 1]].machine) {
            d.append([]const usize, &blocks, path.items[first .. index + 1]);
            first = index + 1;
        }
    }
    var bottleneck: usize = 0;
    for (1..data.machines) |machine| if (counts[machine] > counts[bottleneck]) {
        bottleneck = machine;
    };
    const order = chronological(data, schedule);
    const paths = d.alloc(i64, data.operations.len);
    @memset(paths, 0);
    var total_paths: i64 = 0;
    for (order) |id| {
        if (schedule.start[id] == 0) paths[id] = 1 else {
            if (data.operations[id].previous) |previous| if (schedule.finish[previous] == schedule.start[id]) {
                paths[id] += paths[previous];
            };
            if (schedule.previous[id]) |previous| if (schedule.finish[previous] == schedule.start[id]) {
                paths[id] += paths[previous];
            };
        }
        if (schedule.finish[id] == schedule.makespan) total_paths += paths[id];
    }
    const slack = d.alloc(i64, data.operations.len);
    const free_slack = d.alloc(i64, data.operations.len);
    const latest = d.alloc(i64, data.operations.len);
    var index = order.len;
    while (index > 0) {
        index -= 1;
        const id = order[index];
        var limit = schedule.makespan;
        var free_limit = schedule.makespan;
        if (data.operations[id].next) |next| {
            limit = @min(limit, latest[next]);
            free_limit = @min(free_limit, schedule.start[next]);
        }
        if (schedule.next[id]) |next| {
            limit = @min(limit, latest[next]);
            free_limit = @min(free_limit, schedule.start[next]);
        }
        latest[id] = limit - data.operations[id].duration;
        slack[id] = latest[id] - schedule.start[id];
        free_slack[id] = free_limit - schedule.finish[id];
    }
    return .{ .path = path.items, .blocks = blocks.items, .bottleneck = bottleneck, .paths = total_paths,
         .slack = slack, .free_slack = free_slack };
}
const Move = [2]usize;
fn moves(analysis: Analysis) []Move {
    var result: std.ArrayList(Move) = .empty;
    for (analysis.blocks) |block| for (block[1..], 1..) |id, index| d.append(Move, &result, .{ block[index - 1], id });
    return result.items;
}
fn swapped(data: *const d.Instance, order: d.Order, move: Move) d.Order {
    const result = d.cloneOrder(order);
    const sequence = result[data.operations[move[0]].machine];
    var first: usize = 0;
    var second: usize = 0;
    for (sequence, 0..) |id, index| {
        if (id == move[0]) first = index;
        if (id == move[1]) second = index;
    }
    std.mem.swap(usize, &sequence[first], &sequence[second]);
    return result;
}
const Iteration = struct { number: usize, count: usize, tabu_count: usize, move: Move, tabu: bool, value: i64, best: i64 };
const Search = struct { best: d.Schedule, found: usize = 0, stop: []const u8 = "limit", iterations: []const Iteration = &.{} };
fn tabuSearch(data: *const d.Instance, start: d.Schedule, params: Params) Search {
    var result: Search = .{ .best = start };
    var current = start;
    var tabu = std.AutoHashMap(Move, usize).init(d.allocator);
    var history: std.ArrayList(Iteration) = .empty;
    for (1..params.iterations + 1) |iteration| {
        const list = moves(analyze(data, current));
        if (list.len == 0) {
            result.stop = "no_moves";
            break;
        }
        var selected: ?usize = null;
        var value: i64 = std.math.maxInt(i64);
        var tabu_count: usize = 0;
        var chosen_tabu = false;
        for (list, 0..) |move, index| {
            const candidate = scheduleOrder(data, swapped(data, current.order, move), null).makespan;
            const forbidden = (tabu.get(move) orelse 0) >= iteration;
            if (forbidden) tabu_count += 1;
            if ((!forbidden or candidate < result.best.makespan) and candidate < value) {
                selected = index;
                value = candidate;
                chosen_tabu = forbidden;
            }
        }
        if (selected == null) {
            result.stop = "all_tabu";
            break;
        }
        const move = list[selected.?];
        current = scheduleOrder(data, swapped(data, current.order, move), null);
        tabu.put(.{ move[1], move[0] }, iteration + params.tenure) catch @panic("allocation failed");
        if (value < result.best.makespan) {
            result.best = current;
            result.found = iteration;
        }
        d.append(Iteration, &history, .{ .number = iteration, .count = list.len, .tabu_count = tabu_count,
             .move = move, .tabu = chosen_tabu, .value = value, .best = result.best.makespan });
    }
    result.iterations = history.items;
    return result;
}
const Shift = struct { operation: usize, machine: usize, position: usize, insertion: usize, old_start: i64, new_start: i64 };
fn shiftable(data: *const d.Instance, schedule: d.Schedule) []Shift {
    var result: std.ArrayList(Shift) = .empty;
    for (schedule.order, 0..) |sequence, machine| for (sequence[1..], 1..) |id, position| {
        const ready = if (data.operations[id].previous) |previous| schedule.finish[previous] else 0;
        for (0..position) |gap| {
            const start = @max(ready, if (gap > 0) schedule.finish[sequence[gap - 1]] else 0);
            if (start + data.operations[id].duration <= schedule.start[sequence[gap]]) {
                d.append(Shift, &result, .{ .operation = id, .machine = machine, .position = position,
                     .insertion = gap, .old_start = schedule.start[id], .new_start = start });
                break;
            }
        }
    };
    return result.items;
}
const Activation = struct { schedule: d.Schedule, shifts: []const Shift };
fn activate(data: *const d.Instance, start: d.Schedule) Activation {
    var current = start;
    var history: std.ArrayList(Shift) = .empty;
    while (true) {
        const options = shiftable(data, current);
        if (options.len == 0) break;
        var best: usize = 0;
        for (options, 0..) |shift, index| if (shift.old_start < options[best].old_start or (shift.old_start == options[best].old_start and data.operations[shift.operation].job < data.operations[options[best].operation].job)) {
            best = index;
        };
        const shift = options[best];
        d.append(Shift, &history, shift);
        const order = d.cloneOrder(current.order);
        const sequence = order[shift.machine];
        std.mem.copyBackwards(usize, sequence[shift.insertion + 1 .. shift.position + 1], sequence[shift.insertion..shift.position]);
        sequence[shift.insertion] = shift.operation;
        current = scheduleOrder(data, order, null);
    }
    return .{ .schedule = current, .shifts = history.items };
}
fn distance(data: *const d.Instance, a: d.Schedule, b: d.Schedule) []i64 {
    const result = d.alloc(i64, data.machines);
    @memset(result, 0);
    const positions = d.alloc(usize, data.operations.len);
    for (b.order) |sequence| for (sequence, 0..) |id, index| {
        positions[id] = index;
    };
    for (a.order, 0..) |sequence, machine| for (sequence, 0..) |id, index| for (sequence[index + 1 ..]) |other| if (positions[id] > positions[other]) {
        result[machine] += 1;
    };
    return result;
}
fn sum(values: []const i64) i64 {
    var result: i64 = 0;
    for (values) |value| result += value;
    return result;
}
fn flow(data: *const d.Instance, schedule: d.Schedule) i64 {
    var result: i64 = 0;
    for (data.jobs) |job| result += schedule.finish[job.operations[job.operations.len - 1]];
    return result;
}
fn jackson(data: *const d.Instance, machine: usize) i64 {
    var ids: std.ArrayList(usize) = .empty;
    for (data.operations, 0..) |op, id| if (op.machine == machine) d.append(usize, &ids, id);
    const remaining = d.alloc(i64, ids.items.len);
    for (remaining, ids.items) |*value, id| value.* = data.operations[id].duration;
    var time: i64 = 0;
    var bound: i64 = 0;
    var left = ids.items.len;
    while (left > 0) {
        var selected: ?usize = null;
        var next: i64 = std.math.maxInt(i64);
        for (ids.items, 0..) |id, index| {
            const op = data.operations[id];
            if (op.head > time) next = @min(next, op.head);
            if (remaining[index] > 0 and op.head <= time and (selected == null or op.tail > data.operations[ids.items[selected.?]].tail or (op.tail == data.operations[ids.items[selected.?]].tail and op.job < data.operations[ids.items[selected.?]].job))) selected = index;
        }
        if (selected == null) {
            time = next;
            continue;
        }
        const index = selected.?;
        const amount = @min(remaining[index], if (next == std.math.maxInt(i64)) remaining[index] else next - time);
        time += amount;
        remaining[index] -= amount;
        if (remaining[index] == 0) {
            left -= 1;
            bound = @max(bound, time + data.operations[ids.items[index]].tail);
        }
    }
    return bound;
}
const Record = struct { generation: usize, value: i64, individual: usize };
const GeneticResult = struct { best: d.Schedule, genes: []const usize, records: []const Record, progress: d.Lines,
     population: []const []usize, values: []const i64, rank: []const usize, crossovers: usize, swaps: usize,
     inserts: usize };
fn fitnessOrder(values: []const i64, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] < values[b] else a < b;
}
fn gcd(first: i64, second: i64) i64 {
    var a = first;
    var b = second;
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return a;
}
fn runGenetic(data: *const d.Instance, params: Params, baselines: []const d.Schedule) GeneticResult {
    var random: Minstd = .{ .state = params.seed };
    const basic = d.alloc(usize, data.operations.len);
    var position: usize = 0;
    for (data.jobs) |job| for (job.operations) |_| {
        basic[position] = job.number;
        position += 1;
    };
    var population = d.alloc([]usize, params.population);
    for (baselines, 0..) |schedule, index| population[index] = chromosome(data, schedule);
    for (population[4..]) |*genes| {
        genes.* = d.dupe(usize, basic);
        random.shuffle(genes.*);
    }
    var records: std.ArrayList(Record) = .empty;
    var progress: d.Lines = .{};
    var previous: i64 = std.math.maxInt(i64);
    var crossovers: usize = 0;
    var swaps: usize = 0;
    var inserts: usize = 0;
    for (0..params.generations + 1) |generation| {
        const values = d.alloc(i64, params.population);
        const rank = d.alloc(usize, params.population);
        for (population, values, rank, 0..) |genes, *value, *individual, index| {
            value.* = genetic.decode(data, genes).makespan;
            individual.* = index;
        }
        std.mem.sort(usize, rank, @as([]const i64, values), fitnessOrder);
        const best = rank[0];
        if (values[best] < previous) d.append(Record, &records, .{ .generation = generation, .value = values[best],
             .individual = best + 1 });
        previous = values[best];
        for (params.checkpoints) |checkpoint| if (checkpoint == generation) {
            var distinct: usize = 0;
            var worst: i64 = 0;
            for (population, values, 0..) |genes, value, index| {
                worst = @max(worst, value);
                var first = true;
                for (population[0..index]) |other| if (std.mem.eql(usize, genes, other)) {
                    first = false;
                };
                if (first) distinct += 1;
            }
            const total = sum(values);
            const divisor = gcd(total, d.n(params.population));
            progress.add("{d},{d},{d}/{d},{d},{d}", .{ generation, values[best], @divTrunc(total,
                 divisor), @divTrunc(d.n(params.population), divisor), worst, distinct });
        };
        if (generation == params.generations) return .{ .best = genetic.decode(data, population[best]),
             .genes = population[best], .records = records.items, .progress = progress, .population = population,
             .values = values, .rank = rank, .crossovers = crossovers, .swaps = swaps, .inserts = inserts };
        const next = d.alloc([]usize, params.population);
        for (0..params.elites) |index| next[index] = population[rank[index]];
        position = params.elites;
        while (position < next.len) : (position += 2) {
            const first = genetic.tournament(&random, values, params.tournament);
            const second = genetic.tournament(&random, values, params.tournament);
            var children = [2][]usize{ d.dupe(usize, population[first]), d.dupe(usize, population[second]) };
            if (random.chance(params.cross)) {
                crossovers += 1;
                children = genetic.crossover(&random, data, population[first], population[second]);
            }
            for (children) |child| {
                if (random.chance(params.swap)) {
                    swaps += 1;
                    genetic.swapMutation(&random, child);
                }
                if (random.chance(params.insert)) {
                    inserts += 1;
                    genetic.insertionMutation(&random, child);
                }
            }
            next[position] = children[0];
            next[position + 1] = children[1];
        }
        population = next;
    }
    unreachable;
}
fn genesText(genes: []const usize) []const u8 {
    var text: d.Text = .{};
    for (genes, 0..) |gene, index| text.add("{s}{d}", .{ if (index > 0) " " else "", gene });
    return text.value();
}
fn letters(data: *const d.Instance, sequence: []const usize) []const u8 {
    const text = d.alloc(u8, sequence.len);
    for (sequence, text) |id, *mark| mark.* = 'A' + @as(u8, @intCast(data.operations[id].job - 1));
    return text;
}
const Bounds = struct { job: i64 = 0, job_number: usize = 0, machine: i64 = 0, machine_number: usize = 0,
     jackson: i64 = 0, jackson_machine: usize = 0, lower: i64 = 0, jackson_bounds: []i64 };
fn boundsFor(data: *const d.Instance) Bounds {
    var bounds: Bounds = .{ .jackson_bounds = d.alloc(i64, data.machines) };
    for (data.jobs) |job| if (job.work > bounds.job) {
        bounds.job = job.work;
        bounds.job_number = job.number;
    };
    for (data.machine, 0..) |machine, index| {
        bounds.jackson_bounds[index] = jackson(data, index);
        if (machine.bound > bounds.machine) {
            bounds.machine = machine.bound;
            bounds.machine_number = index + 1;
        }
        if (bounds.jackson_bounds[index] > bounds.jackson) {
            bounds.jackson = bounds.jackson_bounds[index];
            bounds.jackson_machine = index + 1;
        }
    }
    bounds.lower = @max(bounds.job, @max(bounds.machine, bounds.jackson));
    return bounds;
}
fn baselineReport(data: *const d.Instance, baselines: []const d.Schedule, searches: []const Search, bounds: Bounds) d.Lines {
    var out: d.Lines = .{};
    out.add("INSTANCE jobs {d} machines {d} operations {d} work {d} errors {d}", .{ data.jobs.len,
         data.machines, data.operations.len, data.work, data.errors.len });
    for (data.errors) |message| out.add("ERROR {s}", .{message});
    for (data.jobs) |job| {
        var route: d.Text = .{};
        for (job.operations) |id| route.add(" M{d}", .{data.operations[id].machine + 1});
        out.add("JOB J{d} operations {d} work {d} route{s}", .{ job.number, job.operations.len, job.work, route.value() });
    }
    for (data.machine, 1..) |machine, number| out.add("MACHINE M{d} operations {d} load {d} head {d} tail {d} bound {d} jackson {d}",
         .{ number, machine.count, machine.load, machine.head, machine.tail, machine.bound, bounds.jackson_bounds[number - 1] });
    out.add("BOUND job {d} J{d}", .{ bounds.job, bounds.job_number });
    out.add("BOUND machine {d} M{d}", .{ bounds.machine, bounds.machine_number });
    out.add("BOUND jackson {d} M{d}", .{ bounds.jackson, bounds.jackson_machine });
    out.add("BOUND lower {d}", .{bounds.lower});
    var best: usize = 0;
    for (baselines, searches, rules, 0..) |schedule, search, rule, index| {
        const analysis = analyze(data, schedule);
        if (schedule.makespan < baselines[best].makespan) best = index;
        out.add("RULE {s} makespan {d} gap {s} flow {d} idle {d} decisions {d} ties {d}", .{ rule,
             schedule.makespan, percent(schedule.makespan - bounds.lower, bounds.lower), flow(data,
             schedule), d.n(data.machines) * schedule.makespan - data.work, schedule.decisions, schedule.ties });
        out.add("PATH {s} operations {d} blocks {d} critical_paths {d} bottleneck M{d}", .{ rule,
             analysis.path.len, analysis.blocks.len, analysis.paths, analysis.bottleneck + 1 });
        out.add("TABU {s} makespan {d} -> {d} found {d} iterations {d} stop {s}", .{ rule, schedule.makespan,
             search.best.makespan, search.found, search.iterations.len, search.stop });
    }
    out.add("BEST {s} makespan {d}", .{ rules[best], baselines[best].makespan });
    for (data.machine, 1..) |machine, number| {
        var text: d.Text = .{};
        for (baselines, rules) |schedule, rule| text.add(" {s} {s}", .{ rule, percent(machine.load, schedule.makespan) });
        out.add("UTILIZATION M{d}{s}", .{ number, text.value() });
    }
    return out;
}
fn scheduleReport(data: *const d.Instance, params: Params, baselines: []const d.Schedule, ga: GeneticResult,
     active_decode: d.Schedule, activation: Activation, final: d.Schedule, analysis: Analysis, lower: i64) d.Lines {
    var out: d.Lines = .{};
    out.add("GA best {d} generation {d} crossovers {d} swaps {d} inserts {d}", .{ ga.best.makespan,
         ga.records[ga.records.len - 1].generation, ga.crossovers, ga.swaps, ga.inserts });
    for (ga.records) |record| out.add("RECORD generation {d} makespan {d} individual {d}", .{ record.generation,
         record.value, record.individual });
    var seen: std.ArrayList([]const usize) = .empty;
    for (ga.rank) |individual| {
        var distinct = true;
        for (seen.items) |other| if (std.mem.eql(usize, ga.population[individual], other)) {
            distinct = false;
        };
        if (!distinct) continue;
        d.append([]const usize, &seen, ga.population[individual]);
        out.add("TOP {d} individual {d} makespan {d} distance {d}", .{ seen.items.len, individual + 1,
             ga.values[individual], sum(distance(data, genetic.decode(data, ga.population[individual]),
             ga.best)) });
        if (seen.items.len == 5) break;
    }
    out.add("GA_CHROMOSOME {s}", .{genesText(ga.genes)});
    out.add("ACTIVE_DECODE makespan {d} decisions {d}", .{ active_decode.makespan, active_decode.decisions });
    for (activation.shifts, 1..) |shift, number| out.add("SHIFT {d} {s} M{d} start {d} -> {d}", .{ number,
         d.notation(data.operations[shift.operation]), shift.machine + 1, shift.old_start, shift.new_start });
    out.add("ACTIVATED makespan {d} -> {d} shifts {d}", .{ ga.best.makespan, activation.schedule.makespan,
         activation.shifts.len });
    out.add("SCHEDULE makespan {d} lower_bound {d} gap {s} improvement {d} shiftable {d}", .{ final.makespan,
         lower, percent(final.makespan - lower, lower), ga.best.makespan - final.makespan, shiftable(data,
         final).len });
    out.add("CHROMOSOME {s}", .{genesText(chromosome(data, final))});
    var legend: d.Text = .{};
    for (data.jobs) |job| legend.add(" {c}=J{d}", .{ 'A' + @as(u8, @intCast(job.number - 1)), job.number });
    out.add("LEGEND{s}", .{legend.value()});
    const chart = gantt(data, final, analysis.path, params.width);
    out.add("GANTT scale {d} columns {d}", .{ chart.scale, chart.columns });
    for (chart.lines.data.items) |line| out.add("{s}", .{line});
    for (final.order, 1..) |sequence, machine| {
        var text: d.Text = .{};
        for (baselines, rules) |baseline, rule| text.add(" {s} {s}", .{ rule, letters(data, baseline.order[machine - 1]) });
        out.add("ORDER M{d} FINAL {s}{s}", .{ machine, letters(data, sequence), text.value() });
    }
    for (final.order, 0..) |sequence, machine| {
        var gaps: usize = 0;
        var longest: i64 = 0;
        var idle: d.Text = .{};
        var previous: i64 = 0;
        var seq: d.Text = .{};
        for (sequence, 0..) |id, index| {
            if (final.start[id] > previous) {
                idle.add(" {d}-{d}", .{ previous, final.start[id] });
                if (index > 0) {
                    gaps += 1;
                    longest = @max(longest, final.start[id] - previous);
                }
            }
            previous = final.finish[id];
            seq.add(" J{d}:{d}-{d}", .{ data.operations[id].job, final.start[id], final.finish[id] });
        }
        if (previous < final.makespan) idle.add(" {d}-{d}", .{ previous, final.makespan });
        out.add("MACHINE M{d} load {d} idle {d} utilization {s} gaps {d} longest_gap {d} sequence{s}",
             .{ machine + 1, data.machine[machine].load, final.makespan - data.machine[machine].load,
             percent(data.machine[machine].load, final.makespan), gaps, longest, seq.value() });
        out.add("IDLE M{d}{s}", .{ machine + 1, if (idle.value().len == 0) " none" else idle.value() });
    }
    for (data.jobs) |job| {
        const first = job.operations[0];
        const last = job.operations[job.operations.len - 1];
        out.add("JOB J{d} operations {d} work {d} start {d} completion {d} waiting {d}", .{ job.number,
             job.operations.len, job.work, final.start[first], final.finish[last], final.finish[last] - job.work });
    }
    out.add("TOTAL flow {d} waiting {d} idle {d}", .{ flow(data, final), flow(data, final) - data.work,
         d.n(data.machines) * final.makespan - data.work });
    var distances: [5][]i64 = undefined;
    for (baselines, 0..) |baseline, index| distances[index] = distance(data, final, baseline);
    distances[4] = distance(data, final, ga.best);
    var total_pairs: i64 = 0;
    for (data.machine, 0..) |machine, index| {
        const pairs = @divTrunc(d.n(machine.count) * (d.n(machine.count) - 1), 2);
        total_pairs += pairs;
        var text: d.Text = .{};
        for (distances, 0..) |values, r| text.add(" {s} {d}", .{ if (r < 4) rules[r] else "GA", values[index] });
        out.add("DISTANCE M{d} pairs {d}{s}", .{ index + 1, pairs, text.value() });
    }
    var text: d.Text = .{};
    for (distances, 0..) |values, index| text.add(" {s} {d}", .{ if (index < 4) rules[index] else "GA", sum(values) });
    out.add("DISTANCE total pairs {d}{s}", .{ total_pairs, text.value() });
    return out;
}
fn criticalReport(data: *const d.Instance, params: Params, activated: d.Schedule, search: Search, analysis: Analysis) d.Lines {
    var out: d.Lines = .{};
    const final = search.best;
    out.add("SEARCH start {d} iterations {d} tenure {d}", .{ activated.makespan, params.iterations, params.tenure });
    for (search.iterations) |iteration| out.add("ITER {d} moves {d} tabu {d} swap M{d} {s} {s} {s} makespan {d} best {d}",
         .{ iteration.number, iteration.count, iteration.tabu_count, data.operations[iteration.move[0]].machine + 1,
         d.notation(data.operations[iteration.move[0]]), d.notation(data.operations[iteration.move[1]]),
         if (iteration.tabu) "aspiration" else "free", iteration.value, iteration.best });
    out.add("STOP iterations {d} reason {s} best {d} found {d}", .{ search.iterations.len, search.stop,
         final.makespan, search.found });
    out.add("PATH operations {d} blocks {d} makespan {d} critical_paths {d}", .{ analysis.path.len,
         analysis.blocks.len, final.makespan, analysis.paths });
    for (analysis.path, 0..) |id, index| out.add("NODE {d} {s} M{d} {d}-{d} {s}", .{ index + 1, d.notation(data.operations[id]),
         data.operations[id].machine + 1, final.start[id], final.finish[id], if (index == 0) "start" else if (final.previous[id] != null and final.previous[id].? == analysis.path[index - 1]) "machine" else "job" });
    for (analysis.blocks, 1..) |block, number| {
        var text: d.Text = .{};
        for (block) |id| text.add(" {s}", .{d.notation(data.operations[id])});
        out.add("BLOCK {d} M{d} {d}-{d}{s}", .{ number, data.operations[block[0]].machine + 1, final.start[block[0]],
             final.finish[block[block.len - 1]], text.value() });
    }
    for (moves(analysis), 1..) |move, number| out.add("NEIGHBOUR {d} M{d} {s} {s} makespan {d}", .{ number,
         data.operations[move[0]].machine + 1, d.notation(data.operations[move[0]]), d.notation(data.operations[move[1]]),
         scheduleOrder(data, swapped(data, final.order, move), null).makespan });
    var count: usize = 0;
    for (analysis.slack) |slack| if (slack == 0) {
        count += 1;
    };
    out.add("CRITICAL operations {d} total {d}", .{ count, data.operations.len });
    for (data.jobs) |job| {
        var text: d.Text = .{};
        for (job.operations) |id| text.add(" {d}", .{analysis.slack[id]});
        out.add("SLACK J{d}{s}", .{ job.number, text.value() });
    }
    for (data.jobs) |job| {
        var text: d.Text = .{};
        for (job.operations) |id| text.add(" {d}", .{analysis.free_slack[id]});
        out.add("FREE J{d}{s}", .{ job.number, text.value() });
    }
    var bottleneck_count: usize = 0;
    for (final.order, 0..) |sequence, machine| {
        var critical: usize = 0;
        var path_count: usize = 0;
        for (sequence) |id| if (analysis.slack[id] == 0) {
            critical += 1;
        };
        for (analysis.path) |id| if (data.operations[id].machine == machine) {
            path_count += 1;
        };
        const sensitivity = scheduleOrder(data, final.order, machine).makespan;
        out.add("MACHINE M{d} critical {d} path {d} sensitivity {d} delta {d}", .{ machine + 1, critical,
             path_count, sensitivity, sensitivity - final.makespan });
        if (machine == analysis.bottleneck) bottleneck_count = path_count;
    }
    out.add("BOTTLENECK M{d} path {d}", .{ analysis.bottleneck + 1, bottleneck_count });
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const data = try d.read(init.io);
    const params = try Params.read(init.io);
    const bounds = boundsFor(&data);
    var baselines: [4]d.Schedule = undefined;
    var searches: [4]Search = undefined;
    for (rules, &baselines, &searches) |rule, *schedule, *search| {
        schedule.* = dispatch(&data, rule, &.{});
        search.* = tabuSearch(&data, schedule.*, params);
    }
    const ga = runGenetic(&data, params, &baselines);
    const active_decode = dispatch(&data, "GENES", ga.genes);
    const activation = activate(&data, ga.best);
    const search = tabuSearch(&data, activation.schedule, params);
    const analysis = analyze(&data, search.best);
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try d.writeLines(init.io, "baselines.txt", baselineReport(&data, &baselines, &searches, bounds));
    var progress: d.Lines = .{};
    progress.add("generation,best,mean,worst,distinct", .{});
    for (ga.progress.data.items) |line| progress.add("{s}", .{line});
    try d.writeLines(init.io, "ga_progress.csv", progress);
    try d.writeLines(init.io, "best_schedule.txt", scheduleReport(&data, params, &baselines, ga, active_decode,
         activation, search.best, analysis, bounds.lower));
    try d.writeLines(init.io, "critical_path.txt", criticalReport(&data, params, activation.schedule, search, analysis));
}
