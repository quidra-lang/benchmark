const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const names = [_][]const u8{ "RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY" };
const PolicyKind = enum { FIXED, PASS, BASESTOCK, MINMAX, MOVAVG, SMOOTH, STERMAN };
const Metric = enum { ORDERS, INV, BACK, NET };
const Command = enum { DEMAND, GENERATE, RUN, RESET, SAVE, LOAD, SET, BATCH, CAPACITY, COST, VISIBILITY, SHOCK, STATUS, SETTINGS, WEEK, TABLE, CHAIN, DEMANDS, COSTS, SUMMARY, BALANCE, FILLRATE, BULLWHIP, PEAKS, LEADTIME, PLOT, HISTOGRAM, COMPARE, OPTIMIZE, END };
fn integer(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch unreachable;
}
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn sum(values: []const i64) i64 {
    var total: i64 = 0;
    for (values) |value| total += value;
    return total;
}
fn variation(values: []const i64) i64 {
    var squares: i64 = 0;
    for (values) |v| squares += v * v;
    const total = sum(values);
    return @as(i64, @intCast(values.len)) * squares - total * total;
}
const Policy = struct { kind: PolicyKind, values: [4]i64 = @splat(0), text: []const u8 };
const Initial = struct { inventory: i64, quantity: i64, shipping_delay: usize, order_delay: usize, holding_rate: i64, backlog_rate: i64, policy: Policy };
const Record = struct {
    received: i64 = 0,
    incoming: i64 = 0,
    shipped: i64 = 0,
    before: i64 = 0,
    ontime: i64 = 0,
    inventory: i64 = 0,
    backlog: i64 = 0,
    order: i64 = 0,
    holding_cost: i64 = 0,
    backlog_cost: i64 = 0,
    fn cost(r: Record) i64 {
        return r.holding_cost + r.backlog_cost;
    }
    fn value(r: Record, metric: Metric) i64 {
        return switch (metric) {
            .ORDERS => r.order,
            .INV => r.inventory,
            .BACK => r.backlog,
            .NET => r.inventory - r.backlog,
        };
    }
};
const Stage = struct {
    inventory: i64,
    backlog: i64 = 0,
    shipping: [4]i64,
    orders: [4]i64,
    shipping_delay: usize,
    order_delay: usize,
    policy: Policy,
    expected: i64,
    holding_rate: i64,
    backlog_rate: i64,
    lot: i64 = 1,
    capacity: ?i64 = null,
    records: [104]Record = @splat(.{}),
};
const PlantRecord = struct { incoming: i64 = 0, produced: i64 = 0, backlog: i64 = 0 };
const Simulation = struct {
    week: usize = 0,
    horizon: usize,
    demand: [104]i64,
    visible: bool = false,
    stages: [4]Stage,
    plant_backlog: i64 = 0,
    plant_capacity: ?i64 = null,
    plant_records: [104]PlantRecord = @splat(.{}),
    fn init(initial: [4]Initial, demand: [104]i64, horizon: usize) Simulation {
        var result = Simulation{ .horizon = horizon, .demand = demand, .stages = undefined };
        for (initial, 0..) |cfg, i| result.stages[i] = .{
            .inventory = cfg.inventory,
            .shipping = @splat(cfg.quantity),
            .orders = @splat(cfg.quantity),
            .shipping_delay = cfg.shipping_delay,
            .order_delay = cfg.order_delay,
            .policy = cfg.policy,
            .expected = cfg.quantity * 100,
            .holding_rate = cfg.holding_rate,
            .backlog_rate = cfg.backlog_rate,
        };
        return result;
    }
    fn supply(self: *const Simulation, i: usize) i64 {
        const s = &self.stages[i];
        const upstream = if (i == 3) self.plant_backlog else self.stages[i + 1].backlog;
        return sum(s.orders[0..s.order_delay]) + upstream + sum(s.shipping[0..s.shipping_delay]);
    }
    fn signal(self: *const Simulation, stage: usize, week: usize) i64 {
        return if (self.visible) self.demand[week] else self.stages[stage].records[week].incoming;
    }
    fn pop(pipeline: []i64) i64 {
        const first = pipeline[0];
        for (0..pipeline.len - 1) |i| pipeline[i] = pipeline[i + 1];
        pipeline[pipeline.len - 1] = 0;
        return first;
    }
    fn step(self: *Simulation) void {
        var rows: [4]Record = @splat(.{});
        for (&self.stages, 0..) |*s, i| {
            rows[i].received = pop(s.shipping[0..s.shipping_delay]);
            s.inventory += rows[i].received;
        }
        rows[0].incoming = self.demand[self.week];
        var plant = PlantRecord{};
        for (&self.stages, 0..) |*s, i| {
            const incoming = pop(s.orders[0..s.order_delay]);
            if (i == 3) plant.incoming = incoming else rows[i + 1].incoming = incoming;
        }
        for (&self.stages, 0..) |*s, i| {
            const r = &rows[i];
            r.before = s.backlog;
            const requested = s.backlog + r.incoming;
            r.shipped = @min(s.inventory, requested, s.capacity orelse std.math.maxInt(i64));
            s.inventory -= r.shipped;
            s.backlog = requested - r.shipped;
            r.ontime = @min(@max(0, r.shipped - r.before), r.incoming);
            r.inventory = s.inventory;
            r.backlog = s.backlog;
            if (i > 0) {
                const downstream = &self.stages[i - 1];
                downstream.shipping[downstream.shipping_delay - 1] = r.shipped;
            }
        }
        plant.produced = @min(self.plant_backlog + plant.incoming, self.plant_capacity orelse std.math.maxInt(i64));
        self.plant_backlog += plant.incoming - plant.produced;
        plant.backlog = self.plant_backlog;
        self.stages[3].shipping[self.stages[3].shipping_delay - 1] = plant.produced;
        var supplies: [4]i64 = undefined;
        for (0..4) |i| supplies[i] = self.supply(i);
        for (&self.stages, 0..) |*s, i| {
            const r = &rows[i];
            const position = s.inventory + supplies[i] - s.backlog;
            const demand = if (self.visible) self.demand[self.week] else r.incoming;
            const p = s.policy.values;
            const quantity = switch (s.policy.kind) {
                .FIXED => p[0],
                .PASS => r.incoming,
                .BASESTOCK => @max(0, p[0] - position),
                .MINMAX => if (position <= p[0]) p[1] - position else 0,
                .MOVAVG => blk: {
                    const m = @min(@as(usize, @intCast(p[0])), self.week + 1);
                    var signals = demand;
                    for (self.week + 1 - m..self.week) |u| signals += self.signal(i, u);
                    const forecast = @divFloor(signals, @as(i64, @intCast(m)));
                    break :blk @max(0, p[1] + forecast * @as(i64, @intCast(s.shipping_delay + s.order_delay)) - position);
                },
                .SMOOTH => @max(0, demand + @divFloor(p[1] - position, p[0])),
                .STERMAN => blk: {
                    s.expected = @divFloor(100 * p[0] * demand + (100 - p[0]) * s.expected, 100);
                    const net = s.inventory - s.backlog;
                    break :blk @max(0, @divFloor(100 * s.expected + p[1] * (100 * (p[3] - net) - p[2] * supplies[i]), 10000));
                },
            };
            r.order = @divTrunc(quantity + s.lot - 1, s.lot) * s.lot;
            s.orders[s.order_delay - 1] = r.order;
            r.holding_cost = s.holding_rate * s.inventory;
            r.backlog_cost = s.backlog_rate * s.backlog;
            s.records[self.week] = r.*;
        }
        self.plant_records[self.week] = plant;
        self.week += 1;
    }
    fn costs(self: *const Simulation) [4]i64 {
        var result: [4]i64 = @splat(0);
        for (self.stages, 0..) |s, i| for (s.records[0..self.week]) |r| {
            result[i] += r.cost();
        };
        return result;
    }
    fn values(self: *const Simulation, stage: usize, metric: Metric) [104]i64 {
        var result: [104]i64 = @splat(0);
        for (self.stages[stage].records[0..self.week], 0..) |r, i| result[i] = r.value(metric);
        return result;
    }
};
const Statistics = struct {
    total: i64 = 0,
    minimum: i64 = std.math.maxInt(i64),
    maximum: i64 = std.math.minInt(i64),
    fn of(values: []const i64) Statistics {
        var s: Statistics = .{};
        for (values) |v| {
            s.total += v;
            s.minimum = @min(s.minimum, v);
            s.maximum = @max(s.maximum, v);
        }
        return s;
    }
};
const Range = struct { first: usize, end: usize };
const Game = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    initial: [4]Initial = undefined,
    base: [104]i64 = @splat(0),
    base_horizon: usize = 0,
    sim: Simulation = undefined,
    snapshots: std.StringHashMapUnmanaged(*Simulation) = .empty,
    fn fail(self: *Game, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn decimal(self: *Game, comptime places: usize, numerator: i64, denominator: i64) Allocator.Error![]const u8 {
        if (denominator == 0) return "n/a";
        const scale: i64 = if (places == 2) 100 else 10000;
        const scaled: u64 = @intCast(@divTrunc(numerator * scale, denominator));
        const unit: u64 = @intCast(scale);
        return if (places == 2) std.fmt.allocPrint(self.gpa, "{d}.{d:0>2}", .{ scaled / unit, scaled % unit }) else std.fmt.allocPrint(self.gpa, "{d}.{d:0>4}", .{ scaled / unit, scaled % unit });
    }
    fn money(self: *Game, cents: i64) Allocator.Error![]const u8 {
        return self.decimal(2, cents, 100);
    }
    fn percentage(self: *Game, numerator: i64, denominator: i64) Allocator.Error![]const u8 {
        if (denominator == 0) return "n/a";
        return std.fmt.allocPrint(self.gpa, "{s}%", .{try self.decimal(2, numerator * 100, denominator)});
    }
    fn capacityText(self: *Game, capacity: ?i64) Allocator.Error![]const u8 {
        return if (capacity) |n| std.fmt.allocPrint(self.gpa, "{d}", .{n}) else "OFF";
    }
    fn weekText(self: *Game, week: usize) Allocator.Error![]const u8 {
        return if (week > 0) std.fmt.allocPrint(self.gpa, "{d}", .{week}) else "-";
    }
    fn stage(self: *Game, name: []const u8) Error!usize {
        for (names, 0..) |s, i| if (equal(s, name)) return i;
        return self.fail("unknown stage {s}", .{name});
    }
    fn target(self: *Game, name: []const u8) Error!?usize {
        return if (equal(name, "ALL")) null else try self.stage(name);
    }
    fn metric(self: *Game, name: []const u8) Error!Metric {
        return std.meta.stringToEnum(Metric, name) orelse return self.fail("unknown mode {s}", .{name});
    }
    fn requireWeeks(self: *Game) Error!void {
        if (self.sim.week == 0) return self.fail("no weeks simulated", .{});
    }
    fn range(self: *Game, args: []const []const u8, limit: usize) Error!Range {
        if (args.len == 0) return .{ .first = 0, .end = limit };
        const first: usize = @intCast(integer(args[0]));
        const last: usize = @intCast(integer(args[1]));
        if (first == 0 or first > last or last > limit) return self.fail("bad range {s} {s}", .{ args[0], args[1] });
        return .{ .first = first - 1, .end = last };
    }
    fn policy(self: *Game, args: []const []const u8) Error!Policy {
        const kind = std.meta.stringToEnum(PolicyKind, args[0]) orelse return self.fail("unknown policy {s}", .{args[0]});
        const count: usize = switch (kind) {
            .PASS => 0,
            .FIXED, .BASESTOCK => 1,
            .MINMAX, .MOVAVG, .SMOOTH => 2,
            .STERMAN => 4,
        };
        if (args.len != count + 1) return self.fail("{s} needs {d} parameters", .{ args[0], count });
        var result = Policy{ .kind = kind, .text = try std.mem.join(self.gpa, " ", args) };
        for (args[1..], 0..) |arg, i| result.values[i] = if (kind == .STERMAN and i < 3) integer(arg[0..1]) * 100 + integer(arg[2..]) else integer(arg);
        const p = result.values;
        const valid = switch (kind) {
            .PASS => true,
            .FIXED => p[0] <= 1000,
            .BASESTOCK => p[0] <= 10000,
            .MINMAX => p[0] < p[1] and p[1] <= 10000,
            .MOVAVG => p[0] >= 1 and p[0] <= 52 and p[1] <= 10000,
            .SMOOTH => p[0] >= 1 and p[0] <= 10 and p[1] <= 10000,
            .STERMAN => p[0] <= 100 and p[1] <= 100 and p[2] <= 100 and p[3] <= 10000,
        };
        if (!valid) return self.fail("invalid parameter for {s}", .{args[0]});
        return result;
    }
    fn reset(self: *Game) void {
        self.sim = Simulation.init(self.initial, self.base, self.base_horizon);
    }
    fn setDemand(self: *Game, demand: [104]i64, horizon: usize) Error!void {
        self.base = demand;
        self.base_horizon = horizon;
        self.reset();
        const stats = Statistics.of(demand[0..horizon]);
        try self.out.print("DEMAND weeks {d} total {d} min {d} max {d}\n", .{ horizon, stats.total, stats.minimum, stats.maximum });
    }
    fn trial(self: *Game, policies: [4]Policy) Simulation {
        var result = Simulation.init(self.initial, self.sim.demand, self.sim.horizon);
        result.visible = self.sim.visible;
        result.plant_capacity = self.sim.plant_capacity;
        for (&result.stages, 0..) |*s, i| {
            const current = &self.sim.stages[i];
            s.policy = policies[i];
            s.lot = current.lot;
            s.capacity = current.capacity;
            s.holding_rate = current.holding_rate;
            s.backlog_rate = current.backlog_rate;
        }
        while (result.week < result.horizon) result.step();
        return result;
    }
    fn pipeline(self: *Game, values: []const i64) Error!void {
        for (values, 0..) |value, i| try self.out.print("{s}{d}", .{ if (i == 0) "" else ",", value });
    }
    fn execute(self: *Game, a: []const []const u8) Error!void {
        const op = std.meta.stringToEnum(Command, a[0]) orelse return self.fail("unknown command {s}", .{a[0]});
        const id: []const u8 = if (a.len > 1) a[1] else "";
        const sim = &self.sim;
        const n: i64 = @intCast(sim.week);
        switch (op) {
            .DEMAND => {
                var demand: [104]i64 = @splat(0);
                for (a[1..], 0..) |value, i| demand[i] = integer(value);
                try self.setDemand(demand, a.len - 1);
            },
            .GENERATE => {
                const horizon: usize = @intCast(integer(id));
                var i: usize = 5;
                while (i < a.len) : (i += 3) {
                    const week = integer(a[i + 1]);
                    if (week < 1 or week > @as(i64, @intCast(horizon))) return self.fail("week {s} outside horizon", .{a[i + 1]});
                }
                var demand: [104]i64 = @splat(0);
                var random = integer(a[4]);
                for (0..horizon) |t| {
                    var level = integer(a[2]);
                    i = 5;
                    while (i < a.len) : (i += 3) {
                        const elapsed = @as(i64, @intCast(t + 1)) - integer(a[i + 1]);
                        if (elapsed < 0) continue;
                        const value = integer(a[i + 2]);
                        if (equal(a[i], "STEP")) level += value else if (equal(a[i], "RAMP")) level += value * (elapsed + 1) else if (elapsed == 0) {
                            level += value;
                        }
                    }
                    if (level < 0) return self.fail("negative level at week {d}", .{t + 1});
                    random = @mod(48271 * random, 2147483647);
                    demand[t] = level + @mod(random, integer(a[3]));
                }
                try self.setDemand(demand, horizon);
            },
            .RUN => {
                if (sim.week == sim.horizon) return self.fail("horizon reached at week {d}", .{sim.horizon});
                const first = sim.week;
                const end = @min(sim.horizon, sim.week + @as(usize, @intCast(integer(id))));
                var cost: i64 = 0;
                while (sim.week < end) {
                    sim.step();
                    for (&sim.stages, 0..) |*s, i| {
                        const r = s.records[sim.week - 1];
                        cost += r.cost();
                        if (r.before == 0 and r.backlog > 0) try self.out.print("STOCKOUT {s} week {d} backlog {d}\n", .{ names[i], sim.week, r.backlog });
                        if (r.before > 0 and r.backlog == 0) try self.out.print("RECOVER {s} week {d}\n", .{ names[i], sim.week });
                    }
                }
                try self.out.print("RUN {d}-{d} demand {d} cost {s}\n", .{ first + 1, sim.week, sum(sim.demand[first..sim.week]), try self.money(cost) });
                if (sim.week == sim.horizon) try self.out.print("HORIZON {d}\n", .{sim.horizon});
            },
            .RESET => {
                self.reset();
                try self.out.writeAll("RESET week 0\n");
            },
            .SAVE => {
                const snapshot = try self.gpa.create(Simulation);
                snapshot.* = sim.*;
                try self.snapshots.put(self.gpa, id, snapshot);
                try self.out.print("SAVE {s} week {d}\n", .{ id, sim.week });
            },
            .LOAD => {
                const snapshot = self.snapshots.get(id) orelse return self.fail("no snapshot {s}", .{id});
                sim.* = snapshot.*;
                try self.out.print("LOAD {s} week {d}\n", .{ id, sim.week });
            },
            .SET => {
                const selected = try self.target(id);
                const p = try self.policy(a[2..]);
                for (&sim.stages, 0..) |*s, i| {
                    if (selected != null and selected.? != i) continue;
                    s.policy = p;
                    if (p.kind == .STERMAN) s.expected = 100 * (if (sim.week == 0) self.initial[i].quantity else sim.signal(i, sim.week - 1));
                }
                try self.out.print("SET {s} {s}\n", .{ id, p.text });
            },
            .BATCH, .CAPACITY, .COST => {
                const index = if (op == .CAPACITY and equal(id, "PLANT")) 4 else try self.stage(id);
                if (op == .BATCH) {
                    const lot = integer(a[2]);
                    if (lot < 1 or lot > 100) return self.fail("invalid batch size {s}", .{a[2]});
                    sim.stages[index].lot = lot;
                    try self.out.print("BATCH {s} {d}\n", .{ id, lot });
                } else if (op == .CAPACITY) {
                    const capacity: ?i64 = if (equal(a[2], "OFF")) null else integer(a[2]);
                    if (capacity != null and capacity.? > 10000) return self.fail("invalid capacity {s}", .{a[2]});
                    if (index == 4) sim.plant_capacity = capacity else sim.stages[index].capacity = capacity;
                    try self.out.print("CAPACITY {s} {s}\n", .{ id, a[2] });
                } else {
                    const holding = integer(a[2]);
                    const backlog = integer(a[3]);
                    if (holding > 1000 or backlog > 1000) return self.fail("invalid cost", .{});
                    sim.stages[index].holding_rate = holding;
                    sim.stages[index].backlog_rate = backlog;
                    try self.out.print("COST {s} holding {d} backlog {d}\n", .{ id, holding, backlog });
                }
            },
            .VISIBILITY => {
                if (!equal(id, "ON") and !equal(id, "OFF")) return self.fail("unknown visibility {s}", .{id});
                sim.visible = equal(id, "ON");
                try self.out.print("VISIBILITY {s}\n", .{id});
            },
            .SHOCK => {
                const week: usize = @intCast(integer(id));
                if (week == 0 or week > sim.horizon) return self.fail("week {s} outside horizon", .{id});
                if (week <= sim.week) return self.fail("week {s} already simulated", .{id});
                const old = sim.demand[week - 1];
                sim.demand[week - 1] = integer(a[2]);
                try self.out.print("SHOCK week {d} {d} -> {d}\n", .{ week, old, sim.demand[week - 1] });
            },
            .STATUS => {
                try self.out.print("STATUS week {d} of {d}\n", .{ sim.week, sim.horizon });
                for (&sim.stages, 0..) |*s, i| {
                    try self.out.print("{s} inv {d} back {d} transit ", .{ names[i], s.inventory, s.backlog });
                    try self.pipeline(s.shipping[0..s.shipping_delay]);
                    try self.out.writeAll(" pending ");
                    try self.pipeline(s.orders[0..s.order_delay]);
                    const supply = sim.supply(i);
                    try self.out.print(" supply {d} position {d} policy {s}", .{ supply, s.inventory + supply - s.backlog, s.policy.text });
                    if (s.policy.kind == .STERMAN) try self.out.print(" expect {s}", .{try self.money(s.expected)});
                    try self.out.writeAll("\n");
                }
                try self.out.print("PLANT back {d}\n", .{sim.plant_backlog});
            },
            .SETTINGS => {
                try self.out.writeAll("SETTINGS\n");
                for (&sim.stages, 0..) |*s, i| try self.out.print("{s} holding {d} backlog {d} batch {d} capacity {s} delays {d} {d}\n", .{ names[i], s.holding_rate, s.backlog_rate, s.lot, try self.capacityText(s.capacity), s.shipping_delay, s.order_delay });
                try self.out.print("PLANT capacity {s}\nVISIBILITY {s}\n", .{ try self.capacityText(sim.plant_capacity), if (sim.visible) "ON" else "OFF" });
            },
            .WEEK => {
                try self.requireWeeks();
                const week: usize = @intCast(integer(id));
                if (week == 0 or week > sim.week) return self.fail("bad week {s}", .{id});
                try self.out.print("WEEK {d} demand {d}\n", .{ week, sim.demand[week - 1] });
                for (&sim.stages, 0..) |*s, i| {
                    const r = s.records[week - 1];
                    try self.out.print("{s} recv {d} in {d} ship {d} inv {d} back {d} order {d} cost {s}\n", .{ names[i], r.received, r.incoming, r.shipped, r.inventory, r.backlog, r.order, try self.money(r.cost()) });
                }
                const p = sim.plant_records[week - 1];
                try self.out.print("PLANT in {d} made {d} back {d}\n", .{ p.incoming, p.produced, p.backlog });
            },
            .TABLE => {
                const i = try self.stage(id);
                try self.requireWeeks();
                const r = try self.range(a[2..], sim.week);
                try self.out.print("TABLE {s} {d}-{d}\nweek     in   ship   recv    inv   back  order      cost\n", .{ id, r.first + 1, r.end });
                for (r.first..r.end) |t| {
                    const row = sim.stages[i].records[t];
                    try self.out.print("{d: >4} {d: >6} {d: >6} {d: >6} {d: >6} {d: >6} {d: >6} {s: >9}\n", .{ t + 1, row.incoming, row.shipped, row.received, row.inventory, row.backlog, row.order, try self.money(row.cost()) });
                }
            },
            .CHAIN => {
                try self.requireWeeks();
                const r = try self.range(a[1..], sim.week);
                try self.out.print("CHAIN {d}-{d}\n{s: >4} {s: >6}", .{ r.first + 1, r.end, "week", "demand" });
                for (names) |name| try self.out.print(" {s: >11}", .{name});
                try self.out.writeAll("\n");
                for (r.first..r.end) |t| {
                    try self.out.print("{d: >4} {d: >6}", .{ t + 1, sim.demand[t] });
                    for (&sim.stages) |*s| try self.out.print(" {d: >11}", .{s.records[t].order});
                    try self.out.writeAll("\n");
                }
            },
            .DEMANDS => {
                const r = try self.range(a[1..], sim.horizon);
                const values = sim.demand[r.first..r.end];
                const stats = Statistics.of(values);
                try self.out.print("DEMANDS {d}-{d} total {d} min {d} max {d}\n", .{ r.first + 1, r.end, stats.total, stats.minimum, stats.maximum });
                for (values, 0..) |v, i| try self.out.print("{s}{d}", .{ if (i == 0) "" else " ", v });
                try self.out.writeAll("\n");
            },
            .COSTS => {
                try self.out.print("COSTS week {d}\n", .{sim.week});
                var holding: i64 = 0;
                var backlog: i64 = 0;
                for (&sim.stages, 0..) |*s, i| {
                    var h: i64 = 0;
                    var b: i64 = 0;
                    for (s.records[0..sim.week]) |r| {
                        h += r.holding_cost;
                        b += r.backlog_cost;
                    }
                    holding += h;
                    backlog += b;
                    try self.out.print("{s} holding {s} backlog {s} total {s}\n", .{ names[i], try self.money(h), try self.money(b), try self.money(h + b) });
                }
                try self.out.print("TOTAL holding {s} backlog {s} total {s}\n", .{ try self.money(holding), try self.money(backlog), try self.money(holding + backlog) });
            },
            .SUMMARY => {
                try self.requireWeeks();
                try self.out.print("SUMMARY weeks 1-{d}\n", .{sim.week});
                for (&sim.stages, 0..) |*s, i| {
                    var inv: i64 = 0;
                    var back: i64 = 0;
                    var zero: usize = 0;
                    const values = sim.values(i, .ORDERS);
                    const stats = Statistics.of(values[0..sim.week]);
                    for (s.records[0..sim.week]) |r| {
                        inv += r.inventory;
                        back += r.backlog;
                        if (r.order == 0) zero += 1;
                    }
                    try self.out.print("{s} avg_inv {s} avg_back {s} orders {d} min {d} max {d} zero_weeks {d}\n", .{ names[i], try self.decimal(2, inv, n), try self.decimal(2, back, n), stats.total, stats.minimum, stats.maximum, zero });
                }
            },
            .BALANCE => {
                try self.out.print("BALANCE week {d}\n", .{sim.week});
                var initial: i64 = 0;
                var stock: i64 = 0;
                var transit: i64 = 0;
                var delivered: i64 = 0;
                var produced: i64 = 0;
                for (&sim.stages, 0..) |*s, i| {
                    var received: i64 = 0;
                    var shipped: i64 = 0;
                    for (s.records[0..sim.week]) |r| {
                        received += r.received;
                        shipped += r.shipped;
                    }
                    try self.out.print("{s} start {d} received {d} shipped {d} end {d} owed {d}\n", .{ names[i], self.initial[i].inventory, received, shipped, s.inventory, s.backlog });
                    initial += self.initial[i].inventory + self.initial[i].quantity * @as(i64, @intCast(s.shipping_delay));
                    stock += s.inventory;
                    transit += sum(s.shipping[0..s.shipping_delay]);
                    if (i == 0) delivered = shipped;
                }
                for (sim.plant_records[0..sim.week]) |r| produced += r.produced;
                try self.out.print("SYSTEM initial {d} produced {d} delivered {d} stock {d} transit {d}\n", .{ initial, produced, delivered, stock, transit });
            },
            .FILLRATE => {
                try self.requireWeeks();
                try self.out.print("FILLRATE weeks 1-{d}\n", .{sim.week});
                for (&sim.stages, 0..) |*s, i| {
                    var ontime: i64 = 0;
                    var ordered: i64 = 0;
                    var stockouts: i64 = 0;
                    for (s.records[0..sim.week]) |r| {
                        ontime += r.ontime;
                        ordered += r.incoming;
                        if (r.backlog > 0) stockouts += 1;
                    }
                    try self.out.print("{s} fill {s} ontime {d} ordered {d} stockout_weeks {d} service {s}\n", .{ names[i], try self.percentage(ontime, ordered), ontime, ordered, stockouts, try self.percentage(n - stockouts, n) });
                }
            },
            .BULLWHIP => {
                try self.requireWeeks();
                const demand = Statistics.of(sim.demand[0..sim.week]);
                const demand_variation = variation(sim.demand[0..sim.week]);
                try self.out.print("BULLWHIP weeks 1-{d} demand mean {s} var {s}\n", .{ sim.week, try self.decimal(4, demand.total, n), try self.decimal(4, demand_variation, n * n) });
                var previous = demand_variation;
                for (0..4) |i| {
                    const values = sim.values(i, .ORDERS);
                    const stats = Statistics.of(values[0..sim.week]);
                    const order_variation = variation(values[0..sim.week]);
                    try self.out.print("{s} mean {s} var {s} ratio {s} step {s}\n", .{ names[i], try self.decimal(4, stats.total, n), try self.decimal(4, order_variation, n * n), try self.decimal(4, order_variation, demand_variation), try self.decimal(4, order_variation, previous) });
                    previous = order_variation;
                }
            },
            .PEAKS => {
                try self.requireWeeks();
                try self.out.print("PEAKS weeks 1-{d}\n", .{sim.week});
                for (&sim.stages, 0..) |*s, i| {
                    var max_inv: i64 = 0;
                    var max_back: i64 = 0;
                    var inv_week: usize = 0;
                    var back_week: usize = 0;
                    var streak: usize = 0;
                    var longest: usize = 0;
                    var last: usize = 0;
                    for (s.records[0..sim.week], 0..) |r, t| {
                        if (r.inventory > max_inv) {
                            max_inv = r.inventory;
                            inv_week = t + 1;
                        }
                        if (r.backlog > max_back) {
                            max_back = r.backlog;
                            back_week = t + 1;
                        }
                        streak = if (r.backlog > 0) streak + 1 else 0;
                        if (streak > longest) {
                            longest = streak;
                            last = t + 1;
                        }
                    }
                    try self.out.print("{s} max_inv {d} week {s} max_back {d} week {s} longest_stockout {d}", .{ names[i], max_inv, try self.weekText(inv_week), max_back, try self.weekText(back_week), longest });
                    if (longest > 0) try self.out.print(" weeks {d}-{d}", .{ last - longest + 1, last });
                    try self.out.writeAll("\n");
                }
            },
            .LEADTIME => {
                const i = try self.stage(id);
                try self.requireWeeks();
                const s = &sim.stages[i];
                const nominal = s.shipping_delay + s.order_delay;
                var arrivals: [104]i64 = @splat(0);
                var received = -@as(i64, @intCast(nominal)) * self.initial[i].quantity;
                for (s.records[0..sim.week], 0..) |r, t| {
                    received += r.received;
                    arrivals[t] = received;
                }
                var ordered: i64 = 0;
                var count: usize = 0;
                var completed: usize = 0;
                var minimum: usize = 105;
                var maximum: usize = 0;
                var total: i64 = 0;
                for (s.records[0..sim.week], 0..) |r, t| {
                    ordered += r.order;
                    if (r.order == 0) continue;
                    count += 1;
                    for (t + 1..sim.week) |u| {
                        if (arrivals[u] < ordered) continue;
                        const lead = u - t;
                        minimum = @min(minimum, lead);
                        maximum = @max(maximum, lead);
                        total += @intCast(lead);
                        completed += 1;
                        break;
                    }
                }
                try self.out.print("LEADTIME {s} nominal {d} orders {d} completed {d} open {d}", .{ id, nominal, count, completed, count - completed });
                if (completed == 0) try self.out.writeAll(" min - avg - max -\n") else try self.out.print(" min {d} avg {s} max {d}\n", .{ minimum, try self.decimal(2, total, @intCast(completed)), maximum });
            },
            .PLOT, .HISTOGRAM => {
                const i = try self.stage(id);
                const mode = try self.metric(a[2]);
                var width: i64 = 0;
                if (op == .HISTOGRAM) {
                    width = integer(a[3]);
                    if (width < 1 or width > 100) return self.fail("invalid width {s}", .{a[3]});
                }
                try self.requireWeeks();
                const r = if (op == .PLOT) try self.range(a[3..], sim.week) else Range{ .first = 0, .end = sim.week };
                const all = sim.values(i, mode);
                const values = all[r.first..r.end];
                const stats = Statistics.of(values);
                if (op == .HISTOGRAM) {
                    try self.out.print("HISTOGRAM {s} {s} width {d} weeks 1-{d}\n", .{ id, a[2], width, sim.week });
                    var bin = @divFloor(stats.minimum, width);
                    const last = @divFloor(stats.maximum, width);
                    while (bin <= last) : (bin += 1) {
                        var count: usize = 0;
                        for (values) |v| if (@divFloor(v, width) == bin) {
                            count += 1;
                        };
                        try self.out.print("{d}..{d} {d}", .{ bin * width, bin * width + width - 1, count });
                        if (count > 0) {
                            try self.out.writeAll(" ");
                            try self.out.splatByteAll('*', count);
                        }
                        try self.out.writeAll("\n");
                    }
                } else if (mode == .NET) {
                    try self.out.print("PLOT {s} NET {d}-{d} min {d} max {d}\n", .{ id, r.first + 1, r.end, stats.minimum, stats.maximum });
                    const magnitude = @max(@abs(stats.minimum), @abs(stats.maximum));
                    for (values, r.first..) |v, t| {
                        const bars: usize = if (magnitude == 0) 0 else @intCast(@abs(v) * 25 / magnitude);
                        try self.out.print("{d: >3} ", .{t + 1});
                        try self.out.splatByteAll(' ', if (v < 0) 25 - bars else 25);
                        if (v < 0) try self.out.splatByteAll('-', bars);
                        try self.out.writeAll("|");
                        if (v > 0) try self.out.splatByteAll('+', bars);
                        try self.out.print(" {d}\n", .{v});
                    }
                } else {
                    try self.out.print("PLOT {s} {s} {d}-{d} max {d}\n", .{ id, a[2], r.first + 1, r.end, stats.maximum });
                    for (values, r.first..) |v, t| {
                        const bars: usize = if (stats.maximum == 0) 0 else @intCast(@divTrunc(v * 50, stats.maximum));
                        try self.out.print("{d: >3} |", .{t + 1});
                        try self.out.splatByteAll('#', bars);
                        try self.out.print(" {d}\n", .{v});
                    }
                }
            },
            .COMPARE => {
                const Result = struct { policy: Policy, index: usize, cost: i64, ontime: i64, incoming: i64, variation: i64 };
                var policies: std.ArrayList(Policy) = .empty;
                var start: usize = 1;
                var i: usize = 1;
                while (i <= a.len) : (i += 1) {
                    if (i != a.len and !equal(a[i], "/")) continue;
                    try policies.append(self.gpa, try self.policy(a[start..i]));
                    start = i + 1;
                }
                var results: std.ArrayList(Result) = .empty;
                for (policies.items, 0..) |p, index| {
                    const candidate = self.trial(@splat(p));
                    var ontime: i64 = 0;
                    var incoming: i64 = 0;
                    for (candidate.stages[0].records[0..candidate.week]) |r| {
                        ontime += r.ontime;
                        incoming += r.incoming;
                    }
                    const orders = candidate.values(3, .ORDERS);
                    const costs = candidate.costs();
                    try results.append(self.gpa, .{ .policy = p, .index = index, .cost = sum(&costs), .ontime = ontime, .incoming = incoming, .variation = variation(orders[0..candidate.week]) });
                }
                std.mem.sort(Result, results.items, {}, struct {
                    fn less(_: void, x: Result, y: Result) bool {
                        return if (x.cost != y.cost) x.cost < y.cost else x.index < y.index;
                    }
                }.less);
                const demand_variation = variation(sim.demand[0..sim.horizon]);
                try self.out.print("COMPARE {d} weeks {d}\n", .{ policies.items.len, sim.horizon });
                for (results.items, 0..) |r, rank| try self.out.print("{d} {s} total {s} fill {s} bullwhip {s}\n", .{ rank + 1, r.policy.text, try self.money(r.cost), try self.percentage(r.ontime, r.incoming), try self.decimal(4, r.variation, demand_variation) });
            },
            .OPTIMIZE => {
                const selected = try self.target(id);
                const low = integer(a[2]);
                const high = integer(a[3]);
                if (low > high) return self.fail("bad range {s} {s}", .{ a[2], a[3] });
                if (high - low > 200) return self.fail("range too large", .{});
                var best = low;
                var best_cost: i64 = std.math.maxInt(i64);
                var best_total: i64 = 0;
                var stock = low;
                while (stock <= high) : (stock += 1) {
                    var policies: [4]Policy = undefined;
                    for (0..4) |i| policies[i] = if (selected == null or selected.? == i) .{ .kind = .BASESTOCK, .values = .{ stock, 0, 0, 0 }, .text = "" } else sim.stages[i].policy;
                    const candidate = self.trial(policies);
                    const costs = candidate.costs();
                    const total = sum(&costs);
                    const objective = if (selected) |index| costs[index] else total;
                    if (objective < best_cost) {
                        best = stock;
                        best_cost = objective;
                        best_total = total;
                    }
                }
                try self.out.print("OPTIMIZE {s} BASESTOCK {d} cost {s} total {s}\n", .{ id, best, try self.money(best_cost), try self.money(best_total) });
            },
            .END => {},
        }
    }
};
fn readLine(gpa: Allocator, input: *std.Io.Reader) !?[]const u8 {
    var line: std.Io.Writer.Allocating = .init(gpa);
    defer line.deinit();
    _ = try input.streamDelimiterEnding(&line.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (line.written().len == 0) return null;
    return try line.toOwnedSlice();
}
fn tokenize(gpa: Allocator, line: []const u8) Allocator.Error![]const []const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, line, ' ');
    while (it.next()) |token| try tokens.append(gpa, token);
    return tokens.items;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var game = Game{ .gpa = gpa, .out = &output.interface };
    for (0..4) |i| {
        const a = try tokenize(gpa, (try readLine(gpa, &input.interface)).?);
        game.initial[i] = .{ .inventory = integer(a[1]), .quantity = integer(a[2]), .shipping_delay = @intCast(integer(a[3])), .order_delay = @intCast(integer(a[4])), .holding_rate = integer(a[5]), .backlog_rate = integer(a[6]), .policy = try game.policy(a[7..]) };
    }
    game.reset();
    while (try readLine(gpa, &input.interface)) |line| {
        const a = try tokenize(gpa, line);
        if (equal(a[0], "END")) break;
        game.execute(a) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{game.error_message});
        };
    }
    try output.interface.flush();
}
