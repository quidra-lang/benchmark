const std = @import("std");
const d = @import("song_parser.zig");
const instruments = @import("instruments.zig");
const sequencer = @import("sequencer.zig");
const mixer = @import("mixer.zig");
const r = @import("report.zig");
fn magnitude(value: i64) i64 {
    return @intCast(@abs(value));
}
const Channel = struct { instrument: ?usize = null, note: ?i64 = null, base: i64 = 0, target: i64 = 0,
     portamento: i64 = 0, slide: i64 = 0, detune: i64 = 0, vibrato_speed: i64 = 0, vibrato_depth: i64 = 0,
     vibrato_position: i64 = 0, tremolo_speed: i64 = 0, tremolo_depth: i64 = 0, tremolo_position: i64 = 0,
     volume: i64 = 15, mode: usize = 0, phase: i64 = 0, noise: i64 = 1, age: i64 = 0, released: bool = false,
     release_age: i64 = 0, release_value: i64 = 0, env: i64 = 0, output_frequency: i64 = 0, output_volume: i64 = 0,
     amplitude: i64 = 0, increment: i64 = 0, effect: d.Effect = .{}, sounding: bool = false, record: ?usize = null };
fn computeOutput(song: *const d.Song, c: *Channel, tick: usize) void {
    c.sounding = c.note != null;
    if (!c.sounding) return;
    const instrument = song.instruments[c.instrument.?].?;
    const effect = c.effect;
    var semitones: i64 = if (d.eq(effect.name, "0")) (if (tick % 3 == 0) 0 else if (tick % 3 == 1) effect.x else effect.y) else 0;
    if (instrument.arpeggio.len > 0) semitones += instrument.arpeggio[d.u(@mod(c.age, d.n(instrument.arpeggio.len)))];
    var f = instruments.transpose(c.base, semitones) + c.detune;
    if (d.eq(effect.name, "4") or d.eq(effect.name, "6")) f += instruments.oscillation(c.vibrato_position, c.vibrato_depth, 4);
    if (instrument.vibrato) |vibrato| if (c.age >= vibrato.delay) {
        f += instruments.oscillation(@mod((c.age - vibrato.delay) * vibrato.speed, 64), vibrato.depth, 4);
    };
    c.output_frequency = std.math.clamp(f, 1000, 50 * song.rate);
    c.env = instruments.envelope(instrument, c.age, c.released, c.release_age, c.release_value);
    c.output_volume = if (d.eq(effect.name, "7")) std.math.clamp(c.volume + instruments.oscillation(c.tremolo_position,
         c.tremolo_depth, 255), 0, 15) else c.volume;
    c.amplitude = c.env * c.output_volume;
    c.increment = @divFloor(c.output_frequency * 65536, 100 * song.rate);
}
const NoteRecord = struct { channel: usize, position: usize, row: usize, instrument: usize, note: i64,
     start: usize, length: usize = 0, release: ?usize = null, end: []const u8 = "" };
const RowRecord = struct { position: usize, pattern: usize, row: usize, start: usize, speed: usize,
     tempo: i64, notes: [4]?i64 = @splat(null) };
const ChannelStats = struct { notes: i64 = 0, retriggers: i64 = 0, cuts: i64 = 0, active: i64 = 0, audible: i64 = 0 };
const effect_order = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "A", "B", "C", "D", "E1",
     "E2", "E9", "EA", "EB", "EC", "ED", "EE", "F", "P", "Q", "R", "V" };
