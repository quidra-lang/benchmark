const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Failure = error{ Command, OutOfMemory };
const WordCounts = std.StringHashMapUnmanaged(usize);
const WordSet = std.StringHashMapUnmanaged(void);
const Rules = std.StringHashMapUnmanaged([]const u8);

const adjacent_keys = [26][]const u8{
    "qswz",   "ghnv",  "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy", "jkou",
    "hikmnu", "ijlmo", "kop",  "jkn",    "bhjm", "iklp",   "lo",     "aw",     "deft",
    "adewxz", "fgry",  "hijy", "bcfg",   "aeqs", "cdsz",   "ghtu",   "asx",
};
// Digits of a to z; h and w have no digit and are skipped by soundex.
const soundex_digits = "01230120022455012623010202";
const sentence_marks = ".!?";
const max_word_length = 30;
const max_frequency = 1000000;
const max_listed = 20;
const report_size = 10;

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn all(text: []const u8, comptime predicate: fn (u8) bool) bool {
    for (text) |c| {
        if (!predicate(c)) return false;
    }
    return true;
}

fn any(text: []const u8, comptime predicate: fn (u8) bool) bool {
    for (text) |c| {
        if (predicate(c)) return true;
    }
    return false;
}

fn head(comptime T: type, items: []const T, count: usize) []const T {
    return items[0..@min(items.len, count)];
}

const Decimal = struct {
    numerator: usize,
    denominator: usize,
    digits: usize,

    pub fn format(decimal: Decimal, writer: *Writer) Writer.Error!void {
        const scale = std.math.pow(usize, 10, decimal.digits);
        const value = (2 * decimal.numerator * scale + decimal.denominator) / (2 * decimal.denominator);
        try writer.print("{d}.", .{value / scale});
        try writer.printInt(value % scale, 10, .lower, .{ .width = decimal.digits, .fill = '0' });
    }
};

fn applyCase(gpa: Allocator, token_text: []const u8, word: []const u8) ![]u8 {
    if (token_text.len >= 2 and all(token_text, std.ascii.isUpper)) {
        return std.ascii.allocUpperString(gpa, word);
    }
    const result = try gpa.dupe(u8, word);
    if (std.ascii.isUpper(token_text[0])) result[0] = std.ascii.toUpper(result[0]);
    return result;
}

const Token = struct {
    number: usize,
    text: []const u8,
    word: []const u8,
    end: usize,
    gap: []const u8,
    sentence_start: bool,
    repeat: bool,

    fn mixedCase(token: Token) bool {
        return any(token.text[1..], std.ascii.isUpper) and !all(token.text, std.ascii.isUpper);
    }
};

fn tokenize(gpa: Allocator, text: []const u8) ![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    var position: usize = 0;
    var start: usize = 0;
    while (start < text.len) {
        if (!std.ascii.isAlphabetic(text[start])) {
            start += 1;
            continue;
        }
        var end = start;
        while (end < text.len and std.ascii.isAlphabetic(text[end])) end += 1;
        const gap = text[position..start];
        const word = try std.ascii.allocLowerString(gpa, text[start..end]);
        const previous = tokens.getLastOrNull();
        const only_spaces = std.mem.allEqual(u8, gap, ' ');
        try tokens.append(gpa, .{
            .number = tokens.items.len + 1,
            .text = text[start..end],
            .word = word,
            .end = end,
            .gap = gap,
            .sentence_start = previous == null or std.mem.findAny(u8, gap, sentence_marks) != null,
            .repeat = previous != null and only_spaces and equal(word, previous.?.word),
        });
        position = end;
        start = end;
    }
    return tokens.items;
}

fn gapCost(keyboard: bool) usize {
    return if (keyboard) 2 else 1;
}

fn substitutionCost(first: u8, second: u8, keyboard: bool) usize {
    if (first == second) return 0;
    if (!keyboard) return 1;
    return if (std.mem.findScalar(u8, adjacent_keys[first - 'a'], second) != null) 1 else 2;
}

fn isSwap(a: []const u8, b: []const u8, i: usize, j: usize) bool {
    return i >= 2 and j >= 2 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1];
}

const Table = struct {
    cells: []usize,
    width: usize,

    fn get(table: Table, i: usize, j: usize) usize {
        return table.cells[i * table.width + j];
    }

    fn set(table: Table, i: usize, j: usize, value: usize) void {
        table.cells[i * table.width + j] = value;
    }

    fn row(table: Table, i: usize) []const usize {
        return table.cells[i * table.width ..][0..table.width];
    }

    fn deinit(table: Table, gpa: Allocator) void {
        gpa.free(table.cells);
    }
};

