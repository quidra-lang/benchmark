const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Counts = std.StringHashMapUnmanaged(usize);
const WordSet = std.StringHashMapUnmanaged(void);
const Condition = *const fn ([]const u8) bool;

const kwic_width = 30;
const max_count = 100;
const max_document_number = 999;
const max_line_number = 999;
const step_names = [_][]const u8{ "1a", "1b", "1c", "2", "3", "4", "5a", "5b" };
const step_4_suffixes = [_][]const u8{
    "al",  "ance", "ence", "er",  "ic",  "able", "ible", "ant", "ement", "ment",
    "ent", "ion",  "ou",   "ism", "ate", "iti",  "ous",  "ive", "ize",
};

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn printLine(out: *Writer, comptime pattern: []const u8, args: anytype) Writer.Error!void {
    try out.print(pattern ++ "\n", args);
}

fn yesNo(flag: bool) []const u8 {
    return if (flag) "YES" else "NO";
}

fn isWord(text: []const u8) bool {
    if (text.len < 1 or text.len > 30) return false;
    for (text) |c| {
        if (!std.ascii.isAlphabetic(c)) return false;
    }
    return true;
}

fn isNumber(text: []const u8) bool {
    if (text.len < 1 or text.len > 7) return false;
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn isVowel(word: []const u8, index: usize) bool {
    return switch (word[index]) {
        'a', 'e', 'i', 'o', 'u' => true,
        'y' => index > 0 and !isVowel(word, index - 1),
        else => false,
    };
}

fn letterPattern(gpa: Allocator, word: []const u8) Allocator.Error![]const u8 {
    const kinds = try gpa.alloc(u8, word.len);
    for (kinds, 0..) |*kind, index| kind.* = if (isVowel(word, index)) 'V' else 'C';
    return kinds;
}

fn measure(word: []const u8) usize {
    var count: usize = 0;
    var index: usize = 1;
    while (index < word.len) : (index += 1) {
        if (isVowel(word, index - 1) and !isVowel(word, index)) count += 1;
    }
    return count;
}

fn hasVowel(word: []const u8) bool {
    for (0..word.len) |index| {
        if (isVowel(word, index)) return true;
    }
    return false;
}

fn endsDouble(word: []const u8) bool {
    const size = word.len;
    return size >= 2 and word[size - 1] == word[size - 2] and
        !isVowel(word, size - 1) and !isVowel(word, size - 2);
}

fn endsCvc(word: []const u8) bool {
    const size = word.len;
    return size >= 3 and !isVowel(word, size - 3) and isVowel(word, size - 2) and
        !isVowel(word, size - 1) and std.mem.findScalar(u8, "wxy", word[size - 1]) == null;
}

fn always(_: []const u8) bool {
    return true;
}

fn measureAboveZero(remainder: []const u8) bool {
    return measure(remainder) > 0;
}

fn measureAboveOne(remainder: []const u8) bool {
    return measure(remainder) > 1;
}

fn ionCondition(remainder: []const u8) bool {
    return measure(remainder) > 1 and
        (std.mem.endsWith(u8, remainder, "s") or std.mem.endsWith(u8, remainder, "t"));
}

fn finalECondition(remainder: []const u8) bool {
    const value = measure(remainder);
    return value > 1 or (value == 1 and !endsCvc(remainder));
}

const Rule = struct { suffix: []const u8, replacement: []const u8, condition: Condition };

fn rulesWith(
    comptime condition: Condition,
    comptime replacements: []const [2][]const u8,
) [replacements.len]Rule {
    var rules: [replacements.len]Rule = undefined;
    for (replacements, &rules) |pair, *rule| {
        rule.* = .{ .suffix = pair[0], .replacement = pair[1], .condition = condition };
    }
    return rules;
}

fn step4Rules() [step_4_suffixes.len]Rule {
    var rules: [step_4_suffixes.len]Rule = undefined;
    for (step_4_suffixes, &rules) |suffix, *rule| {
        const condition = if (equal(suffix, "ion")) &ionCondition else &measureAboveOne;
        rule.* = .{ .suffix = suffix, .replacement = "", .condition = condition };
    }
    return rules;
}

const step_1a = rulesWith(always, &.{
    .{ "sses", "ss" }, .{ "ies", "i" }, .{ "ss", "ss" }, .{ "s", "" },
});
const step_1b = [_]Rule{
    .{ .suffix = "eed", .replacement = "ee", .condition = measureAboveZero },
    .{ .suffix = "ed", .replacement = "", .condition = hasVowel },
    .{ .suffix = "ing", .replacement = "", .condition = hasVowel },
};
const step_1c = [_]Rule{.{ .suffix = "y", .replacement = "i", .condition = hasVowel }};
const step_2 = rulesWith(measureAboveZero, &.{
    .{ "ational", "ate" }, .{ "tional", "tion" }, .{ "enci", "ence" },   .{ "anci", "ance" },
    .{ "izer", "ize" },    .{ "abli", "able" },   .{ "alli", "al" },     .{ "entli", "ent" },
    .{ "eli", "e" },       .{ "ousli", "ous" },   .{ "ization", "ize" }, .{ "ation", "ate" },
    .{ "ator", "ate" },    .{ "alism", "al" },    .{ "iveness", "ive" }, .{ "fulness", "ful" },
    .{ "ousness", "ous" }, .{ "aliti", "al" },    .{ "iviti", "ive" },   .{ "biliti", "ble" },
});
const step_3 = rulesWith(measureAboveZero, &.{
    .{ "icate", "ic" }, .{ "ative", "" }, .{ "alize", "al" }, .{ "iciti", "ic" },
    .{ "ical", "ic" },  .{ "ful", "" },   .{ "ness", "" },
});
const step_4 = step4Rules();
const step_5a = [_]Rule{.{ .suffix = "e", .replacement = "", .condition = finalECondition }};
const rule_tables = std.StaticStringMap([]const Rule).initComptime(.{
    .{ "1a", &step_1a }, .{ "1b", &step_1b }, .{ "1c", &step_1c }, .{ "2", &step_2 },
    .{ "3", &step_3 },   .{ "4", &step_4 },   .{ "5a", &step_5a },
});

const RuleOutcome = struct { word: []const u8, suffix: ?[]const u8 };

// Apply the rule with the longest matching suffix; return the word and the applied suffix.
fn applyRules(gpa: Allocator, word: []const u8, rules: []const Rule) Allocator.Error!RuleOutcome {
    var selected: ?Rule = null;
    for (rules) |rule| {
        const longer = selected == null or rule.suffix.len > selected.?.suffix.len;
        if (std.mem.endsWith(u8, word, rule.suffix) and longer) selected = rule;
    }
    const rule = selected orelse return .{ .word = word, .suffix = null };
    const remainder = word[0 .. word.len - rule.suffix.len];
    if (!rule.condition(remainder)) return .{ .word = word, .suffix = null };
    return .{
        .word = try std.mem.concat(gpa, u8, &.{ remainder, rule.replacement }),
        .suffix = rule.suffix,
    };
}

fn tidyStep1b(gpa: Allocator, word: []const u8) Allocator.Error![]const u8 {
    for ([_][]const u8{ "at", "bl", "iz" }) |suffix| {
        if (std.mem.endsWith(u8, word, suffix)) return std.mem.concat(gpa, u8, &.{ word, "e" });
    }
    if (endsDouble(word) and std.mem.findScalar(u8, "lsz", word[word.len - 1]) == null) {
        return word[0 .. word.len - 1];
    }
    if (measure(word) == 1 and endsCvc(word)) return std.mem.concat(gpa, u8, &.{ word, "e" });
    return word;
}

fn applyStep(gpa: Allocator, name: []const u8, word: []const u8) Allocator.Error![]const u8 {
    if (equal(name, "5b")) {
        if (measure(word) > 1 and endsDouble(word) and std.mem.endsWith(u8, word, "l")) {
            return word[0 .. word.len - 1];
        }
        return word;
    }
    const outcome = try applyRules(gpa, word, rule_tables.get(name).?);
    if (equal(name, "1b")) {
        if (outcome.suffix) |suffix| {
            if (equal(suffix, "ed") or equal(suffix, "ing")) return tidyStep1b(gpa, outcome.word);
        }
    }
    return outcome.word;
}

const StepChange = struct { step: []const u8, word: []const u8 };
const Stemming = struct { stem: []const u8, changes: []const StepChange };

fn stemmingSteps(gpa: Allocator, word: []const u8) Allocator.Error!Stemming {
    var changes: std.ArrayList(StepChange) = .empty;
    var current = word;
    if (word.len > 2) {
        for (step_names) |name| {
            const result = try applyStep(gpa, name, current);
            if (!equal(result, current)) try changes.append(gpa, .{ .step = name, .word = result });
            current = result;
        }
    }
    return .{ .stem = current, .changes = changes.items };
}

fn porterStem(gpa: Allocator, word: []const u8) Allocator.Error![]const u8 {
    return (try stemmingSteps(gpa, word)).stem;
}

fn increment(gpa: Allocator, counts: *Counts, key: []const u8, amount: usize) Allocator.Error!void {
    const entry = try counts.getOrPut(gpa, key);
    if (!entry.found_existing) entry.value_ptr.* = 0;
    entry.value_ptr.* += amount;
}

const StemCount = struct {
    stem: []const u8,
    count: usize,

    fn before(_: void, left: StemCount, right: StemCount) bool {
        if (left.count != right.count) return left.count > right.count;
        return lessThan({}, left.stem, right.stem);
    }
};

fn rankedCounts(gpa: Allocator, counts: Counts) Allocator.Error![]StemCount {
    var ranked: std.ArrayList(StemCount) = .empty;
    var entries = counts.iterator();
    while (entries.next()) |entry| {
        try ranked.append(gpa, .{ .stem = entry.key_ptr.*, .count = entry.value_ptr.* });
    }
    std.mem.sort(StemCount, ranked.items, {}, StemCount.before);
    return ranked.items;
}

fn sortedKeys(gpa: Allocator, map: anytype) Allocator.Error![]const []const u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try keys.append(gpa, key.*);
    std.mem.sort([]const u8, keys.items, {}, lessThan);
    return keys.items;
}

