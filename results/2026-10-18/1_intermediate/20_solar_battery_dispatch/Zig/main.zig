const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const weekdays = [_][]const u8{ "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN" };
const flow_names = [_][]const u8{ "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL", "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY" };
fn integer(s: []const u8) i64 { return std.fmt.parseInt(i64, s, 10) catch unreachable; }
fn ix(n: i64) usize { return @intCast(n); }
fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn ceilDiv(a: i64, b: i64) i64 { return @divFloor(a + b - 1, b); }
fn money(gpa: Allocator, cents: i64) Allocator.Error![]const u8 {
    const magnitude = @abs(cents);
    return std.fmt.allocPrint(gpa, "{s}{d}.{d:0>2}", .{ if (cents < 0) "-" else "", magnitude / 100, magnitude % 100 });
}
fn percentage(gpa: Allocator, a: i64, b: i64) Allocator.Error![]const u8 {
    const v = if (b == 0) 0 else @divFloor(10000 * a, b);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>2}", .{ @divFloor(v, 100), @mod(v, 100) });
}
fn bar(out: *std.Io.Writer, width: i64) std.Io.Writer.Error!void {
    try out.writeAll("|");
    try out.splatByteAll('#', ix(width));
    try out.splatByteAll('.', ix(20 - width));
    try out.writeAll("|");
}

const Settings = struct {
    capacity: i64, initial: i64, charge: i64, discharge: i64, ceff: i64, deff: i64, reserve: i64, cost: i64,
    export_limit: i64, feedin: i64, fixed: i64, demand: i64, pvscale: i64 = 100,
};
const Item = enum {
    CAPACITY, INITIAL, CHARGE, DISCHARGE, CEFF, DEFF, RESERVE, COST, EXPORT, FEEDIN, FIXED, DEMAND, PVSCALE,
    const fields = [_][]const u8{ "capacity", "initial", "charge", "discharge", "ceff", "deff", "reserve", "cost", "export_limit", "feedin", "fixed", "demand", "pvscale" };
    fn minimum(item: Item) i64 { return switch (item) { .CAPACITY, .CHARGE, .DISCHARGE, .CEFF, .DEFF => 1, else => 0 }; }
    fn maximum(item: Item) i64 {
        return switch (item) { .INITIAL, .CEFF, .DEFF, .RESERVE => 100, .CHARGE, .DISCHARGE => 20000, .FEEDIN => 10000, .PVSCALE => 300, else => 100000 };
    }
    fn get(item: Item, s: Settings) i64 { switch (item) { inline else => |tag| return @field(s, fields[@intFromEnum(tag)]), } }
    fn set(item: Item, s: *Settings, value: i64) void { switch (item) { inline else => |tag| @field(s, fields[@intFromEnum(tag)]) = value, } }
};
const Kind = enum { SELF, TOU, PEAKSHAVE, BACKUP, EXPORTPEAK };
const Strategy = struct {
    kind: Kind,
    parameter: i64 = 0,
    fn hasParameter(s: Strategy) bool { return s.kind == .TOU or s.kind == .PEAKSHAVE or s.kind == .BACKUP; }
    fn text(s: Strategy, gpa: Allocator) Allocator.Error![]const u8 {
        return if (s.hasParameter()) std.fmt.allocPrint(gpa, "{s} {d}", .{ @tagName(s.kind), s.parameter }) else @tagName(s.kind);
    }
};
const HourInput = struct { load: i64, pv: i64, period: usize = 0 };
const Data = struct {
    period_names: []const []const u8,
    hours: []HourInput,
    holiday: []bool,
    fn days(data: Data) usize { return data.holiday.len; }
    fn weekend(data: Data, day: usize) bool { return data.holiday[day] or day % 7 >= 5; }
    fn dayName(data: Data, day: usize) []const u8 { return if (data.holiday[day]) "HOL" else weekdays[day % 7]; }
    fn periodIndex(data: Data, name: []const u8) ?usize {
        for (data.period_names, 0..) |period, i| if (equal(period, name)) return i;
        return null;
    }
    fn extremes(data: Data, prices: [6]i64) struct { low: usize, high: usize } {
        var low: usize = 0;
        var high: usize = 0;
        for (1..data.period_names.len) |i| {
            if (prices[i] < prices[low]) low = i;
            if (prices[i] > prices[high]) high = i;
        }
        return .{ .low = low, .high = high };
    }
};
const Metrics = struct {
    load: i64 = 0, pv: i64 = 0, charge: i64 = 0, discharge: i64 = 0, drawn: i64 = 0, soc: i64 = 0,
    imported: i64 = 0, exported: i64 = 0, curtailed: i64 = 0, shortfall: i64 = 0, loss: i64 = 0,
    import_cost: i64 = 0, export_income: i64 = 0,
    fn add(total: *Metrics, values: Metrics) void {
        inline for (@typeInfo(Metrics).@"struct".field_names) |name| @field(total, name) += @field(values, name);
    }
    fn net(values: Metrics) i64 { return values.import_cost - values.export_income; }
};
const Record = struct { values: Metrics, period: usize, flows: [8]i64 };
const Outage = struct { first: usize, last: usize };
const Result = struct {
    records: []Record,
    settings: Settings,
    prices: [6]i64,
    strategy: Strategy,
    starting: i64,
    reserve: i64,
    total: Metrics = .{},
    periods: [6]Metrics = @splat(.{}),
    period_hours: [6]i64 = @splat(0),
    flows: [8]i64 = @splat(0),
    peak: i64 = 0,
    demand_charge: i64 = 0,
    bill: i64 = 0,
    fn deinit(result: *Result) void { std.heap.page_allocator.free(result.records); }
    fn endSoc(result: Result) i64 { return result.records[result.records.len - 1].values.soc; }
    fn sufficiency(result: Result, gpa: Allocator) Allocator.Error![]const u8 { return percentage(gpa, @max(0, result.total.load - result.total.imported), result.total.load); }
    fn sum(result: Result, first: usize, last: usize) Metrics {
        var total: Metrics = .{};
        for (result.records[first..last]) |record| total.add(record.values);
        return total;
    }
};

