const std = @import("std");
const scoring = @import("scoring.zig");
const substitution = @import("substitution.zig");
const transposition = @import("transposition.zig");
const playfair = @import("playfair.zig");
const analysis = @import("analysis.zig");
const Allocator = std.mem.Allocator;
const Command = enum { ENCRYPT, DECRYPT, BREAK, ANALYZE, COMPARE, IDENTIFY };
const Cipher = enum { caesar, affine, vigenere, autokey, playfair, railfence, columnar };
const Option = enum { TOP, MAXLEN, IOC, KASISKI, REFINE, MAXRAILS, KEYS };
const Key = substitution.Key;
const JobError = error{InvalidJob};
var permanent: Allocator = undefined;
var temporary: Allocator = undefined;

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn enumValue(comptime T: type, text: []const u8) ?T {
    inline for (@typeInfo(T).@"enum".field_names) |name| {
        if (eq(name, text)) return @field(T, name);
    }
    return null;
}

fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(temporary, pattern, args) catch @panic("allocation failed");
}

fn append(comptime T: type, list: *std.ArrayList(T), item: T) void {
    list.append(temporary, item) catch @panic("allocation failed");
}

fn copy(text: []const u8) []u8 {
    return temporary.dupe(u8, text) catch @panic("allocation failed");
}

fn join(parts: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(temporary, separator, parts) catch @panic("allocation failed");
}

fn words(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |part| append([]const u8, &result, part);
    return result.items;
}

fn lines(text: []const u8) []const []const u8 {
    const result = words(text, '\n');
    return result[0..result.len - 1];
}

const Text = struct {
    bytes: std.ArrayList(u8) = .empty,

    fn line(out: *Text, text: []const u8) void {
        out.bytes.appendSlice(permanent, text) catch @panic("allocation failed");
        out.bytes.append(permanent, '\n') catch @panic("allocation failed");
    }

    fn body(out: *Text, body_lines: []const []const u8) void {
        for (body_lines) |text| out.line(text);
    }
};

fn validName(text: []const u8) bool {
    if (text.len == 0 or text.len > 16) return false;
    for (text) |c| {
        if (!(c >= 'a' and c <= 'z') and !(c >= '0' and c <= '9') and c != '_') return false;
    }
    return true;
}

fn digits(text: []const u8, maximum_length: usize) ?usize {
    if (text.len == 0 or text.len > maximum_length) return null;
    var result: usize = 0;
    for (text) |c| {
        if (c < '0' or c > '9') return null;
        result = result * 10 + c - '0';
    }
    return result;
}

fn parseKey(cipher: Cipher, text: []const u8) ?Key {
    switch (cipher) {
        .caesar, .railfence => {
            const number = digits(text, 2) orelse return null;
            if (cipher == .caesar and number > 25) return null;
            if (cipher == .railfence and (number < 2 or number > 20)) return null;
            return .{ .b = @intCast(number) };
        },
        .affine => {
            const comma = std.mem.findScalar(u8, text, ',') orelse return null;
            const a = digits(text[0..comma], 2) orelse return null;
            const b = digits(text[comma + 1..], 2) orelse return null;
            const multiplier: i64 = @intCast(a);
            if (std.mem.findScalar(i64, &substitution.multipliers, multiplier) == null or b > 25) return null;
            return .{ .a = multiplier, .b = @intCast(b) };
        },
        .columnar => {
            if (text.len < 2 or text.len > 9) return null;
            for (text) |c| {
                if (!scoring.isLetter(c) and !(c >= '0' and c <= '9')) return null;
            }
            return .{ .word = scoring.uppercase(temporary, text) };
        },
        .vigenere, .autokey, .playfair => {
            const maximum: usize = if (cipher == .playfair) 25 else 20;
            if (text.len == 0 or text.len > maximum) return null;
            for (text) |c| {
                if (!scoring.isLetter(c)) return null;
            }
            const key = scoring.uppercase(temporary, text);
            if (cipher == .playfair) {
                for (key) |*c| c.* = playfair.normalize(c.*);
            }
            return .{ .word = key };
        },
    }
}

fn keyNotation(cipher: Cipher, key: Key) []const u8 {
    return switch (cipher) {
        .caesar, .railfence => fmt("{d}", .{key.b}),
        .affine => fmt("{d},{d}", .{ key.a, key.b }),
        else => key.word,
    };
}

