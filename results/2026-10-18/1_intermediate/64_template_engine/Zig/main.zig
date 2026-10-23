const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{
    Invalid
};

const Kind = enum {
    absent,
    integer,
    string,
    boolean,
    list,
    map
};

const Value = struct {
    kind: Kind,
    text: Text = "",
    integer: i64 = 0,
    boolean: bool = false,
    list: std.ArrayList(*Value) = .empty,
    map: std.StringHashMapUnmanaged(*Value) = .empty,
};

const Line = struct {
    number: usize,
    text: Text
};

const Failure = struct {
    number: usize,
    reason: Text
};

var failure: Failure = undefined;

fn fail(gpa: Allocator, line: usize, comptime pattern: Text, args: anytype) Error {
    failure = .{
        .number = line,
        .reason = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory
    };
    return error.Invalid;
}

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn starts(s: Text, p: Text) bool {
    return std.mem.startsWith(u8, s, p);
}

fn trim(s: Text) Text {
    return std.mem.trim(u8, s, " ");
}

fn find(s: Text, p: Text, at: usize) ?usize {
    return at + (std.mem.find(u8, s[at..], p) orelse return null);
}

fn includes(s: Text, c: u8) bool {
    return std.mem.findScalar(u8, s, c) != null;
}

fn identifier(s: Text) bool {
    if (s.len == 0 or !(std.ascii.isAlphabetic(s[0]) or s[0] == '_')) return false;
    for (s) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}

fn digits(s: Text) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn subscript(s: Text) bool {
    return digits(s) and (s.len == 1 or s[0] != '0');
}

fn numberText(s: Text) bool {
    const ds = if (starts(s, "-")) s[1..] else s;
    return ds.len <= 9 and digits(ds);
}

fn validName(s: Text) bool {
    if (equal(s, ".") or equal(s, "@index") or equal(s, "@number") or equal(s, "@first") or equal(s, "@last")) return true;
    var pieces = std.mem.splitScalar(u8, s, '.');
    while (pieces.next()) |p| if (!identifier(p) and !subscript(p)) return false;
    return true;
}

fn value(gpa: Allocator, kind: Kind) Allocator.Error!*Value {
    const v = try gpa.create(Value);
    v.* = .{
        .kind = kind
    };
    return v;
}

fn string(gpa: Allocator, s: Text) Allocator.Error!*Value {
    const v = try value(gpa, .string);
    v.text = s;
    return v;
}

fn integer(gpa: Allocator, n: i64) Allocator.Error!*Value {
    const v = try value(gpa, .integer);
    v.integer = n;
    return v;
}

fn boolean(gpa: Allocator, b: bool) Allocator.Error!*Value {
    const v = try value(gpa, .boolean);
    v.boolean = b;
    return v;
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
    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};

