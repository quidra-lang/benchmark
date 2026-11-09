const std = @import("std");
const io = @import("series_io.zig");
const d = @import("decomposition.zig");
const smooth = @import("smoothing.zig");
const ar = @import("autoregression.zig");
const evaluation = @import("evaluation.zig");
const names = [_][]const u8{ "naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult",
     "decomp_add", "decomp_mult", "ar", "combo" };
const difference_names = [_][]const u8{ "none", "first", "seasonal", "both" };
fn valuesText(values: []const f64) []const u8 {
    var text: io.Text = .{};
    for (values) |value| text.add(" {s}", .{io.real(value)});
    return text.value();
}
fn defined(value: f64) []const u8 {
    return if (std.math.isNan(value)) "NA" else io.real(value);
}
const Fitted = struct {
    method: usize,
    season: usize,
    values: []const f64,
    residuals: []const f64 = &.{},
    seasonal: []const f64 = &.{},
    parameters: smooth.Parameters = .{},
    smoothed: smooth.Smoothed = .{},
    intercept: f64 = 0,
    slope: f64 = 0,
    difference_kind: usize = 0,
    order: usize = 0,
    differenced: []const f64 = &.{},
    coefficients: []const f64 = &.{},
    aic: []const f64 = &.{},
    variances: []const f64 = &.{},
    correlation: ar.Correlation = .{},
    levinson: ar.Levinson = .{},
    sigma2: f64 = 0,
    fn forecast(self: Fitted, origin: usize, steps: usize) []f64 {
        const result = io.alloc(f64, steps);
        if (self.method == 0) {
            @memset(result, self.values[origin - 1]);
            return result;
        }
        if (self.method == 1) {
            for (result, 0..) |*value, k| value.* = self.values[origin - self.season + k % self.season];
            return result;
        }
        if (self.method == 2) {
            for (result, 1..) |*value, k| value.* = self.values[origin - 1] + io.f(k) * ((self.values[origin - 1] - self.values[0]) / io.f(origin - 1));
            return result;
        }
        if (self.method <= 7) return smooth.forecast(self.method, self.smoothed.states[origin], self.parameters,
             origin, steps, self.season);
        if (self.method <= 9) {
            for (result, origin..) |*value, t| {
                const base = self.intercept + self.slope * io.f(t + 1);
                const component = self.seasonal[t % self.season];
                value.* = if (self.method == 8) base + component else base * component;
            }
            return result;
        }
        return ar.forecast(self.values, self.differenced, self.difference_kind, self.season, origin,
             steps, self.correlation.mean, self.coefficients);
    }
    fn consider(self: *Fitted, parameters: smooth.Parameters, best: *f64) void {
        const result = smooth.smooth(self.method, self.values, self.season, parameters);
        var sse: f64 = 0;
        for (result.residuals) |error_| sse += error_ * error_;
        if (sse < best.*) {
            best.* = sse;
            self.parameters = parameters;
            self.smoothed = result;
        }
    }
    fn lines(self: Fitted) io.Lines {
        var out: io.Lines = .{};
        const name = names[self.method];
        const tail = io.fmt("rmse {s} residuals {d}", .{ io.real(d.rmse(self.residuals)), self.residuals.len });
        if (self.method <= 1) out.add("{s} {s}", .{ name, tail }) else if (self.method == 2) out.add("{s} slope {s} {s}",
             .{ name, io.real(self.slope), tail }) else if (self.method <= 7) {
            var line: io.Text = .{};
            line.add("{s} alpha {s}", .{ name, io.real(self.parameters.alpha) });
            if (self.method != 3) line.add(" beta {s}", .{io.real(self.parameters.beta)});
            if (self.method == 5) line.add(" phi {s}", .{io.real(self.parameters.phi)});
            if (self.method == 6 or self.method == 7) line.add(" gamma {s}", .{io.real(self.parameters.gamma)});
            const state = self.smoothed.states[self.values.len];
            line.add(" {s} level {s}", .{ tail, io.real(state.level) });
            if (self.method != 3) line.add(" slope {s}", .{io.real(state.slope)});
            out.add("{s}", .{line.value()});
            if (self.method == 6 or self.method == 7) {
                const components = io.alloc(f64, self.season);
                for (components, 0..) |*value, index| value.* = state.seasonal[(self.values.len + index) % self.season];
                out.add("{s} seasonal{s}", .{ name, valuesText(components) });
            }
        } else if (self.method <= 9) {
            out.add("{s} intercept {s} slope {s} {s}", .{ name, io.real(self.intercept), io.real(self.slope), tail });
            out.add("{s} seasonal{s}", .{ name, valuesText(self.seasonal) });
        } else {
            out.add("ar variance none {s} first {s} seasonal {s} both {s}", .{ io.real(self.variances[0]),
                 io.real(self.variances[1]), io.real(self.variances[2]), io.real(self.variances[3]) });
            out.add("ar difference {s} n {d} mean {s} order {d} sigma2 {s} {s}", .{ difference_names[self.difference_kind],
                 self.differenced.len, io.real(self.correlation.mean), self.order, io.real(self.sigma2),
                 tail });
            out.add("ar aic{s}", .{valuesText(self.aic)});
            out.add("ar coefficients{s}", .{if (self.coefficients.len == 0) " none" else valuesText(self.coefficients)});
        }
        return out;
    }
};
fn fitMethod(method: usize, values: []const f64, params: io.Params) Fitted {
    var model: Fitted = .{ .method = method, .season = params.season, .values = values };
    if (method <= 2) {
        if (method == 2) model.slope = (values[values.len - 1] - values[0]) / io.f(values.len - 1);
        const first: usize = if (method == 1) params.season else 1;
        const residuals = io.alloc(f64, values.len - first);
        for (residuals, first..) |*error_, t| error_.* = if (method == 1) values[t] - values[t - params.season] else if (method == 2) values[t] - values[t - 1] - model.slope else values[t] - values[t - 1];
        model.residuals = residuals;
    } else if (method <= 7) {
        var best = std.math.inf(f64);
        for (params.alpha) |alpha| {
            if (method == 3) {
                model.consider(.{ .alpha = alpha }, &best);
                continue;
            }
            for (params.beta) |beta| {
                if (method == 4) model.consider(.{ .alpha = alpha, .beta = beta }, &best) else if (method == 5) {
                    for (params.phi) |phi| model.consider(.{ .alpha = alpha, .beta = beta, .phi = phi }, &best);
                } else for (params.gamma) |gamma| model.consider(.{ .alpha = alpha, .beta = beta, .gamma = gamma }, &best);
            }
        }
        model.residuals = model.smoothed.residuals;
    } else if (method <= 9) {
        const decomposition = d.decompose(values, params.season);
        model.seasonal = if (method == 8) decomposition.additive else decomposition.multiplicative;
        const adjusted = io.alloc(f64, values.len);
        for (values, adjusted, 0..) |value, *target, t| target.* = if (method == 8) value - model.seasonal[t % params.season] else value / model.seasonal[t % params.season];
        const line = d.regression(adjusted);
        model.intercept = line[0];
        model.slope = line[1];
        const residuals = io.alloc(f64, values.len);
        for (values, residuals, 0..) |value, *error_, t| {
            const base = model.intercept + model.slope * io.f(t + 1);
            const component = model.seasonal[t % params.season];
            error_.* = value - (if (method == 8) base + component else base * component);
        }
        model.residuals = residuals;
    } else {
        var smallest = std.math.inf(f64);
        const variances = io.alloc(f64, 4);
        for (variances, 0..) |*variance, kind| {
            const differenced = ar.difference(values, kind, params.season);
            const correlation = ar.autocorrelation(differenced, params.max_lag);
            variance.* = correlation.variance;
            if (correlation.variance < smallest) {
                smallest = correlation.variance;
                model.difference_kind = kind;
                model.differenced = differenced;
                model.correlation = correlation;
            }
        }
        model.variances = variances;
        model.levinson = ar.durbin(model.correlation.acf, params.max_lag);
        const aic = io.alloc(f64, params.max_ar + 1);
        var best = std.math.inf(f64);
        for (aic, 0..) |*value, order| {
            value.* = io.f(model.differenced.len) * @log(model.correlation.variance * model.levinson.variance[order]) + 2 * io.f(order);
            if (value.* < best) {
                best = value.*;
                model.order = order;
            }
        }
        model.aic = aic;
        model.sigma2 = model.correlation.variance * model.levinson.variance[model.order];
        model.coefficients = model.levinson.coefficients[model.order][1 .. model.order + 1];
        model.residuals = ar.residuals(model.differenced, model.correlation.mean, model.coefficients);
    }
    return model;
}
const Forecaster = struct {
    models: []const Fitted,
    method: usize,
    members: []const usize = &.{},
    fn forecast(self: Forecaster, origin: usize, steps: usize) []f64 {
        if (self.method != 11) return self.models[self.method].forecast(origin, steps);
        const result = io.zeros(steps);
        for (self.members) |method| {
            const estimates = self.models[method].forecast(origin, steps);
            for (result, estimates) |*value, estimate| value.* += estimate;
        }
        for (result) |*value| value.* /= io.f(self.members.len);
        return result;
    }
};
const CrossValidation = struct { counts: []usize, sigma: []f64, mae: []f64, rmse: f64 };
fn crossValidate(values: []const f64, params: io.Params, forecast: Forecaster) CrossValidation {
    var result: CrossValidation = .{ .counts = io.alloc(usize, params.horizon), .sigma = io.zeros(params.horizon),
         .mae = io.zeros(params.horizon), .rmse = 0 };
    @memset(result.counts, 0);
    const squares = io.zeros(params.horizon);
    const absolute = io.zeros(params.horizon);
    for (params.cv_start..values.len) |origin| {
        const steps = @min(params.horizon, values.len - origin);
        const estimates = forecast.forecast(origin, steps);
        for (estimates, 0..) |estimate, k| {
            const error_ = values[origin + k] - estimate;
            result.counts[k] += 1;
            squares[k] += error_ * error_;
            absolute[k] += @abs(error_);
        }
    }
    for (0..params.horizon) |k| {
        result.sigma[k] = @sqrt(squares[k] / io.f(result.counts[k]));
        result.mae[k] = absolute[k] / io.f(result.counts[k]);
    }
    var sum: f64 = 0;
    var count: usize = 0;
    for (0..params.holdout) |k| {
        sum += squares[k];
        count += result.counts[k];
    }
    result.rmse = @sqrt(sum / io.f(count));
    return result;
}
fn cvLess(validations: []const CrossValidation, a: usize, b: usize) bool {
    return if (validations[a].rmse != validations[b].rmse) validations[a].rmse < validations[b].rmse else a < b;
}
fn numberLess(_: void, a: usize, b: usize) bool {
    return a < b;
}
const Interval = struct { forecast: f64, lo80: f64, hi80: f64, lo95: f64, hi95: f64 };
fn interval(forecast: f64, sigma: f64, params: io.Params, multiplier: f64) Interval {
    return .{ .forecast = forecast * multiplier, .lo80 = (forecast - params.z80 * sigma) * multiplier,
         .hi80 = (forecast + params.z80 * sigma) * multiplier, .lo95 = (forecast - params.z95 * sigma) * multiplier,
         .hi95 = (forecast + params.z95 * sigma) * multiplier };
}
fn forecastRow(out: *io.Lines, name: []const u8, stage: []const u8, model: []const u8, period: []const u8,
     actual: []const u8, values: Interval) void {
    out.add("{s},{s},{s},{s},{s},{s},{s},{s},{s},{s}", .{ name, stage, model, period, actual, io.real(values.forecast),
         io.real(values.lo80), io.real(values.hi80), io.real(values.lo95), io.real(values.hi95) });
}
const Outputs = struct {
    decomposition: io.Lines = .{},
    models: io.Lines = .{},
    forecasts: io.Lines = .{},
    accuracy: io.Lines = .{},
    cv: io.Lines = .{},
    correlogram: io.Lines = .{},
    chart: io.Lines = .{},
    plan: io.Lines = .{},
    fn init() Outputs {
        var out: Outputs = .{};
        out.decomposition.add("series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag",
             .{});
        out.forecasts.add("series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95", .{});
        out.accuracy.add("series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank", .{});
        out.cv.add("series,method,step,origins,mae,rmse", .{});
        return out;
    }
    fn write(self: Outputs, context: std.Io) !void {
        try io.writeLines(context, "decomposition.csv", self.decomposition);
        try io.writeLines(context, "models.txt", self.models);
        try io.writeLines(context, "forecasts.csv", self.forecasts);
        try io.writeLines(context, "accuracy.csv", self.accuracy);
        try io.writeLines(context, "cv.csv", self.cv);
        try io.writeLines(context, "correlogram.txt", self.correlogram);
        try io.writeLines(context, "chart.txt", self.chart);
        try io.writeLines(context, "plan.txt", self.plan);
    }
};
fn correlationBar(correlation: f64, band: f64) []const u8 {
    const bar = io.alloc(u8, 41);
    @memset(bar, ' ');
    const extent: usize = @intFromFloat(@floor(@abs(correlation) * 20 + 0.5));
    const boundary: usize = @intFromFloat(@floor(band * 20 + 0.5));
    bar[20 - boundary] = ':';
    bar[20 + boundary] = ':';
    bar[20] = '|';
    if (correlation > 0) @memset(bar[21 .. 21 + extent], '#') else if (correlation < 0) @memset(bar[20 - extent .. 20], '#');
    return bar;
}
fn diagnostics(out: *io.Lines, name: []const u8, fitted: []const Fitted, params: io.Params) void {
    const model_ar = fitted[10];
    const band = 2 / @sqrt(io.f(model_ar.differenced.len));
    out.add("series {s} difference {s} n {d} band {s}", .{ name, difference_names[model_ar.difference_kind],
         model_ar.differenced.len, io.real(band) });
    for (0..2) |partial| for (1..params.max_lag + 1) |lag| {
        const value = if (partial == 1) model_ar.levinson.partial[lag] else model_ar.correlation.acf[lag];
        out.add("{s} {d: >2} {s: >7} [{s}]{s}", .{ if (partial == 1) "pacf" else "acf", lag, io.real(value),
             correlationBar(value, band), if (@abs(value) > band) " *" else "" });
    };
    for (fitted) |model| {
        const residuals = model.residuals;
        const average = d.mean(residuals);
        const count = io.f(residuals.len);
        var s2: f64 = 0;
        var s3: f64 = 0;
        var s4: f64 = 0;
        var squares: f64 = 0;
        var differences: f64 = 0;
        for (residuals, 0..) |value, i| {
            const delta = value - average;
            s2 += delta * delta;
            s3 += delta * delta * delta;
            s4 += delta * delta * delta * delta;
            squares += value * value;
            if (i > 0) {
                const change = value - residuals[i - 1];
                differences += change * change;
            }
        }
        const m2 = s2 / count;
        const m3 = s3 / count;
        const m4 = s4 / count;
        const skew = m3 / (m2 * @sqrt(m2));
        const kurtosis = m4 / (m2 * m2) - 3;
        const jb = count / 6 * (skew * skew + kurtosis * kurtosis / 4);
        out.add("residuals {s} n {d} mean {s} sd {s} dw {s} skewness {s} kurtosis {s} jb {s}", .{ names[model.method],
             residuals.len, io.real(average), io.real(@sqrt(s2 / (count - 1))), io.real(differences / squares),
             io.real(skew), io.real(kurtosis), io.real(jb) });
        var line: io.Text = .{};
        line.add("ljung_box {s}", .{names[model.method]});
        for (params.ljung_box) |lag| {
            const result = ar.ljungBox(residuals, lag);
            line.add(" lag {d} q {s} p {s}", .{ lag, io.real(result[0]), io.real(result[1]) });
        }
        out.add("{s}", .{line.value()});
    }
}
fn column(value: f64, low: f64, high: f64) usize {
    return @intFromFloat(@floor((value - low) / (high - low) * 60 + 0.5));
}
fn charts(out: *io.Lines, series: io.Series, best: usize, actual: []const f64, holdout: []const Interval,
     future: []const Interval, decomposition: d.Decomposition, params: io.Params) void {
    const rows = io.alloc(Interval, holdout.len + future.len);
    @memcpy(rows[0..holdout.len], holdout);
    @memcpy(rows[holdout.len..], future);
    var low = rows[0].lo95;
    var high = rows[0].hi95;
    for (rows) |row| {
        low = @min(low, row.lo95);
        high = @max(high, row.hi95);
    }
    for (actual) |value| {
        low = @min(low, value);
        high = @max(high, value);
    }
    out.add("chart {s} method {s}", .{ series.name, names[best] });
    out.add("scale low {s} high {s}", .{ io.real(low), io.real(high) });
    const first = series.raw.len - params.holdout;
    for (rows, 0..) |row, index| {
        const chart = io.alloc(u8, 61);
        @memset(chart, ' ');
        @memset(chart[column(row.lo95, low, high) .. column(row.hi95, low, high) + 1], '-');
        @memset(chart[column(row.lo80, low, high) .. column(row.hi80, low, high) + 1], '=');
        chart[column(row.forecast, low, high)] = 'o';
        if (index < actual.len) chart[column(actual[index], low, high)] = '*';
        out.add("{s} |{s}|", .{ series.periods[first + index], chart });
    }
    var peak: f64 = 0;
    for (decomposition.multiplicative) |value| peak = @max(peak, @abs(value - 1));
    out.add("profile peak {s}", .{io.real(peak)});
    for (decomposition.multiplicative, 1..) |value, number| {
        const extent: usize = @intFromFloat(@floor(@abs(value - 1) / peak * 30 + 0.5));
        const chart = io.alloc(u8, 61);
        @memset(chart, ' ');
        chart[30] = '|';
        if (value > 1) @memset(chart[31 .. 31 + extent], '#') else if (value < 1) @memset(chart[30 - extent .. 30], '#');
        out.add("season {d: >2} {s} [{s}]", .{ number, io.real(value), chart });
    }
}
const Year = struct { year: []const u8, actual_months: usize = 0, forecast_months: usize = 0, actual: f64 = 0,
     forecast: f64 = 0 };