fn closestDistance(
    gpa: Allocator,
    positions: []const usize,
    others: []const usize,
    same_stem: bool,
) Allocator.Error!?usize {
    var gaps: std.ArrayList(usize) = .empty;
    if (same_stem) {
        var index: usize = 1;
        while (index < positions.len) : (index += 1) {
            try gaps.append(gpa, positions[index] - positions[index - 1]);
        }
    } else {
        // The closest pair of different stems is adjacent in the merged order.
        const Marker = struct {
            position: usize,
            source: u1,

            fn before(_: void, left: @This(), right: @This()) bool {
                return left.position < right.position;
            }
        };
        var merged: std.ArrayList(Marker) = .empty;
        for (positions) |position| try merged.append(gpa, .{ .position = position, .source = 0 });
        for (others) |other| try merged.append(gpa, .{ .position = other, .source = 1 });
        std.mem.sort(Marker, merged.items, {}, Marker.before);
        var index: usize = 1;
        while (index < merged.items.len) : (index += 1) {
            const earlier = merged.items[index - 1];
            const later = merged.items[index];
            if (earlier.source != later.source) try gaps.append(gpa, later.position - earlier.position);
        }
    }
    if (gaps.items.len == 0) return null;
    return std.mem.min(usize, gaps.items);
}