const Playback = struct {
    song: *const d.Song,
    params: d.Params,
    channels: [4]Channel = @splat(.{}),
    channel_stats: [4]ChannelStats = @splat(.{}),
    audio: mixer.Audio,
    notes: std.ArrayList(NoteRecord) = .empty,
    rows: std.ArrayList(RowRecord) = .empty,
    logs: r.Lines = .{},
    warnings: r.Lines = .{},
    instrument_ticks: [256]i64 = @splat(0),
    effects: [25]i64 = @splat(0),
    played: [][64]usize,
    first: [][64]?usize,
    ticks: i64 = 0,
    loop_start: ?usize = null,
    end: []const u8 = "",
    position: usize = 0,
    row: usize = 0,
    speed: usize,
    tempo: i64,
    fn init(song: *const d.Song, params: d.Params) Playback {
        const played = d.alloc([64]usize, song.order.len);
        @memset(played, @splat(0));
        const first = d.alloc([64]?usize, song.order.len);
        @memset(first, @splat(null));
        return .{ .song = song, .params = params, .audio = mixer.Audio.init(params.maximum), .played = played,
             .first = first, .speed = song.speed, .tempo = song.tempo };
    }
    fn warn(self: *Playback, channel: usize, message: []const u8) void {
        self.warnings.add("warning {s}:{s} ch{d} {s}", .{ r.hex(self.position, 2), r.hex(self.row, 2), channel + 1, message });
    }
    fn endRecord(self: *Playback, c: *Channel, reason: []const u8) void {
        const index = c.record orelse return;
        const record = &self.notes.items[index];
        record.length = self.audio.count - record.start;
        record.end = reason;
        c.record = null;
    }
    fn noteOn(self: *Playback, k: usize, note: i64) void {
        const c = &self.channels[k];
        self.endRecord(c, "next");
        c.base = instruments.frequency(note);
        c.target = c.base;
        c.phase = 0;
        c.age = 0;
        c.vibrato_position = 0;
        c.tremolo_position = 0;
        c.released = false;
        c.note = note;
        c.record = self.notes.items.len;
        d.append(NoteRecord, &self.notes, .{ .channel = k, .position = self.position, .row = self.row,
             .instrument = c.instrument.?, .note = note, .start = self.audio.count });
        self.channel_stats[k].notes += 1;
    }
    fn keyOff(self: *Playback, c: *Channel) void {
        c.release_age = c.age;
        c.release_value = c.env;
        c.released = true;
        if (c.record) |index| self.notes.items[index].release = self.audio.count - self.notes.items[index].start;
    }
    fn content(self: *Playback, k: usize, cell: d.Cell, portamento: bool) void {
        const c = &self.channels[k];
        if (cell.instrument) |number| {
            if (self.song.instruments[number]) |instrument| {
                c.instrument = number;
                c.volume = 15;
                c.mode = instrument.mode;
            } else self.warn(k, d.fmt("undefined instrument {s}", .{r.hex(number, 2)}));
        }
        if (cell.volume) |volume| c.volume = volume;
        if (cell.note == -2) {
            if (c.note != null and !c.released) self.keyOff(c) else self.warn(k, "key off without note");
        } else if (cell.note >= 0) {
            if (c.instrument == null) self.warn(k, "note without instrument") else if (portamento and c.note != null) {
                c.target = instruments.frequency(cell.note);
                c.note = cell.note;
            } else {
                if (portamento) self.warn(k, "portamento without note");
                self.noteOn(k, cell.note);
            }
        }
    }
    fn approach(c: *Channel, step: i64) void {
        c.base = if (c.base < c.target) @min(c.base + step, c.target) else @max(c.base - step, c.target);
    }
    fn effectZero(self: *Playback, k: usize, delay: *usize) void {
        const c = &self.channels[k];
        const effect = c.effect;
        const a = effect.argument;
        const song = self.song;
        if (d.eq(effect.name, "3")) {
            if (a > 0) c.portamento = a;
        } else if (d.eq(effect.name, "4")) {
            if (effect.x > 0) c.vibrato_speed = effect.x;
            if (effect.y > 0) c.vibrato_depth = effect.y;
        } else if (d.eq(effect.name, "7")) {
            if (effect.x > 0) c.tremolo_speed = effect.x;
            if (effect.y > 0) c.tremolo_depth = effect.y;
        } else if (d.eq(effect.name, "C")) c.volume = @min(a, 15) else if (d.eq(effect.name, "E1")) c.base = std.math.clamp(c.base + 10 * a,
             1000, 50 * song.rate) else if (d.eq(effect.name, "E2")) c.base = std.math.clamp(c.base - 10 * a,
             1000, 50 * song.rate) else if (d.eq(effect.name, "EA")) c.volume = @min(c.volume + a,
             15) else if (d.eq(effect.name, "EB")) c.volume = @max(c.volume - a, 0) else if (d.eq(effect.name,
             "EE")) delay.* = d.u(a) else if (d.eq(effect.name, "F")) {
            if (a >= 1 and a <= 31) self.speed = d.u(a) else if (a >= 32) self.tempo = a;
        } else if (d.eq(effect.name, "P")) c.detune = a - 128 else if (d.eq(effect.name, "Q") or d.eq(effect.name, "R")) {
            if (c.note) |note| {
                c.note = if (d.eq(effect.name, "Q")) @min(note + effect.y, 95) else @max(note - effect.y, 12);
                c.target = instruments.frequency(c.note.?);
                c.slide = 2 * effect.x + 1;
            } else self.warn(k, "slide without note");
        } else if (d.eq(effect.name, "V")) {
            if (c.instrument != null and ((song.instruments[c.instrument.?].?.wave == .pulse and a <= 3) or (song.instruments[c.instrument.?].?.wave == .noise and a <= 1))) c.mode = d.u(a) else self.warn(k,
                 d.fmt("invalid mode {s}", .{r.hex(a, 2)}));
        }
    }
    fn rowStart(self: *Playback, cells: d.Row) usize {
        var delay: usize = 0;
        for (cells, &self.channels, 0..) |cell, *c, k| {
            c.effect = cell.effect;
            c.slide = 0;
            for (effect_order, 0..) |name, i| if (d.eq(c.effect.name, name)) {
                self.effects[i] += 1;
            };
            if (!d.eq(c.effect.name, "ED") or c.effect.argument < 1) self.content(k, cell, d.eq(c.effect.name,
                 "3") or d.eq(c.effect.name, "5"));
            self.effectZero(k, &delay);
        }
        const count = self.speed * (1 + delay);
        for (self.channels, 0..) |c, k| {
            if (d.eq(c.effect.name, "EC") and c.effect.argument >= d.n(count)) self.warn(k, "cut beyond row");
            if (d.eq(c.effect.name, "ED") and c.effect.argument >= d.n(count)) self.warn(k, "delay beyond row");
        }
        return count;
    }
    fn processTick(self: *Playback, cells: d.Row, tick: usize) void {
        const song = self.song;
        for (&self.channels, 0..) |*c, k| {
            const effect = c.effect;
            if (c.note != null and c.age >= 1) {
                const sweep = song.instruments[c.instrument.?].?.sweep;
                if (sweep != 0) c.base = std.math.clamp(c.base + 10 * sweep, 1000, 50 * song.rate);
            }
            if (tick >= 1) {
                if (d.eq(effect.name, "1")) c.base = std.math.clamp(c.base + 10 * effect.argument,
                     1000, 50 * song.rate) else if (d.eq(effect.name, "2")) c.base = std.math.clamp(c.base - 10 * effect.argument,
                     1000, 50 * song.rate) else if (d.eq(effect.name, "3")) approach(c, 10 * c.portamento) else if (d.eq(effect.name,
                     "5")) {
                    approach(c, 10 * c.portamento);
                    c.volume = std.math.clamp(c.volume + effect.x - effect.y, 0, 15);
                } else if (d.eq(effect.name, "6") or d.eq(effect.name, "A")) c.volume = std.math.clamp(c.volume + effect.x - effect.y,
                     0, 15) else if ((d.eq(effect.name, "Q") or d.eq(effect.name, "R")) and c.slide != 0) approach(c,
                     10 * c.slide);
            }
            if (d.eq(effect.name, "ED") and effect.argument >= 1 and d.n(tick) == effect.argument) self.content(k,
                 cells[k], false);
            if (d.eq(effect.name, "E9") and effect.argument >= 1 and tick >= 1 and @mod(d.n(tick),
                 effect.argument) == 0 and c.note != null) {
                c.phase = 0;
                c.age = 0;
                c.released = false;
                self.channel_stats[k].retriggers += 1;
            }
            if (d.eq(effect.name, "EC") and d.n(tick) == effect.argument and c.note != null) {
                c.note = null;
                self.endRecord(c, "cut");
                self.channel_stats[k].cuts += 1;
            }
            computeOutput(song, c, tick);
            if (c.sounding) {
                self.channel_stats[k].active += 1;
                if (c.amplitude > 0) self.channel_stats[k].audible += 1;
                self.instrument_ticks[c.instrument.?] += 1;
            }
        }
    }
    fn channelLine(c: Channel) []const u8 {
        const note = c.note orelse return d.fmt("--- --       - - {s} {s}", .{ r.hex(c.volume, 1), c.effect.text });
        return d.fmt("{s} {s} {s} {s} {s} {s}", .{ d.noteName(note), r.hex(c.instrument.?, 2), r.aligned(c.output_frequency,
             7), r.hex(c.env, 1), r.hex(c.output_volume, 1), c.effect.text });
    }
    fn tickLine(c: Channel) []const u8 {
        return if (c.sounding) d.fmt("{s} {s} {s}{s}", .{ r.aligned(c.output_frequency, 7), r.aligned(c.increment,
             5), r.hex(c.env, 1), r.hex(c.output_volume, 1) }) else "      -     - --";
    }
    fn run(self: *Playback) void {
        const song = self.song;
        while (true) {
            const start = self.audio.count;
            if (self.first[self.position][self.row] == null) self.first[self.position][self.row] = start;
            self.played[self.position][self.row] += 1;
            const cells = song.patterns[song.order[self.position]].?[self.row];
            const count = self.rowStart(cells);
            const spt = sequencer.samplesPerTick(song, self.tempo);
            var record: RowRecord = .{ .position = self.position, .pattern = song.order[self.position],
                 .row = self.row, .start = start, .speed = self.speed, .tempo = self.tempo };
            var limited = false;
            for (0..count) |tick| {
                self.processTick(cells, tick);
                if (tick == 0) {
                    for (self.channels, &record.notes) |c, *note| note.* = c.note;
                    self.logs.add("{s} {s} {s} {s} {s} {s} | {s} | {s} | {s} | {s}", .{ r.hex(self.position,
                         2), r.hex(song.order[self.position], 2), r.hex(self.row, 2), r.aligned(start,
                         7), r.aligned(self.speed, 2), r.aligned(self.tempo, 3), channelLine(self.channels[0]),
                         channelLine(self.channels[1]), channelLine(self.channels[2]), channelLine(self.channels[3]) });
                }
                if (self.params.traces[self.position][self.row]) self.logs.add("  tick {s} {s} | {s} | {s} | {s} | {s}",
                     .{ r.aligned(tick, 3), r.aligned(self.audio.count, 7), tickLine(self.channels[0]),
                     tickLine(self.channels[1]), tickLine(self.channels[2]), tickLine(self.channels[3]) });
                mixer.generate(song, &self.channels, @min(spt, self.params.maximum - self.audio.count),
                     self.params.muted, &self.audio);
                self.ticks += 1;
                for (&self.channels) |*c| {
                    if (c.note != null) c.age += 1;
                    if (d.eq(c.effect.name, "4") or d.eq(c.effect.name, "6")) c.vibrato_position = @mod(c.vibrato_position + c.vibrato_speed,
                         64);
                    if (d.eq(c.effect.name, "7")) c.tremolo_position = @mod(c.tremolo_position + c.tremolo_speed, 64);
                }
                if (self.audio.count == self.params.maximum) {
                    self.end = "limit";
                    limited = true;
                    break;
                }
            }
            d.append(RowRecord, &self.rows, record);
            if (limited) break;
            const next = sequencer.nextRow(song, self.position, self.row);
            if (next.stop) {
                self.end = d.fmt("stop order={s} row={s}", .{ r.hex(self.position, 2), r.hex(self.row, 2) });
                break;
            }
            if (next.position >= song.order.len) {
                self.end = "finished";
                break;
            }
            if (self.played[next.position][next.row] >= self.params.loops) {
                self.loop_start = self.first[next.position][next.row];
                self.end = d.fmt("loop order={s} row={s}", .{ r.hex(next.position, 2), r.hex(next.row, 2) });
                break;
            }
            self.position = next.position;
            self.row = next.row;
        }
        for (&self.channels) |*c| self.endRecord(c, "end");
        if ((d.eq(self.end, "limit") or std.mem.startsWith(u8, self.end, "loop ")) and self.params.fade > 0) mixer.fade(&self.audio,
             self.params.fade);
    }
};
fn noteLines(p: *const Playback) r.Lines {
    var out: r.Lines = .{};
    for (p.notes.items, 1..) |note, serial| {
        const lane = p.audio.lanes[note.channel];
        var peak: i64 = 0;
        var cycles: i64 = 0;
        for (note.start..note.start + note.length) |i| {
            peak = @max(peak, magnitude(lane[i]));
            if (i > note.start and lane[i - 1] < 0 and lane[i] >= 0) cycles += 1;
        }
        out.add("{s} ch={d} at={s}:{s} ins={s} note={s} start={d} length={d} release={s} end={s} peak={d} cycles={d}",
             .{ r.aligned(serial, 4), note.channel + 1, r.hex(note.position, 2), r.hex(note.row, 2),
             r.hex(note.instrument, 2), d.noteName(note.note), note.start, note.length, if (note.release) |release| d.fmt("{d}",
             .{release}) else "-", note.end, peak, cycles });
    }
    return out;
}
fn rollLines(p: *const Playback) r.Lines {
    const first = @min(p.params.roll_start, p.rows.items.len);
    const end = @min(p.rows.items.len, p.params.roll_start + p.params.roll_rows);
    const count = end - first;
    var pitches = std.mem.zeroes([96]bool);
    var pitch_count: usize = 0;
    for (p.rows.items[first..end]) |row| for (row.notes) |note| {
        if (note) |value| if (!pitches[d.u(value)]) {
            pitches[d.u(value)] = true;
            pitch_count += 1;
        };
    };
    var out: r.Lines = .{};
    out.add("ROLL start={d} rows={d} pitches={d}", .{ p.params.roll_start, count, pitch_count });
    var note: usize = 96;
    while (note > 12) {
        note -= 1;
        if (!pitches[note]) continue;
        var marks: r.Text = .{};
        for (p.rows.items[first..end]) |row| {
            var channel: usize = 0;
            var number: usize = 0;
            for (row.notes, 0..) |value, k| if (value != null and value.? == d.n(note)) {
                channel = k;
                number += 1;
            };
            marks.add("{c}", .{if (number == 0) @as(u8, ' ') else if (number == 1) @as(u8, '1') + @as(u8,
                 @intCast(channel)) else @as(u8, '*')});
        }
        out.add("{s} |{s}|", .{ d.noteName(d.n(note)), marks.value() });
    }
    var axis: r.Text = .{};
    axis.add("    +", .{});
    for (0..count) |i| axis.add("{c}", .{if (i % 16 == 0) @as(u8, '+') else @as(u8, '-')});
    axis.add("+", .{});
    out.add("{s}", .{axis.value()});
    return out;
}
fn noteRange(p: *const Playback, channel: ?usize, instrument: ?usize) []const u8 {
    var lo: i64 = 96;
    var hi: i64 = -1;
    for (p.notes.items) |note| {
        if ((channel != null and channel.? != note.channel) or (instrument != null and instrument.? != note.instrument)) continue;
        lo = @min(lo, note.note);
        hi = @max(hi, note.note);
    }
    return if (hi < 0) "none" else d.fmt("{s}..{s}", .{ d.noteName(lo), d.noteName(hi) });
}
fn appendList(out: *r.Lines, prefix: []const u8, values: []const usize) void {
    var text: r.Text = .{};
    text.add("{s}", .{prefix});
    if (values.len == 0) text.add("none", .{}) else for (values, 0..) |value, i| text.add("{s}{s}",
         .{ if (i == 0) "" else " ", r.hex(value, 2) });
    out.add("{s}", .{text.value()});
}
const KeyContext = [24]i64;
fn keyLess(scores: KeyContext, a: usize, b: usize) bool {
    return if (scores[a] != scores[b]) scores[a] > scores[b] else a < b;
}
fn statsLines(p: *const Playback) r.Lines {
    const song = p.song;
    const samples = p.audio.samples[0..p.audio.count];
    const stats = r.statistics(samples);
    var out: r.Lines = .{};
    out.add("title={s}", .{song.title});
    out.add("rate={d}", .{song.rate});
    out.add("samples={d}", .{samples.len});
    out.add("duration_ms={d}", .{@divTrunc(d.n(samples.len) * 1000, song.rate)});
    out.add("end={s}", .{p.end});
    out.add("loop_start={s}", .{if (p.loop_start) |start| d.fmt("{d}", .{start}) else "-"});
    out.add("loop_length={s}", .{if (p.loop_start) |start| d.fmt("{d}", .{samples.len - start}) else "-"});
    out.add("rows={d}", .{p.rows.items.len});
    out.add("ticks={d}", .{p.ticks});
    out.add("clipped={d}", .{p.audio.clipped});
    out.add("peak={d}", .{stats.peak});
    out.add("min={d}", .{stats.minimum});
    out.add("max={d}", .{stats.maximum});
    out.add("rms={d}", .{stats.rms});
    out.add("zero_crossings={d}", .{stats.crossings});
    out.add("adler32={s}", .{r.hex(r.adler32(samples), 8)});
    var path: r.Text = .{};
    path.add("path", .{});
    var previous: ?usize = null;
    for (p.rows.items) |row| if (previous == null or previous.? != row.position) {
        path.add(" {s}", .{r.hex(row.position, 2)});
        previous = row.position;
    };
    out.add("{s}", .{path.value()});
    var speed: ?usize = null;
    var tempo: i64 = -1;
    for (p.rows.items) |row| if (speed == null or speed.? != row.speed or tempo != row.tempo) {
        out.add("timing sample={d} order={s} row={s} speed={d} tempo={d}", .{ row.start, r.hex(row.position,
             2), r.hex(row.row, 2), row.speed, row.tempo });
        speed = row.speed;
        tempo = row.tempo;
    };
    for (p.channel_stats, p.audio.lanes, 1..) |channel, lane, k| {
        var peak: i64 = 0;
        var squares: i64 = 0;
        for (lane[0..p.audio.count]) |value| {
            peak = @max(peak, magnitude(value));
            squares += value * value;
        }
        out.add("channel {d} notes={d} retriggers={d} cuts={d} active={d} audible={d} peak={d} rms={d}",
             .{ k, channel.notes, channel.retriggers, channel.cuts, channel.active, channel.audible,
             peak, r.integerSqrt(@divTrunc(squares, d.n(samples.len))) });
    }
    var instrument_counts = std.mem.zeroes([256]i64);
    var instrument_lengths = std.mem.zeroes([256]i64);
    var note_counts = std.mem.zeroes([96]i64);
    for (p.notes.items) |note| {
        instrument_counts[note.instrument] += 1;
        instrument_lengths[note.instrument] += d.n(note.length);
        note_counts[d.u(note.note)] += 1;
    }
    for (song.instruments, 0..) |maybe_instrument, number| if (maybe_instrument) |instrument| {
        out.add("instrument {s} {s} {s} notes={d} ticks={d} range={s} average={s}", .{ r.hex(number,
             2), instrument.name, instruments.waveName(instrument.wave), instrument_counts[number],
             p.instrument_ticks[number], noteRange(p, null, number), if (instrument_counts[number] == 0) "-" else d.fmt("{d}",
             .{@divTrunc(instrument_lengths[number], instrument_counts[number])}) });
    };
    var order_counts = std.mem.zeroes([256]usize);
    for (song.order) |pattern| order_counts[pattern] += 1;
    for (song.patterns, 0..) |maybe_pattern, number| if (maybe_pattern) |pattern| {
        var rows: usize = 0;
        var notes: usize = 0;
        for (pattern) |row| {
            var any = false;
            for (row) |cell| {
                if (!cell.empty()) any = true;
                if (cell.note != -1) notes += 1;
            }
            if (any) rows += 1;
        }
        out.add("pattern {s} rows={d} notes={d} orders={d}", .{ r.hex(number, 2), rows, notes, order_counts[number] });
    };
    const reached = sequencer.reachable(song);
    const position_counts = d.alloc(usize, song.order.len);
    @memset(position_counts, 0);
    for (song.order, 0..) |pattern, position| {
        var first: ?usize = null;
        var dead: usize = 0;
        for (0..64) |row| {
            position_counts[position] += p.played[position][row];
            if (p.first[position][row]) |start| {
                if (first == null or start < first.?) first = start;
            }
            if (!reached[position][row]) {
                var note = false;
                for (song.patterns[pattern].?[row]) |cell| if (cell.note != -1) {
                    note = true;
                };
                if (note) dead += 1;
            }
        }
        out.add("order {s} pattern={s} rows={d} first={s} dead={d}", .{ r.hex(position, 2), r.hex(pattern,
             2), position_counts[position], if (first) |start| d.fmt("{d}", .{start}) else "-", dead });
    }
    for (note_counts, 0..) |count, note| if (count > 0) out.add("note {s} count={d}", .{ d.noteName(d.n(note)), count });
    var effects: r.Text = .{};
    effects.add("effects", .{});
    var any_effect = false;
    for (effect_order, p.effects) |name, count| if (count > 0) {
        effects.add(" {s}={d}", .{ name, count });
        any_effect = true;
    };
    if (!any_effect) effects.add(" none", .{});
    out.add("{s}", .{effects.value()});
    var unused_instruments: std.ArrayList(usize) = .empty;
    var unused_patterns: std.ArrayList(usize) = .empty;
    var unreached_orders: std.ArrayList(usize) = .empty;
    for (song.instruments, instrument_counts, 0..) |instrument, count, i| if (instrument != null and count == 0) d.append(usize,
         &unused_instruments, i);
    for (song.patterns, order_counts, 0..) |pattern, count, i| if (pattern != null and count == 0) d.append(usize,
         &unused_patterns, i);
    for (position_counts, 0..) |count, i| if (count == 0) d.append(usize, &unreached_orders, i);
    appendList(&out, "unused_instruments=", unused_instruments.items);
    appendList(&out, "unused_patterns=", unused_patterns.items);
    appendList(&out, "unreached_orders=", unreached_orders.items);
    var pitch_classes = std.mem.zeroes([12]i64);
    for (p.notes.items) |note| if (song.instruments[note.instrument].?.wave != .noise) {
        pitch_classes[d.u(@mod(note.note, 12))] += d.n(note.length);
    };
    const tonics = [_][]const u8{ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
    var pitch_line: r.Text = .{};
    pitch_line.add("pitch_classes", .{});
    for (tonics, pitch_classes) |name, count| pitch_line.add(" {s}={d}", .{ name, count });
    out.add("{s}", .{pitch_line.value()});
    const major = [12]i64{ 64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29 };
    const minor = [12]i64{ 64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32 };
    var scores = std.mem.zeroes([24]i64);
    var keys: [24]usize = undefined;
    for (&keys, 0..) |*key, i| {
        key.* = i;
        for (pitch_classes, 0..) |count, j| scores[i] += (if (i < 12) major else minor)[d.u(@mod(d.n(j) - d.n(i % 12),
             12))] * count;
    }
    std.mem.sort(usize, &keys, scores, keyLess);
    out.add("key={s} {s} score={d} runner_up={s} {s} score={d}", .{ tonics[keys[0] % 12], if (keys[0] < 12) "major" else "minor",
         scores[keys[0]], tonics[keys[1] % 12], if (keys[1] < 12) "major" else "minor", scores[keys[1]] });
    for (0..4) |k| {
        var counts = std.mem.zeroes([256]i64);
        for (p.notes.items) |note| if (note.channel == k) {
            counts[note.instrument] += 1;
        };
        var usage: r.Text = .{};
        usage.add("usage ch{d} range={s}", .{ k + 1, noteRange(p, k, null) });
        for (song.instruments, counts, 0..) |instrument, count, i| if (instrument != null) usage.add(" {s}={d}",
             .{ r.hex(i, 2), count });
        out.add("{s}", .{usage.value()});
    }
    out.extend(p.warnings);
    return out;
}
fn plotRow(value: i64, lo: i64, hi: i64, height: usize) usize {
    return d.u(@divFloor(2 * (hi - value) * d.n(height - 1) + (hi - lo), 2 * (hi - lo)));
}
fn waveformPlot(values: []const i64, lo: i64, hi: i64, mid: i64, width: usize, height: usize) r.Lines {
    const middle = plotRow(mid, lo, hi, height);
    const top = d.alloc(usize, width);
    const bottom = d.alloc(usize, width);
    for (0..width) |col| {
        const first = col * values.len / width;
        const end = (col + 1) * values.len / width;
        var low = values[first];
        var high = low;
        for (values[first..end]) |value| {
            low = @min(low, value);
            high = @max(high, value);
        }
        top[col] = plotRow(high, lo, hi, height);
        bottom[col] = plotRow(low, lo, hi, height);
    }
    var out: r.Lines = .{};
    for (0..height) |row| {
        const label = if (row == 0) r.aligned(hi, 5) else if (row == middle) r.aligned(mid, 5) else if (row == height - 1) r.aligned(lo,
             5) else "     ";
        const marks = d.alloc(u8, width);
        for (marks, top, bottom) |*mark, a, b| mark.* = if (a <= row and row <= b) '#' else if (row == middle) '-' else ' ';
        out.add("{s} |{s}|", .{ label, marks });
    }
    return out;
}
fn axes(song: *const d.Song, p: d.Params) r.Lines {
    var first: r.Text = .{};
    first.add("      +", .{});
    for (0..p.width) |col| first.add("{c}", .{if (col % 10 == 0) @as(u8, '+') else @as(u8, '-')});
    first.add("+", .{});
    const second = d.alloc(u8, p.width + 64);
    @memset(second, ' ');
    @memcpy(second[0..6], "    ms");
    var end: usize = 6;
    var col: usize = 0;
    while (col < p.width) : (col += 10) {
        const text = d.fmt("{d}", .{@divTrunc(d.n(p.start + col * p.length / p.width) * 1000, song.rate)});
        const position = 7 + col;
        @memcpy(second[position .. position + text.len], text);
        end = position + text.len;
    }
    var out: r.Lines = .{};
    out.add("{s}", .{first.value()});
    out.add("{s}", .{second[0..end]});
    return out;
}
fn waveformLines(p: *const Playback) r.Lines {
    const params = p.params;
    var out: r.Lines = .{};
    out.add("MIX start={d} length={d} width={d} height={d}", .{ params.start, params.length, params.width, params.height });
    out.extend(waveformPlot(p.audio.samples[params.start .. params.start + params.length], 0, 255,
         128, params.width, params.height));
    out.extend(axes(p.song, params));
    for (p.audio.lanes, 1..) |lane, k| {
        out.add("CHANNEL {d}", .{k});
        out.extend(waveformPlot(lane[params.start .. params.start + params.length], -3375, 3375, 0, params.width, params.scope));
    }
    out.extend(axes(p.song, params));
    return out;
}
fn previewLines(song: *const d.Song, p: d.Params) r.Lines {
    var out: r.Lines = .{};
    const spt = sequencer.samplesPerTick(song, song.tempo);
    for (song.instruments, 0..) |maybe_instrument, number| if (maybe_instrument) |instrument| {
        const parent = d.allocator;
        var arena = std.heap.ArenaAllocator.init(parent);
        d.allocator = arena.allocator();
        var channels: [4]Channel = @splat(.{});
        const c = &channels[0];
        c.instrument = number;
        c.mode = instrument.mode;
        c.note = p.preview_note;
        c.base = instruments.frequency(p.preview_note);
        c.target = c.base;
        var audio = mixer.Audio.init(p.preview_ticks * spt);
        var env: r.Text = .{};
        var frequencies: r.Text = .{};
        for (0..p.preview_ticks) |tick| {
            if (tick == p.preview_release) {
                c.released = true;
                c.release_age = d.n(tick);
                c.release_value = c.env;
            }
            if (tick >= 1 and instrument.sweep != 0) c.base = std.math.clamp(c.base + 10 * instrument.sweep,
                 1000, 50 * song.rate);
            c.age = d.n(tick);
            computeOutput(song, c, tick);
            env.add("{s}", .{r.hex(c.env, 1)});
            frequencies.add("{s}{d}", .{ if (tick == 0) "" else " ", c.output_frequency });
            mixer.generate(song, &channels, spt, @splat(false), &audio);
        }
        const stats = r.statistics(audio.samples[0..audio.count]);
        const adler = r.adler32(audio.samples[0..audio.count]);
        d.allocator = parent;
        out.add("instrument {s} {s} wave={s} samples={d} peak={d} rms={d} adler32={s}", .{ r.hex(number,
             2), instrument.name, instruments.waveName(instrument.wave), audio.count, stats.peak,
             stats.rms, r.hex(adler, 8) });
        out.add("  env {s}", .{env.value()});
        out.add("  freq {s}", .{frequencies.value()});
        arena.deinit();
    };
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const song = try d.readSong(init.io);
    const params = try d.readParams(init.io);
    var playback = Playback.init(&song, params);
    playback.run();
    try r.write(init.io, "samples.txt", r.sampleDump(playback.audio.samples[0..playback.audio.count]));
    try r.write(init.io, "channel_log.txt", playback.logs);
    try r.write(init.io, "notes.txt", noteLines(&playback));
    try r.write(init.io, "roll.txt", rollLines(&playback));
    try r.write(init.io, "stats.txt", statsLines(&playback));
    try r.write(init.io, "waveform.txt", waveformLines(&playback));
    try r.write(init.io, "instruments.txt", previewLines(&song, params));
}
