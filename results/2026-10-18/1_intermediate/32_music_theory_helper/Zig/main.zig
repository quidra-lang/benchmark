const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Command = enum {
    MIDI, NOTE, FREQ, TUNING, PITCH, INTERVAL, INVERT, TRANSPOSE, SCALE,
    CHORD, VOICE, IDENTIFY, MELODY, ENHARMONIC, KEYSIG, RELATIVE, CIRCLE,
    DIATONIC, PROGRESSION, ANALYZE, FINDKEY, DEGREE, SPELL, KEYDIST,
};
const letters = "CDEFGAB";
const naturals = [_]i32{ 0, 2, 4, 5, 7, 9, 11 };
const accidentals = [_][]const u8{ "bb", "b", "", "#", "x" };
const sharp_names = [_][]const u8{ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
const flat_names = [_][]const u8{ "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" };
const romans = [_][]const u8{ "I", "II", "III", "IV", "V", "VI", "VII" };
const lower_romans = [_][]const u8{ "i", "ii", "iii", "iv", "v", "vi", "vii" };

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn digit(c: u8) bool { return c >= '0' and c <= '9'; }
fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!digit(c)) return false;
    return true;
}
fn integer(text: []const u8) i32 { return std.fmt.parseInt(i32, text, 10) catch unreachable; }
fn absolute(value: i32) i32 { return if (value < 0) -value else value; }
fn bit(pitch_class: i32) u16 { return @as(u16, 1) << @as(u4, @intCast(pitch_class)); }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }

const Pitch = struct {
    letter: usize,
    alteration: i32,
    fn natural(pitch: Pitch) i32 { return naturals[pitch.letter]; }
    fn class(pitch: Pitch) i32 { return @mod(pitch.natural() + pitch.alteration, 12); }
    fn same(a: Pitch, b: Pitch) bool { return a.letter == b.letter and a.alteration == b.alteration; }
    pub fn format(pitch: Pitch, out: *Writer) Writer.Error!void {
        try out.print("{c}{s}", .{ letters[pitch.letter], accidentals[@intCast(pitch.alteration + 2)] });
    }
};
const Note = struct {
    pitch: Pitch,
    octave: i32,
    fn midi(note: Note) i32 { return 12 * (note.octave + 1) + note.pitch.natural() + note.pitch.alteration; }
    fn position(note: Note) i32 { return 7 * note.octave + @as(i32, @intCast(note.pitch.letter)); }
    fn valid(note: Note) bool { return note.octave >= -1 and note.octave <= 9 and note.midi() >= 0 and note.midi() <= 127; }
    pub fn format(note: Note, out: *Writer) Writer.Error!void { try out.print("{f}{d}", .{ note.pitch, note.octave }); }
};
const IntervalQuality = enum { P, M, m, A, d, AA, dd };
const Interval = struct {
    quality: IntervalQuality,
    number: i32,
    fn distance(interval: Interval) i32 { return interval.number - 1; }
    fn perfect(interval: Interval) bool { return switch (@mod(interval.distance(), 7)) { 0, 3, 4 => true, else => false }; }
    fn semitones(interval: Interval) i32 {
        const difference: i32 = switch (interval.quality) {
            .dd => if (interval.perfect()) -2 else -3,
            .d => if (interval.perfect()) -1 else -2,
            .m => -1, .A => 1, .AA => 2, .P, .M => 0,
        };
        return 12 * @divTrunc(interval.distance(), 7) + naturals[@intCast(@mod(interval.distance(), 7))] + difference;
    }
    fn simple(interval: Interval) Interval {
        var result = interval;
        while (result.number > 8) result.number -= 7;
        return result;
    }
    fn consonance(interval: Interval) []const u8 {
        const small = interval.simple();
        if (small.quality == .P and (small.number == 1 or small.number == 5 or small.number == 8)) return "perfect";
        if ((small.quality == .m or small.quality == .M) and (small.number == 3 or small.number == 6)) return "imperfect";
        return "dissonant";
    }
    pub fn format(interval: Interval, out: *Writer) Writer.Error!void { try out.print("{s}{d}", .{ @tagName(interval.quality), interval.number }); }
};
fn rawInterval(text: []const u8) ?Interval {
    var start: usize = 0;
    while (start < text.len and !digit(text[start])) start += 1;
    const quality = std.meta.stringToEnum(IntervalQuality, text[0..start]) orelse return null;
    const number = text[start..];
    if (number.len == 0 or number.len > 2 or number[0] == '0' or !digits(number)) return null;
    const result: Interval = .{ .quality = quality, .number = integer(number) };
    if (result.perfect()) {
        if (quality == .M or quality == .m) return null;
    } else if (quality == .P) return null;
    if (result.number == 1 and (quality == .d or quality == .dd)) return null;
    return result;
}
const Pattern = struct {
    items: [7]Interval = [_]Interval{.{ .quality = .P, .number = 1 }} ** 7,
    len: usize = 0,
    fn list(pattern: *const Pattern) []const Interval { return pattern.items[0..pattern.len]; }
};
fn makePattern(comptime text: []const u8) Pattern {
    @setEvalBranchQuota(20000);
    var result: Pattern = .{};
    var words = std.mem.tokenizeScalar(u8, text, ' ');
    while (words.next()) |word| {
        result.items[result.len] = rawInterval(word).?;
        result.len += 1;
    }
    return result;
}
const ScaleName = enum {
    major, natural_minor, harmonic_minor, melodic_minor, ionian, dorian,
    phrygian, lydian, mixolydian, aeolian, locrian, major_pentatonic,
    minor_pentatonic, blues, whole_tone,
    fn pattern(name: ScaleName) *const Pattern { return &scale_patterns[@intFromEnum(name)]; }
};
const scale_patterns = [_]Pattern{
    makePattern("P1 M2 M3 P4 P5 M6 M7"), makePattern("P1 M2 m3 P4 P5 m6 m7"),
    makePattern("P1 M2 m3 P4 P5 m6 M7"), makePattern("P1 M2 m3 P4 P5 M6 M7"),
    makePattern("P1 M2 M3 P4 P5 M6 M7"), makePattern("P1 M2 m3 P4 P5 M6 m7"),
    makePattern("P1 m2 m3 P4 P5 m6 m7"), makePattern("P1 M2 M3 A4 P5 M6 M7"),
    makePattern("P1 M2 M3 P4 P5 M6 m7"), makePattern("P1 M2 m3 P4 P5 m6 m7"),
    makePattern("P1 m2 m3 P4 d5 m6 m7"), makePattern("P1 M2 M3 P5 M6"),
    makePattern("P1 m3 P4 P5 m7"), makePattern("P1 m3 P4 A4 P5 m7"),
    makePattern("P1 M2 M3 A4 A5 A6"),
};
const QualityName = enum {
    maj, min, dim, aug, sus2, sus4, @"6", m6, @"7", maj7, m7, mMaj7, m7b5, dim7, @"9", add9,
    fn data(name: QualityName) *const Quality { return &quality_table[@intFromEnum(name)]; }
};
const Quality = struct {
    pattern: Pattern,
    suffix: []const u8,
    numeral: []const u8,
    fn lower(quality: Quality) bool { return quality.numeral[0] == 'i'; }
};
const quality_table = [_]Quality{
    .{ .pattern = makePattern("P1 M3 P5"), .suffix = "", .numeral = "I" },
    .{ .pattern = makePattern("P1 m3 P5"), .suffix = "m", .numeral = "i" },
    .{ .pattern = makePattern("P1 m3 d5"), .suffix = "dim", .numeral = "io" },
    .{ .pattern = makePattern("P1 M3 A5"), .suffix = "aug", .numeral = "I+" },
    .{ .pattern = makePattern("P1 M2 P5"), .suffix = "sus2", .numeral = "Isus2" },
    .{ .pattern = makePattern("P1 P4 P5"), .suffix = "sus4", .numeral = "Isus4" },
    .{ .pattern = makePattern("P1 M3 P5 M6"), .suffix = "6", .numeral = "I6" },
    .{ .pattern = makePattern("P1 m3 P5 M6"), .suffix = "m6", .numeral = "i6" },
    .{ .pattern = makePattern("P1 M3 P5 m7"), .suffix = "7", .numeral = "I7" },
    .{ .pattern = makePattern("P1 M3 P5 M7"), .suffix = "maj7", .numeral = "Imaj7" },
    .{ .pattern = makePattern("P1 m3 P5 m7"), .suffix = "m7", .numeral = "i7" },
    .{ .pattern = makePattern("P1 m3 P5 M7"), .suffix = "mMaj7", .numeral = "imaj7" },
    .{ .pattern = makePattern("P1 m3 d5 m7"), .suffix = "m7b5", .numeral = "ih7" },
    .{ .pattern = makePattern("P1 m3 d5 d7"), .suffix = "dim7", .numeral = "io7" },
    .{ .pattern = makePattern("P1 M3 P5 m7 M9"), .suffix = "9", .numeral = "I9" },
    .{ .pattern = makePattern("P1 M3 P5 M9"), .suffix = "add9", .numeral = "Iadd9" },
};
const Mode = enum {
    major, minor, ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian,
    fn offset(mode: Mode) i32 { return ([_]i32{ 0, -3, 0, -2, -4, 1, -1, -3, -5 })[@intFromEnum(mode)]; }
    fn scale(mode: Mode) ScaleName {
        return ([_]ScaleName{ .major, .natural_minor, .ionian, .dorian, .phrygian, .lydian, .mixolydian, .aeolian, .locrian })[@intFromEnum(mode)];
    }
};
const Key = struct {
    tonic: Pitch,
    mode: Mode,
    fn fifths(key: Key) i32 { return ([_]i32{ 0, 2, 4, -1, 1, 3, 5 })[key.tonic.letter] + 7 * key.tonic.alteration + key.mode.offset(); }
    pub fn format(key: Key, out: *Writer) Writer.Error!void { try out.print("{f} {s}", .{ key.tonic, @tagName(key.mode) }); }
};
const Numeral = struct { degree: usize, alteration: i32, quality: QualityName };
const Chord = struct {
    root: Pitch,
    quality: QualityName,
    pub fn format(chord: Chord, out: *Writer) Writer.Error!void { try out.print("{f}{s}", .{ chord.root, chord.quality.data().suffix }); }
};
const Roman = struct {
    degree: usize,
    quality: QualityName,
    pub fn format(value: Roman, out: *Writer) Writer.Error!void {
        const quality = value.quality.data();
        try out.print("{s}{s}", .{ (if (quality.lower()) lower_romans else romans)[value.degree], quality.numeral[1..] });
    }
};
const Degree = struct {
    index: usize,
    alteration: i32,
    fn prefix(value: Degree, out: *Writer) Writer.Error!void {
        var i: i32 = 0;
        while (i < absolute(value.alteration)) : (i += 1) try out.writeByte(if (value.alteration < 0) 'b' else '#');
    }
    pub fn format(value: Degree, out: *Writer) Writer.Error!void { try value.prefix(out); try out.print("{d}", .{value.index + 1}); }
};
const Motion = struct { interval: Interval, down: bool, semitones: i32 };
const Frequency = struct {
    cents: i32,
    pub fn format(value: Frequency, out: *Writer) Writer.Error!void { try out.print("{d}.{d:0>2}", .{ @divTrunc(value.cents, 100), @mod(value.cents, 100) }); }
};
const Signed = struct {
    value: i32,
    positive_zero: bool = false,
    pub fn format(value: Signed, out: *Writer) Writer.Error!void {
        if (value.value > 0 or (value.value == 0 and value.positive_zero)) try out.writeByte('+');
        try out.print("{d}", .{value.value});
    }
};
const Pitches = struct {
    items: [7]Pitch = undefined,
    len: usize = 0,
    fn list(pitches: *const Pitches) []const Pitch { return pitches.items[0..pitches.len]; }
    fn mask(pitches: *const Pitches) u16 {
        var result: u16 = 0;
        for (pitches.list()) |pitch| result |= bit(pitch.class());
        return result;
    }
};
const PitchPrefix = struct { pitch: Pitch, len: usize };
fn pitchPrefix(text: []const u8) ?PitchPrefix {
    if (text.len == 0) return null;
    const letter = std.mem.findScalar(u8, letters, text[0]) orelse return null;
    var len: usize = 1;
    var alteration: i32 = 0;
    if (std.mem.startsWith(u8, text[1..], "bb")) {
        len = 3;
        alteration = -2;
    } else if (text.len > 1) {
        switch (text[1]) {
            'b' => { len = 2; alteration = -1; },
            '#' => { len = 2; alteration = 1; },
            'x' => { len = 2; alteration = 2; },
            else => {},
        }
    }
    return .{ .pitch = .{ .letter = letter, .alteration = alteration }, .len = len };
}
fn rawPitch(text: []const u8) ?Pitch {
    const prefix = pitchPrefix(text) orelse return null;
    return if (prefix.len == text.len) prefix.pitch else null;
}
fn rawNote(text: []const u8) ?Note {
    const prefix = pitchPrefix(text) orelse return null;
    const tail = text[prefix.len..];
    const octave: i32 = if (equal(tail, "-1")) -1 else if (tail.len == 1 and digit(tail[0])) tail[0] - '0' else return null;
    const note: Note = .{ .pitch = prefix.pitch, .octave = octave };
    return if (note.valid()) note else null;
}
fn fromMidi(pitch: Pitch, midi: i32) Note { return .{ .pitch = pitch, .octave = @divExact(midi - pitch.natural() - pitch.alteration, 12) - 1 }; }
fn standardNote(midi: i32, flat: bool) Note {
    return .{ .pitch = rawPitch((if (flat) flat_names else sharp_names)[@intCast(@mod(midi, 12))]).?, .octave = @divFloor(midi, 12) - 1 };
}
fn fifthsPitch(fifths: i32) Pitch {
    const letter = std.mem.findScalar(u8, letters, "FCGDAEB"[@intCast(@mod(fifths + 1, 7))]).?;
    return .{ .letter = letter, .alteration = @divFloor(fifths + 1, 7) };
}
fn keyAt(fifths: i32, mode: Mode) Key { return .{ .tonic = fifthsPitch(fifths - mode.offset()), .mode = mode }; }
fn chordMask(root: Note, quality: QualityName) u16 {
    var result: u16 = 0;
    for (quality.data().pattern.list()) |interval| result |= bit(@mod(root.midi() + interval.semitones(), 12));
    return result;
}
fn cadence(numerals: []const Numeral) []const u8 {
    if (numerals.len < 2) return "none";
    const a = numerals[numerals.len - 2];
    const b = numerals[numerals.len - 1];
    if (a.alteration == 0 and b.alteration == 0) {
        if (a.degree == 4 and b.degree == 0) return "authentic";
        if (a.degree == 3 and b.degree == 0) return "plagal";
        if (a.degree == 4 and b.degree == 5) return "deceptive";
    }
    return if (b.alteration == 0 and b.degree == 4) "half" else "none";
}
fn arity(command: Command) struct { min: usize, max: usize } {
    return switch (command) {
        .MIDI, .NOTE, .FREQ, .TUNING, .PITCH, .INVERT, .ENHARMONIC, .CIRCLE => .{ .min = 1, .max = 1 },
        .INTERVAL, .SCALE, .KEYSIG, .RELATIVE, .DIATONIC => .{ .min = 2, .max = 2 },
        .TRANSPOSE, .DEGREE, .SPELL => .{ .min = 3, .max = 3 },
        .KEYDIST => .{ .min = 4, .max = 4 },
        .CHORD, .VOICE => .{ .min = 2, .max = 3 },
        .IDENTIFY, .MELODY => .{ .min = 2, .max = 15 },
        .PROGRESSION, .ANALYZE => .{ .min = 3, .max = 15 },
        .FINDKEY => .{ .min = 1, .max = 15 },
    };
}
const IndexedNote = struct {
    note: Note,
    index: usize,
    fn less(_: void, a: IndexedNote, b: IndexedNote) bool { return if (a.note.midi() != b.note.midi()) a.note.midi() < b.note.midi() else a.index < b.index; }
};