fn isSubstitution(cipher: Cipher) bool {
    return switch (cipher) {
        .caesar, .affine, .vigenere, .autokey => true,
        else => false,
    };
}

fn transform(cipher: Cipher, key: Key, text: []const u8, decrypt: bool) []const u8 {
    return switch (cipher) {
        .caesar => substitution.transform(temporary, text, .caesar, key, decrypt),
        .affine => substitution.transform(temporary, text, .affine, key, decrypt),
        .vigenere => substitution.transform(temporary, text, .vigenere, key, decrypt),
        .autokey => substitution.transform(temporary, text, .autokey, key, decrypt),
        .railfence => transposition.railFence(temporary, text, @intCast(key.b), decrypt),
        .columnar => transposition.columnar(temporary, text, key.word, decrypt),
        .playfair => if (decrypt) playfair.decrypt(temporary, text, key.word) else playfair.encrypt(temporary, text, key.word),
    };
}

fn groupForm(text: []const u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    while (start < text.len) : (start += 50) {
        const end = @min(start + 50, text.len);
        var groups: std.ArrayList([]const u8) = .empty;
        var position = start;
        while (position < end) : (position += 5) append([]const u8, &groups, text[position..@min(position + 5, end)]);
        append([]const u8, &result, join(groups.items, " "));
    }
    return result.items;
}

fn solutionLines(cipher: Cipher, key: Key, message: Message, decrypt: bool) []const []const u8 {
    const result = transform(cipher, key, if (isSubstitution(cipher)) message.text else message.letters, decrypt);
    return if (isSubstitution(cipher)) words(result, '\n') else groupForm(result);
}

fn asSuffix(name: ?[]const u8) []const u8 {
    return if (name) |text| fmt(" as={s}", .{text}) else "";
}

fn numberList(numbers: anytype) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    for (numbers) |number| append([]const u8, &parts, fmt("{d}", .{number}));
    return join(parts.items, ",");
}

fn countList(counts: []const analysis.PairCount) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    for (counts[0..@min(10, counts.len)]) |entry| append([]const u8, &parts, fmt("{s}:{d}", .{ &entry.pair, entry.count }));
    return join(parts.items, " ");
}

fn distinctLetters(counts: [26]i64) usize {
    var total: usize = 0;
    for (counts) |count| {
        if (count > 0) total += 1;
    }
    return total;
}

const Options = struct {
    top: usize = 5,
    maxlen: usize = 10,
    ioc: i64 = 6000,
    kasiski: usize = 60,
    refine: usize = 5,
    maxrails: usize = 10,
    keys: ?[]const u8 = null,
};

fn defaults(cipher: Cipher) Options {
    return switch (cipher) {
        .autokey => .{ .maxlen = 8 },
        .columnar => .{ .maxlen = 6 },
        else => .{},
    };
}

fn optionAllowed(command: Command, cipher: ?Cipher, option: Option) bool {
    if (command == .ANALYZE) return option == .MAXLEN;
    if (command == .IDENTIFY) return option == .KEYS;
    if (option == .TOP) return true;
    return switch (cipher.?) {
        .caesar, .affine => false,
        .vigenere => option == .MAXLEN or option == .IOC or option == .KASISKI or option == .REFINE,
        .autokey, .columnar => option == .MAXLEN,
        .railfence => option == .MAXRAILS,
        .playfair => option == .KEYS,
    };
}

const Period = struct { length: usize, indices: []const i64, average: i64, kasiski: usize };
const Profile = struct { periods: []const Period, repeats: []const analysis.Repeat, gap_count: usize };

fn periodProfile(text: []const u8, maximum: usize) Profile {
    const repeats = analysis.repeatedTrigrams(temporary, text);
    var gap_count: usize = 0;
    for (repeats) |repeat| gap_count += repeat.gaps.len;
    var periods: std.ArrayList(Period) = .empty;
    for (1..maximum + 1) |length| {
        const indices = analysis.columnIndices(temporary, text, length);
        var total: i64 = 0;
        for (indices) |index| total += index;
        var kasiski: usize = 0;
        for (repeats) |repeat| {
            for (repeat.gaps) |gap| {
                if (gap % length == 0) kasiski += 1;
            }
        }
        append(Period, &periods, .{ .length = length, .indices = indices, .average = @divFloor(total, @as(i64, @intCast(length))), .kasiski = kasiski });
    }
    return .{ .periods = periods.items, .repeats = repeats, .gap_count = gap_count };
}

