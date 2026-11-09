const std = @import("std");
const d = @import("records.zig");
const cleaning = @import("cleaning.zig");
const harmonic = @import("harmonic_fit.zig");
const predict = @import("predict.zig");
const report = @import("report.zig");
const real = report.real;
const f = d.f;
const n = d.n;
const u = d.u;
const pi: f64 = 3.141592653589793;
const Selection = struct { chosen: std.ArrayList(usize) = .empty, status: []const []const u8 = &.{},
     speeds: []const f64 = &.{} };
fn select(input: d.Input, length: usize, rayleigh: f64) Selection {
    var out: Selection = .{};
    const statuses = d.alloc([]const u8, input.constituents.len);
    var speeds: std.ArrayList(f64) = .empty;
    for (input.constituents, 0..) |item, i| {
        var status: []const u8 = "fitted";
        if (item.speed * f(length) < 360 * rayleigh) status = "short" else {
            for (out.chosen.items) |previous| {
                if (@abs(item.speed - input.constituents[previous].speed) * f(length) < 360 * rayleigh) {
                    status = d.fmt("conflict:{s}", .{input.constituents[previous].name});
                    break;
                }
            }
        }
        statuses[i] = status;
        if (d.eq(status, "fitted")) {
            d.append(usize, &out.chosen, i);
            d.append(f64, &speeds, item.speed);
        }
    }
    out.status = statuses;
    out.speeds = speeds.items;
    return out;
}
const Day = struct { day: i64, high_count: usize = 0, low_count: usize = 0, best_high: ?usize = null,
     best_low: ?usize = null, hhw: ?f64 = null, llw: ?f64 = null, range: ?f64 = null };
const Event = struct { first: usize, last: usize, peak: usize, sign: i64 };
const DailyMean = struct { day: i64, filled: usize, level: f64 };
const State = struct { station: *const d.Station, first: usize, last: usize, selection: Selection = .{},
     model: *harmonic.Model = undefined, usable: []const d.Sample = &.{}, residuals: [10001]f64 = [_]f64{0} ** 10001,
     used: [10001]bool = [_]bool{false} ** 10001, hourly: []const f64 = &.{}, waters: std.ArrayList(predict.Extremum) = .empty,
     high: std.ArrayList(usize) = .empty, low: std.ArrayList(usize) = .empty, days: []Day = &.{},
     mhhw: f64 = 0, mllw: f64 = 0, mhw: f64 = 0, mlw: f64 = 0, mtl: f64 = 0, gt: f64 = 0, cleaning: d.Lines = .{},
     constituents: d.Lines = .{}, extremes: d.Lines = .{}, summary: d.Lines = .{} };