fn inventoryPlan(out: *io.Lines, series: io.Series, best: usize, corrected: []const f64, actual: []const f64,
     future: []const Interval, policy: io.Inventory, params: io.Params, forecast: Forecaster) void {
    const size = corrected.len;
    const protection = policy.lead_time + policy.review;
    var squares: f64 = 0;
    for (params.cv_start..size - protection + 1) |origin| {
        const estimates = forecast.forecast(origin, protection);
        var error_: f64 = 0;
        for (estimates, 0..) |estimate, k| error_ += corrected[origin + k] - estimate;
        squares += error_ * error_;
    }
    const safety = policy.service * @sqrt(squares / io.f(size - protection - params.cv_start + 1));
    out.add("series {s} method {s}", .{ series.name, names[best] });
    out.add("policy on_hand {d} lead_time {d} review {d} service {s} safety_stock {s}", .{ policy.on_hand,
         policy.lead_time, policy.review, io.real(policy.service), io.real(safety) });
    var last: usize = 1;
    var k: usize = 1;
    while (k - 1 + protection <= params.horizon) : (k += policy.review) last = k;
    const end = last - 1 + protection;
    const receipts = io.alloc(i64, params.horizon + policy.lead_time + 2);
    @memset(receipts, 0);
    var stock = io.f(policy.on_hand);
    var outstanding: i64 = 0;
    var ordered: i64 = 0;
    var orders: usize = 0;
    var short_periods: usize = 0;
    var lowest = std.math.inf(f64);
    var sum: f64 = 0;
    for (1..end + 1) |step| {
        const receipt = receipts[step];
        stock += io.f(receipt);
        outstanding -= receipt;
        if ((step - 1) % policy.review == 0 and step - 1 + protection <= params.horizon) {
            const position = stock + io.f(outstanding);
            var demand: f64 = 0;
            for (future[step - 1 .. step - 1 + protection]) |row| demand += row.forecast;
            const target = demand + safety;
            const quantity: i64 = @intFromFloat(@max(0, @ceil(target - position)));
            out.add("review {s} position {s} target {s} order {d}", .{ series.periods[size + step - 1],
                 io.real(position), io.real(target), quantity });
            if (quantity > 0) {
                orders += 1;
                ordered += quantity;
                outstanding += quantity;
                receipts[step + policy.lead_time] += quantity;
            }
        }
        stock -= future[step - 1].forecast;
        const status = if (stock < 0) "short" else if (stock < safety) "low" else "ok";
        if (stock < 0) short_periods += 1;
        lowest = @min(lowest, stock);
        sum += stock;
        out.add("period {s} demand {s} receipt {d} on_hand {s} status {s}", .{ series.periods[size + step - 1],
             io.real(future[step - 1].forecast), receipt, io.real(stock), status });
    }
    out.add("summary orders {d} ordered {d} short_periods {d} lowest {s} average {s}", .{ orders,
         ordered, short_periods, io.real(lowest), io.real(sum / io.f(end)) });
    var years: std.ArrayList(Year) = .empty;
    for (series.periods, 0..) |period, t| {
        const year = period[0..4];
        if (years.items.len == 0 or !io.eq(years.items[years.items.len - 1].year, year)) io.append(Year,
             &years, .{ .year = year });
        const item = &years.items[years.items.len - 1];
        if (t < size) {
            item.actual_months += 1;
            item.actual += actual[t];
        } else {
            item.forecast_months += 1;
            item.forecast += future[t - size].forecast;
        }
    }
    var previous_full = false;
    var previous_total: f64 = 0;
    for (years.items) |year| {
        const value = year.actual + year.forecast;
        const full = year.actual_months + year.forecast_months == 12;
        out.add("year {s} actual_months {d} actual {s} forecast_months {d} forecast {s} total {s} growth {s}",
             .{ year.year, year.actual_months, io.real(year.actual), year.forecast_months, io.real(year.forecast),
             io.real(value), if (full and previous_full) io.real(100 * (value - previous_total) / previous_total) else "NA" });
        previous_full = full;
        previous_total = value;
    }
}
const Lift = struct { kind: []const u8, values: std.ArrayList(f64) = .empty };
fn analyzeSeries(source: io.Series, input: *const io.Input, inventory: io.Inventory, out: *Outputs) void {
    const params = input.params;
    const size = source.raw.len;
    const training_size = size - params.holdout;
    var series = source;
    const periods = io.alloc([]const u8, size + params.horizon);
    @memcpy(periods[0..size], source.periods);
    for (size..periods.len) |t| periods[t] = io.nextMonth(periods[t - 1]);
    series.periods = periods;
    const interpolated = io.dupe(f64, series.raw);
    for (series.missing, 0..) |missing, t| if (missing) {
        var a = t - 1;
        var b = t + 1;
        while (series.missing[a]) a -= 1;
        while (series.missing[b]) b += 1;
        interpolated[t] = series.raw[a] + (series.raw[b] - series.raw[a]) * io.f(t - a) / io.f(b - a);
    };
    const decomposition = d.decompose(interpolated, params.season);
    const half = params.season / 2;
    const residuals = decomposition.residual_add[half .. size - half];
    const residual_mean = d.mean(residuals);
    const residual_sd = @sqrt(d.sampleVariance(residuals));
    const corrected = io.dupe(f64, interpolated);
    const outliers = io.alloc(bool, size);
    @memset(outliers, false);
    const events = io.alloc(?[]const u8, size);
    @memset(events, null);
    var lifts: std.ArrayList(Lift) = .empty;
    var outlier_count: usize = 0;
    var event_count: usize = 0;
    var missing_count: usize = 0;
    for (0..size) |t| {
        if (series.missing[t]) missing_count += 1;
        events[t] = input.event(series.name, series.periods[t]);
        if (events[t]) |kind| {
            event_count += 1;
            var index: usize = 0;
            while (index < lifts.items.len and !io.eq(lifts.items[index].kind, kind)) index += 1;
            if (index == lifts.items.len) io.append(Lift, &lifts, .{ .kind = kind });
            io.append(f64, &lifts.items[index].values, interpolated[t] / (decomposition.trend[t] + decomposition.additive[t % params.season]));
        }
        if (t >= half and t < size - half and !series.missing[t] and events[t] == null and @abs(decomposition.residual_add[t] - residual_mean) > params.outlier * residual_sd) {
            outliers[t] = true;
            outlier_count += 1;
        }
        if (outliers[t] or events[t] != null) corrected[t] = decomposition.trend[t] + decomposition.additive[t % params.season];
        const flag = events[t] orelse if (series.missing[t]) "missing" else if (outliers[t]) "outlier" else "ok";
        out.decomposition.add("{s},{s},{s},{s},{s},{s},{s},{s},{s},{s}", .{ series.name, series.periods[t],
             io.real(interpolated[t]), io.real(corrected[t]), defined(decomposition.trend[t]), io.real(decomposition.additive[t % params.season]),
             defined(decomposition.residual_add[t]), io.real(decomposition.multiplicative[t % params.season]),
             defined(decomposition.residual_mult[t]), flag });
    }
    const trend_residual = io.alloc(f64, size - params.season);
    const seasonal_residual = io.alloc(f64, size - params.season);
    for (trend_residual, seasonal_residual, half..) |*trend, *season, t| {
        trend.* = decomposition.trend[t] + decomposition.residual_add[t];
        season.* = decomposition.additive[t % params.season] + decomposition.residual_add[t];
    }
    const residual_variance = d.sampleVariance(residuals);
    const strength_trend = @max(0, 1 - residual_variance / d.sampleVariance(trend_residual));
    const strength_season = @max(0, 1 - residual_variance / d.sampleVariance(seasonal_residual));
    const training = corrected[0..training_size];
    const actual = interpolated[training_size..];
    const fitted = io.alloc(Fitted, 11);
    for (fitted, 0..) |*model, method| model.* = fitMethod(method, training, params);
    const validations = io.alloc(CrossValidation, 12);
    for (0..11) |method| validations[method] = crossValidate(training, params, .{ .models = fitted, .method = method });
    const order = io.alloc(usize, 11);
    for (order, 0..) |*value, index| value.* = index;
    std.mem.sort(usize, order, @as([]const CrossValidation, validations), cvLess);
    const members = order[0..params.combo];
    std.mem.sort(usize, members, {}, numberLess);
    const combo: Forecaster = .{ .models = fitted, .method = 11, .members = members };
    validations[11] = crossValidate(training, params, combo);
    const forecasts = io.alloc([]f64, 12);
    const measures = io.alloc(evaluation.Accuracy, 12);
    const intervals = io.alloc([]Interval, 12);
    const delta = evaluation.scaleDelta(training, params.season);
    for (0..12) |method| {
        const forecaster: Forecaster = .{ .models = fitted, .method = method, .members = members };
        forecasts[method] = forecaster.forecast(training_size, params.holdout);
        measures[method] = evaluation.evaluate(actual, forecasts[method], validations[method].sigma,
             params.z80, params.z95, delta);
        measures[method].cv_rmse = validations[method].rmse;
        intervals[method] = io.alloc(Interval, params.holdout);
        for (intervals[method], 0..) |*row, k| row.* = interval(forecasts[method][k], validations[method].sigma[k], params, 1);
    }
    const best = evaluation.rank(measures)[0];
    const naive_mae = measures[0].mae;
    for (measures) |*measure| measure.fva = 100 * (naive_mae - measure.mae) / naive_mae;
    const final_fitted = io.alloc(Fitted, 11);
    if (best == 11) {
        for (members) |method| final_fitted[method] = fitMethod(method, corrected, params);
    } else final_fitted[best] = fitMethod(best, corrected, params);
    const final_forecast: Forecaster = .{ .models = final_fitted, .method = best, .members = members };
    const final_cv = crossValidate(corrected, params, final_forecast);
    const estimates = final_forecast.forecast(size, params.horizon);
    const future = io.alloc(Interval, params.horizon);
    for (future, 0..) |*row, k| {
        var multiplier: f64 = 1;
        if (input.event(series.name, series.periods[size + k])) |kind| {
            for (lifts.items) |lift| if (io.eq(lift.kind, kind)) {
                multiplier = d.mean(lift.values.items);
                break;
            };
        }
        row.* = interval(estimates[k], final_cv.sigma[k], params, multiplier);
    }
    out.models.add("series {s}", .{series.name});
    out.models.add("data observations {d} train {d} holdout {d} missing {d} outliers {d} events {d}",
         .{ size, training_size, params.holdout, missing_count, outlier_count, event_count });
    for (lifts.items) |lift| out.models.add("event {s} occurrences {d} lift {s}", .{ lift.kind, lift.values.items.len,
         io.real(d.mean(lift.values.items)) });
    for (outliers, 0..) |outlier, t| if (outlier) out.models.add("outlier {s} value {s} expected {s} score {s}",
         .{ series.periods[t], io.real(interpolated[t]), io.real(corrected[t]), io.real((decomposition.residual_add[t] - residual_mean) / residual_sd) });
    out.models.add("strength trend {s} seasonal {s}", .{ io.real(strength_trend), io.real(strength_season) });
    for (fitted) |model| out.models.extend(model.lines());
    var combo_names: io.Text = .{};
    for (members) |method| combo_names.add(" {s}", .{names[method]});
    out.models.add("combo members{s}", .{combo_names.value()});
    out.models.add("best {s} rmse {s}", .{ names[best], io.real(measures[best].rmse) });
    if (best == 11) {
        for (members) |method| for (final_fitted[method].lines().data.items) |line| out.models.add("final {s}", .{line});
    } else for (final_fitted[best].lines().data.items) |line| out.models.add("final {s}", .{line});
    for (0..12) |method| {
        for (0..params.holdout) |k| forecastRow(&out.forecasts, series.name, "holdout", names[method],
             series.periods[training_size + k], io.fmt("{d}", .{@as(i64, @intFromFloat(series.raw[training_size + k]))}),
             intervals[method][k]);
        const a = measures[method];
        out.accuracy.add("{s},{s},{s},{s},{s},{s},{s},{s},{s},{s},{d},{d},{s},{s},{d}", .{ series.name,
             names[method], io.real(a.me), io.real(a.mae), io.real(a.rmse), io.real(a.mape), io.real(a.smape),
             io.real(a.mase), io.real(a.fva), io.real(a.cv_rmse), a.cover80, a.cover95, io.real(a.winkler80),
             io.real(a.winkler95), a.rank });
        for (0..params.horizon) |k| out.cv.add("{s},{s},{d},{d},{s},{s}", .{ series.name, names[method],
             k + 1, validations[method].counts[k], io.real(validations[method].mae[k]), io.real(validations[method].sigma[k]) });
    }
    for (future, 0..) |row, k| forecastRow(&out.forecasts, series.name, "future", names[best], series.periods[size + k],
         "NA", row);
    diagnostics(&out.correlogram, series.name, fitted, params);
    charts(&out.chart, series, best, actual, intervals[best], future, decomposition, params);
    inventoryPlan(&out.plan, series, best, corrected, interpolated, future, inventory, params, final_forecast);
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    io.allocator = arena.allocator();
    const input = try io.readInput(init.io);
    var out = Outputs.init();
    for (input.series, input.inventory) |series, inventory| analyzeSeries(series, &input, inventory, &out);
    try out.write(init.io);
}
