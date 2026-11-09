const std = @import("std");
const S = @import("signals.zig");
const E = @import("effects.zig");
const F = @import("filters.zig");
const D = @import("dynamics.zig");
const A = @import("analysis.zig");
const Command = enum { SET, IMPULSE, STEP, NOISE, GAIN, MIX, DELAY, ECHO, RESAMPLE, FADE, TRIM, CONCAT, FIR, BIQUAD, MOVAVG, DCBLOCK, NORMALIZE, GATE, ENVELOPE, COMPRESS, ANALYZE, COMPARE, EXPECT, SEGMENTS, ONSETS, PITCHTRACK, EXCERPT, PLOT, METER, HISTOGRAM, TRACE, SAVE };
const Kind = enum { name, signal, metric, operator, integer };
const Bound = union(enum) { fixed: i64, count_minus_one, columns, min_hz_plus_one, num_plus_one, length, last, remaining, rate_half, rate_half_minus_one, ratio_num, frame };
const Argument = struct { name: []const u8, kind: Kind, low: Bound = .{ .fixed = 0 }, high: Bound = .{ .fixed = 0 } };
fn named(name: []const u8) Argument { return .{ .name = name, .kind = if (S.eq(name, "src")) .signal else if (S.eq(name, "metric")) .metric else if (S.eq(name, "op")) .operator else .name }; }
fn integer(name: []const u8, low: i64, high: i64) Argument { return .{ .name = name, .kind = .integer, .low = .{ .fixed = low }, .high = .{ .fixed = high } }; }
fn bounded(name: []const u8, low: Bound, high: Bound) Argument { return .{ .name = name, .kind = .integer, .low = low, .high = high }; }
const Spec = struct { tag: Command, arguments: []const Argument, repeated: []const Argument = &.{}, minimum: usize = 0, maximum: usize = 0 };
fn commandSpec(tag: Command, args: []const Argument) Spec { return .{ .tag = tag, .arguments = args }; }
fn repeatedSpec(tag: Command, args: []const Argument, repeat_args: []const Argument, minimum: usize, maximum: usize) Spec { return .{ .tag = tag, .arguments = args, .repeated = repeat_args, .minimum = minimum, .maximum = maximum }; }
const dst = named("dst");
const src = named("src");
const rate_arg = integer("rate", 1000, 48000);
const count_arg = integer("count", 1, 20000);
const num = integer("num", -65536, 65536);
const den = integer("den", 1, 65536);
const attack = integer("attack", 1, 32768);
const release = integer("release", 1, 32768);
const min_hz = bounded("min_hz", .{ .fixed = 1 }, .rate_half_minus_one);
const max_hz = bounded("max_hz", .min_hz_plus_one, .rate_half);
const start_arg = bounded("start", .{ .fixed = 0 }, .last);
const test_args: []const Argument = &.{ dst, rate_arg, count_arg, bounded("pos", .{ .fixed = 0 }, .count_minus_one), integer("amp", -32768, 32767) };
const commands = [_]Spec{
    repeatedSpec(.SET, &.{ named("var"), integer("value", -10000000, 10000000) }, &.{ named("op"), integer("operand", -10000000, 10000000) }, 0, 1),
    commandSpec(.IMPULSE, test_args), commandSpec(.STEP, test_args), commandSpec(.NOISE, &.{ dst, rate_arg, count_arg, integer("seed", 1, 2147483646) }),
    commandSpec(.GAIN, &.{ dst, src, num, den }), repeatedSpec(.MIX, &.{ dst, den }, &.{ src, integer("weight", -65536, 65536) }, 1, 8),
    commandSpec(.DELAY, &.{ dst, src, integer("samples", 0, 20000) }), commandSpec(.ECHO, &.{ dst, src, integer("delay", 1, 20000), num, den, integer("tail", 0, 20000) }),
    commandSpec(.RESAMPLE, &.{ dst, src, integer("new_rate", 1000, 48000) }), commandSpec(.FADE, &.{ dst, src, bounded("in", .{ .fixed = 0 }, .length), bounded("out", .{ .fixed = 0 }, .length) }),
    commandSpec(.TRIM, &.{ dst, src, start_arg, bounded("count", .{ .fixed = 1 }, .remaining) }), repeatedSpec(.CONCAT, &.{dst}, &.{src}, 2, 8),
    repeatedSpec(.FIR, &.{ dst, src, integer("divisor", 1, 1000000) }, &.{integer("tap", -32768, 32767)}, 1, 64),
    repeatedSpec(.BIQUAD, &.{ dst, src }, &.{ integer("b0", -65536, 65536), integer("b1", -65536, 65536), integer("b2", -65536, 65536), integer("a1", -65536, 65536), integer("a2", -65536, 65536) }, 1, 4),
    commandSpec(.MOVAVG, &.{ dst, src, integer("width", 1, 1000) }), commandSpec(.DCBLOCK, &.{ dst, src, integer("num", 0, 65535), bounded("den", .num_plus_one, .{ .fixed = 65536 }) }),
    commandSpec(.NORMALIZE, &.{ dst, src, integer("target", 1, 32767) }), commandSpec(.GATE, &.{ dst, src, integer("threshold", 1, 32768), integer("hold", 0, 20000) }),
    commandSpec(.ENVELOPE, &.{ dst, src, attack, release }), commandSpec(.COMPRESS, &.{ dst, src, integer("threshold", 1, 32767), integer("ratio_num", 1, 100), bounded("ratio_den", .{ .fixed = 1 }, .ratio_num), attack, release }),
    commandSpec(.ANALYZE, &.{ src, min_hz, max_hz }), commandSpec(.COMPARE, &.{ src, src }), commandSpec(.EXPECT, &.{ src, named("metric"), named("op"), integer("value", -1000000000, 1000000000) }),
    commandSpec(.SEGMENTS, &.{ src, integer("threshold", 1, 32768), integer("gap", 1, 20000), integer("min_length", 1, 20000) }),
    commandSpec(.ONSETS, &.{ src, attack, release, integer("threshold", 1, 32767), integer("min_gap", 1, 20000) }),
    commandSpec(.PITCHTRACK, &.{ src, bounded("frame", .{ .fixed = 16 }, .length), bounded("hop", .{ .fixed = 1 }, .frame), min_hz, max_hz, integer("threshold", 0, 32767) }),
    commandSpec(.EXCERPT, &.{ src, start_arg, integer("count", 1, 1000) }), commandSpec(.PLOT, &.{ src, start_arg, bounded("count", .{ .fixed = 1 }, .remaining), bounded("columns", .{ .fixed = 8 }, .columns), integer("half", 2, 20), attack, release }),
    commandSpec(.METER, &.{ src, integer("block", 1, 20000) }), commandSpec(.HISTOGRAM, &.{ src, integer("bins", 2, 64) }), commandSpec(.TRACE, &.{src}), commandSpec(.SAVE, &.{src}),
};
const Value = struct { token: []const u8, number: i64 = 0, source: ?*const S.Signal = null };
const Parsed = struct { values: []const Value, sources: []const *const S.Signal };
const Error = error{CommandError};
var error_message: []const u8 = "";
fn fail(comptime pattern: []const u8, args: anytype) Error { error_message = S.fmt(pattern, args); return error.CommandError; }
fn has(values: []const []const u8, value: []const u8) bool { for (values) |candidate| { if (S.eq(candidate, value)) return true; } return false; }
fn validName(text: []const u8) bool { if (text.len == 0 or text.len > 16 or text[0] < 'a' or text[0] > 'z') return false; for (text[1..]) |ch| { if (!((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_')) return false; } return true; }
fn validInteger(text: []const u8) bool { if (text.len == 0 or S.eq(text, "-0")) return false; const digits = if (text[0] == '-') text[1..] else text; if (digits.len == 0 or digits.len > 10 or (digits.len > 1 and digits[0] == '0')) return false; for (digits) |ch| { if (ch < '0' or ch > '9') return false; } return true; }
fn resolve(value: Bound, known: std.StringHashMapUnmanaged(i64), source: ?*const S.Signal) i64 {
    return switch (value) { .fixed => |n| n, .count_minus_one => known.get("count").? - 1, .columns => @min(120, known.get("count").?), .min_hz_plus_one => known.get("min_hz").? + 1, .num_plus_one => known.get("num").? + 1, .length => S.int(source.?.samples.len), .last => S.int(source.?.samples.len) - 1, .remaining => S.int(source.?.samples.len) - known.get("start").?, .rate_half => @divFloor(source.?.rate, 2), .rate_half_minus_one => @divFloor(source.?.rate, 2) - 1, .ratio_num => known.get("ratio_num").?, .frame => known.get("frame").? };
}
fn sameRate(sources: []const *const S.Signal) Error!void { for (sources) |source| { if (source.rate != sources[0].rate) return fail("rate mismatch", .{}); } }
fn milliseconds(n: usize, rate: i64) i64 { return @divFloor(S.int(n) * 1000, rate); }
fn twoDecimals(h: i64) []const u8 { return S.fmt("{d}.{d:0>2}", .{ @divFloor(h, 100), @mod(h, 100) }); }
fn frequency(rate: i64, lag: usize) []const u8 { return twoDecimals(S.rdiv(100 * rate, S.int(lag))); }
const Lags = struct { low: usize, high: usize };
fn lagRange(rate: i64, low: i64, high: i64) Lags { return .{ .low = S.index(@divFloor(rate + high - 1, high)), .high = S.index(@divFloor(rate, low)) }; }
fn numeric(values: []const Value) []const i64 { const result = S.alloc(i64, values.len); for (values, result) |value, *number| number.* = value.number; return result; }
const Pipeline = struct {
    signals: std.StringHashMapUnmanaged(*const S.Signal) = .empty,
    variables: std.StringHashMapUnmanaged(i64) = .empty,
    log: S.Lines = .{}, analysis: S.Lines = .{}, excerpts: S.Lines = .{}, waveforms: S.Lines = .{}, saved: S.Lines = .{},
    steps: usize = 0, errors: usize = 0, passed: usize = 0, failed: usize = 0,
    fn init(loaded: []const *const S.Signal) Pipeline { var p: Pipeline = .{}; p.analysis.write("signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"); for (loaded) |signal| { p.signals.put(S.allocator, signal.name, signal) catch @panic("allocation failed"); p.log.add("load {s} rate={d} samples={d} peak={d}", .{ signal.name, signal.rate, signal.samples.len, S.peak(signal.samples) }); } return p; }
    fn integerValue(self: *Pipeline, text: []const u8) Error!i64 { if (text.len > 0 and text[0] == '$') { const result = self.variables.get(text[1..]) orelse return fail("undefined variable {s}", .{text}); return result; } if (!validInteger(text)) return fail("bad integer {s}", .{text}); return std.fmt.parseInt(i64, text, 10) catch unreachable; }
    fn parse(self: *Pipeline, command_spec: Spec, tokens: []const []const u8) Error!Parsed {
        if (tokens.len < command_spec.arguments.len) return fail("wrong number of arguments", .{}); const extra = tokens.len - command_spec.arguments.len;
        if (command_spec.repeated.len == 0) { if (extra != 0) return fail("wrong number of arguments", .{}); } else if (extra % command_spec.repeated.len != 0 or extra / command_spec.repeated.len < command_spec.minimum or extra / command_spec.repeated.len > command_spec.maximum) return fail("wrong number of arguments", .{});
        const values = S.alloc(Value, tokens.len); var sources: std.ArrayList(*const S.Signal) = .empty; var known: std.StringHashMapUnmanaged(i64) = .empty;
        for (tokens, values, 0..) |token, *value, i| { const arg = if (i < command_spec.arguments.len) command_spec.arguments[i] else command_spec.repeated[(i - command_spec.arguments.len) % command_spec.repeated.len]; value.* = .{ .token = token };
            switch (arg.kind) {
                .name => { if (!validName(token)) return fail("bad name {s}", .{token}); },
                .signal => { const signal = self.signals.get(token) orelse return fail("unknown signal {s}", .{token}); value.source = signal; S.append(*const S.Signal, &sources, signal); },
                .metric => { if (!has(&.{ "samples", "peak", "rms", "sum", "zero_crossings", "clipped" }, token)) return fail("unknown metric {s}", .{token}); },
                .operator => { const allowed: []const []const u8 = if (command_spec.tag == .SET) &.{ "+", "-", "*", "/" } else &.{ "eq", "ne", "lt", "le", "gt", "ge" }; if (!has(allowed, token)) return fail("unknown operator {s}", .{token}); },
                .integer => { const n = try self.integerValue(token); const source = if (sources.items.len == 0) null else sources.items[0]; if (n < resolve(arg.low, known, source) or n > resolve(arg.high, known, source)) return fail("{s} out of range", .{arg.name}); value.number = n; known.put(S.allocator, arg.name, n) catch @panic("allocation failed"); },
            }
        }
        return .{ .values = values, .sources = sources.items };
    }
    fn generate(self: *Pipeline, line_number: usize, tag: Command, parsed: Parsed) Error![]const u8 {
        const v = parsed.values; const args = v[1..]; const sources = parsed.sources; var rate: i64 = undefined; var samples: []const i64 = undefined; var extras: S.Text = .{};
        if (tag == .IMPULSE or tag == .STEP or tag == .NOISE) { rate = args[0].number; const count = S.index(args[1].number); samples = switch (tag) { .IMPULSE => S.impulse(count, S.index(args[2].number), args[3].number), .STEP => S.step(count, S.index(args[2].number), args[3].number), else => S.noise(count, args[2].number) }; } else {
            const source = sources[0]; const x = source.samples; rate = source.rate;
            switch (tag) {
                .GAIN => { const result = E.gain(x, args[1].number, args[2].number); samples = result.samples; extras.add(" clipped={d}", .{result.clipped}); },
                .MIX => { try sameRate(sources); const weights = S.alloc(i64, sources.len); for (weights, 0..) |*weight, i| weight.* = args[2 + 2 * i].number; const result = E.mix(sources, weights, args[0].number); samples = result.samples; extras.add(" clipped={d}", .{result.clipped}); },
                .DELAY => { const count = S.index(args[1].number); if (x.len + count > 20000) return fail("result too long", .{}); samples = E.delay(x, count); },
                .ECHO => { if (S.abs(args[2].number) >= args[3].number) return fail("unstable feedback", .{}); const tail = S.index(args[4].number); if (x.len + tail > 20000) return fail("result too long", .{}); const result = E.echo(x, S.index(args[1].number), args[2].number, args[3].number, tail); samples = result.samples; extras.add(" clipped={d}", .{result.clipped}); },
                .RESAMPLE => { rate = args[1].number; if (E.resampledLength(x.len, source.rate, rate) > 20000) return fail("result too long", .{}); samples = E.resample(x, source.rate, rate); },
                .FADE => samples = E.fade(x, S.index(args[1].number), S.index(args[2].number)),
                .TRIM => { const start = S.index(args[1].number); samples = S.clone(i64, x[start..start + S.index(args[2].number)]); },
                .CONCAT => { try sameRate(sources); var count: usize = 0; for (sources) |signal| count += signal.samples.len; if (count > 20000) return fail("result too long", .{}); const result = S.alloc(i64, count); var offset: usize = 0; for (sources) |signal| { @memcpy(result[offset..offset + signal.samples.len], signal.samples); offset += signal.samples.len; } samples = result; },
                .FIR => { const result = F.fir(x, args[1].number, numeric(args[2..])); samples = result.samples; extras.add(" clipped={d}", .{result.clipped}); },
                .BIQUAD => { const result = F.biquad(x, numeric(args[1..])); samples = result.samples; extras.add(" sections={d} clipped={d}", .{ (args.len - 1) / 5, result.clipped }); },
                .MOVAVG => samples = F.movingAverage(x, S.index(args[1].number)),
                .DCBLOCK => { const result = F.dcBlock(x, args[1].number, args[2].number); samples = result.samples; extras.add(" clipped={d}", .{result.clipped}); },
                .NORMALIZE => { const result = D.normalize(x, args[1].number); samples = result.samples; extras.add(" source_peak={d}", .{result.source_peak}); },
                .GATE => { const result = D.gate(x, args[1].number, args[2].number); samples = result.samples; extras.add(" muted={d}", .{result.muted}); },
                .ENVELOPE => samples = D.envelope(x, args[1].number, args[2].number),
                .COMPRESS => { const result = D.compress(x, args[1].number, args[2].number, args[3].number, args[4].number, args[5].number); samples = result.samples; extras.add(" min_gain={d} reduced={d}", .{ result.min_gain, result.reduced }); },
                else => unreachable,
            }
        }
        const signal = S.create(.{ .name = v[0].token, .rate = rate, .samples = samples, .origin = S.fmt("line {d} {s}", .{ line_number, @tagName(tag) }), .ingredients = sources }); self.signals.put(S.allocator, signal.name, signal) catch @panic("allocation failed");
        return S.fmt("{s} rate={d} samples={d} peak={d} sum={d}{s}", .{ signal.name, rate, samples.len, S.peak(samples), S.sum(samples), extras.value() });
    }
    fn execute(self: *Pipeline, line_number: usize, tag: Command, parsed: Parsed) Error!S.Lines {
        const v = parsed.values; const sources = parsed.sources; var result: S.Lines = .{};
        if (@intFromEnum(tag) >= @intFromEnum(Command.IMPULSE) and @intFromEnum(tag) <= @intFromEnum(Command.COMPRESS)) { result.write(try self.generate(line_number, tag, parsed)); return result; }
        if (tag == .SET) { var value = v[1].number; if (v.len == 4) { const op = v[2].token; const operand = v[3].number; if (S.eq(op, "/") and operand == 0) return fail("division by zero", .{}); value = if (S.eq(op, "+")) value + operand else if (S.eq(op, "-")) value - operand else if (S.eq(op, "*")) value * operand else @divFloor(value, operand); if (S.abs(value) > 10000000) return fail("value out of range", .{}); } self.variables.put(S.allocator, v[0].token, value) catch @panic("allocation failed"); result.add("{s}={d}", .{ v[0].token, value }); return result; }
        const source = sources[0]; const x = source.samples; const rate = source.rate;
        switch (tag) {
            .ANALYZE => { const lags = lagRange(rate, v[1].number, v[2].number); if (lags.low > lags.high) return fail("empty lag range", .{}); if (lags.high >= x.len) return fail("signal too short", .{}); const lag = A.pitchLag(x, lags.low, lags.high); const lag_text = if (lag) |n| S.fmt("{d}", .{n}) else "none"; const hz = if (lag) |n| frequency(rate, n) else "none"; self.analysis.add("{s},{d},{d},{d},{d},{s},{s},{s}", .{ source.name, S.peak(x), A.rms(x), A.zeroCrossings(x), A.countClipped(x), A.crestFraction(x), lag_text, hz }); result.add("{s} lags={d}-{d}", .{ source.name, lags.low, lags.high }); },
            .COMPARE => { try sameRate(sources); const other = sources[1]; var differing: i64 = 0; var max_diff: i64 = 0; var first: ?usize = null; var energy: i64 = 0; for (0..@max(x.len, other.samples.len)) |i| { const difference = (if (i < x.len) x[i] else 0) - (if (i < other.samples.len) other.samples[i] else 0); if (difference != 0) { differing += 1; if (first == null) first = i; } max_diff = @max(max_diff, S.abs(difference)); energy += difference * difference; } result.add("{s} {s} differing={d} max_diff={d} first={s} error_energy={d}", .{ source.name, other.name, differing, max_diff, if (first) |i| S.fmt("{d}", .{i}) else "none", energy }); },
            .EXPECT => { const metric = v[1].token; const op = v[2].token; const value = v[3].number; const measured = metricValue(metric, x); const passed = if (S.eq(op, "eq")) measured == value else if (S.eq(op, "ne")) measured != value else if (S.eq(op, "lt")) measured < value else if (S.eq(op, "le")) measured <= value else if (S.eq(op, "gt")) measured > value else measured >= value; if (passed) self.passed += 1 else self.failed += 1; result.add("{s} {s}={d} {s} {d} {s}", .{ source.name, metric, measured, op, value, if (passed) "pass" else "fail" }); },
            .SEGMENTS => { const Segment = struct { start: usize, end: usize }; var found: std.ArrayList(Segment) = .empty; for (x, 0..) |value, i| { if (S.abs(value) < v[1].number) continue; if (found.items.len > 0 and S.int(i - found.items[found.items.len - 1].end) <= v[2].number) found.items[found.items.len - 1].end = i else S.append(Segment, &found, .{ .start = i, .end = i }); } var detail: S.Lines = .{}; var count: usize = 0; for (found.items) |segment| { if (S.int(segment.end - segment.start + 1) < v[3].number) continue; count += 1; const part = x[segment.start..segment.end + 1]; detail.add("  segment {d} start={d} end={d} start_ms={d} end_ms={d} peak={d} rms={d} crossings={d}", .{ count, segment.start, segment.end, milliseconds(segment.start, rate), milliseconds(segment.end, rate), S.peak(part), A.rms(part), A.zeroCrossings(part) }); } result.add("{s} segments={d}", .{ source.name, count }); result.extend(detail); },
            .ONSETS => { const levels = D.envelope(x, v[1].number, v[2].number); var onsets: std.ArrayList(usize) = .empty; for (levels, 0..) |level, n| { const rising = level >= v[3].number and (n == 0 or levels[n - 1] < v[3].number); if (rising and (onsets.items.len == 0 or S.int(n - onsets.items[onsets.items.len - 1]) >= v[4].number)) S.append(usize, &onsets, n); } var tempo: []const u8 = "none"; if (onsets.items.len >= 2) { const intervals = S.alloc(usize, onsets.items.len - 1); for (intervals, 0..) |*interval, i| interval.* = onsets.items[i + 1] - onsets.items[i]; std.mem.sort(usize, intervals, {}, lessIndex); tempo = twoDecimals(S.rdiv(6000 * rate, S.int(intervals[(onsets.items.len - 2) / 2]))); } result.add("{s} onsets={d} tempo={s}", .{ source.name, onsets.items.len, tempo }); for (onsets.items, 0..) |n, i| result.add("  onset {d} sample={d} ms={d} interval={s}", .{ i + 1, n, milliseconds(n, rate), if (i == 0) "none" else S.fmt("{d}", .{n - onsets.items[i - 1]}) }); },
            .PITCHTRACK => { const frame = S.index(v[1].number); const hop = S.index(v[2].number); const lags = lagRange(rate, v[3].number, v[4].number); if (lags.low > lags.high) return fail("empty lag range", .{}); if (lags.high >= frame) return fail("frame too short", .{}); const count = (x.len - frame) / hop + 1; var detail: S.Lines = .{}; var voiced: usize = 0; for (0..count) |t| { const part = x[t * hop..t * hop + frame]; const level = A.rms(part); const lag = if (level < v[5].number) null else A.pitchLag(part, lags.low, lags.high); if (lag != null) voiced += 1; detail.write(pitchRow(rate, t * hop, level, lag, lags)); } self.waveforms.add("PITCHTRACK {s} rate={d} frame={d} hop={d} lags={d}-{d} threshold={d} frames={d} voiced={d}", .{ source.name, rate, frame, hop, lags.low, lags.high, v[5].number, count, voiced }); self.waveforms.extend(detail); result.add("{s} frames={d} voiced={d}", .{ source.name, count, voiced }); },
            .EXCERPT => { const start = S.index(v[1].number); const count = @min(S.index(v[2].number), x.len - start); self.excerpts.add("EXCERPT {s} rate={d} samples={d} start={d} count={d}", .{ source.name, rate, x.len, start, count }); var offset: usize = 0; while (offset < count) : (offset += 8) { var text: S.Text = .{}; text.add("{d: >5}:", .{start + offset}); for (x[start + offset..start + @min(offset + 8, count)]) |value| text.add(" {d: >6}", .{value}); self.excerpts.write(text.value()); } result.add("{s} start={d} count={d}", .{ source.name, start, count }); },
            .PLOT => { const start = S.index(v[1].number); const count = S.index(v[2].number); const columns = S.index(v[3].number); const half = S.index(v[4].number); self.waveforms.extend(waveformPlot(source, start, count, columns, half, v[5].number, v[6].number)); result.add("{s} start={d} count={d} columns={d} rows={d}", .{ source.name, start, count, columns, 2 * half + 1 }); },
            .METER => { self.waveforms.extend(meterPlot(source, S.index(v[1].number))); result.add("{s} block={d}", .{ source.name, v[1].number }); },
            .HISTOGRAM => { self.waveforms.extend(histogramPlot(source, S.index(v[1].number))); result.add("{s} bins={d}", .{ source.name, v[1].number }); },
            .TRACE => { result.write(source.name); traceLines(&result, source, 1); },
            .SAVE => { self.saved.extend(S.format(source)); result.add("{s} samples={d}", .{ source.name, x.len }); },
            else => unreachable,
        }
        return result;
    }
    fn run(self: *Pipeline, number: usize, line: []const u8) void {
        const tokens = S.split(line, ' '); var command_spec: ?Spec = null; for (commands) |candidate| { if (S.eq(@tagName(candidate.tag), tokens[0])) { command_spec = candidate; break; } }
        if (command_spec == null) { self.log.add("line {d}: error: unknown command {s}", .{ number, tokens[0] }); self.errors += 1; return; }
        const parsed = self.parse(command_spec.?, tokens[1..]) catch { self.log.add("line {d}: error: {s}", .{ number, error_message }); self.errors += 1; return; };
        const result = self.execute(number, command_spec.?.tag, parsed) catch { self.log.add("line {d}: error: {s}", .{ number, error_message }); self.errors += 1; return; };
        self.log.add("line {d}: {s} {s}", .{ number, tokens[0], result.data.items[0] }); for (result.data.items[1..]) |detail| self.log.write(detail); self.steps += 1;
    }
    fn finish(self: *Pipeline) void {
        var names: std.ArrayList([]const u8) = .empty; var it = self.signals.keyIterator(); while (it.next()) |name| S.append([]const u8, &names, name.*); std.mem.sort([]const u8, names.items, {}, lessText);
        for (names.items) |name| { const signal = self.signals.get(name).?; self.log.add("signal {s} rate={d} samples={d} peak={d} rms={d}", .{ name, signal.rate, signal.samples.len, S.peak(signal.samples), A.rms(signal.samples) }); }
        self.log.add("summary steps={d} errors={d} signals={d} passed={d} failed={d}", .{ self.steps, self.errors, self.signals.count(), self.passed, self.failed });
    }
};
fn lessIndex(_: void, a: usize, b: usize) bool { return a < b; }
fn lessText(_: void, a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
fn metricValue(name: []const u8, samples: []const i64) i64 { if (S.eq(name, "samples")) return S.int(samples.len); if (S.eq(name, "peak")) return S.peak(samples); if (S.eq(name, "rms")) return A.rms(samples); if (S.eq(name, "sum")) return S.sum(samples); if (S.eq(name, "zero_crossings")) return A.zeroCrossings(samples); return A.countClipped(samples); }
fn plotRow(value: i64, scale: i64, rows: usize) usize { return S.index(S.rdiv((scale - value) * S.int(rows - 1), 2 * scale)); }
fn waveformPlot(signal: *const S.Signal, start: usize, count: usize, columns: usize, half: usize, attack_value: i64, release_value: i64) S.Lines {
    const window = signal.samples[start..start + count]; const all_levels = D.envelope(signal.samples, attack_value, release_value); const levels = all_levels[start..start + count]; const rows = 2 * half + 1; const scale = @max(1, S.peak(window)); const grid = S.alloc(u8, rows * columns); @memset(grid, ' ');
    for (0..columns) |column| { const first = column * count / columns; const last = (column + 1) * count / columns; var maximum: i64 = -32768; var minimum: i64 = 32767; var level: i64 = 0; for (window[first..last], levels[first..last]) |value, e| { maximum = @max(maximum, value); minimum = @min(minimum, value); level = @max(level, e); } level = @min(scale, level); const top = plotRow(maximum, scale, rows); const bottom = plotRow(minimum, scale, rows); const upper = plotRow(level, scale, rows); const lower = plotRow(-level, scale, rows);
        for (0..rows) |row| grid[row * columns + column] = if (row == upper or row == lower) '*' else if (top <= row and row <= bottom) '#' else if (row == half) '-' else ' ';
    }
    var result: S.Lines = .{}; result.add("PLOT {s} rate={d} start={d} count={d} columns={d} rows={d} scale={d} attack={d} release={d}", .{ signal.name, signal.rate, start, count, columns, rows, scale, attack_value, release_value });
    for (0..rows) |row| { const label = if (row == 0) S.fmt("{d}", .{scale}) else if (row == half) "0" else if (row == rows - 1) S.fmt("{d}", .{-scale}) else ""; result.add("{s: >6} |{s}|", .{ label, grid[row * columns..(row + 1) * columns] }); }
    var axis: S.Text = .{}; axis.write("       +"); for (0..columns) |column| axis.byte(if (column % 10 == 0) '+' else '-'); axis.byte('+'); result.write(axis.value());
    var time_line: S.Text = .{}; time_line.write("    ms"); var column: usize = 0; while (column < columns) : (column += 10) { if (time_line.value().len < 8 + column) time_line.spaces(8 + column - time_line.value().len); time_line.add("{d}", .{milliseconds(start + column * count / columns, signal.rate)}); } result.write(time_line.value()); return result;
}
fn meterPlot(signal: *const S.Signal, block: usize) S.Lines {
    const blocks = (signal.samples.len + block - 1) / block; var result: S.Lines = .{}; result.add("METER {s} rate={d} samples={d} block={d} blocks={d}", .{ signal.name, signal.rate, signal.samples.len, block, blocks });
    for (0..blocks) |b| { const part = signal.samples[b * block..@min((b + 1) * block, signal.samples.len)]; const p = S.peak(part); const q = A.rms(part); const np = S.rdiv(p * 40, 32768); const nq = S.rdiv(q * 40, 32768); var bar: [40]u8 = undefined; for (&bar, 0..) |*ch, j| ch.* = if (S.int(j) < nq) '#' else if (S.int(j) < np) '-' else ' '; result.add("{d: >6} |{s}| peak={d} rms={d} clipped={d}", .{ milliseconds(b * block, signal.rate), bar, p, q, A.countClipped(part) }); }
    return result;
}
fn histogramPlot(signal: *const S.Signal, bins: usize) S.Lines {
    const counts = S.alloc(i64, bins); @memset(counts, 0); for (signal.samples) |value| counts[S.index(@divFloor((value + 32768) * S.int(bins), 65536))] += 1; var largest: i64 = 0; for (counts) |count| largest = @max(largest, count);
    var result: S.Lines = .{}; result.add("HISTOGRAM {s} rate={d} samples={d} bins={d} max={d}", .{ signal.name, signal.rate, signal.samples.len, bins, largest });
    for (counts, 0..) |count, b| { const low = @divFloor(S.int(b) * 65536 + S.int(bins) - 1, S.int(bins)) - 32768; const high = @divFloor(S.int(b + 1) * 65536 + S.int(bins) - 1, S.int(bins)) - 32769; var text: S.Text = .{}; text.add("{d: >6} {d: >6} {d: >5} |", .{ low, high, count }); for (0..S.index(S.rdiv(count * 50, largest))) |_| text.byte('#'); result.write(text.value()); }
    return result;
}
fn pitchRow(rate: i64, start: usize, level: i64, lag: ?usize, lags: Lags) []const u8 {
    var bar = [_]u8{' '} ** 41; if (lag) |n| { const position = if (lags.high > lags.low) S.index(S.rdiv(S.int(lags.high - n) * 40, S.int(lags.high - lags.low))) else 0; bar[position] = 'o'; return S.fmt("{d: >6} |{s}| lag={d} hz={s} rms={d}", .{ milliseconds(start, rate), bar, n, frequency(rate, n), level }); }
    return S.fmt("{d: >6} |{s}| unvoiced rms={d}", .{ milliseconds(start, rate), bar, level });
}
fn traceLines(result: *S.Lines, signal: *const S.Signal, depth: usize) void { var text: S.Text = .{}; text.spaces(2 * depth); text.add("{s} <- {s}", .{ signal.name, signal.origin }); result.write(text.value()); for (signal.ingredients) |ingredient| traceLines(result, ingredient, depth + 1); }
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); S.allocator = arena.allocator(); const dir = std.Io.Dir.cwd(); const signals_text = try dir.readFileAlloc(init.io, "input/signals.txt", S.allocator, .unlimited); const pipeline_text = try dir.readFileAlloc(init.io, "input/pipeline.txt", S.allocator, .unlimited); var pipeline = Pipeline.init(S.read(signals_text));
    for (S.lines(pipeline_text), 1..) |line, number| { if (line.len == 0 or line[0] == '#') continue; pipeline.run(number, line); } pipeline.finish(); try dir.createDirPath(init.io, "output");
    const reports = [_]S.Lines{ pipeline.log, pipeline.analysis, pipeline.excerpts, pipeline.waveforms, pipeline.saved }; const names = [_][]const u8{ "log.txt", "analysis.csv", "excerpts.txt", "waveforms.txt", "signals_out.txt" }; for (names, reports) |name, report| try dir.writeFile(init.io, .{ .sub_path = S.fmt("output/{s}", .{name}), .data = report.content() });
}
