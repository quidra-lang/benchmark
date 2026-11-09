const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn hex(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 16) catch unreachable;
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &result, field);
    return result.items;
}
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
const pitch_names = [_][]const u8{ "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-" };
pub fn noteNumber(name: []const u8) i64 {
    for (pitch_names, 0..) |pitch, i| if (eq(pitch, name[0..2])) return 12 * @as(i64, name[2] - '0') + n(i);
    unreachable;
}
pub fn noteName(note: i64) []const u8 {
    return fmt("{s}{d}", .{ pitch_names[u(@mod(note, 12))], @divTrunc(note, 12) });
}
pub const Effect = struct { text: []const u8 = "...", name: []const u8 = "", argument: i64 = 0, x: i64 = 0, y: i64 = 0 };
pub const Cell = struct {
    note: i64 = -1,
    instrument: ?usize = null,
    volume: ?i64 = null,
    effect: Effect = .{},
    pub fn empty(self: Cell) bool {
        return self.note == -1 and self.instrument == null and self.volume == null and self.effect.name.len == 0;
    }
};
pub const Row = [4]Cell;
pub const Pattern = [64]Row;
pub const Wave = enum { pulse, triangle, saw, noise, table };
pub const Vibrato = struct { delay: i64, speed: i64, depth: i64 };
pub const Instrument = struct { number: usize, name: []const u8, wave: Wave = .pulse, mode: usize = 0,
     table: [32]i64 = @splat(0), attack: i64 = 0, decay: i64 = 0, sustain: i64 = 0, release: i64 = 0,
     vibrato: ?Vibrato = null, arpeggio: []i64 = &.{}, sweep: i64 = 0 };
pub const Song = struct { title: []const u8 = "", rate: i64 = 0, speed: usize = 0, tempo: i64 = 0,
     gain: i64 = 0, instruments: [256]?Instrument = @splat(null), patterns: [256]?*Pattern = @splat(null),
     order: []usize = &.{} };
pub const Params = struct { maximum: usize = 0, loops: usize = 0, fade: usize = 0, muted: [4]bool = @splat(false),
     start: usize = 0, length: usize = 0, width: usize = 0, height: usize = 0, scope: usize = 0, roll_start: usize = 0,
     roll_rows: usize = 0, preview_note: i64 = 0, preview_ticks: usize = 0, preview_release: usize = 0,
     traces: [64][64]bool = @splat(@splat(false)) };
fn effect(text: []const u8) Effect {
    var result: Effect = .{ .text = text };
    if (eq(text, "...")) return result;
    if (text[0] == 'E') {
        result.name = text[0..2];
        result.argument = hex(text[2..3]);
        result.x = result.argument;
    } else {
        result.name = text[0..1];
        result.argument = hex(text[1..3]);
        result.x = @divTrunc(result.argument, 16);
        result.y = @mod(result.argument, 16);
    }
    return result;
}
fn cell(text: []const u8) Cell {
    return .{ .note = if (eq(text[0..3], "...")) -1 else if (eq(text[0..3], "OFF")) -2 else noteNumber(text[0..3]),
         .instrument = if (eq(text[4..6], "..")) null else u(hex(text[4..6])), .volume = if (text[7] == '.') null else hex(text[7..8]),
         .effect = effect(text[9..12]) };
}
pub fn readSong(io: std.Io) !Song {
    var filtered: std.ArrayList([]const u8) = .empty;
    for (try readLines(io, "input/song.txt")) |line| if (line.len > 0 and line[0] != '#') append([]const u8, &filtered, line);
    const lines = filtered.items;
    var song: Song = .{ .title = lines[0][6..], .rate = number(split(lines[1], ' ')[1]), .speed = u(number(split(lines[2],
         ' ')[1])), .tempo = number(split(lines[3], ' ')[1]), .gain = number(split(lines[4], ' ')[1]) };
    var i: usize = 5;
    while (i < lines.len) {
        const header = split(lines[i], ' ');
        i += 1;
        if (eq(header[0], "ORDER")) {
            song.order = alloc(usize, header.len - 1);
            for (header[1..], song.order) |word, *value| value.* = u(hex(word));
            continue;
        }
        if (eq(header[0], "PATTERN")) {
            const storage = alloc(Pattern, 1);
            const pattern = &storage[0];
            for (pattern) |*row| for (row) |*value| {
                value.* = .{};
            };
            while (!eq(lines[i], "END")) : (i += 1) {
                const line = lines[i];
                const row = u(hex(line[0..2]));
                for (&pattern[row], 0..) |*value, k| value.* = cell(line[3 + 15 * k .. 3 + 15 * k + 12]);
            }
            i += 1;
            song.patterns[u(hex(header[1]))] = pattern;
            continue;
        }
        var instrument: Instrument = .{ .number = u(hex(header[1])), .name = header[2] };
        while (!eq(lines[i], "END")) : (i += 1) {
            const fields = split(lines[i], ' ');
            if (eq(fields[0], "WAVE")) {
                if (eq(fields[1], "PULSE")) {
                    instrument.wave = .pulse;
                    const duty = number(fields[2]);
                    instrument.mode = if (duty == 12) 0 else if (duty == 25) 1 else if (duty == 50) 2 else 3;
                } else if (eq(fields[1], "TRIANGLE")) instrument.wave = .triangle else if (eq(fields[1],
                     "SAW")) instrument.wave = .saw else if (eq(fields[1], "NOISE")) {
                    instrument.wave = .noise;
                    instrument.mode = if (eq(fields[2], "SHORT")) 1 else 0;
                } else {
                    instrument.wave = .table;
                    for (&instrument.table, 0..) |*value, j| value.* = hex(fields[2][j .. j + 1]);
                }
            } else if (eq(fields[0], "ENVELOPE")) {
                instrument.attack = number(fields[1]);
                instrument.decay = number(fields[2]);
                instrument.sustain = number(fields[3]);
                instrument.release = number(fields[4]);
            } else if (eq(fields[0], "VIBRATO")) instrument.vibrato = .{ .delay = number(fields[1]),
                 .speed = number(fields[2]), .depth = number(fields[3]) } else if (eq(fields[0], "ARPEGGIO")) {
                instrument.arpeggio = alloc(i64, fields.len - 1);
                for (fields[1..], instrument.arpeggio) |word, *value| value.* = number(word);
            } else instrument.sweep = number(fields[1]);
        }
        i += 1;
        song.instruments[instrument.number] = instrument;
    }
    return song;
}
pub fn readParams(io: std.Io) !Params {
    const lines = try readLines(io, "input/params.txt");
    var p: Params = .{};
    for (lines, 0..) |line, i| {
        const fields = split(line, ' ');
        switch (i) {
            0 => p.maximum = u(number(fields[1])),
            1 => p.loops = u(number(fields[1])),
            2 => p.fade = u(number(fields[1])),
            3 => for (&p.muted, fields[1..]) |*muted, word| {
                muted.* = eq(word, "1");
            },
            4 => {
                p.start = u(number(fields[1]));
                p.length = u(number(fields[2]));
                p.width = u(number(fields[3]));
                p.height = u(number(fields[4]));
                p.scope = u(number(fields[5]));
            },
            5 => {
                p.roll_start = u(number(fields[1]));
                p.roll_rows = u(number(fields[2]));
            },
            6 => {
                p.preview_note = noteNumber(fields[1]);
                p.preview_ticks = u(number(fields[2]));
                p.preview_release = u(number(fields[3]));
            },
            else => p.traces[u(hex(fields[1]))][u(hex(fields[2]))] = true,
        }
    }
    return p;
}