fn at(time: anytype, p: d.Params) []const u8 {
    return d.datetime(60 * n(time), p.epoch_day);
}
fn optional(value: ?f64) []const u8 {
    return if (value) |v| real(v, 3) else "none";
}
fn average(values: []const f64) f64 {
    var sum: f64 = 0;
    for (values) |value| sum += value;
    return sum / f(values.len);
}
fn modelIndex(state: *const State, input: d.Input, name: []const u8) usize {
    for (state.selection.chosen.items, 0..) |index, k| {
        if (d.eq(input.constituents[index].name, name)) return k;
    }
    unreachable;
}
fn amplitude(state: *const State, input: d.Input, name: []const u8) f64 {
    return state.model.amplitudes[modelIndex(state, input, name)];
}
fn phase(state: *const State, input: d.Input, name: []const u8) f64 {
    return state.model.phases[modelIndex(state, input, name)];
}
fn residualLess(state: *const State, a: usize, b: usize) bool {
    const x = @abs(state.residuals[a]);
    const y = @abs(state.residuals[b]);
    return if (x != y) x > y else a < b;
}
fn eventSign(state: *const State, time: usize, p: d.Params) i64 {
    const residual = state.residuals[time];
    return if (residual > p.surge) 1 else if (residual < -p.surge) -1 else 0;
}
fn analyze(s: *State, input: d.Input) void {
    const station = s.station;
    const p = input.params;
    const length = s.last - s.first;
    const reasons = d.alloc(cleaning.Reason, 10001);
    @memset(reasons, .usable);
    var numeric: usize = 0;
    var na: usize = 0;
    var absent: usize = 0;
    var flat_count: usize = 0;
    for (s.first..s.last + 1) |t| {
        if (!station.present[t]) {
            reasons[t] = .absent;
            absent += 1;
        } else if (station.observations[t] == null) {
            reasons[t] = .na;
            na += 1;
        } else numeric += 1;
    }
    const flats = cleaning.flatRuns(station, p.flat_run);
    for (flats) |flat| for (flat.first + 1..flat.last + 1) |t| {
        reasons[t] = .flat;
        flat_count += 1;
    };
    var candidates: std.ArrayList(d.Sample) = .empty;
    for (s.first..s.last + 1) |t| {
        if (station.observations[t]) |value| {
            if (reasons[t] == .usable) d.append(d.Sample, &candidates, .{ .time = t, .value = f(value) / 1000 });
        }
    }
    s.selection = select(input, length, p.rayleigh);
    const preliminary = harmonic.fit(candidates.items, s.selection.speeds);
    const pre_residuals = d.alloc(d.Sample, candidates.items.len);
    var pre_ss: f64 = 0;
    for (candidates.items, pre_residuals) |sample, *destination| {
        const value = sample.value - predict.prediction(preliminary, f(sample.time));
        destination.* = .{ .time = sample.time, .value = value };
        pre_ss += value * value;
    }
    const found_spikes = cleaning.spikes(pre_residuals, p);
    for (found_spikes.values) |spike| reasons[spike.time] = .spike;
    var usable: std.ArrayList(d.Sample) = .empty;
    for (candidates.items) |sample| {
        if (reasons[sample.time] == .usable) {
            d.append(d.Sample, &usable, sample);
            s.used[sample.time] = true;
        }
    }
    s.usable = usable.items;
    s.cleaning.add("station={s} name={s}", .{ station.code, station.name });
    s.cleaning.add("span start={s} end={s} hours={d} record_length={d}", .{ at(s.first, p),
         at(s.last, p), length + 1, length });
    s.cleaning.add("counts rows={d} numeric={d} na={d} absent={d} flat={d} spikes={d} usable={d}",
         .{ station.rows, numeric, na, absent, flat_count, found_spikes.values.len, s.usable.len });
    for (flats) |flat| s.cleaning.add("flat start={s} end={s} value={s} removed={d}", .{ at(flat.first,
         p), at(flat.last, p), real(f(flat.milli) / 1000, 3), flat.last - flat.first });
    s.cleaning.add("spike_test window={d} candidates={d} tested={d} prefit_rms={s}", .{ p.spike_window,
         candidates.items.len, found_spikes.tested, real(@sqrt(pre_ss / f(candidates.items.len)),
         4) });
    for (found_spikes.values) |spike| s.cleaning.add("spike time={s} value={s} residual={s} median={s} mad={s} limit={s}",
         .{ at(spike.time, p), real(f(station.observations[spike.time].?) / 1000, 3), real(spike.residual,
         4), real(spike.median, 4), real(spike.mad, 4), real(spike.limit, 4) });
    for (cleaning.gaps(reasons, s.first, s.last)) |gap| s.cleaning.add("gap start={s} end={s} hours={d} cause={s}",
         .{ at(gap.first, p), at(gap.last, p), gap.last - gap.first + 1, @tagName(gap.cause) });
    s.model = harmonic.fit(s.usable, s.selection.speeds);
    const unknowns = s.model.size;
    const count = s.usable.len;
    const dof = count - unknowns;
    var ss: f64 = 0;
    var max_abs: f64 = 0;
    var mean: f64 = 0;
    for (s.usable) |sample| {
        const residual = sample.value - predict.prediction(s.model, f(sample.time));
        s.residuals[sample.time] = residual;
        ss += residual * residual;
        max_abs = @max(max_abs, @abs(residual));
        mean += sample.value;
    }
    mean /= f(count);
    const variance = ss / f(dof);
    var observed_ss: f64 = 0;
    var lag_numerator: f64 = 0;
    var lag_denominator: f64 = 0;
    for (s.usable) |sample| {
        const centered = sample.value - mean;
        observed_ss += centered * centered;
        if (sample.time < s.last and s.used[sample.time + 1]) {
            const residual = s.residuals[sample.time];
            lag_numerator += residual * s.residuals[sample.time + 1];
            lag_denominator += residual * residual;
        }
    }
    var fitted_index: usize = 0;
    for (input.constituents, 0..) |item, i| {
        if (!d.eq(s.selection.status[i], "fitted")) {
            s.constituents.add("{s},{s},{s},{s},,,,,,", .{ station.code, item.name, real(item.speed,
                 7), s.selection.status[i] });
            continue;
        }
        const k = fitted_index;
        fitted_index += 1;
        const ia = 2 * k + 1;
        const ib = 2 * k + 2;
        const a = s.model.coefficients[ia];
        const b = s.model.coefficients[ib];
        const amp = s.model.amplitudes[k];
        const va = variance * s.model.inverse[ia][ia];
        const vb = variance * s.model.inverse[ib][ib];
        const cab = variance * s.model.inverse[ia][ib];
        const amplitude_error = @sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amp;
        const phase_error = @sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amp * amp) * 180 / pi;
        const ratio = amp / amplitude_error;
        const snr = ratio * ratio;
        s.constituents.add("{s},{s},{s},fitted,{s},{s},{s},{s},{s},{s}", .{ station.code, item.name,
             real(item.speed, 7), real(amp, 4), real(s.model.phases[k], 2), real(amplitude_error,
             4), real(phase_error, 2), real(snr, 1), if (snr >= p.snr) "yes" else "no" });
    }
    const hourly = d.alloc(f64, p.length + 1);
    for (hourly, 0..) |*value, i| value.* = predict.prediction(s.model, f(p.start + n(i)));
    s.hourly = hourly;
    s.waters = predict.extrema(s.model, p.start, p.length, p.grid);
    const raw = s.waters.items.len;
    while (s.waters.items.len >= 2) {
        var first: usize = 0;
        var minimum = @abs(s.waters.items[0].height - s.waters.items[1].height);
        for (1..s.waters.items.len - 1) |i| {
            const difference = @abs(s.waters.items[i].height - s.waters.items[i + 1].height);
            if (difference < minimum) {
                minimum = difference;
                first = i;
            }
        }
        if (minimum >= p.min_range) break;
        _ = s.waters.orderedRemove(first);
        _ = s.waters.orderedRemove(first);
    }
    s.days = d.alloc(Day, p.length / 24);
    for (s.days, 0..) |*day, i| day.* = .{ .day = @divTrunc(p.start, 24) + n(i) };
    for (s.waters.items, 0..) |*water, i| {
        water.minute = @intFromFloat(@floor(water.mu + 0.5));
        const day = &s.days[u(@divTrunc(water.minute, 1440) - @divTrunc(p.start, 24))];
        if (water.high) {
            d.append(usize, &s.high, i);
            day.high_count += 1;
            if (day.best_high == null or water.height > s.waters.items[day.best_high.?].height) day.best_high = i;
        } else {
            d.append(usize, &s.low, i);
            day.low_count += 1;
            if (day.best_low == null or water.height < s.waters.items[day.best_low.?].height) day.best_low = i;
        }
    }
    for (s.days) |*day| {
        if (day.best_high) |i| day.hhw = s.waters.items[i].height;
        if (day.best_low) |i| day.llw = s.waters.items[i].height;
        if (day.hhw != null and day.llw != null) day.range = day.hhw.? - day.llw.?;
    }
    for (s.waters.items, 0..) |*water, i| {
        const day = s.days[u(@divTrunc(water.minute, 1440) - @divTrunc(p.start, 24))];
        water.label = if (water.high) (if (i == day.best_high.?) @as(usize, 0) else 1) else (if (i == day.best_low.?) @as(usize,
             3) else 2);
    }
    s.extremes.add("station={s} extremes={d} raw={d} removed={d}", .{ station.code, s.waters.items.len,
         raw, raw - s.waters.items.len });
    const labels = [4][]const u8{ "HHW", "LHW", "HLW", "LLW" };
    for (s.waters.items, 0..) |water, i| s.extremes.add("{s} {s} {s} change={s}", .{ d.datetime(water.minute,
         p.epoch_day), labels[water.label], real(water.height, 3), if (i > 0) real(water.height - s.waters.items[i - 1].height,
         3) else "none" });
    for (s.days) |day| s.extremes.add("day date={s} high_waters={d} low_waters={d} hhw={s} llw={s} range={s}",
         .{ d.date(day.day, p.epoch_day), day.high_count, day.low_count, optional(day.hhw),
         optional(day.llw), optional(day.range) });
    var hhws: std.ArrayList(f64) = .empty;
    var llws: std.ArrayList(f64) = .empty;
    var highs: std.ArrayList(f64) = .empty;
    var lows: std.ArrayList(f64) = .empty;
    for (s.days) |day| {
        if (day.hhw) |value| d.append(f64, &hhws, value);
        if (day.llw) |value| d.append(f64, &llws, value);
    }
    for (s.high.items) |i| d.append(f64, &highs, s.waters.items[i].height);
    for (s.low.items) |i| d.append(f64, &lows, s.waters.items[i].height);
    s.mhhw = average(hhws.items);
    s.mllw = average(llws.items);
    s.mhw = average(highs.items);
    s.mlw = average(lows.items);
    s.mtl = (s.mhw + s.mlw) / 2;
    s.gt = s.mhhw - s.mllw;
    const amp_m2 = amplitude(s, input, "M2");
    const amp_s2 = amplitude(s, input, "S2");
    const amp_k1 = amplitude(s, input, "K1");
    const amp_o1 = amplitude(s, input, "O1");
    const amp_m4 = amplitude(s, input, "M4");
    const phase_m2 = phase(s, input, "M2");
    const phase_s2 = phase(s, input, "S2");
    const phase_m4 = phase(s, input, "M4");
    const form = (amp_k1 + amp_o1) / (amp_m2 + amp_s2);
    const spring = 2 * (amp_m2 + amp_s2);
    const neap = 2 * (amp_m2 - amp_s2);
    var sum_amplitudes: f64 = 0;
    for (s.model.amplitudes[0..s.model.count]) |value| sum_amplitudes += value;
    var rise: std.ArrayList(f64) = .empty;
    var fall: std.ArrayList(f64) = .empty;
    for (1..s.waters.items.len) |i| {
        const previous = s.waters.items[i - 1];
        const water = s.waters.items[i];
        if (!previous.high and water.high) d.append(f64, &rise, f(water.minute - previous.minute));
        if (previous.high and !water.high) d.append(f64, &fall, f(water.minute - previous.minute));
    }
    var relative = 2 * phase_m2 - phase_m4;
    while (relative < 0) relative += 360;
    while (relative >= 360) relative -= 360;
    var highest = s.high.items[0];
    var lowest = s.low.items[0];
    var widest: ?usize = null;
    var narrowest: ?usize = null;
    for (s.high.items) |i| {
        if (s.waters.items[i].height > s.waters.items[highest].height) highest = i;
    }
    for (s.low.items) |i| {
        if (s.waters.items[i].height < s.waters.items[lowest].height) lowest = i;
    }
    for (s.days, 0..) |day, i| {
        if (day.range) |value| {
            if (widest == null or value > s.days[widest.?].range.?) widest = i;
            if (narrowest == null or value < s.days[narrowest.?].range.?) narrowest = i;
        }
    }
    var above: usize = 0;
    var below: usize = 0;
    for (s.hourly) |value| {
        above += @intFromBool(value > s.mhhw);
        below += @intFromBool(value < s.mllw);
    }
    const mid = s.first + length / 2;
    var training: std.ArrayList(d.Sample) = .empty;
    var test_data: std.ArrayList(d.Sample) = .empty;
    for (s.usable) |sample| {
        if (sample.time <= mid) d.append(d.Sample, &training, sample) else d.append(d.Sample, &test_data, sample);
    }
    const validation_selection = select(input, training.items[training.items.len - 1].time - training.items[0].time,
         p.rayleigh);
    const validation = harmonic.fit(training.items, validation_selection.speeds);
    var test_ss: f64 = 0;
    var in_sample: f64 = 0;
    var test_mean: f64 = 0;
    var test_variance: f64 = 0;
    for (test_data.items) |sample| test_mean += sample.value;
    test_mean /= f(test_data.items.len);
    for (test_data.items) |sample| {
        const residual = sample.value - predict.prediction(validation, f(sample.time));
        test_ss += residual * residual;
        const fitted_residual = s.residuals[sample.time];
        in_sample += fitted_residual * fitted_residual;
        const centered = sample.value - test_mean;
        test_variance += centered * centered;
    }
    s.summary.add("[station {s}] {s}", .{ station.code, station.name });
    s.summary.add("record first={s} last={s} length={d} usable={d}", .{ at(s.first, p), at(s.last, p), length, count });
    s.summary.add("fit constituents={d} unknowns={d} dof={d} mean_level={s}", .{ s.selection.chosen.items.len,
         unknowns, dof, real(s.model.coefficients[0], 4) });
    s.summary.add("residual rms={s} max_abs={s} explained_percent={s} lag1_autocorrelation={s}",
         .{ real(@sqrt(ss / f(count)), 4), real(max_abs, 4), real(100 * (1 - ss / observed_ss),
         4), real(lag_numerator / lag_denominator, 4) });
    const top = d.alloc(usize, count);
    for (s.usable, top) |sample, *t| t.* = sample.time;
    std.mem.sort(usize, top, @as(*const State, s), residualLess);
    for (top[0..p.top], 1..) |t, i| s.summary.add("top_residual rank={d} time={s} observed={s} fitted={s} residual={s}",
         .{ i, at(t, p), real(f(station.observations[t].?) / 1000, 3), real(predict.prediction(s.model,
         f(t)), 4), real(s.residuals[t], 4) });
    s.summary.add("validation split={s} train={d} test={d} constituents={d} rms={s} in_sample_rms={s} skill={s}",
         .{ at(mid, p), training.items.len, test_data.items.len, validation_selection.chosen.items.len,
         real(@sqrt(test_ss / f(test_data.items.len)), 4), real(@sqrt(in_sample / f(test_data.items.len)),
         4), real(1 - test_ss / test_variance, 4) });
    s.summary.add("form_number={s} type={s}", .{ real(form, 4), if (form < 0.25) "semidiurnal" else if (form < 1.5) "mixed_semidiurnal" else if (form < 3) "mixed_diurnal" else "diurnal" });
    s.summary.add("ranges spring={s} neap={s} mn={s} gt={s}", .{ real(spring, 3), real(neap,
         3), real(s.mhw - s.mlw, 3), real(s.gt, 3) });
    s.summary.add("asymmetry rise_minutes={s} fall_minutes={s} m4_m2_ratio={s} relative_phase={s} dominance={s}",
         .{ real(average(rise.items), 1), real(average(fall.items), 1), real(amp_m4 / amp_m2,
         4), real(relative, 2), if (relative < 180) "flood" else "ebb" });
    s.summary.add("datums mhhw={s} mhw={s} mtl={s} dtl={s} mlw={s} mllw={s}", .{ real(s.mhhw,
         3), real(s.mhw, 3), real(s.mtl, 3), real((s.mhhw + s.mllw) / 2, 3), real(s.mlw, 3),
         real(s.mllw, 3) });
    s.summary.add("bounds hat={s} lat={s}", .{ real(s.model.coefficients[0] + sum_amplitudes,
         3), real(s.model.coefficients[0] - sum_amplitudes, 3) });
    s.summary.add("window high_waters={d} low_waters={d} highest={s} highest_time={s} lowest={s} lowest_time={s}",
         .{ s.high.items.len, s.low.items.len, real(s.waters.items[highest].height, 3), d.datetime(s.waters.items[highest].minute,
         p.epoch_day), real(s.waters.items[lowest].height, 3), d.datetime(s.waters.items[lowest].minute,
         p.epoch_day) });
    s.summary.add("daily_range widest={s} widest_date={s} narrowest={s} narrowest_date={s}",
         .{ real(s.days[widest.?].range.?, 3), d.date(s.days[widest.?].day, p.epoch_day), real(s.days[narrowest.?].range.?,
         3), d.date(s.days[narrowest.?].day, p.epoch_day) });
    s.summary.add("exceedance above_mhhw={s} below_mllw={s}", .{ real(100 * f(above) / f(p.length + 1),
         2), real(100 * f(below) / f(p.length + 1), 2) });
    const dw = s.model.speeds[modelIndex(s, input, "S2")] - s.model.speeds[modelIndex(s, input, "M2")];
    const dg = phase_s2 - phase_m2;
    const q1 = (dw * f(p.start) - dg) / 180;
    const q2 = (dw * f(p.start + n(p.length)) - dg) / 180;
    const qfirst = @as(i64, @intFromFloat(@floor(@min(q1, q2)))) - 1;
    const qlast = @as(i64, @intFromFloat(@ceil(@max(q1, q2)))) + 1;
    var q = qfirst;
    while (q <= qlast) : (q += 1) {
        const t = (dg + 180 * f(q)) / dw;
        if (f(p.start) <= t and t <= f(p.start + n(p.length))) s.summary.add("{s} time={s}",
             .{ if (@mod(q, 2) == 0) "spring" else "neap", d.datetime(@intFromFloat(@floor(t * 60 + 0.5)),
             p.epoch_day) });
    }
    var events: std.ArrayList(Event) = .empty;
    var position: usize = 0;
    while (position < count) {
        const t = s.usable[position].time;
        const sign = eventSign(s, t, p);
        if (sign == 0) {
            position += 1;
            continue;
        }
        const first = t;
        var last = t;
        var peak = t;
        while (position + 1 < count and s.usable[position + 1].time == last + 1 and eventSign(s,
             s.usable[position + 1].time, p) == sign) {
            position += 1;
            last = s.usable[position].time;
            if ((sign > 0 and s.residuals[last] > s.residuals[peak]) or (sign < 0 and s.residuals[last] < s.residuals[peak])) peak = last;
        }
        if (last - first + 1 >= p.surge_hours) d.append(Event, &events, .{ .first = first,
             .last = last, .peak = peak, .sign = sign });
        position += 1;
    }
    s.summary.add("surges count={d} threshold={s} min_hours={d}", .{ events.items.len, real(p.surge,
         3), p.surge_hours });
    for (events.items) |event| s.summary.add("surge type={s} start={s} end={s} hours={d} peak={s} peak_time={s}",
         .{ if (event.sign > 0) "positive" else "negative", at(event.first, p), at(event.last,
         p), event.last - event.first + 1, real(s.residuals[event.peak], 4), at(event.peak,
         p) });
    const weights = [20]i64{ 0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1 };
    var means: std.ArrayList(DailyMean) = .empty;
    for (s.first / 24..s.last / 24 + 1) |day| {
        const noon = 24 * n(day) + 12;
        if (noon - 19 < n(s.first) or noon + 19 > n(s.last)) continue;
        var sum: f64 = 0;
        var filled: usize = 0;
        var j: i64 = -19;
        while (j <= 19) : (j += 1) {
            const t = u(noon + j);
            const is_usable = s.used[t];
            const value = if (is_usable) f(station.observations[t].?) / 1000 else predict.prediction(s.model, f(t));
            sum += f(weights[@intCast(@abs(j))]) * value;
            filled += @intFromBool(!is_usable);
        }
        d.append(DailyMean, &means, .{ .day = n(day), .filled = filled, .level = sum / 30 });
    }
    const x = d.alloc(f64, means.items.len);
    const levels = d.alloc(f64, means.items.len);
    var maximum: usize = 0;
    var minimum: usize = 0;
    for (means.items, 0..) |record, i| {
        x[i] = f(record.day - means.items[0].day);
        levels[i] = record.level;
        if (record.level > means.items[maximum].level) maximum = i;
        if (record.level < means.items[minimum].level) minimum = i;
    }
    const xm = average(x);
    const vm = average(levels);
    var numerator: f64 = 0;
    var denominator: f64 = 0;
    for (x, levels) |value, level| {
        const dx = value - xm;
        numerator += dx * (level - vm);
        denominator += dx * dx;
    }
    s.summary.add("daily_mean days={d} average={s} slope_mm_per_day={s} max={s} max_date={s} min={s} min_date={s}",
         .{ means.items.len, real(vm, 4), real(1000 * (numerator / denominator), 3), real(means.items[maximum].level,
         4), d.date(means.items[maximum].day, p.epoch_day), real(means.items[minimum].level,
         4), d.date(means.items[minimum].day, p.epoch_day) });
    for (means.items) |record| s.summary.add("daily_mean date={s} level={s} filled={d}", .{ d.date(record.day,
         p.epoch_day), real(record.level, 4), record.filled });
}
fn lag(station: *const State, reference: *const State, high: bool) f64 {
    const items = if (high) station.high.items else station.low.items;
    const ref = if (high) reference.high.items else reference.low.items;
    var sum: f64 = 0;
    for (items) |i| {
        const minute = station.waters.items[i].minute;
        var best = ref[0];
        for (ref) |j| {
            const difference = @abs(minute - reference.waters.items[j].minute);
            const previous = @abs(minute - reference.waters.items[best].minute);
            if (difference < previous or (difference == previous and reference.waters.items[j].minute < reference.waters.items[best].minute)) best = j;
        }
        sum += f(minute - reference.waters.items[best].minute);
    }
    return sum / f(items.len);
}
const Correlation = struct { value: f64, pairs: usize };
fn correlation(a: *const State, b: *const State, offset: i64) Correlation {
    var x: std.ArrayList(f64) = .empty;
    var y: std.ArrayList(f64) = .empty;
    for (a.usable) |sample| {
        const other = n(sample.time) + offset;
        if (other < 0 or other > 10000 or !b.used[u(other)]) continue;
        d.append(f64, &x, a.residuals[sample.time]);
        d.append(f64, &y, b.residuals[u(other)]);
    }
    const xm = average(x.items);
    const ym = average(y.items);
    var cross: f64 = 0;
    var xx: f64 = 0;
    var yy: f64 = 0;
    for (x.items, y.items) |vx, vy| {
        const dx = vx - xm;
        const dy = vy - ym;
        cross += dx * dy;
        xx += dx * dx;
        yy += dy * dy;
    }
    return .{ .value = cross / @sqrt(xx * yy), .pairs = x.items.len };
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const io = init.io;
    const input = try d.load(io);
    const p = input.params;
    const states = d.alloc(*State, input.stations.len);
    var cleaning_lines: d.Lines = .{};
    var constituents: d.Lines = .{};
    var predictions: d.Lines = .{};
    var waters: d.Lines = .{};
    var summary: d.Lines = .{};
    constituents.add("station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant",
         .{});
    var header: d.Text = .{};
    header.add("time", .{});
    for (input.stations) |station| header.add(",{s}", .{station.code});
    predictions.add("{s}", .{header.value()});
    var reference_index: usize = 0;
    var plot_index: usize = 0;
    for (input.stations, 0..) |*station, i| {
        states[i] = d.create(State, .{ .station = station, .first = station.first, .last = station.last });
        analyze(states[i], input);
        cleaning_lines.extend(states[i].cleaning);
        constituents.extend(states[i].constituents);
        waters.extend(states[i].extremes);
        summary.extend(states[i].summary);
        if (d.eq(station.code, p.reference)) reference_index = i;
        if (d.eq(station.code, p.plot)) plot_index = i;
    }
    for (0..p.length + 1) |i| {
        var row: d.Text = .{};
        row.add("{s}", .{at(p.start + n(i), p)});
        for (states) |state| row.add(",{s}", .{real(state.hourly[i], 3)});
        predictions.add("{s}", .{row.value()});
    }
    const reference = states[reference_index];
    summary.add("[comparison] reference={s}", .{p.reference});
    const compared = [4][]const u8{ "M2", "S2", "K1", "O1" };
    for (states, 0..) |state, i| {
        if (i == reference_index) continue;
        summary.add("{s} tide hw_lag_min={s} lw_lag_min={s} range_ratio={s} mtl_diff={s}",
             .{ state.station.code, real(lag(state, reference, true), 1), real(lag(state, reference,
             false), 1), real(state.gt / reference.gt, 4), real(state.mtl - reference.mtl,
             3) });
        for (compared) |name| {
            const k = modelIndex(state, input, name);
            const kr = modelIndex(reference, input, name);
            var phase_difference = state.model.phases[k] - reference.model.phases[kr];
            if (phase_difference > 180) phase_difference -= 360;
            if (phase_difference <= -180) phase_difference += 360;
            summary.add("{s} {s} amplitude_ratio={s} phase_diff={s} time_lag_min={s}", .{ state.station.code,
                 name, real(state.model.amplitudes[k] / reference.model.amplitudes[kr], 4),
                 real(phase_difference, 2), real(phase_difference / state.model.speeds[k] * 60,
                 1) });
        }
    }
    summary.add("[correlation] max_lag={d}", .{p.lag});
    for (0..states.len) |a| for (a + 1..states.len) |b| {
        var best_lag = -p.lag;
        var best = correlation(states[a], states[b], best_lag);
        const zero = correlation(states[a], states[b], 0);
        var offset = -p.lag + 1;
        while (offset <= p.lag) : (offset += 1) {
            const value = correlation(states[a], states[b], offset);
            if (value.value > best.value or (value.value == best.value and (@abs(offset) < @abs(best_lag) or (@abs(offset) == @abs(best_lag) and offset < best_lag)))) {
                best = value;
                best_lag = offset;
            }
        }
        summary.add("{s}-{s} lag0={s} best_lag={d} best={s} pairs={d}", .{ states[a].station.code,
             states[b].station.code, real(zero.value, 4), best_lag, real(best.value, 4), best.pairs });
    };
    const plotted = states[plot_index];
    summary.add("[plot] station={s} start={s} hours={d} step_cm={d}", .{ p.plot, at(p.start,
         p), p.plot_hours, p.plot_step });
    const rows = u(@divTrunc(p.plot_top - p.plot_bottom, p.plot_step) + 1);
    const cells = d.alloc([]u8, rows);
    for (cells) |*row| {
        row.* = d.alloc(u8, p.plot_hours);
        @memset(row.*, ' ');
    }
    const zero_row: i64 = @intFromFloat(@floor((f(p.plot_top) - 100 * plotted.model.coefficients[0]) / f(p.plot_step) + 0.5));
    if (zero_row >= 0 and zero_row < n(rows)) @memset(cells[u(zero_row)], '-');
    const marks = d.alloc(u8, p.plot_hours);
    @memset(marks, ' ');
    for (plotted.waters.items) |water| {
        const column = @divTrunc(water.minute - 60 * p.start + 30, 60);
        if (column >= 0 and column < n(p.plot_hours)) marks[u(column)] = if (water.high) 'H' else 'L';
    }
    for (0..p.plot_hours) |column| {
        const row: i64 = @intFromFloat(@floor((f(p.plot_top) - 100 * plotted.hourly[column]) / f(p.plot_step) + 0.5));
        if (row < 0) cells[0][column] = '^' else if (row >= n(rows)) cells[rows - 1][column] = 'v' else cells[u(row)][column] = if (marks[column] == ' ') '*' else marks[column];
    }
    const heights = d.alloc(f64, rows);
    for (heights, 0..) |*height, row| height.* = f(p.plot_top - n(row) * p.plot_step) / 100;
    const axis = d.alloc(u8, p.plot_hours);
    for (axis, 0..) |*c, column| c.* = if (column % 6 == 0) '+' else '-';
    summary.extend(report.plotLines(heights, cells, axis));
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try report.save(io, "cleaning.txt", cleaning_lines);
    try report.save(io, "constituents.csv", constituents);
    try report.save(io, "predictions.csv", predictions);
    try report.save(io, "extremes.txt", waters);
    try report.save(io, "summary.txt", summary);
}
