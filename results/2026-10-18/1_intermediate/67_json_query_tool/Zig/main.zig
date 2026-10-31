const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
const Kind = enum { object, array, string, number, boolean, null };
const Failure = struct { reason: Text, position: usize = 0, json: bool = false };
var failure: Failure = undefined;
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn starts(s: Text, p: Text) bool {
    return std.mem.startsWith(u8, s, p);
}
fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = .{ .reason = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory };
    return error.Invalid;
}
fn jsonFail(offset: usize, reason: Text) Error {
    failure = .{ .reason = reason, .position = offset, .json = true };
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, s: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, s);
    }
    fn byte(self: *Builder, c: u8) Allocator.Error!void {
        try self.bytes.append(self.gpa, c);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};
fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (parts, 0..) |p, i| {
        if (i > 0) try out.add(separator);
        try out.add(p);
    }
    return out.result();
}
fn split(gpa: Allocator, text: Text, separator: u8, limit: usize) Allocator.Error![]Text {
    var parts: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    for (text, 0..) |c, i| {
        if (c == separator and (limit == 0 or parts.items.len + 1 < limit)) {
            try parts.append(gpa, text[start..i]);
            start = i + 1;
        }
    }
    try parts.append(gpa, text[start..]);
    return parts.items;
}
fn identifier(s: Text) bool {
    if (s.len == 0 or (!std.ascii.isAlphabetic(s[0]) and s[0] != '_')) return false;
    for (s) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    return true;
}
fn integerNotation(s: Text) bool {
    if (equal(s, "0")) return true;
    const ds = if (starts(s, "-")) s[1..] else s;
    if (ds.len == 0 or ds.len > 9 or ds[0] == '0') return false;
    for (ds) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn quote(gpa: Allocator, s: Text, mark: u8) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    try out.byte(mark);
    for (s) |c| {
        if (c == mark or c == '\\') {
            try out.byte('\\');
            try out.byte(c);
        } else switch (c) {
            8 => try out.add("\\b"),
            12 => try out.add("\\f"),
            10 => try out.add("\\n"),
            13 => try out.add("\\r"),
            9 => try out.add("\\t"),
            else => if (c < 32 or c == 127) {
                try out.print("\\u{x:0>4}", .{c});
            } else try out.byte(c),
        }
    }
    try out.byte(mark);
    return out.result();
}
const Value = struct {
    kind: Kind,
    text: Text = "",
    number: i64 = 0,
    boolean: bool = false,
    keys: std.ArrayList(Text) = .empty,
    items: std.ArrayList(*Value) = .empty,
    fn find(self: *const Value, key: Text) ?usize {
        for (self.keys.items, 0..) |k, i| if (equal(k, key)) return i;
        return null;
    }
    fn copy(self: *const Value, gpa: Allocator) Error!*Value {
        const result = try make(gpa, self.kind);
        result.text = self.text;
        result.number = self.number;
        result.boolean = self.boolean;
        try result.keys.appendSlice(gpa, self.keys.items);
        for (self.items.items) |item| try result.items.append(gpa, try item.copy(gpa));
        return result;
    }
    fn size(self: *const Value) [2]usize {
        var count: usize = 1;
        var depth: usize = 1;
        for (self.items.items) |item| {
            const child = item.size();
            count += child[0];
            depth = @max(depth, child[1] + 1);
        }
        return .{ count, depth };
    }
};
fn make(gpa: Allocator, kind: Kind) Allocator.Error!*Value {
    const v = try gpa.create(Value);
    v.* = .{ .kind = kind };
    return v;
}
fn compact(gpa: Allocator, v: *Value) Error!Text {
    switch (v.kind) {
        .null => return "null",
        .boolean => return if (v.boolean) "true" else "false",
        .number => return std.fmt.allocPrint(gpa, "{d}", .{v.number}),
        .string => return quote(gpa, v.text, '"'),
        else => {},
    }
    var out: Builder = .{ .gpa = gpa };
    try out.byte(if (v.kind == .array) '[' else '{');
    for (v.items.items, 0..) |item, i| {
        if (i > 0) try out.byte(',');
        if (v.kind == .object) {
            try out.add(try quote(gpa, v.keys.items[i], '"'));
            try out.byte(':');
        }
        try out.add(try compact(gpa, item));
    }
    try out.byte(if (v.kind == .array) ']' else '}');
    return out.result();
}
fn pretty(gpa: Allocator, v: *Value, indent: Text) Error!Text {
    if (v.items.items.len == 0) return compact(gpa, v);
    const inner = try std.fmt.allocPrint(gpa, "{s}  ", .{indent});
    var out: Builder = .{ .gpa = gpa };
    try out.byte(if (v.kind == .array) '[' else '{');
    try out.byte('\n');
    for (v.items.items, 0..) |item, i| {
        if (i > 0) try out.add(",\n");
        try out.add(inner);
        if (v.kind == .object) {
            try out.add(try quote(gpa, v.keys.items[i], '"'));
            try out.add(": ");
        }
        try out.add(try pretty(gpa, item, inner));
    }
    try out.byte('\n');
    try out.add(indent);
    try out.byte(if (v.kind == .array) ']' else '}');
    return out.result();
}
fn same(a: *Value, b: *Value) bool {
    if (a.kind != b.kind) return false;
    switch (a.kind) {
        .null => return true,
        .string => return equal(a.text, b.text),
        .number => return a.number == b.number,
        .boolean => return a.boolean == b.boolean,
        else => {},
    }
    if (a.items.items.len != b.items.items.len) return false;
    for (a.items.items, 0..) |item, i| {
        const j = if (a.kind == .object) b.find(a.keys.items[i]) orelse return false else i;
        if (!same(item, b.items.items[j])) return false;
    }
    return true;
}
const Reader = struct {
    gpa: Allocator,
    text: Text,
    pos: usize = 0,
    fn peek(self: *const Reader) u8 {
        return if (self.pos < self.text.len) self.text[self.pos] else 0;
    }
    fn skip(self: *Reader) void {
        while (self.peek() == ' ' or self.peek() == '\n') self.pos += 1;
    }
    fn require(self: *Reader, c: u8, reason: Text) Error!void {
        if (self.pos == self.text.len) return jsonFail(self.pos, "unexpected end of input");
        if (self.peek() != c) return jsonFail(self.pos, reason);
    }
    fn readString(self: *Reader, mark: u8) Error!Text {
        self.pos += 1;
        var out: Builder = .{ .gpa = self.gpa };
        while (true) {
            const c = self.peek();
            if (c == 0 or c == '\n') return jsonFail(self.pos, "unterminated string");
            if (c == mark) {
                self.pos += 1;
                return out.result();
            }
            if (c != '\\') {
                try out.byte(c);
                self.pos += 1;
                continue;
            }
            const start = self.pos;
            self.pos += 1;
            const e = self.peek();
            if (e == 0 or e == '\n') return jsonFail(self.pos, "unterminated string");
            if (e == 'u') {
                if (start + 6 > self.text.len) return jsonFail(start, "bad unicode escape");
                const digits = self.text[start + 2 .. start + 6];
                for (digits) |d| if (!std.ascii.isHex(d)) return jsonFail(start, "bad unicode escape");
                const n = std.fmt.parseInt(u16, digits, 16) catch unreachable;
                if (n > 127) return jsonFail(start, "non-ascii escape");
                try out.byte(@intCast(n));
                self.pos = start + 6;
            } else {
                const decoded: u8 = if (e == mark) mark else switch (e) {
                    '\\' => '\\',
                    '/' => '/',
                    'b' => 8,
                    'f' => 12,
                    'n' => 10,
                    'r' => 13,
                    't' => 9,
                    else => return jsonFail(start, try std.fmt.allocPrint(self.gpa, "invalid escape '\\{c}'", .{e})),
                };
                try out.byte(decoded);
                self.pos += 1;
            }
        }
    }
    fn containerEnd(self: *Reader, close: u8, reason: Text) Error!bool {
        self.skip();
        if (self.peek() == close) {
            self.pos += 1;
            return true;
        }
        try self.require(',', reason);
        self.pos += 1;
        self.skip();
        if (self.peek() == close) return jsonFail(self.pos, "trailing comma");
        return false;
    }
    fn readValue(self: *Reader) Error!*Value {
        self.skip();
        const c = self.peek();
        if (c == 0) return jsonFail(self.pos, "unexpected end of input");
        if (c == '"') {
            const v = try make(self.gpa, .string);
            v.text = try self.readString('"');
            return v;
        }
        if (c == '{' or c == '[') {
            const kind: Kind = if (c == '{') .object else .array;
            const close: u8 = if (c == '{') '}' else ']';
            const reason: Text = if (c == '{') "expected ',' or '}'" else "expected ',' or ']'";
            const v = try make(self.gpa, kind);
            self.pos += 1;
            self.skip();
            if (self.peek() == close) {
                self.pos += 1;
                return v;
            }
            while (true) {
                if (kind == .object) {
                    self.skip();
                    try self.require('"', "expected key");
                    const start = self.pos;
                    const key = try self.readString('"');
                    if (v.find(key) != null) return jsonFail(start, try std.fmt.allocPrint(self.gpa, "duplicate key {s}", .{try quote(self.gpa, key, '"')}));
                    self.skip();
                    try self.require(':', "expected ':'");
                    self.pos += 1;
                    try v.keys.append(self.gpa, key);
                }
                try v.items.append(self.gpa, try self.readValue());
                if (try self.containerEnd(close, reason)) return v;
            }
        }
        if (c == '-' or std.ascii.isDigit(c)) {
            const start = self.pos;
            const negative = c == '-';
            if (negative) self.pos += 1;
            const first = self.pos;
            while (std.ascii.isDigit(self.peek())) self.pos += 1;
            const ds = self.text[first..self.pos];
            if (ds.len == 0) return jsonFail(start, "invalid number");
            if (ds.len > 1 and ds[0] == '0') return jsonFail(first, "leading zero");
            if (self.peek() == '.') return jsonFail(self.pos, "fraction not allowed");
            if (self.peek() == 'e' or self.peek() == 'E') return jsonFail(self.pos, "exponent not allowed");
            if (ds.len >= 10) return jsonFail(start, "number out of range");
            const v = try make(self.gpa, .number);
            const n = std.fmt.parseInt(i64, ds, 10) catch unreachable;
            v.number = if (negative) -n else n;
            return v;
        }
        if (std.ascii.isAlphabetic(c)) {
            const start = self.pos;
            while (std.ascii.isAlphabetic(self.peek())) self.pos += 1;
            const word = self.text[start..self.pos];
            if (equal(word, "null")) return make(self.gpa, .null);
            if (equal(word, "true") or equal(word, "false")) {
                const v = try make(self.gpa, .boolean);
                v.boolean = equal(word, "true");
                return v;
            }
            return jsonFail(start, try std.fmt.allocPrint(self.gpa, "invalid literal '{s}'", .{word}));
        }
        return jsonFail(self.pos, try std.fmt.allocPrint(self.gpa, "unexpected character '{c}'", .{c}));
    }
    fn parse(self: *Reader) Error!*Value {
        const v = try self.readValue();
        self.skip();
        if (self.pos < self.text.len) return jsonFail(self.pos, "trailing characters");
        return v;
    }
};
fn parseJson(gpa: Allocator, text: Text) Error!*Value {
    var p: Reader = .{ .gpa = gpa, .text = text };
    return p.parse();
}
const SelectorKind = enum { key, index, all, slice };
const Selector = struct { kind: SelectorKind, key: Text = "", index: i64 = 0, start: ?i64 = null, end: ?i64 = null, descendant: bool = false };
const PathReader = struct {
    source: Reader,
    reason: Text,
    fn invalid(self: *PathReader) Error {
        return bad(self.source.gpa, "{s}", .{self.reason});
    }
    fn readIdentifier(self: *PathReader) Error!Text {
        const start = self.source.pos;
        const c = self.source.peek();
        if (!std.ascii.isAlphabetic(c) and c != '_') return self.invalid();
        while (std.ascii.isAlphanumeric(self.source.peek()) or self.source.peek() == '_') self.source.pos += 1;
        return self.source.text[start..self.source.pos];
    }
    fn quoted(self: *PathReader) Error!Text {
        return self.source.readString('\'') catch |err| {
            if (err != error.Invalid) return err;
            return self.invalid();
        };
    }
    fn selection(self: *PathReader) Error!Selector {
        if (self.source.peek() == '\'') {
            const key = try self.quoted();
            if (self.source.peek() != ']') return self.invalid();
            self.source.pos += 1;
            return .{ .kind = .key, .key = key };
        }
        const after = self.source.text[self.source.pos..];
        const end = std.mem.findScalar(u8, after, ']') orelse return self.invalid();
        const text = after[0..end];
        self.source.pos += end + 1;
        if (equal(text, "*")) return .{ .kind = .all };
        if (integerNotation(text)) return .{ .kind = .index, .index = std.fmt.parseInt(i64, text, 10) catch unreachable };
        const colon = std.mem.findScalar(u8, text, ':') orelse return self.invalid();
        const a = text[0..colon];
        const b = text[colon + 1 ..];
        if ((a.len > 0 and !integerNotation(a)) or (b.len > 0 and !integerNotation(b))) return self.invalid();
        return .{ .kind = .slice, .start = if (a.len == 0) null else std.fmt.parseInt(i64, a, 10) catch unreachable, .end = if (b.len == 0) null else std.fmt.parseInt(i64, b, 10) catch unreachable };
    }
};
fn parsePath(gpa: Allocator, text: Text, field: bool) Error![]Selector {
    var p: PathReader = .{ .source = .{ .gpa = gpa, .text = text }, .reason = if (field) "bad field" else "bad path" };
    if (p.source.peek() != (if (field) @as(u8, '@') else '$')) return p.invalid();
    p.source.pos += 1;
    var out: std.ArrayList(Selector) = .empty;
    while (p.source.pos < text.len) {
        var s: Selector = undefined;
        if (p.source.peek() == '[') {
            p.source.pos += 1;
            s = try p.selection();
        } else {
            if (p.source.peek() != '.') return p.invalid();
            p.source.pos += 1;
            const descendant = !field and p.source.peek() == '.';
            if (descendant) p.source.pos += 1;
            if (!field and p.source.peek() == '*') {
                p.source.pos += 1;
                s = .{ .kind = .all };
            } else if (descendant and p.source.peek() == '[') {
                p.source.pos += 1;
                s = try p.selection();
            } else s = .{ .kind = .key, .key = try p.readIdentifier() };
            s.descendant = descendant;
        }
        if (field and s.kind != .key and s.kind != .index) return p.invalid();
        try out.append(gpa, s);
    }
    return out.items;
}
fn parseKey(gpa: Allocator, text: Text) Error!Text {
    var p: PathReader = .{ .source = .{ .gpa = gpa, .text = text }, .reason = "bad key" };
    const key = if (p.source.peek() == '\'') try p.quoted() else try p.readIdentifier();
    if (p.source.pos != text.len) return p.invalid();
    return key;
}
const Step = struct { key: ?Text = null, position: usize };
const Match = struct {
    node: ?*Value,
    steps: []const Step = &.{},
    fn child(self: Match, gpa: Allocator, i: usize) Allocator.Error!Match {
        const v = self.node.?;
        const steps = try gpa.alloc(Step, self.steps.len + 1);
        @memcpy(steps[0..self.steps.len], self.steps);
        steps[self.steps.len] = .{ .key = if (v.kind == .object) v.keys.items[i] else null, .position = i };
        return .{ .node = v.items.items[i], .steps = steps };
    }
    fn location(self: Match, gpa: Allocator) Allocator.Error!Text {
        var out: Builder = .{ .gpa = gpa };
        try out.byte('$');
        for (self.steps) |s| {
            if (s.key) |key| {
                if (identifier(key)) try out.print(".{s}", .{key}) else try out.print("[{s}]", .{try quote(gpa, key, '\'')});
            } else try out.print("[{d}]", .{s.position});
        }
        return out.result();
    }
};
fn position(v: *Value, s: Selector) ?usize {
    if (s.kind == .key) return if (v.kind == .object) v.find(s.key) else null;
    if (v.kind != .array) return null;
    var i = s.index;
    if (i < 0) i += @intCast(v.items.items.len);
    if (i < 0 or i >= @as(i64, @intCast(v.items.items.len))) return null;
    return @intCast(i);
}
fn selectValue(gpa: Allocator, m: Match, s: Selector, out: *std.ArrayList(Match)) Error!void {
    const v = m.node.?;
    if (s.kind == .all) {
        for (0..v.items.items.len) |i| try out.append(gpa, try m.child(gpa, i));
    } else if (s.kind == .slice) {
        if (v.kind != .array) return;
        const n: i64 = @intCast(v.items.items.len);
        var a = s.start orelse 0;
        var b = s.end orelse n;
        if (a < 0) a += n;
        if (b < 0) b += n;
        a = @max(0, @min(n, a));
        b = @max(0, @min(n, b));
        var i = a;
        while (i < b) : (i += 1) try out.append(gpa, try m.child(gpa, @intCast(i)));
    } else if (position(v, s)) |i| try out.append(gpa, try m.child(gpa, i));
}
fn selectDescendants(gpa: Allocator, m: Match, s: Selector, out: *std.ArrayList(Match)) Error!void {
    try selectValue(gpa, m, s, out);
    for (0..m.node.?.items.items.len) |i| try selectDescendants(gpa, try m.child(gpa, i), s, out);
}
fn applySegment(gpa: Allocator, matches: []const Match, s: Selector) Error![]Match {
    var out: std.ArrayList(Match) = .empty;
    for (matches) |m| {
        if (s.descendant) try selectDescendants(gpa, m, s, &out) else try selectValue(gpa, m, s, &out);
    }
    return out.items;
}
fn evaluate(gpa: Allocator, root: *Value, path: []const Selector) Error![]Match {
    var result = try gpa.alloc(Match, 1);
    result[0] = .{ .node = root };
    for (path) |s| result = try applySegment(gpa, result, s);
    return result;
}
fn fieldValue(v: *Value, path: []const Selector) ?*Value {
    var current = v;
    for (path) |s| {
        const i = position(current, s) orelse return null;
        current = current.items.items[i];
    }
    return current;
}
fn rank(v: ?*Value) u8 {
    const x = v orelse return 3;
    return switch (x.kind) {
        .null => 0,
        .number => 1,
        .string => 2,
        else => 3,
    };
}
fn compare(a: ?*Value, b: ?*Value) i8 {
    const x = rank(a);
    const y = rank(b);
    if (x < y) return -1;
    if (x > y) return 1;
    if (x == 1) {
        if (a.?.number < b.?.number) return -1;
        if (a.?.number > b.?.number) return 1;
    }
    if (x == 2) return switch (std.mem.order(u8, a.?.text, b.?.text)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
    return 0;
}
fn holds(operator: Text, v: ?*Value, reference: ?*Value) bool {
    if (equal(operator, "EXISTS")) return v != null;
    if (equal(operator, "==") or equal(operator, "!=")) {
        const matches = v != null and same(v.?, reference.?);
        return if (equal(operator, "==")) matches else !matches;
    }
    if (v == null or v.?.kind != reference.?.kind or (v.?.kind != .number and v.?.kind != .string)) return false;
    const c = compare(v, reference);
    if (equal(operator, "<")) return c < 0;
    if (equal(operator, "<=")) return c <= 0;
    if (equal(operator, ">")) return c > 0;
    return c >= 0;
}
fn documentOrder(a: Match, b: Match) i8 {
    for (0..@min(a.steps.len, b.steps.len)) |i| {
        if (a.steps[i].position < b.steps[i].position) return -1;
        if (a.steps[i].position > b.steps[i].position) return 1;
    }
    if (a.steps.len < b.steps.len) return -1;
    if (a.steps.len > b.steps.len) return 1;
    return 0;
}
fn targets(gpa: Allocator, matches: []const Match) Allocator.Error![]Match {
    const sorted = try gpa.dupe(Match, matches);
    std.mem.sort(Match, sorted, {}, struct {
        fn less(_: void, a: Match, b: Match) bool {
            return documentOrder(a, b) > 0;
        }
    }.less);
    var out: std.ArrayList(Match) = .empty;
    for (sorted) |m| if (out.items.len == 0 or documentOrder(out.items[out.items.len - 1], m) != 0) {
        try out.append(gpa, m);
    };
    return out.items;
}
fn resolve(root: *Value, steps: []const Step) *Value {
    var v = root;
    for (steps) |s| v = v.items.items[s.position];
    return v;
}
fn merge(gpa: Allocator, target: *Value, patch: *Value) Error!void {
    for (patch.keys.items, patch.items.items) |key, item| {
        if (target.find(key)) |i| {
            if (target.items.items[i].kind == .object and item.kind == .object) try merge(gpa, target.items.items[i], item) else target.items.items[i] = try item.copy(gpa);
        } else {
            try target.keys.append(gpa, key);
            try target.items.append(gpa, try item.copy(gpa));
        }
    }
}
fn shape(gpa: Allocator, args: []const Text, minimum: usize, maximum: usize) Error!void {
    if (args.len < minimum or args.len > maximum) return bad(gpa, "bad arguments", .{});
}
fn requireKind(gpa: Allocator, matches: []const Match, kind: Kind, reason: Text) Error!void {
    for (matches) |m| if (m.node.?.kind != kind) return bad(gpa, "{s} at {s}", .{ reason, try m.location(gpa) });
}
const Tool = struct {
    gpa: Allocator,
    document: *Value,
    history: std.ArrayList(*Value) = .empty,
    out: Builder,
    fn commit(self: *Tool, v: *Value) Allocator.Error!void {
        try self.history.append(self.gpa, self.document);
        self.document = v;
    }
    fn load(self: *Tool, lines: []const Text) Error!void {
        const text = try join(self.gpa, lines, "\n");
        const v = parseJson(self.gpa, text) catch |err| {
            if (err != error.Invalid) return err;
            var line: usize = 1;
            var column: usize = 1;
            for (text[0..failure.position]) |c| {
                if (c == '\n') {
                    line += 1;
                    column = 1;
                } else column += 1;
            }
            try self.out.line("PARSE ERROR line {d} col {d}: {s}", .{ line, column, failure.reason });
            return;
        };
        try self.commit(v);
        const counts = v.size();
        try self.out.line("LOADED nodes={d} depth={d}", .{ counts[0], counts[1] });
    }
    fn leaves(self: *Tool, m: Match) Error!void {
        if (m.node.?.items.items.len == 0) {
            try self.out.line("{s} = {s}", .{ try m.location(self.gpa), try compact(self.gpa, m.node.?) });
            return;
        }
        for (0..m.node.?.items.items.len) |i| try self.leaves(try m.child(self.gpa, i));
    }
    fn execute(self: *Tool, line: Text) Error!void {
        const gpa = self.gpa;
        const separator = std.mem.findScalar(u8, line, ' ');
        const command = if (separator) |p| line[0..p] else line;
        const argument = if (separator) |p| line[p + 1 ..] else "";
        const known = " GET COMPACT PRETTY TYPE LENGTH KEYS FLATTEN COUNT SUM MIN MAX AVG FILTER SET DELETE INSERT MERGE SORT RENAME UNDO ";
        const needle = try std.fmt.allocPrint(gpa, " {s} ", .{command});
        if (std.mem.find(u8, known, needle) == null) return bad(gpa, "unknown command '{s}'", .{command});
        var args = if (separator != null) try split(gpa, argument, ' ', 0) else try gpa.alloc(Text, 0);
        if (equal(command, "UNDO")) {
            try shape(gpa, args, 0, 0);
            if (self.history.items.len == 0) return bad(gpa, "nothing to undo", .{});
            self.document = self.history.items[self.history.items.len - 1];
            self.history.items.len -= 1;
            try self.out.line("UNDO {d}", .{self.history.items.len});
            return;
        }
        if (equal(command, "SET") or equal(command, "MERGE") or equal(command, "INSERT")) {
            const count: usize = if (equal(command, "INSERT")) 3 else 2;
            args = try split(gpa, argument, ' ', count);
            if (separator == null or args.len != count) return bad(gpa, "bad arguments", .{});
        } else if (equal(command, "FILTER")) {
            args = try split(gpa, argument, ' ', 4);
            if (separator == null or args.len < 3 or (equal(args[2], "EXISTS") and args.len == 4) or (!equal(args[2], "EXISTS") and args.len == 3)) return bad(gpa, "bad arguments", .{});
        } else if (equal(command, "SORT")) {
            try shape(gpa, args, 1, 3);
            if (args.len == 3 and (equal(args[1], "DESC") or !equal(args[2], "DESC"))) return bad(gpa, "bad arguments", .{});
        } else {
            const optional = equal(command, "COMPACT") or equal(command, "PRETTY") or equal(command, "FLATTEN");
            const rename = equal(command, "RENAME");
            try shape(gpa, args, if (rename) 2 else if (optional) 0 else 1, if (rename) 2 else 1);
        }
        const path = try parsePath(gpa, if (args.len == 0) "$" else args[0], false);
        var field: []Selector = &.{};
        var patch: ?*Value = null;
        var index: i64 = 0;
        var new_key: Text = "";
        var operator: Text = "";
        var descending = false;
        if (equal(command, "FILTER")) {
            field = try parsePath(gpa, args[1], true);
            operator = args[2];
            if (!equal(operator, "==") and !equal(operator, "!=") and !equal(operator, "<") and !equal(operator, "<=") and !equal(operator, ">") and !equal(operator, ">=") and !equal(operator, "EXISTS")) return bad(gpa, "bad operator", .{});
            if (!equal(operator, "EXISTS")) patch = try parseJson(gpa, args[3]);
        } else if (equal(command, "SET") or equal(command, "MERGE")) patch = try parseJson(gpa, args[1]) else if (equal(command, "INSERT")) {
            if (!integerNotation(args[1])) return bad(gpa, "bad index", .{});
            index = std.fmt.parseInt(i64, args[1], 10) catch unreachable;
            patch = try parseJson(gpa, args[2]);
        } else if (equal(command, "SORT")) {
            var field_text: Text = "@";
            if (args.len > 1) {
                descending = equal(args[args.len - 1], "DESC");
                if (!equal(args[1], "DESC")) field_text = args[1];
            }
            field = try parsePath(gpa, field_text, true);
        } else if (equal(command, "RENAME")) new_key = try parseKey(gpa, args[1]);
        if (equal(command, "DELETE") and path.len == 0) return bad(gpa, "cannot delete root", .{});
        if (equal(command, "MERGE") and patch.?.kind != .object) return bad(gpa, "merge value is not an object", .{});
        var matches = try evaluate(gpa, self.document, path);
        if (equal(command, "LENGTH")) for (matches) |m| if (m.node.?.kind != .object and m.node.?.kind != .array and m.node.?.kind != .string) return bad(gpa, "no length at {s}", .{try m.location(gpa)});
        if (equal(command, "KEYS") or equal(command, "MERGE")) try requireKind(gpa, matches, .object, "not an object");
        if (equal(command, "FILTER") or equal(command, "INSERT") or equal(command, "SORT")) try requireKind(gpa, matches, .array, "not an array");
        if (equal(command, "INSERT")) for (matches) |m| {
            const n: i64 = @intCast(m.node.?.items.items.len);
            if (index < -n - 1 or index > n) return bad(gpa, "index out of range at {s}", .{try m.location(gpa)});
        };
        if (equal(command, "RENAME")) for (matches) |m| if (m.steps.len == 0 or m.steps[m.steps.len - 1].key == null) return bad(gpa, "not a member at {s}", .{try m.location(gpa)});
        if (equal(command, "COUNT")) {
            try self.out.line("COUNT {d}", .{matches.len});
            return;
        }
        if (equal(command, "SUM") or equal(command, "MIN") or equal(command, "MAX") or equal(command, "AVG")) {
            var total: i64 = 0;
            var minimum: i64 = 0;
            var maximum: i64 = 0;
            var count: i64 = 0;
            for (matches) |m| if (m.node.?.kind == .number) {
                const n = m.node.?.number;
                total += n;
                if (count == 0 or n < minimum) minimum = n;
                if (count == 0 or n > maximum) maximum = n;
                count += 1;
            };
            var text: Text = "null";
            if (equal(command, "SUM")) text = try std.fmt.allocPrint(gpa, "{d}", .{total}) else if (equal(command, "MIN") and count > 0) text = try std.fmt.allocPrint(gpa, "{d}", .{minimum}) else if (equal(command, "MAX") and count > 0) text = try std.fmt.allocPrint(gpa, "{d}", .{maximum}) else if (equal(command, "AVG") and count > 0) {
                const magnitude = if (total < 0) -total else total;
                const q = @divTrunc(magnitude * 200 + count, 2 * count);
                text = try std.fmt.allocPrint(gpa, "{s}{d}.{d:0>2}", .{ if (total < 0 and q >= 1) @as(Text, "-") else "", @divTrunc(q, 100), @mod(q, 100) });
            }
            try self.out.line("{s} {s}", .{ command, text });
            return;
        }
        const modifying = equal(command, "SET") or equal(command, "DELETE") or equal(command, "INSERT") or equal(command, "MERGE") or equal(command, "SORT") or equal(command, "RENAME");
        if (modifying) {
            if (equal(command, "SET") and path.len == 0) {
                try self.commit(try patch.?.copy(gpa));
                try self.out.add("SET 1\n");
                return;
            }
            if (equal(command, "SET")) {
                var selected: std.ArrayList(Match) = .empty;
                const last = path[path.len - 1];
                for (try evaluate(gpa, self.document, path[0 .. path.len - 1])) |parent| {
                    if (last.kind == .key and !last.descendant and parent.node.?.kind == .object) {
                        const steps = try gpa.alloc(Step, parent.steps.len + 1);
                        @memcpy(steps[0..parent.steps.len], parent.steps);
                        steps[parent.steps.len] = .{ .key = last.key, .position = parent.node.?.find(last.key) orelse parent.node.?.items.items.len };
                        try selected.append(gpa, .{ .node = null, .steps = steps });
                    } else try selected.appendSlice(gpa, try applySegment(gpa, &.{parent}, last));
                }
                matches = selected.items;
            }
            const selected = try targets(gpa, matches);
            const document = try self.document.copy(gpa);
            for (selected) |target| {
                if (equal(command, "SET") or equal(command, "DELETE") or equal(command, "RENAME")) {
                    const parent = resolve(document, target.steps[0 .. target.steps.len - 1]);
                    const i = target.steps[target.steps.len - 1].position;
                    if (equal(command, "SET")) {
                        if (i == parent.items.items.len) {
                            try parent.keys.append(gpa, target.steps[target.steps.len - 1].key.?);
                            try parent.items.append(gpa, try patch.?.copy(gpa));
                        } else parent.items.items[i] = try patch.?.copy(gpa);
                    } else if (equal(command, "DELETE")) {
                        _ = parent.items.orderedRemove(i);
                        if (parent.kind == .object) _ = parent.keys.orderedRemove(i);
                    } else {
                        if (!equal(parent.keys.items[i], new_key) and parent.find(new_key) != null) return bad(gpa, "key exists at {s}", .{try target.location(gpa)});
                        parent.keys.items[i] = new_key;
                    }
                } else {
                    const v = resolve(document, target.steps);
                    if (equal(command, "INSERT")) {
                        const j = if (index >= 0) index else @as(i64, @intCast(v.items.items.len)) + 1 + index;
                        try v.items.insert(gpa, @intCast(j), try patch.?.copy(gpa));
                    } else if (equal(command, "MERGE")) try merge(gpa, v, patch.?) else {
                        var at: usize = 1;
                        while (at < v.items.items.len) : (at += 1) {
                            const item = v.items.items[at];
                            const key = fieldValue(item, field);
                            var destination = at;
                            while (destination > 0) {
                                const comparison = compare(key, fieldValue(v.items.items[destination - 1], field));
                                if (!(if (descending) comparison > 0 else comparison < 0)) break;
                                v.items.items[destination] = v.items.items[destination - 1];
                                destination -= 1;
                            }
                            v.items.items[destination] = item;
                        }
                    }
                }
            }
            try self.commit(document);
            try self.out.line("{s} {d}", .{ command, selected.len });
            return;
        }
        var emitted = false;
        for (matches) |m| {
            const v = m.node.?;
            if (equal(command, "GET")) try self.out.line("{s} = {s}", .{ try m.location(gpa), try compact(gpa, v) }) else if (equal(command, "COMPACT")) try self.out.line("{s}", .{try compact(gpa, v)}) else if (equal(command, "PRETTY")) try self.out.line("{s}", .{try pretty(gpa, v, "")}) else if (equal(command, "TYPE")) try self.out.line("{s} {s}", .{ try m.location(gpa), @tagName(v.kind) }) else if (equal(command, "LENGTH")) try self.out.line("{s} {d}", .{ try m.location(gpa), if (v.kind == .string) v.text.len else v.items.items.len }) else if (equal(command, "KEYS")) {
                var quoted_keys: std.ArrayList(Text) = .empty;
                for (v.keys.items) |key| try quoted_keys.append(gpa, try quote(gpa, key, '"'));
                try self.out.line("{s} [{s}]", .{ try m.location(gpa), try join(gpa, quoted_keys.items, ",") });
            } else if (equal(command, "FLATTEN")) try self.leaves(m) else if (equal(command, "FILTER")) {
                for (0..v.items.items.len) |i| {
                    const element = try m.child(gpa, i);
                    if (holds(operator, fieldValue(element.node.?, field), patch)) {
                        try self.out.line("{s} = {s}", .{ try element.location(gpa), try compact(gpa, element.node.?) });
                        emitted = true;
                    }
                }
                continue;
            }
            emitted = true;
        }
        if (!emitted) try self.out.add("no match\n");
    }
    fn run(self: *Tool, lines: []const Text) Error!void {
        var at: usize = 0;
        while (true) {
            const start = at;
            while (!equal(lines[at], "%%")) at += 1;
            try self.load(lines[start..at]);
            at += 1;
            while (!equal(lines[at], "END") and !equal(lines[at], "LOAD")) {
                self.execute(lines[at]) catch |err| {
                    if (err != error.Invalid) return err;
                    if (failure.json) try self.out.line("PARSE ERROR col {d}: {s}", .{ failure.position + 1, failure.reason }) else try self.out.line("ERROR {s}", .{failure.reason});
                };
                at += 1;
            }
            if (equal(lines[at], "END")) return;
            at += 1;
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
    var tool: Tool = .{ .gpa = gpa, .document = try make(gpa, .null), .out = .{ .gpa = gpa } };
    try tool.run(try split(gpa, text, '\n', 0));
    try output.interface.writeAll(tool.out.result());
    try output.interface.flush();
}