fn distanceTable(gpa: Allocator, a: []const u8, b: []const u8, keyboard: bool) !Table {
    const gap = gapCost(keyboard);
    const width = b.len + 1;
    const table: Table = .{ .cells = try gpa.alloc(usize, (a.len + 1) * width), .width = width };
    for (0..a.len + 1) |i| table.set(i, 0, i * gap);
    for (0..b.len + 1) |j| table.set(0, j, j * gap);
    for (1..a.len + 1) |i| {
        for (1..b.len + 1) |j| {
            var best = @min(
                table.get(i - 1, j) + gap,
                table.get(i, j - 1) + gap,
                table.get(i - 1, j - 1) + substitutionCost(a[i - 1], b[j - 1], keyboard),
            );
            if (isSwap(a, b, i, j)) best = @min(best, table.get(i - 2, j - 2) + 1);
            table.set(i, j, best);
        }
    }
    return table;
}

fn editDistance(gpa: Allocator, a: []const u8, b: []const u8, keyboard: bool) !usize {
    const table = try distanceTable(gpa, a, b, keyboard);
    defer table.deinit(gpa);
    return table.get(a.len, b.len);
}

fn prefixDistance(gpa: Allocator, a: []const u8, b: []const u8, keyboard: bool) !usize {
    const table = try distanceTable(gpa, a, b, keyboard);
    defer table.deinit(gpa);
    return std.mem.min(usize, table.row(a.len));
}

const Operation = union(enum) {
    sub: [2]u8,
    swap: [2]u8,
    del: u8,
    ins: u8,

    pub fn format(operation: Operation, writer: *Writer) Writer.Error!void {
        switch (operation) {
            .sub => |pair| try writer.print("sub:{c}>{c}", .{ pair[0], pair[1] }),
            .swap => |pair| try writer.print("swap:{c}{c}", .{ pair[0], pair[1] }),
            .del => |letter| try writer.print("del:{c}", .{letter}),
            .ins => |letter| try writer.print("ins:{c}", .{letter}),
        }
    }
};

const Edits = struct { distance: usize, operations: []const Operation };

fn editOperations(gpa: Allocator, a: []const u8, b: []const u8, keyboard: bool) !Edits {
    const table = try distanceTable(gpa, a, b, keyboard);
    defer table.deinit(gpa);
    const gap = gapCost(keyboard);
    var operations: std.ArrayList(Operation) = .empty;
    var i = a.len;
    var j = b.len;
    while (i > 0 or j > 0) {
        const current = table.get(i, j);
        if (i >= 1 and j >= 1 and
            current == table.get(i - 1, j - 1) + substitutionCost(a[i - 1], b[j - 1], keyboard))
        {
            if (a[i - 1] != b[j - 1]) try operations.append(gpa, .{ .sub = .{ a[i - 1], b[j - 1] } });
            i -= 1;
            j -= 1;
        } else if (isSwap(a, b, i, j) and current == table.get(i - 2, j - 2) + 1) {
            try operations.append(gpa, .{ .swap = .{ a[i - 2], a[i - 1] } });
            i -= 2;
            j -= 2;
        } else if (i >= 1 and current == table.get(i - 1, j) + gap) {
            try operations.append(gpa, .{ .del = a[i - 1] });
            i -= 1;
        } else {
            try operations.append(gpa, .{ .ins = b[j - 1] });
            j -= 1;
        }
    }
    std.mem.reverse(Operation, operations.items);
    return .{ .distance = table.get(a.len, b.len), .operations = operations.items };
}

fn soundex(word: []const u8) [4]u8 {
    var code: [4]u8 = @splat('0');
    code[0] = std.ascii.toUpper(word[0]);
    var length: usize = 1;
    var previous = soundex_digits[word[0] - 'a'];
    for (word[1..]) |letter| {
        if (letter == 'h' or letter == 'w') continue;
        const digit = soundex_digits[letter - 'a'];
        if (digit != '0' and digit != previous and length < code.len) {
            code[length] = digit;
            length += 1;
        }
        previous = digit;
    }
    return code;
}

const Segmentation = struct { ways: usize, words: []const []const u8 };

fn segmentationLess(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return a.len < b.len;
    for (a, b) |left, right| {
        const order = std.mem.order(u8, left, right);
        if (order != .eq) return order == .lt;
    }
    return false;
}

fn segment(gpa: Allocator, word: []const u8, dictionary: WordCounts) !?Segmentation {
    const ways = try gpa.alloc(usize, word.len + 1);
    const best = try gpa.alloc([]const []const u8, word.len + 1);
    @memset(ways, 0);
    ways[word.len] = 1;
    best[word.len] = &.{};
    var start = word.len;
    while (start > 0) {
        start -= 1;
        for (start + 1..word.len + 1) |end| {
            const piece = word[start..end];
            if (!dictionary.contains(piece) or ways[end] == 0) continue;
            const candidate = try std.mem.concat(gpa, []const u8, &.{ &.{piece}, best[end] });
            if (ways[start] == 0 or segmentationLess(candidate, best[start])) best[start] = candidate;
            ways[start] += ways[end];
        }
    }
    if (ways[0] == 0) return null;
    return .{ .ways = ways[0], .words = best[0] };
}

