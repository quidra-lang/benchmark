const std = @import("std");
const d = @import("dataset.zig");
const v = @import("variable_charts.zig");
const attr = @import("attribute_charts.zig");
const rules = @import("run_rules.zig");
const cap = @import("capability.zig");
const plot = @import("plot.zig");
const charts = [_][]const u8{ "XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA" };
const families = [_][]const u8{ "XBAR_R", "XBAR_S", "I_MR" };
const labels = [_][2][]const u8{ .{ "XBAR", "R" }, .{ "XBAR", "S" }, .{ "I", "MR" } };
const attribute_names = [_][]const u8{ "p", "np", "c", "u" };
const event_types = [_][]const u8{ "SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN" };
const standard: v.Limits = .{ .lcl = -3, .cl = 0, .ucl = 3 };
const Pass = struct { points: usize, limits: [2]v.Limits, out: []const usize };
const Estimate = struct { retained: []const usize, removed: []const usize, passes: []const Pass, limits: [2]v.Limits, converged: bool };
const Cusum = struct { upper: f64 = 0, lower: f64 = 0 };
const BandPoint = struct { value: f64 = 0, width: f64 = 0 };
const AttributeResult = struct { points: []const attr.Point, lines: d.Strings };
const Event = struct { first: usize, last: usize, signals: []const rules.Signal = &.{}, counts: [5]usize = @splat(0), detection: [9]usize = @splat(0), onset: usize = 0, shift: f64 = 0, spread: f64 = 0, out: usize = 0, kind: []const u8 = "" };
fn realText(value: f64) []const u8 { const text = d.fmt("{d:.4}", .{value}); return if (d.eq(text, "-0.0000")) "0.0000" else text; }
fn ruleText(rule: usize) []const u8 { return if (rule == 9) "UPPER" else if (rule == 10) "LOWER" else d.fmt("{d}", .{rule}); }
fn status(converged: bool) []const u8 { return if (converged) "converged" else "stopped"; }
fn numberList(numbers: []const usize) []const u8 { if (numbers.len == 0) return "none"; var parts: std.ArrayList([]const u8) = .empty; for (numbers) |number| d.append([]const u8, &parts, d.fmt("{d}", .{number})); return d.join(parts.items, " "); }
fn limitText(label: []const u8, l: v.Limits) []const u8 { return d.fmt("{s} lcl {s} cl {s} ucl {s}", .{ label, realText(l.lcl), realText(l.cl), realText(l.ucl) }); }
fn pairText(family: usize, limits: [2]v.Limits) []const u8 { return d.fmt("{s} {s}", .{ limitText(labels[family][0], limits[0]), limitText(labels[family][1], limits[1]) }); }
fn signalLess(_: void, a: rules.Signal, b: rules.Signal) bool { if (a.chart != b.chart) return a.chart < b.chart; if (a.last != b.last) return a.last < b.last; return a.rule < b.rule; }
fn extend(lines: *std.ArrayList([]const u8), more: d.Strings) void { for (more) |line| d.append([]const u8, lines, line); }
const Analysis = struct {
    s: d.Settings,
    values: []const i64,
    lots: []const d.Lot,
    groups: []const v.Subgroup,
    constants: d.Constants,
    estimates: [3]Estimate = undefined,
    signals: std.ArrayList(rules.Signal) = .empty,
    events: []Event = &.{},
    attributes: [4]AttributeResult = undefined,
    mu: f64 = 0,
    sigma: f64 = 0,
    reference: f64 = 0,
    threshold: f64 = 0,
    ewma_scale: f64 = 0,
    ma_scale: f64 = 0,
    cusum: []Cusum = &.{},
    ewma: []BandPoint = &.{},
    ma: []BandPoint = &.{},
    fn groupNumber(a: Analysis, signal: rules.Signal) usize { return if (signal.chart == 4 or signal.chart == 5) (signal.last - 1) / a.s.n + 1 else signal.last; }
    fn hasSignal(a: Analysis, chart: usize, last: usize, rule: usize) bool { for (a.signals.items) |signal| { if (signal.chart == chart and signal.last == last and (rule == 0 or signal.rule == rule)) return true; } return false; }
    fn eventNumber(a: Analysis, number: usize) usize { for (a.events, 1..) |event, i| { if (number >= event.first and number <= event.last) return i; } return 0; }
    fn estimateFamily(a: Analysis, family: usize) Estimate {
        const initial = d.sequence(1, if (family == 2) a.s.m * a.s.n else a.s.m);
        var retained: []const usize = initial;
        var passes: std.ArrayList(Pass) = .empty;
        var limits: [2]v.Limits = undefined;
        var converged = false;
        for (1..a.s.passes + 1) |p| {
            limits = v.familyLimits(family, retained, a.groups, a.values, a.s.n, a.constants);
            var flagged: [1001]bool = @splat(false);
            const sequences = v.familySeries(family, retained, a.groups, a.values);
            for (sequences, limits) |series, l| for (series.numbers, series.values) |number, value| { if (l.outside(value)) flagged[number] = true; };
            var out: std.ArrayList(usize) = .empty;
            for (retained) |number| { if (flagged[number]) d.append(usize, &out, number); }
            d.append(Pass, &passes, .{ .points = retained.len, .limits = limits, .out = out.items });
            if (out.items.len == 0) { converged = true; break; }
            if (p == a.s.passes) break;
            var next: std.ArrayList(usize) = .empty;
            for (retained) |number| { if (!flagged[number]) d.append(usize, &next, number); }
            retained = next.items;
        }
        var removed: std.ArrayList(usize) = .empty;
        for (initial) |number| { if (!d.contains(retained, number)) d.append(usize, &removed, number); }
        return .{ .retained = retained, .removed = removed.items, .passes = passes.items, .limits = limits, .converged = converged };
    }
    fn chartLimits(a: Analysis, chart: usize) v.Limits { return a.estimates[chart / 2].limits[chart % 2]; }
    fn phase2Series(a: Analysis, chart: usize) v.Series {
        const numbers = d.sequence(if (chart >= 4) a.s.m * a.s.n + 1 else a.s.m + 1, if (chart >= 4) a.values.len else a.groups.len);
        const values = d.alloc(f64, numbers.len);
        for (numbers, values) |number, *value| {
            value.* = switch (chart) { 0, 2 => a.groups[number - 1].mean, 1 => d.real(a.groups[number - 1].range), 3 => a.groups[number - 1].sd, 4 => d.real(a.values[number - 1]), else => d.real(@abs(a.values[number - 1] - a.values[number - 2])) };
        }
        return .{ .numbers = numbers, .values = values };
    }
    fn addBandSignal(a: *Analysis, chart: usize, point: BandPoint, first: usize, last: usize) void {
        const up = point.value > a.mu + point.width;
        if (up or point.value < a.mu - point.width) d.append(rules.Signal, &a.signals, .{ .chart = chart, .rule = if (up) 9 else 10, .first = first, .last = last, .value = point.value, .direction = if (up) .UP else .DOWN });
    }
    fn monitor(a: *Analysis) void {
        for (0..6) |chart| for (rules.check(chart, a.phase2Series(chart), a.chartLimits(chart), a.s.rules[chart])) |signal| d.append(rules.Signal, &a.signals, signal);
        a.mu = a.estimates[0].limits[0].cl;
        a.sigma = a.estimates[0].limits[1].cl / a.constants.d2 / @sqrt(d.real(a.s.n));
        a.reference = a.s.k * a.sigma; a.threshold = a.s.h * a.sigma;
        const decay = (1 - a.s.lambda) * (1 - a.s.lambda); const rho = a.s.lambda / (2 - a.s.lambda);
        a.ewma_scale = a.s.e * a.sigma * @sqrt(rho); a.ma_scale = 3 * a.sigma / @sqrt(d.real(a.s.span));
        a.cusum = d.alloc(Cusum, a.groups.len); @memset(a.cusum, .{});
        a.ewma = d.alloc(BandPoint, a.groups.len); @memset(a.ewma, .{});
        a.ma = d.alloc(BandPoint, a.groups.len); @memset(a.ma, .{});
        var upper: f64 = 0; var lower: f64 = 0; var uprun: usize = 0; var downrun: usize = 0; var smoothed = a.mu; var factor: f64 = 1;
        for (a.groups[a.s.m..]) |group| {
            const i = group.number; const index = i - 1;
            upper = @max(0, upper + (group.mean - a.mu - a.reference)); lower = @max(0, lower + (a.mu - group.mean - a.reference));
            uprun = if (upper > 0) uprun + 1 else 0; downrun = if (lower > 0) downrun + 1 else 0;
            a.cusum[index] = .{ .upper = upper, .lower = lower };
            if (upper > a.threshold) { d.append(rules.Signal, &a.signals, .{ .chart = 6, .rule = 9, .first = i - uprun + 1, .last = i, .value = upper, .direction = .UP }); upper = 0; uprun = 0; }
            if (lower > a.threshold) { d.append(rules.Signal, &a.signals, .{ .chart = 6, .rule = 10, .first = i - downrun + 1, .last = i, .value = lower, .direction = .DOWN }); lower = 0; downrun = 0; }
            smoothed = a.s.lambda * group.mean + (1 - a.s.lambda) * smoothed; factor *= decay;
            a.ewma[index] = .{ .value = smoothed, .width = a.s.e * a.sigma * @sqrt(rho * (1 - factor)) };
            const first = @max(a.s.m + 1, if (i >= a.s.span) i - a.s.span + 1 else 1); const count = i - first + 1;
            var total: i64 = 0; for (a.groups[first - 1..i]) |g| total += g.total;
            a.ma[index] = .{ .value = d.real(total) / d.real(a.s.n * count), .width = 3 * a.sigma / @sqrt(d.real(count)) };
            a.addBandSignal(7, a.ewma[index], i, i); a.addBandSignal(8, a.ma[index], first, i);
        }
        std.mem.sort(rules.Signal, a.signals.items, {}, signalLess);
    }
    fn buildEvents(a: *Analysis) void {
        var marked: [101]bool = @splat(false); for (a.signals.items) |signal| marked[a.groupNumber(signal)] = true;
        var events: std.ArrayList(Event) = .empty;
        for (1..a.groups.len + 1) |i| {
            if (!marked[i]) continue;
            if (events.items.len > 0 and i - events.items[events.items.len - 1].last - 1 <= a.s.gap) events.items[events.items.len - 1].last = i else d.append(Event, &events, .{ .first = i, .last = i });
        }
        for (events.items) |*event| {
            var selected: std.ArrayList(rules.Signal) = .empty;
            for (a.signals.items) |signal| {
                const g = a.groupNumber(signal); if (g < event.first or g > event.last) continue;
                d.append(rules.Signal, &selected, signal);
                const spread = signal.chart == 1 or signal.chart == 3 or signal.chart == 5;
                const bucket: usize = if (signal.direction == .NONE) 4 else if (spread) (if (signal.direction == .UP) @as(usize, 2) else 3) else (if (signal.direction == .UP) @as(usize, 0) else 1);
                event.counts[bucket] += 1;
                if (event.detection[signal.chart] == 0 or g < event.detection[signal.chart]) event.detection[signal.chart] = g;
                if (signal.chart == 6 and (event.onset == 0 or signal.first < event.onset)) event.onset = signal.first;
            }
            event.signals = selected.items; if (event.onset == 0) event.onset = event.first;
            var best: usize = 0; for (1..5) |i| { if (event.counts[i] > event.counts[best]) best = i; } event.kind = event_types[best];
            var total: i64 = 0; var deviations: f64 = 0;
            for (a.groups[event.first - 1..event.last]) |group| { total += group.total; deviations += group.sd; for (group.values) |value| { if (value < a.s.lsl or value > a.s.usl) event.out += 1; } }
            const count = event.last - event.first + 1;
            event.shift = (d.real(total) / d.real(a.s.n * count) - a.mu) / a.sigma;
            event.spread = (deviations / d.real(count)) / a.estimates[1].limits[1].cl;
        }
        a.events = events.items;
    }
    fn limitsLines(a: Analysis) d.Strings {
        var lines: std.ArrayList([]const u8) = .empty;
        extend(&lines, &.{ d.fmt("characteristic {s}", .{a.s.characteristic}), d.fmt("subgroup_size {d}", .{a.s.n}), d.fmt("subgroups {d}", .{a.groups.len}), d.fmt("samples {d}", .{a.values.len}), d.fmt("phase1_subgroups {d}", .{a.s.m}) });
        for (a.estimates, 0..) |e, family| {
            d.append([]const u8, &lines, d.fmt("family {s}", .{families[family]}));
            for (e.passes, 1..) |p, i| d.append([]const u8, &lines, d.fmt("pass {d} points {d} {s} out {s}", .{ i, p.points, pairText(family, p.limits), numberList(p.out) }));
            d.append([]const u8, &lines, d.fmt("result {s} passes {d} retained {d} removed {s}", .{ status(e.converged), e.passes.len, e.retained.len, numberList(e.removed) }));
        }
        for (a.estimates, 0..) |e, family| {
            for (v.familySeries(family, e.retained, a.groups, a.values), 0..) |series, index| {
                const chart = family * 2 + index; const signals = rules.check(chart, series, e.limits[index], a.s.rules[chart]);
                for (signals) |signal| d.append([]const u8, &lines, d.fmt("phase1_signal {s} {d} {d} {d} {s}", .{ charts[chart], signal.rule, signal.first, signal.last, realText(signal.value) }));
                d.append([]const u8, &lines, d.fmt("phase1_check {s} points {d} signals {d}", .{ charts[chart], series.values.len, signals.len }));
            }
        }
        for (a.estimates, 0..) |e, family| {
            var numbers: std.ArrayList(usize) = .empty; for (e.retained) |number| d.append(usize, &numbers, number);
            for (a.groups[a.s.m..]) |group| { if (a.eventNumber(group.number) != 0) continue; if (family == 2) { for ((group.number - 1) * a.s.n + 1..group.number * a.s.n + 1) |sample| d.append(usize, &numbers, sample); } else d.append(usize, &numbers, group.number); }
            const limits = v.familyLimits(family, numbers.items, a.groups, a.values, a.s.n, a.constants);
            d.append([]const u8, &lines, d.fmt("proposed {s} points {d} {s}", .{ families[family], numbers.items.len, pairText(family, limits) }));
        }
        const target = d.fmt("target {s} sigma {s}", .{ realText(a.mu), realText(a.sigma) });
        extend(&lines, &.{ d.fmt("cusum {s} k {s} h {s}", .{ target, realText(a.reference), realText(a.threshold) }), d.fmt("ewma {s} lcl {s} ucl {s}", .{ target, realText(a.mu - a.ewma_scale), realText(a.mu + a.ewma_scale) }), d.fmt("ma {s} span {d} lcl {s} ucl {s}", .{ target, a.s.span, realText(a.mu - a.ma_scale), realText(a.mu + a.ma_scale) }) });
        for (charts, 0..) |name, chart| {
            var count: usize = 0; var ends: [1001]bool = @splat(false); var counts: [11]usize = @splat(0); var first: usize = 0; var distinct: usize = 0;
            for (a.signals.items) |signal| { if (signal.chart != chart) continue; count += 1; counts[signal.rule] += 1; if (first == 0 or signal.last < first) first = signal.last; if (!ends[signal.last]) { ends[signal.last] = true; distinct += 1; } }
            var by_rule: std.ArrayList([]const u8) = .empty;
            const selected_rules: []const usize = if (chart < 6) a.s.rules[chart] else &.{ 9, 10 };
            for (selected_rules) |rule| d.append([]const u8, &by_rule, d.fmt("{s}:{d}", .{ ruleText(rule), counts[rule] }));
            const points = if (chart == 4 or chart == 5) a.values.len - a.s.m * a.s.n else a.groups.len - a.s.m;
            d.append([]const u8, &lines, d.fmt("phase2 {s} points {d} signals {d} signalled {d} first {s} by_rule {s}", .{ name, points, count, distinct, if (first == 0) "none" else d.fmt("{d}", .{first}), d.join(by_rule.items, " ") }));
        }
        return lines.items;
    }
    fn signalLines(a: Analysis) d.Strings { var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, "chart,rule,start,end,value,direction"); for (a.signals.items) |signal| d.append([]const u8, &lines, d.fmt("{s},{s},{d},{d},{s},{s}", .{ charts[signal.chart], ruleText(signal.rule), signal.first, signal.last, realText(signal.value), @tagName(signal.direction) })); return lines.items; }
    fn eventLines(a: Analysis) d.Strings {
        var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("events {d}", .{a.events.len}));
        for (a.events, 1..) |e, i| {
            var names: std.ArrayList([]const u8) = .empty; var detection: std.ArrayList([]const u8) = .empty;
            for (charts, e.detection) |name, number| { if (number > 0) d.append([]const u8, &names, name); d.append([]const u8, &detection, d.fmt("{s}:{s}", .{ name, if (number == 0) "-" else d.fmt("{d}", .{number}) })); }
            d.append([]const u8, &lines, d.fmt("event {d} start {d} end {d} length {d} signals {d} charts {s} location_up {d} location_down {d} spread_up {d} spread_down {d} pattern {d} onset {d} shift {s} spread {s} out_of_spec {d} type {s}", .{ i, e.first, e.last, e.last - e.first + 1, e.signals.len, d.join(names.items, ","), e.counts[0], e.counts[1], e.counts[2], e.counts[3], e.counts[4], e.onset, realText(e.shift), realText(e.spread), e.out, e.kind }));
            d.append([]const u8, &lines, d.fmt("detection {d} {s}", .{ i, d.join(detection.items, " ") }));
        }
        return lines.items;
    }
    fn subgroupLines(a: Analysis) d.Strings {
        var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, "subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event");
        for (a.groups, 0..) |group, index| {
            const i = group.number; const phase = if (i > a.s.m) "phase2" else if (d.contains(a.estimates[0].removed, i)) "excluded" else "phase1";
            const monitored = if (i > a.s.m) d.fmt("{s},{s},{s},{s}", .{ realText(a.cusum[index].upper), realText(a.cusum[index].lower), realText(a.ewma[index].value), realText(a.ma[index].value) }) else "-,-,-,-";
            var count: usize = 0; for (a.signals.items) |signal| { if (a.groupNumber(signal) == i) count += 1; } const event = a.eventNumber(i);
            d.append([]const u8, &lines, d.fmt("{d},{s},{s},{s},{d},{s},{s},{d},{s}", .{ i, phase, realText(group.mean), rules.zoneName(a.estimates[0].limits[0], group.mean), group.range, realText(group.sd), monitored, count, if (event == 0) "-" else d.fmt("{d}", .{event}) }));
        }
        return lines.items;
    }
    fn estimateAttribute(a: Analysis, chart: usize) AttributeResult {
        const initial = d.sequence(1, a.lots.len); var retained: []const usize = initial;
        var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("chart {s}", .{attribute_names[chart]}));
        var center: attr.Center = undefined; var converged = false; var passes: usize = 0;
        for (1..a.s.passes + 1) |p| {
            passes = p; center = attr.centerline(chart, a.lots, retained);
            var out: std.ArrayList(usize) = .empty; for (retained) |number| { if (attr.point(chart, a.lots[number - 1], center).status != .ok) d.append(usize, &out, number); }
            d.append([]const u8, &lines, d.fmt("pass {d} lots {d} center {s} out {s}", .{ p, retained.len, realText(center.value), numberList(out.items) }));
            if (out.items.len == 0) { converged = true; break; } if (p == a.s.passes) break;
            var next: std.ArrayList(usize) = .empty; for (retained) |number| { if (!d.contains(out.items, number)) d.append(usize, &next, number); } retained = next.items;
        }
        var removed: std.ArrayList(usize) = .empty; for (initial) |number| { if (!d.contains(retained, number)) d.append(usize, &removed, number); }
        d.append([]const u8, &lines, d.fmt("result {s} passes {d} retained {d} removed {s}", .{ status(converged), passes, retained.len, numberList(removed.items) }));
        const points = d.alloc(attr.Point, a.lots.len); const values = d.alloc(f64, a.lots.len);
        for (a.lots, points, values) |lot, *point, *value| {
            point.* = attr.point(chart, lot, center); value.* = point.z;
            const text = if (chart == 1) d.fmt("{d}", .{lot.defectives}) else if (chart == 2) d.fmt("{d}", .{lot.defects}) else realText(point.value);
            d.append([]const u8, &lines, d.fmt("lot {d} size {d} value {s} lcl {s} ucl {s} z {s} status {s}", .{ lot.number, lot.inspected, text, realText(point.lcl), realText(point.ucl), realText(point.z), @tagName(point.status) }));
        }
        const signals = rules.check(chart, .{ .numbers = initial, .values = values }, standard, a.s.rules[6]);
        for (signals) |signal| d.append([]const u8, &lines, d.fmt("signal {d} {d} {d} {s}", .{ signal.rule, signal.first, signal.last, realText(signal.value) }));
        d.append([]const u8, &lines, d.fmt("signals {d}", .{signals.len}));
        return .{ .points = points, .lines = lines.items };
    }
    fn capabilityLines(a: Analysis) d.Strings {
        var lines: std.ArrayList([]const u8) = .empty;
        const cohort_names = [_][]const u8{ "phase1", "phase2" }; const cohorts = [_][]const usize{ a.estimates[0].retained, d.sequence(a.s.m + 1, a.groups.len) };
        for (cohort_names, cohorts) |name, numbers| {
            const result = cap.assess(a.groups, numbers, a.s, a.constants);
            d.append([]const u8, &lines, d.fmt("group {s} subgroups {d} values {d}", .{ name, numbers.len, result.count }));
            inline for (.{ "mean", "sigma_within", "sigma_sbar", "sigma_overall", "cp", "cpu", "cpl", "cpk", "pp", "ppu", "ppl", "ppk", "cpm" }) |field| d.append([]const u8, &lines, d.fmt("{s} {s}", .{ field, realText(@field(result, field)) }));
            inline for (.{ "cpk_ci", "ppk_ci" }) |field| { const interval = @field(result, field); d.append([]const u8, &lines, d.fmt("{s} {s} {s}", .{ field, realText(interval[0]), realText(interval[1]) })); }
            extend(&lines, &.{ d.fmt("below_lsl {d}", .{result.below}), d.fmt("above_usl {d}", .{result.above}), d.fmt("ppm {s}", .{realText(result.ppm)}) });
            for (numbers) |number| for (a.groups[number - 1].values, 1..) |value, j| { if (value < a.s.lsl or value > a.s.usl) d.append([]const u8, &lines, d.fmt("out_of_spec sample {d} subgroup {d} value {d} side {s}", .{ (number - 1) * a.s.n + j, number, value, if (value < a.s.lsl) "low" else "high" })); };
            d.append([]const u8, &lines, d.fmt("verdict {s}", .{result.verdict})); extend(&lines, cap.histogram(a.groups, numbers, a.s));
        }
        var first = a.s.m + 1;
        while (first + a.s.window - 1 <= a.groups.len) : (first += a.s.step) {
            const last = first + a.s.window - 1; const result = cap.assess(a.groups, d.sequence(first, last), a.s, a.constants);
            d.append([]const u8, &lines, d.fmt("rolling {d} {d} mean {s} sigma_within {s} sigma_overall {s} cpk {s} ppk {s} verdict {s}", .{ first, last, realText(result.mean), realText(result.sigma_within), realText(result.sigma_overall), realText(result.cpk), realText(result.ppk), result.verdict }));
        }
        return lines.items;
    }
    fn chartLines(a: Analysis) d.Strings {
        var lines: std.ArrayList([]const u8) = .empty;
        const picture_names = [_][]const u8{ "XBAR", "R", "S" }; const picture_charts = [_]usize{ 0, 1, 3 };
        for (picture_names, picture_charts) |name, chart| {
            const l = a.chartLimits(chart); const e = a.estimates[chart / 2]; d.append([]const u8, &lines, limitText(d.fmt("chart {s}", .{name}), l));
            for (a.groups) |group| {
                const number = group.number; const mark: u8 = if (number > a.s.m) '2' else if (d.contains(e.removed, number)) 'x' else '1';
                const value = if (chart == 0) group.mean else if (chart == 1) d.real(group.range) else group.sd;
                const band = plot.limitsBand(l, value, number > a.s.m and a.hasSignal(chart, number, 0));
                d.append([]const u8, &lines, d.fmt("{d: >3} {c} {s} {s}", .{ number, mark, band, realText(value) }));
            }
        }
        d.append([]const u8, &lines, d.fmt("chart CUSUM h {s}", .{realText(a.threshold)}));
        for (a.groups[a.s.m..]) |group| { const i = group.number; const point = a.cusum[i - 1]; const band = plot.cusumBand(point.upper, point.lower, a.threshold, a.hasSignal(6, i, 9), a.hasSignal(6, i, 10)); d.append([]const u8, &lines, d.fmt("{d: >3} {s} {s} {s}", .{ i, band, realText(point.upper), realText(point.lower) })); }
        for ([_]usize{ 7, 8 }) |chart| {
            const scale = if (chart == 7) a.ewma_scale else a.ma_scale; const points = if (chart == 7) a.ewma else a.ma;
            d.append([]const u8, &lines, limitText(d.fmt("chart {s}", .{charts[chart]}), .{ .lcl = a.mu - scale, .cl = a.mu, .ucl = a.mu + scale }));
            for (a.groups[a.s.m..]) |group| { const i = group.number; const point = points[i - 1]; const band = plot.widthBand(scale, point.width, point.value, a.mu, a.hasSignal(chart, i, 0)); d.append([]const u8, &lines, d.fmt("{d: >3} {s} {s} {s} {s}", .{ i, band, realText(point.value), realText(a.mu - point.width), realText(a.mu + point.width) })); }
        }
        const names = [_][]const u8{ "P_STD", "NP_STD", "C_STD", "U_STD" };
        for (names, a.attributes) |name, result| { d.append([]const u8, &lines, limitText(d.fmt("chart {s}", .{name}), standard)); for (result.points, 1..) |point, i| { const band = plot.standardBand(point.z, point.status == .ok); d.append([]const u8, &lines, d.fmt("{d: >3} {s} {s}", .{ i, band, realText(point.z) })); } }
        return lines.items;
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); d.allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();
    const settings_text = try cwd.readFileAlloc(init.io, "input/spec.txt", d.allocator, .unlimited);
    const measurements_text = try cwd.readFileAlloc(init.io, "input/measurements.csv", d.allocator, .unlimited);
    const attributes_text = try cwd.readFileAlloc(init.io, "input/attributes.csv", d.allocator, .unlimited);
    const s = d.settings(settings_text); const values = d.measurements(measurements_text);
    var a: Analysis = .{ .s = s, .values = values, .lots = d.attributes(attributes_text), .groups = v.statistics(values, s.n), .constants = d.constants(s.n) };
    for (0..3) |family| a.estimates[family] = a.estimateFamily(family);
    a.monitor(); a.buildEvents(); for (0..4) |chart| a.attributes[chart] = a.estimateAttribute(chart);
    var attribute_lines: std.ArrayList([]const u8) = .empty; for (a.attributes) |result| extend(&attribute_lines, result.lines);
    const names = [_][]const u8{ "limits.txt", "signals.csv", "events.txt", "subgroups.csv", "attribute_charts.txt", "capability.txt", "charts.txt" };
    const outputs = [_]d.Strings{ a.limitsLines(), a.signalLines(), a.eventLines(), a.subgroupLines(), attribute_lines.items, a.capabilityLines(), a.chartLines() };
    try cwd.createDirPath(init.io, "output");
    for (names, outputs) |name, lines| try cwd.writeFile(init.io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = d.fmt("{s}\n", .{d.join(lines, "\n")}) });
}
