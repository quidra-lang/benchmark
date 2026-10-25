const std = @import("std");
const d = @import("dates_calendar.zig");
const dc = @import("daycount.zig");
const schedule = @import("schedule.zig");
const pricing = @import("pricing.zig");
const curve = @import("curve.zig");
const Strings = d.Strings;
const fmt = d.fmt;
const add = d.append;
const real = d.real;
const integer = d.integer;
const InputError = error{InvalidInput};
const BondType = enum { FIXED, ZERO, AMORT, FRN };
const frequencies = [_]i64{ 1, 2, 4, 12 };
const business_rules = [_][]const u8{ "FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED" };
const bucket_names = [_][]const u8{ "0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+" };

fn enumValue(comptime T: type, text: []const u8) ?T { inline for (@typeInfo(T).@"enum".field_names) |name| { if (d.eq(name, text)) return @field(T, name); } return null; }
fn rounded(n: i64, denominator: i64) i64 { return @divFloor(2 * n + denominator, 2 * denominator); }
fn thousandths(text: []const u8) i64 { const dot = std.mem.findScalar(u8, text, '.').?; return integer(text[0..dot]) * 1000 + integer(text[dot + 1..]); }
fn fixedInteger(value: i64, digits: usize) []const u8 {
    var scale: i64 = 1;
    for (0..digits) |_| scale *= 10;
    const magnitude = if (value < 0) -value else value;
    const fraction = fmt("{d}", .{@mod(magnitude, scale)});
    const padding = d.allocator.alloc(u8, digits - fraction.len) catch @panic("allocation failed");
    @memset(padding, '0');
    return fmt("{s}{d}.{s}{s}", .{ if (value < 0) @as([]const u8, "-") else "", @divFloor(magnitude, scale), padding, fraction });
}
fn hundredths(value: i64) []const u8 { return fixedInteger(value, 2); }
fn decimals(value: f64, digits: usize) []const u8 {
    var scale: i64 = 1;
    for (0..digits) |_| scale *= 10;
    const magnitude = if (value < 0) -value else value;
    const rounded_value: i64 = @intFromFloat(magnitude * real(scale) + 0.5);
    return fixedInteger(if (value < 0) -rounded_value else rounded_value, digits);
}
fn percent(value: f64) []const u8 { return decimals(value * 100, 4); }
fn amount(value: f64) []const u8 { return decimals(value / 100, 2); }
fn create(comptime T: type, value: T) *T { const result = d.allocator.create(T) catch @panic("allocation failed"); result.* = value; return result; }
fn zeros(size: usize) []f64 { const values = d.allocator.alloc(f64, size) catch @panic("allocation failed"); @memset(values, 0); return values; }
fn stringLess(a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
const Text = struct {
    lines: std.ArrayList([]const u8) = .empty,
    fn line(out: *Text, text: []const u8) void { add([]const u8, &out.lines, text); }
    fn value(out: Text) []const u8 { return if (out.lines.items.len == 0) "" else fmt("{s}\n", .{d.join(out.lines.items, "\n")}); }
};
const Row = struct { number: usize, fields: Strings };
fn rows(text: []const u8) []const Row { var result: std.ArrayList(Row) = .empty; for (d.lines(text)[1..], 2..) |line, number| add(Row, &result, .{ .number = number, .fields = d.split(line, ',') }); return result.items; }
const RawScenario = struct { number: usize, name: []const u8, shifts: []const i64 };
const Scenario = struct { name: []const u8, deltas: []const f64 };
const Params = struct {
    valuation: i64 = 0,
    settlement_days: i64 = 0,
    scenarios: std.ArrayList(RawScenario) = .empty,
    limits: std.ArrayList(Strings) = .empty,
    fn parse(text: []const u8) Params {
        var result: Params = .{};
        for (d.lines(text), 1..) |line, number| {
            const words = d.split(line, ' ');
            if (d.eq(words[0], "valuation_date")) result.valuation = d.parseDate(words[1]) else if (d.eq(words[0], "settlement_days")) result.settlement_days = integer(words[1]) else if (d.eq(words[0], "scenario")) {
                var shifts: std.ArrayList(i64) = .empty;
                for (words[2..]) |word| add(i64, &shifts, integer(word));
                add(RawScenario, &result.scenarios, .{ .number = number, .name = words[1], .shifts = shifts.items });
            } else add(Strings, &result.limits, words[1..]);
        }
        return result;
    }
};
const DatedAmount = struct { date: []const u8, amount: i64 };
const Redemption = struct { day: i64, amount: i64 };
const Options = struct {
    eom: bool = false,
    long_stub: bool = false,
    lag: ?i64 = null,
    cap: ?i64 = null,
    floor: ?i64 = null,
    sinks: std.ArrayList(DatedAmount) = .empty,
    calls: std.ArrayList(DatedAmount) = .empty,
};
const Period = struct {
    number: usize,
    start: i64,
    end: i64,
    payment: i64,
    fraction: dc.Fraction,
    rate: i64,
    opening: i64,
    coupon: i64,
    principal: i64,
    fn cashflow(period: Period) i64 { return period.coupon + period.principal; }
};
const Bond = struct {
    code: []const u8,
    kind: BondType,
    issue: i64,
    maturity: i64,
    coupon: i64,
    frequency: i64,
    daycount: []const u8,
    bdc: []const u8,
    face: i64,
    options: Options,
    boundaries: []const i64,
    calls: []const Redemption,
    periods: []const Period,
};
const Valuation = struct {
    bond: *const Bond,
    clean: i64,
    remaining: []const Period,
    cashflows: []const Period,
    flows: []const curve.Flow,
    outstanding: i64,
    accrued: f64,
    accrued_amount: i64,
    clean_amount: i64,
    unit_value: i64,
    target: f64,
    fraction: f64,
    pricer: pricing.YieldPricer,
    ytm: f64 = 0,
    ytw: f64 = 0,
    risk: pricing.Risk = .{},
    workout: i64,
    wal: f64 = 0,
    next_payment: i64,
    curve_clean: f64 = 0,
    zspread: f64 = 0,
    fn init(bond: *const Bond, clean: i64, settlement: i64) Valuation {
        var index: usize = 0;
        while (bond.periods[index].end <= settlement) : (index += 1) {}
        const remaining = bond.periods[index..];
        const current = remaining[0];
        const accrued_fraction = dc.fraction(bond.daycount, current.start, settlement);
        const accrued = real(current.rate) * real(accrued_fraction.n) / (100 * real(accrued_fraction.m));
        const accrued_amount = rounded(current.opening * current.rate * accrued_fraction.n, 10000 * accrued_fraction.m);
        const clean_amount = rounded(current.opening * clean, 100000);
        const fraction = real(bond.frequency) * dc.fraction(bond.daycount, settlement, current.end).value();
        var cashflows: std.ArrayList(Period) = .empty;
        var flows: std.ArrayList(curve.Flow) = .empty;
        var amounts: std.ArrayList(i64) = .empty;
        for (remaining) |period| {
            add(i64, &amounts, period.cashflow());
            if (period.cashflow() > 0) {
                add(Period, &cashflows, period);
                add(curve.Flow, &flows, .{ .days = period.payment - settlement, .amount = real(period.cashflow()) });
            }
        }
        return .{ .bond = bond, .clean = clean, .remaining = remaining, .cashflows = cashflows.items, .flows = flows.items, .outstanding = current.opening, .accrued = accrued, .accrued_amount = accrued_amount, .clean_amount = clean_amount, .unit_value = clean_amount + accrued_amount, .target = real(clean) / 1000 + accrued, .fraction = fraction, .pricer = .{ .flows = amounts.items, .fraction = fraction, .frequency = bond.frequency, .outstanding = current.opening }, .workout = bond.maturity, .next_payment = cashflows.items[0].payment };
    }
    fn analyze(value: *Valuation, zero_curve: curve.ZeroCurve, settlement: i64) void {
        value.ytm = value.pricer.solve(value.target);
        value.risk = value.pricer.risk(value.ytm);
        value.ytw = value.ytm;
        for (value.bond.calls) |call| {
            if (call.day <= settlement) continue;
            var amounts: std.ArrayList(i64) = .empty;
            for (value.remaining) |period| {
                add(i64, &amounts, period.coupon);
                if (period.end == call.day) { amounts.items[amounts.items.len - 1] += rounded(period.opening * call.amount, 100000); break; }
            }
            const pricer: pricing.YieldPricer = .{ .flows = amounts.items, .fraction = value.fraction, .frequency = value.bond.frequency, .outstanding = value.outstanding };
            const rate = pricer.solve(value.target);
            if (rate < value.ytw) { value.ytw = rate; value.workout = call.day; }
        }
        var principal_days: i64 = 0;
        for (value.cashflows) |period| principal_days += period.principal * (period.payment - settlement);
        value.wal = real(principal_days) / real(365 * value.outstanding);
        value.curve_clean = zero_curve.presentValue(value.flows, 0) * 100 / real(value.outstanding) - value.accrued;
        value.zspread = curve.zSpread(zero_curve, value.flows, real(value.unit_value));
    }
};
const Position = struct {
    portfolio: []const u8,
    valuation: *const Valuation,
    units: i64 = 0,
    book: i64 = 0,
    fn market(position: Position) i64 { return position.units * position.valuation.unit_value; }
    fn face(position: Position) i64 { return position.units * position.valuation.bond.face; }
    fn outstanding(position: Position) i64 { return position.units * position.valuation.outstanding; }
    fn gain(position: Position) i64 { return position.units * position.valuation.clean_amount - position.book; }
    fn dv01(position: Position) f64 { return position.valuation.risk.dv01 * real(position.units) * real(position.valuation.outstanding) / 10000; }
    fn presentValue(position: Position, zero_curve: curve.ZeroCurve) f64 { return real(position.units) * zero_curve.presentValue(position.valuation.flows, position.valuation.zspread); }
};
fn pillarLess(_: void, a: curve.Pillar, b: curve.Pillar) bool { return a.maturity < b.maturity; }
fn bondLess(_: void, a: *Bond, b: *Bond) bool { return stringLess(a.code, b.code); }
fn valuationLess(_: void, a: *Valuation, b: *Valuation) bool { return stringLess(a.bond.code, b.bond.code); }
fn positionLess(_: void, a: Position, b: Position) bool { return stringLess(a.portfolio, b.portfolio) or (d.eq(a.portfolio, b.portfolio) and stringLess(a.valuation.bond.code, b.valuation.bond.code)); }
const Fixing = struct { day: i64, rate: i64 };

const Data = struct {
    params: Params,
    calendar: d.Calendar,
    fixings: []const Fixing,
    settlement: i64,
    pillars: std.ArrayList(curve.Pillar) = .empty,
    scenarios: std.ArrayList(Scenario) = .empty,
    bonds: std.ArrayList(*Bond) = .empty,
    valuations: std.ArrayList(*Valuation) = .empty,
    positions: std.ArrayList(Position) = .empty,
    errors: Text = .{},
    reason: []const u8 = "",
    fn fail(data: *Data, reason: []const u8) InputError { data.reason = reason; return error.InvalidInput; }
    fn record(data: *Data, file: []const u8, number: usize, key: []const u8) void { data.errors.line(fmt("{s}:{d}: {s}: {s}", .{ file, number, key, data.reason })); }
    fn bond(data: *const Data, code: []const u8) ?*Bond { for (data.bonds.items) |entry| { if (d.eq(entry.code, code)) return entry; } return null; }
    fn valuation(data: *const Data, code: []const u8) ?*Valuation { for (data.valuations.items) |entry| { if (d.eq(entry.bond.code, code)) return entry; } return null; }
    fn parseOptions(data: *Data, kind: BondType, text: []const u8) InputError!Options {
        var options: Options = .{};
        var seen: std.ArrayList([]const u8) = .empty;
        if (!d.eq(text, "-")) {
            for (d.split(text, ';')) |item| {
                const equal = std.mem.findScalar(u8, item, '=') orelse item.len;
                const key = item[0..equal];
                const value = if (equal < item.len) item[equal + 1..] else "";
                const repeatable = d.eq(key, "SINK") or d.eq(key, "CALL");
                const allowed = d.eq(key, "EOM") or d.eq(key, "LONG") or (kind == .FIXED and d.eq(key, "CALL")) or (kind == .AMORT and d.eq(key, "SINK")) or (kind == .FRN and d.has(&.{ "LAG", "CAP", "FLOOR" }, key));
                if (!allowed or (d.has(seen.items, key) and !repeatable)) return data.fail("invalid option");
                add([]const u8, &seen, key);
                if (d.eq(key, "EOM")) options.eom = true else if (d.eq(key, "LONG")) options.long_stub = true else if (d.eq(key, "LAG")) options.lag = integer(value) else if (d.eq(key, "CAP")) options.cap = integer(value) else if (d.eq(key, "FLOOR")) options.floor = integer(value) else {
                    const fields = d.split(value, ':');
                    add(DatedAmount, if (d.eq(key, "SINK")) &options.sinks else &options.calls, .{ .date = fields[0], .amount = if (d.eq(key, "SINK")) integer(fields[1]) else thousandths(fields[1]) });
                }
            }
        }
        if (kind == .FRN and (options.lag == null or options.lag.? < 1 or options.lag.? > 5 or (options.cap orelse 1200) > 1200 or (options.floor orelse 0) > (options.cap orelse 1200))) return data.fail("invalid option");
        return options;
    }
    fn redemptions(data: *Data, items: []const DatedAmount, boundaries: []const i64, reason: []const u8) InputError![]const Redemption {
        var result: std.ArrayList(Redemption) = .empty;
        for (items) |item| {
            if (!d.valid(item.date)) return data.fail(reason);
            const day = d.parseDate(item.date);
            if (std.mem.findScalar(i64, boundaries[1..boundaries.len - 1], day) == null or (result.items.len > 0 and day <= result.items[result.items.len - 1].day)) return data.fail(reason);
            add(Redemption, &result, .{ .day = day, .amount = item.amount });
        }
        return result.items;
    }
    fn parseBond(data: *Data, fields: Strings, seen: Strings) InputError!*Bond {
        if (d.has(seen, fields[0])) return data.fail("duplicate id");
        const kind = enumValue(BondType, fields[1]) orelse return data.fail("unknown type");
        if (!d.valid(fields[2]) or !d.valid(fields[3])) return data.fail("invalid date");
        const issue = d.parseDate(fields[2]);
        const maturity = d.parseDate(fields[3]);
        if (maturity <= issue) return data.fail("maturity not after issue");
        const coupon = integer(fields[4]);
        const frequency = integer(fields[5]);
        if (std.mem.findScalar(i64, &frequencies, frequency) == null) return data.fail("invalid frequency");
        if (!d.has(&dc.conventions, fields[6])) return data.fail("unknown day count");
        if (!d.has(&business_rules, fields[7])) return data.fail("unknown business day rule");
        const face = integer(fields[8]);
        if (@mod(face, 100000) != 0 or face > 10000000) return data.fail("invalid face");
        if (coupon > 1200 or (kind == .ZERO and coupon != 0)) return data.fail("invalid coupon");
        const options = try data.parseOptions(kind, fields[9]);
        const boundaries = schedule.build(issue, maturity, frequency, options.eom, options.long_stub);
        const sinks = try data.redemptions(options.sinks.items, boundaries, "invalid sinking fund");
        var total: i64 = 0;
        for (sinks) |sink| { if (sink.amount == 0) return data.fail("invalid sinking fund"); total += sink.amount; }
        if (kind == .AMORT and (total == 0 or total >= face)) return data.fail("invalid sinking fund");
        const calls = try data.redemptions(options.calls.items, boundaries, "invalid call schedule");
        for (calls) |call| { if (call.amount < 100000 or call.amount > 110000) return data.fail("invalid call schedule"); }
        var periods: std.ArrayList(Period) = .empty;
        var opening = face;
        for (1..boundaries.len) |i| {
            const start = boundaries[i - 1];
            const end = boundaries[i];
            var rate: i64 = if (kind == .ZERO) 0 else coupon;
            if (kind == .FRN) {
                const fixing_date = data.calendar.move(data.calendar.adjust(start, fields[7]), -options.lag.?);
                var fixing: ?i64 = null;
                for (data.fixings) |entry| { if (entry.day <= fixing_date) fixing = entry.rate else break; }
                rate = (fixing orelse return data.fail("missing fixing")) + coupon;
                if (options.floor) |floor| rate = @max(rate, floor);
                if (options.cap) |cap| rate = @min(rate, cap);
            }
            var principal: i64 = if (i == boundaries.len - 1) opening else 0;
            if (i != boundaries.len - 1) { for (sinks) |sink| { if (sink.day == end) principal = sink.amount; } }
            const fraction = dc.fraction(fields[6], start, end);
            add(Period, &periods, .{ .number = i, .start = start, .end = end, .payment = data.calendar.adjust(end, fields[7]), .fraction = fraction, .rate = rate, .opening = opening, .coupon = rounded(opening * rate * fraction.n, 10000 * fraction.m), .principal = principal });
            opening -= principal;
        }
        return create(Bond, .{ .code = fields[0], .kind = kind, .issue = issue, .maturity = maturity, .coupon = coupon, .frequency = frequency, .daycount = fields[6], .bdc = fields[7], .face = face, .options = options, .boundaries = boundaries, .calls = calls, .periods = periods.items });
    }
    fn parsePrice(data: *Data, fields: Strings, seen: Strings) InputError!*Valuation {
        const bond_value = data.bond(fields[0]) orelse return data.fail("unknown bond");
        if (d.has(seen, fields[0])) return data.fail("duplicate price");
        if (!(bond_value.issue <= data.settlement and data.settlement < bond_value.maturity)) return data.fail("not outstanding");
        const value = Valuation.init(bond_value, thousandths(fields[1]), data.settlement);
        if (!(value.pricer.dirty(0) > value.target and value.target > value.pricer.dirty(1))) return data.fail("yield out of range");
        return create(Valuation, value);
    }
    fn holding(data: *Data, fields: Strings) InputError!void {
        const bond_value = data.bond(fields[1]) orelse return data.fail("unknown bond");
        const value = data.valuation(fields[1]) orelse return data.fail("no price");
        const face = integer(fields[2]);
        if (@mod(face, bond_value.face) != 0) return data.fail("invalid face");
        const units = @divFloor(face, bond_value.face);
        const book = rounded(units * value.outstanding * thousandths(fields[3]), 100000);
        for (data.positions.items) |*position| {
            if (d.eq(position.portfolio, fields[0]) and d.eq(position.valuation.bond.code, fields[1])) { position.units += units; position.book += book; return; }
        }
        add(Position, &data.positions, .{ .portfolio = fields[0], .valuation = value, .units = units, .book = book });
    }
    fn load(data: *Data, curve_rows: []const Row, bond_rows: []const Row, price_rows: []const Row, holding_rows: []const Row) void {
        var seen: std.ArrayList([]const u8) = .empty;
        for (curve_rows) |row| {
            const fields = row.fields;
            const reason: ?[]const u8 = if (d.has(seen.items, fields[0])) "duplicate pillar" else if (!d.valid(fields[0])) "invalid date" else if (d.parseDate(fields[0]) <= data.settlement) "pillar not after settlement" else if (std.mem.findScalar(i64, &frequencies, integer(fields[2])) == null) "invalid frequency" else null;
            if (reason) |message| { data.reason = message; data.record("curve_quotes.csv", row.number, fields[0]); } else add(curve.Pillar, &data.pillars, .{ .maturity = d.parseDate(fields[0]), .coupon = integer(fields[1]), .frequency = integer(fields[2]) });
            add([]const u8, &seen, fields[0]);
        }
        std.mem.sort(curve.Pillar, data.pillars.items, {}, pillarLess);
        seen = .empty;
        for (data.params.scenarios.items) |scenario| {
            const reason: ?[]const u8 = if (d.has(seen.items, scenario.name)) "duplicate scenario" else if (scenario.shifts.len != data.pillars.items.len) "wrong number of shifts" else null;
            if (reason) |message| { data.reason = message; data.record("params.txt", scenario.number, scenario.name); } else {
                const deltas = zeros(scenario.shifts.len);
                for (deltas, scenario.shifts) |*delta, shift| delta.* = real(shift) * 0.0001;
                add(Scenario, &data.scenarios, .{ .name = scenario.name, .deltas = deltas });
            }
            add([]const u8, &seen, scenario.name);
        }
        seen = .empty;
        for (bond_rows) |row| {
            const value = data.parseBond(row.fields, seen.items) catch { data.record("bonds.csv", row.number, row.fields[0]); add([]const u8, &seen, row.fields[0]); continue; };
            add([]const u8, &seen, row.fields[0]);
            add(*Bond, &data.bonds, value);
        }
        seen = .empty;
        for (price_rows) |row| {
            const value = data.parsePrice(row.fields, seen.items) catch { data.record("prices.csv", row.number, row.fields[0]); add([]const u8, &seen, row.fields[0]); continue; };
            add([]const u8, &seen, row.fields[0]);
            add(*Valuation, &data.valuations, value);
        }
        for (holding_rows) |row| data.holding(row.fields) catch data.record("holdings.csv", row.number, row.fields[1]);
        std.mem.sort(*Bond, data.bonds.items, {}, bondLess);
        std.mem.sort(*Valuation, data.valuations.items, {}, valuationLess);
        std.mem.sort(Position, data.positions.items, {}, positionLess);
    }
};

fn bucket(days: i64) usize { return if (days < 365) 0 else if (days < 1095) 1 else if (days < 1825) 2 else if (days < 3650) 3 else 4; }
const Group = struct {
    count: usize = 0,
    value: i64 = 0,
    duration: f64 = 0,
    dv01: f64 = 0,
    fn include(group: *Group, position: Position) void { group.count += 1; group.value += position.market(); group.duration += real(position.market()) * position.valuation.risk.modified; group.dv01 += position.dv01(); }
};
const Portfolio = struct {
    positions: []const Position,
    face: i64 = 0,
    outstanding: i64 = 0,
    value: i64 = 0,
    book: i64 = 0,
    gain: i64 = 0,
    income: i64 = 0,
    weighted: [4]f64 = @splat(0),
    dv01: f64 = 0,
    cash_yield: f64 = 0,
    base_values: []f64,
    base_value: f64 = 0,
    groups: [9]Group = @splat(.{}),
    ladder: [100][2]i64 = @splat(@splat(0)),
    fn init(positions: []const Position, zero_curve: curve.ZeroCurve, settlement: i64) Portfolio {
        var result: Portfolio = .{ .positions = positions, .base_values = zeros(positions.len) };
        var flows: std.ArrayList(curve.Flow) = .empty;
        for (positions, 0..) |position, index| {
            const value = position.valuation;
            const mv = position.market();
            result.face += position.face();
            result.outstanding += position.outstanding();
            result.value += mv;
            result.book += position.book;
            result.gain += position.gain();
            result.weighted[0] += real(mv) * value.ytm;
            result.weighted[1] += real(mv) * value.risk.modified;
            result.weighted[2] += real(mv) * value.risk.convexity;
            result.weighted[3] += real(mv) * value.zspread;
            result.dv01 += position.dv01();
            result.base_values[index] = position.presentValue(zero_curve);
            result.base_value += result.base_values[index];
            result.groups[@intFromEnum(value.bond.kind)].include(position);
            result.groups[4 + bucket(value.bond.maturity - settlement)].include(position);
            for (value.cashflows) |period| {
                const days = period.payment - settlement;
                add(curve.Flow, &flows, .{ .days = days, .amount = real(position.units * period.cashflow()) });
                if (days <= 365) result.income += position.units * period.coupon;
                const year: usize = @intCast(d.civil(period.payment).year - 2000);
                result.ladder[year][0] += position.units * period.coupon;
                result.ladder[year][1] += position.units * period.principal;
            }
        }
        for (&result.weighted) |*value| value.* /= real(result.value);
        result.cash_yield = pricing.bisect(@as([]const curve.Flow, flows.items), curve.flatPresentValue, 0, 1, real(result.value));
        return result;
    }
    fn presentValue(portfolio: Portfolio, zero_curve: curve.ZeroCurve) f64 { var total: f64 = 0; for (portfolio.positions) |position| total += position.presentValue(zero_curve); return total; }
    fn rateDuration(portfolio: Portfolio, zero_curve: curve.ZeroCurve, pillar: ?usize) f64 {
        const down = zeros(zero_curve.rates.len);
        const up = zeros(zero_curve.rates.len);
        for (down, up, 0..) |*low, *high, i| { if (pillar == null or pillar.? == i) { low.* = -0.0001; high.* = 0.0001; } }
        return (portfolio.presentValue(zero_curve.shifted(down)) - portfolio.presentValue(zero_curve.shifted(up))) / (2 * 0.0001 * portfolio.base_value);
    }
    fn report(portfolio: Portfolio, out: *Text, zero_curve: curve.ZeroCurve) void {
        const name = portfolio.positions[0].portfolio;
        out.line(fmt("portfolio {s}", .{name}));
        for (portfolio.positions) |position| {
            const value = position.valuation;
            out.line(fmt("position {s} face {s} outstanding {s} clean {s} value {s} weight {s} book {s} gain {s} ytm {s} modified {s} dv01 {s}", .{ value.bond.code, hundredths(position.face()), hundredths(position.outstanding()), decimals(real(value.clean) / 1000, 6), hundredths(position.market()), decimals(real(position.market()) * 100 / real(portfolio.value), 4), hundredths(position.book), hundredths(position.gain()), percent(value.ytm), decimals(value.risk.modified, 4), decimals(position.dv01(), 2) }));
        }
        out.line(fmt("total positions {d} face {s} outstanding {s} value {s} book {s} gain {s} income {s}", .{ portfolio.positions.len, hundredths(portfolio.face), hundredths(portfolio.outstanding), hundredths(portfolio.value), hundredths(portfolio.book), hundredths(portfolio.gain), hundredths(portfolio.income) }));
        out.line(fmt("risk ytm {s} yield {s} modified {s} convexity {s} zspread {s} dv01 {s}", .{ percent(portfolio.weighted[0]), percent(portfolio.cash_yield), decimals(portfolio.weighted[1], 4), decimals(portfolio.weighted[2], 4), percent(portfolio.weighted[3]), decimals(portfolio.dv01, 2) }));
        var key_rates: std.ArrayList([]const u8) = .empty;
        for (0..zero_curve.rates.len) |i| add([]const u8, &key_rates, decimals(portfolio.rateDuration(zero_curve, i), 4));
        out.line(fmt("curve effective {s} krd {s}", .{ decimals(portfolio.rateDuration(zero_curve, null), 4), d.join(key_rates.items, " ") }));
        for (portfolio.groups, 0..) |group, index| {
            const name_value = if (index < 4) @tagName(@as(BondType, @enumFromInt(index))) else bucket_names[index - 4];
            out.line(fmt("{s} {s} positions {d} value {s} weight {s} duration {s} dv01 {s}", .{ if (index < 4) @as([]const u8, "type") else "bucket", name_value, group.count, hundredths(group.value), decimals(real(group.value) * 100 / real(portfolio.value), 4), decimals(group.duration / real(portfolio.value), 4), decimals(group.dv01, 2) }));
        }
        var total_coupon: i64 = 0;
        var total_principal: i64 = 0;
        for (portfolio.ladder, 2000..) |values, year| {
            if (values[0] + values[1] == 0) continue;
            out.line(fmt("ladder {d} coupon {s} principal {s} total {s}", .{ year, hundredths(values[0]), hundredths(values[1]), hundredths(values[0] + values[1]) }));
            total_coupon += values[0];
            total_principal += values[1];
        }
        out.line(fmt("ladder total coupon {s} principal {s} total {s}", .{ hundredths(total_coupon), hundredths(total_principal), hundredths(total_coupon + total_principal) }));
    }
    fn scenarios(portfolio: Portfolio, zero_curve: curve.ZeroCurve, inputs: []const Scenario, out: *Text, report_out: *Text) void {
        const name = portfolio.positions[0].portfolio;
        var worst: ?struct { name: []const u8, pnl: f64, pnls: []const f64 } = null;
        for (0..inputs.len + 1) |scenario_index| {
            const scenario: Scenario = if (scenario_index == 0) .{ .name = "BASE", .deltas = zeros(zero_curve.rates.len) } else inputs[scenario_index - 1];
            const shifted = zero_curve.shifted(scenario.deltas);
            const pnls = zeros(portfolio.positions.len);
            var total: f64 = 0;
            for (portfolio.positions, 0..) |position, i| {
                const value = position.presentValue(shifted);
                const pnl = value - portfolio.base_values[i];
                pnls[i] = pnl;
                total += value;
                out.line(fmt("{s},{s},{s},{s},{s}", .{ name, scenario.name, position.valuation.bond.code, amount(value), amount(pnl) }));
            }
            const pnl = total - portfolio.base_value;
            out.line(fmt("{s},{s},*,{s},{s}", .{ name, scenario.name, amount(total), amount(pnl) }));
            if (scenario_index > 0 and (worst == null or pnl < worst.?.pnl)) worst = .{ .name = scenario.name, .pnl = pnl, .pnls = pnls };
        }
        if (worst) |scenario| {
            var losers: std.ArrayList(Loser) = .empty;
            for (portfolio.positions, scenario.pnls) |position, pnl| add(Loser, &losers, .{ .code = position.valuation.bond.code, .pnl = pnl });
            std.mem.sort(Loser, losers.items, {}, loserLess);
            var labels: std.ArrayList([]const u8) = .empty;
            for (losers.items[0..@min(3, losers.items.len)]) |loser| add([]const u8, &labels, fmt("{s} {s}", .{ loser.code, amount(loser.pnl) }));
            report_out.line(fmt("stress worst {s} pnl {s} losers {s}", .{ scenario.name, amount(scenario.pnl), d.join(labels.items, " ") }));
        }
    }
    fn compliance(portfolio: Portfolio, out: *Text, limits: []const Strings, settlement: i64) void {
        const name = portfolio.positions[0].portfolio;
        var largest: usize = 0;
        for (portfolio.positions, 0..) |position, i| { if (position.market() > portfolio.positions[largest].market()) largest = i; }
        var breaches: usize = 0;
        for (limits) |words| {
            const kind = words[0];
            var breach = false;
            var content: []const u8 = undefined;
            if (d.eq(kind, "position_weight")) {
                const limit = integer(words[1]);
                const position = portfolio.positions[largest];
                const value = position.market();
                content = fmt("{s} {s} limit {s}", .{ position.valuation.bond.code, decimals(real(value) * 100 / real(portfolio.value), 4), hundredths(limit) });
                breach = value * 10000 > limit * portfolio.value;
            } else if (d.eq(kind, "type_weight")) {
                const limit = integer(words[2]);
                const value = portfolio.groups[@intFromEnum(enumValue(BondType, words[1]).?)].value;
                content = fmt("{s} {s} limit {s}", .{ words[1], decimals(real(value) * 100 / real(portfolio.value), 4), hundredths(limit) });
                breach = value * 10000 > limit * portfolio.value;
            } else if (d.eq(kind, "max_maturity")) {
                const years = integer(words[1]);
                var count: usize = 0;
                for (portfolio.positions) |position| { if (position.valuation.bond.maturity - settlement > 365 * years) count += 1; }
                content = fmt("{d}Y positions {d}", .{ years, count });
                breach = count > 0;
            } else if (d.eq(kind, "min_yield")) {
                const limit = integer(words[1]);
                content = fmt("{s} limit {s}", .{ percent(portfolio.weighted[0]), hundredths(limit) });
                breach = portfolio.weighted[0] * 10000 < real(limit);
            } else if (d.eq(kind, "duration")) {
                const low = integer(words[1]);
                const high = integer(words[2]);
                content = fmt("{s} range {s} {s}", .{ decimals(portfolio.weighted[1], 4), hundredths(low), hundredths(high) });
                breach = portfolio.weighted[1] < real(low) / 100 or portfolio.weighted[1] > real(high) / 100;
            } else {
                const limit = integer(words[1]);
                content = fmt("{s} limit {s}", .{ decimals(portfolio.dv01, 2), hundredths(limit) });
                breach = portfolio.dv01 * 100 > real(limit);
            }
            if (breach) breaches += 1;
            out.line(fmt("{s} {s} {s} {s}", .{ name, kind, content, if (breach) @as([]const u8, "BREACH") else "PASS" }));
        }
        out.line(fmt("{s} breaches {d}", .{ name, breaches }));
    }
};
const Loser = struct { code: []const u8, pnl: f64 };
fn loserLess(_: void, a: Loser, b: Loser) bool { return a.pnl < b.pnl or (a.pnl == b.pnl and stringLess(a.code, b.code)); }

fn cashflowReport(data: *const Data) Text {
    var out: Text = .{};
    out.line("bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal");
    for (data.bonds.items) |bond| {
        for (bond.periods) |period| {
            if (period.cashflow() == 0) continue;
            out.line(fmt("{s},{d},{s},{s},{s},{s},{d},{d},{d},{d}", .{ bond.code, period.number, d.formatDate(period.start), d.formatDate(period.end), d.formatDate(period.payment), decimals(period.fraction.value(), 6), period.rate, period.opening, period.coupon, period.principal }));
        }
    }
    return out;
}
fn analyticsReport(data: *const Data) Text {
    var out: Text = .{};
    out.line("bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread");
    for (data.valuations.items) |value| out.line(fmt("{s},{s},{s},{s},{s},{s},{s},{s},{s},{s},{s},{s},{s},{s},{s}", .{ value.bond.code, decimals(real(value.clean) / 1000, 6), decimals(value.accrued, 6), decimals(value.target, 6), percent(value.ytm), percent(value.ytw), d.formatDate(value.workout), d.formatDate(value.next_payment), decimals(value.wal, 4), decimals(value.risk.macaulay, 4), decimals(value.risk.modified, 4), decimals(value.risk.convexity, 4), decimals(value.risk.dv01, 6), decimals(value.curve_clean, 6), percent(value.zspread) }));
    return out;
}
fn curveReport(data: *const Data, zero_curve: curve.ZeroCurve) Text {
    var out: Text = .{};
    out.line(fmt("valuation {s} settlement {s}", .{ d.formatDate(data.params.valuation), d.formatDate(data.settlement) }));
    var previous: i64 = 0;
    for (data.pillars.items, zero_curve.days, zero_curve.rates) |pillar, days, rate| {
        out.line(fmt("pillar {s} days {d} frequency {d} par {s} zero {s} df {s} forward {s}", .{ d.formatDate(pillar.maturity), days, pillar.frequency, hundredths(pillar.coupon), percent(rate), decimals(zero_curve.discount(days, 0), 6), percent(zero_curve.forward(previous, days)) }));
        previous = days;
    }
    var year: i64 = 1;
    while (year <= @divFloor(zero_curve.days[zero_curve.days.len - 1], 365)) : (year += 1) {
        const days = year * 365;
        out.line(fmt("grid {d}Y days {d} zero {s} df {s} forward {s}", .{ year, days, percent(zero_curve.zero(days)), decimals(zero_curve.discount(days, 0), 6), percent(zero_curve.forward(days - 365, days)) }));
    }
    return out;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();
    const input_names = [_][]const u8{ "params.txt", "calendar.txt", "fixings.csv", "curve_quotes.csv", "bonds.csv", "prices.csv", "holdings.csv" };
    var inputs: [7][]const u8 = undefined;
    for (input_names, 0..) |name, i| inputs[i] = try cwd.readFileAlloc(init.io, fmt("input/{s}", .{name}), d.allocator, .unlimited);
    const params = Params.parse(inputs[0]);
    var holidays: std.ArrayList(i64) = .empty;
    for (d.lines(inputs[1])) |line| add(i64, &holidays, d.parseDate(line));
    const calendar: d.Calendar = .{ .holidays = holidays.items };
    var fixings: std.ArrayList(Fixing) = .empty;
    for (rows(inputs[2])) |row| add(Fixing, &fixings, .{ .day = d.parseDate(row.fields[0]), .rate = integer(row.fields[1]) });
    var data: Data = .{ .params = params, .calendar = calendar, .fixings = fixings.items, .settlement = calendar.move(params.valuation, params.settlement_days) };
    data.load(rows(inputs[3]), rows(inputs[4]), rows(inputs[5]), rows(inputs[6]));
    const zero_curve = curve.bootstrap(data.settlement, data.pillars.items);
    for (data.valuations.items) |value| value.analyze(zero_curve, data.settlement);
    var portfolio_out: Text = .{};
    var scenario_out: Text = .{};
    var compliance_out: Text = .{};
    scenario_out.line("portfolio,scenario,bond,value,pnl");
    var start: usize = 0;
    while (start < data.positions.items.len) {
        var end = start + 1;
        while (end < data.positions.items.len and d.eq(data.positions.items[end].portfolio, data.positions.items[start].portfolio)) : (end += 1) {}
        const portfolio = Portfolio.init(data.positions.items[start..end], zero_curve, data.settlement);
        portfolio.report(&portfolio_out, zero_curve);
        portfolio.scenarios(zero_curve, data.scenarios.items, &scenario_out, &portfolio_out);
        portfolio.compliance(&compliance_out, data.params.limits.items, data.settlement);
        start = end;
    }
    const outputs = [_]Text{ data.errors, cashflowReport(&data), analyticsReport(&data), curveReport(&data, zero_curve), portfolio_out, scenario_out, compliance_out };
    const output_names = [_][]const u8{ "errors.txt", "cashflows.csv", "analytics.csv", "curve.txt", "portfolio.txt", "scenarios.csv", "compliance.txt" };
    try cwd.createDirPath(init.io, "output");
    for (output_names, outputs) |name, out| try cwd.writeFile(init.io, .{ .sub_path = fmt("output/{s}", .{name}), .data = out.value() });
}