const WordCount = struct { word: []const u8, count: usize };

fn countLess(_: void, a: WordCount, b: WordCount) bool {
    if (a.count != b.count) return a.count > b.count;
    return less({}, a.word, b.word);
}

fn alphabeticalLess(_: void, a: WordCount, b: WordCount) bool {
    return less({}, a.word, b.word);
}

fn wordCounts(gpa: Allocator, counts: WordCounts) ![]WordCount {
    const result = try gpa.alloc(WordCount, counts.count());
    var iterator = counts.iterator();
    var i: usize = 0;
    while (iterator.next()) |entry| : (i += 1) {
        result[i] = .{ .word = entry.key_ptr.*, .count = entry.value_ptr.* };
    }
    return result;
}

fn writeWordCounts(out: *Writer, items: []const WordCount) !void {
    for (items) |item| try out.print(" {s}:{d}", .{ item.word, item.count });
    try out.writeByte('\n');
}

const Candidate = struct { word: []const u8, distance: usize, frequency: usize };

fn candidateLess(_: void, a: Candidate, b: Candidate) bool {
    if (a.distance != b.distance) return a.distance < b.distance;
    if (a.frequency != b.frequency) return a.frequency > b.frequency;
    return less({}, a.word, b.word);
}

const Correction = struct { word: []const u8, replacement: []const u8, count: usize };

fn correctionLess(_: void, a: Correction, b: Correction) bool {
    if (a.count != b.count) return a.count > b.count;
    if (!equal(a.word, b.word)) return less({}, a.word, b.word);
    return less({}, a.replacement, b.replacement);
}

const UndoRecord = struct {
    name: []const u8,
    dictionary: WordCounts,
    ignored: WordSet,
    rules: Rules,
};

const Counters = struct {
    checked: usize = 0,
    unknown: usize = 0,
    case: usize = 0,
    capital: usize = 0,
    repeats: usize = 0,
    corrected: usize = 0,
};

const Command = enum {
    CHECK,
    CORRECT,
    FIX,
    PROFILE,
    LEARN,
    SUGGEST,
    DIST,
    SOUNDEX,
    SOUNDS,
    SPLIT,
    PREFIX,
    COMPLETE,
    LIST,
    WORD,
    ADD,
    REMOVE,
    IGNORE,
    UNIGNORE,
    RULE,
    UNRULE,
    RULES,
    KEYBOARD,
    SET,
    UNDO,
    REPORT,
    HISTORY,
    STATS,

    fn arity(command: Command) ?usize {
        return switch (command) {
            .CHECK, .CORRECT, .FIX, .PROFILE, .LEARN => null,
            .RULES, .UNDO, .REPORT, .HISTORY, .STATS => 0,
            .DIST, .PREFIX, .COMPLETE, .LIST, .ADD, .RULE, .SET => 2,
            else => 1,
        };
    }
};

