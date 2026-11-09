const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
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
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}
pub const Sequence = []const []const u8;
pub const Alternatives = std.ArrayList(Sequence);
pub const Rule = struct { name: []const u8, alternatives: Alternatives = .empty };
pub const Grammar = struct {
    rules: std.ArrayList(Rule) = .empty,
    start: []const u8 = "",
    pub fn index(self: Grammar, name: []const u8) ?usize {
        for (self.rules.items, 0..) |rule, i| if (eq(rule.name, name)) return i;
        return null;
    }
    pub fn insert(self: *Grammar, rule: Rule, position: usize) void {
        append(Rule, &self.rules, rule);
        var i = self.rules.items.len - 1;
        while (i > position) : (i -= 1) self.rules.items[i] = self.rules.items[i - 1];
        self.rules.items[position] = rule;
    }
    pub fn clone(self: Grammar) Grammar {
        var out: Grammar = .{ .start = self.start };
        for (self.rules.items) |rule| append(Rule, &out.rules, rule);
        return out;
    }
};
pub const Set = std.ArrayList([]const u8);
pub fn has(values: Sequence, value: []const u8) bool {
    for (values) |entry| if (eq(entry, value)) return true;
    return false;
}
pub fn addUnique(values: *Set, value: []const u8) bool {
    if (has(values.items, value)) return false;
    append([]const u8, values, value);
    return true;
}
pub fn nonterminal(symbol: []const u8) bool {
    return symbol.len >= 2 and symbol[0] == '<' and symbol[symbol.len - 1] == '>';
}
pub fn notation(sequence: Sequence) []const u8 {
    if (sequence.len == 0) return "%empty";
    var out: Text = .{};
    for (sequence, 0..) |symbol, i| out.add("{s}{s}", .{ if (i == 0) "" else " ", symbol });
    return out.value();
}
pub fn productionText(lhs: []const u8, rhs: Sequence) []const u8 {
    return fmt("{s} -> {s}", .{ lhs, notation(rhs) });
}
pub fn sameSequence(a: Sequence, b: Sequence) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!eq(x, y)) return false;
    return true;
}
pub fn concat(a: Sequence, b: Sequence) Sequence {
    const out = alloc([]const u8, a.len + b.len);
    @memcpy(out[0..a.len], a);
    @memcpy(out[a.len..], b);
    return out;
}
pub fn alternativeUnique(values: *Alternatives, value: Sequence) void {
    for (values.items) |entry| if (sameSequence(entry, value)) return;
    append(Sequence, values, value);
}
pub fn terminalLess(_: void, a: []const u8, b: []const u8) bool {
    if (eq(a, "$")) return false;
    if (eq(b, "$")) return true;
    return std.mem.lessThan(u8, a, b);
}
pub fn sorted(values: Sequence) Sequence {
    const out = dupe([]const u8, values);
    std.mem.sort([]const u8, out, {}, terminalLess);
    return out;
}
pub const Occurrence = struct { name: []const u8, line: usize };
pub const Parsed = struct { grammar: Grammar = .{}, diagnostics: Lines = .{}, declarations: bool = false,
     declared: Set = .empty, word_first: std.ArrayList(Occurrence) = .empty };
