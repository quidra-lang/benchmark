const std = @import("std");
const d = @import("data_io.zig");
const m = @import("models.zig");
const integration = @import("integrator.zig");
const fitting = @import("fitting.zig");
const report = @import("report.zig");
const real = report.real;
const f = d.f;
fn multipliers(lines: []const d.Intervention, count: usize) []const f64 {
    const out = d.alloc(f64, count);
    var index: usize = 0;
    for (out, 1..) |*value, day| {
        while (index + 1 < lines.len and lines[index + 1].day <= day) index += 1;
        value.* = lines[index].multiplier;
    }
    return out;
}
const Laboratory = struct {
    input: d.Input,
    population: i64 = 0,
    fatality: f64 = 0,
    kbar: f64 = 0,
    contacts: [6][6]f64 = std.mem.zeroes([6][6]f64),
    multiplier: []const f64 = &.{},
    fn init(input: d.Input) Laboratory {
        var out: Laboratory = .{ .input = input };
        for (input.groups) |group| {
            out.population += group.population;
            out.fatality += f(group.population) * group.fatality;
        }
        out.fatality /= f(out.population);
        for (input.groups, 0..) |group, g| {
            var sum: f64 = 0;
            for (0..input.groups.len) |h| sum += input.contacts[g][h];
            out.kbar += f(group.population) * sum;
        }
        out.kbar /= f(out.population);
        for (0..input.groups.len) |g| for (0..input.groups.len) |h| {
            out.contacts[g][h] = input.contacts[g][h] / out.kbar;
        };
        out.multiplier = multipliers(input.interventions, input.cases.len);
        return out;
    }
    fn model(self: *const Laboratory, kind: m.Kind, beta: f64, gamma: f64, sigma: f64) m.Model {
        return .{ .kind = kind, .beta = beta, .gamma = gamma, .sigma = sigma, .population = f(self.population),
             .fatality = self.fatality, .e0 = self.input.params.e0, .i0 = self.input.params.i0,
             .groups = self.input.groups, .contacts = self.contacts };
    }
    fn incidence(self: *const Laboratory, beta: f64, gamma: f64, sigma: f64, sequence: []const f64) []const f64 {
        const model = self.model(.seird, beta, gamma, sigma);
        return series(model, integration.trajectory(model, sequence));
    }
    fn objective(self: *const Laboratory, beta: f64, gamma: f64, rho: f64) f64 {
        return errors(self.incidence(beta, gamma, self.input.params.sigma, self.multiplier), rho, self.input.cases);
    }
};
fn series(model: m.Model, states: []const m.State) []const f64 {
    const out = d.alloc(f64, states.len);
    for (states, out) |state, *value| {
        value.* = 0;
        if (model.kind == .age) {
            for (0..model.groups.len) |g| value.* += state.values[6 * g + 5];
        } else value.* = state.values[if (model.kind == .generation) @as(usize, 2) else if (model.kind == .sir) @as(usize,
             3) else 5];
    }
    return out;
}
fn errors(values: []const f64, coefficient: f64, observations: []const i64) f64 {
    var out: f64 = 0;
    for (values, 0..) |value, i| {
        const difference = coefficient * value - f(observations[i]);
        out += difference * difference;
    }
    return out;
}
fn rmse(value: f64, count: usize) f64 {
    return @sqrt(value / f(count));
}
fn total(values: []const f64) f64 {
    var out: f64 = 0;
    for (values) |value| out += value;
    return out;
}
fn peak(values: []const f64) usize {
    var out: usize = 0;
    for (values, 0..) |value, i| {
        if (value > values[out]) out = i;
    }
    return out;
}
fn reported(values: []const f64, rho: f64) []const f64 {
    const out = d.alloc(f64, values.len);
    for (values, out) |value, *destination| destination.* = rho * value;
    return out;
}
const Search = struct {
    lab: *const Laboratory,
    beta: f64 = 0,
    gamma: f64 = 0,
    rho: f64 = 0,
    sigma: f64 = 0,
    sequence: []const f64 = &.{},
    cached: ?[]const f64 = null,
    parameter: usize = 0,
    kind: m.Kind = .seird,
    effect: ?usize = null,
    interventions: []const d.Intervention = &.{},
    fn value(self: Search, x: f64) f64 {
        if (self.effect) |index| {
            const lines = d.dupe(d.Intervention, self.interventions);
            lines[index].multiplier = x;
            return errors(self.lab.incidence(self.beta, self.gamma, self.sigma, multipliers(lines,
                 self.sequence.len)), self.rho, self.lab.input.cases);
        }
        var beta = self.beta;
        var gamma = self.gamma;
        var rho = self.rho;
        switch (self.parameter) {
            0 => beta = x,
            1 => gamma = x,
            else => rho = x,
        }
        if (self.cached) |values| return errors(values, rho, self.lab.input.cases);
        const model = self.lab.model(self.kind, beta, gamma, self.sigma);
        return errors(series(model, integration.trajectory(model, self.sequence)), rho, self.lab.input.cases);
    }
    fn simplex(self: Search, point: fitting.Point) f64 {
        return self.lab.objective(point[0], point[1], self.rho);
    }
};
fn goldenReport(lines: *d.Lines, search: fitting.Golden, round: usize, name: []const u8, days: usize) void {
    for (search.records, 0..) |record, i| lines.add("golden {d} {s} {d} a {s} b {s} c {s} d {s} rmse {s} {s}",
         .{ round, name, i, real(record.a, 6), real(record.b, 6), real(record.c, 6), real(record.d,
         6), real(rmse(record.fc, days), 4), real(rmse(record.fd, days), 4) });
    lines.add("golden_result {d} {s} {s} sse {s}", .{ round, name, real(search.point, 6), real(search.value, 1) });
}
fn finalSize(r: f64) f64 {
    if (r <= 1) return 0;
    var lo = 1 - 1 / r;
    var hi: f64 = 1;
    for (0..20) |_| {
        const mid = (lo + hi) / 2;
        const value = 1 - mid - @exp(-r * mid);
        if (value > 0) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}
const Eigen = struct { value: f64 = 0, vector: [6]f64 = [_]f64{0} ** 6 };
fn largest(matrix: [6][6]f64, count: usize) Eigen {
    var out: Eigen = .{};
    for (0..count) |g| out.vector[g] = 1 / f(count);
    for (0..200) |_| {
        var next: [6]f64 = [_]f64{0} ** 6;
        for (0..count) |g| for (0..count) |h| {
            next[g] += matrix[g][h] * out.vector[h];
        };
        out.value = total(next[0..count]);
        for (0..count) |g| out.vector[g] = next[g] / out.value;
    }
    return out;
}
fn nextGeneration(lab: *const Laboratory, contacts: [6][6]f64, r0: f64) [6][6]f64 {
    var out: [6][6]f64 = std.mem.zeroes([6][6]f64);
    for (lab.input.groups, 0..) |group, g| for (lab.input.groups, 0..) |other, h| {
        out[g][h] = r0 * contacts[g][h] * f(group.population) / f(other.population);
    };
    return out;
}
fn ageDeaths(state: m.State, groups: usize) f64 {
    var out: f64 = 0;
    for (0..groups) |g| out += state.values[6 * g + 4];
    return out;
}
fn stage(lines: *d.Lines, name: []const u8, beta: f64, gamma: f64, rho: f64, sse: f64, days: usize) void {
    lines.add("stage {s} beta {s} gamma {s} rho {s} r0 {s} rmse {s}", .{ name, real(beta, 6),
         real(gamma, 6), real(rho, 6), real(beta / gamma, 4), real(rmse(sse, days), 4) });
}
fn compareModel(lines: *d.Lines, name: []const u8, values: []const f64, input: d.Input, rho: f64) void {
    var cross: f64 = 0;
    var square: f64 = 0;
    for (values, input.cases) |value, observed| {
        cross += f(observed) * value;
        square += value * value;
    }
    const optimal = cross / square;
    lines.add("model {s} rmse {s} peak_day {d} rho_opt {s} rmse_opt {s}", .{ name, real(rmse(errors(values,
         rho, input.cases), values.len), 4), peak(values) + 1, real(optimal, 6), real(rmse(errors(values,
         optimal, input.cases), values.len), 4) });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const io = init.io;
    try std.Io.Dir.cwd().createDirPath(io, "output");
    const input = try d.load(io);
    const p = input.params;
    const lab = Laboratory.init(input);
    const days = input.cases.len;
    const groups = input.groups.len;
    var cases_total: i64 = 0;
    var deaths_total: i64 = 0;
    for (input.cases, input.deaths) |cases, deaths| {
        cases_total += cases;
        deaths_total += deaths;
    }
    var fit: d.Lines = .{};
    fit.add("data days {d} cases {d} deaths {d} population {d} fatality {s}", .{ days, cases_total,
         deaths_total, lab.population, real(lab.fatality, 6) });
    const beta_grid = d.alloc(f64, p.beta_count);
    const rho_grid = d.alloc(f64, p.rho_count);
    for (beta_grid, 0..) |*value, i| value.* = p.beta_min + (p.beta_max - p.beta_min) * f(i) / f(p.beta_count - 1);
    for (rho_grid, 0..) |*value, j| value.* = p.rho_min + (p.rho_max - p.rho_min) * f(j) / f(p.rho_count - 1);
    const beta_spacing = (p.beta_max - p.beta_min) / f(p.beta_count - 1);
    const rho_spacing = (p.rho_max - p.rho_min) / f(p.rho_count - 1);
    var heading: d.Text = .{};
    heading.add("grid gamma {s} rho", .{real(p.gamma, 4)});
    for (rho_grid) |value| heading.add(" {s}", .{real(value, 4)});
    fit.add("{s}", .{heading.value()});
    var grid_sse = std.math.inf(f64);
    var grid_beta: f64 = 0;
    var grid_rho: f64 = 0;
    for (beta_grid) |beta| {
        const values = lab.incidence(beta, p.gamma, p.sigma, lab.multiplier);
        var row: d.Text = .{};
        row.add("grid beta {s} rmse", .{real(beta, 4)});
        for (rho_grid) |rho| {
            const value = errors(values, rho, input.cases);
            row.add(" {s}", .{real(rmse(value, days), 2)});
            if (value < grid_sse) {
                grid_sse = value;
                grid_beta = beta;
                grid_rho = rho;
            }
        }
        fit.add("{s}", .{row.value()});
    }
    fit.add("grid_best beta {s} rho {s} sse {s} rmse {s}", .{ real(grid_beta, 4), real(grid_rho,
         4), real(grid_sse, 1), real(rmse(grid_sse, days), 4) });
    var beta_golden = grid_beta;
    var rho_hat = grid_rho;
    var golden_sse = grid_sse;
    var search: Search = .{ .lab = &lab, .gamma = p.gamma, .sigma = p.sigma, .sequence = lab.multiplier };
    for (1..p.rounds + 1) |round| {
        search.rho = rho_hat;
        search.parameter = 0;
        search.cached = null;
        const beta = fitting.golden(search, Search.value, beta_golden - beta_spacing, beta_golden + beta_spacing,
             p.golden);
        goldenReport(&fit, beta, round, "beta", days);
        beta_golden = beta.point;
        search.beta = beta_golden;
        search.parameter = 2;
        search.cached = lab.incidence(beta_golden, p.gamma, p.sigma, lab.multiplier);
        const rho = fitting.golden(search, Search.value, rho_hat - rho_spacing, rho_hat + rho_spacing, p.golden);
        goldenReport(&fit, rho, round, "rho", days);
        rho_hat = rho.point;
        golden_sse = rho.value;
    }
    search.rho = rho_hat;
    const simplex = fitting.nelderMead(search, Search.simplex, .{ beta_golden, p.gamma }, p);
    for (simplex.initial) |vertex| fit.add("simplex {d} beta {s} gamma {s} rmse {s}", .{ vertex.number,
         real(vertex.point[0], 6), real(vertex.point[1], 6), real(rmse(vertex.value, days),
         4) });
    for (simplex.records, 1..) |record, i| fit.add("nelder_mead {d} {s} beta {s} gamma {s} rmse {s}",
         .{ i, record.operation, real(record.best.point[0], 6), real(record.best.point[1],
         6), real(rmse(record.best.value, days), 4) });
    for (simplex.final, 1..) |vertex, rank| fit.add("final_simplex {d} beta {s} gamma {s} rmse {s}",
         .{ rank, real(vertex.point[0], 6), real(vertex.point[1], 6), real(rmse(vertex.value,
         days), 4) });
    const beta_hat = simplex.final[0].point[0];
    const gamma_hat = simplex.final[0].point[1];
    const nm_sse = simplex.final[0].value;
    const r0 = beta_hat / gamma_hat;
    const model = lab.model(.seird, beta_hat, gamma_hat, p.sigma);
    const fitted = integration.trajectory(model, lab.multiplier);
    const infections = series(model, fitted);
    const predicted = reported(infections, rho_hat);
    const residuals = d.alloc(f64, days);
    const deaths = d.alloc(f64, days);
    const average = d.alloc(f64, days);
    const rt = d.alloc(f64, days);
    const infectious = d.alloc(f64, days);
    const cumulative_fitted = d.alloc(f64, days);
    const cumulative_observed = d.alloc(i64, days);
    var cumulative: i64 = 0;
    var cumulative_reported: f64 = 0;
    var sst: f64 = 0;
    var residual_sum: f64 = 0;
    var absolute: f64 = 0;
    var square_residual: f64 = 0;
    var dw: f64 = 0;
    const mean = f(cases_total) / f(days);
    var max_residual: usize = 0;
    var positive: usize = 0;
    var runs: usize = 1;
    for (0..days) |day| {
        residuals[day] = f(input.cases[day]) - predicted[day];
        residual_sum += residuals[day];
        absolute += @abs(residuals[day]);
        square_residual += residuals[day] * residuals[day];
        if (@abs(residuals[day]) > @abs(residuals[max_residual])) max_residual = day;
        positive += @intFromBool(residuals[day] > 0);
        if (day > 0) {
            const difference = residuals[day] - residuals[day - 1];
            dw += difference * difference;
            runs += @intFromBool((residuals[day] > 0) != (residuals[day - 1] > 0));
        }
        const centered = f(input.cases[day]) - mean;
        sst += centered * centered;
        deaths[day] = fitted[day].values[4] - (if (day > 0) fitted[day - 1].values[4] else @as(f64, 0));
        rt[day] = r0 * lab.multiplier[day] * (if (day > 0) fitted[day - 1].values[0] else model.initial().values[0]) / f(lab.population);
        infectious[day] = fitted[day].values[2];
        var week: i64 = 0;
        for (input.cases[day + 1 - @min(day + 1, 7) .. day + 1]) |value| week += value;
        average[day] = f(week) / f(@min(day + 1, 7));
        cumulative += input.cases[day];
        cumulative_observed[day] = cumulative;
        cumulative_reported += predicted[day];
        cumulative_fitted[day] = cumulative_reported;
    }
    fit.add("fitted beta {s} gamma {s} rho {s} sigma {s} r0 {s}", .{ real(beta_hat, 6), real(gamma_hat,
         6), real(rho_hat, 6), real(p.sigma, 6), real(r0, 4) });
    fit.add("sse grid {s} golden {s} nelder_mead {s} rmse {s} r2 {s}", .{ real(grid_sse, 1),
         real(golden_sse, 1), real(nm_sse, 1), real(rmse(nm_sse, days), 4), real(1 - nm_sse / sst,
         4) });
    stage(&fit, "grid", grid_beta, p.gamma, grid_rho, grid_sse, days);
    stage(&fit, "golden", beta_golden, p.gamma, rho_hat, golden_sse, days);
    stage(&fit, "nelder_mead", beta_hat, gamma_hat, rho_hat, nm_sse, days);
    fit.add("residuals sum {s} mae {s} max {s} day {d} positive {d} runs {d} durbin_watson {s}",
         .{ real(residual_sum, 1), real(absolute / f(days), 1), real(residuals[max_residual],
         1), max_residual + 1, positive, runs, real(dw / square_residual, 4) });
    var autocorrelation: d.Text = .{};
    autocorrelation.add("autocorrelation", .{});
    for (1..8) |lag| {
        var sum: f64 = 0;
        for (0..days - lag) |day| sum += residuals[day] * residuals[day + lag];
        autocorrelation.add(" {s}", .{real(sum / square_residual, 4)});
    }
    fit.add("{s}", .{autocorrelation.value()});
    var outliers: usize = 0;
    for (0..days) |day| {
        const z = residuals[day] / @sqrt(predicted[day]);
        if (@abs(z) > p.outlier) {
            outliers += 1;
            fit.add("outlier {d} observed {d} fitted {s} z {s}", .{ day + 1, input.cases[day],
                 real(predicted[day], 1), real(z, 4) });
        }
    }
    fit.add("outliers {d}", .{outliers});
    var weekday_observed: [7]i64 = [_]i64{0} ** 7;
    var weekday_fitted: [7]f64 = [_]f64{0} ** 7;
    var weekday_factor: [7]f64 = undefined;
    for (0..days) |day| {
        weekday_observed[day % 7] += input.cases[day];
        weekday_fitted[day % 7] += predicted[day];
    }
    for (0..7) |k| {
        weekday_factor[k] = f(weekday_observed[k]) / weekday_fitted[k];
        fit.add("weekday {d} observed {d} fitted {s} factor {s}", .{ k + 1, weekday_observed[k],
             real(weekday_fitted[k], 1), real(weekday_factor[k], 4) });
    }
    var corrected: f64 = 0;
    for (0..days) |day| {
        const difference = predicted[day] * weekday_factor[day % 7] - f(input.cases[day]);
        corrected += difference * difference;
    }
    fit.add("weekday_adjusted rmse {s}", .{real(rmse(corrected, days), 4)});
    const burden = total(infections);
    fit.add("burden infections {s} ascertainment {s} deaths_per_infection {s}", .{ real(burden,
         1), real(f(cases_total) / burden, 4), real(f(deaths_total) / burden, 6) });
    var death_cross: f64 = 0;
    var death_square: f64 = 0;
    for (0..days) |day| {
        death_cross += deaths[day] * f(input.deaths[day]);
        death_square += deaths[day] * deaths[day];
    }
    const kappa = death_cross / death_square;
    fit.add("deaths observed {d} model {s} rmse {s} scale {s} implied_fatality {s} cfr {s}",
         .{ deaths_total, real(fitted[days - 1].values[4], 1), real(rmse(errors(deaths, 1,
         input.deaths), days), 4), real(kappa, 4), real(lab.fatality * kappa, 6), real(f(deaths_total) / f(cases_total),
         4) });
    const death_correlations = d.alloc(f64, p.death_lag + 1);
    for (0..p.death_lag + 1) |lag| {
        var a: i64 = 0;
        var b: i64 = 0;
        var y: i64 = 0;
        var cases: i64 = 0;
        var death_count: i64 = 0;
        for (0..days - lag) |day| {
            a += input.cases[day] * input.deaths[day + lag];
            b += input.cases[day] * input.cases[day];
            y += input.deaths[day + lag] * input.deaths[day + lag];
            cases += input.cases[day];
            death_count += input.deaths[day + lag];
        }
        const correlation = f(a) / @sqrt(f(b) * f(y));
        death_correlations[lag] = correlation;
        fit.add("death_lag {d} correlation {s} cfr {s}", .{ lag, real(correlation, 4), real(f(death_count) / f(cases),
             4) });
    }
    fit.add("death_best_lag {d}", .{peak(death_correlations)});
    var previous_week: i64 = 0;
    var first: usize = 0;
    var week: usize = 1;
    while (first < days) : ({
        first += 7;
        week += 1;
    }) {
        const last = @min(first + 7, days);
        var cases: i64 = 0;
        var observed_deaths: i64 = 0;
        var fitted_sum: f64 = 0;
        var death_sum: f64 = 0;
        for (first..last) |day| {
            cases += input.cases[day];
            observed_deaths += input.deaths[day];
            fitted_sum += predicted[day];
            death_sum += deaths[day];
        }
        fit.add("weekly {d} days {d} {d} observed {d} fitted {s} deaths_observed {d} deaths_model {s} growth {s}",
             .{ week, first + 1, last, cases, real(fitted_sum, 1), observed_deaths, real(death_sum,
             1), if (week == 1) "-" else real(f(cases) / f(previous_week), 4) });
        previous_week = cases;
    }
    const parameter_names = [3][]const u8{ "beta", "gamma", "rho" };
    const fitted_values = [3]f64{ beta_hat, gamma_hat, rho_hat };
    var standard_errors: [3]f64 = undefined;
    for (0..3) |parameter| {
        var values: [11]f64 = undefined;
        for (0..11) |index| {
            const k = d.n(index) - 5;
            const value = fitted_values[parameter] * (1 + f(k) / 100);
            var point = fitted_values;
            point[parameter] = value;
            values[index] = lab.objective(point[0], point[1], point[2]);
            fit.add("profile {s} {d} value {s} rmse {s}", .{ parameter_names[parameter], k,
                 real(value, 6), real(rmse(values[index], days), 4) });
        }
        const h = fitted_values[parameter] / 100;
        const curvature = (values[6] - 2 * values[5] + values[4]) / (h * h);
        const variance = nm_sse / f(days - 3);
        standard_errors[parameter] = @sqrt(2 * variance / curvature);
        fit.add("profile_se {s} {s}", .{ parameter_names[parameter], real(standard_errors[parameter], 6) });
    }
    const training_days = days - p.holdout;
    var back: Search = .{ .lab = &lab, .beta = beta_hat, .gamma = gamma_hat, .rho = rho_hat,
         .sigma = p.sigma, .sequence = lab.multiplier[0..training_days] };
    const back_beta = fitting.golden(back, Search.value, beta_hat - beta_spacing, beta_hat + beta_spacing, p.golden);
    back.cached = lab.incidence(back_beta.point, gamma_hat, p.sigma, back.sequence);
    back.parameter = 2;
    const back_rho = fitting.golden(back, Search.value, rho_hat - rho_spacing, rho_hat + rho_spacing, p.golden);
    const back_incidence = lab.incidence(back_beta.point, gamma_hat, p.sigma, lab.multiplier);
    const forecast = reported(back_incidence[training_days..], back_rho.point);
    fit.add("backtest train_days {d} beta {s} rho {s} train_rmse {s} test_rmse {s} full_fit_test_rmse {s}",
         .{ training_days, real(back_beta.point, 6), real(back_rho.point, 6), real(rmse(back_rho.value,
         training_days), 4), real(rmse(errors(forecast, 1, input.cases[training_days..]), p.holdout),
         4), real(rmse(errors(predicted[training_days..], 1, input.cases[training_days..]),
         p.holdout), 4) });
    for (forecast, 0..) |value, i| fit.add("backtest_day {d} observed {d} forecast {s} error {s}",
         .{ training_days + i + 1, input.cases[training_days + i], real(value, 1), real(f(input.cases[training_days + i]) - value,
         1) });
    const estimated = d.dupe(d.Intervention, input.interventions);
    var effect_sse = nm_sse;
    for (1..estimated.len) |k| {
        const context: Search = .{ .lab = &lab, .beta = beta_hat, .gamma = gamma_hat, .rho = rho_hat,
             .sigma = p.sigma, .sequence = lab.multiplier, .effect = k, .interventions = estimated };
        const result = fitting.golden(context, Search.value, input.interventions[k].multiplier - p.effect_width,
             input.interventions[k].multiplier + p.effect_width, p.golden);
        estimated[k].multiplier = result.point;
        effect_sse = result.value;
        fit.add("effect {d} day {d} given {s} estimated {s} sse {s}", .{ k + 1, input.interventions[k].day,
             real(input.interventions[k].multiplier, 4), real(result.point, 6), real(result.value,
             1) });
    }
    fit.add("effect_sse before {s} after {s} rmse {s}", .{ real(nm_sse, 1), real(effect_sse,
         1), real(rmse(effect_sse, days), 4) });
    const sensitivity_names = [4][]const u8{ "beta", "gamma", "sigma", "rho" };
    for (0..4) |parameter| {
        for ([2]f64{ 0.9, 1.1 }) |factor| {
            var values = [4]f64{ beta_hat, gamma_hat, p.sigma, rho_hat };
            values[parameter] *= factor;
            const changed = lab.model(.seird, values[0], values[1], values[2]);
            const states = integration.trajectory(changed, lab.multiplier);
            const values_incidence = series(changed, states);
            const day = peak(values_incidence);
            fit.add("sensitivity {s} {s} r0 {s} rmse {s} peak_day {d} peak {s} attack {s}",
                 .{ sensitivity_names[parameter], real(factor, 2), real(values[0] / values[1],
                 4), real(rmse(errors(values_incidence, values[3], input.cases), days), 4),
                 day + 1, real(values[3] * values_incidence[day], 1), real((f(lab.population) - states[days - 1].values[0]) / f(lab.population),
                 4) });
        }
    }
    const sir = lab.model(.sir, beta_hat, gamma_hat, p.sigma);
    const age = lab.model(.age, beta_hat, gamma_hat, p.sigma);
    const age_states = integration.trajectory(age, lab.multiplier);
    const sir_incidence = series(sir, integration.trajectory(sir, lab.multiplier));
    const age_incidence = series(age, age_states);
    compareModel(&fit, "sir", sir_incidence, input, rho_hat);
    compareModel(&fit, "seir", infections, input, rho_hat);
    compareModel(&fit, "age", age_incidence, input, rho_hat);
    const sir_context: Search = .{ .lab = &lab, .gamma = gamma_hat, .rho = rho_hat, .sigma = p.sigma,
         .sequence = lab.multiplier, .kind = .sir };
    const sir_search = fitting.golden(sir_context, Search.value, p.beta_min, p.beta_max, p.golden);
    const fitted_sir = lab.model(.sir, sir_search.point, gamma_hat, p.sigma);
    const fitted_sir_incidence = series(fitted_sir, integration.trajectory(fitted_sir, lab.multiplier));
    fit.add("model sir_fit beta {s} rmse {s} peak_day {d}", .{ real(sir_search.point, 6), real(rmse(sir_search.value,
         days), 4), peak(fitted_sir_incidence) + 1 });
    var trajectories: d.Lines = .{};
    trajectories.add("day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported", .{});
    for (0..days) |day| trajectories.add("{d},{s},{s},{s},{s},{s},{s},{s},{d},{s},{d},{s}",
         .{ day + 1, real(fitted[day].values[0], 1), real(fitted[day].values[1], 1), real(fitted[day].values[2],
         1), real(fitted[day].values[3], 1), real(fitted[day].values[4], 1), real(infections[day],
         1), real(predicted[day], 1), input.cases[day], real(average[day], 2), cumulative_observed[day],
         real(cumulative_fitted[day], 1) });
    var reproduction: d.Lines = .{};
    reproduction.add("r0 {s} herd_immunity {s}", .{ real(r0, 4), real(1 - 1 / r0, 4) });
    const ones = [_]f64{1} ** 730;
    const long_states = integration.trajectory(model, &ones);
    reproduction.add("final_size equation {s} simulated {s}", .{ real(finalSize(r0), 4), real((f(lab.population) - long_states[729].values[0]) / f(lab.population),
         4) });
    const generation = lab.model(.generation, 0, gamma_hat, p.sigma);
    const generation_incidence = series(generation, integration.trajectory(generation, ones[0..p.generation]));
    const coverage = total(generation_incidence);
    const generation_weights = d.alloc(f64, p.generation);
    var generation_mean: f64 = 0;
    for (generation_incidence, 0..) |value, s| {
        generation_weights[s] = value / coverage;
        generation_mean += (f(s + 1) - 0.5) * generation_weights[s];
    }
    reproduction.add("generation mean {s} theory {s} coverage {s}", .{ real(generation_mean,
         4), real(1 / p.sigma + 1 / gamma_hat, 4), real(coverage, 4) });
    for (generation_weights, 1..) |value, s| reproduction.add("generation_weight {d} {s}", .{ s, real(value, 6) });
    const model_peak = peak(infections);
    const infectious_peak = peak(infectious);
    var observed_peak: usize = 0;
    for (input.cases, 0..) |value, day| {
        if (value > input.cases[observed_peak]) observed_peak = day;
    }
    const average_peak = peak(average);
    reproduction.add("peak model day {d} incidence {s} reported {s} infectious_day {d} infectious {s}",
         .{ model_peak + 1, real(infections[model_peak], 1), real(predicted[model_peak], 1),
         infectious_peak + 1, real(infectious[infectious_peak], 1) });
    reproduction.add("peak observed day {d} cases {d} average7_day {d} average7 {s}", .{ observed_peak + 1,
         input.cases[observed_peak], average_peak + 1, real(average[average_peak], 2) });
    for (input.interventions, 0..) |intervention, k| {
        const start = intervention.day - 1;
        const last = if (k + 1 < input.interventions.len) input.interventions[k + 1].day - 1 else days;
        var observed: i64 = 0;
        var predicted_sum: f64 = 0;
        var square: f64 = 0;
        var bias: f64 = 0;
        for (start..last) |day| {
            observed += input.cases[day];
            predicted_sum += predicted[day];
            square += residuals[day] * residuals[day];
            bias += residuals[day];
        }
        reproduction.add("period {d} days {d} {d} multiplier {s} rt_start {s} rt_end {s} observed {d} fitted {s} rmse {s} bias {s}",
             .{ k + 1, start + 1, last, real(intervention.multiplier, 4), real(rt[start], 4),
             real(rt[last - 1], 4), observed, real(predicted_sum, 1), real(rmse(square, last - start),
             4), real(bias / f(last - start), 1) });
    }
    for (p.milestones) |target| {
        var observed: ?usize = null;
        var predicted_day: ?usize = null;
        for (0..days) |day| {
            if (observed == null and cumulative_observed[day] >= target) observed = day + 1;
            if (predicted_day == null and cumulative_fitted[day] >= f(target)) predicted_day = day + 1;
        }
        reproduction.add("milestone {d} observed {s} fitted {s}", .{ target, if (observed) |value| d.fmt("{d}",
             .{value}) else "never", if (predicted_day) |value| d.fmt("{d}", .{value}) else "never" });
    }
    const predicted_total = total(predicted);
    const constant = d.alloc(f64, days);
    @memset(constant, input.interventions[0].multiplier);
    const none = reported(lab.incidence(beta_hat, gamma_hat, p.sigma, constant), rho_hat);
    const none_peak = peak(none);
    reproduction.add("counterfactual none reported {s} peak_day {d} peak {s} averted {s}",
         .{ real(total(none), 1), none_peak + 1, real(none[none_peak], 1), real(total(none) - predicted_total,
         1) });
    for (1..input.interventions.len) |k| {
        var without: std.ArrayList(d.Intervention) = .empty;
        for (input.interventions, 0..) |intervention, j| {
            if (j != k) d.append(d.Intervention, &without, intervention);
        }
        const sum = total(reported(lab.incidence(beta_hat, gamma_hat, p.sigma, multipliers(without.items,
             days)), rho_hat));
        reproduction.add("counterfactual without {d} reported {s} averted {s}", .{ k + 1, real(sum,
             1), real(sum - predicted_total, 1) });
    }
    for (1..input.interventions.len) |k| {
        for ([2]i64{ -7, 7 }) |shift| {
            const moved = d.dupe(d.Intervention, input.interventions);
            moved[k].day = d.u(d.n(moved[k].day) + shift);
            const sum = total(reported(lab.incidence(beta_hat, gamma_hat, p.sigma, multipliers(moved, days)), rho_hat));
            reproduction.add("timing {d} shift {d} reported {s} change {s}", .{ k + 1, shift,
                 real(sum, 1), real(sum - predicted_total, 1) });
        }
    }
    for (1..days) |day| {
        if ((rt[day] < 1) != (rt[day - 1] < 1)) reproduction.add("rt_cross day {d} {s}", .{ day + 1,
             if (rt[day] < 1) "down" else "up" });
    }
    const pressure = d.alloc(f64, days);
    @memset(pressure, 0);
    for (0..days) |day| {
        for (1..@min(p.generation, day) + 1) |s| pressure[day] += generation_weights[s - 1] * f(input.cases[day - s]);
    }
    for (0..days) |day| {
        var empirical: []const u8 = "-";
        if (day + 1 >= p.generation + 7) {
            var numerator: i64 = 0;
            var denominator: f64 = 0;
            for (day - 6..day + 1) |j| {
                numerator += input.cases[j];
                denominator += pressure[j];
            }
            empirical = real(f(numerator) / denominator, 4);
        }
        reproduction.add("rt {d} model {s} empirical {s}", .{ day + 1, real(rt[day], 4), empirical });
    }
    const ngm = nextGeneration(&lab, lab.contacts, r0);
    const eigen = largest(ngm, groups);
    for (input.groups, 0..) |group, g| {
        var row: d.Text = .{};
        row.add("ngm {s}", .{group.name});
        for (ngm[g][0..groups]) |value| row.add(" {s}", .{real(value, 4)});
        reproduction.add("{s}", .{row.value()});
    }
    var eigen_line: d.Text = .{};
    eigen_line.add("r0_age {s} ratio {s} kbar {s} eigenvector", .{ real(eigen.value, 4), real(eigen.value / r0,
         4), real(lab.kbar, 4) });
    for (eigen.vector[0..groups]) |value| eigen_line.add(" {s}", .{real(value, 4)});
    reproduction.add("{s}", .{eigen_line.value()});
    var z: [6]f64 = [_]f64{1} ** 6;
    for (0..100) |_| {
        var next: [6]f64 = [_]f64{0} ** 6;
        for (0..groups) |g| {
            var sum: f64 = 0;
            for (0..groups) |h| sum += r0 * lab.contacts[g][h] * z[h];
            next[g] = 1 - @exp(-sum);
        }
        z = next;
    }
    const long_age = integration.trajectory(age, &ones);
    var final_equation: f64 = 0;
    var final_simulated: f64 = 0;
    for (input.groups, 0..) |group, g| {
        const population = f(group.population);
        const simulated = (population - long_age[729].values[6 * g]) / population;
        final_equation += population * z[g];
        final_simulated += population * simulated;
        reproduction.add("final_size_age {s} equation {s} simulated {s}", .{ group.name, real(z[g],
             4), real(simulated, 4) });
    }
    reproduction.add("final_size_age total equation {s} simulated {s}", .{ real(final_equation / f(lab.population),
         4), real(final_simulated / f(lab.population), 4) });
    const age_initial = age.initial();
    var day_index: usize = 0;
    while (day_index < days) : (day_index += 7) {
        var matrix: [6][6]f64 = std.mem.zeroes([6][6]f64);
        for (0..groups) |g| for (input.groups, 0..) |group, h| {
            matrix[g][h] = lab.multiplier[day_index] * r0 * lab.contacts[g][h] * (if (day_index > 0) age_states[day_index - 1].values[6 * g] else age_initial.values[6 * g]) / f(group.population);
        };
        reproduction.add("age_rt {d} {s} homogeneous {s}", .{ day_index + 1, real(largest(matrix,
             groups).value, 4), real(rt[day_index], 4) });
    }
    first = 0;
    week = 1;
    while (first < days) : ({
        first += 7;
        week += 1;
    }) {
        const last = @min(first + 7, days);
        var row: d.Text = .{};
        row.add("age_weekly {d} days {d} {d}", .{ week, first + 1, last });
        for (0..groups) |g| {
            var sum: f64 = 0;
            for (first..last) |day| sum += age_states[day].values[6 * g + 5];
            row.add(" {s}", .{real(sum, 1)});
        }
        reproduction.add("{s}", .{row.value()});
    }
    var age_infections: [6]f64 = [_]f64{0} ** 6;
    for (0..groups) |g| for (0..days) |day| {
        age_infections[g] += age_states[day].values[6 * g + 5];
    };
    const age_total = total(age_infections[0..groups]);
    for (input.groups, 0..) |group, g| {
        const values = d.alloc(f64, days);
        for (age_states, values) |state, *value| value.* = state.values[6 * g + 5];
        const day = peak(values);
        const population = f(group.population);
        reproduction.add("age {s} attack {s} infections {s} share {s} deaths {s} peak_day {d} peak {s}",
             .{ group.name, real((population - age_states[days - 1].values[6 * g]) / population,
             4), real(age_infections[g], 1), real(age_infections[g] / age_total, 4), real(age_states[days - 1].values[6 * g + 4],
             1), day + 1, real(values[day], 1) });
    }
    for (p.changes.items) |change| {
        var target: usize = 0;
        while (!d.eq(input.groups[target].name, change.group)) target += 1;
        var changed_contacts = lab.contacts;
        for (0..groups) |g| for (0..groups) |h| {
            changed_contacts[g][h] = changed_contacts[g][h] * (if (g == target) change.factor else @as(f64,
                 1)) * (if (h == target) change.factor else @as(f64, 1));
        };
        var changed = age;
        changed.contacts = changed_contacts;
        const states = integration.trajectory(changed, lab.multiplier);
        const changed_infections = total(series(changed, states));
        var susceptible_loss: f64 = 0;
        for (input.groups, 0..) |group, g| susceptible_loss += f(group.population) - states[days - 1].values[6 * g];
        reproduction.add("contact_change {s} group {s} factor {s} r0_age {s} infections {s} deaths {s} attack {s}",
             .{ change.name, change.group, real(change.factor, 4), real(largest(nextGeneration(&lab,
             changed_contacts, r0), groups).value, 4), real(changed_infections, 1), real(ageDeaths(states[days - 1],
             groups), 1), real(susceptible_loss / f(lab.population), 4) });
    }
    var scenarios: d.Lines = .{};
    scenarios.add("scenario,day,incidence,reported", .{});
    var first_scenario: f64 = 0;
    for (p.scenarios.items, 0..) |scenario, index| {
        const future_multiplier = d.alloc(f64, p.horizon);
        @memset(future_multiplier, scenario.multiplier);
        const future = integration.simulate(model, fitted[days - 1], future_multiplier);
        const future_incidence = series(model, future);
        const future_reported = reported(future_incidence, rho_hat);
        const sum = total(future_reported);
        if (index == 0) first_scenario = sum;
        const day = peak(future_reported);
        var below: ?usize = null;
        var above: usize = 0;
        for (0..p.horizon) |j| {
            if (below == null and future_reported[j] < p.threshold) below = days + j + 1;
            above += @intFromBool(future_reported[j] >= p.threshold);
            scenarios.add("{s},{d},{s},{s}", .{ scenario.name, days + j + 1, real(future_incidence[j],
                 1), real(future_reported[j], 1) });
        }
        reproduction.add("scenario {s} multiplier {s} rt {s} reported {s} peak_day {d} peak {s} attack {s} final_size {s} averted {s} below {s} days_above {d}",
             .{ scenario.name, real(scenario.multiplier, 4), real(r0 * scenario.multiplier * fitted[days - 1].values[0] / f(lab.population),
             4), real(sum, 1), days + day + 1, real(future_reported[day], 1), real((f(lab.population) - future[p.horizon - 1].values[0]) / f(lab.population),
             4), real(finalSize(r0 * scenario.multiplier), 4), real(first_scenario - sum, 1),
             if (below) |value| d.fmt("{d}", .{value}) else "never", above });
        const beta_low = beta_hat - 2 * standard_errors[0];
        const beta_high = beta_hat + 2 * standard_errors[0];
        const combined = d.alloc(f64, days + p.horizon);
        @memcpy(combined[0..days], lab.multiplier);
        @memcpy(combined[days..], future_multiplier);
        var band: [2]f64 = .{ 0, 0 };
        for ([2]f64{ beta_low, beta_high }, 0..) |beta, k| {
            const values = lab.incidence(beta, gamma_hat, p.sigma, combined);
            for (values[days..]) |value| band[k] += rho_hat * value;
        }
        reproduction.add("scenario_band {s} beta_low {s} reported_low {s} beta_high {s} reported_high {s}",
             .{ scenario.name, real(beta_low, 6), real(band[0], 1), real(beta_high, 6), real(band[1],
             1) });
        const age_future = integration.simulate(age, age_states[days - 1], future_multiplier);
        var row: d.Text = .{};
        row.add("scenario_age {s} attack", .{scenario.name});
        for (input.groups, 0..) |group, g| row.add(" {s}", .{real((f(group.population) - age_future[p.horizon - 1].values[6 * g]) / f(group.population),
             4)});
        row.add(" deaths {s}", .{real(ageDeaths(age_future[p.horizon - 1], groups), 1)});
        reproduction.add("{s}", .{row.value()});
    }
    try d.save(io, "fit.txt", fit);
    try d.save(io, "trajectories.csv", trajectories);
    try d.save(io, "scenarios.csv", scenarios);
    try d.save(io, "reproduction.txt", reproduction);
    try d.save(io, "curve_plot.txt", report.curvePlot(input.cases, predicted));
}