fn simulate(data: Data, s: Settings, prices: [6]i64, strategy: Strategy, outage: ?Outage) Allocator.Error!Result {
    const records = try std.heap.page_allocator.alloc(Record, data.hours.len);
    const reserve_pct = if (strategy.kind == .BACKUP) @max(s.reserve, strategy.parameter) else s.reserve;
    const reserve = @divFloor(s.capacity * reserve_pct, 100);
    var soc = @divFloor(s.capacity * s.initial, 100);
    var result: Result = .{ .records = records, .settings = s, .prices = prices, .strategy = strategy, .starting = soc, .reserve = reserve };
    const periods = data.extremes(prices);
    const arbitrage = strategy.kind == .EXPORTPEAK and s.feedin > prices[periods.low];
    for (data.hours, records, 0..) |input, *record, i| {
        const p = input.period;
        const pv = @divFloor(input.pv * s.pvscale, 100);
        const u = @min(input.load, pv);
        var surplus = pv - u;
        var deficit = input.load - u;
        const x1 = @min(surplus, s.charge, ceilDiv(100 * (s.capacity - soc), s.ceff));
        const stored1 = @divFloor(x1 * s.ceff, 100);
        soc += stored1;
        surplus -= x1;
        const off = if (outage) |o| i >= o.first and i <= o.last else false;
        const target = if (off) deficit else switch (strategy.kind) {
            .SELF, .BACKUP => deficit,
            .TOU => if (p == periods.high) deficit else 0,
            .PEAKSHAVE => @max(0, deficit - strategy.parameter),
            .EXPORTPEAK => if (arbitrage and p == periods.low and p != periods.high) 0 else deficit,
        };
        const lower = if (off) 0 else reserve;
        const y1 = @min(ceilDiv(100 * target, s.deff), s.discharge, @max(0, soc - lower));
        const d1 = @divFloor(y1 * s.deff, 100);
        soc -= y1;
        deficit -= d1;
        const g = if (off) 0 else deficit;
        const e1 = if (off) 0 else @min(surplus, s.export_limit);
        var x2: i64 = 0;
        var y2: i64 = 0;
        var d2: i64 = 0;
        if (!off) {
            var headroom = s.charge - x1;
            const charge_target: ?i64 = switch (strategy.kind) {
                .TOU => if (p == periods.low and p != periods.high) @divFloor(s.capacity * strategy.parameter, 100) else null,
                .PEAKSHAVE => if (p == periods.low) blk: {
                    headroom = @min(headroom, @max(0, strategy.parameter - g));
                    break :blk s.capacity;
                } else null,
                .BACKUP => if (p == periods.low) reserve else null,
                .EXPORTPEAK => if (arbitrage and p == periods.low and p != periods.high) s.capacity else null,
                .SELF => null,
            };
            if (charge_target) |v| {
                x2 = @min(headroom, ceilDiv(100 * @max(0, v - soc), s.ceff));
                soc += @divFloor(x2 * s.ceff, 100);
            }
            if (strategy.kind == .EXPORTPEAK and arbitrage and p == periods.high and x1 == 0) {
                y2 = @min(ceilDiv(100 * (s.export_limit - e1), s.deff), s.discharge - y1, @max(0, soc - reserve));
                d2 = @divFloor(y2 * s.deff, 100);
                soc -= y2;
            }
        }
        const curtailed = surplus - e1;
        record.* = .{
            .values = .{ .load = input.load, .pv = pv, .charge = x1 + x2, .discharge = d1 + d2, .drawn = y1 + y2, .soc = soc,
                .imported = g + x2, .exported = e1 + d2, .curtailed = curtailed, .shortfall = if (off) deficit else 0,
                .loss = x1 - stored1 + x2 - @divFloor(x2 * s.ceff, 100) + y1 - d1 + y2 - d2,
                .import_cost = @divFloor((g + x2) * prices[p], 100000), .export_income = @divFloor((e1 + d2) * s.feedin, 100000) },
            .period = p, .flows = .{ u, x1, e1, curtailed, d1, d2, g, x2 },
        };
        result.total.add(record.values);
        result.periods[p].add(record.values);
        result.period_hours[p] += 1;
        result.peak = @max(result.peak, record.values.imported);
        for (&result.flows, record.flows) |*total, flow| total.* += flow;
    }
    result.demand_charge = @divFloor(result.peak * s.demand, 1000);
    result.bill = result.total.net() + s.fixed + result.demand_charge;
    return result;
}
fn baseline(data: Data, settings: Settings, prices: [6]i64) Allocator.Error!Result {
    var s = settings;
    s.capacity = 0;
    return simulate(data, s, prices, .{ .kind = .SELF }, null);
}