const Kind = enum { nt, word, quoted, definition, bar, start, declaration, empty, invalid };
const Token = struct { kind: Kind, text: []const u8 = "", start: usize, end: usize };
fn letter(character: u8) bool {
    return (character >= 'A' and character <= 'Z') or (character >= 'a' and character <= 'z');
}
fn wordCharacter(character: u8) bool {
    return letter(character) or (character >= '0' and character <= '9') or character == '_';
}
fn lex(line: []const u8) []const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == ' ') {
            i += 1;
            continue;
        }
        if (line[i] == '#') break;
        const start = i;
        var token: Token = .{ .kind = .invalid, .start = start + 1, .end = start + 1 };
        if (line[i] == '<') {
            var j = i + 1;
            if (j < line.len and letter(line[j])) {
                j += 1;
                while (j < line.len and wordCharacter(line[j])) j += 1;
                if (j < line.len and line[j] == '>') {
                    i = j + 1;
                    token.kind = .nt;
                    token.text = line[start..i];
                }
            }
        } else if (line[i] == '"') {
            var j = i + 1;
            while (j < line.len and line[j] != ' ' and line[j] != '"') j += 1;
            if (j > i + 1 and j < line.len and line[j] == '"') {
                token.kind = .quoted;
                token.text = line[i + 1 .. j];
                i = j + 1;
            }
        } else if (letter(line[i])) {
            i += 1;
            while (i < line.len and wordCharacter(line[i])) i += 1;
            token.kind = .word;
            token.text = line[start..i];
        } else if (std.mem.startsWith(u8, line[i..], "::=")) {
            token.kind = .definition;
            token.text = "::=";
            i += 3;
        } else if (line[i] == '|') {
            token.kind = .bar;
            token.text = "|";
            i += 1;
        } else if (line[i] == '%') {
            var j = i + 1;
            while (j < line.len and letter(line[j])) j += 1;
            const directive = line[i + 1 .. j];
            if (eq(directive, "empty") or eq(directive, "start") or eq(directive, "token")) {
                token.kind = if (eq(directive, "empty")) Kind.empty else if (eq(directive, "start")) Kind.start else Kind.declaration;
                token.text = line[i..j];
                i = j;
            }
        }
        if (token.kind != .invalid) token.end = i;
        append(Token, &out, token);
        if (token.kind == .invalid) break;
    }
    return out.items;
}
fn transition(state: usize, kind: Kind) ?usize {
    return switch (state) {
        0 => switch (kind) {
            .nt => 1,
            .bar => 2,
            .start => 5,
            .declaration => 7,
            else => null,
        },
        1 => if (kind == .definition) 2 else null,
        2 => switch (kind) {
            .nt, .word, .quoted => 3,
            .empty => 4,
            else => null,
        },
        3 => switch (kind) {
            .nt, .word, .quoted => 3,
            .bar => 2,
            else => null,
        },
        4 => if (kind == .bar) 2 else null,
        5 => if (kind == .nt) 6 else null,
        7, 8 => if (kind == .word) 8 else null,
        else => null,
    };
}
fn appendAlternative(out: *Parsed, lhs: usize, alternative: Sequence, line: usize) void {
    const rule = &out.grammar.rules.items[lhs];
    for (rule.alternatives.items) |entry| if (sameSequence(entry, alternative)) {
        out.diagnostics.add("line {d}: duplicate alternative {s}", .{ line, productionText(rule.name, alternative) });
        return;
    };
    append(Sequence, &rule.alternatives, alternative);
}
pub fn readGrammar(lines: Sequence) Parsed {
    var out: Parsed = .{};
    var attached: ?[]const u8 = null;
    var start_seen = false;
    for (lines, 1..) |line, line_number| {
        const tokens = lex(line);
        if (tokens.len == 0) continue;
        var state: usize = 0;
        var column: ?usize = null;
        for (tokens) |token| {
            state = transition(state, token.kind) orelse {
                column = token.start;
                break;
            };
        }
        if (column == null and state != 3 and state != 4 and state != 6 and state != 8) column = tokens[tokens.len - 1].end + 1;
        if (column) |position| {
            out.diagnostics.add("line {d}: syntax error at column {d}", .{ line_number, position });
            attached = null;
            continue;
        }
        const first = tokens[0].kind;
        if (first == .start) {
            if (start_seen) out.diagnostics.add("line {d}: duplicate %start", .{line_number}) else {
                out.grammar.start = tokens[1].text;
                start_seen = true;
            }
            attached = null;
            continue;
        }
        if (first == .declaration) {
            out.declarations = true;
            for (tokens[1..]) |token| _ = addUnique(&out.declared, token.text);
            attached = null;
            continue;
        }
        var begin: usize = 0;
        if (first == .nt) {
            attached = tokens[0].text;
            if (out.grammar.index(attached.?) == null) append(Rule, &out.grammar.rules, .{ .name = attached.? });
            begin = 2;
        } else {
            if (attached == null) {
                out.diagnostics.add("line {d}: continuation without a rule", .{line_number});
                continue;
            }
            begin = 1;
        }
        const lhs = out.grammar.index(attached.?).?;
        var alternative: std.ArrayList([]const u8) = .empty;
        for (tokens[begin..]) |token| {
            if (token.kind == .bar) {
                appendAlternative(&out, lhs, alternative.items, line_number);
                alternative = .empty;
                continue;
            }
            if (token.kind == .word) {
                var known = false;
                for (out.word_first.items) |occurrence| if (eq(occurrence.name, token.text)) {
                    known = true;
                };
                if (!known) append(Occurrence, &out.word_first, .{ .name = token.text, .line = line_number });
            }
            if (token.kind != .empty) append([]const u8, &alternative, token.text);
        }
        appendAlternative(&out, lhs, alternative.items, line_number);
    }
    if (!start_seen) out.grammar.start = out.grammar.rules.items[0].name;
    return out;
}