const Session = struct {
    gpa: Allocator,
    tuning: *i32,
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn pitch(session: *Session, text: []const u8) Error!Pitch { return rawPitch(text) orelse session.fail("BAD PITCH {s}", .{text}); }
    fn note(session: *Session, text: []const u8) Error!Note { return rawNote(text) orelse session.fail("BAD NOTE {s}", .{text}); }
    fn interval(session: *Session, text: []const u8) Error!Interval { return rawInterval(text) orelse session.fail("BAD INTERVAL {s}", .{text}); }
    fn number(session: *Session, text: []const u8) Error!i32 {
        if (!digits(text) or (text.len > 1 and text[0] == '0')) return session.fail("BAD NUMBER {s}", .{text});
        const value = std.fmt.parseInt(i32, text, 10) catch return session.fail("BAD NUMBER {s}", .{text});
        if (value > 127) return session.fail("BAD NUMBER {s}", .{text});
        return value;
    }
    fn frequency(session: *Session, text: []const u8, tuning: bool) Error!i32 {
        const separator = std.mem.findScalar(u8, text, '.');
        const first = if (separator) |i| text[0..i] else text;
        const tail = if (separator) |i| text[i + 1 ..] else "";
        if (first.len > 5 or !digits(first) or (separator != null and (tail.len > 2 or !digits(tail))))
            return session.fail("BAD FREQUENCY {s}", .{text});
        var value = integer(first) * 100;
        if (tail.len > 0) value += integer(tail) * @as(i32, if (tail.len == 1) 10 else 1);
        if (if (tuning) value < 40000 or value > 48000 else value == 0) return session.fail("BAD FREQUENCY {s}", .{text});
        return value;
    }
    fn quality(session: *Session, text: []const u8) Error!QualityName { return std.meta.stringToEnum(QualityName, text) orelse session.fail("BAD QUALITY {s}", .{text}); }
    fn mode(session: *Session, text: []const u8) Error!Mode { return std.meta.stringToEnum(Mode, text) orelse session.fail("BAD MODE {s}", .{text}); }
    fn scaleName(session: *Session, text: []const u8) Error!ScaleName { return std.meta.stringToEnum(ScaleName, text) orelse session.fail("BAD SCALE {s}", .{text}); }
    fn key(session: *Session, tonic: []const u8, mode_text: []const u8) Error!Key {
        const root = try session.pitch(tonic);
        const mode_value = try session.mode(mode_text);
        const result: Key = .{ .tonic = root, .mode = mode_value };
        if (result.fifths() < -7 or result.fifths() > 7) return session.fail("THEORETICAL KEY", .{});
        return result;
    }
    fn inversion(session: *Session, text: []const u8, quality_value: QualityName) Error!usize {
        if (text.len != 1 or !digit(text[0]) or text[0] - '0' >= quality_value.data().pattern.len)
            return session.fail("BAD INVERSION {s}", .{text});
        return text[0] - '0';
    }
    fn numeral(session: *Session, text: []const u8) Error!Numeral {
        const start: usize = if (text[0] == 'b' or text[0] == '#') 1 else 0;
        const alteration: i32 = if (start == 0) 0 else if (text[0] == 'b') -1 else 1;
        var end = start;
        while (end < text.len and std.mem.findScalar(u8, "IViv", text[end]) != null) end += 1;
        const roman = text[start..end];
        for (romans, 0..) |name, index| {
            const lower = equal(roman, lower_romans[index]);
            if (!lower and !equal(roman, name)) continue;
            for (quality_table, 0..) |entry, q| {
                if (entry.lower() == lower and equal(entry.numeral[1..], text[end..]))
                    return .{ .degree = index, .alteration = alteration, .quality = @enumFromInt(q) };
            }
        }
        return session.fail("BAD NUMERAL {s}", .{text});
    }
    fn symbol(session: *Session, text: []const u8) Error!Chord {
        const prefix = pitchPrefix(text) orelse return session.fail("BAD SYMBOL {s}", .{text});
        for (quality_table, 0..) |entry, index| {
            if (equal(entry.suffix, text[prefix.len..])) return .{ .root = prefix.pitch, .quality = @enumFromInt(index) };
        }
        return session.fail("BAD SYMBOL {s}", .{text});
    }
    fn raise(session: *Session, root: Pitch, interval_value: Interval) Error!Pitch {
        const position = @as(i32, @intCast(root.letter)) + interval_value.distance();
        const target: usize = @intCast(@mod(position, 7));
        const alteration = root.natural() + root.alteration + interval_value.semitones() - naturals[target] - 12 * @divFloor(position, 7);
        if (alteration < -2 or alteration > 2) return session.fail("CANNOT SPELL", .{});
        return .{ .letter = target, .alteration = alteration };
    }
    fn build(session: *Session, root: Pitch, pattern: *const Pattern) Error!Pitches {
        var result: Pitches = .{ .len = pattern.len };
        for (pattern.list(), 0..) |interval_value, i| result.items[i] = try session.raise(root, interval_value);
        return result;
    }
    fn scale(session: *Session, key_value: Key) Error!Pitches { return session.build(key_value.tonic, key_value.mode.scale().pattern()); }
    fn label(session: *Session, key_value: Key, pitch_value: Pitch) Error!Degree {
        const index: usize = @intCast(@mod(@as(i32, @intCast(pitch_value.letter)) - @as(i32, @intCast(key_value.tonic.letter)), 7));
        const pitches = try session.scale(key_value);
        return .{ .index = index, .alteration = pitch_value.alteration - pitches.items[index].alteration };
    }
    fn between(session: *Session, first: Note, second: Note) Error!Motion {
        var distance = second.position() - first.position();
        var semitones = second.midi() - first.midi();
        const down = distance < 0 or (distance == 0 and semitones < 0);
        if (down) { distance = -distance; semitones = -semitones; }
        const difference = semitones - (12 * @divTrunc(distance, 7) + naturals[@intCast(@mod(distance, 7))]);
        const perfect = switch (@mod(distance, 7)) { 0, 3, 4 => true, else => false };
        const quality_value: ?IntervalQuality = if (perfect) switch (difference) {
            -2 => .dd, -1 => .d, 0 => .P, 1 => .A, 2 => .AA, else => null,
        } else switch (difference) {
            -3 => .dd, -2 => .d, -1 => .m, 0 => .M, 1 => .A, 2 => .AA, else => null,
        };
        return .{ .interval = .{ .quality = quality_value orelse return session.fail("UNNAMEABLE INTERVAL", .{}), .number = distance + 1 }, .down = down, .semitones = semitones };
    }
    fn writePitches(session: *Session, pitches: []const Pitch) Writer.Error!void {
        for (pitches) |pitch_value| try session.out.print(" {f}", .{pitch_value});
    }
    fn execute(session: *Session, text: []const u8) Error!void {
        var words: [16][]const u8 = undefined;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, text, ' ');
        while (tokens.next()) |word| { words[count] = word; count += 1; }
        const w = words[0..count];
        const command = std.meta.stringToEnum(Command, w[0]) orelse return session.fail("UNKNOWN COMMAND {s}", .{w[0]});
        const limits = arity(command);
        if (count - 1 < limits.min or count - 1 > limits.max) return session.fail("ARGUMENT COUNT", .{});
        const out = session.out;
        switch (command) {
            .MIDI => try line(out, "MIDI {s} {d}", .{ w[1], (try session.note(w[1])).midi() }),
            .NOTE => {
                const number_value = try session.number(w[1]);
                try line(out, "NOTE {d} {f} {f}", .{ number_value, standardNote(number_value, false), standardNote(number_value, true) });
            },
            .FREQ => {
                const input = try session.note(w[1]);
                const value = (@as(f64, @floatFromInt(session.tuning.*)) / 100.0) * @exp2(@as(f64, @floatFromInt(input.midi() - 69)) / 12.0);
                try line(out, "FREQ {s} {f}", .{ w[1], Frequency{ .cents = @intFromFloat(@floor(value * 100.0 + 0.5)) } });
            },
            .TUNING => {
                const value = try session.frequency(w[1], true);
                session.tuning.* = value;
                try line(out, "TUNING {f}", .{Frequency{ .cents = value }});
            },
            .PITCH => {
                const value = try session.frequency(w[1], false);
                const x = 69.0 + 12.0 * @log2(@as(f64, @floatFromInt(value)) / @as(f64, @floatFromInt(session.tuning.*)));
                const midi: i32 = @intFromFloat(@floor(x + 0.5));
                if (midi < 0 or midi > 127) return session.fail("OUT OF RANGE", .{});
                const cents: i32 = @intFromFloat(@floor(100.0 * (x - @as(f64, @floatFromInt(midi))) + 0.5));
                try line(out, "PITCH {f} {f} {f}", .{ Frequency{ .cents = value }, standardNote(midi, false), Signed{ .value = cents, .positive_zero = true } });
            },
            .INTERVAL => {
                const a = try session.note(w[1]);
                const b = try session.note(w[2]);
                const motion = try session.between(a, b);
                try line(out, "INTERVAL {s} {s} {f} {s} semitones={d} simple={f} class={s}", .{
                    w[1], w[2], motion.interval, if (motion.down) "down" else "up", motion.semitones, motion.interval.simple(), motion.interval.consonance(),
                });
            },
            .INVERT => {
                const original = try session.interval(w[1]);
                const simple = original.simple();
                const quality_value: IntervalQuality = switch (simple.quality) { .P => .P, .M => .m, .m => .M, .A => .d, .d => .A, .AA => .dd, .dd => .AA };
                const inverted: Interval = .{ .quality = quality_value, .number = 9 - simple.number };
                if (inverted.number == 1 and (quality_value == .d or quality_value == .dd)) return session.fail("CANNOT INVERT", .{});
                try line(out, "INVERT {s} {f} {f}", .{ w[1], simple, inverted });
            },
            .TRANSPOSE => {
                const input = try session.note(w[1]);
                const interval_value = try session.interval(w[2]);
                if (!equal(w[3], "UP") and !equal(w[3], "DOWN")) return session.fail("BAD DIRECTION {s}", .{w[3]});
                const sign: i32 = if (equal(w[3], "UP")) 1 else -1;
                const position = input.position() + sign * interval_value.distance();
                const midi = input.midi() + sign * interval_value.semitones();
                const letter: usize = @intCast(@mod(position, 7));
                const octave = @divFloor(position, 7);
                const alteration = midi - (12 * (octave + 1) + naturals[letter]);
                if (alteration < -2 or alteration > 2) return session.fail("CANNOT SPELL", .{});
                const result: Note = .{ .pitch = .{ .letter = letter, .alteration = alteration }, .octave = octave };
                if (!result.valid()) return session.fail("OUT OF RANGE", .{});
                try line(out, "TRANSPOSE {s} {s} {s} {f}", .{ w[1], w[2], w[3], result });
            },
            .SCALE => {
                const root = try session.pitch(w[1]);
                const name = try session.scaleName(w[2]);
                const pattern = name.pattern();
                const pitches = try session.build(root, pattern);
                try out.print("SCALE {s} {s}", .{ w[1], w[2] });
                try session.writePitches(pitches.list());
                try out.writeAll(" steps=");
                for (pattern.list(), 0..) |interval_value, i| {
                    if (i != 0) try out.writeByte(',');
                    const next: i32 = if (i + 1 == pattern.len) 12 else pattern.items[i + 1].semitones();
                    try out.print("{d}", .{next - interval_value.semitones()});
                }
                try out.writeByte('\n');
            },
            .CHORD, .VOICE => {
                var input: ?Note = null;
                const root = if (command == .VOICE) blk: {
                    input = try session.note(w[1]);
                    break :blk input.?.pitch;
                } else try session.pitch(w[1]);
                const quality_value = try session.quality(w[2]);
                const inversion_value = if (count == 4) try session.inversion(w[3], quality_value) else 0;
                const tones = try session.build(root, &quality_value.data().pattern);
                var reordered: Pitches = .{ .len = tones.len };
                for (0..tones.len) |i| reordered.items[i] = tones.items[(i + inversion_value) % tones.len];
                try out.print("{s} {f}", .{ w[0], Chord{ .root = root, .quality = quality_value } });
                if (inversion_value != 0) try out.print("/{f}", .{reordered.items[0]});
                if (command == .CHORD) {
                    try session.writePitches(reordered.list());
                } else {
                    var notes: [7]Note = undefined;
                    var previous = input.?.midi();
                    for (reordered.list(), 0..) |pitch_value, i| {
                        var midi = previous;
                        if (i != 0 or inversion_value != 0) {
                            midi += @mod(pitch_value.class() - previous, 12);
                            if (midi == previous) midi += 12;
                        }
                        notes[i] = fromMidi(pitch_value, midi);
                        if (!notes[i].valid()) return session.fail("OUT OF RANGE", .{});
                        previous = midi;
                    }
                    for (notes[0..tones.len]) |note_value| try out.print(" {f}", .{note_value});
                    try out.writeAll(" midi=");
                    for (notes[0..tones.len], 0..) |note_value, i| {
                        if (i != 0) try out.writeByte(',');
                        try out.print("{d}", .{note_value.midi()});
                    }
                }
                try out.writeByte('\n');
            },
            .IDENTIFY => {
                var ordered: [15]IndexedNote = undefined;
                var mask: u16 = 0;
                for (w[1..], 0..) |word, i| {
                    const note_value = try session.note(word);
                    ordered[i] = .{ .note = note_value, .index = i };
                    mask |= bit(note_value.pitch.class());
                }
                std.sort.heap(IndexedNote, ordered[0 .. count - 1], {}, IndexedNote.less);
                var candidates: [15]Note = undefined;
                var candidate_count: usize = 0;
                var seen: u16 = 0;
                for (ordered[0 .. count - 1]) |entry| {
                    const note_bit = bit(entry.note.pitch.class());
                    if ((seen & note_bit) != 0) continue;
                    seen |= note_bit;
                    candidates[candidate_count] = entry.note;
                    candidate_count += 1;
                }
                const bass = candidates[0];
                for (candidates[0..candidate_count]) |root| {
                    for (quality_table, 0..) |entry, q| {
                        const quality_value: QualityName = @enumFromInt(q);
                        if (chordMask(root, quality_value) != mask) continue;
                        var inversion_value: usize = 0;
                        for (entry.pattern.list(), 0..) |interval_value, i| {
                            if (@mod(root.midi() + interval_value.semitones(), 12) == bass.pitch.class()) { inversion_value = i; break; }
                        }
                        try out.print("IDENTIFY {f}", .{Chord{ .root = root.pitch, .quality = quality_value }});
                        if (inversion_value != 0) try out.print("/{f}", .{bass.pitch});
                        try line(out, " root={f} quality={s} inversion={d}", .{ root.pitch, @tagName(quality_value), inversion_value });
                        return;
                    }
                }
                try line(out, "IDENTIFY UNKNOWN", .{});
            },
            .MELODY => {
                var notes: [15]Note = undefined;
                for (w[1..], 0..) |word, i| notes[i] = try session.note(word);
                const values = notes[0 .. count - 1];
                var low = values[0];
                var high = values[0];
                for (values) |note_value| {
                    if (note_value.midi() < low.midi()) low = note_value;
                    if (note_value.midi() > high.midi()) high = note_value;
                }
                const range = (try session.between(low, high)).interval;
                var steps: [14]Motion = undefined;
                var leaps: usize = 0;
                for (1..values.len) |i| {
                    steps[i - 1] = try session.between(values[i - 1], values[i]);
                    if (absolute(values[i].midi() - values[i - 1].midi()) >= 3) leaps += 1;
                }
                try out.print("MELODY n={d} low={f} high={f} range={f} leaps={d} steps=", .{ values.len, low, high, range, leaps });
                for (steps[0 .. values.len - 1], 0..) |motion, i| {
                    if (i != 0) try out.writeByte(',');
                    try out.print("{c}{f}", .{ @as(u8, if (motion.down) '-' else '+'), motion.interval });
                }
                try out.writeByte('\n');
            },
            .ENHARMONIC => {
                const input = try session.note(w[1]);
                var notes: [7]Note = undefined;
                var len: usize = 0;
                for (0..7) |letter| {
                    var alteration: i32 = -2;
                    while (alteration <= 2) : (alteration += 1) {
                        const pitch_value: Pitch = .{ .letter = letter, .alteration = alteration };
                        if (pitch_value.class() != input.pitch.class()) continue;
                        const note_value = fromMidi(pitch_value, input.midi());
                        if (note_value.valid()) { notes[len] = note_value; len += 1; }
                    }
                }
                std.sort.heap(Note, notes[0..len], {}, struct {
                    fn less(_: void, a: Note, b: Note) bool { return a.position() < b.position(); }
                }.less);
                try out.print("ENHARMONIC {s}", .{w[1]});
                for (notes[0..len]) |note_value| try out.print(" {f}", .{note_value});
                try out.writeByte('\n');
            },
            .KEYSIG, .RELATIVE, .DIATONIC, .PROGRESSION, .ANALYZE, .DEGREE => {
                const key_value = try session.key(w[1], w[2]);
                if (command == .KEYSIG) {
                    const fifths = key_value.fifths();
                    if (fifths == 0) return line(out, "KEYSIG {f} none", .{key_value});
                    const names = if (fifths > 0) [_][]const u8{ "F#", "C#", "G#", "D#", "A#", "E#", "B#" }
                        else [_][]const u8{ "Bb", "Eb", "Ab", "Db", "Gb", "Cb", "Fb" };
                    try out.print("KEYSIG {f} {s}={d}", .{ key_value, if (fifths > 0) "sharps" else "flats", absolute(fifths) });
                    for (names[0..@intCast(absolute(fifths))]) |name| try out.print(" {s}", .{name});
                    try out.writeByte('\n');
                    return;
                }
                if (command == .RELATIVE) return line(out, "RELATIVE {f} major={f} minor={f}", .{ key_value, keyAt(key_value.fifths(), .major).tonic, keyAt(key_value.fifths(), .minor).tonic });
                if (command == .DEGREE) {
                    const pitch_value = try session.pitch(w[3]);
                    return line(out, "DEGREE {f} {s} {f}", .{ key_value, w[3], try session.label(key_value, pitch_value) });
                }
                if (command == .ANALYZE) {
                    var chords: [13]Chord = undefined;
                    for (w[3..], 0..) |word, i| chords[i] = try session.symbol(word);
                    try out.print("ANALYZE {f}", .{key_value});
                    for (chords[0 .. count - 3]) |chord| {
                        const degree = try session.label(key_value, chord.root);
                        try out.writeByte(' ');
                        try degree.prefix(out);
                        try out.print("{f}", .{Roman{ .degree = degree.index, .quality = chord.quality }});
                    }
                    try out.writeByte('\n');
                    return;
                }
                if (command == .PROGRESSION) {
                    var numerals: [13]Numeral = undefined;
                    for (w[3..], 0..) |word, i| numerals[i] = try session.numeral(word);
                    const key_scale = try session.scale(key_value);
                    try line(out, "PROGRESSION {f} {d}", .{ key_value, count - 3 });
                    for (numerals[0 .. count - 3], 0..) |numeral_value, i| {
                        const degree = key_scale.items[numeral_value.degree];
                        const root: Pitch = .{ .letter = degree.letter, .alteration = degree.alteration + numeral_value.alteration };
                        const tones = try session.build(root, &numeral_value.quality.data().pattern);
                        try out.print("{s} {f}", .{ w[i + 3], Chord{ .root = root, .quality = numeral_value.quality } });
                        try session.writePitches(tones.list());
                        try out.writeByte('\n');
                    }
                    try line(out, "CADENCE {s}", .{cadence(numerals[0 .. count - 3])});
                    return;
                }
                const key_scale = try session.scale(key_value);
                try line(out, "DIATONIC {f}", .{key_value});
                for (0..2) |kind| {
                    try out.writeAll(if (kind == 0) "TRIADS" else "SEVENTHS");
                    for (0..7) |i| {
                        const third = @mod(key_scale.items[(i + 2) % 7].class() - key_scale.items[i].class(), 12);
                        const fifth = @mod(key_scale.items[(i + 4) % 7].class() - key_scale.items[i].class(), 12);
                        const seventh = @mod(key_scale.items[(i + 6) % 7].class() - key_scale.items[i].class(), 12);
                        const quality_value: QualityName = if (kind == 0)
                            (if (third == 4) .maj else if (fifth == 7) .min else .dim)
                            else (if (third == 4) (if (seventh == 11) .maj7 else .@"7") else if (fifth == 7) .m7 else .m7b5);
                        try out.print(" {f}={f}", .{ Roman{ .degree = i, .quality = quality_value }, Chord{ .root = key_scale.items[i], .quality = quality_value } });
                    }
                    try out.writeByte('\n');
                }
            },
            .CIRCLE => {
                const mode_value = try session.mode(w[1]);
                try out.print("CIRCLE {s}", .{w[1]});
                var fifths: i32 = -7;
                while (fifths <= 7) : (fifths += 1) try out.print(" {f}", .{keyAt(fifths, mode_value).tonic});
                try out.writeByte('\n');
            },
            .FINDKEY => {
                var pitches: [15]Pitch = undefined;
                for (w[1..], 0..) |word, i| pitches[i] = try session.pitch(word);
                var keys: [30]Key = undefined;
                var len: usize = 0;
                var fifths: i32 = -7;
                while (fifths <= 7) : (fifths += 1) {
                    for ([_]Mode{ .major, .minor }) |mode_value| {
                        const key_value = keyAt(fifths, mode_value);
                        const key_scale = try session.scale(key_value);
                        var matches = true;
                        for (pitches[0 .. count - 1]) |pitch_value| {
                            var found = false;
                            for (key_scale.list()) |candidate| {
                                if (candidate.same(pitch_value)) { found = true; break; }
                            }
                            if (!found) { matches = false; break; }
                        }
                        if (matches) { keys[len] = key_value; len += 1; }
                    }
                }
                try out.print("FINDKEY {d}", .{len});
                for (keys[0..len], 0..) |key_value, i| try out.print("{s}{f}", .{ if (i == 0) " " else ", ", key_value });
                try out.writeByte('\n');
            },
            .SPELL => {
                const midi = try session.number(w[1]);
                const key_value = try session.key(w[2], w[3]);
                const key_scale = try session.scale(key_value);
                var pitch_value = standardNote(midi, key_value.fifths() < 0).pitch;
                for (key_scale.list()) |candidate| {
                    if (candidate.class() == @mod(midi, 12)) { pitch_value = candidate; break; }
                }
                const note_value = fromMidi(pitch_value, midi);
                if (!note_value.valid()) return session.fail("OUT OF RANGE", .{});
                try line(out, "SPELL {d} {f} {f} {f}", .{ midi, key_value, note_value, try session.label(key_value, pitch_value) });
            },
            .KEYDIST => {
                const a = try session.key(w[1], w[2]);
                const b = try session.key(w[3], w[4]);
                var difference = @mod(b.fifths() - a.fifths(), 12);
                if (difference > 6) difference -= 12;
                const first_scale = try session.scale(a);
                const second_scale = try session.scale(b);
                const first = first_scale.mask();
                const second = second_scale.mask();
                const same_tonic = a.tonic.class() == b.tonic.class();
                const relation: []const u8 = if (first == second) (if (same_tonic) "same" else "relative")
                    else if (same_tonic) "parallel" else if (absolute(difference) == 1) "close" else "distant";
                try line(out, "KEYDIST {f} {f} fifths={f} common={d} relation={s}", .{ a, b, Signed{ .value = difference }, @popCount(first & second), relation });
            },
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var header = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer header.deinit();
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var tuning: i32 = 44000;
    const count: usize = @intCast(integer(try readLine(header.allocator(), &input.interface)));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = gpa, .tuning = &tuning, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
