const std = @import("std");
const c = @import("dataset.zig");
const estimators = @import("estimators.zig");
const tests = @import("group_tests.zig");
const cox = @import("cox.zig");
const numerics = @import("numerics.zig");
const plot = @import("plot.zig");
fn real(value: f64) []const u8 {
    return c.fmt("{d:.4}", .{if (@abs(value) < 0.00005) @as(f64, 0) else value});
}
fn optional(value: ?i64) []const u8 {
    return if (value) |present| c.fmt("{d}", .{present}) else "NA";
}
fn optionalReal(value: ?f64) []const u8 {
    return if (value) |present| real(present) else "NA";
}
fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
fn paragraph(out: *c.Lines, part: *c.Lines) void {
    if (out.data.items.len > 0) out.add("", .{});
    out.extend(part.*);
    part.* = .{};
}
const Collection = struct { name: []const u8, subjects: c.Subjects, km: []const estimators.KMRow,
     life: []const estimators.LifeRow, events: i64 = 0, maximum: i64 = 0, person_days: i64 = 0, rate: f64 = 0,
     rate_lower: f64 = 0, rate_upper: f64 = 0, rmst: f64 = 0, rmst_se: f64 = 0, followup: ?i64 = null,
     life_median: ?f64 = null, percentiles: [3][3]?i64 = @splat(@splat(null)) };