fn profileLines(out: *Text, profile: Profile) void {
    for (profile.periods) |period| out.line(fmt("L={d} ioc={d} kasiski={d} cols={s}", .{ period.length, period.average, period.kasiski, numberList(period.indices) }));
    out.line(fmt("kasiski repeats={d} spacings={d}", .{ profile.repeats.len, profile.gap_count }));
    for (profile.repeats) |repeat| out.line(fmt("{s} at={s} gaps={s} gcd={d}", .{ &repeat.trigram, numberList(repeat.positions), numberList(repeat.gaps), repeat.divisor }));
}

fn nextPermutation(key: []u8) bool {
    var end = key.len - 1;
    while (end > 0 and key[end - 1] >= key[end]) : (end -= 1) {}
    if (end == 0) return false;
    const pivot = end - 1;
    var successor = key.len - 1;
    while (key[successor] <= key[pivot]) : (successor -= 1) {}
    const old = key[pivot];
    key[pivot] = key[successor];
    key[successor] = old;
    var last = key.len - 1;
    while (end < last) {
        const first = key[end];
        key[end] = key[last];
        key[last] = first;
        end += 1;
        last -= 1;
    }
    return true;
}

const Candidate = struct { key: Key, plaintext: []const u8, score: i64, order: usize };
const BreakResult = struct {
    cipher: Cipher,
    candidates: []const Candidate,
    key: Key,
    score: i64,
    profile: ?Profile = null,
    length: usize = 0,
    method: []const u8 = "",
    passes: usize = 0,
    changes: usize = 0,
};

fn candidateLess(_: void, a: Candidate, b: Candidate) bool {
    return a.score > b.score or (a.score == b.score and a.order < b.order);
}

fn keyList(text: []const u8) []const []const u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    var position: usize = 0;
    while (position < text.len) {
        if (!scoring.isLetter(text[position])) {
            position += 1;
            continue;
        }
        const start = position;
        while (position < text.len and scoring.isLetter(text[position])) : (position += 1) {}
        const key = scoring.uppercase(temporary, text[start..position]);
        for (key) |*c| c.* = playfair.normalize(c.*);
        var duplicate = false;
        for (keys.items) |existing| {
            if (eq(key, existing)) duplicate = true;
        }
        if (!duplicate) append([]const u8, &keys, key);
    }
    return keys.items;
}

const Message = struct { text: []const u8, letters: []const u8 };