const Command = enum { RUN, SET, PRICE, RESET, CONFIG, NOBATTERY, COMPARE, SIZE, SWEEP, OUTAGE, DIFF, HOURLY, DAILY, BILL, SAVINGS, BYPERIOD, DAYTYPE, PEAKS, PROFILE, FLOWS, SELFSUFF, CYCLES, USAGE, HISTOGRAM, CHART, END };
const Comparison = struct {
    strategy: Strategy, bill: i64, load: i64, imported: i64, order: usize,
    fn less(_: void, a: Comparison, b: Comparison) bool { return if (a.bill == b.bill) a.order < b.order else a.bill < b.bill; }
};
const Peak = struct {
    index: usize, imported: i64,
    fn less(_: void, a: Peak, b: Peak) bool { return if (a.imported == b.imported) a.index < b.index else a.imported > b.imported; }
};
const App = struct {
    data: Data,
    settings: Settings,
    prices: [6]i64,
    initial_settings: Settings,
    initial_prices: [6]i64,
    current: ?Result = null,
    error_message: []const u8 = "",

    fn fail(app: *App, gpa: Allocator, comptime format: []const u8, args: anytype) Error {
        app.error_message = std.fmt.allocPrint(gpa, format, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn arity(app: *App, gpa: Allocator, a: []const []const u8, count: usize) Error!void {
        if (a.len != count) return app.fail(gpa, "wrong number of arguments", .{});
    }
    fn dayArgument(app: *App, gpa: Allocator, text: []const u8) Error!usize {
        const day = integer(text);
        if (day < 1 or day > @as(i64, @intCast(app.data.days()))) return app.fail(gpa, "invalid day", .{});
        return ix(day - 1);
    }
    fn itemArgument(app: *App, gpa: Allocator, text: []const u8) Error!Item {
        return std.meta.stringToEnum(Item, text) orelse app.fail(gpa, "unknown parameter {s}", .{text});
    }
    fn range(app: *App, gpa: Allocator, low: i64, high: i64, step: i64, minimum: i64, maximum: i64) Error!void {
        if (low < minimum or high > maximum or high < low or step < 1 or @divFloor(high - low, step) + 1 > 20) return app.fail(gpa, "invalid range", .{});
    }
    fn strategies(app: *App, gpa: Allocator, a: []const []const u8) Error![]Strategy {
        var parsed: std.ArrayList(Strategy) = .empty;
        var i: usize = 0;
        while (i < a.len) {
            const name = a[i];
            i += 1;
            var strategy: Strategy = .{ .kind = std.meta.stringToEnum(Kind, name) orelse return app.fail(gpa, "unknown strategy {s}", .{name}) };
            if (strategy.hasParameter()) {
                if (i == a.len) return app.fail(gpa, "missing parameter for {s}", .{name});
                strategy.parameter = integer(a[i]);
                i += 1;
                const low: i64 = if (strategy.kind == .TOU) 1 else 0;
                const high: i64 = if (strategy.kind == .PEAKSHAVE) 100000 else 100;
                if (strategy.parameter < low or strategy.parameter > high) return app.fail(gpa, "invalid parameter for {s}", .{name});
            }
            try parsed.append(gpa, strategy);
        }
        return parsed.items;
    }
    fn oneStrategy(app: *App, gpa: Allocator, a: []const []const u8) Error!Strategy {
        const parsed = try app.strategies(gpa, a);
        if (parsed.len != 1) return app.fail(gpa, "wrong number of arguments", .{});
        return parsed[0];
    }
    fn result(app: *App, gpa: Allocator) Error!Result {
        return app.current orelse app.fail(gpa, "no run", .{});
    }
    fn config(app: *App, out: *std.Io.Writer) Error!void {
        const s = app.settings;
        const extremes = app.data.extremes(app.prices);
        try out.print("BATTERY capacity {d} initial {d} charge {d} discharge {d} ceff {d} deff {d} reserve {d} cost {d}\nGRID export {d} feedin {d} fixed {d} demand {d}\nSOLAR pvscale {d}\nTARIFF", .{ s.capacity, s.initial, s.charge, s.discharge, s.ceff, s.deff, s.reserve, s.cost, s.export_limit, s.feedin, s.fixed, s.demand, s.pvscale });
        for (app.data.period_names, 0..) |name, p| try out.print(" {s} {d}", .{ name, app.prices[p] });
        try out.print(" cheapest {s} peak {s}\n", .{ app.data.period_names[extremes.low], app.data.period_names[extremes.high] });
    }
    fn execute(app: *App, gpa: Allocator, out: *std.Io.Writer, words: []const []const u8) Error!bool {
        const cmd = std.meta.stringToEnum(Command, words[0]) orelse return app.fail(gpa, "unknown command {s}", .{words[0]});
        const a = words[1..];
        switch (cmd) {
            .END => { try app.arity(gpa, a, 0); return true; },
            .RUN => {
                const strategy = try app.oneStrategy(gpa, a);
                var trial = try simulate(app.data, app.settings, app.prices, strategy, null);
                errdefer trial.deinit();
                try out.print("RUN {s} bill {s} import {d} export {d} soc {d}\n", .{ try strategy.text(gpa), try money(gpa, trial.bill), trial.total.imported, trial.total.exported, trial.endSoc() });
                if (app.current) |*old| old.deinit();
                app.current = trial;
            },
            .SET => {
                try app.arity(gpa, a, 2);
                const item = try app.itemArgument(gpa, a[0]);
                const value = integer(a[1]);
                if (value < item.minimum() or value > item.maximum()) return app.fail(gpa, "invalid value for {s}", .{a[0]});
                const old = item.get(app.settings);
                item.set(&app.settings, value);
                try out.print("SET {s} {d} -> {d}\n", .{ a[0], old, value });
            },
            .PRICE => {
                try app.arity(gpa, a, 2);
                const p = app.data.periodIndex(a[0]) orelse return app.fail(gpa, "unknown period {s}", .{a[0]});
                const value = integer(a[1]);
                if (value < 0 or value > 10000) return app.fail(gpa, "invalid value for {s}", .{a[0]});
                const old = app.prices[p];
                app.prices[p] = value;
                const extremes = app.data.extremes(app.prices);
                try out.print("PRICE {s} {d} -> {d} cheapest {s} peak {s}\n", .{ a[0], old, value, app.data.period_names[extremes.low], app.data.period_names[extremes.high] });
            },
            .RESET => {
                try app.arity(gpa, a, 0);
                app.settings = app.initial_settings;
                app.prices = app.initial_prices;
                try out.writeAll("RESET\n");
            },
            .CONFIG => { try app.arity(gpa, a, 0); try app.config(out); },
            .NOBATTERY => {
                try app.arity(gpa, a, 0);
                var base = try baseline(app.data, app.settings, app.prices);
                defer base.deinit();
                try out.print("NOBATTERY bill {s} import {d} export {d} curtailed {d} peak {d}\n", .{ try money(gpa, base.bill), base.total.imported, base.total.exported, base.total.curtailed, base.peak });
            },
            .COMPARE => {
                const parsed = try app.strategies(gpa, a);
                if (parsed.len == 0) return app.fail(gpa, "wrong number of arguments", .{});
                var base = try baseline(app.data, app.settings, app.prices);
                defer base.deinit();
                var rows: std.ArrayList(Comparison) = .empty;
                for (parsed, 0..) |strategy, order| {
                    var trial = try simulate(app.data, app.settings, app.prices, strategy, null);
                    defer trial.deinit();
                    try rows.append(gpa, .{ .strategy = strategy, .bill = trial.bill, .load = trial.total.load, .imported = trial.total.imported, .order = order });
                }
                std.mem.sort(Comparison, rows.items, {}, Comparison.less);
                try out.print("COMPARE baseline {s}\n", .{try money(gpa, base.bill)});
                for (rows.items, 1..) |row, rank| try out.print("{d}. {s} bill {s} saving {s} sufficiency {s}%\n", .{ rank, try row.strategy.text(gpa), try money(gpa, row.bill), try money(gpa, base.bill - row.bill), try percentage(gpa, @max(0, row.load - row.imported), row.load) });
            },
            .SIZE => {
                try app.arity(gpa, a, 3);
                const low = integer(a[0]);
                const high = integer(a[1]);
                const step = integer(a[2]);
                try app.range(gpa, low, high, step, 1, 100000);
                var base = try baseline(app.data, app.settings, app.prices);
                defer base.deinit();
                var best: ?struct { capacity: i64, cost: i64, saving: i64 } = null;
                var capacity = low;
                while (capacity <= high) : (capacity += step) {
                    var s = app.settings;
                    s.capacity = capacity;
                    var trial = try simulate(app.data, s, app.prices, .{ .kind = .SELF }, null);
                    defer trial.deinit();
                    const saving = base.bill - trial.bill;
                    const cost = @divFloor(capacity * s.cost, 1000);
                    try out.print("SIZE {d} bill {s} saving {s} cost {s} payback ", .{ capacity, try money(gpa, trial.bill), try money(gpa, saving), try money(gpa, cost) });
                    if (saving > 0) {
                        const w = @divFloor(10 * cost, saving);
                        try out.print("{d}.{d}\n", .{ @divFloor(w, 10), @mod(w, 10) });
                        if (best == null or cost * best.?.saving < best.?.cost * saving) best = .{ .capacity = capacity, .cost = cost, .saving = saving };
                    } else try out.writeAll("never\n");
                }
                if (best) |b| try out.print("BEST {d}\n", .{b.capacity}) else try out.writeAll("BEST none\n");
            },
            .SWEEP => {
                if (a.len < 5) return app.fail(gpa, "wrong number of arguments", .{});
                const item = try app.itemArgument(gpa, a[0]);
                const low = integer(a[1]);
                const high = integer(a[2]);
                const step = integer(a[3]);
                try app.range(gpa, low, high, step, item.minimum(), item.maximum());
                const strategy = try app.oneStrategy(gpa, a[4..]);
                var best: ?struct { value: i64, bill: i64 } = null;
                var value = low;
                while (value <= high) : (value += step) {
                    var s = app.settings;
                    item.set(&s, value);
                    var trial = try simulate(app.data, s, app.prices, strategy, null);
                    defer trial.deinit();
                    var base = try baseline(app.data, s, app.prices);
                    defer base.deinit();
                    try out.print("SWEEP {s} {d} bill {s} saving {s} sufficiency {s}%\n", .{ a[0], value, try money(gpa, trial.bill), try money(gpa, base.bill - trial.bill), try trial.sufficiency(gpa) });
                    if (best == null or trial.bill < best.?.bill) best = .{ .value = value, .bill = trial.bill };
                }
                try out.print("BEST {d}\n", .{best.?.value});
            },
            .OUTAGE => {
                try app.arity(gpa, a, 3);
                const day = try app.dayArgument(gpa, a[0]);
                const start = integer(a[1]);
                const end = integer(a[2]);
                if (start < 0 or start > end or end > 23) return app.fail(gpa, "invalid hours", .{});
                const r = try app.result(gpa);
                const first = day * 24 + ix(start);
                const last = day * 24 + ix(end);
                var trial = try simulate(app.data, r.settings, r.prices, r.strategy, .{ .first = first, .last = last });
                defer trial.deinit();
                const before = if (first == 0) trial.starting else trial.records[first - 1].values.soc;
                try out.print("OUTAGE day {d} hours {d}-{d} strategy {s} soc {d}\nhour   load     pv  disch    soc  short   curt\n", .{ day + 1, start, end, try r.strategy.text(gpa), before });
                for (trial.records[first .. last + 1], ix(start)..) |record, h| {
                    const v = record.values;
                    try out.print("{d:>4}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}\n", .{ h, v.load, v.pv, v.discharge, v.soc, v.shortfall, v.curtailed });
                }
                const v = trial.sum(first, last + 1);
                const served = if (v.load == 0) "100.00" else try percentage(gpa, v.load - v.shortfall, v.load);
                try out.print("TOTAL load {d} unserved {d} served {s}% bill {s}\n", .{ v.load, v.shortfall, served, try money(gpa, trial.bill) });
            },
            .DIFF => {
                if (a.len < 2) return app.fail(gpa, "wrong number of arguments", .{});
                const day = try app.dayArgument(gpa, a[0]);
                const strategy = try app.oneStrategy(gpa, a[1..]);
                const r = try app.result(gpa);
                var trial = try simulate(app.data, r.settings, r.prices, strategy, null);
                defer trial.deinit();
                try out.print("DIFF day {d} {s} {s} vs {s}\nhour   imp1   imp2   exp1   exp2   soc1   soc2\n", .{ day + 1, app.data.dayName(day), try r.strategy.text(gpa), try strategy.text(gpa) });
                const first = day * 24;
                const last = first + 24;
                for (r.records[first..last], trial.records[first..last], 0..) |left, right, h| try out.print("{d:>4}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}\n", .{ h, left.values.imported, right.values.imported, left.values.exported, right.values.exported, left.values.soc, right.values.soc });
                const cost1 = r.sum(first, last).net();
                const cost2 = trial.sum(first, last).net();
                try out.print("TOTAL cost1 {s} cost2 {s} difference {s}\n", .{ try money(gpa, cost1), try money(gpa, cost2), try money(gpa, cost2 - cost1) });
            },
            .HOURLY, .CHART => {
                try app.arity(gpa, a, 1);
                const day = try app.dayArgument(gpa, a[0]);
                try app.report(gpa, out, cmd, day, 0);
            },
            .PEAKS => {
                try app.arity(gpa, a, 1);
                const count = integer(a[0]);
                if (count < 1) return app.fail(gpa, "invalid count", .{});
                try app.report(gpa, out, cmd, 0, ix(count));
            },
            else => { try app.arity(gpa, a, 0); try app.report(gpa, out, cmd, 0, 0); },
        }
        return false;
    }
    fn report(app: *App, gpa: Allocator, out: *std.Io.Writer, cmd: Command, day: usize, count: usize) Error!void {
        const r = try app.result(gpa);
        const label = try r.strategy.text(gpa);
        const total = r.total;
        switch (cmd) {
            .HOURLY => {
                try out.print("HOURLY day {d} {s} strategy {s}\nhour   load     pv charge  disch    soc import export   curt\n", .{ day + 1, app.data.dayName(day), label });
                for (r.records[day * 24 .. (day + 1) * 24], 0..) |record, h| {
                    const v = record.values;
                    try out.print("{d:>4}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}\n", .{ h, v.load, v.pv, v.charge, v.discharge, v.soc, v.imported, v.exported, v.curtailed });
                }
                const v = r.sum(day * 24, (day + 1) * 24);
                try out.print(" sum{d:>7}{d:>7}{d:>7}{d:>7}       {d:>7}{d:>7}{d:>7}\n", .{ v.load, v.pv, v.charge, v.discharge, v.imported, v.exported, v.curtailed });
            },
            .DAILY => {
                try out.print("DAILY strategy {s}\nday name    load      pv  import  export    curt     soc      cost\n", .{label});
                for (0..app.data.days()) |d| {
                    const v = r.sum(d * 24, (d + 1) * 24);
                    try out.print("{d:>3}{s:>5}{d:>8}{d:>8}{d:>8}{d:>8}{d:>8}{d:>8}{s:>10}\n", .{ d + 1, app.data.dayName(d), v.load, v.pv, v.imported, v.exported, v.curtailed, r.records[d * 24 + 23].values.soc, try money(gpa, v.net()) });
                }
                try out.print("TOTAL load {d} pv {d} import {d} export {d} curtailed {d} cost {s}\n", .{ total.load, total.pv, total.imported, total.exported, total.curtailed, try money(gpa, total.net()) });
            },
            .BILL => {
                try out.print("BILL strategy {s} days {d}\n", .{ label, app.data.days() });
                for (app.data.period_names, 0..) |name, p| try out.print("IMPORT {s} {d} Wh {s}\n", .{ name, r.periods[p].imported, try money(gpa, r.periods[p].import_cost) });
                try out.print("EXPORT {d} Wh {s}\nFIXED {s}\nDEMAND {d} Wh {s}\nTOTAL {s}\n", .{ total.exported, try money(gpa, -total.export_income), try money(gpa, r.settings.fixed), r.peak, try money(gpa, r.demand_charge), try money(gpa, r.bill) });
            },
            .SAVINGS => {
                var base = try baseline(app.data, r.settings, r.prices);
                defer base.deinit();
                try out.print("SAVINGS strategy {s}\n", .{label});
                for (app.data.period_names, 0..) |name, p| try savingsRow(gpa, out, name, base.periods[p].import_cost, r.periods[p].import_cost);
                try savingsRow(gpa, out, "EXPORT", -base.total.export_income, -total.export_income);
                try savingsRow(gpa, out, "DEMAND", base.demand_charge, r.demand_charge);
                try savingsRow(gpa, out, "TOTAL", base.bill, r.bill);
            },
            .BYPERIOD => {
                try out.print("BYPERIOD strategy {s}\n", .{label});
                for (app.data.period_names, 0..) |name, p| {
                    const v = r.periods[p];
                    try out.print("{s} hours {d} load {d} pv {d} charge {d} discharge {d} import {d} export {d}\n", .{ name, r.period_hours[p], v.load, v.pv, v.charge, v.discharge, v.imported, v.exported });
                }
            },
            .DAYTYPE => {
                try out.print("DAYTYPE strategy {s}\n", .{label});
                for ([_][]const u8{ "WEEKDAY", "WEEKEND" }, 0..) |name, kind| {
                    var v: Metrics = .{};
                    var days: i64 = 0;
                    for (0..app.data.days()) |d| {
                        if (app.data.weekend(d) != (kind == 1)) continue;
                        days += 1;
                        v.add(r.sum(d * 24, (d + 1) * 24));
                    }
                    try out.print("{s} days {d} load {d} pv {d} import {d} export {d} cost {s}\n", .{ name, days, @divFloor(v.load, days), @divFloor(v.pv, days), @divFloor(v.imported, days), @divFloor(v.exported, days), try money(gpa, @divTrunc(v.net(), days)) });
                }
            },
            .PEAKS => {
                try out.print("PEAKS strategy {s}\n", .{label});
                var peaks: std.ArrayList(Peak) = .empty;
                for (r.records, 0..) |record, i| if (record.values.imported > 0) try peaks.append(gpa, .{ .index = i, .imported = record.values.imported });
                std.mem.sort(Peak, peaks.items, {}, Peak.less);
                if (peaks.items.len == 0) try out.writeAll("none\n");
                for (peaks.items[0..@min(count, peaks.items.len)], 1..) |peak, rank| {
                    const record = r.records[peak.index];
                    try out.print("{d}. day {d} hour {d} {s} import {d} load {d} soc {d}\n", .{ rank, peak.index / 24 + 1, peak.index % 24, app.data.period_names[record.period], record.values.imported, record.values.load, record.values.soc });
                }
            },
            .PROFILE => {
                try out.print("PROFILE strategy {s} days {d}\nhour   load     pv import export    soc\n", .{ label, app.data.days() });
                const days: i64 = @intCast(app.data.days());
                for (0..24) |h| {
                    var v: Metrics = .{};
                    for (0..app.data.days()) |d| v.add(r.records[d * 24 + h].values);
                    try out.print("{d:>4}{d:>7}{d:>7}{d:>7}{d:>7}{d:>7}\n", .{ h, @divFloor(v.load, days), @divFloor(v.pv, days), @divFloor(v.imported, days), @divFloor(v.exported, days), @divFloor(v.soc, days) });
                }
            },
            .FLOWS => {
                try out.print("FLOWS strategy {s}\n", .{label});
                for (flow_names, r.flows) |name, flow| try out.print("{s} {d}\n", .{ name, flow });
                try out.print("LOSSES {d}\nSTORED {d}\n", .{ total.loss, r.endSoc() - r.starting });
            },
            .SELFSUFF => try out.print("SELFSUFF sufficiency {s}% consumption {s}%\n", .{ try r.sufficiency(gpa), try percentage(gpa, r.flows[0] + r.flows[1], total.pv) }),
            .CYCLES => {
                var a = total.drawn;
                var b = r.settings.capacity;
                while (b != 0) {
                    const remainder = @mod(a, b);
                    a = b;
                    b = remainder;
                }
                const cycles = @divFloor(1000 * total.drawn, r.settings.capacity);
                try out.print("CYCLES {d}/{d} {d}.{d:0>3} drawn {d} losses {d}\n", .{ @divExact(total.drawn, a), @divExact(r.settings.capacity, a), @divFloor(cycles, 1000), @mod(cycles, 1000), total.drawn, total.loss });
            },
            .USAGE => {
                var charging: usize = 0;
                var discharging: usize = 0;
                var idle: usize = 0;
                var full: usize = 0;
                var low: usize = 0;
                var streak: usize = 0;
                var longest: usize = 0;
                var first: usize = 0;
                for (r.records, 0..) |record, i| {
                    const v = record.values;
                    charging += @intFromBool(v.charge > 0);
                    discharging += @intFromBool(v.drawn > 0);
                    idle += @intFromBool(v.charge == 0 and v.drawn == 0);
                    full += @intFromBool(v.soc == r.settings.capacity);
                    if (v.soc <= r.reserve) {
                        low += 1;
                        streak += 1;
                        if (streak > longest) {
                            longest = streak;
                            first = i + 1 - streak;
                        }
                    } else streak = 0;
                }
                try out.print("USAGE charging {d} discharging {d} idle {d} full {d} low {d} longest {d}", .{ charging, discharging, idle, full, low, longest });
                if (longest > 0) try out.print(" from day {d} hour {d}", .{ first / 24 + 1, first % 24 });
                try out.writeAll("\n");
            },
            .HISTOGRAM => {
                try out.print("HISTOGRAM strategy {s}\n", .{label});
                var bands: [10]i64 = @splat(0);
                for (r.records) |record| bands[ix(@min(9, @divFloor(10 * record.values.soc, r.settings.capacity)))] += 1;
                for (bands, 0..) |frequency, band| {
                    try out.print("{d:>3}% ", .{band * 10});
                    try bar(out, @divFloor(20 * frequency, @as(i64, @intCast(r.records.len))));
                    try out.print(" {d}\n", .{frequency});
                }
            },
            .CHART => {
                try out.print("CHART day {d} {s} strategy {s}\n", .{ day + 1, app.data.dayName(day), label });
                for (r.records[day * 24 .. (day + 1) * 24], 0..) |record, h| {
                    const soc = record.values.soc;
                    try out.print("{d:>2} ", .{h});
                    try bar(out, @divFloor(20 * soc, r.settings.capacity));
                    try out.print(" {s}%\n", .{try percentage(gpa, soc, r.settings.capacity)});
                }
            },
            else => unreachable,
        }
    }
};

fn savingsRow(gpa: Allocator, out: *std.Io.Writer, name: []const u8, base: i64, current: i64) Error!void {
    try out.print("{s} {s} -> {s} saving {s}\n", .{ name, try money(gpa, base), try money(gpa, current), try money(gpa, base - current) });
}

fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const line = try buffer.toOwnedSlice();
    var words: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, line, ' ');
    while (split.next()) |word| try words.append(gpa, word);
    return words.items;
}
fn readInput(gpa: Allocator, input: *std.Io.Reader) !App {
    const battery = try readWords(gpa, input);
    const grid = try readWords(gpa, input);
    const settings: Settings = .{ .capacity = integer(battery[1]), .initial = integer(battery[2]), .charge = integer(battery[3]), .discharge = integer(battery[4]), .ceff = integer(battery[5]), .deff = integer(battery[6]), .reserve = integer(battery[7]), .cost = integer(battery[8]), .export_limit = integer(grid[1]), .feedin = integer(grid[2]), .fixed = integer(grid[3]), .demand = integer(grid[4]) };
    const period_count = ix(integer((try readWords(gpa, input))[1]));
    const names = try gpa.alloc([]const u8, period_count);
    var prices: [6]i64 = @splat(0);
    for (names, 0..) |*name, p| {
        const words = try readWords(gpa, input);
        name.* = words[0];
        prices[p] = integer(words[1]);
    }
    var divisions: [2][24]usize = undefined;
    for (&divisions) |*division| {
        const words = try readWords(gpa, input);
        var j: usize = 1;
        while (j < words.len) : (j += 2) {
            const first = ix(integer(words[j]));
            const last = if (j + 2 < words.len) ix(integer(words[j + 2])) else 24;
            var p: usize = 0;
            while (!equal(names[p], words[j + 1])) p += 1;
            @memset(division[first..last], p);
        }
    }
    const Profile = struct { kind: []const u8, name: []const u8, values: [24]i64 };
    const profile_count = ix(integer((try readWords(gpa, input))[1]));
    const profiles = try gpa.alloc(Profile, profile_count);
    for (profiles) |*profile| {
        const words = try readWords(gpa, input);
        profile.* = .{ .kind = words[0], .name = words[1], .values = undefined };
        for (&profile.values, words[2..]) |*value, word| value.* = integer(word);
    }
    const days = ix(integer((try readWords(gpa, input))[1]));
    const hours = try gpa.alloc(HourInput, days * 24);
    for (0..days) |day| {
        const words = try readWords(gpa, input);
        var load: *const Profile = undefined;
        var pv: *const Profile = undefined;
        for (profiles) |*profile| {
            if (equal(profile.kind, "LOAD") and equal(profile.name, words[0])) load = profile;
            if (equal(profile.kind, "PV") and equal(profile.name, words[2])) pv = profile;
        }
        for (0..24) |h| hours[day * 24 + h] = .{ .load = @divFloor(load.values[h] * integer(words[1]), 100), .pv = @divFloor(pv.values[h] * integer(words[3]), 100) };
    }
    const holiday = try gpa.alloc(bool, days);
    @memset(holiday, false);
    const holiday_words = try readWords(gpa, input);
    for (holiday_words[2..]) |word| holiday[ix(integer(word) - 1)] = true;
    const data: Data = .{ .period_names = names, .hours = hours, .holiday = holiday };
    for (hours, 0..) |*hour, i| hour.period = divisions[@intFromBool(data.weekend(i / 24))][i % 24];
    const overrides = ix(integer((try readWords(gpa, input))[1]));
    for (0..overrides) |_| {
        const words = try readWords(gpa, input);
        const i = ix(integer(words[0]) - 1) * 24 + ix(integer(words[1]));
        hours[i].load = integer(words[2]);
        hours[i].pv = integer(words[3]);
    }
    return .{ .data = data, .settings = settings, .prices = prices, .initial_settings = settings, .initial_prices = prices };
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var app = try readInput(arena.allocator(), &input.interface);
    defer if (app.current) |*r| r.deinit();
    while (true) {
        var command_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer command_arena.deinit();
        const gpa = command_arena.allocator();
        const words = try readWords(gpa, &input.interface);
        var response: std.Io.Writer.Allocating = .init(gpa);
        const done = app.execute(gpa, &response.writer, words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{app.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
        if (done) break;
    }
    try output.interface.flush();
}