fn collection(name: []const u8, subjects: c.Subjects, params: c.Params) Collection {
    var out: Collection = .{ .name = name, .subjects = subjects, .km = estimators.kaplanMeier(subjects),
         .life = estimators.lifeTable(subjects, params.life_width, params.life_intervals) };
    const reverse = c.dupe(c.Subject, subjects);
    for (reverse) |*subject| subject.event = 1 - subject.event;
    for (estimators.kaplanMeier(reverse)) |row| if (row.survival <= 0.5) {
        out.followup = row.time;
        break;
    };
    var previous: f64 = 1;
    for (out.life) |row| {
        if (row.survival <= 0.5) {
            out.life_median = c.f(row.a) + c.f(params.life_width) * (previous - 0.5) / (previous - row.survival);
            break;
        }
        previous = row.survival;
    }
    for (subjects) |subject| {
        out.events += subject.event;
        out.maximum = @max(out.maximum, subject.time);
        out.person_days += subject.time;
    }
    out.rate = c.f(1000 * out.events) / c.f(out.person_days);
    const eta = c.normal_z / @sqrt(c.f(out.events));
    out.rate_lower = @exp(@log(out.rate) - eta);
    out.rate_upper = @exp(@log(out.rate) + eta);
    for ([_]f64{ 0.75, 0.5, 0.25 }, 0..) |quantile, q| for (out.km) |row| {
        if (out.percentiles[q][0] == null and row.survival <= quantile) out.percentiles[q][0] = row.time;
        if (out.percentiles[q][1] == null and (row.survival == 0 or row.lower.? <= quantile)) out.percentiles[q][1] = row.time;
        if (out.percentiles[q][2] == null and (row.survival == 0 or row.upper.? <= quantile)) out.percentiles[q][2] = row.time;
    };
    var count: usize = 0;
    while (count < out.km.len and out.km[count].time <= params.tau) count += 1;
    const rectangles = c.alloc(f64, count + 1);
    const tails = c.alloc(f64, count + 1);
    for (0..count + 1) |i| {
        const first = if (i == 0) @as(i64, 0) else out.km[i - 1].time;
        const last = if (i == count) params.tau else out.km[i].time;
        rectangles[i] = (if (i == 0) @as(f64, 1) else out.km[i - 1].survival) * c.f(last - first);
    }
    tails[count] = rectangles[count];
    var remaining = count;
    while (remaining > 0) {
        remaining -= 1;
        tails[remaining] = rectangles[remaining] + tails[remaining + 1];
    }
    out.rmst = tails[0];
    var variance: f64 = 0;
    for (1..count + 1) |i| {
        const row = out.km[i - 1];
        variance += tails[i] * tails[i] * (c.f(row.events) / c.f(row.risk * (row.risk - row.events)));
    }
    out.rmst_se = @sqrt(variance);
    return out;
}
fn kmTables(collections: []const Collection, params: c.Params) c.Lines {
    var out: c.Lines = .{};
    for (collections) |item| {
        var part: c.Lines = .{};
        part.add("group {s} subjects {d} events {d} censored {d} max_time {d}", .{ item.name, item.subjects.len,
             item.events, c.n(item.subjects.len) - item.events, item.maximum });
        part.add("person_days {d} rate {s} lower {s} upper {s}", .{ item.person_days, real(item.rate),
             real(item.rate_lower), real(item.rate_upper) });
        part.add("followup_median {s}", .{optional(item.followup)});
        part.add("life_table_median {s}", .{optionalReal(item.life_median)});
        for (item.percentiles, 1..) |values, q| part.add("percentile {d} time {s} lower {s} upper {s}",
             .{ 25 * q, optional(values[0]), optional(values[1]), optional(values[2]) });
        part.add("rmst tau {d} estimate {s} se {s} lower {s} upper {s}", .{ params.tau, real(item.rmst),
             real(item.rmst_se), real(item.rmst - c.normal_z * item.rmst_se), real(item.rmst + c.normal_z * item.rmst_se) });
        for (params.report_times) |time| {
            const row = estimators.rowAt(item.km, time);
            var events: i64 = 0;
            for (item.subjects) |subject| events += @intFromBool(subject.time <= time and subject.event == 1);
            part.add("at {d} at_risk {d} events {d} survival {s} std_err {s} lower {s} upper {s} cum_hazard {s} hazard_se {s}",
                 .{ time, estimators.riskSize(item.subjects, time), events, real(row.survival), optionalReal(row.std_err),
                 optionalReal(row.lower), optionalReal(row.upper), real(row.hazard), real(row.hazard_se) });
        }
        part.add("{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}", .{ "time",
             "at_risk", "events", "censored", "survival", "std_err", "lower", "upper", "cum_haz",
             "haz_se" });
        for (item.km) |row| part.add("{d: >9}{d: >9}{d: >9}{d: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}{s: >9}",
             .{ row.time, row.risk, row.events, row.censored, real(row.survival), optionalReal(row.std_err),
             optionalReal(row.lower), optionalReal(row.upper), real(row.hazard), real(row.hazard_se) });
        paragraph(&out, &part);
    }
    return out;
}
fn level(subject: c.Subject, variable: []const u8) i64 {
    return if (c.eq(variable, "sex")) @intFromBool(subject.sex == 'M') else subject.stage;
}
fn levelName(value: i64, variable: []const u8) []const u8 {
    return if (c.eq(variable, "sex")) (if (value == 0) "F" else "M") else c.fmt("{d}", .{value});
}
fn levels(subjects: c.Subjects, variable: []const u8) []const i64 {
    var out: std.ArrayList(i64) = .empty;
    for (subjects) |subject| {
        const value = level(subject, variable);
        if (std.mem.indexOfScalar(i64, out.items, value) == null) c.append(i64, &out, value);
    }
    std.mem.sort(i64, out.items, {}, std.sort.asc(i64));
    return out.items;
}
fn selectLevel(subjects: c.Subjects, variable: []const u8, value: i64) c.Subjects {
    var out: std.ArrayList(c.Subject) = .empty;
    for (subjects) |subject| if (level(subject, variable) == value) c.append(c.Subject, &out, subject);
    return out.items;
}
fn selectGroups(subjects: c.Subjects, a: usize, b: usize) c.Subjects {
    var out: std.ArrayList(c.Subject) = .empty;
    for (subjects) |subject| if (subject.group == a or subject.group == b) c.append(c.Subject, &out, subject);
    return out.items;
}
fn groupLines(out: *c.Lines, test_: tests.Test, params: c.Params) void {
    for (test_.groups, 0..) |group, g| out.add("  group {s} events {d} observed {s} expected {s} o_minus_e {s} variance {s}",
         .{ params.groups[group], test_.events[g], real(test_.observed[g]), real(test_.expected[g]),
         real(test_.observed[g] - test_.expected[g]), real(test_.covariance[g][g]) });
}
fn testValues(statistic: f64, degrees: usize) []const u8 {
    return c.fmt("chisq {s} df {d} p {s}", .{ real(statistic), degrees, real(numerics.pValue(statistic, degrees)) });
}
const TwoGroup = struct { test_: tests.Test, hr: f64, lower: f64, upper: f64, phi: f64 };
fn twoGroup(subjects: c.Subjects, a: usize, b: usize, total: usize) TwoGroup {
    const test_ = tests.weighted(subjects, c.dupe(usize, &.{ a, b }), 0, total);
    const hr = (test_.observed[1] / test_.expected[1]) / (test_.observed[0] / test_.expected[0]);
    const phi = 1 / test_.expected[0] + 1 / test_.expected[1];
    const logarithm = @log(hr);
    const se = @sqrt(phi);
    return .{ .test_ = test_, .hr = hr, .phi = phi, .lower = @exp(logarithm - c.normal_z * se), .upper = @exp(logarithm + c.normal_z * se) };
}
fn ageLess(subjects: c.Subjects, a: usize, b: usize) bool {
    return if (subjects[a].age != subjects[b].age) subjects[a].age < subjects[b].age else subjects[a].id < subjects[b].id;
}
const Comparison = struct { a: usize, b: usize, result: TwoGroup, adjusted: f64 = 0 };
fn comparisonLess(pairs: []const Comparison, a: usize, b: usize) bool {
    return if (pairs[a].result.test_.p != pairs[b].result.test_.p) pairs[a].result.test_.p < pairs[b].result.test_.p else a < b;
}
fn groupReport(data: c.Dataset, collections: []const Collection) c.Lines {
    const p = data.params;
    const subjects = data.subjects;
    const groups = p.groups.len;
    const total = subjects.len;
    const group_ids = c.alloc(usize, groups);
    for (group_ids, 0..) |*value, i| value.* = i;
    var out: c.Lines = .{};
    var part: c.Lines = .{};
    part.add("baseline", .{});
    for (collections) |item| {
        var age_sum: i64 = 0;
        var males: usize = 0;
        var stages = std.mem.zeroes([4]usize);
        const ages = c.alloc(i64, item.subjects.len);
        for (item.subjects, ages) |subject, *age| {
            age_sum += subject.age;
            males += @intFromBool(subject.sex == 'M');
            stages[c.u(subject.stage - 1)] += 1;
            age.* = subject.age;
        }
        const count = ages.len;
        const mean = c.f(age_sum) / c.f(count);
        var squares: f64 = 0;
        for (item.subjects) |subject| squares += (c.f(subject.age) - mean) * (c.f(subject.age) - mean);
        std.mem.sort(i64, ages, {}, std.sort.asc(i64));
        const median = c.f(ages[(count - 1) / 2] + ages[count / 2]) / 2;
        part.add("  group {s} subjects {d} age_mean {s} age_sd {s} age_median {d:.1} male {d} stage {d} {d} {d} {d}",
             .{ item.name, count, real(mean), real(@sqrt(squares / c.f(count - 1))), median, males,
             stages[0], stages[1], stages[2], stages[3] });
    }
    const age_order = c.alloc(usize, total);
    for (age_order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, age_order, subjects, ageLess);
    const ranks = c.alloc(f64, total);
    var tied: i64 = 0;
    var first: usize = 0;
    while (first < total) {
        var end = first + 1;
        while (end < total and subjects[age_order[end]].age == subjects[age_order[first]].age) end += 1;
        const rank = c.f(first + 1 + end) / 2;
        for (age_order[first..end]) |index| ranks[index] = rank;
        const count = c.n(end - first);
        tied += count * count * count - count;
        first = end;
    }
    var rank_sums = std.mem.zeroes(c.Vector);
    for (subjects, ranks) |subject, rank| rank_sums[subject.group] += rank;
    var sum: f64 = 0;
    for (0..groups) |g| sum += rank_sums[g] * rank_sums[g] / c.f(collections[g].subjects.len);
    const initial = 12 * sum / c.f(total * (total + 1)) - c.f(3 * (total + 1));
    const kw = initial / (1 - c.f(tied) / c.f(total * total * total - total));
    part.add("  age kruskal_wallis {s}", .{testValues(kw, groups - 1)});
    for ([_][]const u8{ "sex", "stage" }) |variable| {
        const values = levels(subjects, variable);
        var counts = std.mem.zeroes([6][4]usize);
        var columns = std.mem.zeroes([4]usize);
        for (subjects) |subject| {
            const j = std.mem.indexOfScalar(i64, values, level(subject, variable)).?;
            counts[subject.group][j] += 1;
            columns[j] += 1;
        }
        var statistic: f64 = 0;
        for (0..groups) |g| for (0..values.len) |j| {
            const expected = c.f(collections[g].subjects.len * columns[j]) / c.f(total);
            statistic += (c.f(counts[g][j]) - expected) * (c.f(counts[g][j]) - expected) / expected;
        };
        part.add("  {s} {s}", .{ variable, testValues(statistic, (groups - 1) * (values.len - 1)) });
    }
    paragraph(&out, &part);
    const weights = [_][]const u8{ "logrank", "gehan_wilcoxon", "tarone_ware" };
    var overall: [3]tests.Test = undefined;
    for (weights, 0..) |weight, kind| {
        overall[kind] = tests.weighted(subjects, group_ids, kind, total);
        part.add("test {s} {s}", .{ weight, testValues(overall[kind].statistic, overall[kind].degrees) });
        groupLines(&part, overall[kind], p);
    }
    var trend_u: f64 = 0;
    var trend_v: f64 = 0;
    for (0..groups) |g| {
        trend_u += c.f(g + 1) * (overall[0].observed[g] - overall[0].expected[g]);
        var inner: f64 = 0;
        for (0..groups) |h| inner += c.f((g + 1) * (h + 1)) * overall[0].covariance[g][h];
        trend_v += inner;
    }
    part.add("test logrank_trend {s}", .{testValues(trend_u * trend_u / trend_v, 1)});
    paragraph(&out, &part);
    const strata = levels(subjects, p.strata);
    for (weights, 0..) |weight, kind| {
        const stratum_tests = c.alloc(tests.Test, strata.len);
        const sets = c.alloc(c.Subjects, strata.len);
        for (strata, 0..) |value, i| {
            sets[i] = selectLevel(subjects, p.strata, value);
            stratum_tests[i] = tests.weighted(sets[i], group_ids, kind, total);
        }
        const combined = tests.combine(stratum_tests);
        part.add("stratified {s} by {s} {s}", .{ weight, p.strata, testValues(combined.statistic, combined.degrees) });
        for (strata, 0..) |value, i| {
            var events: i64 = 0;
            for (sets[i]) |subject| events += subject.event;
            part.add("  stratum {s} subjects {d} events {d} chisq {s} p {s}", .{ levelName(value,
                 p.strata), sets[i].len, events, real(stratum_tests[i].statistic), real(stratum_tests[i].p) });
        }
        groupLines(&part, combined, p);
    }
    paragraph(&out, &part);
    var landmark: std.ArrayList(c.Subject) = .empty;
    for (subjects) |subject| if (subject.time > p.landmark) c.append(c.Subject, &landmark, subject);
    const landmark_test = tests.weighted(landmark.items, group_ids, 0, total);
    part.add("landmark {d} subjects {d} {s}", .{ p.landmark, landmark.items.len, testValues(landmark_test.statistic,
         landmark_test.degrees) });
    groupLines(&part, landmark_test, p);
    paragraph(&out, &part);
    var pairs: std.ArrayList(Comparison) = .empty;
    for (0..groups) |a| for (a + 1..groups) |b| c.append(Comparison, &pairs, .{ .a = a, .b = b, .result = twoGroup(selectGroups(subjects,
         a, b), a, b, total) });
    const order = c.alloc(usize, pairs.items.len);
    for (order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, order, @as([]const Comparison, pairs.items), comparisonLess);
    var adjusted: f64 = 0;
    for (order, 0..) |index, r| {
        adjusted = @max(adjusted, @min(@as(f64, 1), c.f(order.len - r) * pairs.items[index].result.test_.p));
        pairs.items[index].adjusted = adjusted;
    }
    part.add("pairwise logrank adjust holm", .{});
    for (pairs.items) |pair| part.add("  {s} {s} chisq {s} p {s} p_holm {s} hr {s} lower {s} upper {s}",
         .{ p.groups[pair.a], p.groups[pair.b], real(pair.result.test_.statistic), real(pair.result.test_.p),
         real(pair.adjusted), real(pair.result.hr), real(pair.result.lower), real(pair.result.upper) });
    paragraph(&out, &part);
    part.add("subgroups reference {s}", .{p.groups[0]});
    for (p.subgroups) |variable| {
        const values = levels(subjects, variable);
        for (1..groups) |b| {
            const weights_ = c.alloc(f64, values.len);
            const logarithms = c.alloc(f64, values.len);
            var numerator: f64 = 0;
            var denominator: f64 = 0;
            for (values, 0..) |value, i| {
                const selected = selectGroups(selectLevel(subjects, variable, value), 0, b);
                const comparison = twoGroup(selected, 0, b, total);
                var events: i64 = 0;
                for (selected) |subject| events += subject.event;
                part.add("  {s} {s} {s} subjects {d} events {d} hr {s} lower {s} upper {s} p {s}",
                     .{ variable, levelName(value, variable), p.groups[b], selected.len, events, real(comparison.hr),
                     real(comparison.lower), real(comparison.upper), real(comparison.test_.p) });
                weights_[i] = 1 / comparison.phi;
                logarithms[i] = @log(comparison.hr);
                numerator += weights_[i] * logarithms[i];
                denominator += weights_[i];
            }
            const mean = numerator / denominator;
            var heterogeneity: f64 = 0;
            for (weights_, logarithms) |weight, logarithm| heterogeneity += weight * (logarithm - mean) * (logarithm - mean);
            part.add("  {s} {s} heterogeneity {s}", .{ variable, p.groups[b], testValues(heterogeneity, values.len - 1) });
        }
    }
    paragraph(&out, &part);
    part.add("rmst_difference tau {d} reference {s}", .{ p.tau, p.groups[0] });
    for (1..groups) |g| {
        const difference = collections[g].rmst - collections[0].rmst;
        const se = @sqrt(collections[g].rmst_se * collections[g].rmst_se + collections[0].rmst_se * collections[0].rmst_se);
        const statistic = difference / se;
        part.add("  {s} difference {s} se {s} lower {s} upper {s} z {s} p {s}", .{ p.groups[g], real(difference),
             real(se), real(difference - c.normal_z * se), real(difference + c.normal_z * se), real(statistic),
             real(numerics.pValue(statistic * statistic, 1)) });
    }
    paragraph(&out, &part);
    part.add("rate_ratio reference {s}", .{p.groups[0]});
    for (1..groups) |g| {
        const ratio = collections[g].rate / collections[0].rate;
        const se = @sqrt(1 / c.f(collections[g].events) + 1 / c.f(collections[0].events));
        const logarithm = @log(ratio);
        const statistic = logarithm / se;
        part.add("  {s} ratio {s} lower {s} upper {s} z {s} p {s}", .{ p.groups[g], real(ratio), real(@exp(logarithm - c.normal_z * se)),
             real(@exp(logarithm + c.normal_z * se)), real(statistic), real(numerics.pValue(statistic * statistic,
             1)) });
    }
    paragraph(&out, &part);
    part.add("survival_difference reference {s}", .{p.groups[0]});
    for (p.report_times) |time| for (1..groups) |g| {
        const first_ = estimators.rowAt(collections[0].km, time);
        const second = estimators.rowAt(collections[g].km, time);
        const difference = second.survival - first_.survival;
        const se = @sqrt(second.std_err.? * second.std_err.? + first_.std_err.? * first_.std_err.?);
        const statistic = difference / se;
        part.add("  at {d} {s} difference {s} se {s} lower {s} upper {s} z {s} p {s}", .{ time, p.groups[g],
             real(difference), real(se), real(difference - c.normal_z * se), real(difference + c.normal_z * se),
             real(statistic), real(numerics.pValue(statistic * statistic, 1)) });
    };
    paragraph(&out, &part);
    return out;
}
fn coefficient(prefix: []const u8, value: f64, se: f64) []const u8 {
    const statistic = value / se;
    return c.fmt("{s} coef {s} se {s} z {s} p {s} hr {s} lower {s} upper {s}", .{ prefix, real(value),
         real(se), real(statistic), real(numerics.pValue(statistic * statistic, 1)), real(@exp(value)),
         real(@exp(value - c.normal_z * se)), real(@exp(value + c.normal_z * se)) });
}
fn cumulative(times: []const cox.Time, baseline: []const f64, time: i64) f64 {
    var value: f64 = 0;
    for (times, baseline) |entry, hazard| {
        if (entry.time > time) break;
        value = hazard;
    }
    return value;
}
fn eventLess(subjects: c.Subjects, a: usize, b: usize) bool {
    return if (subjects[a].time != subjects[b].time) subjects[a].time < subjects[b].time else subjects[a].id < subjects[b].id;
}
const Residual = struct { subject: usize, martingale: f64, deviance: f64 };
fn residualLess(subjects: c.Subjects, a: Residual, b: Residual) bool {
    return if (@abs(a.deviance) != @abs(b.deviance)) @abs(a.deviance) > @abs(b.deviance) else subjects[a.subject].id < subjects[b.subject].id;
}
fn coxReport(data: c.Dataset) c.Lines {
    const subjects = data.subjects;
    const p = data.params;
    const size = p.covariates.len;
    const count = subjects.len;
    const design = c.alloc(c.Vector, count);
    @memset(design, std.mem.zeroes(c.Vector));
    const group_term = c.alloc(bool, size);
    for (p.covariates, 0..) |name, column| {
        group_term[column] = !c.eq(name, "age") and !c.eq(name, "male") and !c.eq(name, "stage");
        var group: usize = 0;
        if (group_term[column]) while (!c.eq(p.groups[group], name)) {
            group += 1;
        };
        for (subjects, design) |subject, *values| values[column] = if (c.eq(name, "age")) c.f(subject.age) else if (c.eq(name,
             "male")) c.f(@intFromBool(subject.sex == 'M')) else if (c.eq(name, "stage")) c.f(subject.stage) else c.f(@intFromBool(subject.group == group));
    }
    const fit = cox.fit(subjects, design, size);
    const covariance = numerics.inverse(fit.final.information, size);
    var events: i64 = 0;
    for (subjects) |subject| events += subject.event;
    var header: c.Text = .{};
    header.add("cox covariates", .{});
    for (p.covariates) |name| header.add(" {s}", .{name});
    header.add(" subjects {d} events {d} event_times {d}", .{ count, events, fit.final.times.items.len });
    var out: c.Lines = .{};
    out.add("{s}", .{header.value()});
    for (fit.iterations, 1..) |iteration, i| {
        var line: c.Text = .{};
        line.add("iter {d} loglik {s} beta", .{ i, real(iteration.loglik) });
        for (iteration.beta[0..size]) |value| line.add(" {s}", .{real(value)});
        out.add("{s}", .{line.value()});
    }
    out.add("final loglik {s} null_loglik {s}", .{ real(fit.final.loglik), real(fit.initial.loglik) });
    for (p.covariates, 0..) |name, column| out.add("{s}", .{coefficient(c.fmt("term {s}", .{name}),
         fit.beta[column], @sqrt(covariance[column][column]))});
    for (0..size) |a| if (group_term[a]) {
        for (a + 1..size) |b| if (group_term[b]) out.add("{s}", .{coefficient(c.fmt("contrast {s} vs {s}",
             .{ p.covariates[b], p.covariates[a] }), fit.beta[b] - fit.beta[a], @sqrt(covariance[b][b] + covariance[a][a] - 2 * covariance[a][b]))});
    };
    const likelihood = 2 * (fit.final.loglik - fit.initial.loglik);
    var wald: f64 = 0;
    for (0..size) |column| {
        var sum: f64 = 0;
        for (0..size) |d| sum += fit.final.information[column][d] * fit.beta[d];
        wald += fit.beta[column] * sum;
    }
    const score_solution = numerics.solve(fit.initial.information, fit.initial.score, size);
    var score: f64 = 0;
    for (0..size) |column| score += fit.initial.score[column] * score_solution[column];
    out.add("likelihood_ratio {s}", .{testValues(likelihood, size)});
    out.add("wald {s}", .{testValues(wald, size)});
    out.add("score {s}", .{testValues(score, size)});
    for (p.covariates, 0..) |name, column| {
        var loglik = fit.initial.loglik;
        if (size >= 2) {
            const reduced = c.alloc(c.Vector, count);
            @memset(reduced, std.mem.zeroes(c.Vector));
            for (design, reduced) |values, *row| {
                var index: usize = 0;
                for (0..size) |d| if (d != column) {
                    row[index] = values[d];
                    index += 1;
                };
            }
            loglik = cox.fit(subjects, reduced, size - 1).final.loglik;
        }
        const statistic = 2 * (fit.final.loglik - loglik);
        out.add("drop {s} loglik {s} chisq {s} df 1 p {s}", .{ name, real(loglik), real(statistic),
             real(numerics.pValue(statistic, 1)) });
    }
    var comparable: usize = 0;
    var concordant: usize = 0;
    var tied: usize = 0;
    for (subjects, 0..) |first, i| if (first.event == 1) {
        for (subjects, 0..) |second, j| if (i != j and (first.time < second.time or (first.time == second.time and second.event == 0))) {
            comparable += 1;
            const equal = std.mem.eql(f64, design[i][0..size], design[j][0..size]);
            if (equal) tied += 1 else if (fit.final.theta[i] > fit.final.theta[j]) concordant += 1;
        };
    };
    out.add("concordance {s} comparable {d} concordant {d} tied {d}", .{ real(c.f(2 * concordant + tied) / c.f(2 * comparable)),
         comparable, concordant, tied });
    const times = c.dupe(cox.Time, fit.final.times.items);
    std.mem.reverse(cox.Time, times);
    var event_order: std.ArrayList(usize) = .empty;
    for (subjects, 0..) |subject, i| if (subject.event == 1) c.append(usize, &event_order, i);
    std.mem.sort(usize, event_order.items, subjects, eventLess);
    var time_sum: i64 = 0;
    for (event_order.items) |i| time_sum += subjects[i].time;
    const time_mean = c.f(time_sum) / c.f(event_order.items.len);
    for (p.covariates, 0..) |name, column| {
        const residuals = c.alloc(f64, event_order.items.len);
        var sum: f64 = 0;
        for (event_order.items, residuals) |i, *value| {
            var at: usize = 0;
            while (times[at].time != subjects[i].time) at += 1;
            value.* = design[i][column] - times[at].s1[column] / times[at].s0;
            sum += value.*;
        }
        const mean = sum / c.f(event_order.items.len);
        var sxy: f64 = 0;
        var sxx: f64 = 0;
        var syy: f64 = 0;
        for (event_order.items, residuals) |i, residual| {
            const x = residual - mean;
            const y = c.f(subjects[i].time) - time_mean;
            sxy += x * y;
            sxx += x * x;
            syy += y * y;
        }
        const rho = sxy / @sqrt(sxx * syy);
        const statistic = 0.5 * @log((1 + rho) / (1 - rho)) * @sqrt(c.f(event_order.items.len - 3));
        out.add("ph_check {s} rho {s} z {s} p {s}", .{ name, real(rho), real(statistic), real(numerics.pValue(statistic * statistic,
             1)) });
    }
    const baseline = c.alloc(f64, times.len);
    var hazard: f64 = 0;
    for (times, baseline) |time, *value| {
        hazard += c.f(time.events) / time.s0;
        value.* = hazard;
    }
    const residuals = c.alloc(Residual, count);
    for (subjects, residuals, 0..) |subject, *residual, j| {
        const martingale = c.f(subject.event) - cumulative(times, baseline, subject.time) * @exp(fit.final.theta[j]);
        var deviance = if (subject.event == 1) @sqrt(-2 * (martingale + @log(1 - martingale))) else @sqrt(-2 * martingale);
        if (!(martingale > 0)) deviance = -deviance;
        residual.* = .{ .subject = j, .martingale = martingale, .deviance = deviance };
    }
    std.mem.sort(Residual, residuals, subjects, residualLess);
    out.add("residuals top {d}", .{p.residuals});
    for (residuals[0..p.residuals]) |residual| {
        const subject = subjects[residual.subject];
        out.add("  id {d} group {s} time {d} event {d} martingale {s} deviance {s}", .{ subject.id,
             p.groups[subject.group], subject.time, subject.event, real(residual.martingale), real(residual.deviance) });
    }
    var means = std.mem.zeroes(c.Vector);
    var mean_line: c.Text = .{};
    mean_line.add("adjusted_survival mean", .{});
    var any = false;
    for (p.covariates, 0..) |name, column| if (!group_term[column]) {
        var sum: i64 = 0;
        for (design) |values| sum += @intFromFloat(values[column]);
        means[column] = c.f(sum) / c.f(count);
        mean_line.add(" {s} {s}", .{ name, real(means[column]) });
        any = true;
    };
    if (!any) mean_line.add(" none", .{});
    out.add("{s}", .{mean_line.value()});
    const group_risks = c.alloc(f64, p.groups.len);
    for (p.groups, group_risks) |name, *risk| {
        var predictor: f64 = 0;
        for (p.covariates, 0..) |covariate, column| {
            const value = if (group_term[column]) c.f(@intFromBool(c.eq(name, covariate))) else means[column];
            predictor += fit.beta[column] * value;
        }
        risk.* = @exp(predictor);
    }
    for (p.report_times) |time| {
        var line: c.Text = .{};
        line.add("  at {d}", .{time});
        for (p.groups, group_risks) |name, risk| line.add(" {s} {s}", .{ name, real(@exp(-cumulative(times,
             baseline, time) * risk)) });
        out.add("{s}", .{line.value()});
    }
    var median_line: c.Text = .{};
    median_line.add("  median", .{});
    for (p.groups, group_risks) |name, risk| {
        var median: ?i64 = null;
        for (times, baseline) |time, value| if (@exp(-value * risk) <= 0.5) {
            median = time.time;
            break;
        };
        median_line.add(" {s} {s}", .{ name, optional(median) });
    }
    out.add("{s}", .{median_line.value()});
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const data = try c.readDataset(init.io);
    var collections: std.ArrayList(Collection) = .empty;
    for (data.params.groups, 0..) |name, group| {
        var subjects: std.ArrayList(c.Subject) = .empty;
        for (data.subjects) |subject| if (subject.group == group) c.append(c.Subject, &subjects, subject);
        c.append(Collection, &collections, collection(name, subjects.items, data.params));
    }
    c.append(Collection, &collections, collection("all", data.subjects, data.params));
    try write(init.io, "km_tables.txt", kmTables(collections.items, data.params));
    var life: c.Lines = .{};
    life.add("group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard", .{});
    for (collections.items) |item| for (item.life) |row| life.add("{s},{d}-{d},{d},{d},{d},{d:.1},{s},{s},{s},{s}",
         .{ item.name, row.a, row.b, row.risk, row.events, row.withdrawn, c.f(row.exposure2) / 2,
         real(row.probability), real(row.survival), real(row.std_err), real(row.hazard) });
    try write(init.io, "life_table.csv", life);
    try write(init.io, "tests.txt", groupReport(data, collections.items));
    try write(init.io, "cox.txt", coxReport(data));
    const curves = c.alloc([]const estimators.KMRow, data.params.groups.len);
    const maximums = c.alloc(i64, data.params.groups.len);
    for (collections.items[0..data.params.groups.len], curves, maximums) |item, *curve, *maximum| {
        curve.* = item.km;
        maximum.* = item.maximum;
    }
    var chart = plot.curves(curves, maximums, data.params);
    var risk_line: c.Text = .{};
    risk_line.add("at_risk", .{});
    for (0..data.params.plot_divisions + 1) |i| risk_line.add(" {d}", .{c.n(i) * @divFloor(data.params.plot_time,
         c.n(data.params.plot_divisions))});
    chart.add("{s}", .{risk_line.value()});
    for (collections.items[0..data.params.groups.len]) |item| {
        var line: c.Text = .{};
        line.add("{s}", .{item.name});
        for (0..data.params.plot_divisions + 1) |i| line.add(" {d}", .{estimators.riskSize(item.subjects,
             c.n(i) * @divFloor(data.params.plot_time, c.n(data.params.plot_divisions)))});
        chart.add("{s}", .{line.value()});
    }
    try write(init.io, "km_plot.txt", chart);
}
