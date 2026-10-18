const std = @import("std");

const Allocator = std.mem.Allocator;
const CommandError = error{ BadCommand } || Allocator.Error || std.Io.Writer.Error;
const systems = [_][]const u8{ "HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO" };
const row_names = [_][]const u8{
    "a",
    "ka",
    "sa",
    "ta",
    "na",
    "ha",
    "ma",
    "ya",
    "ra",
    "wa",
    "ga",
    "za",
    "da",
    "ba",
    "pa"
};
const base_rows = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 5, 5 };
const row_text = [_][]const u8{
    "a i u e o",
    "ka ki ku ke ko",
    "sa si su se so",
    "ta ti tu te to",
    "na ni nu ne no",
    "ha hi hu he ho",
    "ma mi mu me mo",
    "ya yu yo",
    "ra ri ru re ro",
    "wa wi we wo",
    "ga gi gu ge go",
    "za zi zu ze zo",
    "da di du de do",
    "ba bi bu be bo",
    "pa pi pu pe po",
};
const iroha_text = "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N";
const mora_n: usize = 108;
const mora_q: usize = 109;
const mora_l: usize = 110;
const Syllable = struct {
    id: []const u8,
    row: usize,
    dan: []const u8
};

const Mora = struct {
    id: usize,
    column: usize
};

const Element = struct {
    base: usize,
    voice: usize,
    size: usize
};

const Word = struct {
    original: []const u8,
    start: usize,
    end: usize,
    ordinal: usize,
    pattern: usize = 0,
    morae: []Mora = &.{},
    elements: []Element = &.{},
    sort_key: [4][]usize = undefined,
};

const Match = struct {
    id: usize,
    len: usize
};

fn choice(value: []const u8, values: []const []const u8) ?usize {
    for (values, 0..) |candidate, i| {
        if (std.mem.eql(u8, value, candidate))
            return i;
    }
    return null;
}

fn wordCharacter(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '\'' or c == '-';
}

fn vowel(c: u8) bool {
    return c != 0 and std.mem.findScalar(u8, "aiueo", c) != null;
}

fn hasWord(text: []const u8) bool {
    for (text) |c| {
        if (wordCharacter(c))
            return true;
    }
    return false;
}

fn equalMorae(a: []const Mora, b: []const Mora) bool {
    if (a.len != b.len)
        return false;
    for (a, b) |x, y| {
        if (x.id != y.id)
            return false;
    }
    return true;
}

fn spelling(gpa: Allocator, id: []const u8, system: usize) Allocator.Error![]const u8 {
    if (system == 3)
        return id;
    if (system == 2) {
        const from = [_][]const u8{ "di", "du", "wi", "we", "wo", "dya", "dyu", "dyo" };
        const to = [_][]const u8{ "zi", "zu", "i", "e", "o", "zya", "zyu", "zyo" };
        if (choice(id, &from)) |i|
            return to[i];
        return id;
    }
    const common = [_][]const u8{ "si", "ti", "tu", "hu", "zi" };
    const replacements = [_][]const u8{ "shi", "chi", "tsu", "fu", "ji" };
    if (choice(id, &common)) |i|
        return replacements[i];
    const hepburn = system == 0 or system == 1;
    if (hepburn) {
        const from = [_][]const u8{ "di", "du", "wi", "we", "wo" };
        const to = [_][]const u8{ "ji", "zu", "i", "e", "o" };
        if (choice(id, &from)) |i|
            return to[i];
    }
    if (id.len == 3) {
        const prefix = id[0..2];
        if (std.mem.eql(u8, prefix, "sy"))
            return std.fmt.allocPrint(gpa, "sh{s}", .{ id[2..] });
        if (std.mem.eql(u8, prefix, "ty"))
            return std.fmt.allocPrint(gpa, "ch{s}", .{ id[2..] });
        if (std.mem.eql(u8, prefix, "zy") or (hepburn and std.mem.eql(u8, prefix, "dy")))
            return std.fmt.allocPrint(gpa, "j{s}", .{ id[2..] });
    }
    return id;
}