fn sortedKeys(gpa: Allocator, m: std.StringHashMapUnmanaged(*Value)) Allocator.Error![]Text {
    var out: std.ArrayList(Text) = .empty;
    var it = m.keyIterator();
    while (it.next()) |key| try out.append(gpa, key.*);
    std.mem.sort(Text, out.items, { }, struct {
        fn less(_: void, a: Text, b: Text) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return out.items;
}

const Part = struct {
    key: ?Text = null,
    index: usize = 0,
    prefix: Text = ""
};

fn keyParts(gpa: Allocator, s: Text) Error![]Part {
    var out: std.ArrayList(Part) = .empty;
    var at: usize = 0;
    while (at < s.len) {
        var p: Part = .{ };
        if (at > 0 and s[at] == '[') {
            at += 1;
            const start = at;
            while (at < s.len and std.ascii.isDigit(s[at])): (at += 1) { }
            if (at == s.len or s[at] != ']' or !subscript(s[start..at])) return fail(gpa, 0, "bad key '{s}'", .{
                s
            });
            p.index = std.fmt.parseInt(usize, s[start..at], 10) catch std.math.maxInt(usize);
            at += 1;
        } else {
            if (at > 0) {
                if (s[at] != '.') return fail(gpa, 0, "bad key '{s}'", .{
                    s
                });
                at += 1;
            }
            const start = at;
            while (at < s.len and (std.ascii.isAlphanumeric(s[at]) or s[at] == '_')): (at += 1) { }
            if (!identifier(s[start..at])) return fail(gpa, 0, "bad key '{s}'", .{
                s
            });
            p.key = s[start..at];
        }
        p.prefix = s[0..at];
        try out.append(gpa, p);
    }
    if (out.items.len == 0) return fail(gpa, 0, "bad key '{s}'", .{
        s
    });
    return out.items;
}

const Scalar = struct {
    v: *Value,
    end: usize
};

fn readScalar(gpa: Allocator, s: Text, start: usize) Error!Scalar {
    var at = start;
    if (at < s.len and s[at] == '"') {
        var out: Builder = .{
            .gpa = gpa
        };
        at += 1;
        while (at < s.len) {
            var c = s[at];
            at += 1;
            if (c == '"') return .{
                .v = try string(gpa, out.result()),
                .end = at
            };
            if (c == '\\') {
                if (at == s.len) return error.Invalid;
                c = s[at];
                at += 1;
                switch (c) {
                    'n' => c = '\n',
                    '"',
                    '\\' => { },
                    else => return error.Invalid
                }
            }
            try out.byte(c);
        }
        return error.Invalid;
    }
    while (at < s.len and s[at] != ',' and s[at] != ']'): (at += 1) { }
    const word = s[start..at];
    if (equal(word, "true") or equal(word, "false")) return .{
        .v = try boolean(gpa, equal(word, "true")),
        .end = at
    };
    const ds = if (starts(word, "-")) word[1..] else word;
    if (!(equal(word, "0") or (digits(ds) and ds[0] != '0'))) return error.Invalid;
    return .{
        .v = try integer(gpa, std.fmt.parseInt(i64, word, 10) catch return error.Invalid),
        .end = at
    };
}

fn readValue(gpa: Allocator, s: Text) Error!*Value {
    if (equal(s, "[]")) return value(gpa, .list);
    if (equal(s, "{}")) return value(gpa, .map);
    if (starts(s, "[")) {
        const v = try value(gpa, .list);
        var at: usize = 1;
        while (true) {
            const scalar = try readScalar(gpa, s, at);
            try v.list.append(gpa, scalar.v);
            at = scalar.end;
            if (equal(s[at..], "]")) return v;
            if (!starts(s[at..], ", ")) return error.Invalid;
            at += 2;
        }
    }
    const scalar = try readScalar(gpa, s, 0);
    if (scalar.end != s.len) return error.Invalid;
    return scalar.v;
}

fn parseValue(gpa: Allocator, s: Text) Error!*Value {
    return readValue(gpa, s) catch | err | {
        if (err == error.Invalid) return fail(gpa, 0, "bad value '{s}'", .{
            s
        });
        return err;
    };
}

fn get(v: *Value, p: Part) ?*Value {
    if (p.key) |key| return if (v.kind == .map) v.map.get(key) else null;
    return if (v.kind == .list and p.index < v.list.items.len) v.list.items[p.index] else null;
}

fn change(gpa: Allocator, v: *Value, parts: []Part, at: usize, replacement: *Value, remove: bool, key: Text) Error!*Value {
    const p = parts[at];
    const existing = get(v, p);
    if (remove and existing == null) return fail(gpa, 0, "no value at '{s}'", .{
        key
    });
    if (!remove and p.key == null and p.index > v.list.items.len) return fail(gpa, 0, "index gap at '{s}'", .{
        p.prefix
    });
    var child = replacement;
    if (at + 1 < parts.len) {
        var current: *Value = undefined;
        if (remove) current = existing.?else {
            const required: Kind = if (parts[at + 1].key == null).list else.map;
            if (existing) |old| {
                if (old.kind != required) return fail(gpa, 0, "type conflict at '{s}'", .{
                    p.prefix
                });
                current = old;
            } else current = try value(gpa, required);
        }
        child = try change(gpa, current, parts, at + 1, replacement, remove, key);
    }
    const result = try value(gpa, v.kind);
    if (p.key) |name| {
        var it = v.map.iterator();
        while (it.next()) |entry| try result.map.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
        if (remove and at + 1 == parts.len) {
            _ = result.map.remove(name);
        } else try result.map.put(gpa, name, child);
    } else {
        try result.list.appendSlice(gpa, v.list.items);
        if (remove and at + 1 == parts.len) {
            _ = result.list.orderedRemove(p.index);
        } else if (p.index == result.list.items.len) try result.list.append(gpa, child) else result.list.items[p.index] = child;
    }
    return result;
}

fn splitQuoted(gpa: Allocator, s: Text, separator: u8) Allocator.Error![]Text {
    var out: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    var quoted = false;
    for (s, 0..) |c,
    at | {
        if (c == '\'') quoted = !quoted else if (c == separator and !quoted) {
            try out.append(gpa, s[start..at]);
            start = at + 1;
        }
    }
    try out.append(gpa, s[start..]);
    return out.items;
}

const Filter = struct {
    name: Text,
    args: []* Value
};

const Expression = struct {
    name: Text = "",
    filters: []Filter = &.{ }
};

fn argKind(args: []* Value, at: usize, kind: Kind) bool {
    return at < args.len and args[at].kind == kind;
}

fn parseExpression(gpa: Allocator, s: Text, line: usize) Error!Expression {
    const pieces = try splitQuoted(gpa, s, '|');
    const name = trim(pieces[0]);
    if (!validName(name)) return fail(gpa, line, "invalid name '{s}'", .{
        name
    });
    var filters: std.ArrayList(Filter) = .empty;
    for (pieces[1..]) |piece| {
        const fields = try splitQuoted(gpa, trim(piece), ':');
        const f = fields[0];
        const known = " upper lower title trim length first last reverse items comma sum min max default eq pad lpad truncate replace join sort pluck add sub mul div mod gt lt ";
        const needle = try std.fmt.allocPrint(gpa, " {s} ", .{
            f
        });
        if (std.mem.find(u8, known, needle) == null) return fail(gpa, line, "unknown filter '{s}'", .{
            f
        });
        var args: std.ArrayList(*Value) = .empty;
        var valid = true;
        for (fields[1..]) |a| {
            if (a.len >= 2 and a[0] == '\'' and a[a.len - 1] == '\'' and !includes(a[1..a.len - 1], '\'')) try args.append(gpa, try string(gpa, a[1..a.len - 1])) else if (numberText(a)) try args.append(gpa, try integer(gpa, std.fmt.parseInt(i64, a, 10) catch unreachable)) else valid = false;
        }
        const a = args.items;
        const n = a.len;
        if (equal(f, "default") or equal(f, "eq")) valid = valid and n == 1 else if (equal(f, "pad") or equal(f, "lpad")) valid = valid and (n == 1 or n == 2) and argKind(a, 0, .integer) and a[0].integer >= 0 and (n == 1 or (argKind(a, 1, .string) and a[1].text.len == 1)) else if (equal(f, "truncate")) valid = valid and n == 1 and argKind(a, 0, .integer) and a[0].integer >= 0 else if (equal(f, "replace")) valid = valid and n == 2 and argKind(a, 0, .string) and argKind(a, 1, .string) and a[0].text.len > 0 else if (equal(f, "join") or equal(f, "pluck")) valid = valid and n == 1 and argKind(a, 0, .string) else if (equal(f, "sort")) valid = valid and (n == 0 or (n == 1 and argKind(a, 0, .string))) else if (equal(f, "div") or equal(f, "mod")) valid = valid and n == 1 and argKind(a, 0, .integer) and a[0].integer != 0 else if (equal(f, "add") or equal(f, "sub") or equal(f, "mul") or equal(f, "gt") or equal(f, "lt")) valid = valid and n == 1 and argKind(a, 0, .integer) else valid = valid and n == 0;
        if (!valid) return fail(gpa, line, "bad arguments for '{s}'", .{
            f
        });
        try filters.append(gpa, .{
            .name = f,
            .args = a
        });
    }
    return .{
        .name = name,
        .filters = filters.items
    };
}

const Node = struct {
    kind: u8 = 0,
    text: Text = "",
    line: usize = 0,
    expr: Expression = .{ },
    children: std.ArrayList(*Node) = .empty,
    indent: Text = "",
};

fn node(gpa: Allocator, kind: u8, text: Text, line: usize) Allocator.Error!*Node {
    const n = try gpa.create(Node);
    n.* = .{
        .kind = kind,
        .text = text,
        .line = line
    };
    return n;
}

fn parseSource(gpa: Allocator, lines: []const Line) Error![]* Node {
    const root = try node(gpa, 0, "", 0);
    var targets: std.ArrayList(*Node) = .empty;
    var opens: std.ArrayList(*Node) = .empty;
    try targets.append(gpa, root);
    var opening: Text = "{{";
    var closing: Text = "}}";
    for (lines) |line| {
        var tokens: std.ArrayList(*Node) = .empty;
        var at: usize = 0;
        var count: usize = 0;
        var spaces = true;
        var only_tag: *Node = undefined;
        while (true) {
            const start = find(line.text, opening, at) orelse {
                const text = line.text[at..];
                try tokens.append(gpa, try node(gpa, 0, text, line.number));
                spaces = spaces and trim(text).len == 0;
                break;
            };
            const text = line.text[at..start];
            try tokens.append(gpa, try node(gpa, 0, text, line.number));
            spaces = spaces and trim(text).len == 0;
            var after = start + opening.len;
            const triple = after < line.text.len and line.text[after] == '{';
            const close = if (triple) try std.fmt.allocPrint(gpa, "}}{s}", .{
                closing
            }) else closing;
            if (triple) after += 1;
            const stop = find(line.text, close, after) orelse return fail(gpa, line.number, "unclosed tag", .{ });
            at = stop + close.len;
            const content = trim(line.text[after..stop]);
            const n = try node(gpa, if (triple) '&' else 'v', content, line.number);
            if (!triple and content.len > 0 and includes("#^/!>&=", content[0])) {
                n.kind = content[0];
                if (n.kind != '=') n.text = trim(content[1..]);
            }
            switch (n.kind) {
                '=' => {
                    var ds: std.ArrayList(Text) = .empty;
                    if (content.len >= 2 and content[content.len - 1] == '=') {
                        var parts = std.mem.tokenizeScalar(u8, content[1..content.len - 1], ' ');
                        while (parts.next()) |p| try ds.append(gpa, p);
                    }
                    if (ds.items.len != 2 or includes(ds.items[0], '=') or includes(ds.items[1], '=')) return fail(gpa, line.number, "invalid delimiters", .{ });
                    opening = ds.items[0];
                    closing = ds.items[1];
                },
                'v',
                '&',
                '#',
                '^' => {
                    n.expr = try parseExpression(gpa, n.text, line.number);
                    if (n.kind == '#' or n.kind == '^') try opens.append(gpa, n);
                },
                '/' => {
                    if (!validName(n.text)) return fail(gpa, line.number, "invalid name '{s}'", .{
                        n.text
                    });
                    if (opens.items.len == 0) return fail(gpa, line.number, "unexpected closing '{s}'", .{
                        n.text
                    });
                    const expected = opens.items[opens.items.len - 1].expr.name;
                    if (!equal(n.text, expected)) return fail(gpa, line.number, "mismatched closing '{s}', expected '{s}'", .{
                        n.text,
                        expected
                    });
                    opens.items.len -= 1;
                },
                '>' => if (!identifier(n.text)) return fail(gpa, line.number, "invalid name '{s}'", .{
                    n.text
                }),
                else => { },
            }
            try tokens.append(gpa, n);
            count += 1;
            only_tag = n;
        }
        const standalone = count == 1 and spaces and includes("#^/!>=", only_tag.kind);
        if (standalone) {
            if (only_tag.kind == '>') only_tag.indent = tokens.items[0].text;
            tokens.items.len = 0;
            try tokens.append(gpa, only_tag);
        } else try tokens.append(gpa, try node(gpa, 0, "\n", line.number));
        for (tokens.items) |n| {
            const target = targets.items[targets.items.len - 1];
            switch (n.kind) {
                '#',
                '^' => {
                    try target.children.append(gpa, n);
                    try targets.append(gpa, n);
                },
                '/' => targets.items.len -= 1,
                '!',
                '=' => { },
                else => try target.children.append(gpa, n),
            }
        }
    }
    if (opens.items.len > 0) {
        const n = opens.items[opens.items.len - 1];
        return fail(gpa, n.line, "unclosed section '{s}'", .{
            n.expr.name
        });
    }
    return root.children.items;
}

fn truth(v: *Value) bool {
    return switch (v.kind) {
        .absent => false,
        .integer => v.integer != 0,
        .string => v.text.len > 0,
        .boolean => v.boolean,
        .list => v.list.items.len > 0,
        .map => v.map.count() > 0
    };
}

fn stringify(gpa: Allocator, v: *Value, line: usize) Error!Text {
    switch (v.kind) {
        .absent => return "",
        .string => return v.text,
        .integer => return std.fmt.allocPrint(gpa, "{d}", .{
            v.integer
        }),
        .boolean => return if (v.boolean) "true" else "false",
        .map => return fail(gpa, line, "cannot render map", .{ }),
        .list => {
            var out: Builder = .{
                .gpa = gpa
            };
            for (v.list.items, 0..) |x,
            i | {
                if (i > 0) try out.add(", ");
                try out.add(try stringify(gpa, x, line));
            }
            return out.result();
        },
    }
}

fn numeric(gpa: Allocator, v: *Value, name: Text, line: usize) Error!i64 {
    if (v.kind == .absent) return 0;
    if (v.kind == .integer) return v.integer;
    if (v.kind == .string and numberText(v.text)) return std.fmt.parseInt(i64, v.text, 10) catch unreachable;
    return fail(gpa, line, "not a number for '{s}'", .{
        name
    });
}

fn sortRank(v: *Value) u8 {
    return switch (v.kind) {
        .absent => 0,
        .integer => 1,
        .string => 2,
        .boolean => 3,
        .list,
        .map => 4
    };
}

fn less(a: *Value, b: *Value) bool {
    if (sortRank(a) != sortRank(b)) return sortRank(a) < sortRank(b);
    return switch (a.kind) {
        .integer => a.integer < b.integer,
        .string => std.mem.order(u8, a.text, b.text) == .lt,
        .boolean =>!a.boolean and b.boolean,
        else => false
    };
}

fn field(gpa: Allocator, v: *Value, key: Text) Allocator.Error!*Value {
    if (v.kind == .map) if (v.map.get(key)) |x| return x;
    return value(gpa, .absent);
}

fn apply(gpa: Allocator, f: Filter, v: *Value, line: usize) Error!*Value {
    const name = f.name;
    const a = f.args;
    if (equal(name, "default")) return if (truth(v)) v else a[0];
    if (equal(name, "length")) {
        if (v.kind == .list) return integer(gpa, @intCast(v.list.items.len));
        if (v.kind == .map) return integer(gpa, @intCast(v.map.count()));
    }
    if (equal(name, "first") or equal(name, "last")) {
        if (v.kind != .list) return v;
        if (v.list.items.len == 0) return value(gpa, .absent);
        return v.list.items[if (equal(name, "first")) 0 else v.list.items.len - 1];
    }
    if (equal(name, "reverse")) {
        if (v.kind == .string) {
            const bytes = try gpa.dupe(u8, v.text);
            std.mem.reverse(u8, bytes);
            return string(gpa, bytes);
        }
        if (v.kind != .list) return v;
        const out = try value(gpa, .list);
        try out.list.appendSlice(gpa, v.list.items);
        std.mem.reverse(*Value, out.list.items);
        return out;
    }
    if (equal(name, "items")) {
        if (v.kind != .map) return v;
        const out = try value(gpa, .list);
        for (try sortedKeys(gpa, v.map)) |key| {
            const m = try value(gpa, .map);
            try m.map.put(gpa, "key", try string(gpa, key));
            try m.map.put(gpa, "value", v.map.get(key).?);
            try out.list.append(gpa, m);
        }
        return out;
    }
    if (equal(name, "sort") or equal(name, "pluck")) {
        if (v.kind != .list) return v;
        const out = try value(gpa, .list);
        try out.list.appendSlice(gpa, v.list.items);
        if (equal(name, "pluck")) {
            for (out.list.items) |*x| x.* = try field(gpa, x.*, a[0].text);
        } else {
            var at: usize = 1;
            while (at < out.list.items.len): (at += 1) {
                const x = out.list.items[at];
                const key = if (a.len == 0) x else try field(gpa, x, a[0].text);
                var dest = at;
                while (dest > 0) {
                    const previous = out.list.items[dest - 1];
                    const previous_key = if (a.len == 0) previous else try field(gpa, previous, a[0].text);
                    if (!less(key, previous_key)) break;
                    out.list.items[dest] = previous;
                    dest -= 1;
                }
                out.list.items[dest] = x;
            }
        }
        return out;
    }
    if (equal(name, "sum") or equal(name, "min") or equal(name, "max")) {
        if (v.kind != .list) return integer(gpa, try numeric(gpa, v, name, line));
        if (v.list.items.len == 0 and !equal(name, "sum")) return value(gpa, .absent);
        var total: i64 = 0;
        for (v.list.items, 0..) |x,
        i | {
            const n = try numeric(gpa, x, name, line);
            if (equal(name, "sum")) total += n else if (i == 0 or (equal(name, "min") and n < total) or (equal(name, "max") and n > total)) total = n;
        }
        return integer(gpa, total);
    }
    if (equal(name, "comma") or equal(name, "add") or equal(name, "sub") or equal(name, "mul") or equal(name, "div") or equal(name, "mod") or equal(name, "gt") or equal(name, "lt")) {
        const n = try numeric(gpa, v, name, line);
        if (equal(name, "comma")) {
            const text = try std.fmt.allocPrint(gpa, "{d}", .{
                if (n < 0) - n else n
            });
            var out: Builder = .{
                .gpa = gpa
            };
            if (n < 0) try out.byte('-');
            for (text, 0..) |c,
            i | {
                if (i > 0 and (text.len - i) % 3 == 0) try out.byte(',');
                try out.byte(c);
            }
            return string(gpa, out.result());
        }
        const argument = a[0].integer;
        if (equal(name, "add")) return integer(gpa, n + argument);
        if (equal(name, "sub")) return integer(gpa, n - argument);
        if (equal(name, "mul")) return integer(gpa, n * argument);
        if (equal(name, "div")) return integer(gpa, @divFloor(n, argument));
        if (equal(name, "mod")) return integer(gpa, n - argument * @divFloor(n, argument));
        return boolean(gpa, if (equal(name, "gt")) n > argument else n < argument);
    }
    if (equal(name, "join") and v.kind == .list) {
        var out: Builder = .{
            .gpa = gpa
        };
        for (v.list.items, 0..) |x,
        i | {
            if (i > 0) try out.add(a[0].text);
            try out.add(try stringify(gpa, x, line));
        }
        return string(gpa, out.result());
    }
    const s = try stringify(gpa, v, line);
    if (equal(name, "upper") or equal(name, "lower") or equal(name, "title")) {
        const bytes = try gpa.dupe(u8, s);
        for (bytes, 0..) |*c,
        i | c.* = if (equal(name, "upper") or (equal(name, "title") and (i == 0 or s[i - 1] == ' '))) std.ascii.toUpper(c.*) else std.ascii.toLower(c.*);
        return string(gpa, bytes);
    }
    if (equal(name, "trim")) return string(gpa, trim(s));
    if (equal(name, "length")) return integer(gpa, @intCast(s.len));
    if (equal(name, "eq")) return boolean(gpa, equal(s, try stringify(gpa, a[0], line)));
    if (equal(name, "pad") or equal(name, "lpad")) {
        const size: usize = @intCast(a[0].integer);
        if (s.len >= size) return string(gpa, s);
        const padding = try gpa.alloc(u8, size - s.len);
        @memset(padding, if (a.len == 1) ' ' else a[1].text[0]);
        return string(gpa, if (equal(name, "pad")) try std.fmt.allocPrint(gpa, "{s}{s}", .{
            s,
            padding
        }) else try std.fmt.allocPrint(gpa, "{s}{s}", .{
            padding,
            s
        }));
    }
    if (equal(name, "truncate")) {
        const size: usize = @intCast(a[0].integer);
        return string(gpa, if (s.len <= size) s else try std.fmt.allocPrint(gpa, "{s}...", .{
            s[0..size]
        }));
    }
    if (equal(name, "replace")) {
        var out: Builder = .{
            .gpa = gpa
        };
        var at: usize = 0;
        while (find(s, a[0].text, at)) |position| {
            try out.add(s[at..position]);
            try out.add(a[1].text);
            at = position + a[0].text.len;
        }
        try out.add(s[at..]);
        return string(gpa, out.result());
    }
    return string(gpa, s);
}

fn escape(gpa: Allocator, s: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    for (s) |c| switch (c) {
        '&' => try out.add("&amp;"),
        '<' => try out.add("&lt;"),
        '>' => try out.add("&gt;"),
        '"' => try out.add("&quot;"),
        '\'' => try out.add("&#39;"),
        else => try out.byte(c)
    };
    return out.result();
}

const Loop = struct {
    index: usize,
    count: usize
};

const Renderer = struct {
    gpa: Allocator,
    contexts: std.ArrayList(*Value) = .empty,
    loops: std.ArrayList(Loop) = .empty,
    partials: std.StringHashMapUnmanaged([]const Line),
    strict: bool,
    out: Builder,
    fn resolve(self: *Renderer, name: Text) Error!?*Value {
        if (equal(name, ".")) return self.contexts.items[self.contexts.items.len - 1];
        if (starts(name, "@")) {
            if (self.loops.items.len == 0) return null;
            const l = self.loops.items[self.loops.items.len - 1];
            if (equal(name, "@index")) return try integer(self.gpa, @intCast(l.index));
            if (equal(name, "@number")) return try integer(self.gpa, @intCast(l.index + 1));
            return try boolean(self.gpa, if (equal(name, "@first")) l.index == 0 else l.index == l.count - 1);
        }
        var parts: std.ArrayList(Part) = .empty;
        var words = std.mem.splitScalar(u8, name, '.');
        while (words.next()) |p| try parts.append(self.gpa, if (subscript(p)).{
            .index = std.fmt.parseInt(usize, p, 10) catch std.math.maxInt(usize)
        } else.{
            .key = p
        });
        var at = self.contexts.items.len;
        while (at > 0) {
            at -= 1;
            const context = self.contexts.items[at];
            if (get(context, parts.items[0]) == null) continue;
            var v = context;
            for (parts.items) |p| v = get(v, p) orelse return null;
            return v;
        }
        return null;
    }
    fn evaluate(self: *Renderer, e: Expression, strict: bool, line: usize) Error!*Value {
        const found = try self.resolve(e.name);
        if (strict and found == null) return fail(self.gpa, line, "missing '{s}'", .{
            e.name
        });
        var v = found orelse try value(self.gpa, .absent);
        for (e.filters) |f| v = try apply(self.gpa, f, v, line);
        return v;
    }
    fn render(self: *Renderer, nodes: []* Node, depth: usize) Error!void {
        for (nodes) |n| switch (n.kind) {
            0 => try self.out.add(n.text),
            'v',
            '&' => {
                const s = try stringify(self.gpa, try self.evaluate(n.expr, self.strict, n.line), n.line);
                try self.out.add(if (n.kind == '&') s else try escape(self.gpa, s));
            },
            '#',
            '^' => {
                const v = try self.evaluate(n.expr, false, n.line);
                if (n.kind == '^') {
                    if (!truth(v)) try self.render(n.children.items, depth);
                } else if (v.kind == .list) {
                    for (v.list.items, 0..) |x,
                    i | {
                        try self.contexts.append(self.gpa, x);
                        try self.loops.append(self.gpa, .{
                            .index = i,
                            .count = v.list.items.len
                        });
                        try self.render(n.children.items, depth);
                        self.contexts.items.len -= 1;
                        self.loops.items.len -= 1;
                    }
                } else if (truth(v)) {
                    try self.contexts.append(self.gpa, v);
                    try self.render(n.children.items, depth);
                    self.contexts.items.len -= 1;
                }
            },
            '>' => {
                const body = self.partials.get(n.text) orelse return fail(self.gpa, n.line, "unknown partial '{s}'", .{
                    n.text
                });
                if (depth == 8) return fail(self.gpa, n.line, "partial depth exceeded at '{s}'", .{
                    n.text
                });
                const source = try self.gpa.dupe(Line, body);
                for (source) |*line| if (line.text.len > 0) {
                    line.text = try std.fmt.allocPrint(self.gpa, "{s}{s}", .{
                        n.indent,
                        line.text
                    });
                };
                try self.render(try parseSource(self.gpa, source), depth + 1);
            },
            else => unreachable,
        };
    }
};

fn notation(gpa: Allocator, v: *Value) Error!Text {
    if (v.kind == .map) return "{}";
    if (v.kind == .list) return "[]";
    if (v.kind != .string) return stringify(gpa, v, 0);
    var out: Builder = .{
        .gpa = gpa
    };
    try out.byte('"');
    for (v.text) |c| switch (c) {
        '\\' => try out.add("\\\\"),
        '"' => try out.add("\\\""),
        '\n' => try out.add("\\n"),
        else => try out.byte(c)
    };
    try out.byte('"');
    return out.result();
}

fn collect(gpa: Allocator, v: *Value, path: Text, leaves: *std.ArrayList(Text)) Error!void {
    if (v.kind == .map and v.map.count() > 0) {
        for (try sortedKeys(gpa, v.map)) |key| try collect(gpa, v.map.get(key).?, if (path.len == 0) key else try std.fmt.allocPrint(gpa, "{s}.{s}", .{
            path,
            key
        }), leaves);
    } else if (v.kind == .list and v.list.items.len > 0) {
        for (v.list.items, 0..) |x,
        i | try collect(gpa, x, try std.fmt.allocPrint(gpa, "{s}[{d}]", .{
            path,
            i
        }), leaves);
    } else if (path.len > 0) try leaves.append(gpa, try std.fmt.allocPrint(gpa, "{s} = {s}", .{
        path,
        try notation(gpa, v)
    }));
}

const Engine = struct {
    gpa: Allocator,
    root: *Value,
    partials: std.StringHashMapUnmanaged([]const Line) = .empty,
    templates: std.StringHashMapUnmanaged([]const Line) = .empty,
    strict: bool = false,
    out: Builder,
    fn showTemplate(self: *Engine, name: Text) Error!void {
        const nodes = parseSource(self.gpa, self.templates.get(name).?) catch | err | {
            if (err != error.Invalid) return err;
            try self.out.print("TEMPLATE {s} ERROR line {d}: {s}\n", .{
                name,
                failure.number,
                failure.reason
            });
            return;
        };
        var r: Renderer = .{
            .gpa = self.gpa,
            .partials = self.partials,
            .strict = self.strict,
            .out = .{
                .gpa = self.gpa
            }
        };
        try r.contexts.append(self.gpa, self.root);
        r.render(nodes, 0) catch | err | {
            if (err != error.Invalid) return err;
            try self.out.print("TEMPLATE {s} ERROR line {d}: {s}\n", .{
                name,
                failure.number,
                failure.reason
            });
            return;
        };
        const text = r.out.result();
        var count: usize = 0;
        for (text) |c| if (c == '\n') {
            count += 1;
        };
        if (text.len > 0 and text[text.len - 1] != '\n') count += 1;
        try self.out.print("TEMPLATE {s} OK lines={d} chars={d}\n", .{
            name,
            count,
            text.len
        });
        try self.out.add(text);
        if (text.len > 0 and text[text.len - 1] != '\n') try self.out.byte('\n');
    }
    fn dataLine(self: *Engine, text: Text) Error!bool {
        const remove = starts(text, "UNSET ");
        var key: Text = undefined;
        var v: *Value = undefined;
        var notation_text: Text = "";
        if (remove) key = text[6..] else {
            const separator = find(text, " = ", 0) orelse return fail(self.gpa, 0, "bad line", .{ });
            key = text[0..separator];
            notation_text = text[separator + 3..];
        }
        const parts = try keyParts(self.gpa, key);
        v = if (remove) try value(self.gpa, .absent) else try parseValue(self.gpa, notation_text);
        self.root = try change(self.gpa, self.root, parts, 0, v, remove, key);
        return remove;
    }
    fn loadData(self: *Engine, body: []const Line) Error!void {
        var set: usize = 0;
        var unset: usize = 0;
        var errors: std.ArrayList(Text) = .empty;
        for (body) |line| {
            if (line.text.len == 0 or starts(line.text, "#")) continue;
            const remove = self.dataLine(line.text) catch | err | {
                if (err != error.Invalid) return err;
                try errors.append(self.gpa, try std.fmt.allocPrint(self.gpa, "ERROR line {d}: {s}\n", .{
                    line.number,
                    failure.reason
                }));
                continue;
            };
            if (remove) unset += 1 else set += 1;
        }
        try self.out.print("DATA set={d} unset={d} errors={d}\n", .{
            set,
            unset,
            errors.items.len
        });
        for (errors.items) |line| try self.out.add(line);
    }
    fn run(self: *Engine, lines: []const Line) Error!void {
        var at: usize = 0;
        while (at < lines.len) {
            const line = lines[at];
            at += 1;
            if (equal(line.text, "END")) break;
            const space = std.mem.findScalar(u8, line.text, ' ') orelse line.text.len;
            const command = line.text[0..space];
            const name = if (space < line.text.len) line.text[space + 1..] else "";
            if (equal(command, "DATA") or equal(command, "PARTIAL") or equal(command, "TEMPLATE")) {
                const marker = try std.fmt.allocPrint(self.gpa, "END{s}", .{
                    command
                });
                const start = at;
                while (!equal(lines[at].text, marker)): (at += 1) { }
                const body = lines[start..at];
                at += 1;
                if (equal(command, "DATA")) try self.loadData(body) else if (equal(command, "TEMPLATE")) {
                    try self.templates.put(self.gpa, name, body);
                    try self.showTemplate(name);
                } else {
                    _ = parseSource(self.gpa, body) catch | err | {
                        if (err != error.Invalid) return err;
                        try self.out.print("PARTIAL {s} ERROR line {d}: {s}\n", .{
                            name,
                            failure.number,
                            failure.reason
                        });
                        continue;
                    };
                    const status: Text = if (self.partials.contains(name)) "REPLACED" else "DEFINED";
                    try self.partials.put(self.gpa, name, body);
                    try self.out.print("PARTIAL {s} {s} lines={d}\n", .{
                        name,
                        status,
                        body.len
                    });
                }
            } else if (equal(command, "RENDER")) {
                if (self.templates.contains(name)) try self.showTemplate(name) else try self.out.print("TEMPLATE {s} ERROR line {d}: unknown template '{s}'\n", .{
                    name,
                    line.number,
                    name
                });
            } else if (equal(command, "STRICT")) {
                self.strict = equal(name, "ON");
                try self.out.print("{s}\n", .{
                    line.text
                });
            } else if (equal(command, "RESET")) {
                self.root = try value(self.gpa, .map);
                self.partials = .empty;
                self.templates = .empty;
                try self.out.add("RESET\n");
            } else if (equal(command, "DUMP")) {
                var leaves: std.ArrayList(Text) = .empty;
                try collect(self.gpa, self.root, "", & leaves);
                try self.out.print("DUMP leaves={d}\n", .{
                    leaves.items.len
                });
                for (leaves.items) |leaf| try self.out.print("{s}\n", .{
                    leaf
                });
            }
        }
    }
};

pub fn main(init: std.process.Init)!void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, & input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, & output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines: std.ArrayList(Line) = .empty;
    var pieces = std.mem.splitScalar(u8, text, '\n');
    while (pieces.next()) |line| try lines.append(gpa, .{
        .number = lines.items.len + 1,
        .text = line
    });
    var engine: Engine = .{
        .gpa = gpa,
        .root = try value(gpa, .map),
        .out = .{
            .gpa = gpa
        }
    };
    try engine.run(lines.items);
    try output.interface.writeAll(engine.out.result());
    try output.interface.flush();
}
