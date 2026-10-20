const std = @import("std");
const Text = []const u8;
const I = i64;
fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn number(a: Text) I { return std.fmt.parseInt(I, a, 10) catch unreachable; }
fn ix(a: I) usize { return @intCast(a); }
fn byte(a: I) u8 { return @intCast(a); }
const Host = struct {
    a: std.mem.Allocator,
    out: *std.Io.Writer,
    fn text(h: Host, comptime f: Text, args: anytype) !Text { return std.fmt.allocPrint(h.a, f, args); }
    fn line(h: Host, comptime f: Text, args: anytype) !void { try h.out.print(f ++ "\n", args); }
};
const names = [_]Text{"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
const channels = [_]Text{"NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND"};
const text_kinds = [_]Text{"TEXT_EVENT", "COPYRIGHT", "TRACK_NAME", "INSTRUMENT_NAME", "LYRIC", "MARKER", "CUE_POINT"};
const keys = [2][15]Text{
    .{"Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"},
    .{"Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"},
};
fn noteName(h: Host, pitch: I) !Text { return h.text("{s}{d}", .{names[ix(@mod(pitch, 12))], @divTrunc(pitch, 12) - 1}); }
fn kindName(code: u16) Text {
    if (code < 240) return channels[code / 16 - 8];
    if (code == 240) return "SYSEX";
    if (code == 247) return "SYSEX_ESCAPE";
    const tag = code - 256;
    if (tag >= 1 and tag <= 7) return text_kinds[tag - 1];
    return switch (tag) {
        0 => "SEQUENCE_NUMBER", 32 => "CHANNEL_PREFIX", 47 => "END_OF_TRACK", 81 => "TEMPO",
        84 => "SMPTE_OFFSET", 88 => "TIME_SIGNATURE", 89 => "KEY_SIGNATURE", 127 => "SEQUENCER_SPECIFIC", else => "META",
    };
}
fn knownMeta(tag: u16) bool { return tag <= 7 or tag == 32 or tag == 47 or tag == 81 or tag == 84 or tag == 88 or tag == 89 or tag == 127; }
fn bigEndian(bytes: []const u8) I {
    var result: I = 0;
    for (bytes) |value| result = result * 256 + value;
    return result;
}
fn putBig(bytes: *std.ArrayList(u8), a: std.mem.Allocator, value: I, size: usize) !void {
    var remaining = value;
    const start = bytes.items.len;
    try bytes.resize(a, start + size);
    for (0..size) |j| {
        bytes.items[start + size - 1 - j] = byte(@mod(remaining, 256));
        remaining = @divTrunc(remaining, 256);
    }
}
fn bigBytes(h: Host, value: I, size: usize) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    try putBig(&bytes, h.a, value, size);
    return bytes.toOwnedSlice(h.a);
}
fn putVlq(bytes: *std.ArrayList(u8), a: std.mem.Allocator, value: I) !void {
    var groups: [10]u8 = undefined;
    var len: usize = 1;
    var remaining = @divTrunc(value, 128);
    groups[0] = byte(@mod(value, 128));
    while (remaining > 0) : (remaining = @divTrunc(remaining, 128)) {
        groups[len] = byte(@mod(remaining, 128) + 128);
        len += 1;
    }
    while (len > 0) { len -= 1; try bytes.append(a, groups[len]); }
}
const Event = struct {
    tick: I,
    code: u16,
    payload: []u8 = &.{},
    fn isChannel(e: Event) bool { return e.code < 240; }
    fn channel(e: Event) I { return e.code % 16 + 1; }
    fn on(e: Event) bool { return e.code / 16 == 9 and e.payload[1] > 0; }
    fn off(e: Event) bool { return e.code / 16 == 8 or (e.code / 16 == 9 and e.payload[1] == 0); }
    fn fields(e: Event, h: Host) !Text {
        var b: std.Io.Writer.Allocating = .init(h.a);
        if (e.isChannel()) {
            try b.writer.print("{d}", .{e.channel()});
            const family = e.code / 16;
            if (family <= 10) try b.writer.print(" {s} {d}", .{try noteName(h, e.payload[0]), e.payload[1]})
            else if (family == 14) try b.writer.print(" {d}", .{@as(I, e.payload[0]) + 128 * @as(I, e.payload[1]) - 8192})
            else for (e.payload) |value| { try b.writer.print(" {d}", .{value}); };
        } else if (e.code >= 257 and e.code <= 263) {
            try b.writer.print("\"{s}\"", .{e.payload});
        } else switch (e.code) {
            256, 337 => try b.writer.print("{d}", .{bigEndian(e.payload)}),
            288 => try b.writer.print("{d}", .{@as(I, e.payload[0]) + 1}),
            303 => {},
            340 => for (e.payload, 0..) |value, j| {
                if (j > 0) try b.writer.writeByte(' ');
                try b.writer.print("{d}", .{value});
            },
            344 => try b.writer.print("{d}/{d} {d} {d}", .{e.payload[0], @as(I, 1) << @as(u6, @intCast(e.payload[1])), e.payload[2], e.payload[3]}),
            345 => {
                const sf: I = if (e.payload[0] >= 128) @as(I, e.payload[0]) - 256 else e.payload[0];
                try b.writer.print("{s} {s}", .{keys[e.payload[1]][ix(sf + 7)], if (e.payload[1] == 0) @as(Text, "major") else "minor"});
            },
            else => {
                if (e.code >= 256 and e.code != 383) try b.writer.print("{X:0>2} ", .{e.code - 256});
                try b.writer.print("{d}", .{e.payload.len});
                if (e.payload.len > 0) {
                    try b.writer.writeByte(' ');
                    for (e.payload) |value| try b.writer.print("{X:0>2}", .{value});
                }
            },
        }
        return b.toOwnedSlice();
    }
    fn textLine(e: Event, h: Host, track_id: usize) !Text {
        const suffix = try e.fields(h);
        return h.text("{d} {d} {s}{s}{s}", .{e.tick, track_id, kindName(e.code), if (suffix.len > 0) @as(Text, " ") else "", suffix});
    }
};
const Track = std.ArrayList(Event);
const Placed = struct { track_id: usize, event_id: usize, event: Event };
const Song = struct {
    format: I,
    division: I,
    tracks: std.ArrayList(Track) = .empty,
    fn clone(s: Song, h: Host) !Song {
        var result: Song = .{.format = s.format, .division = s.division};
        for (s.tracks.items) |track_value| {
            var copied: Track = .empty;
            for (track_value.items) |ev| {
                var next = ev;
                next.payload = try h.a.dupe(u8, ev.payload);
                try copied.append(h.a, next);
            }
            try result.tracks.append(h.a, copied);
        }
        return result;
    }
    fn count(s: Song) usize {
        var result: usize = 0;
        for (s.tracks.items) |track_value| result += track_value.items.len;
        return result;
    }
    fn length(s: Song) I {
        var result: I = 0;
        for (s.tracks.items) |track_value| result = @max(result, track_value.items[track_value.items.len - 1].tick);
        return result;
    }
    fn description(s: Song, h: Host) !Text { return h.text("format {d} tracks {d} division {d} events {d}", .{s.format, s.tracks.items.len, s.division, s.count()}); }
    fn globalOrder(s: Song, h: Host) ![]Placed {
        var result: std.ArrayList(Placed) = .empty;
        for (s.tracks.items, 0..) |track_value, ti| for (track_value.items, 0..) |ev, ei| {
            try result.append(h.a, .{.track_id = ti, .event_id = ei, .event = ev});
        };
        std.mem.sort(Placed, result.items, {}, struct {
            fn less(_: void, a: Placed, b: Placed) bool {
                if (a.event.tick != b.event.tick) return a.event.tick < b.event.tick;
                if (a.track_id != b.track_id) return a.track_id < b.track_id;
                return a.event_id < b.event_id;
            }
        }.less);
        return result.toOwnedSlice(h.a);
    }
    fn clockText(s: Song, h: Host, target: I, ordered: []const Placed) !Text {
        var scaled: I = 0;
        var last_tick: I = 0;
        var usec: I = 500000;
        for (ordered) |placed| {
            const ev = placed.event;
            if (ev.tick > target) break;
            if (ev.code == 337) {
                scaled += (ev.tick - last_tick) * usec;
                last_tick = ev.tick;
                usec = bigEndian(ev.payload);
            }
        }
        const micros = @divTrunc(scaled + (target - last_tick) * usec, s.division);
        return h.text("{d}.{d:0>3}", .{@divTrunc(micros, 1000), @mod(micros, 1000)});
    }
    fn barText(s: Song, h: Host, target: I, ordered: []const Placed) !Text {
        var start_tick: I = 0;
        var bar_number: I = 1;
        var numerator: I = 4;
        var beat = s.division;
        for (ordered) |placed| {
            const ev = placed.event;
            if (ev.tick > target) break;
            if (ev.code == 344) {
                const size = numerator * beat;
                bar_number += @divTrunc(ev.tick - start_tick + size - 1, size);
                start_tick = ev.tick;
                numerator = ev.payload[0];
                beat = @divTrunc(s.division * 4, @as(I, 1) << @as(u6, @intCast(ev.payload[1])));
            }
        }
        const delta = target - start_tick;
        const size = numerator * beat;
        return h.text("{d}:{d}:{d}", .{bar_number + @divTrunc(delta, size), @divTrunc(@mod(delta, size), beat) + 1, @mod(delta, beat)});
    }
};
const Note = struct { on_id: usize, off_id: usize, start_tick: I, duration: I, channel_id: I, pitch: I, velocity: I };
const Pairing = struct { ordered: []Placed, notes: std.ArrayList(Note) = .empty, unmatched: std.ArrayList(usize) = .empty, pending: std.ArrayList(usize) = .empty };
fn pairNotes(song: Song, h: Host) !Pairing {
    var result: Pairing = .{.ordered = try song.globalOrder(h)};
    const consumed = try h.a.alloc(bool, result.ordered.len);
    @memset(consumed, false);
    for (result.ordered, 0..) |placed, oi| {
        const ev = placed.event;
        if (!ev.off()) continue;
        for (result.ordered[0..oi], 0..) |candidate, ni| {
            const on_event = candidate.event;
            if (!consumed[ni] and on_event.on() and on_event.channel() == ev.channel() and on_event.payload[0] == ev.payload[0]) {
                consumed[ni] = true;
                consumed[oi] = true;
                try result.notes.append(h.a, .{.on_id = ni, .off_id = oi, .start_tick = on_event.tick, .duration = ev.tick - on_event.tick, .channel_id = ev.channel(), .pitch = on_event.payload[0], .velocity = on_event.payload[1]});
                break;
            }
        }
    }
    for (result.ordered, 0..) |placed, j| {
        if (!consumed[j] and (placed.event.on() or placed.event.off())) {
            try result.unmatched.append(h.a, j);
            if (placed.event.on()) try result.pending.append(h.a, j);
        }
    }
    std.mem.sort(Note, result.notes.items, {}, struct {
        fn less(_: void, a: Note, b: Note) bool {
            if (a.start_tick != b.start_tick) return a.start_tick < b.start_tick;
            if (a.channel_id != b.channel_id) return a.channel_id < b.channel_id;
            if (a.pitch != b.pitch) return a.pitch < b.pitch;
            return a.on_id < b.on_id;
        }
    }.less);
    return result;
}
const Issue = struct { position: usize = 0, reason: Text = "" };
fn invalid(issue: *Issue, where: usize, reason: Text) error{Invalid} {
    issue.* = .{.position = where, .reason = reason};
    return error.Invalid;
}
const Parser = struct {
    h: Host,
    bytes: []const u8,
    issue: *Issue,
    position: usize = 0,
    limit: usize = 0,
    event_start: usize = 0,
    fn chunk(p: *Parser, at: usize, ident: Text) !usize {
        if (p.bytes.len - at < 8) return invalid(p.issue, at, "truncated chunk");
        if (!eq(p.bytes[at .. at + 4], ident)) return invalid(p.issue, at, "bad chunk id");
        const size = ix(bigEndian(p.bytes[at + 4 .. at + 8]));
        if (at + 8 + size > p.bytes.len) return invalid(p.issue, at, "truncated chunk");
        return size;
    }
    fn readByte(p: *Parser) !u8 {
        if (p.position >= p.limit) return invalid(p.issue, p.event_start, "truncated event");
        const result = p.bytes[p.position];
        p.position += 1;
        return result;
    }
    fn readVlq(p: *Parser) !I {
        const at = p.position;
        var result: I = 0;
        for (0..4) |_| {
            const value = try p.readByte();
            result = result * 128 + value % 128;
            if (value < 128) return result;
        }
        return invalid(p.issue, at, "variable-length value too long");
    }
    fn parse(p: *Parser) !Song {
        if (try p.chunk(0, "MThd") != 6) return invalid(p.issue, 4, "bad header length");
        const format_value = bigEndian(p.bytes[8..10]);
        const track_count = bigEndian(p.bytes[10..12]);
        const division_value = bigEndian(p.bytes[12..14]);
        if (format_value > 2) return invalid(p.issue, 8, "bad format");
        if (track_count == 0 or (format_value == 0 and track_count != 1)) return invalid(p.issue, 10, "bad track count");
        if (division_value >= 32768) return invalid(p.issue, 12, "smpte timing not supported");
        if (division_value == 0) return invalid(p.issue, 12, "bad division");
        var result: Song = .{.format = format_value, .division = division_value};
        p.position = 14;
        for (0..ix(track_count)) |_| {
            if (p.position == p.bytes.len) return invalid(p.issue, p.position, "missing track");
            const size = try p.chunk(p.position, "MTrk");
            p.position += 8;
            p.limit = p.position + size;
            var track_value: Track = .empty;
            var tick_value: I = 0;
            var running_status: ?u16 = null;
            while (p.position < p.limit) {
                if (track_value.items.len > 0 and track_value.items[track_value.items.len - 1].code == 303) return invalid(p.issue, p.position, "event after end of track");
                p.event_start = p.position;
                tick_value += try p.readVlq();
                if (p.position >= p.limit) return invalid(p.issue, p.event_start, "truncated event");
                const status_at = p.position;
                var code_value: u16 = p.bytes[p.position];
                if (code_value < 128) code_value = running_status orelse return invalid(p.issue, p.position, "data byte without running status")
                else p.position += 1;
                var payload_value: []u8 = undefined;
                if (code_value <= 239) {
                    running_status = code_value;
                    const count_bytes: usize = if (code_value / 16 == 12 or code_value / 16 == 13) 1 else 2;
                    payload_value = try p.h.a.alloc(u8, count_bytes);
                    for (payload_value) |*value| {
                        const data_at = p.position;
                        value.* = try p.readByte();
                        if (value.* >= 128) return invalid(p.issue, data_at, "bad data byte");
                    }
                } else if (code_value == 240 or code_value == 247 or code_value == 255) {
                    running_status = null;
                    if (code_value == 255) code_value = 256 + @as(u16, try p.readByte());
                    const count_bytes = ix(try p.readVlq());
                    if (p.position + count_bytes > p.limit) return invalid(p.issue, p.event_start, "truncated event");
                    payload_value = try p.h.a.dupe(u8, p.bytes[p.position .. p.position + count_bytes]);
                    p.position += count_bytes;
                    if (code_value >= 256) {
                        const tag = code_value - 256;
                        const expected: ?usize = switch (tag) { 0, 89 => 2, 32 => 1, 47 => 0, 81 => 3, 84 => 5, 88 => 4, else => null };
                        if (expected) |count_bytes_expected| if (payload_value.len != count_bytes_expected) return invalid(p.issue, status_at, "bad meta length");
                        const sf: I = if (tag == 89 and payload_value[0] >= 128) @as(I, payload_value[0]) - 256 else if (tag == 89) payload_value[0] else 0;
                        const valid = switch (tag) {
                            81 => bigEndian(payload_value) > 0,
                            32 => payload_value[0] <= 15,
                            88 => payload_value[0] > 0 and payload_value[1] <= 6,
                            89 => sf >= -7 and sf <= 7 and payload_value[1] <= 1,
                            else => true,
                        };
                        if (!valid) return invalid(p.issue, status_at, "bad meta data");
                    }
                } else return invalid(p.issue, status_at, "unknown status byte");
                try track_value.append(p.h.a, .{.tick = tick_value, .code = code_value, .payload = payload_value});
            }
            if (track_value.items.len == 0 or track_value.items[track_value.items.len - 1].code != 303) return invalid(p.issue, p.limit, "missing end of track");
            try result.tracks.append(p.h.a, track_value);
        }
        if (p.position < p.bytes.len) return invalid(p.issue, p.position, "extra data");
        return result;
    }
};
fn splitWords(h: Host, line: Text) ![]Text {
    var words: std.ArrayList(Text) = .empty;
    var it = std.mem.splitScalar(u8, line, ' ');
    while (it.next()) |word| try words.append(h.a, word);
    return words.toOwnedSlice(h.a);
}
const TextReader = struct {
    h: Host,
    issue: *Issue,
    row: usize = 1,
    fn bad(r: TextReader, reason: Text) error{Invalid} { return invalid(r.issue, r.row, reason); }
    fn bounded(r: TextReader, word: Text, low: I, high: I) !I {
        const value = number(word);
        if (value < low or value > high) return r.bad("bad value");
        return value;
    }
    fn unhex(r: TextReader, text: Text) !I { return std.fmt.parseInt(I, text, 16) catch return r.bad("bad value"); }
    fn noteNumber(r: TextReader, text: Text) !I {
        for (0..128) |p| if (eq(try noteName(r.h, @intCast(p)), text)) return @intCast(p);
        return r.bad("bad value");
    }
    fn event(r: TextReader, line: Text) !Event {
        const words = try splitWords(r.h, line);
        const name = words[2];
        var code_value: ?u16 = null;
        for (channels, 0..) |candidate, j| if (eq(candidate, name)) { code_value = @intCast(128 + j * 16); };
        for (0..256) |tag| if (!eq(name, "META") and eq(name, kindName(@intCast(256 + tag)))) { code_value = @intCast(256 + tag); };
        if (eq(name, "META")) code_value = 512;
        if (eq(name, "SYSEX")) code_value = 240;
        if (eq(name, "SYSEX_ESCAPE")) code_value = 247;
        var code = code_value orelse return r.bad("unknown event type");
        const fields = words[3..];
        var payload: std.ArrayList(u8) = .empty;
        if (code < 240) {
            const family = code / 16;
            const expected: usize = if (family >= 12) 2 else 3;
            if (fields.len != expected) return r.bad("bad value");
            code += @intCast((try r.bounded(fields[0], 1, 16)) - 1);
            if (family <= 10) {
                try payload.append(r.h.a, byte(try r.noteNumber(fields[1])));
                try payload.append(r.h.a, byte(try r.bounded(fields[2], 0, 127)));
            } else if (family == 14) {
                const bend = (try r.bounded(fields[1], -8192, 8191)) + 8192;
                try payload.appendSlice(r.h.a, &.{byte(@mod(bend, 128)), byte(@divTrunc(bend, 128))});
            } else for (fields[1..]) |word| { try payload.append(r.h.a, byte(try r.bounded(word, 0, 127))); };
        } else if (code >= 257 and code <= 263) {
            // The original suffix preserves consecutive spaces within the quoted field.
            const prefix_len = words[0].len + words[1].len + words[2].len + 3;
            const quoted = if (line.len >= prefix_len) line[prefix_len..] else "";
            if (quoted.len < 2 or quoted[0] != '"' or quoted[quoted.len - 1] != '"' or std.mem.indexOfScalar(u8, quoted[1 .. quoted.len - 1], '"') != null) return r.bad("bad value");
            try payload.appendSlice(r.h.a, quoted[1 .. quoted.len - 1]);
        } else switch (code) {
            303 => if (fields.len != 0) { return r.bad("bad value"); },
            256, 337, 288 => {
                if (fields.len != 1) return r.bad("bad value");
                const value = try r.bounded(fields[0], if (code == 256) 0 else 1, if (code == 256) 65535 else if (code == 337) 16777215 else 16);
                if (code == 288) try payload.append(r.h.a, byte(value - 1)) else try putBig(&payload, r.h.a, value, if (code == 256) 2 else 3);
            },
            340 => {
                if (fields.len != 5) return r.bad("bad value");
                for (fields) |word| try payload.append(r.h.a, byte(try r.bounded(word, 0, 255)));
            },
            344 => {
                if (fields.len != 3) return r.bad("bad value");
                var signature = std.mem.splitScalar(u8, fields[0], '/');
                const nn = try r.bounded(signature.next().?, 1, 255);
                const dd = number(signature.next().?);
                var exponent: ?u8 = null;
                for (0..7) |j| if (dd == @as(I, 1) << @as(u6, @intCast(j))) { exponent = @intCast(j); };
                const e = exponent orelse return r.bad("bad value");
                try payload.appendSlice(r.h.a, &.{byte(nn), e, byte(try r.bounded(fields[1], 0, 255)), byte(try r.bounded(fields[2], 0, 255))});
            },
            345 => {
                if (fields.len != 2) return r.bad("bad value");
                var found = false;
                for (keys, 0..) |table, mi| for (table, 0..) |key, j| {
                    if (eq(fields[0], key) and eq(fields[1], if (mi == 0) "major" else "minor")) {
                        const sf = @as(I, @intCast(j)) - 7;
                        try payload.appendSlice(r.h.a, &.{byte(if (sf < 0) sf + 256 else sf), @intCast(mi)});
                        found = true;
                    }
                };
                if (!found) return r.bad("bad value");
            },
            else => {
                var beginning: usize = 0;
                if (code == 512) {
                    if (fields.len < 2 or fields[0].len != 2) return r.bad("bad value");
                    const tag = try r.unhex(fields[0]);
                    for (fields[0]) |c| if (!std.ascii.isDigit(c) and (c < 'A' or c > 'F')) return r.bad("bad value");
                    if (knownMeta(@intCast(tag))) return r.bad("bad value");
                    code = 256 + @as(u16, @intCast(tag));
                    beginning = 1;
                }
                if (fields.len <= beginning) return r.bad("bad value");
                const size = ix(try r.bounded(fields[beginning], 0, 1000000));
                if (fields.len != beginning + @as(usize, if (size == 0) 1 else 2)) return r.bad("bad value");
                if (size > 0) {
                    const hex_data = fields[beginning + 1];
                    if (hex_data.len != 2 * size) return r.bad("bad value");
                    for (hex_data) |c| if (!std.ascii.isDigit(c) and (c < 'A' or c > 'F')) return r.bad("bad value");
                    for (0..size) |j| try payload.append(r.h.a, byte(try r.unhex(hex_data[2 * j .. 2 * j + 2])));
                }
            },
        }
        return .{.tick = number(words[0]), .code = code, .payload = try payload.toOwnedSlice(r.h.a)};
    }
    fn parse(r: *TextReader, lines: []const Text) !Song {
        const header = try splitWords(r.h, lines[0]);
        if (header.len != 4 or !eq(header[0], "HEADER")) return r.bad("bad header");
        const f = number(header[1]);
        const t = number(header[2]);
        const d = number(header[3]);
        if (f < 0 or f > 2 or t < 1 or t > 65535 or d < 1 or d > 32767 or (f == 0 and t != 1)) return r.bad("bad header");
        var result: Song = .{.format = f, .division = d};
        try result.tracks.append(r.h.a, .empty);
        var current: usize = 0;
        for (lines[1..], 1..) |line, j| {
            r.row = j + 1;
            const ev = try r.event(line);
            const words = try splitWords(r.h, line);
            const track_id = ix(number(words[1]));
            const events = result.tracks.items[current].items;
            const ended = events.len > 0 and events[events.len - 1].code == 303;
            if (track_id >= ix(t)) return r.bad("bad track");
            if (track_id < current) return r.bad("out of order");
            if (track_id > current and (!ended or track_id > current + 1)) return r.bad("missing end of track");
            if (track_id == current and ended) return r.bad("event after end of track");
            if (track_id == current and events.len > 0 and ev.tick < events[events.len - 1].tick) return r.bad("out of order");
            if (track_id > current) { current += 1; try result.tracks.append(r.h.a, .empty); }
            try result.tracks.items[current].append(r.h.a, ev);
        }
        r.row = lines.len + 1;
        const final = result.tracks.items[current].items;
        if (current + 1 < ix(t) or final.len == 0 or final[final.len - 1].code != 303) return r.bad("missing end of track");
        return result;
    }
};
fn encodeSong(h: Host, song: Song, running: bool, zero_off: bool) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(h.a, "MThd");
    try putBig(&result, h.a, 6, 4);
    try putBig(&result, h.a, song.format, 2);
    try putBig(&result, h.a, @intCast(song.tracks.items.len), 2);
    try putBig(&result, h.a, song.division, 2);
    for (song.tracks.items) |track_value| {
        var bytes: std.ArrayList(u8) = .empty;
        var previous: I = 0;
        var status: ?u16 = null;
        for (track_value.items) |ev| {
            try putVlq(&bytes, h.a, ev.tick - previous);
            previous = ev.tick;
            var code = ev.code;
            const rewrite = zero_off and code / 16 == 8;
            if (rewrite) code += 16;
            if (code < 240) {
                if (!running or status != code) try bytes.append(h.a, @intCast(code));
                if (rewrite) try bytes.appendSlice(h.a, &.{ev.payload[0], 0}) else try bytes.appendSlice(h.a, ev.payload);
                status = code;
            } else {
                status = null;
                if (code >= 256) try bytes.appendSlice(h.a, &.{255, @intCast(code - 256)}) else try bytes.append(h.a, @intCast(code));
                try putVlq(&bytes, h.a, @intCast(ev.payload.len));
                try bytes.appendSlice(h.a, ev.payload);
            }
        }
        try result.appendSlice(h.a, "MTrk");
        try putBig(&result, h.a, @intCast(bytes.items.len), 4);
        try result.appendSlice(h.a, bytes.items);
    }
    return result.toOwnedSlice(h.a);
}
const NamedSong = struct { name: Text, song: Song };
const Codec = struct {
    h: Host,
    songs: std.ArrayList(NamedSong) = .empty,
    running: bool = true,
    zero_off: bool = false,
    fn lookup(s: *const Codec, wanted: Text) ?usize {
        for (s.songs.items, 0..) |named, j| if (eq(named.name, wanted)) return j;
        return null;
    }
    fn store(s: *Codec, wanted: Text, value: Song) !void {
        if (s.lookup(wanted)) |at| s.songs.items[at].song = value else try s.songs.append(s.h.a, .{.name = wanted, .song = value});
    }
    fn command(s: *Codec, words: []const Text, data_lines: []const Text) !void {
        const op = words[0];
        const commands = [_]Text{"HEX", "TEXT", "DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL", "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT", "COPY", "LIST", "RUNNING", "NOTEOFF"};
        var known = false;
        for (commands) |candidate| known = known or eq(candidate, op);
        if (!known) return s.h.line("error: unknown command", .{});
        if (eq(op, "HEX") or eq(op, "TEXT")) {
            var issue: Issue = .{};
            var parsed: Song = undefined;
            if (eq(op, "TEXT")) {
                var reader: TextReader = .{.h = s.h, .issue = &issue};
                parsed = reader.parse(data_lines) catch |err| {
                    if (err == error.Invalid) return s.h.line("error: line {d}: {s}", .{issue.position, issue.reason});
                    return err;
                };
            } else {
                var bytes: std.ArrayList(u8) = .empty;
                for (data_lines) |line| {
                    var it = std.mem.splitScalar(u8, line, ' ');
                    while (it.next()) |word| try bytes.append(s.h.a, std.fmt.parseInt(u8, word, 16) catch unreachable);
                }
                var parser_value: Parser = .{.h = s.h, .bytes = bytes.items, .issue = &issue};
                parsed = parser_value.parse() catch |err| {
                    if (err == error.Invalid) return s.h.line("error: byte {d}: {s}", .{issue.position, issue.reason});
                    return err;
                };
            }
            try s.store(words[1], parsed);
            return s.h.line("loaded {s} {s}", .{words[1], try parsed.description(s.h)});
        }
        if (eq(op, "LIST")) {
            const listed = try s.h.a.dupe(NamedSong, s.songs.items);
            std.mem.sort(NamedSong, listed, {}, struct { fn less(_: void, a: NamedSong, b: NamedSong) bool { return std.mem.lessThan(u8, a.name, b.name); } }.less);
            if (listed.len == 0) return s.h.line("no songs", .{});
            for (listed) |named| try s.h.line("{s} {s}", .{named.name, try named.song.description(s.h)});
            return;
        }
        if (eq(op, "RUNNING") or eq(op, "NOTEOFF")) {
            if (eq(op, "RUNNING")) {
                if (!eq(words[1], "ON") and !eq(words[1], "OFF")) return s.h.line("error: bad argument", .{});
                s.running = eq(words[1], "ON");
                return s.h.line("running {s}", .{if (s.running) @as(Text, "on") else "off"});
            }
            if (!eq(words[1], "ZERO") and !eq(words[1], "KEEP")) return s.h.line("error: bad argument", .{});
            s.zero_off = eq(words[1], "ZERO");
            return s.h.line("noteoff {s}", .{if (s.zero_off) @as(Text, "zero") else "keep"});
        }
        const at = s.lookup(words[1]) orelse return s.h.line("error: no song {s}", .{words[1]});
        var song = try s.songs.items[at].song.clone(s.h);
        var arguments: std.ArrayList(I) = .empty;
        if (!eq(op, "COPY")) for (words[2..]) |word| { try arguments.append(s.h.a, number(word)); };
        const args = arguments.items;
        var valid = true;
        if (eq(op, "TRANSPOSE")) valid = args[0] >= -127 and args[0] <= 127 and (args.len == 1 or (args[1] >= 1 and args[1] <= 16))
        else if (eq(op, "QUANTIZE")) valid = args[0] >= 1 and args[0] <= 1000000 and args[1] >= 0 and args[1] <= 100
        else if (eq(op, "VELOCITY")) valid = args[0] >= 0 and args[0] <= 1000 and args[1] >= -127 and args[1] <= 127
        else if (eq(op, "TEMPO")) valid = args[0] >= 1 and args[0] <= 1000 and args[1] >= 1 and args[1] <= 1000
        else if (eq(op, "FILTER")) {
            for (args) |item| valid = valid and item >= 1 and item <= 16;
        } else if (eq(op, "ROLL")) {
            valid = args[0] >= 0 and args[0] <= 10000000 and args[1] >= 1 and args[1] <= 10000000 and args[2] >= 1 and args[2] <= 10000000 and args[1] > args[0];
            if (valid) valid = @divTrunc(args[1] - args[0] + args[2] - 1, args[2]) <= 64;
        }
        if (!valid) return s.h.line("error: bad argument", .{});
        if ((eq(op, "TIMING") or eq(op, "STATS")) and song.format == 2) return s.h.line("error: format 2 not supported", .{});
        if (eq(op, "COPY")) {
            try s.store(words[2], song);
            return s.h.line("copied {s} to {s}", .{words[1], words[2]});
        }
        if (eq(op, "DECODE")) {
            try s.h.line("HEADER {d} {d} {d}", .{song.format, song.tracks.items.len, song.division});
            for (song.tracks.items, 0..) |track_value, ti| for (track_value.items) |ev| { try s.h.line("{s}", .{try ev.textLine(s.h, ti)}); };
            return;
        }
        if (eq(op, "ENCODE")) {
            const bytes = try encodeSong(s.h, song, s.running, s.zero_off);
            var j: usize = 0;
            while (j < bytes.len) : (j += 16) {
                try s.h.out.print("{X:0>4}:", .{j});
                for (bytes[j..@min(j + 16, bytes.len)]) |value| try s.h.out.print(" {X:0>2}", .{value});
                try s.h.out.writeByte('\n');
            }
            return s.h.line("{d} bytes", .{bytes.len});
        }
        if (eq(op, "TIMING")) {
            const ordered = try song.globalOrder(s.h);
            for (ordered) |placed| {
                const ev = placed.event;
                try s.h.line("{d} {d} {s} {s} {s}", .{ev.tick, placed.track_id, kindName(ev.code), try song.clockText(s.h, ev.tick, ordered), try song.barText(s.h, ev.tick, ordered)});
            }
            const endpoint = song.length();
            return s.h.line("end {d} {s} {s}", .{endpoint, try song.clockText(s.h, endpoint, ordered), try song.barText(s.h, endpoint, ordered)});
        }
        const pairs = try pairNotes(song, s.h);
        if (eq(op, "NOTES")) {
            try s.h.line("notes {d} unmatched {d}", .{pairs.notes.items.len, pairs.unmatched.items.len});
            for (pairs.notes.items) |note| try s.h.line("{d} {d} {d} {s} {d}", .{note.start_tick, note.duration, note.channel_id, try noteName(s.h, note.pitch), note.velocity});
            for (pairs.unmatched.items) |j| {
                const placed = pairs.ordered[j];
                const ev = placed.event;
                try s.h.line("unmatched {s} {d} {d} {d} {s}", .{if (ev.on()) @as(Text, "on") else "off", ev.tick, placed.track_id, ev.channel(), try noteName(s.h, ev.payload[0])});
            }
            return;
        }
        if (eq(op, "ROLL")) {
            const columns = ix(@divTrunc(args[1] - args[0] + args[2] - 1, args[2]));
            var any_cell = false;
            var pitch: I = 127;
            while (pitch >= 0) : (pitch -= 1) {
                const cells = try s.h.a.alloc(u8, columns);
                @memset(cells, '.');
                for (0..columns) |j| {
                    const low = args[0] + @as(I, @intCast(j)) * args[2];
                    for (pairs.notes.items) |note| {
                        if (note.pitch != pitch) continue;
                        if (low <= note.start_tick and note.start_tick < low + args[2]) cells[j] = '#'
                        else if (cells[j] != '#' and note.start_tick <= low and low < note.start_tick + note.duration) cells[j] = '=';
                    }
                }
                if (std.mem.indexOfNone(u8, cells, ".") != null) {
                    any_cell = true;
                    const label = try noteName(s.h, pitch);
                    try s.h.out.writeAll(label);
                    try s.h.out.splatByteAll(' ', 5 - label.len);
                    try s.h.line("{s}", .{cells});
                }
            }
            if (!any_cell) try s.h.line("empty", .{});
            return;
        }
        if (eq(op, "STATS")) {
            try s.h.line("{s}", .{try song.description(s.h)});
            try s.h.line("notes {d} unmatched {d}", .{pairs.notes.items.len, pairs.unmatched.items.len});
            var lowest: I = 128;
            var highest: I = -1;
            for (1..17) |ch| {
                var count_notes: usize = 0;
                var low: I = 128;
                var high: I = -1;
                for (pairs.notes.items) |note| if (note.channel_id == @as(I, @intCast(ch))) {
                    count_notes += 1;
                    low = @min(low, note.pitch);
                    high = @max(high, note.pitch);
                };
                if (count_notes > 0) {
                    try s.h.line("channel {d} notes {d} range {s} {s}", .{ch, count_notes, try noteName(s.h, low), try noteName(s.h, high)});
                    lowest = @min(lowest, low);
                    highest = @max(highest, high);
                }
            }
            if (highest < 0) try s.h.line("range none", .{}) else try s.h.line("range {s} {s}", .{try noteName(s.h, lowest), try noteName(s.h, highest)});
            const endpoint = song.length();
            try s.h.line("length {d} ticks {s} ms", .{endpoint, try song.clockText(s.h, endpoint, pairs.ordered)});
            var peak: usize = 0;
            var peak_tick: I = 0;
            for (pairs.notes.items) |candidate| {
                var active: usize = 0;
                for (pairs.notes.items) |note| if (note.start_tick <= candidate.start_tick and candidate.start_tick < note.start_tick + note.duration) { active += 1; };
                if (active > peak) { peak = active; peak_tick = candidate.start_tick; }
            }
            if (peak == 0) return s.h.line("polyphony 0", .{});
            return s.h.line("polyphony {d} at {d}", .{peak, peak_tick});
        }
        if (eq(op, "TRANSPOSE") or eq(op, "FILTER")) {
            var changed: usize = 0;
            var dropped: usize = 0;
            var dropped_lines: std.ArrayList(Text) = .empty;
            for (song.tracks.items, 0..) |*track_value, ti| {
                var kept: Track = .empty;
                for (track_value.items) |original| {
                    var ev = original;
                    var remove = false;
                    if (eq(op, "FILTER") and ev.isChannel()) {
                        remove = true;
                        for (args) |ch| if (ev.channel() == ch) { remove = false; };
                    } else if (eq(op, "TRANSPOSE") and ev.code / 16 >= 8 and ev.code / 16 <= 10 and (args.len == 1 or ev.channel() == args[1])) {
                        const pitch = @as(I, ev.payload[0]) + args[0];
                        if (pitch < 0 or pitch > 127) {
                            remove = true;
                            try dropped_lines.append(s.h.a, try s.h.text("dropped {d} {d} {s} {d} {s}", .{ev.tick, ti, kindName(ev.code), ev.channel(), try noteName(s.h, ev.payload[0])}));
                        } else { ev.payload[0] = byte(pitch); changed += 1; }
                    }
                    if (remove) dropped += 1 else try kept.append(s.h.a, ev);
                }
                track_value.* = kept;
            }
            if (eq(op, "FILTER")) try s.h.line("removed {d}", .{dropped}) else {
                try s.h.line("transposed {d} dropped {d}", .{changed, dropped});
                for (dropped_lines.items) |line| try s.h.line("{s}", .{line});
            }
        } else if (eq(op, "VELOCITY")) {
            var changed: usize = 0;
            var clamped: usize = 0;
            for (song.tracks.items) |track_value| for (track_value.items) |*ev| {
                if (ev.on()) {
                    const value = @divTrunc(@as(I, ev.payload[1]) * args[0] + 50, 100) + args[1];
                    if (value < 1 or value > 127) clamped += 1;
                    ev.payload[1] = byte(@min(127, @max(1, value)));
                    changed += 1;
                }
            };
            try s.h.line("velocity {d} clamped {d}", .{changed, clamped});
        } else if (eq(op, "TEMPO")) {
            var at_zero = false;
            var changed: usize = 0;
            for (song.tracks.items) |track_value| for (track_value.items) |*ev| {
                if (ev.code == 337) {
                    const value = @divTrunc(2 * bigEndian(ev.payload) * args[1] + args[0], 2 * args[0]);
                    if (value < 1 or value > 16777215) return s.h.line("error: tempo out of range", .{});
                    ev.payload = try bigBytes(s.h, value, 3);
                    at_zero = at_zero or ev.tick == 0;
                    changed += 1;
                }
            };
            const inserted_value = @divTrunc(2 * 500000 * args[1] + args[0], 2 * args[0]);
            if (!at_zero and (inserted_value < 1 or inserted_value > 16777215)) return s.h.line("error: tempo out of range", .{});
            try s.h.line("scaled {d}", .{changed});
            if (!at_zero) {
                const ev: Event = .{.tick = 0, .code = 337, .payload = try bigBytes(s.h, inserted_value, 3)};
                try song.tracks.items[0].insert(s.h.a, 0, ev);
                try s.h.line("inserted {s}", .{try ev.textLine(s.h, 0)});
            }
        } else if (eq(op, "QUANTIZE")) {
            var on_ids: std.ArrayList(usize) = .empty;
            var off_ids: std.ArrayList(?usize) = .empty;
            for (pairs.notes.items) |note| {
                try on_ids.append(s.h.a, note.on_id);
                try off_ids.append(s.h.a, note.off_id);
            }
            for (pairs.pending.items) |j| { try on_ids.append(s.h.a, j); try off_ids.append(s.h.a, null); }
            var moved: usize = 0;
            for (on_ids.items, off_ids.items) |on_id, off_id| {
                const placed = pairs.ordered[on_id];
                const t = placed.event.tick;
                const grid = args[0];
                const low = @divTrunc(t, grid) * grid;
                const target = if (t - low <= low + grid - t) low else low + grid;
                const delta = @divFloor(2 * (target - t) * args[1] + 100, 200);
                song.tracks.items[placed.track_id].items[placed.event_id].tick += delta;
                if (off_id) |j| {
                    const off_event = pairs.ordered[j];
                    song.tracks.items[off_event.track_id].items[off_event.event_id].tick += delta;
                }
                if (delta != 0) moved += 1;
            }
            for (song.tracks.items) |*track_value| {
                var end_event = track_value.items[track_value.items.len - 1];
                const ordinary = track_value.items[0 .. track_value.items.len - 1];
                // Stable insertion preserves prior order at equal ticks.
                var j: usize = 1;
                while (j < ordinary.len) : (j += 1) {
                    var k = j;
                    while (k > 0 and ordinary[k].tick < ordinary[k - 1].tick) : (k -= 1) std.mem.swap(Event, &ordinary[k], &ordinary[k - 1]);
                }
                if (ordinary.len > 0) end_event.tick = @max(end_event.tick, ordinary[ordinary.len - 1].tick);
                track_value.items[track_value.items.len - 1] = end_event;
            }
            try s.h.line("quantized {d} moved {d}", .{on_ids.items.len, moved});
        } else if (eq(op, "MERGE")) {
            if (song.format != 1) return s.h.line("error: not format 1", .{});
            const original_count = song.tracks.items.len;
            const endpoint = song.length();
            var merged: Track = .empty;
            for (try song.globalOrder(s.h)) |placed| if (placed.event.code != 303) { try merged.append(s.h.a, placed.event); };
            try merged.append(s.h.a, .{.tick = endpoint, .code = 303});
            song.tracks = .empty;
            try song.tracks.append(s.h.a, merged);
            song.format = 0;
            try s.h.line("merged {d} tracks events {d}", .{original_count, song.count()});
        } else if (eq(op, "SPLIT")) {
            if (song.format != 0) return s.h.line("error: not format 0", .{});
            const endpoint = song.length();
            var tracks_new: std.ArrayList(Track) = .empty;
            try tracks_new.append(s.h.a, .empty);
            var mapping: [16]?usize = @splat(null);
            for (0..16) |ch| for (song.tracks.items[0].items) |ev| {
                if (ev.isChannel() and ev.code % 16 == ch and mapping[ch] == null) {
                    mapping[ch] = tracks_new.items.len;
                    try tracks_new.append(s.h.a, .empty);
                }
            };
            for (song.tracks.items[0].items) |ev| {
                if (ev.code != 303) {
                    const dest: usize = if (ev.isChannel()) mapping[ev.code % 16].? else 0;
                    try tracks_new.items[dest].append(s.h.a, ev);
                }
            }
            for (tracks_new.items) |*track_value| try track_value.append(s.h.a, .{.tick = endpoint, .code = 303});
            song.tracks = tracks_new;
            song.format = 1;
            try s.h.line("split tracks {d} events {d}", .{song.tracks.items.len, song.count()});
        }
        s.songs.items[at].song = song;
    }
};
fn readLine(r: *std.Io.Reader, a: std.mem.Allocator) !?Text {
    var b: std.Io.Writer.Allocating = .init(a);
    defer b.deinit();
    _ = try r.streamDelimiterEnding(&b.writer, '\n');
    if (r.bufferedLen() == 0 and b.written().len == 0) return null;
    if (r.bufferedLen() > 0) r.toss(1);
    return b.toOwnedSlice();
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var codec: Codec = .{.h = .{.a = a, .out = &output.interface}};
    const count = number(std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"));
    for (0..ix(count)) |_| {
        const line = std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r");
        const words = try splitWords(codec.h, line);
        var data_lines: std.ArrayList(Text) = .empty;
        if (eq(words[0], "HEX") or eq(words[0], "TEXT")) {
            for (0..ix(number(words[2]))) |_| try data_lines.append(a, std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"));
        }
        try codec.command(words, data_lines.items);
    }
    try output.interface.flush();
}