const Similarity = struct {
    number: usize,
    numerator: usize,
    denominator: usize,

    fn jaccard(number: usize, common: usize, total: usize) Similarity {
        if (total == 0) return .{ .number = number, .numerator = 0, .denominator = 1 };
        const divisor = std.math.gcd(common, total);
        return .{ .number = number, .numerator = common / divisor, .denominator = total / divisor };
    }

    fn before(_: void, left: Similarity, right: Similarity) bool {
        const left_score = left.numerator * right.denominator;
        const right_score = right.numerator * left.denominator;
        if (left_score != right_score) return left_score > right_score;
        return left.number < right.number;
    }
};

const Ranking = struct {
    number: usize,
    matched: usize,
    total: usize,

    fn before(_: void, left: Ranking, right: Ranking) bool {
        if (left.matched != right.matched) return left.matched > right.matched;
        if (left.total != right.total) return left.total > right.total;
        return left.number < right.number;
    }
};

const Token = struct {
    text: []const u8,
    form: []const u8,
    stem: []const u8,
    line: usize,
    position: usize,
    start: usize,

    fn end(token: Token) usize {
        return token.start + token.text.len;
    }
};

const Document = struct {
    number: usize,
    lines: std.ArrayList([]const u8) = .empty,
    tokens: std.ArrayList(Token) = .empty,

    fn addLine(document: *Document, gpa: Allocator, text: []const u8) Allocator.Error![]const Token {
        try document.lines.append(gpa, text);
        const first = document.tokens.items.len;
        var index: usize = 0;
        while (index < text.len) {
            if (!std.ascii.isAlphabetic(text[index])) {
                index += 1;
                continue;
            }
            const start = index;
            while (index < text.len and std.ascii.isAlphabetic(text[index])) index += 1;
            const form = try std.ascii.allocLowerString(gpa, text[start..index]);
            try document.tokens.append(gpa, .{
                .text = text[start..index],
                .form = form,
                .stem = try porterStem(gpa, form),
                .line = document.lines.items.len,
                .position = document.tokens.items.len + 1,
                .start = start,
            });
        }
        return document.tokens.items[first..];
    }

    fn lineTokens(
        document: *const Document,
        gpa: Allocator,
        line_number: usize,
    ) Allocator.Error![]const Token {
        var found: std.ArrayList(Token) = .empty;
        for (document.tokens.items) |token| {
            if (token.line == line_number) try found.append(gpa, token);
        }
        return found.items;
    }
};

const Occurrence = struct {
    document: *const Document,
    token: Token,

    pub fn format(occurrence: Occurrence, out: *Writer) Writer.Error!void {
        const token = occurrence.token;
        try out.print("{d}:{d}:{d}", .{ occurrence.document.number, token.line, token.position });
    }
};

const OccurrenceMap = std.StringHashMapUnmanaged(std.ArrayList(Occurrence));

fn documentCount(occurrences: []const Occurrence) usize {
    var count: usize = 0;
    for (occurrences, 0..) |occurrence, index| {
        if (index == 0 or occurrences[index - 1].document != occurrence.document) count += 1;
    }
    return count;
}

const Kind = enum { and_operator, or_operator, not_operator, open, close, term, prefix };
const symbols = std.StaticStringMap(Kind).initComptime(.{
    .{ "AND", .and_operator }, .{ "OR", .or_operator }, .{ "NOT", .not_operator },
    .{ "(", .open },           .{ ")", .close },
});
const QueryItem = struct { kind: Kind, spelling: []const u8 };
const QueryResult = struct { canonical: []const u8, documents: []bool };

fn lexemes(gpa: Allocator, expression: []const u8) Allocator.Error![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < expression.len) {
        switch (expression[index]) {
            ' ' => index += 1,
            '(', ')' => {
                try result.append(gpa, expression[index .. index + 1]);
                index += 1;
            },
            else => {
                const start = index;
                while (index < expression.len and
                    std.mem.findScalar(u8, " ()", expression[index]) == null) index += 1;
                try result.append(gpa, expression[start..index]);
            },
        }
    }
    return result.items;
}

fn hasPrefix(stems: WordSet, prefix: []const u8) bool {
    var keys = stems.keyIterator();
    while (keys.next()) |stem| {
        if (std.mem.startsWith(u8, stem.*, prefix)) return true;
    }
    return false;
}