fn tokenizeWords(gpa: Allocator, text: []const u8) Allocator.Error![]Word {
    var result: std.ArrayList(Word) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (!wordCharacter(text[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < text.len and wordCharacter(text[i]))
            i += 1;
        try result.append(gpa, .{
            .original = text[start..i],
            .start = start,
            .end = i,
            .ordinal = result.items.len
        });
    }
    return result.items;
}

const Engine = struct {
    table: [108]Syllable = undefined,
    spellings: [5][108][]const u8 = undefined,
    iroha_rank: [48]usize = undefined,
    long_mode: usize = 0,
    case_mode: usize = 0,
    iroha: bool = false,
    error_buffer: [1024]u8 = undefined,
    error_len: usize = 0,

    fn init(gpa: Allocator) Allocator.Error!Engine {
        var self = Engine{};
        var len: usize = 0;
        for (row_text, 0..) |text, row| {
            var ids = std.mem.splitScalar(u8, text, ' ');
            while (ids.next()) |id| {
                self.table[len] = .{ .id = id, .row = row, .dan = id[id.len - 1..] };
                len += 1;
            }
        }
        for ([_]usize{ 1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14 }) |row| {
            var stem: []const u8 = undefined;
            for (self.table[0..72]) |m| {
                if (m.row == row and std.mem.eql(u8, m.dan, "i")) {
                    stem = m.id;
                    break;
                }
            }
            for ([_][]const u8{ "ya", "yu", "yo" }) |dan| {
                const id = try std.fmt.allocPrint(gpa, "{s}{s}", .{ stem[0..stem.len - 1], dan });
                self.table[len] = .{ .id = id, .row = row, .dan = dan };
                len += 1;
            }
        }
        for (0..5) |s| {
            for (self.table, 0..) |m, i|
                self.spellings[s][i] = try spelling(gpa, m.id, s);
        }
        var ranks = std.mem.splitScalar(u8, iroha_text, ' ');
        var rank: usize = 0;
        while (ranks.next()) |id| : (rank += 1)
            self.iroha_rank[self.baseIndex(id)] = rank;
        return self;
    }

    fn fail(self: *Engine, message: []const u8) error{ BadCommand } {
        @memcpy(self.error_buffer[0..message.len], message);
        self.error_len = message.len;
        return error.BadCommand;
    }

    fn failFmt(self: *Engine, comptime fmt: []const u8, args: anytype) error{ BadCommand } {
        const text = std.fmt.bufPrint(&self.error_buffer, fmt, args) catch unreachable;
        self.error_len = text.len;
        return error.BadCommand;
    }

    fn columnError(self: *Engine, column: usize, message: []const u8) error{ BadCommand } {
        return self.failFmt("col {d}: {s}", .{ column, message });
    }

    fn idIndex(self: *const Engine, id: []const u8) usize {
        for (self.table, 0..) |m, i| {
            if (std.mem.eql(u8, m.id, id))
                return i;
        }
        unreachable;
    }

    fn baseIndex(self: *const Engine, id: []const u8) usize {
        return if (std.mem.eql(u8, id, "N")) 47 else self.idIndex(id);
    }

    fn baseName(self: *const Engine, base: usize) []const u8 {
        return if (base == 47) "N" else self.table[base].id;
    }

    fn moraVowel(self: *const Engine, id: usize) u8 {
        const name = self.table[id].id;
        return name[name.len - 1];
    }

    fn checkCase(self: *Engine, word: *Word) error{ BadCommand }!void {
        var letters: usize = 0;
        var uppers: usize = 0;
        for (word.original) |c| {
            if (std.ascii.isAlphabetic(c)) {
                letters += 1;
                if (std.ascii.isUpper(c))
                    uppers += 1;
            }
        }
        if (uppers == 0) {
            word.pattern = 0;
            return;
        }
        if (std.ascii.isUpper(word.original[0]) and uppers == 1) {
            word.pattern = 1;
            return;
        }
        if (letters >= 2 and uppers == letters) {
            word.pattern = 2;
            return;
        }
        return self.columnError(word.start + 1, "mixed case");
    }

    fn matchAt(self: *const Engine, text: []const u8, position: usize, system: usize) ?Match {
        var best: ?Match = null;
        const choices: []const usize = if (system == 5) &.{ 0, 2, 3, 4 } else &.{ system };
        for (0..108) |id| {
            for (choices) |s| {
                const candidate = self.spellings[s][id];
                if (std.mem.startsWith(u8, text[position..], candidate) and (best == null or candidate.len > best.?.len))
                    best = .{ .id = id, .len = candidate.len };
            }
        }
        return best;
    }

    fn parse(self: *Engine, gpa: Allocator, original: []const u8, start: usize, system: usize) CommandError![]Mora {
        const text = try std.ascii.allocLowerString(gpa, original);
        var result: std.ArrayList(Mora) = .empty;
        var p: usize = 0;
        while (p < text.len) {
            const c = text[p];
            const next: u8 = if (p + 1 < text.len) text[p + 1] else 0;
            const column = start + p + 1;
            if (c == '-') {
                if (result.items.len == 0 or result.items[result.items.len - 1].id >= mora_n)
                    return self.columnError(column, "misplaced long mark");
                try result.append(gpa, .{ .id = mora_l, .column = column });
                p += 1;
                continue;
            }
            if (c == '\'')
                return self.columnError(column, "misplaced apostrophe");
            if (self.matchAt(text, p, system)) |matched| {
                try result.append(gpa, .{ .id = matched.id, .column = column });
                p += matched.len;
                continue;
            }
            if ((system == 4 or system == 5) and std.mem.startsWith(u8, text[p..], "xtu")) {
                try result.append(gpa, .{ .id = mora_q, .column = column });
                p += 3;
                continue;
            }
            if (c == 'n') {
                var advance: usize = 1;
                if (system == 5) {
                    const third: u8 = if (p + 2 < text.len) text[p + 2] else 0;
                    if (next == '\'' or (next == 'n' and !vowel(third) and third != 'y' and third != '\''))
                        advance = 2;
                } else if (system == 4) {
                    if (next == 'n')
                        advance = 2;
                } else if (next == '\'') {
                    advance = 2;
                }
                try result.append(gpa, .{ .id = mora_n, .column = column });
                p += advance;
                continue;
            }
            if ((system == 1 or system == 5) and c == 'm' and next != 0 and std.mem.findScalar(u8, "bmp",
                next) != null) {
                try result.append(gpa, .{ .id = mora_n, .column = column });
                p += 1;
                continue;
            }
            if (std.ascii.isAlphabetic(c) and std.mem.findScalar(u8, "aiueon", c) == null and next == c and self.matchAt(text,
                p + 1, system) != null) {
                try result.append(gpa, .{ .id = mora_q, .column = column });
                p += 1;
                continue;
            }
            if ((system == 0 or system == 1 or system == 5) and c == 't' and std.mem.startsWith(u8, text[p + 1..],
                "ch") and self.matchAt(text, p + 1, system) != null) {
                try result.append(gpa, .{ .id = mora_q, .column = column });
                p += 1;
                continue;
            }
            return self.columnError(column, "unknown syllable");
        }
        return result.items;
    }

    fn pairs(self: *const Engine, gpa: Allocator, morae: []const Mora) Allocator.Error![]bool {
        const result = try gpa.alloc(bool, morae.len);
        @memset(result, false);
        var i: usize = 0;
        while (i + 1 < morae.len) {
            const a = morae[i].id;
            const b = morae[i + 1].id;
            if (a < mora_n and b < 5) {
                const v = self.moraVowel(a);
                const following = self.table[b].id[0];
                if (v == following or (v == 'o' and following == 'u') or (v == 'e' and following == 'i')) {
                    result[i + 1] = true;
                    i += 2;
                    continue;
                }
            }
            i += 1;
        }
        return result;
    }

    fn longElements(self: *const Engine, gpa: Allocator, morae: []const Mora) Allocator.Error![]bool {
        const paired = try self.pairs(gpa, morae);
        const result = try gpa.alloc(bool, morae.len);
        @memset(result, false);
        for (morae, 0..) |m, i| {
            if (m.id == mora_l) {
                result[i] = true;
                continue;
            }
            if (!paired[i])
                continue;
            const v = self.moraVowel(morae[i - 1].id);
            const following = self.table[m.id].id[0];
            result[i] = (v == 'o' and (following == 'o' or following == 'u')) or (v == 'u' and following == 'u');
        }
        return result;
    }

    fn parts(self: *Engine, gpa: Allocator, morae: []const Mora, target: usize, long_setting: usize) CommandError![][]const u8 {
        const long = try self.longElements(gpa, morae);
        const result = try gpa.alloc([]const u8, morae.len);
        for (morae, 0..) |m, i| {
            const next_id: usize = if (i + 1 < morae.len) morae[i + 1].id else 111;
            const next = if (next_id < mora_n) self.spellings[target][next_id] else "";
            const first: u8 = if (next.len > 0) next[0] else 0;
            if (long[i]) {
                const v = self.moraVowel(morae[i - 1].id);
                result[i] = switch (long_setting) {
                    0 => if (m.id == mora_l) "-" else self.spellings[target][m.id],
                    1 => "",
                    2 => if (v == 'o' and !vowel(first)) "h" else "",
                    3 => "-",
                    else => self.table[morae[i - 1].id].id[self.table[morae[i - 1].id].id.len - 1..],
                };
            } else if (m.id < mora_n) {
                result[i] = self.spellings[target][m.id];
            } else if (m.id == mora_n) {
                if (target == 4) {
                    result[i] = if (next_id == mora_n or vowel(first) or first == 'y' or first == 'n') "nn" else "n";
                } else if (target == 1 and first != 0 and std.mem.findScalar(u8, "bmp", first) != null) {
                    result[i] = "m";
                } else {
                    result[i] = if (vowel(first) or first == 'y') "n'" else "n";
                }
            } else {
                if (first != 0 and std.mem.findScalar(u8, "aiueon", first) == null) {
                    result[i] = if ((target == 0 or target == 1) and std.mem.startsWith(u8, next, "ch")) "t" else next[0..1];
                } else if (target == 4) {
                    result[i] = "xtu";
                } else {
                    return self.columnError(m.column, "small tsu cannot be written");
                }
            }
        }
        return result;
    }

    fn writeWord(self: *Engine, gpa: Allocator, word: Word, target: usize, canonical: bool, morae: []const Mora) CommandError![]const u8 {
        const pieces = try self.parts(gpa, morae, target, if (canonical) 0 else self.long_mode);
        const result = try std.mem.concat(gpa, u8, pieces);
        const pattern: usize = if (canonical or self.case_mode == 0) word.pattern else if (self.case_mode == 1) 0 else if (self.case_mode == 3) 1 else 2;
        if (pattern == 1)
            result[0] = std.ascii.toUpper(result[0]);
        if (pattern == 2)
            _ = std.ascii.upperString(result, result);
        return result;
    }

    fn loose(self: *const Engine, gpa: Allocator, word: Word) Allocator.Error![]Mora {
        const long = try self.longElements(gpa, word.morae);
        const result = try gpa.alloc(Mora, word.morae.len);
        var len: usize = 0;
        for (word.morae, 0..) |m, i| {
            if (!long[i]) {
                result[len] = m;
                len += 1;
            }
        }
        return result[0..len];
    }

    fn devoiced(self: *const Engine, id: []const u8) usize {
        var buffer: [4]u8 = undefined;
        @memcpy(buffer[0..id.len], id);
        if (std.mem.findScalar(u8, "gzdbp", id[0])) |i|
            buffer[0] = "ksthh"[i];
        return self.baseIndex(buffer[0..id.len]);
    }

    fn collate(self: *const Engine, gpa: Allocator, word: *Word) Allocator.Error!void {
        var result: std.ArrayList(Element) = .empty;
        for (word.morae) |m| {
            if (m.id == mora_l)
                continue;
            if (m.id == mora_n) {
                try result.append(gpa, .{ .base = 47, .voice = 0, .size = 0 });
                continue;
            }
            if (m.id == mora_q) {
                try result.append(gpa, .{ .base = self.baseIndex("tu"), .voice = 0, .size = 1 });
                continue;
            }
            const syllable = self.table[m.id];
            const voice: usize = if (syllable.row >= 10 and syllable.row <= 13) 1 else if (syllable.row == 14) 2 else 0;
            if (m.id < 72) {
                try result.append(gpa, .{ .base = self.devoiced(syllable.id), .voice = voice, .size = 0 });
            } else {
                const stem = [_]u8{ syllable.id[0], 'i' };
                try result.append(gpa, .{ .base = self.devoiced(&stem), .voice = voice, .size = 0 });
                try result.append(gpa, .{ .base = self.baseIndex(syllable.id[1..]), .voice = 0, .size = 1 });
            }
        }
        word.elements = result.items;
    }

    fn prepareSortKey(self: *const Engine, gpa: Allocator, word: *Word) Allocator.Error!void {
        for (0..3) |criterion| {
            const key = try gpa.alloc(usize, word.elements.len);
            for (word.elements, 0..) |e, i| {
                key[i] = switch (criterion) {
                    0 => if (self.iroha) self.iroha_rank[e.base] else e.base,
                    1 => e.voice,
                    else => e.size,
                };
            }
            word.sort_key[criterion] = key;
        }
        const long = try gpa.alloc(usize, word.morae.len);
        for (word.morae, 0..) |m, i|
            long[i] = if (m.id == mora_l) 1 else 0;
        word.sort_key[3] = long;
    }

    fn wordLess(_: void, a: Word, b: Word) bool {
        for (a.sort_key, b.sort_key) |left, right| {
            const order = std.mem.order(usize, left, right);
            if (order != .eq)
                return order == .lt;
        }
        return a.ordinal < b.ordinal;
    }

    fn parsePattern(self: *Engine, gpa: Allocator, text: []const u8, system: usize) CommandError![]i32 {
        for (text) |c| {
            if (!((c >= 'a' and c <= 'z') or c == '\'' or c == '-' or c == '?' or c == '*'))
                return self.fail("invalid pattern");
        }
        var result: std.ArrayList(i32) = .empty;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (i == text.len or text[i] == '?' or text[i] == '*') {
                if (i > start) {
                    const part = self.parse(gpa, text[start..i], start, system) catch |err| {
                        if (err == error.BadCommand)
                            return self.fail("invalid pattern");
                        return err;
                    };
                    for (part) |m|
                        try result.append(gpa, @intCast(m.id));
                }
                if (i < text.len)
                    try result.append(gpa, if (text[i] == '?') -1 else -2);
                start = i + 1;
            }
        }
        return result.items;
    }

    fn matches(gpa: Allocator, pattern: []const i32, morae: []const Mora) Allocator.Error!bool {
        var previous = try gpa.alloc(bool, morae.len + 1);
        @memset(previous, false);
        previous[0] = true;
        for (pattern) |token| {
            const current = try gpa.alloc(bool, morae.len + 1);
            @memset(current, false);
            for (0..morae.len + 1) |j|
                current[j] = if (token == -2) previous[j] or (j > 0 and current[j - 1]) else
                    j > 0 and previous[j - 1] and (token == -1 or token == @as(i32, @intCast(morae[j - 1].id)));
            previous = current;
        }
        return previous[morae.len];
    }

    fn execute(self: *Engine, gpa: Allocator, line: []const u8, out: *std.Io.Writer) CommandError!void {
        const commands = [_][]const u8{
            "SET",
            "TABLE",
            "CONVERT",
            "NORMALIZE",
            "REVERSE",
            "VALID",
            "DETECT",
            "DIFF",
            "SAME",
            "MORAE",
            "SYLLABLES",
            "ROW",
            "STATS",
            "SORT",
            "INDEX",
            "FIND",
            "HAIKU",
            "KAIBUN",
            "SHIRITORI"
        };
        const first_space = std.mem.findScalar(u8, line, ' ');
        const op = if (first_space) |position| line[0..position] else line;
        if (choice(op, &commands) == null)
            return self.failFmt("unknown command {s}", .{ op });
        const fixed = std.mem.eql(u8, op, "SET") or std.mem.eql(u8, op, "TABLE");
        const argument_count: usize = if (choice(op, &.{ "CONVERT", "DIFF", "SAME", "FIND" }) != null) 2 else if (choice(op,
            &.{ "NORMALIZE", "DETECT" }) != null) 0 else 1;
        var args: [2][]const u8 = undefined;
        var text: []const u8 = "";
        if (fixed) {
            var tokens = std.mem.splitScalar(u8, line, ' ');
            var len: usize = 0;
            while (tokens.next()) |token| {
                if (len > 0 and len <= 2)
                    args[len - 1] = token;
                len += 1;
            }
            if (len < 3)
                return self.fail("missing argument");
            if (len > 3)
                return self.fail("too many arguments");
        } else {
            var cursor = first_space orelse return self.fail("missing argument");
            for (0..argument_count) |i| {
                const offset = std.mem.findScalar(u8, line[cursor + 1..], ' ') orelse return self.fail("missing argument");
                const end = cursor + 1 + offset;
                args[i] = line[cursor + 1..end];
                cursor = end;
            }
            text = line[cursor + 1..];
        }
        var system: usize = 0;
        var target: usize = 0;
        const system_count: usize = if (std.mem.eql(u8, op, "TABLE")) 1 else if (fixed or choice(op, &.{ "NORMALIZE",
            "DETECT" }) != null) 0 else if (choice(op, &.{ "CONVERT", "DIFF", "SAME" }) != null) 2 else 1;
        for (0..system_count) |i| {
            const value = choice(args[i], &systems) orelse return self.failFmt("unknown system {s}", .{ args[i] });
            if (i == 0) {
                system = value;
            } else {
                target = value;
            }
        }
        if (std.mem.eql(u8, op, "SET")) {
            const options = [_][]const u8{ "LONG", "CASE", "ORDER" };
            const option = choice(args[0], &options) orelse return self.failFmt("unknown option {s}", .{ args[0] });
            const values: []const []const u8 = switch (option) {
                0 => &.{ "KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE" },
                1 => &.{ "KEEP", "LOWER", "UPPER", "TITLE" },
                else => &.{ "GOJUON", "IROHA" },
            };
            const value = choice(args[1], values) orelse return self.failFmt("unknown value {s}", .{ args[1] });
            switch (option) {
                0 => self.long_mode = value,
                1 => self.case_mode = value,
                else => self.iroha = value == 1
            }
            try out.print("{s}={s}", .{ args[0], args[1] });
            return;
        }
        if (std.mem.eql(u8, op, "TABLE")) {
            const row = choice(args[1], &row_names) orelse return self.failFmt("unknown row {s}", .{ args[1] });
            var first = true;
            for (self.table, 0..) |m, i| {
                if (m.row == row) {
                    if (!first)
                        try out.writeByte(' ');
                    first = false;
                    try out.writeAll(self.spellings[system][i]);
                }
            }
            return;
        }
        const find_pattern: []const i32 = if (std.mem.eql(u8, op, "FIND")) try self.parsePattern(gpa, args[1], system) else &.{};
        const allow_slash = std.mem.eql(u8, op, "SAME") or std.mem.eql(u8, op, "HAIKU");
        for (text, 0..) |c, i| {
            if (!wordCharacter(c) and std.mem.findScalar(u8, " 0123456789.,!?;:()\"", c) == null and !(allow_slash
                and c == '/'))
                return self.columnError(i + 1, "invalid character");
        }
        const words = try tokenizeWords(gpa, text);
        var line_count: usize = 0;
        var empty_line = false;
        var segments = std.mem.splitScalar(u8, text, '/');
        while (segments.next()) |segment| {
            line_count += 1;
            if (!hasWord(segment))
                empty_line = true;
        }
        if (std.mem.eql(u8, op, "SAME") and (line_count != 2 or empty_line))
            return self.fail("expected two texts");
        if (std.mem.eql(u8, op, "HAIKU") and (!(line_count == 3 or line_count == 5) or empty_line))
            return self.fail("expected 3 or 5 lines");
        if (words.len == 0)
            return self.fail("no words");
        for (words) |*word|
            try self.checkCase(word);
        if (std.mem.eql(u8, op, "DETECT")) {
            for (0..5) |s| {
                var verdict: []const u8 = "canonical";
                for (words) |*word| {
                    word.morae = self.parse(gpa, word.original, word.start, s) catch |err| {
                        if (err == error.BadCommand) {
                            verdict = "error";
                            break;
                        }
                        return err;
                    };
                }
                if (!std.mem.eql(u8, verdict, "error")) {
                    for (words) |word| {
                        const canonical = try self.writeWord(gpa, word, s, true, word.morae);
                        if (!std.mem.eql(u8, canonical, word.original))
                            verdict = "readable";
                    }
                }
                if (s > 0)
                    try out.writeByte(' ');
                try out.print("{s}={s}", .{ systems[s], verdict });
            }
            return;
        }
        const slash_position = if (std.mem.eql(u8, op, "SAME")) std.mem.findScalar(u8, text, '/').? else text.len;
        for (words) |*word|
            word.morae = try self.parse(gpa, word.original, word.start, if (std.mem.eql(u8, op, "NORMALIZE")) 5 else if (std.mem.eql(u8, op,
                "SAME") and word.start > slash_position) target else
                system);
        if (choice(op, &.{ "CONVERT", "NORMALIZE", "REVERSE" }) != null) {
            var cursor: usize = 0;
            for (words) |word| {
                try out.writeAll(text[cursor..word.start]);
                var morae: []const Mora = word.morae;
                if (std.mem.eql(u8, op, "REVERSE")) {
                    const reversed = try gpa.alloc(Mora, word.morae.len);
                    for (word.morae, 0..) |m, i| {
                        var replacement = m;
                        if (m.id == mora_l) {
                            const v = self.moraVowel(word.morae[i - 1].id);
                            replacement.id = std.mem.findScalar(u8, "aiueo", v).?;
                        }
                        reversed[word.morae.len - 1 - i] = replacement;
                    }
                    morae = reversed;
                }
                const written = try self.writeWord(gpa, word, if (std.mem.eql(u8, op, "NORMALIZE")) 0 else if (std.mem.eql(u8, op,
                    "REVERSE")) system else target, false, morae);
                try out.writeAll(written);
                cursor = word.end;
            }
            try out.writeAll(text[cursor..]);
            return;
        }
        if (std.mem.eql(u8, op, "VALID")) {
            for (words) |word| {
                const canonical = try self.writeWord(gpa, word, system, true, word.morae);
                if (std.mem.eql(u8, canonical, word.original))
                    continue;
                var i: usize = 0;
                while (i < canonical.len and i < word.original.len and canonical[i] == word.original[i])
                    i += 1;
                try out.print("INVALID col {d}: expected {s}", .{ word.start + i + 1, canonical });
                return;
            }
            try out.writeAll("VALID");
            return;
        }
        if (std.mem.eql(u8, op, "DIFF")) {
            const Difference = struct {
                a: []const u8,
                b: []const u8
            };
            var differences: std.ArrayList(Difference) = .empty;
            for (words) |word| {
                const a = try self.writeWord(gpa, word, system, false, word.morae);
                const b = try self.writeWord(gpa, word, target, false, word.morae);
                if (!std.mem.eql(u8, a, b))
                    try differences.append(gpa, .{ .a = a, .b = b });
            }
            try out.print("{d} of {d}", .{ differences.items.len, words.len });
            if (differences.items.len > 0) {
                try out.writeAll(": ");
                for (differences.items, 0..) |d, i| {
                    if (i > 0)
                        try out.writeByte(' ');
                    try out.print("{s}>{s}", .{ d.a, d.b });
                }
            }
            return;
        }
        if (std.mem.eql(u8, op, "SAME")) {
            var split: usize = 0;
            while (split < words.len and words[split].start < slash_position)
                split += 1;
            const left = words[0..split];
            const right = words[split..];
            var exact = true;
            for (0..@min(left.len, right.len)) |i| {
                if (!equalMorae(try self.loose(gpa, left[i]), try self.loose(gpa, right[i]))) {
                    try out.print("DIFFERENT at word {d}", .{ i + 1 });
                    return;
                }
                if (!equalMorae(left[i].morae, right[i].morae))
                    exact = false;
            }
            if (left.len != right.len) {
                try out.print("DIFFERENT at word {d}", .{ @min(left.len, right.len) + 1 });
                return;
            }
            try out.writeAll(if (exact) "EXACT" else "LOOSE");
            return;
        }
        if (std.mem.eql(u8, op, "MORAE")) {
            var total: usize = 0;
            for (words) |word|
                total += word.morae.len;
            try out.print("{d}: ", .{ total });
            for (words, 0..) |word, i| {
                if (i > 0)
                    try out.writeByte(' ');
                for (word.morae, 0..) |m, j| {
                    if (j > 0)
                        try out.writeByte('.');
                    try out.writeAll(if (m.id < mora_n) self.spellings[system][m.id] else if (m.id == mora_n) "N" else if (m.id == mora_q) "Q" else "-");
                }
            }
            return;
        }
        if (std.mem.eql(u8, op, "SYLLABLES")) {
            var total: usize = 0;
            const result = try gpa.alloc([]const u8, words.len);
            for (words, 0..) |word, w| {
                const paired = try self.pairs(gpa, word.morae);
                const written = try self.parts(gpa, word.morae, system, 0);
                var bytes: std.ArrayList(u8) = .empty;
                for (word.morae, 0..) |m, i| {
                    if (i == 0 or (m.id < mora_n and !paired[i])) {
                        if (i > 0)
                            try bytes.append(gpa, '.');
                        total += 1;
                    }
                    try bytes.appendSlice(gpa, written[i]);
                }
                result[w] = bytes.items;
            }
            try out.print("{d}: ", .{ total });
            for (result, 0..) |s, i| {
                if (i > 0)
                    try out.writeByte(' ');
                try out.writeAll(s);
            }
            return;
        }
        if (std.mem.eql(u8, op, "ROW")) {
            var first = true;
            for (words) |word| {
                for (word.morae) |m| {
                    if (!first)
                        try out.writeAll(", ");
                    first = false;
                    if (m.id < mora_n) {
                        const syllable = self.table[m.id];
                        try out.print("{s}: {s} {s}", .{
                            self.spellings[system][m.id],
                            row_names[syllable.row],
                            syllable.dan
                        });
                    } else {
                        const display: []const u8 = if (m.id == mora_n) "N" else if (m.id == mora_q) "Q" else "-";
                        try out.print("{s}: special", .{display});
                    }
                }
            }
            return;
        }
        if (std.mem.eql(u8, op, "STATS")) {
            var total: usize = 0;
            var voiced: usize = 0;
            var semi: usize = 0;
            var contracted: usize = 0;
            var rows = [_]usize{ 0 } ** 10;
            var special = [_]usize{ 0 } ** 3;
            for (words) |word| {
                for (word.morae) |m| {
                    total += 1;
                    if (m.id >= mora_n) {
                        special[m.id - mora_n] += 1;
                        continue;
                    }
                    const row = self.table[m.id].row;
                    rows[base_rows[row]] += 1;
                    if (row >= 10 and row <= 13)
                        voiced += 1;
                    if (row == 14)
                        semi += 1;
                    if (m.id >= 72)
                        contracted += 1;
                }
            }
            try out.print("morae={d}", .{ total });
            for (rows, 0..) |n, i| {
                if (n > 0)
                    try out.print(" {s}={d}", .{ row_names[i], n });
            }
            try out.print(" voiced={d} semivoiced={d} contracted={d} N={d} Q={d} L={d}", .{ voiced, semi,
                contracted, special[0], special[1], special[2] });
            return;
        }
        if (std.mem.eql(u8, op, "FIND")) {
            var found: std.ArrayList(Word) = .empty;
            for (words) |word| {
                if (try matches(gpa, find_pattern, word.morae))
                    try found.append(gpa, word);
            }
            try out.print("{d} of {d}", .{ found.items.len, words.len });
            if (found.items.len > 0) {
                try out.writeAll(": ");
                for (found.items, 0..) |word, i| {
                    if (i > 0)
                        try out.writeByte(' ');
                    try out.writeAll(word.original);
                }
            }
            return;
        }
        if (std.mem.eql(u8, op, "HAIKU")) {
            var counts = [_]usize{ 0 } ** 5;
            for (words) |word| {
                const part = std.mem.countScalar(u8, text[0..word.start], '/');
                counts[part] += word.morae.len;
            }
            const expected = [_]usize{ 5, 7, 5, 7, 7 };
            const ok = std.mem.eql(usize, counts[0..line_count], expected[0..line_count]);
            const verdict: []const u8 = if (ok) "OK" else "NG";
            const poem: []const u8 = if (line_count == 3) "haiku" else "tanka";
            try out.print("{s} {s} ", .{verdict, poem});
            for (counts[0..line_count], 0..) |n, i| {
                if (i > 0)
                    try out.writeByte('-');
                try out.print("{d}", .{ n });
            }
            return;
        }
        for (words) |*word|
            try self.collate(gpa, word);
        if (std.mem.eql(u8, op, "SORT") or std.mem.eql(u8, op, "INDEX")) {
            for (words) |*word|
                try self.prepareSortKey(gpa, word);
            std.mem.sort(Word, words, {}, wordLess);
            if (std.mem.eql(u8, op, "SORT")) {
                for (words, 0..) |word, i| {
                    if (i > 0)
                        try out.writeByte(' ');
                    try out.writeAll(word.original);
                }
                return;
            }
            var previous: []const u8 = "";
            for (words, 0..) |word, i| {
                const base = word.elements[0].base;
                const heading = if (self.iroha or base == 47) self.baseName(base) else row_names[self.table[base].row];
                if (!std.mem.eql(u8, previous, heading)) {
                    if (i > 0)
                        try out.writeAll("; ");
                    try out.print("{s}:", .{ heading });
                    previous = heading;
                }
                try out.print(" {s}", .{ word.original });
            }
            return;
        }
        if (std.mem.eql(u8, op, "KAIBUN")) {
            var sequence: std.ArrayList(usize) = .empty;
            for (words) |word| {
                for (word.elements) |e|
                    try sequence.append(gpa, e.base);
            }
            var palindrome = true;
            for (0..sequence.items.len / 2) |i| {
                if (sequence.items[i] != sequence.items[sequence.items.len - 1 - i])
                    palindrome = false;
            }
            try out.writeAll(if (palindrome) "YES " else "NO ");
            for (sequence.items, 0..) |base, i| {
                if (i > 0)
                    try out.writeByte('.');
                try out.writeAll(self.baseName(base));
            }
            return;
        }
        for (words, 0..) |word, i| {
            const head = word.elements[0].base;
            const tail = word.elements[word.elements.len - 1].base;
            if (i > 0 and head != words[i - 1].elements[words[i - 1].elements.len - 1].base) {
                const previous = words[i - 1].elements[words[i - 1].elements.len - 1].base;
                try out.print("NG {d}: {s} must start with {s}", .{
                    i + 1,
                    word.original,
                    if (previous == 47) @as([]const u8, "N") else self.spellings[system][previous]
                });
                return;
            }
            for (words[0..i]) |earlier| {
                if (equalMorae(earlier.morae, word.morae)) {
                    try out.print("NG {d}: {s} is repeated", .{ i + 1, word.original });
                    return;
                }
            }
            if (tail == 47) {
                try out.print("NG {d}: {s} ends with N", .{ i + 1, word.original });
                return;
            }
        }
        try out.print("OK {d}", .{ words.len });
    }
};

pub fn main(init: std.process.Init) !void {
    var table_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer table_arena.deinit();
    var engine = try Engine.init(table_arena.allocator());
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &output.interface;
    const n = try std.fmt.parseInt(usize, (try input.interface.takeDelimiter('\n')).?, 10);
    for (0..n) |_| {
        const line = (try input.interface.takeDelimiter('\n')).?;
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        var draft_buffer: [8192]u8 = undefined;
        var draft: std.Io.Writer = .fixed(&draft_buffer);
        engine.execute(arena.allocator(), line, &draft) catch |err| {
            if (err == error.BadCommand) {
                try out.print("ERROR {s}\n", .{ engine.error_buffer[0..engine.error_len] });
                continue;
            }
            return err;
        };
        try out.writeAll(draft.buffered());
        try out.writeByte('\n');
    }
    try out.flush();
}