const Engine = struct {
    weights: scoring.Weights,
    messages: std.StringHashMapUnmanaged(Message) = .empty,
    results: Text = .{},
    candidates: Text = .{},
    reports: Text = .{},
    jobs: usize = 0,
    ok: [6]usize = @splat(0),
    errors: [6]usize = @splat(0),
    reason: []const u8 = "",

    fn fail(e: *Engine, comptime pattern: []const u8, args: anytype) JobError {
        e.reason = fmt(pattern, args);
        return error.InvalidJob;
    }

    fn store(e: *Engine, name: []const u8, body: []const []const u8) void {
        const text = std.mem.join(permanent, "\n", body) catch @panic("allocation failed");
        e.messages.put(permanent, name, .{ .text = text, .letters = scoring.letterString(permanent, text) }) catch @panic("allocation failed");
    }

    fn loadMessages(e: *Engine, text: []const u8) void {
        var name: ?[]const u8 = null;
        var body: std.ArrayList([]const u8) = .empty;
        for (lines(text)) |line| {
            if (name == null) {
                if (line.len == 0) continue;
                name = line[8..];
                body = .empty;
            } else if (eq(line, "END")) {
                e.store(name.?, body.items);
                name = null;
            } else append([]const u8, &body, line);
        }
    }

    fn message(e: *Engine, name: []const u8) JobError!Message {
        return e.messages.get(name) orelse return e.fail("unknown message {s}", .{name});
    }

    fn options(e: *Engine, command: Command, cipher: ?Cipher, input: []const []const u8) JobError!Options {
        var result: Options = if (command == .BREAK) defaults(cipher.?) else .{};
        var seen: u8 = 0;
        for (input) |word| {
            const equal = std.mem.findScalar(u8, word, '=') orelse return e.fail("bad option {s}", .{word});
            const option = enumValue(Option, word[0..equal]) orelse return e.fail("bad option {s}", .{word});
            const bit = @as(u8, 1) << @as(u3, @intCast(@intFromEnum(option)));
            if (!optionAllowed(command, cipher, option) or seen & bit != 0) return e.fail("bad option {s}", .{word});
            seen |= bit;
            const value = word[equal + 1..];
            if (option == .KEYS) {
                if (!validName(value)) return e.fail("bad option {s}", .{word});
                result.keys = value;
                continue;
            }
            const number = digits(value, 6) orelse return e.fail("bad option {s}", .{word});
            const bounds: [2]usize = switch (option) {
                .TOP => .{ 1, 20 },
                .MAXLEN => if (command == .BREAK and cipher.? == .autokey) .{ 1, 20 } else if (command == .BREAK and cipher.? == .columnar) .{ 2, 6 } else .{ 2, 20 },
                .IOC => .{ 1, 100000 },
                .KASISKI => .{ 1, 100 },
                .REFINE => .{ 0, 10 },
                .MAXRAILS => .{ 2, 20 },
                .KEYS => unreachable,
            };
            if (number < bounds[0] or number > bounds[1]) return e.fail("bad option {s}", .{word});
            switch (option) {
                .TOP => result.top = number,
                .MAXLEN => result.maxlen = number,
                .IOC => result.ioc = @intCast(number),
                .KASISKI => result.kasiski = number,
                .REFINE => result.refine = number,
                .MAXRAILS => result.maxrails = number,
                .KEYS => unreachable,
            }
        }
        if (command == .BREAK and cipher.? == .playfair and result.keys == null) return e.fail("missing option KEYS", .{});
        return result;
    }

    fn addCandidate(e: *Engine, list: *std.ArrayList(Candidate), cipher: Cipher, key: Key, text: []const u8) void {
        const plain = transform(cipher, key, text, true);
        const score = if (cipher == .caesar or cipher == .affine) e.weights.monogram(plain) else e.weights.bigram(plain);
        append(Candidate, list, .{ .key = key, .plaintext = plain, .score = score, .order = list.items.len });
    }

    fn columnKey(e: *Engine, cipher: Cipher, text: []const u8, length: usize) []const u8 {
        const key = temporary.alloc(u8, length) catch @panic("allocation failed");
        for (key, 0..) |*letter, column| {
            var best: i64 = -1;
            var chosen: usize = 0;
            for (0..26) |shift| {
                var previous: i64 = @intCast(shift);
                var total: i64 = 0;
                var position = column;
                while (position < text.len) : (position += length) {
                    const value: i64 = @intCast(scoring.value(text[position]));
                    const plain = @mod(value - previous, 26);
                    total += e.weights.monograms[@intCast(plain)];
                    if (cipher == .autokey) previous = plain;
                }
                if (total > best) {
                    best = total;
                    chosen = shift;
                }
            }
            letter.* = 'A' + @as(u8, @intCast(chosen));
        }
        return key;
    }

    fn vigenereScore(e: *Engine, text: []const u8, key: []const u8) i64 {
        var total: i64 = 0;
        var previous: usize = 0;
        for (text, 0..) |c, i| {
            const value: i64 = @intCast(scoring.value(c));
            const shift: i64 = @intCast(scoring.value(key[i % key.len]));
            const plain: usize = @intCast(@mod(value - shift, 26));
            if (i > 0) total += e.weights.bigrams[previous][plain];
            previous = plain;
        }
        return total;
    }

    fn refineVigenere(e: *Engine, result: *BreakResult, text: []const u8, candidates: []const Candidate, opts: Options) void {
        const profile = periodProfile(text, opts.maxlen);
        var kasiski_length: usize = 0;
        if (profile.gap_count > 0) {
            for (profile.periods[1..]) |period| {
                if (100 * period.kasiski >= opts.kasiski * profile.gap_count) kasiski_length = period.length;
            }
        }
        var length: usize = 0;
        var method: []const u8 = "maxioc";
        if (kasiski_length != 0 and profile.periods[kasiski_length - 1].average >= opts.ioc) {
            length = kasiski_length;
            method = "kasiski";
        } else {
            for (profile.periods) |period| {
                if (period.average >= opts.ioc) {
                    length = period.length;
                    method = "ioc";
                    break;
                }
            }
            if (length == 0) {
                length = 1;
                for (profile.periods[1..]) |period| {
                    if (period.average > profile.periods[length - 1].average) length = period.length;
                }
            }
        }
        const key = copy(candidates[length - 1].key.word);
        var reference = candidates[length - 1].score;
        var passes: usize = 0;
        var changes: usize = 0;
        while (passes < opts.refine) {
            passes += 1;
            var changed = false;
            for (0..length) |column| {
                const old = key[column];
                var best: i64 = -1;
                var chosen: u8 = 'A';
                for (scoring.alphabet) |letter| {
                    key[column] = letter;
                    const score = e.vigenereScore(text, key);
                    if (score > best) {
                        best = score;
                        chosen = letter;
                    }
                }
                key[column] = old;
                if (best > reference) {
                    key[column] = chosen;
                    reference = best;
                    changes += 1;
                    changed = true;
                }
            }
            if (!changed) break;
        }
        result.key = .{ .word = key };
        result.score = reference;
        result.profile = profile;
        result.length = length;
        result.method = method;
        result.passes = passes;
        result.changes = changes;
    }

    fn breakCipher(e: *Engine, cipher: Cipher, text: []const u8, opts: Options, keys: []const []const u8) BreakResult {
        var candidates: std.ArrayList(Candidate) = .empty;
        switch (cipher) {
            .caesar => for (0..26) |shift| e.addCandidate(&candidates, cipher, .{ .b = @intCast(shift) }, text),
            .affine => for (substitution.multipliers) |a| {
                for (0..26) |b| e.addCandidate(&candidates, cipher, .{ .a = a, .b = @intCast(b) }, text);
            },
            .railfence => for (2..opts.maxrails + 1) |rails| e.addCandidate(&candidates, cipher, .{ .b = @intCast(rails) }, text),
            .columnar => for (2..opts.maxlen + 1) |width| {
                const permutation = temporary.alloc(u8, width) catch @panic("allocation failed");
                for (permutation, 0..) |*c, i| c.* = '1' + @as(u8, @intCast(i));
                while (true) {
                    e.addCandidate(&candidates, cipher, .{ .word = copy(permutation) }, text);
                    if (!nextPermutation(permutation)) break;
                }
            },
            .playfair => for (keys) |key| e.addCandidate(&candidates, cipher, .{ .word = key }, text),
            .vigenere, .autokey => for (1..opts.maxlen + 1) |length| e.addCandidate(&candidates, cipher, .{ .word = e.columnKey(cipher, text, length) }, text),
        }
        var result: BreakResult = .{ .cipher = cipher, .candidates = candidates.items, .key = candidates.items[0].key, .score = candidates.items[0].score };
        if (cipher == .vigenere) e.refineVigenere(&result, text, candidates.items, opts);
        std.mem.sort(Candidate, candidates.items, {}, candidateLess);
        if (cipher != .vigenere) {
            result.key = candidates.items[0].key;
            result.score = candidates.items[0].score;
        }
        return result;
    }

    fn run(e: *Engine, line: []const u8) void {
        e.jobs += 1;
        const input = words(line, ' ');
        const command = enumValue(Command, input[0]) orelse {
            e.results.line(fmt("JOB {d} ERROR unknown command", .{e.jobs}));
            return;
        };
        e.execute(command, input) catch {
            e.errors[@intFromEnum(command)] += 1;
            e.results.line(fmt("JOB {d} ERROR {s}", .{ e.jobs, e.reason }));
            return;
        };
        e.ok[@intFromEnum(command)] += 1;
    }

    fn execute(e: *Engine, command: Command, input: []const []const u8) JobError!void {
        var tokens = input;
        var new_name: ?[]const u8 = null;
        const naming = command == .ENCRYPT or command == .DECRYPT or command == .BREAK;
        if (naming and tokens.len >= 5 and eq(tokens[tokens.len - 2], "AS")) {
            new_name = tokens[tokens.len - 1];
            if (!validName(new_name.?)) return e.fail("bad syntax", .{});
            tokens = tokens[0..tokens.len - 2];
        }
        const syntax = switch (command) {
            .ENCRYPT, .DECRYPT => tokens.len == 4,
            .BREAK => tokens.len >= 3,
            .ANALYZE, .IDENTIFY => tokens.len == 2 or tokens.len == 3,
            .COMPARE => tokens.len == 3,
        };
        if (!syntax) return e.fail("bad syntax", .{});
        const cipher: ?Cipher = if (naming) enumValue(Cipher, tokens[1]) orelse return e.fail("unknown cipher {s}", .{tokens[1]}) else null;
        const key: Key = if (command == .ENCRYPT or command == .DECRYPT) parseKey(cipher.?, tokens[2]) orelse return e.fail("bad key {s}", .{tokens[2]}) else .{};
        const opts = switch (command) {
            .BREAK => try e.options(command, cipher, tokens[3..]),
            .ANALYZE, .IDENTIFY => try e.options(command, cipher, tokens[2..]),
            else => Options{},
        };
        const source = switch (command) {
            .ENCRYPT, .DECRYPT => tokens[3],
            .BREAK => tokens[2],
            else => tokens[1],
        };
        const message_value = try e.message(source);
        var second: Message = .{ .text = "", .letters = "" };
        if (command == .COMPARE) second = try e.message(tokens[2]);
        if (opts.keys) |name| second = try e.message(name);
        if (new_name) |name| {
            if (e.messages.contains(name)) return e.fail("duplicate message {s}", .{name});
        }
        switch (command) {
            .ENCRYPT, .DECRYPT => try e.transformMessage(command, cipher.?, key, source, message_value, new_name),
            .BREAK => try e.breakMessage(cipher.?, source, message_value, opts, second, new_name),
            .ANALYZE => try e.analyze(source, message_value, opts),
            .COMPARE => e.compare(source, tokens[2], message_value, second),
            .IDENTIFY => try e.identify(source, message_value, opts, second),
        }
    }

    fn transformMessage(e: *Engine, command: Command, cipher: Cipher, key: Key, source: []const u8, message_value: Message, new_name: ?[]const u8) JobError!void {
        if (message_value.letters.len == 0) return e.fail("no letters", .{});
        if (command == .DECRYPT and cipher == .playfair and !playfair.validCiphertext(message_value.letters)) return e.fail("bad playfair text", .{});
        const body = solutionLines(cipher, key, message_value, command == .DECRYPT);
        var letter_count: usize = 0;
        for (body) |line| {
            for (line) |c| {
                if (scoring.isLetter(c)) letter_count += 1;
            }
        }
        e.results.line(fmt("JOB {d} {s} {s} key={s} source={s} letters={d} lines={d}{s}", .{ e.jobs, @tagName(command), @tagName(cipher), keyNotation(cipher, key), source, letter_count, body.len, asSuffix(new_name) }));
        e.results.body(body);
        if (new_name) |name| e.store(name, body);
    }

    fn breakMessage(e: *Engine, cipher: Cipher, source: []const u8, message_value: Message, opts: Options, key_message: Message, new_name: ?[]const u8) JobError!void {
        const text = message_value.letters;
        if (text.len < 40) return e.fail("text too short", .{});
        var keys: []const []const u8 = &.{};
        if (cipher == .playfair) {
            if (!playfair.validCiphertext(text)) return e.fail("bad playfair text", .{});
            keys = keyList(key_message.text);
            if (keys.len == 0) return e.fail("empty key list", .{});
        }
        const result = e.breakCipher(cipher, text, opts, keys);
        const body = solutionLines(cipher, result.key, message_value, true);
        e.results.line(fmt("JOB {d} BREAK {s} source={s} key={s} score={d} lines={d}{s}", .{ e.jobs, @tagName(cipher), source, keyNotation(cipher, result.key), result.score, body.len, asSuffix(new_name) }));
        e.results.body(body);
        if (new_name) |name| e.store(name, body);
        const ranked = result.candidates;
        const margin = if (ranked.len > 1) ranked[0].score - ranked[1].score else 0;
        e.candidates.line(fmt("JOB {d} BREAK {s} source={s} tried={d} margin={d}", .{ e.jobs, @tagName(cipher), source, ranked.len, margin }));
        for (ranked[0..@min(opts.top, ranked.len)], 1..) |candidate, rank| e.candidates.line(fmt("{d} {s} {d} {s}", .{ rank, keyNotation(cipher, candidate.key), candidate.score, candidate.plaintext[0..40] }));
        if (cipher == .vigenere) {
            e.reports.line(fmt("JOB {d} BREAK vigenere source={s}", .{ e.jobs, source }));
            e.reports.line(fmt("letters={d}", .{text.len}));
            profileLines(&e.reports, result.profile.?);
            e.reports.line(fmt("decision length={d} method={s}", .{ result.length, result.method }));
            e.reports.line(fmt("refine passes={d} changes={d} key={s}", .{ result.passes, result.changes, result.key.word }));
        } else if (cipher == .playfair) {
            const pairs = analysis.pairCounts(temporary, text, 2, true);
            const grid = playfair.square(result.key.word);
            e.reports.line(fmt("JOB {d} BREAK playfair source={s}", .{ e.jobs, source }));
            e.reports.line(fmt("letters={d}", .{text.len}));
            e.reports.line(fmt("digraphs pairs={d} distinct={d}", .{ text.len / 2, pairs.len }));
            e.reports.line(fmt("top {s}", .{countList(pairs)}));
            e.reports.line(fmt("square {s} {s} {s} {s} {s}", .{ grid[0..5], grid[5..10], grid[10..15], grid[15..20], grid[20..25] }));
        }
    }

    fn analyze(e: *Engine, source: []const u8, message_value: Message, opts: Options) JobError!void {
        const text = message_value.letters;
        if (text.len < 40) return e.fail("text too short", .{});
        const counts = analysis.letterCounts(text);
        var doubles: usize = 0;
        var pair_doubles: usize = 0;
        for (0..text.len - 1) |i| {
            if (text[i] == text[i + 1]) {
                doubles += 1;
                if (i % 2 == 0) pair_doubles += 1;
            }
        }
        e.results.line(fmt("JOB {d} ANALYZE source={s} letters={d}", .{ e.jobs, source, text.len }));
        e.reports.line(fmt("JOB {d} ANALYZE source={s}", .{ e.jobs, source }));
        e.reports.line(fmt("letters={d}", .{text.len}));
        e.reports.line(fmt("ioc={d} mono={d} bigram={d}", .{ analysis.indexOfCoincidence(text), e.weights.monogram(text), e.weights.bigram(text) }));
        e.reports.line(fmt("doubles={d} pair_doubles={d} distinct={d}", .{ doubles, pair_doubles, distinctLetters(counts) }));
        for (scoring.alphabet, counts) |letter, count| e.reports.line(fmt("{c} {d} {s}", .{ letter, count, analysis.percentage(temporary, count, text.len) }));
        e.reports.line(fmt("bigrams {s}", .{countList(analysis.pairCounts(temporary, text, 1, false))}));
        profileLines(&e.reports, periodProfile(text, opts.maxlen));
    }

    fn compare(e: *Engine, first_name: []const u8, second_name: []const u8, first: Message, second: Message) void {
        const a = first.letters;
        const b = second.letters;
        if (eq(a, b)) {
            e.results.line(fmt("JOB {d} COMPARE {s} {s} equal letters={d}", .{ e.jobs, first_name, second_name, a.len }));
            return;
        }
        const shared = @min(a.len, b.len);
        var first_difference = shared + 1;
        var mismatches: usize = 0;
        for (0..shared) |i| {
            if (a[i] != b[i]) {
                if (mismatches == 0) first_difference = i + 1;
                mismatches += 1;
            }
        }
        e.results.line(fmt("JOB {d} COMPARE {s} {s} differ letters={d},{d} first={d} mismatches={d}", .{ e.jobs, first_name, second_name, a.len, b.len, first_difference, mismatches }));
    }

    fn identify(e: *Engine, source: []const u8, message_value: Message, opts: Options, key_message: Message) JobError!void {
        const text = message_value.letters;
        if (text.len < 40) return e.fail("text too short", .{});
        const ioc = analysis.indexOfCoincidence(text);
        const average = @divFloor(e.weights.monogram(text), @as(i64, @intCast(text.len)));
        const shaped = text.len % 2 == 0 and std.mem.findScalar(u8, text, 'J') == null and playfair.validCiphertext(text);
        const family: []const u8 = if (shaped) "playfair" else if (ioc >= 5500 and average >= 44) "transposition" else if (ioc >= 5500) "monoalphabetic" else "polyalphabetic";
        var keys: []const []const u8 = &.{};
        if (shaped and opts.keys != null) {
            keys = keyList(key_message.text);
            if (keys.len == 0) return e.fail("empty key list", .{});
        }
        const ciphers: []const Cipher = if (shaped) (if (opts.keys != null) &.{.playfair} else &.{}) else if (eq(family, "transposition")) &.{ .railfence, .columnar } else if (eq(family, "monoalphabetic")) &.{.affine} else &.{ .vigenere, .autokey };
        var tried: std.ArrayList(BreakResult) = .empty;
        for (ciphers) |cipher| append(BreakResult, &tried, e.breakCipher(cipher, text, defaults(cipher), keys));
        e.reports.line(fmt("JOB {d} IDENTIFY source={s}", .{ e.jobs, source }));
        e.reports.line(fmt("letters={d} ioc={d} mono_avg={d} distinct={d} shape={s}", .{ text.len, ioc, average, distinctLetters(analysis.letterCounts(text)), if (shaped) @as([]const u8, "yes") else "no" }));
        e.reports.line(fmt("family={s}", .{family}));
        for (tried.items) |result| e.reports.line(fmt("try {s} key={s} score={d}", .{ @tagName(result.cipher), keyNotation(result.cipher, result.key), result.score }));
        if (tried.items.len == 0) {
            e.results.line(fmt("JOB {d} IDENTIFY source={s} family={s}", .{ e.jobs, source, family }));
            return;
        }
        var best: usize = 0;
        for (tried.items, 0..) |result, i| {
            if (result.score > tried.items[best].score) best = i;
        }
        const chosen = tried.items[best];
        const cipher: Cipher = if (chosen.cipher == .affine and chosen.key.a == 1) .caesar else chosen.cipher;
        const body = solutionLines(cipher, chosen.key, message_value, true);
        e.results.line(fmt("JOB {d} IDENTIFY source={s} family={s} cipher={s} key={s} score={d} lines={d}", .{ e.jobs, source, family, @tagName(cipher), keyNotation(cipher, chosen.key), chosen.score, body.len }));
        e.results.body(body);
        e.reports.line(fmt("choice {s}", .{@tagName(cipher)}));
    }

    fn finish(e: *Engine) void {
        var total_ok: usize = 0;
        inline for (@typeInfo(Command).@"enum".field_names, 0..) |command, i| {
            e.results.line(fmt("TOTAL {s} ok={d} errors={d}", .{ command, e.ok[i], e.errors[i] }));
            total_ok += e.ok[i];
        }
        e.results.line(fmt("SUMMARY jobs={d} ok={d} errors={d} messages={d}", .{ e.jobs, total_ok, e.jobs - total_ok, e.messages.count() }));
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    permanent = arena.allocator();
    temporary = permanent;
    const cwd = std.Io.Dir.cwd();
    const weights = try cwd.readFileAlloc(init.io, "input/weights.txt", permanent, .unlimited);
    const messages = try cwd.readFileAlloc(init.io, "input/messages.txt", permanent, .unlimited);
    const jobs = try cwd.readFileAlloc(init.io, "input/jobs.txt", permanent, .unlimited);
    var engine: Engine = .{ .weights = scoring.Weights.parse(weights) };
    engine.loadMessages(messages);
    for (lines(jobs)) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var job_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer job_arena.deinit();
        temporary = job_arena.allocator();
        engine.run(line);
    }
    temporary = permanent;
    engine.finish();
    try cwd.createDirPath(init.io, "output");
    try cwd.writeFile(init.io, .{ .sub_path = "output/results.txt", .data = engine.results.bytes.items });
    try cwd.writeFile(init.io, .{ .sub_path = "output/candidates.txt", .data = engine.candidates.bytes.items });
    try cwd.writeFile(init.io, .{ .sub_path = "output/analysis.txt", .data = engine.reports.bytes.items });
}