const QueryParser = struct {
    engine: *Engine,
    items: []const QueryItem,
    stem_sets: []const WordSet,
    position: usize = 0,

    fn peek(parser: *const QueryParser) ?Kind {
        if (parser.position < parser.items.len) return parser.items[parser.position].kind;
        return null;
    }

    fn take(parser: *QueryParser) Error!QueryItem {
        if (parser.position >= parser.items.len) return parser.engine.fail("SYNTAX", .{});
        parser.position += 1;
        return parser.items[parser.position - 1];
    }

    fn parse(parser: *QueryParser) Error!QueryResult {
        const result = try parser.expression();
        if (parser.position < parser.items.len) return parser.engine.fail("SYNTAX", .{});
        return result;
    }

    fn expression(parser: *QueryParser) Error!QueryResult {
        var result = try parser.conjunction();
        while (parser.peek() == Kind.or_operator) {
            parser.position += 1;
            const right = try parser.conjunction();
            for (result.documents, right.documents) |*selected, other| selected.* = selected.* or other;
            result.canonical = try std.fmt.allocPrint(
                parser.engine.scratch,
                "({s} OR {s})",
                .{ result.canonical, right.canonical },
            );
        }
        return result;
    }

    fn conjunction(parser: *QueryParser) Error!QueryResult {
        var result = try parser.negation();
        while (parser.peek()) |kind| {
            switch (kind) {
                .and_operator, .not_operator, .open, .term, .prefix => {},
                .or_operator, .close => break,
            }
            if (kind == .and_operator) parser.position += 1;
            const right = try parser.negation();
            for (result.documents, right.documents) |*selected, other| selected.* = selected.* and other;
            result.canonical = try std.fmt.allocPrint(
                parser.engine.scratch,
                "({s} AND {s})",
                .{ result.canonical, right.canonical },
            );
        }
        return result;
    }

    fn negation(parser: *QueryParser) Error!QueryResult {
        if (parser.peek() != Kind.not_operator) return parser.element();
        parser.position += 1;
        const inner = try parser.negation();
        for (inner.documents) |*selected| selected.* = !selected.*;
        return .{
            .canonical = try std.fmt.allocPrint(parser.engine.scratch, "(NOT {s})", .{inner.canonical}),
            .documents = inner.documents,
        };
    }

    fn element(parser: *QueryParser) Error!QueryResult {
        const item = try parser.take();
        const scratch = parser.engine.scratch;
        switch (item.kind) {
            .open => {
                const result = try parser.expression();
                if ((try parser.take()).kind != .close) return parser.engine.fail("SYNTAX", .{});
                return result;
            },
            .term => {
                const stem = try porterStem(scratch, item.spelling);
                const documents = try scratch.alloc(bool, parser.stem_sets.len);
                for (parser.stem_sets, documents) |stems, *selected| selected.* = stems.contains(stem);
                return .{ .canonical = stem, .documents = documents };
            },
            .prefix => {
                const documents = try scratch.alloc(bool, parser.stem_sets.len);
                for (parser.stem_sets, documents) |stems, *selected| {
                    selected.* = hasPrefix(stems, item.spelling);
                }
                return .{
                    .canonical = try std.fmt.allocPrint(scratch, "{s}*", .{item.spelling}),
                    .documents = documents,
                };
            },
            .and_operator, .or_operator, .not_operator, .close => {
                return parser.engine.fail("SYNTAX", .{});
            },
        }
    }
};

const Command = enum {
    STEM,
    STEPS,
    MEASURE,
    INDEX,
    SEARCH,
    PHRASE,
    NEAR,
    TOP,
    KWIC,
    TF,
    DF,
    VARIANTS,
    SIMILAR,
    RANK,
    INFO,
    LINE,
    STATS,
    STOP,
    UNSTOP,
    APPEND,
    DELETE,

    fn arity(command: Command) struct { usize, usize } {
        return switch (command) {
            .STEM => .{ 1, 10 },
            .PHRASE => .{ 2, 10 },
            .RANK => .{ 2, 11 },
            .INDEX => .{ 0, 1 },
            .TOP => .{ 1, 2 },
            .STATS => .{ 0, 0 },
            .NEAR => .{ 3, 3 },
            .TF, .SIMILAR, .LINE, .APPEND => .{ 2, 2 },
            .STEPS, .MEASURE, .SEARCH, .KWIC, .DF, .VARIANTS, .INFO, .STOP, .UNSTOP, .DELETE => .{ 1, 1 },
        };
    }
};

fn splitArguments(gpa: Allocator, command: Command, rest: []const u8) Allocator.Error![]const []const u8 {
    switch (command) {
        .SEARCH => return gpa.dupe([]const u8, &.{rest}),
        .APPEND => {
            const space = std.mem.findScalar(u8, rest, ' ') orelse return gpa.dupe([]const u8, &.{rest});
            return gpa.dupe([]const u8, &.{ rest[0..space], rest[space + 1 ..] });
        },
        else => {
            var parts: std.ArrayList([]const u8) = .empty;
            var pieces = std.mem.splitScalar(u8, rest, ' ');
            while (pieces.next()) |piece| try parts.append(gpa, piece);
            return parts.items;
        },
    }
}

