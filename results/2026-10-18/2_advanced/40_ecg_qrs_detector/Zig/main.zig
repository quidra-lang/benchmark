const std = @import("std");
const c = @import("signal_io.zig");
const filters = @import("filters.zig");
const detector = @import("detector.zig");
const hrv = @import("hrv.zig");
const report = @import("report.zig");
fn num(value: anytype) []const u8 {
    return c.fmt("{d}", .{value});
}
fn labelIndex(label: u8) usize {
    return if (label == 'N') 0 else if (label == 'V') 1 else 2;
}
fn repeat(character: u8, count: usize) []u8 {
    const out = c.alloc(u8, count);
    @memset(out, character);
    return out;
}
fn alignment(value: []const u8, width: usize) []const u8 {
    return c.fmt("{s}{s}", .{ repeat(' ', width -| value.len), value });
}
const Beat = struct { peak: usize, sample: usize = 0, reference: ?usize = null, rr: i64 = 0, width: i64 = 0, label: u8 = 'N' };
fn thresholds(levels: detector.Levels) [2]i64 {
    return .{ levels.npki + @divFloor(levels.spki - levels.npki, 4), levels.npkf + @divFloor(levels.spkf - levels.npkf, 4) };
}
const Detection = struct {
    peaks: []detector.Peak,
    beats: std.ArrayList(Beat) = .empty,
    initial: detector.Levels,
    levels: detector.Levels,
    last: ?usize = null,
    ra1: i64 = 200,
    ra2: i64 = 200,
    recent: std.ArrayList(i64) = .empty,
    fn registerBeat(self: *Detection, index: usize) void {
        if (self.last) |last| {
            const interval = c.n(self.peaks[index].time) - c.n(self.peaks[last].time);
            c.append(i64, &self.recent, interval);
            if (self.recent.items.len > 8) _ = self.recent.orderedRemove(0);
            var sum: i64 = 0;
            for (self.recent.items) |value| sum += value;
            self.ra1 = @divFloor(sum, c.n(self.recent.items.len));
            if (92 * self.ra1 <= 100 * interval and 100 * interval <= 116 * self.ra1) self.ra2 = self.ra1;
        }
        self.last = index;
        c.append(Beat, &self.beats, .{ .peak = index });
    }
    fn update(self: *Detection, peak: detector.Peak, kind: usize) void {
        if (kind == 0) {
            self.levels.spki = @divFloor(peak.integrated + 7 * self.levels.spki, 8);
            self.levels.spkf = @divFloor(peak.filtered + 7 * self.levels.spkf, 8);
        } else if (kind == 1) {
            self.levels.npki = @divFloor(peak.integrated + 7 * self.levels.npki, 8);
            self.levels.npkf = @divFloor(peak.filtered + 7 * self.levels.npkf, 8);
        } else {
            self.levels.spki = @divFloor(peak.integrated + 3 * self.levels.spki, 4);
            self.levels.spkf = @divFloor(peak.filtered + 3 * self.levels.spkf, 4);
        }
    }
    fn searchback(self: *Detection, params: c.Params, time: usize) void {
        while (true) {
            const t0 = if (self.last) |last| self.peaks[last].time else 0;
            if (c.n(time) - c.n(t0) <= @divFloor(self.ra2 * params.searchback_percent, 100)) break;
            const threshold = thresholds(self.levels);
            var selected: ?usize = null;
            for (self.peaks, 0..) |peak, i| if (peak.kind == .noise and peak.time > t0 and peak.time < time and peak.integrated > @divFloor(threshold[0],
                 2) and peak.filtered > @divFloor(threshold[1], 2) and (selected == null or peak.integrated > self.peaks[selected.?].integrated)) {
                selected = i;
            };
            if (selected == null) break;
            const index = selected.?;
            self.update(self.peaks[index], 2);
            self.peaks[index].kind = .searchback;
            self.registerBeat(index);
        }
    }
};
fn detect(signals: filters.Signals, params: c.Params) Detection {
    const initial = detector.initialLevels(signals);
    var out: Detection = .{ .peaks = detector.findPeaks(signals).items, .initial = initial, .levels = initial };
    for (out.peaks, 0..) |*peak, i| {
        out.searchback(params, peak.time);
        const threshold = thresholds(out.levels);
        peak.thr_i = threshold[0];
        peak.thr_f = threshold[1];
        if (out.last != null and c.n(peak.time) - c.n(out.peaks[out.last.?].time) < @divFloor(params.refractory_ms,
             5)) peak.kind = .refractory else if (peak.integrated > peak.thr_i and peak.filtered > peak.thr_f) {
            if (out.last != null and c.n(peak.time) - c.n(out.peaks[out.last.?].time) < @divFloor(params.twave_ms,
                 5) and 2 * peak.slope < out.peaks[out.last.?].slope) {
                peak.kind = .twave;
                out.update(peak.*, 1);
            } else {
                peak.kind = .qrs;
                out.update(peak.*, 0);
                out.registerBeat(i);
            }
        } else {
            peak.kind = .noise;
            out.update(peak.*, 1);
        }
    }
    out.searchback(params, signals.integrated.len);
    for (out.beats.items, 0..) |*beat, i| {
        const peak = out.peaks[beat.peak];
        beat.sample = peak.r -| 21;
        beat.width = detector.qrsWidth(signals, peak.r);
        if (i > 0) beat.rr = 5 * c.n(beat.sample - out.beats.items[i - 1].sample);
        if (i >= 9) {
            var preceding: i64 = 0;
            for (out.beats.items[i - 8 .. i]) |other| preceding += other.rr;
            if (800 * beat.rr < params.premature_percent * preceding) beat.label = if (beat.width > params.qrs_width_ms) 'V' else 'A';
        }
    }
    return out;
}
fn match(beats: []Beat, annotations: []c.Annotation, tolerance: i64) void {
    for (beats, 0..) |*beat, k| {
        var selected: ?usize = null;
        var distance: i64 = 0;
        for (annotations, 0..) |annotation, i| {
            const difference = detector.abs(c.n(annotation.sample) - c.n(beat.sample));
            if (annotation.beat == null and difference <= tolerance and (selected == null or difference < distance)) {
                selected = i;
                distance = difference;
            }
        }
        if (selected) |index| {
            beat.reference = index;
            annotations[index].beat = k;
        }
    }
}
fn scale(value: i64, top: i64, bottom: i64, rows: usize) usize {
    return if (top > bottom) c.u(report.rdiv((top - value) * c.n(rows - 1), top - bottom)) else 0;
}
fn waveform(out: *c.Lines, upper: []const i64, lower: []const i64, rows: usize) void {
    var top = upper[0];
    var bottom = lower[0];
    for (upper, lower) |high, low| {
        top = @max(top, high);
        bottom = @min(bottom, low);
    }
    const zero: ?usize = if (bottom <= 0 and top >= 0) scale(0, top, bottom, rows) else null;
    for (0..rows) |row| {
        const label = if (row == 0) num(top) else if (row == rows - 1) num(bottom) else if (zero != null and row == zero.?) "0" else "";
        const marks = repeat(' ', upper.len);
        for (upper, lower, marks) |high, low, *mark| mark.* = if (scale(high, top, bottom, rows) <= row and row <= scale(low,
             top, bottom, rows)) '#' else if (zero != null and row == zero.?) '-' else ' ';
        out.add("{s} |{s}|", .{ alignment(label, 6), marks });
    }
}
fn axis(columns: usize, period: usize, offset: usize) []const u8 {
    const marks = repeat('-', columns);
    if (period > 0) for (marks, 0..) |*mark, i| {
        if ((i + offset) % period == 0) mark.* = '+';
    };
    return c.fmt("       +{s}+", .{marks});
}
const Label = struct { column: usize, text: []const u8 };
fn labelRow(heading: []const u8, labels: []const Label) []const u8 {
    var out: c.Text = .{};
    out.add("{s}  ", .{alignment(heading, 6)});
    for (labels) |label| {
        out.add("{s}{s}", .{ repeat(' ', (8 + label.column) -| out.value().len), label.text });
    }
    var end = out.value().len;
    while (end > 0 and out.value()[end - 1] == ' ') end -= 1;
    return out.value()[0..end];
}
fn charts(input: c.Input, detection: Detection) c.Lines {
    const beats = detection.beats.items;
    const count = beats.len;
    const rows = c.u(input.params.chart_rows);
    var out: c.Lines = .{};
    var rr: std.ArrayList(i64) = .empty;
    for (beats[1..]) |beat| c.append(i64, &rr, beat.rr);
    if (rr.items.len == 0) {
        out.add("TACHOGRAM intervals=0", .{});
        out.add("POINCARE points=0", .{});
    } else {
        const lo = std.mem.min(i64, rr.items);
        const hi = std.mem.max(i64, rr.items);
        out.add("TACHOGRAM intervals={d} min_ms={d} max_ms={d} rows={d}", .{ rr.items.len, lo, hi, rows });
        for (0..rows) |row| {
            const marks = repeat(' ', rr.items.len);
            for (rr.items, marks) |value, *mark| if (scale(value, hi, lo, rows) == row) {
                mark.* = '*';
            };
            out.add("{s} |{s}|", .{ alignment(if (row == 0) num(hi) else if (row == rows - 1) num(lo) else "", 6), marks });
        }
        out.add("{s}", .{axis(rr.items.len, 10, 2)});
        var labels: std.ArrayList(Label) = .empty;
        for (0..rr.items.len) |j| if ((j + 2) % 10 == 0) c.append(Label, &labels, .{ .column = j, .text = num(j + 2) });
        out.add("{s}", .{labelRow("beat", labels.items)});
        const marks = c.alloc(u8, rr.items.len);
        for (beats[1..], marks) |beat, *mark| mark.* = beat.label;
        out.add(" label |{s}|", .{marks});
        const side = c.u(input.params.poincare_size);
        const cells = c.alloc(usize, side * side);
        @memset(cells, 0);
        for (0..rr.items.len - 1) |i| {
            const column = if (hi > lo) c.u(report.rdiv((rr.items[i] - lo) * c.n(side - 1), hi - lo)) else 0;
            const row = scale(rr.items[i + 1], hi, lo, side);
            cells[row * side + column] += 1;
        }
        out.add("POINCARE points={d} size={d} min_ms={d} max_ms={d}", .{ count - 2, side, lo, hi });
        for (0..side) |row| {
            const points = c.alloc(u8, side);
            for (points, 0..) |*point, i| {
                const value = cells[row * side + i];
                point.* = if (value == 0) '.' else if (value >= 10) '#' else '0' + @as(u8, @intCast(value));
            }
            out.add("{s} |{s}|", .{ alignment(if (row == 0) num(hi) else if (row == side - 1) num(lo) else "", 6), points });
        }
        out.add("{s}", .{axis(side, 0, 0)});
        const low = num(lo);
        const high = num(hi);
        out.add("        {s}{s}{s}", .{ low, repeat(' ', side - low.len - high.len), high });
    }
    for ("NVA") |label| {
        var used: std.ArrayList(usize) = .empty;
        for (beats) |beat| if (beat.label == label and beat.sample >= 60 and beat.sample <= input.ecg.len - 100) c.append(usize,
             &used, beat.sample);
        if (used.items.len == 0) {
            out.add("TEMPLATE {c} beats=0", .{label});
            continue;
        }
        var average = std.mem.zeroes([160]i64);
        for (used.items) |sample| {
            var baseline: i64 = 0;
            for (input.ecg[sample - 60 .. sample - 50]) |value| baseline += value;
            for (&average, 0..) |*value, j| value.* += 10 * input.ecg[sample + j - 60] - baseline;
        }
        for (&average) |*value| value.* = report.rdiv(value.*, 10 * c.n(used.items.len));
        var maximum: usize = 0;
        var minimum: usize = 0;
        for (average, 0..) |value, j| {
            if (value > average[maximum]) maximum = j;
            if (value < average[minimum]) minimum = j;
        }
        out.add("TEMPLATE {c} beats={d} max_uv={d} max_ms={d} min_uv={d} min_ms={d} rows={d}", .{ label,
             used.items.len, average[maximum], 5 * (c.n(maximum) - 60), average[minimum], 5 * (c.n(minimum) - 60),
             rows });
        var upper: [80]i64 = undefined;
        var lower: [80]i64 = undefined;
        for (&upper, &lower, 0..) |*high, *low, i| {
            high.* = @max(average[2 * i], average[2 * i + 1]);
            low.* = @min(average[2 * i], average[2 * i + 1]);
        }
        waveform(&out, &upper, &lower, rows);
        out.add("{s}", .{axis(80, 10, 0)});
        var labels: [8]Label = undefined;
        for (&labels, 0..) |*item, i| item.* = .{ .column = 10 * i, .text = num(100 * c.n(i) - 300) };
        out.add("{s}", .{labelRow("ms", &labels)});
    }
    return out;
}
fn rhythm(input: c.Input, detection: Detection) c.Lines {
    const p = input.params;
    const first = c.u(@divFloor(p.strip_start_ms, 5));
    const length = c.u(@divFloor(p.strip_ms, 5));
    const columns = length / 10;
    const upper = c.alloc(i64, columns);
    const lower = c.alloc(i64, columns);
    for (upper, lower, 0..) |*high, *low, i| {
        const samples = input.ecg[first + 10 * i .. first + 10 * i + 10];
        high.* = std.mem.max(i64, samples);
        low.* = std.mem.min(i64, samples);
    }
    var out: c.Lines = .{};
    out.add("RHYTHM start_ms={d} end_ms={d} columns={d} rows={d} max_uv={d} min_uv={d}", .{ p.strip_start_ms,
         p.strip_start_ms + p.strip_ms, columns, p.strip_rows, std.mem.max(i64, upper), std.mem.min(i64,
         lower) });
    waveform(&out, upper, lower, c.u(p.strip_rows));
    out.add("{s}", .{axis(columns, 20, 0)});
    var labels: std.ArrayList(Label) = .empty;
    var i: usize = 0;
    while (i < columns) : (i += 20) c.append(Label, &labels, .{ .column = i, .text = num(@divFloor(p.strip_start_ms + 50 * c.n(i),
         1000)) });
    out.add("{s}", .{labelRow("s", labels.items)});
    const beat_marks = repeat(' ', columns);
    const ref_marks = repeat(' ', columns);
    for (detection.beats.items) |beat| if (beat.sample >= first and beat.sample < first + length) {
        beat_marks[(beat.sample - first) / 10] = beat.label;
    };
    for (input.annotations) |annotation| if (annotation.sample >= first and annotation.sample < first + length) {
        ref_marks[(annotation.sample - first) / 10] = annotation.label;
    };
    out.add(" beats |{s}|", .{beat_marks});
    out.add("  refs |{s}|", .{ref_marks});
    return out;
}
const OrderedLine = struct { sample: usize, priority: usize, line: []const u8 };
fn orderedLess(_: void, a: OrderedLine, b: OrderedLine) bool {
    return if (a.sample != b.sample) a.sample < b.sample else a.priority < b.priority;
}
fn performance(input: c.Input, detection: Detection) c.Lines {
    const beats = detection.beats.items;
    const annotations = input.annotations;
    var classes = std.mem.zeroes([5]usize);
    var refs = std.mem.zeroes([3]usize);
    var labels = std.mem.zeroes([3]usize);
    var miss = std.mem.zeroes([3]usize);
    var extra = std.mem.zeroes([3]usize);
    var confusion = std.mem.zeroes([3][3]usize);
    var method_total = std.mem.zeroes([2]usize);
    var method_tp = std.mem.zeroes([2]usize);
    var tp: usize = 0;
    var max_abs: i64 = 0;
    var offset_sum: i64 = 0;
    var absolute_sum: i64 = 0;
    for (detection.peaks) |peak| classes[@intFromEnum(peak.kind)] += 1;
    for (annotations) |annotation| {
        refs[labelIndex(annotation.label)] += 1;
        if (annotation.beat == null) miss[labelIndex(annotation.label)] += 1;
    }
    for (beats) |beat| {
        labels[labelIndex(beat.label)] += 1;
        const method: usize = @intFromBool(detection.peaks[beat.peak].kind == .searchback);
        method_total[method] += 1;
        if (beat.reference) |reference_index| {
            tp += 1;
            method_tp[method] += 1;
            const reference = annotations[reference_index];
            confusion[labelIndex(reference.label)][labelIndex(beat.label)] += 1;
            const offset = 5 * (c.n(beat.sample) - c.n(reference.sample));
            offset_sum += offset;
            absolute_sum += detector.abs(offset);
            max_abs = @max(max_abs, detector.abs(offset));
        } else extra[labelIndex(beat.label)] += 1;
    }
    const fp = beats.len - tp;
    const fn_count = annotations.len - tp;
    const threshold = thresholds(detection.levels);
    var out: c.Lines = .{};
    out.add("DETECTOR", .{});
    out.add("samples {d}", .{input.ecg.len});
    out.add("duration_ms {d}", .{5 * input.ecg.len});
    out.add("peaks {d} qrs={d} searchback={d} twave={d} refractory={d} noise={d}", .{ detection.peaks.len,
         classes[0], classes[1], classes[2], classes[3], classes[4] });
    for ([_][]const u8{ "initial_levels", "final_levels" }, [_]detector.Levels{ detection.initial,
         detection.levels }) |name, levels| out.add("{s} spki={d} npki={d} spkf={d} npkf={d}", .{ name,
         levels.spki, levels.npki, levels.spkf, levels.npkf });
    out.add("final_thresholds thr_i={d} thr_f={d}", .{ threshold[0], threshold[1] });
    out.add("final_rr_averages rravg1_ms={d} rravg2_ms={d}", .{ 5 * detection.ra1, 5 * detection.ra2 });
    out.add("MATCHING", .{});
    out.add("tolerance_ms {d}", .{input.params.match_ms});
    out.add("references {d} N={d} V={d} A={d}", .{ annotations.len, refs[0], refs[1], refs[2] });
    out.add("detections {d} N={d} V={d} A={d}", .{ beats.len, labels[0], labels[1], labels[2] });
    out.add("true_positives {d}", .{tp});
    out.add("false_positives {d}", .{fp});
    out.add("false_negatives {d}", .{fn_count});
    out.add("sensitivity {s}", .{report.ratio(c.n(tp), c.n(tp + fn_count))});
    out.add("positive_predictivity {s}", .{report.ratio(c.n(tp), c.n(tp + fp))});
    out.add("detection_error_rate {s}", .{report.ratio(c.n(fp + fn_count), c.n(annotations.len))});
    out.add("by_method threshold={d}/{d} searchback={d}/{d}", .{ method_tp[0], method_total[0], method_tp[1], method_total[1] });
    if (tp > 0) out.add("offset_ms mean={s} mean_abs={s} max_abs={d}", .{ report.decimal2(report.rdiv(100 * offset_sum,
         c.n(tp))), report.decimal2(report.rdiv(100 * absolute_sum, c.n(tp))), max_abs }) else out.add("offset_ms none",
         .{});
    out.add("CONFUSION", .{});
    out.add("ref  {s}{s}{s}  miss", .{ alignment("N", 6), alignment("V", 6), alignment("A", 6) });
    for ("NVA", 0..) |label, i| out.add("{c}    {s}{s}{s}{s}", .{ label, alignment(num(confusion[i][0]),
         6), alignment(num(confusion[i][1]), 6), alignment(num(confusion[i][2]), 6), alignment(num(miss[i]),
         6) });
    out.add("extra{s}{s}{s}", .{ alignment(num(extra[0]), 6), alignment(num(extra[1]), 6), alignment(num(extra[2]), 6) });
    out.add("veb_sensitivity {s}", .{report.ratio(c.n(confusion[1][1]), c.n(refs[1]))});
    out.add("veb_positive_predictivity {s}", .{report.ratio(c.n(confusion[1][1]), c.n(labels[1]))});
    out.add("sveb_sensitivity {s}", .{report.ratio(c.n(confusion[2][2]), c.n(refs[2]))});
    out.add("sveb_positive_predictivity {s}", .{report.ratio(c.n(confusion[2][2]), c.n(labels[2]))});
    const segment = @min(c.u(@divFloor(input.params.segment_ms, 5)), input.ecg.len);
    const segments = (input.ecg.len + segment - 1) / segment;
    out.add("SEGMENTS segment_ms={d} segments={d}", .{ input.params.segment_ms, segments });
    for (0..segments) |g| {
        const start = g * segment;
        const end = @min((g + 1) * segment, input.ecg.len);
        var reference_count: usize = 0;
        var matched: usize = 0;
        var false_positive: usize = 0;
        var noise: usize = 0;
        for (annotations) |annotation| if (annotation.sample >= start and annotation.sample < end) {
            reference_count += 1;
            matched += @intFromBool(annotation.beat != null);
        };
        for (beats) |beat| if (beat.sample >= start and beat.sample < end and beat.reference == null) {
            false_positive += 1;
        };
        for (detection.peaks) |peak| if (peak.time >= start and peak.time < end and peak.kind == .noise) {
            noise += 1;
        };
        out.add("{s}-{s} refs={d} tp={d} fp={d} fn={d} noise_peaks={d}", .{ alignment(num(5 * start),
             6), alignment(num(5 * end), 6), reference_count, matched, false_positive, reference_count - matched,
             noise });
    }
    out.add("ERRORS count={d}", .{fp + fn_count});
    var errors: std.ArrayList(OrderedLine) = .empty;
    for (beats, 1..) |beat, i| if (beat.reference == null) c.append(OrderedLine, &errors, .{ .sample = beat.sample,
         .priority = 0, .line = c.fmt("false_positive beat={d} sample={d} time_ms={d} label={c}",
         .{ i, beat.sample, 5 * beat.sample, beat.label }) });
    for (annotations) |annotation| if (annotation.beat == null) c.append(OrderedLine, &errors, .{ .sample = annotation.sample,
         .priority = 1, .line = c.fmt("false_negative sample={d} time_ms={d} label={c}", .{ annotation.sample,
         5 * annotation.sample, annotation.label }) });
    std.mem.sort(OrderedLine, errors.items, {}, orderedLess);
    for (errors.items) |err| out.add("{s}", .{err.line});
    return out;
}
fn hrvReport(input: c.Input, detection: Detection) c.Lines {
    const beats = detection.beats.items;
    const count = beats.len;
    var rr: std.ArrayList(i64) = .empty;
    var nn: std.ArrayList(i64) = .empty;
    var differences: std.ArrayList(i64) = .empty;
    var sums: std.ArrayList(i64) = .empty;
    const is_nn = c.alloc(bool, count);
    @memset(is_nn, false);
    for (1..count) |i| {
        c.append(i64, &rr, beats[i].rr);
        if (i >= 2 and beats[i - 1].label == 'N' and beats[i].label == 'N' and 5 * detector.abs(beats[i].rr - beats[i - 1].rr) <= beats[i - 1].rr) {
            is_nn[i] = true;
            c.append(i64, &nn, beats[i].rr);
            if (is_nn[i - 1]) {
                c.append(i64, &differences, beats[i].rr - beats[i - 1].rr);
                c.append(i64, &sums, beats[i].rr + beats[i - 1].rr);
            }
        }
    }
    var out: c.Lines = .{};
    out.add("RR", .{});
    out.add("beats {d}", .{count});
    out.add("intervals {d}", .{rr.items.len});
    if (rr.items.len == 0) {
        out.add("mean_rr_ms none", .{});
        out.add("min_rr_ms none", .{});
        out.add("max_rr_ms none", .{});
        out.add("mean_hr_bpm none", .{});
    } else {
        var minimum: usize = 0;
        var maximum: usize = 0;
        for (rr.items, 0..) |value, i| {
            if (value < rr.items[minimum]) minimum = i;
            if (value > rr.items[maximum]) maximum = i;
        }
        out.add("mean_rr_ms {s}", .{report.decimal2(hrv.meanScaled(rr.items))});
        out.add("min_rr_ms {d} beat={d}", .{ rr.items[minimum], minimum + 2 });
        out.add("max_rr_ms {d} beat={d}", .{ rr.items[maximum], maximum + 2 });
        out.add("mean_hr_bpm {s}", .{report.decimal2(hrv.meanHr(rr.items))});
    }
    var nn50: i64 = 0;
    for (differences.items) |difference| if (detector.abs(difference) > 50) {
        nn50 += 1;
    };
    out.add("NN", .{});
    out.add("intervals {d}", .{nn.items.len});
    out.add("mean_nn_ms {s}", .{if (nn.items.len == 0) "none" else report.decimal2(hrv.meanScaled(nn.items))});
    out.add("sdnn_ms {s}", .{if (nn.items.len < 2) "none" else report.decimal2(hrv.sampleDeviation(nn.items, 1))});
    out.add("differences {d}", .{differences.items.len});
    out.add("rmssd_ms {s}", .{if (differences.items.len == 0) "none" else report.decimal2(hrv.rms(differences.items))});
    out.add("sdsd_ms {s}", .{if (differences.items.len < 2) "none" else report.decimal2(hrv.sampleDeviation(differences.items,
         1))});
    out.add("nn50 {d}", .{nn50});
    if (differences.items.len == 0) out.add("pnn50 none", .{}) else out.add("pnn50 {s}%", .{report.decimal2(report.rdiv(10000 * nn50,
         c.n(differences.items.len)))});
    out.add("sd1_ms {s}", .{if (differences.items.len < 2) "none" else report.decimal2(hrv.sampleDeviation(differences.items,
         2))});
    out.add("sd2_ms {s}", .{if (sums.items.len < 2) "none" else report.decimal2(hrv.sampleDeviation(sums.items, 2))});
    const bins = hrv.histogram(nn.items);
    var maximum_bin: usize = 0;
    for (bins) |bin| maximum_bin = @max(maximum_bin, bin.count);
    out.add("HISTOGRAM bin_ms=7.8125 bins={d} max={d}", .{ bins.len, maximum_bin });
    for (bins) |bin| out.add("{s} {s} {s} |{s}", .{ alignment(report.decimal4(78125 * bin.bin), 10),
         alignment(report.decimal4(78125 * (bin.bin + 1)), 10), alignment(num(bin.count), 3), repeat('#',
         bin.count) });
    if (nn.items.len == 0) out.add("triangular_index none", .{}) else out.add("triangular_index {s} {s}",
         .{ report.reduced(c.n(nn.items.len), c.n(maximum_bin)), report.decimal2(report.rdiv(100 * c.n(nn.items.len),
         c.n(maximum_bin))) });
    var ventricular: usize = 0;
    var atrial: usize = 0;
    for (beats) |beat| {
        ventricular += @intFromBool(beat.label == 'V');
        atrial += @intFromBool(beat.label == 'A');
    }
    out.add("PREMATURE count={d} V={d} A={d}", .{ ventricular + atrial, ventricular, atrial });
    for (beats, 0..) |beat, i| if (beat.label != 'N') {
        var preceding: i64 = 0;
        for (beats[i - 8 .. i]) |other| preceding += other.rr;
        var compensation: []const u8 = "-";
        if (i + 1 < count) {
            const total = beat.rr + beats[i + 1].rr;
            compensation = if (10 * detector.abs(4 * total - preceding) <= preceding) "full" else if (4 * total < preceding) "partial" else "long";
        }
        out.add("beat={d} sample={d} label={c} rr_ms={d} next_rr_ms={s} mean_ms={s} prematurity={s}% compensation={s} width_ms={d} ref={c}",
             .{ i + 1, beat.sample, beat.label, beat.rr, report.optionalNumber(if (i + 1 < count) beats[i + 1].rr else null),
             report.decimal2(report.rdiv(100 * preceding, 8)), report.decimal2(report.rdiv(80000 * beat.rr,
             preceding)), compensation, beat.width, if (beat.reference) |index| input.annotations[index].label else @as(u8,
             '-') });
    };
    var runs: c.Lines = .{};
    var first: usize = 0;
    while (first < count) {
        if (beats[first].label == 'N') {
            first += 1;
            continue;
        }
        var last = first;
        while (last + 1 < count and beats[last + 1].label == beats[first].label) last += 1;
        const length = last - first + 1;
        runs.add("{c} {s} beats={d}-{d} length={d} start_ms={d}", .{ beats[first].label, if (length == 1) "isolated" else if (length == 2) "couplet" else "run",
             first + 1, last + 1, length, 5 * beats[first].sample });
        first = last + 1;
    }
    out.add("RUNS count={d}", .{runs.data.items.len});
    out.extend(runs);
    var events: c.Lines = .{};
    for (1..count) |i| if (beats[i].rr > input.params.pause_ms) events.add("pause beats={d}-{d} rr_ms={d} start_ms={d}",
         .{ i, i + 1, beats[i].rr, 5 * beats[i - 1].sample });
    for (0..2) |kind| {
        const flags = c.alloc(bool, count);
        @memset(flags, false);
        for (1..count) |i| flags[i] = if (kind == 0) beats[i].rr > input.params.brady_ms else beats[i].rr < input.params.tachy_ms;
        for (hrv.ranges(flags)) |range| if (range.last - range.first + 1 >= 3) {
            var intervals: std.ArrayList(i64) = .empty;
            for (beats[range.first .. range.last + 1]) |beat| c.append(i64, &intervals, beat.rr);
            events.add("{s} beats={d}-{d} intervals={d} mean_hr={s} start_ms={d}", .{ if (kind == 0) "bradycardia" else "tachycardia",
                 range.first, range.last + 1, intervals.items.len, report.decimal2(hrv.meanHr(intervals.items)),
                 5 * beats[range.first - 1].sample });
        };
    }
    var vbeats: std.ArrayList(usize) = .empty;
    for (beats, 0..) |beat, i| if (beat.label == 'V') c.append(usize, &vbeats, i);
    for ([_]usize{ 2, 3 }) |step| {
        first = 0;
        while (first < vbeats.items.len) {
            var last = first;
            while (last + 1 < vbeats.items.len) {
                const a = vbeats.items[last];
                const b = vbeats.items[last + 1];
                var linked = b - a == step;
                for (beats[a + 1 .. b]) |beat| if (beat.label != 'N') {
                    linked = false;
                };
                if (!linked) break;
                last += 1;
            }
            if (last - first + 1 >= 3) events.add("{s} beats={d}-{d} cycles={d} start_ms={d}", .{ if (step == 2) "bigeminy" else "trigeminy",
                 vbeats.items[first] + 1, vbeats.items[last] + 1, last - first + 1, 5 * beats[vbeats.items[first]].sample });
            first = last + 1;
        }
    }
    out.add("EVENTS count={d}", .{events.data.items.len});
    out.extend(events);
    const segment = @min(c.u(@divFloor(input.params.segment_ms, 5)), input.ecg.len);
    const segments = (input.ecg.len + segment - 1) / segment;
    out.add("TREND segment_ms={d} segments={d}", .{ input.params.segment_ms, segments });
    for (0..segments) |g| {
        const start = g * segment;
        const end = @min((g + 1) * segment, input.ecg.len);
        var intervals: std.ArrayList(i64) = .empty;
        var beat_count: usize = 0;
        for (beats, 0..) |beat, i| if (beat.sample >= start and beat.sample < end) {
            beat_count += 1;
            if (i > 0) c.append(i64, &intervals, beat.rr);
        };
        if (intervals.items.len == 0) out.add("{s}-{s} beats={d} mean_hr=none min_hr=none max_hr=none |",
             .{ alignment(num(5 * start), 6), alignment(num(5 * end), 6), beat_count }) else {
            const heart_rate = hrv.meanHr(intervals.items);
            out.add("{s}-{s} beats={d} mean_hr={s} min_hr={s} max_hr={s} |{s}", .{ alignment(num(5 * start),
                 6), alignment(num(5 * end), 6), beat_count, report.decimal2(heart_rate), report.decimal2(report.rdiv(6000000,
                 std.mem.max(i64, intervals.items))), report.decimal2(report.rdiv(6000000, std.mem.min(i64,
                 intervals.items))), repeat('#', c.u(report.rdiv(heart_rate, 500))) });
        }
    }
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.readInput(init.io);
    const signals = filters.filter(input.ecg);
    const detection = detect(signals, input.params);
    match(detection.beats.items, input.annotations, @divFloor(input.params.match_ms, 5));
    var beats: c.Lines = .{};
    beats.add("beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label", .{});
    for (detection.beats.items, 0..) |beat, i| beats.add("{d},{d},{d},{s},{s},{d},{c},{s},{s},{c}",
         .{ i + 1, beat.sample, 5 * beat.sample, if (i == 0) "-" else num(beat.rr), if (i == 0) "-" else report.decimal2(report.rdiv(6000000,
         beat.rr)), beat.width, beat.label, if (detection.peaks[beat.peak].kind == .qrs) "threshold" else "searchback",
         if (beat.reference) |index| num(input.annotations[index].sample) else "-", if (beat.reference) |index| input.annotations[index].label else @as(u8,
         '-') });
    try c.write(init.io, "beats.csv", beats);
    var peaks: c.Lines = .{};
    peaks.add("peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class", .{});
    for (detection.peaks, 1..) |peak, i| peaks.add("{d},{d},{d},{d},{d},{d},{d},{d},{s}", .{ i, peak.time,
         peak.r, peak.integrated, peak.filtered, peak.slope, peak.thr_i, peak.thr_f, @tagName(peak.kind) });
    try c.write(init.io, "peaks.csv", peaks);
    var matches: std.ArrayList(OrderedLine) = .empty;
    for (input.annotations) |reference| {
        const line = if (reference.beat) |index| blk: {
            const beat = detection.beats.items[index];
            break :blk c.fmt("{d},{c},{d},{d},{c},{d},TP,{s}", .{ reference.sample, reference.label,
                 index + 1, beat.sample, beat.label, 5 * (c.n(beat.sample) - c.n(reference.sample)),
                 if (beat.label == reference.label) "yes" else "no" });
        } else c.fmt("{d},{c},-,-,-,-,FN,-", .{ reference.sample, reference.label });
        c.append(OrderedLine, &matches, .{ .sample = reference.sample, .priority = 0, .line = line });
    }
    for (detection.beats.items, 1..) |beat, i| if (beat.reference == null) c.append(OrderedLine, &matches,
         .{ .sample = beat.sample, .priority = 1, .line = c.fmt("-,-,{d},{d},{c},-,FP,-", .{ i, beat.sample,
         beat.label }) });
    std.mem.sort(OrderedLine, matches.items, {}, orderedLess);
    var matching: c.Lines = .{};
    matching.add("ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree", .{});
    for (matches.items) |row| matching.add("{s}", .{row.line});
    try c.write(init.io, "matching.csv", matching);
    var excerpt: c.Lines = .{};
    excerpt.add("sample,ecg,lowpass,bandpass,derivative,squared,integrated", .{});
    for (0..c.u(@divFloor(input.params.excerpt_ms, 5))) |i| excerpt.add("{d},{d},{d},{d},{d},{d},{d}",
         .{ i, input.ecg[i], signals.lowpass[i], signals.bandpass[i], signals.derivative[i], signals.squared[i],
         signals.integrated[i] });
    try c.write(init.io, "signals_excerpt.csv", excerpt);
    try c.write(init.io, "performance.txt", performance(input, detection));
    try c.write(init.io, "hrv.txt", hrvReport(input, detection));
    try c.write(init.io, "charts.txt", charts(input, detection));
    try c.write(init.io, "rhythm_strip.txt", rhythm(input, detection));
}