const SpellChecker = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Writer,
    dictionary: WordCounts,
    ignored: WordSet = .empty,
    rules: Rules = .empty,
    keyboard: bool = false,
    base_limit: usize = 2,
    suggestion_count: usize = 5,
    undo_history: std.ArrayList(UndoRecord) = .empty,
    unknown_log: WordCounts = .empty,
    correction_log: std.ArrayList(Correction) = .empty,
    counters: Counters = .{},
    problem: []const u8 = "",

    fn fail(checker: *SpellChecker, comptime pattern: []const u8, args: anytype) Failure {
        checker.problem = std.fmt.allocPrint(checker.scratch, pattern, args) catch
            return error.OutOfMemory;
        return error.Command;
    }

    fn wordArgument(checker: *SpellChecker, text: []const u8) ![]const u8 {
        if (text.len == 0 or text.len > max_word_length or !all(text, std.ascii.isAlphabetic)) {
            return checker.fail("BAD WORD {s}", .{text});
        }
        return std.ascii.allocLowerString(checker.scratch, text);
    }

    fn numberArgument(checker: *SpellChecker, text: []const u8, minimum: usize, maximum: usize) !usize {
        if (text.len >= 1 and text.len <= 7 and all(text, std.ascii.isDigit)) {
            const value = std.fmt.parseInt(usize, text, 10) catch unreachable;
            if (minimum <= value and value <= maximum) return value;
        }
        return checker.fail("BAD NUMBER {s}", .{text});
    }

    fn limit(checker: SpellChecker) usize {
        return if (checker.keyboard) 2 * checker.base_limit else checker.base_limit;
    }

    fn isKnown(checker: SpellChecker, word: []const u8) bool {
        return checker.dictionary.contains(word) or checker.ignored.contains(word);
    }

    fn dictionaryEntries(checker: *SpellChecker) ![]WordCount {
        return wordCounts(checker.scratch, checker.dictionary);
    }

    fn frequencyOrder(checker: *SpellChecker) ![]WordCount {
        const order = try checker.dictionaryEntries();
        std.mem.sort(WordCount, order, {}, countLess);
        return order;
    }

    fn requireEntry(checker: *SpellChecker, word: []const u8) !usize {
        return checker.dictionary.get(word) orelse return checker.fail("NOT FOUND {s}", .{word});
    }

    fn candidates(checker: *SpellChecker, word: []const u8) ![]Candidate {
        const max_distance = checker.limit();
        const gap = gapCost(checker.keyboard);
        var found: std.ArrayList(Candidate) = .empty;
        for (try checker.dictionaryEntries()) |entry| {
            const difference = @max(entry.word.len, word.len) - @min(entry.word.len, word.len);
            if (equal(entry.word, word) or difference * gap > max_distance) continue;
            const distance = try editDistance(checker.scratch, word, entry.word, checker.keyboard);
            if (distance <= max_distance) {
                try found.append(checker.scratch, .{
                    .word = entry.word,
                    .distance = distance,
                    .frequency = entry.count,
                });
            }
        }
        std.mem.sort(Candidate, found.items, {}, candidateLess);
        return found.items;
    }

    fn correction(checker: *SpellChecker, word: []const u8) !?[]const u8 {
        if (checker.isKnown(word)) return null;
        if (checker.rules.get(word)) |target| return target;
        const found = try checker.candidates(word);
        return if (found.len > 0) found[0].word else null;
    }

    fn recordUndo(checker: *SpellChecker, name: []const u8) !void {
        try checker.undo_history.append(checker.gpa, .{
            .name = name,
            .dictionary = try checker.dictionary.clone(checker.gpa),
            .ignored = try checker.ignored.clone(checker.gpa),
            .rules = try checker.rules.clone(checker.gpa),
        });
    }

    fn logCorrection(checker: *SpellChecker, word: []const u8, replacement: []const u8) !void {
        checker.counters.corrected += 1;
        for (checker.correction_log.items) |*entry| {
            if (equal(entry.word, word) and equal(entry.replacement, replacement)) {
                entry.count += 1;
                return;
            }
        }
        try checker.correction_log.append(checker.gpa, .{
            .word = try checker.gpa.dupe(u8, word),
            .replacement = replacement,
            .count = 1,
        });
    }

    fn writeUnknown(checker: *SpellChecker, out: *Writer, token: Token) !void {
        try out.print("UNKNOWN {d} {s}", .{ token.number, token.text });
        if (checker.rules.get(token.word)) |target| {
            try out.print(" RULE {s}\n", .{target});
            return;
        }
        const found = try checker.candidates(token.word);
        if (found.len == 0) {
            try out.writeAll(" NONE\n");
            return;
        }
        try out.writeAll(" SUGGEST");
        for (head(Candidate, found, checker.suggestion_count)) |candidate| {
            try out.print(" {s}", .{candidate.word});
        }
        try out.writeByte('\n');
    }

    fn check(checker: *SpellChecker, text: []const u8) !void {
        const tokens = try tokenize(checker.scratch, text);
        var findings: Writer.Allocating = .init(checker.scratch);
        const out = &findings.writer;
        var unknown: usize = 0;
        var mixed: usize = 0;
        var capital: usize = 0;
        var repeats: usize = 0;
        for (tokens) |token| {
            if (!checker.isKnown(token.word)) {
                try checker.writeUnknown(out, token);
                const logged = try checker.unknown_log.getOrPut(checker.gpa, token.word);
                if (!logged.found_existing) {
                    logged.key_ptr.* = try checker.gpa.dupe(u8, token.word);
                    logged.value_ptr.* = 0;
                }
                logged.value_ptr.* += 1;
                unknown += 1;
            }
            if (token.mixedCase()) {
                try out.print("CASE {d} {s}\n", .{ token.number, token.text });
                mixed += 1;
            }
            if (token.sentence_start and std.ascii.isLower(token.text[0])) {
                try out.print("CAPITAL {d} {s}\n", .{ token.number, token.text });
                capital += 1;
            }
            if (token.repeat) {
                try out.print("REPEAT {d} {s}\n", .{ token.number, token.text });
                repeats += 1;
            }
        }
        checker.counters.checked += tokens.len;
        checker.counters.unknown += unknown;
        checker.counters.case += mixed;
        checker.counters.capital += capital;
        checker.counters.repeats += repeats;
        try checker.out.print("CHECK words={d} unknown={d} case={d} capital={d} repeats={d}\n", .{
            tokens.len, unknown, mixed, capital, repeats,
        });
        try checker.out.writeAll(findings.written());
    }

    fn correct(checker: *SpellChecker, text: []const u8) !void {
        const scratch = checker.scratch;
        var result: std.ArrayList(u8) = .empty;
        var position: usize = 0;
        var changed: usize = 0;
        for (try tokenize(scratch, text)) |token| {
            try result.appendSlice(scratch, token.gap);
            if (try checker.correction(token.word)) |replacement| {
                try result.appendSlice(scratch, try applyCase(scratch, token.text, replacement));
                try checker.logCorrection(token.word, replacement);
                changed += 1;
            } else {
                try result.appendSlice(scratch, token.text);
            }
            position = token.end;
        }
        try result.appendSlice(scratch, text[position..]);
        try checker.out.print("CORRECT changed={d}: {s}\n", .{ changed, result.items });
    }

    fn fix(checker: *SpellChecker, text: []const u8) !void {
        const scratch = checker.scratch;
        var result: std.ArrayList(u8) = .empty;
        var position: usize = 0;
        var removed: usize = 0;
        var replaced: usize = 0;
        var recased: usize = 0;
        for (try tokenize(scratch, text)) |token| {
            position = token.end;
            if (token.repeat) {
                removed += 1;
                continue;
            }
            const replacement = try checker.correction(token.word);
            const fixed = try applyCase(scratch, token.text, replacement orelse token.word);
            if (token.sentence_start and std.ascii.isLower(fixed[0])) {
                fixed[0] = std.ascii.toUpper(fixed[0]);
            }
            if (replacement) |word| {
                try checker.logCorrection(token.word, word);
                replaced += 1;
            } else if (!equal(fixed, token.text)) {
                recased += 1;
            }
            try result.appendSlice(scratch, token.gap);
            try result.appendSlice(scratch, fixed);
        }
        try result.appendSlice(scratch, text[position..]);
        try checker.out.print("FIX removed={d} replaced={d} recased={d}: {s}\n", .{
            removed, replaced, recased, result.items,
        });
    }

    fn profile(checker: *SpellChecker, text: []const u8) !void {
        const tokens = try tokenize(checker.scratch, text);
        var distinct: WordSet = .empty;
        var unknown: usize = 0;
        var sentences: usize = 0;
        var characters: usize = 0;
        var longest: ?Token = null;
        for (tokens) |token| {
            try distinct.put(checker.scratch, token.word, {});
            if (!checker.isKnown(token.word)) unknown += 1;
            if (token.sentence_start) sentences += 1;
            characters += token.text.len;
            if (longest == null or token.text.len > longest.?.text.len) longest = token;
        }
        const count = @max(tokens.len, 1);
        const rate: Decimal = .{ .numerator = 100 * unknown, .denominator = count, .digits = 1 };
        const average: Decimal = .{ .numerator = characters, .denominator = count, .digits = 2 };
        try checker.out.print(
            "PROFILE words={d} distinct={d} unknown={d} rate={f} avglen={f} longest={s} sentences={d}\n",
            .{
                tokens.len,
                distinct.count(),
                unknown,
                rate,
                average,
                if (longest) |token| token.word else "-",
                sentences,
            },
        );
    }

    fn learn(checker: *SpellChecker, text: []const u8) !void {
        try checker.recordUndo("LEARN");
        var updated: usize = 0;
        var added: usize = 0;
        var skipped: usize = 0;
        for (try tokenize(checker.scratch, text)) |token| {
            if (token.word.len > max_word_length) {
                skipped += 1;
            } else if (checker.dictionary.getPtr(token.word)) |frequency| {
                frequency.* += 1;
                updated += 1;
            } else {
                try checker.dictionary.put(checker.gpa, try checker.gpa.dupe(u8, token.word), 1);
                _ = checker.ignored.remove(token.word);
                added += 1;
            }
        }
        try checker.out.print("LEARN updated={d} added={d} skipped={d}\n", .{ updated, added, skipped });
    }

    fn suggest(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const out = checker.out;
        if (checker.isKnown(word)) {
            try out.print("SUGGEST {s} KNOWN\n", .{word});
        } else if (checker.rules.get(word)) |target| {
            try out.print("SUGGEST {s} RULE {s}\n", .{ word, target });
        } else {
            const found = try checker.candidates(word);
            try out.print("SUGGEST {s} found={d}", .{ word, found.len });
            for (head(Candidate, found, checker.suggestion_count)) |candidate| {
                try out.print(" {s}:{d}", .{ candidate.word, candidate.distance });
            }
            try out.writeByte('\n');
        }
    }

    fn dist(checker: *SpellChecker, raw_first: []const u8, raw_second: []const u8) !void {
        const first = try checker.wordArgument(raw_first);
        const second = try checker.wordArgument(raw_second);
        const edits = try editOperations(checker.scratch, first, second, checker.keyboard);
        try checker.out.print("DIST {s} {s} {d}", .{ first, second, edits.distance });
        for (edits.operations) |operation| try checker.out.print(" {f}", .{operation});
        try checker.out.writeByte('\n');
    }

    fn soundexCode(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const code = soundex(word);
        try checker.out.print("SOUNDEX {s} {s}\n", .{ word, &code });
    }

    fn sounds(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const code = soundex(word);
        var matches: std.ArrayList([]const u8) = .empty;
        for (try checker.frequencyOrder()) |entry| {
            const other_code = soundex(entry.word);
            if (!equal(entry.word, word) and equal(&other_code, &code)) {
                try matches.append(checker.scratch, entry.word);
            }
        }
        try checker.out.print("SOUNDS {s} {s} count={d}", .{ word, &code, matches.items.len });
        for (head([]const u8, matches.items, report_size)) |match| try checker.out.print(" {s}", .{match});
        try checker.out.writeByte('\n');
    }

    fn split(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const result = try segment(checker.scratch, word, checker.dictionary) orelse {
            try checker.out.print("SPLIT {s} ways=0 -> NONE\n", .{word});
            return;
        };
        try checker.out.print("SPLIT {s} ways={d} ->", .{ word, result.ways });
        for (result.words) |piece| try checker.out.print(" {s}", .{piece});
        try checker.out.writeByte('\n');
    }

    fn prefix(checker: *SpellChecker, raw_word: []const u8, raw_count: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const count = try checker.numberArgument(raw_count, 1, max_listed);
        var matches: std.ArrayList(WordCount) = .empty;
        for (try checker.frequencyOrder()) |entry| {
            if (std.mem.startsWith(u8, entry.word, word)) try matches.append(checker.scratch, entry);
        }
        try checker.out.print("PREFIX {s} count={d}", .{ word, matches.items.len });
        try writeWordCounts(checker.out, head(WordCount, matches.items, count));
    }

    fn complete(checker: *SpellChecker, raw_word: []const u8, raw_count: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const count = try checker.numberArgument(raw_count, 1, max_listed);
        const threshold = checker.limit() / 2;
        var matches: std.ArrayList(Candidate) = .empty;
        for (try checker.dictionaryEntries()) |entry| {
            const distance = try prefixDistance(checker.scratch, word, entry.word, checker.keyboard);
            if (distance <= threshold) {
                try matches.append(checker.scratch, .{
                    .word = entry.word,
                    .distance = distance,
                    .frequency = entry.count,
                });
            }
        }
        std.mem.sort(Candidate, matches.items, {}, candidateLess);
        try checker.out.print("COMPLETE {s} count={d}", .{ word, matches.items.len });
        for (head(Candidate, matches.items, count)) |match| {
            try checker.out.print(" {s}:{d}", .{ match.word, match.distance });
        }
        try checker.out.writeByte('\n');
    }

    fn listWords(checker: *SpellChecker, raw_word: []const u8, raw_count: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const count = try checker.numberArgument(raw_count, 1, max_listed);
        var matches: std.ArrayList(WordCount) = .empty;
        for (try checker.dictionaryEntries()) |entry| {
            if (!less({}, entry.word, word)) try matches.append(checker.scratch, entry);
        }
        std.mem.sort(WordCount, matches.items, {}, alphabeticalLess);
        try checker.out.print("LIST {s} count={d}", .{ word, matches.items.len });
        try writeWordCounts(checker.out, head(WordCount, matches.items, count));
    }

    fn wordInfo(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const frequency = try checker.requireEntry(word);
        const rank = for (try checker.frequencyOrder(), 1..) |entry, position| {
            if (equal(entry.word, word)) break position;
        } else unreachable;
        const code = soundex(word);
        const neighbors = (try checker.candidates(word)).len;
        try checker.out.print("WORD {s} freq={d} rank={d} soundex={s} neighbors={d}\n", .{
            word, frequency, rank, &code, neighbors,
        });
    }

    fn add(checker: *SpellChecker, raw_word: []const u8, raw_frequency: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const frequency = try checker.numberArgument(raw_frequency, 1, max_frequency);
        if (checker.dictionary.contains(word)) return checker.fail("DUPLICATE {s}", .{word});
        try checker.recordUndo("ADD");
        try checker.dictionary.put(checker.gpa, try checker.gpa.dupe(u8, word), frequency);
        _ = checker.ignored.remove(word);
        try checker.out.print("ADD {s} {d}\n", .{ word, frequency });
    }

    fn remove(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const frequency = try checker.requireEntry(word);
        try checker.recordUndo("REMOVE");
        _ = checker.dictionary.remove(word);
        try checker.out.print("REMOVE {s} {d}\n", .{ word, frequency });
    }

    fn ignore(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        if (checker.dictionary.contains(word)) return checker.fail("IN DICTIONARY {s}", .{word});
        if (checker.ignored.contains(word)) return checker.fail("ALREADY IGNORED {s}", .{word});
        try checker.recordUndo("IGNORE");
        try checker.ignored.put(checker.gpa, try checker.gpa.dupe(u8, word), {});
        try checker.out.print("IGNORE {s}\n", .{word});
    }

    fn unignore(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        if (!checker.ignored.contains(word)) return checker.fail("NOT IGNORED {s}", .{word});
        try checker.recordUndo("UNIGNORE");
        _ = checker.ignored.remove(word);
        try checker.out.print("UNIGNORE {s}\n", .{word});
    }

    fn rule(checker: *SpellChecker, raw_source: []const u8, raw_target: []const u8) !void {
        const source = try checker.wordArgument(raw_source);
        const target = try checker.wordArgument(raw_target);
        if (checker.dictionary.contains(source)) return checker.fail("IN DICTIONARY {s}", .{source});
        if (!checker.dictionary.contains(target)) return checker.fail("NOT FOUND {s}", .{target});
        try checker.recordUndo("RULE");
        const previous = checker.rules.get(source);
        const gpa = checker.gpa;
        try checker.rules.put(gpa, try gpa.dupe(u8, source), try gpa.dupe(u8, target));
        if (previous) |old_target| {
            try checker.out.print("RULE {s} {s} REPLACED {s}\n", .{ source, target, old_target });
        } else {
            try checker.out.print("RULE {s} {s}\n", .{ source, target });
        }
    }

    fn unrule(checker: *SpellChecker, raw_word: []const u8) !void {
        const word = try checker.wordArgument(raw_word);
        const target = checker.rules.get(word) orelse return checker.fail("NO RULE {s}", .{word});
        try checker.recordUndo("UNRULE");
        _ = checker.rules.remove(word);
        try checker.out.print("UNRULE {s} {s}\n", .{ word, target });
    }

    fn showRules(checker: *SpellChecker) !void {
        const out = checker.out;
        var sources: std.ArrayList([]const u8) = .empty;
        var iterator = checker.rules.keyIterator();
        while (iterator.next()) |source| try sources.append(checker.scratch, source.*);
        std.mem.sort([]const u8, sources.items, {}, less);
        try out.print("RULES count={d}", .{sources.items.len});
        for (sources.items) |source| try out.print(" {s}>{s}", .{ source, checker.rules.get(source).? });
        try out.writeByte('\n');
    }

    fn keyboardMode(checker: *SpellChecker, mode: []const u8) !void {
        if (!equal(mode, "ON") and !equal(mode, "OFF")) return checker.fail("BAD MODE {s}", .{mode});
        checker.keyboard = equal(mode, "ON");
        try checker.out.print("KEYBOARD {s}\n", .{mode});
    }

    fn setOption(checker: *SpellChecker, option: []const u8, raw_value: []const u8) !void {
        const Option = enum { LIMIT, SUGGESTIONS };
        const selected = std.meta.stringToEnum(Option, option) orelse
            return checker.fail("BAD OPTION {s}", .{option});
        const maximum: usize = switch (selected) {
            .LIMIT => 3,
            .SUGGESTIONS => 10,
        };
        const value = try checker.numberArgument(raw_value, 1, maximum);
        switch (selected) {
            .LIMIT => checker.base_limit = value,
            .SUGGESTIONS => checker.suggestion_count = value,
        }
        try checker.out.print("SET {s} {d}\n", .{ option, value });
    }

    fn undo(checker: *SpellChecker) !void {
        const record = checker.undo_history.pop() orelse return checker.fail("NOTHING TO UNDO", .{});
        checker.dictionary = record.dictionary;
        checker.ignored = record.ignored;
        checker.rules = record.rules;
        try checker.out.print("UNDO {s}\n", .{record.name});
    }

    fn report(checker: *SpellChecker) !void {
        const entries = try wordCounts(checker.scratch, checker.unknown_log);
        std.mem.sort(WordCount, entries, {}, countLess);
        try checker.out.print("REPORT distinct={d}", .{entries.len});
        try writeWordCounts(checker.out, head(WordCount, entries, report_size));
    }

    fn history(checker: *SpellChecker) !void {
        const entries = try checker.scratch.dupe(Correction, checker.correction_log.items);
        std.mem.sort(Correction, entries, {}, correctionLess);
        try checker.out.print("HISTORY distinct={d}", .{entries.len});
        for (head(Correction, entries, report_size)) |entry| {
            try checker.out.print(" {s}>{s}:{d}", .{ entry.word, entry.replacement, entry.count });
        }
        try checker.out.writeByte('\n');
    }

    fn stats(checker: *SpellChecker) !void {
        const order = try checker.frequencyOrder();
        var total: usize = 0;
        var characters: usize = 0;
        for (order) |entry| {
            total += entry.count;
            characters += entry.word.len;
        }
        const average: Decimal = .{ .numerator = characters, .denominator = order.len, .digits = 2 };
        try checker.out.print(
            "STATS words={d} total={d} avglen={f} top={s}:{d} ignored={d} rules={d} keyboard={s} " ++
                "limit={d} suggestions={d} undo={d}\n",
            .{
                order.len,
                total,
                average,
                order[0].word,
                order[0].count,
                checker.ignored.count(),
                checker.rules.count(),
                if (checker.keyboard) "ON" else "OFF",
                checker.limit(),
                checker.suggestion_count,
                checker.undo_history.items.len,
            },
        );
        const counters = checker.counters;
        try checker.out.print(
            "SESSION checked={d} unknown={d} case={d} capital={d} repeats={d} corrected={d}\n",
            .{
                counters.checked,
                counters.unknown,
                counters.case,
                counters.capital,
                counters.repeats,
                counters.corrected,
            },
        );
    }

    fn execute(checker: *SpellChecker, line: []const u8) !void {
        const space = std.mem.findScalar(u8, line, ' ');
        const name = line[0 .. space orelse line.len];
        const rest = if (space) |index| line[index + 1 ..] else "";
        const command = std.meta.stringToEnum(Command, name) orelse
            return checker.fail("UNKNOWN COMMAND {s}", .{name});
        var arguments: std.ArrayList([]const u8) = .empty;
        if (command.arity()) |expected| {
            if (space != null) {
                var parts = std.mem.splitScalar(u8, rest, ' ');
                while (parts.next()) |part| try arguments.append(checker.scratch, part);
            }
            if (arguments.items.len != expected) return checker.fail("BAD ARGUMENTS {s}", .{name});
        } else if (space == null) {
            return checker.fail("BAD ARGUMENTS {s}", .{name});
        }
        const args = arguments.items;
        switch (command) {
            .CHECK => try checker.check(rest),
            .CORRECT => try checker.correct(rest),
            .FIX => try checker.fix(rest),
            .PROFILE => try checker.profile(rest),
            .LEARN => try checker.learn(rest),
            .SUGGEST => try checker.suggest(args[0]),
            .DIST => try checker.dist(args[0], args[1]),
            .SOUNDEX => try checker.soundexCode(args[0]),
            .SOUNDS => try checker.sounds(args[0]),
            .SPLIT => try checker.split(args[0]),
            .PREFIX => try checker.prefix(args[0], args[1]),
            .COMPLETE => try checker.complete(args[0], args[1]),
            .LIST => try checker.listWords(args[0], args[1]),
            .WORD => try checker.wordInfo(args[0]),
            .ADD => try checker.add(args[0], args[1]),
            .REMOVE => try checker.remove(args[0]),
            .IGNORE => try checker.ignore(args[0]),
            .UNIGNORE => try checker.unignore(args[0]),
            .RULE => try checker.rule(args[0], args[1]),
            .UNRULE => try checker.unrule(args[0]),
            .RULES => try checker.showRules(),
            .KEYBOARD => try checker.keyboardMode(args[0]),
            .SET => try checker.setOption(args[0], args[1]),
            .UNDO => try checker.undo(),
            .REPORT => try checker.report(),
            .HISTORY => try checker.history(),
            .STATS => try checker.stats(),
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var line: Writer.Allocating = .init(gpa);
    _ = try input.streamDelimiterEnding(&line.writer, '\n');
    if (input.seek < input.end) {
        input.toss(1);
    } else if (line.written().len == 0) {
        return error.EndOfStream;
    }
    return line.toOwnedSlice();
}

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const reader = &input.interface;
    var dictionary: WordCounts = .empty;
    const word_count = try std.fmt.parseInt(usize, try readLine(gpa, reader), 10);
    for (0..word_count) |_| {
        var fields = std.mem.tokenizeScalar(u8, try readLine(gpa, reader), ' ');
        const word = fields.next().?;
        try dictionary.put(gpa, word, try std.fmt.parseInt(usize, fields.next().?, 10));
    }
    var checker: SpellChecker = .{
        .gpa = gpa,
        .scratch = gpa,
        .out = &output.interface,
        .dictionary = dictionary,
    };
    const command_count = try std.fmt.parseInt(usize, try readLine(gpa, reader), 10);
    for (0..command_count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        checker.scratch = scratch.allocator();
        const line = try readLine(checker.scratch, reader);
        checker.execute(line) catch |err| {
            if (err != error.Command) return err;
            try checker.out.print("ERROR {s}\n", .{checker.problem});
        };
    }
    try output.interface.flush();
}