const Engine = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Writer,
    stopwords: WordSet = .empty,
    documents: std.ArrayList(*Document) = .empty,
    problem: []const u8 = "",

    fn fail(engine: *Engine, comptime pattern: []const u8, args: anytype) Error {
        engine.problem = std.fmt.allocPrint(engine.scratch, pattern, args) catch return error.OutOfMemory;
        return error.Invalid;
    }

    fn addDocument(engine: *Engine, number: usize) Allocator.Error!*Document {
        const document = try engine.gpa.create(Document);
        document.* = .{ .number = number };
        var index: usize = 0;
        while (index < engine.documents.items.len and engine.documents.items[index].number < number) {
            index += 1;
        }
        try engine.documents.insert(engine.gpa, index, document);
        return document;
    }

    fn findDocument(engine: *const Engine, number: usize) ?usize {
        for (engine.documents.items, 0..) |document, index| {
            if (document.number == number) return index;
        }
        return null;
    }

    fn isStopword(engine: *const Engine, word: []const u8) bool {
        return engine.stopwords.contains(word);
    }

    fn isIndexed(engine: *const Engine, token: Token) bool {
        return !engine.isStopword(token.form);
    }

    fn termFrequencies(engine: *const Engine, document: *const Document) Allocator.Error!Counts {
        var counts: Counts = .empty;
        for (document.tokens.items) |token| {
            if (engine.isIndexed(token)) try increment(engine.scratch, &counts, token.stem, 1);
        }
        return counts;
    }

    fn stemSet(engine: *const Engine, document: *const Document) Allocator.Error!WordSet {
        var stems: WordSet = .empty;
        for (document.tokens.items) |token| {
            if (engine.isIndexed(token)) try stems.put(engine.scratch, token.stem, {});
        }
        return stems;
    }

    fn totalFrequencies(engine: *const Engine) Allocator.Error!Counts {
        var totals: Counts = .empty;
        for (engine.documents.items) |document| {
            const counts = try engine.termFrequencies(document);
            var entries = counts.iterator();
            while (entries.next()) |entry| {
                try increment(engine.scratch, &totals, entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        return totals;
    }

    fn occurrenceMap(engine: *const Engine) Allocator.Error!OccurrenceMap {
        var occurrences: OccurrenceMap = .empty;
        for (engine.documents.items) |document| {
            for (document.tokens.items) |token| {
                if (!engine.isIndexed(token)) continue;
                const entry = try occurrences.getOrPut(engine.scratch, token.stem);
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                try entry.value_ptr.append(engine.scratch, .{ .document = document, .token = token });
            }
        }
        return occurrences;
    }

    fn occurrencesOf(engine: *const Engine, stem: []const u8) Allocator.Error![]const Occurrence {
        const occurrences = try engine.occurrenceMap();
        return if (occurrences.get(stem)) |found| found.items else &.{};
    }

    fn stemPositions(
        engine: *const Engine,
        document: *const Document,
        stem: []const u8,
    ) Allocator.Error![]const usize {
        var positions: std.ArrayList(usize) = .empty;
        for (document.tokens.items) |token| {
            if (engine.isIndexed(token) and equal(token.stem, stem)) {
                try positions.append(engine.scratch, token.position);
            }
        }
        return positions.items;
    }

    fn formCount(engine: *const Engine, form: []const u8) usize {
        var count: usize = 0;
        for (engine.documents.items) |document| {
            for (document.tokens.items) |token| {
                if (equal(token.form, form)) count += 1;
            }
        }
        return count;
    }

    fn tokenMatches(engine: *const Engine, token: Token, target: []const u8) bool {
        return equal(target, "?") or (engine.isIndexed(token) and equal(token.stem, target));
    }

    fn phraseMatches(engine: *const Engine, tokens: []const Token, targets: []const []const u8) bool {
        for (tokens, targets) |token, target| {
            if (!engine.tokenMatches(token, target)) return false;
        }
        return true;
    }

    fn describeToken(engine: *const Engine, token: Token) Writer.Error!void {
        if (engine.isIndexed(token)) {
            try engine.out.print(" {s}/{s}", .{ token.form, token.stem });
        } else {
            try engine.out.print(" {s}/-", .{token.form});
        }
    }

    fn wordArgument(engine: *Engine, text: []const u8) Error![]const u8 {
        if (!isWord(text)) return engine.fail("BAD WORD {s}", .{text});
        return std.ascii.allocLowerString(engine.scratch, text);
    }

    fn numberArgument(engine: *Engine, text: []const u8, minimum: usize, maximum: usize) Error!usize {
        if (!isNumber(text)) return engine.fail("BAD NUMBER {s}", .{text});
        const value = std.fmt.parseInt(usize, text, 10) catch unreachable;
        if (value < minimum or value > maximum) return engine.fail("BAD NUMBER {s}", .{text});
        return value;
    }

    fn termArgument(engine: *Engine, text: []const u8) Error![]const u8 {
        const word = try engine.wordArgument(text);
        if (engine.isStopword(word)) return engine.fail("STOPWORD {s}", .{word});
        return porterStem(engine.scratch, word);
    }

    fn documentArgument(engine: *Engine, text: []const u8) Error!*Document {
        const number = try engine.numberArgument(text, 1, max_document_number);
        const index = engine.findDocument(number) orelse return engine.fail("NO DOC {d}", .{number});
        return engine.documents.items[index];
    }

    fn stemWords(engine: *Engine, arguments: []const []const u8) Error!void {
        const words = try engine.scratch.alloc([]const u8, arguments.len);
        for (arguments, words) |argument, *word| word.* = try engine.wordArgument(argument);
        try engine.out.writeAll("STEM");
        for (words) |word| {
            try engine.out.print(" {s}:{s}", .{ word, try porterStem(engine.scratch, word) });
        }
        try engine.out.writeByte('\n');
    }

    fn showSteps(engine: *Engine, arguments: []const []const u8) Error!void {
        const word = try engine.wordArgument(arguments[0]);
        const stemming = try stemmingSteps(engine.scratch, word);
        try engine.out.print("STEPS {s}", .{word});
        if (stemming.changes.len == 0) try engine.out.writeAll(" NONE");
        for (stemming.changes) |change| try engine.out.print(" {s}:{s}", .{ change.step, change.word });
        try engine.out.writeByte('\n');
    }

    fn showMeasure(engine: *Engine, arguments: []const []const u8) Error!void {
        const word = try engine.wordArgument(arguments[0]);
        try printLine(engine.out, "MEASURE {s} {s} m={d} vowel={s} double={s} cvc={s}", .{
            word,                  try letterPattern(engine.scratch, word), measure(word),
            yesNo(hasVowel(word)), yesNo(endsDouble(word)),                 yesNo(endsCvc(word)),
        });
    }

    fn showIndex(engine: *Engine, arguments: []const []const u8) Error!void {
        const prefix = if (arguments.len == 1) try engine.wordArgument(arguments[0]) else "";
        const occurrences = try engine.occurrenceMap();
        var stems: std.ArrayList([]const u8) = .empty;
        for (try sortedKeys(engine.scratch, occurrences)) |stem| {
            if (std.mem.startsWith(u8, stem, prefix)) try stems.append(engine.scratch, stem);
        }
        try printLine(engine.out, "INDEX stems={d}", .{stems.items.len});
        for (stems.items) |stem| {
            const found = occurrences.get(stem).?.items;
            try engine.out.print("{s} df={d}", .{ stem, documentCount(found) });
            for (found) |occurrence| try engine.out.print(" {f}", .{occurrence});
            try engine.out.writeByte('\n');
        }
    }

    fn search(engine: *Engine, arguments: []const []const u8) Error!void {
        var items: std.ArrayList(QueryItem) = .empty;
        for (try lexemes(engine.scratch, arguments[0])) |lexeme| {
            if (symbols.get(lexeme)) |kind| {
                try items.append(engine.scratch, .{ .kind = kind, .spelling = lexeme });
            } else if (isWord(lexeme)) {
                const spelling = try std.ascii.allocLowerString(engine.scratch, lexeme);
                try items.append(engine.scratch, .{ .kind = .term, .spelling = spelling });
            } else if (std.mem.endsWith(u8, lexeme, "*") and isWord(lexeme[0 .. lexeme.len - 1])) {
                const spelling = try std.ascii.allocLowerString(engine.scratch, lexeme[0 .. lexeme.len - 1]);
                try items.append(engine.scratch, .{ .kind = .prefix, .spelling = spelling });
            } else {
                return engine.fail("BAD TERM {s}", .{lexeme});
            }
        }
        const stem_sets = try engine.scratch.alloc(WordSet, engine.documents.items.len);
        for (engine.documents.items, stem_sets) |document, *stems| stems.* = try engine.stemSet(document);
        var parser: QueryParser = .{ .engine = engine, .items = items.items, .stem_sets = stem_sets };
        const result = try parser.parse();
        for (items.items) |item| {
            if (item.kind == .term and engine.isStopword(item.spelling)) {
                return engine.fail("STOPWORD {s}", .{item.spelling});
            }
        }
        const count = std.mem.count(bool, result.documents, &.{true});
        try engine.out.print("SEARCH {s} count={d}", .{ result.canonical, count });
        for (engine.documents.items, result.documents) |document, selected| {
            if (selected) try engine.out.print(" {d}", .{document.number});
        }
        try engine.out.writeByte('\n');
    }

    fn phrase(engine: *Engine, arguments: []const []const u8) Error!void {
        const words = try engine.scratch.alloc([]const u8, arguments.len);
        for (arguments, words) |argument, *word| word.* = try engine.wordArgument(argument);
        var only_stopwords = true;
        for (words) |word| {
            if (!engine.isStopword(word)) only_stopwords = false;
        }
        if (only_stopwords) return engine.fail("STOPWORDS ONLY", .{});
        const targets = try engine.scratch.alloc([]const u8, words.len);
        for (words, targets) |word, *target| {
            target.* = if (engine.isStopword(word)) "?" else try porterStem(engine.scratch, word);
        }
        var matches: std.ArrayList(Occurrence) = .empty;
        for (engine.documents.items) |document| {
            const tokens = document.tokens.items;
            if (tokens.len < targets.len) continue;
            for (0..tokens.len - targets.len + 1) |start| {
                if (engine.phraseMatches(tokens[start..][0..targets.len], targets)) {
                    try matches.append(engine.scratch, .{ .document = document, .token = tokens[start] });
                }
            }
        }
        const phrase_text = try std.mem.join(engine.scratch, " ", targets);
        try engine.out.print("PHRASE \"{s}\" matches={d}", .{ phrase_text, matches.items.len });
        for (matches.items) |occurrence| try engine.out.print(" {f}", .{occurrence});
        try engine.out.writeByte('\n');
    }

    fn near(engine: *Engine, arguments: []const []const u8) Error!void {
        const first = try engine.termArgument(arguments[0]);
        const second = try engine.termArgument(arguments[1]);
        const limit = try engine.numberArgument(arguments[2], 1, max_count);
        const Found = struct { number: usize, distance: usize };
        var found: std.ArrayList(Found) = .empty;
        for (engine.documents.items) |document| {
            const positions = try engine.stemPositions(document, first);
            const others = try engine.stemPositions(document, second);
            const distance = try closestDistance(engine.scratch, positions, others, equal(first, second));
            if (distance != null and distance.? <= limit) {
                try found.append(engine.scratch, .{ .number = document.number, .distance = distance.? });
            }
        }
        try engine.out.print("NEAR {s} {s} {d} count={d}", .{ first, second, limit, found.items.len });
        for (found.items) |entry| try engine.out.print(" {d}:{d}", .{ entry.number, entry.distance });
        try engine.out.writeByte('\n');
    }

    fn top(engine: *Engine, arguments: []const []const u8) Error!void {
        const limit = try engine.numberArgument(arguments[0], 1, max_count);
        const document = if (arguments.len == 2) try engine.documentArgument(arguments[1]) else null;
        const counts = if (document) |chosen|
            try engine.termFrequencies(chosen)
        else
            try engine.totalFrequencies();
        const ranked = try rankedCounts(engine.scratch, counts);
        try engine.out.print("TOP {d}", .{limit});
        if (document) |chosen| try engine.out.print(" doc={d}", .{chosen.number});
        for (ranked[0..@min(limit, ranked.len)]) |entry| {
            try engine.out.print(" {s}:{d}", .{ entry.stem, entry.count });
        }
        try engine.out.writeByte('\n');
    }

    fn kwic(engine: *Engine, arguments: []const []const u8) Error!void {
        const stem = try engine.termArgument(arguments[0]);
        const found = try engine.occurrencesOf(stem);
        try printLine(engine.out, "KWIC {s} count={d}", .{ stem, found.len });
        for (found) |occurrence| {
            const token = occurrence.token;
            const text = occurrence.document.lines.items[token.line - 1];
            const before = text[token.start -| kwic_width..token.start];
            const after = text[token.end()..@min(text.len, token.end() + kwic_width)];
            try engine.out.writeByte('|');
            try engine.out.splatByteAll(' ', kwic_width - before.len);
            try engine.out.print("{s}[{s}]{s}", .{ before, token.text, after });
            try engine.out.splatByteAll(' ', kwic_width - after.len);
            try printLine(engine.out, "| {f}", .{occurrence});
        }
    }

    fn termFrequency(engine: *Engine, arguments: []const []const u8) Error!void {
        const document = try engine.documentArgument(arguments[0]);
        const stem = try engine.termArgument(arguments[1]);
        const count = (try engine.termFrequencies(document)).get(stem) orelse 0;
        try printLine(engine.out, "TF {d} {s} {d}", .{ document.number, stem, count });
    }

    fn documentFrequency(engine: *Engine, arguments: []const []const u8) Error!void {
        const stem = try engine.termArgument(arguments[0]);
        const found = try engine.occurrencesOf(stem);
        try printLine(engine.out, "DF {s} {d}", .{ stem, documentCount(found) });
    }

    fn variants(engine: *Engine, arguments: []const []const u8) Error!void {
        const stem = try engine.termArgument(arguments[0]);
        var forms: Counts = .empty;
        for (try engine.occurrencesOf(stem)) |occurrence| {
            try increment(engine.scratch, &forms, occurrence.token.form, 1);
        }
        try engine.out.print("VARIANTS {s} count={d}", .{ stem, forms.count() });
        for (try sortedKeys(engine.scratch, forms)) |form| {
            try engine.out.print(" {s}:{d}", .{ form, forms.get(form).? });
        }
        try engine.out.writeByte('\n');
    }

    fn similar(engine: *Engine, arguments: []const []const u8) Error!void {
        const document = try engine.documentArgument(arguments[0]);
        const limit = try engine.numberArgument(arguments[1], 1, max_count);
        const stems = try engine.stemSet(document);
        var scores: std.ArrayList(Similarity) = .empty;
        for (engine.documents.items) |other| {
            if (other == document) continue;
            const other_stems = try engine.stemSet(other);
            var common: usize = 0;
            var keys = stems.keyIterator();
            while (keys.next()) |stem| {
                if (other_stems.contains(stem.*)) common += 1;
            }
            const union_size = stems.count() + other_stems.count() - common;
            try scores.append(engine.scratch, Similarity.jaccard(other.number, common, union_size));
        }
        std.mem.sort(Similarity, scores.items, {}, Similarity.before);
        try engine.out.print("SIMILAR {d}", .{document.number});
        for (scores.items[0..@min(limit, scores.items.len)]) |score| {
            try engine.out.print(" {d}:{d}/{d}", .{ score.number, score.numerator, score.denominator });
        }
        try engine.out.writeByte('\n');
    }

    fn rank(engine: *Engine, arguments: []const []const u8) Error!void {
        const limit = try engine.numberArgument(arguments[0], 1, max_count);
        var query: WordSet = .empty;
        for (arguments[1..]) |argument| try query.put(engine.scratch, try engine.termArgument(argument), {});
        var ranked: std.ArrayList(Ranking) = .empty;
        for (engine.documents.items) |document| {
            const counts = try engine.termFrequencies(document);
            var matched: usize = 0;
            var total: usize = 0;
            var stems = query.keyIterator();
            while (stems.next()) |stem| {
                const count = counts.get(stem.*) orelse 0;
                if (count > 0) matched += 1;
                total += count;
            }
            if (matched > 0) {
                try ranked.append(engine.scratch, .{
                    .number = document.number,
                    .matched = matched,
                    .total = total,
                });
            }
        }
        std.mem.sort(Ranking, ranked.items, {}, Ranking.before);
        try engine.out.print("RANK count={d}", .{ranked.items.len});
        for (ranked.items[0..@min(limit, ranked.items.len)]) |entry| {
            try engine.out.print(" {d}:{d}:{d}", .{ entry.number, entry.matched, entry.total });
        }
        try engine.out.writeByte('\n');
    }

    fn info(engine: *Engine, arguments: []const []const u8) Error!void {
        const document = try engine.documentArgument(arguments[0]);
        const ranked = try rankedCounts(engine.scratch, try engine.termFrequencies(document));
        var indexed: usize = 0;
        for (ranked) |entry| indexed += entry.count;
        try engine.out.print("INFO {d} lines={d} tokens={d} indexed={d} stems={d} top=", .{
            document.number, document.lines.items.len, document.tokens.items.len, indexed, ranked.len,
        });
        if (ranked.len == 0) {
            try engine.out.writeAll("-\n");
        } else {
            try printLine(engine.out, "{s}:{d}", .{ ranked[0].stem, ranked[0].count });
        }
    }

    fn showLine(engine: *Engine, arguments: []const []const u8) Error!void {
        const document = try engine.documentArgument(arguments[0]);
        const line_number = try engine.numberArgument(arguments[1], 1, max_line_number);
        if (line_number > document.lines.items.len) {
            return engine.fail("NO LINE {d}:{d}", .{ document.number, line_number });
        }
        const tokens = try document.lineTokens(engine.scratch, line_number);
        try engine.out.print("LINE {d}:{d} tokens={d}", .{ document.number, line_number, tokens.len });
        for (tokens) |token| try engine.describeToken(token);
        try engine.out.writeByte('\n');
    }

    fn stats(engine: *Engine, _: []const []const u8) Error!void {
        var lines: usize = 0;
        var tokens: usize = 0;
        var indexed: usize = 0;
        for (engine.documents.items) |document| {
            lines += document.lines.items.len;
            tokens += document.tokens.items.len;
            for (document.tokens.items) |token| {
                if (engine.isIndexed(token)) indexed += 1;
            }
        }
        const stems = (try engine.totalFrequencies()).count();
        const pattern = "STATS docs={d} lines={d} tokens={d} indexed={d} stems={d} stopwords={d}";
        try printLine(engine.out, pattern, .{
            engine.documents.items.len, lines, tokens, indexed, stems, engine.stopwords.count(),
        });
    }

    fn stop(engine: *Engine, arguments: []const []const u8) Error!void {
        const word = try engine.wordArgument(arguments[0]);
        if (engine.isStopword(word)) return engine.fail("ALREADY STOPWORD {s}", .{word});
        try engine.stopwords.put(engine.gpa, try engine.gpa.dupe(u8, word), {});
        try printLine(engine.out, "STOP {s} unindexed={d}", .{ word, engine.formCount(word) });
    }

    fn unstop(engine: *Engine, arguments: []const []const u8) Error!void {
        const word = try engine.wordArgument(arguments[0]);
        if (!engine.isStopword(word)) return engine.fail("NOT STOPWORD {s}", .{word});
        _ = engine.stopwords.remove(word);
        try printLine(engine.out, "UNSTOP {s} indexed={d}", .{ word, engine.formCount(word) });
    }

    fn append(engine: *Engine, arguments: []const []const u8) Error!void {
        const number = try engine.numberArgument(arguments[0], 1, max_document_number);
        const existing = engine.findDocument(number);
        const document = if (existing) |index|
            engine.documents.items[index]
        else
            try engine.addDocument(number);
        const tokens = try document.addLine(engine.gpa, arguments[1]);
        var indexed: usize = 0;
        for (tokens) |token| {
            if (engine.isIndexed(token)) indexed += 1;
        }
        try printLine(engine.out, "APPEND {d} line={d} tokens={d} indexed={d} new={s}", .{
            number, document.lines.items.len, tokens.len, indexed, yesNo(existing == null),
        });
    }

    fn delete(engine: *Engine, arguments: []const []const u8) Error!void {
        const document = try engine.documentArgument(arguments[0]);
        _ = engine.documents.orderedRemove(engine.findDocument(document.number).?);
        try printLine(engine.out, "DELETE {d} lines={d} tokens={d}", .{
            document.number, document.lines.items.len, document.tokens.items.len,
        });
    }

    fn execute(engine: *Engine, line: []const u8) Error!void {
        const space = std.mem.findScalar(u8, line, ' ');
        const name = line[0 .. space orelse line.len];
        const command = std.meta.stringToEnum(Command, name) orelse
            return engine.fail("UNKNOWN COMMAND {s}", .{name});
        const arguments: []const []const u8 = if (space) |index|
            try splitArguments(engine.scratch, command, line[index + 1 ..])
        else
            &.{};
        const minimum, const maximum = command.arity();
        if (arguments.len < minimum or arguments.len > maximum) {
            return engine.fail("BAD ARGUMENTS {s}", .{name});
        }
        switch (command) {
            .STEM => try engine.stemWords(arguments),
            .STEPS => try engine.showSteps(arguments),
            .MEASURE => try engine.showMeasure(arguments),
            .INDEX => try engine.showIndex(arguments),
            .SEARCH => try engine.search(arguments),
            .PHRASE => try engine.phrase(arguments),
            .NEAR => try engine.near(arguments),
            .TOP => try engine.top(arguments),
            .KWIC => try engine.kwic(arguments),
            .TF => try engine.termFrequency(arguments),
            .DF => try engine.documentFrequency(arguments),
            .VARIANTS => try engine.variants(arguments),
            .SIMILAR => try engine.similar(arguments),
            .RANK => try engine.rank(arguments),
            .INFO => try engine.info(arguments),
            .LINE => try engine.showLine(arguments),
            .STATS => try engine.stats(arguments),
            .STOP => try engine.stop(arguments),
            .UNSTOP => try engine.unstop(arguments),
            .APPEND => try engine.append(arguments),
            .DELETE => try engine.delete(arguments),
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.splitScalar(u8, text, '\n');
    while (pieces.next()) |piece| try lines.append(gpa, piece);

    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var engine: Engine = .{ .gpa = gpa, .scratch = scratch.allocator(), .out = &output.interface };
    var stopwords = std.mem.tokenizeScalar(u8, lines.items[0], ' ');
    _ = stopwords.next();
    while (stopwords.next()) |word| try engine.stopwords.put(gpa, word, {});
    var index: usize = 1;
    while (std.mem.startsWith(u8, lines.items[index], "DOC ")) : (index += 1) {
        const document = try engine.addDocument(try std.fmt.parseInt(usize, lines.items[index][4..], 10));
        index += 1;
        while (!equal(lines.items[index], "ENDDOC")) : (index += 1) {
            _ = try document.addLine(gpa, lines.items[index]);
        }
    }
    for (lines.items[index..]) |line| {
        if (equal(line, "END")) break;
        _ = scratch.reset(.retain_capacity);
        engine.execute(line) catch |err| {
            if (err != error.Invalid) return err;
            try printLine(&output.interface, "ERROR {s}", .{engine.problem});
        };
    }
    try output.interface.flush();
}
