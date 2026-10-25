const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;
const size = 26 * 99;

var out: std.ArrayList(u8) = .empty;

var why: S = "";

fn eq(a: S, b: S) bool {
    return std.mem.eql(u8, a, b);
}

fn fmt(comptime f: S, a: anytype) !S {
    return std.fmt.allocPrint(A, f, a);
}

fn fail(comptime f: S, a: anytype) anyerror {
    why = fmt(f, a) catch unreachable;
    return error.Invalid;
}

fn put(s: S) !void {
    try out.appendSlice(A, s);
}

fn line(s: S) !void {
    try put(s);
    try put("\n");
}

const Ref = struct {
    c: i32,
    r: i32,
    ac: bool = false,
    ar: bool = false
};

const Rect = struct {
    a: Ref,
    b: Ref
};

const Tag = enum {
    num,
    str,
    name,
    ref,
    range,
    invalid,
    call,
    neg,
    binary
};

const Node = struct {
    k: Tag,
    n: i64 = 0,
    s: S = "",
    a: Ref = .{ .c = 0, .r = 0 },
    b: Ref = .{ .c = 0, .r = 0 },
    args: []const *Node = &.{}
};

fn node(n: Node) ! *Node {
    const p = try A.create(Node);
    p.* = n;
    return p;
}

const Value = struct {
    k: enum {
        empty,
        num,
        str,
        err,
        range
    }
 = .empty,
    n: i64 = 0,
    s: S = "",
    a: Ref = .{ .c = 0, .r = 0 },
    b: Ref = .{ .c = 0, .r = 0 }
};

fn num(n: i64) Value {
    return .{ .k = .num, .n = n };
}

fn err(s: S) Value {
    return .{ .k = .err, .s = s };
}

fn equal(a: Value, b: Value) bool {
    return a.k == b.k and a.n == b.n and eq(a.s, b.s);
}

fn display(v: Value, quoted: bool) !S {
    return switch (v.k) {
        .empty => if (quoted) "(empty)" else "",
        .num => fmt("{d}", .{ v.n }),
        .str => if (quoted) fmt("\"{s}\"", .{ v.s }) else v.s,
        .err => v.s,
        .range => "#VALUE!"
    };
}

fn numeric(v: Value) Value {
    return switch (v.k) {
        .empty => num(0),
        .num,
        .err => v,
        else => err("#VALUE!")
    };
}

fn string(v: Value) !Value {
    return switch (v.k) {
        .empty => .{ .k = .str },
        .num => .{
            .k = .str,
            .s = try fmt("{d}", .{ v.n })
        },
        .str,
        .err => v,
        else => err("#VALUE!")
    };
}

fn addr(s: S) ?Ref {
    if (s.len < 2 or s.len > 3 or s[0] < 'A' or s[0] > 'Z' or s[1] == '0') return null;
    for (s[1..]) |c| if (!std.ascii.isDigit(c)) return null;
    const r = std.fmt.parseInt(i32, s[1..], 10) catch return null;
    if (r < 1 or r > 99) return null;
    return .{ .c = s[0] - 'A' + 1, .r = r };
}

fn normalize(a0: Ref, b0: Ref) Rect {
    var a = a0;
    var b = b0;
    if (a.c > b.c) {
        std.mem.swap(i32, &a.c, &b.c);
        std.mem.swap(bool, &a.ac, &b.ac);
    }
    if (a.r > b.r) {
        std.mem.swap(i32, &a.r, &b.r);
        std.mem.swap(bool, &a.ar, &b.ar);
    }
    return .{ .a = a, .b = b };
}

fn rectangle(s: S) ?Rect {
    if (std.mem.indexOfScalar(u8, s, ':')) |i| {
        return normalize(addr(s[0..i]) orelse return null, addr(s[i + 1..]) orelse return null);
    }
    const a = addr(s) orelse return null;
    return .{ .a = a, .b = a };
}

fn idx(a: Ref) usize {
    return @intCast((a.r - 1) * 26 + a.c - 1);
}

fn at(i: usize) Ref {
    return .{ .c = @intCast(i % 26 + 1), .r = @intCast(i / 26 + 1) };
}

fn inside(a: Ref, r: Rect) bool {
    return a.c >= r.a.c and a.c <= r.b.c and a.r >= r.a.r and a.r <= r.b.r;
}

fn valid(a: Ref) bool {
    return a.c >= 1 and a.c <= 26 and a.r >= 1 and a.r <= 99;
}

fn refText(a: Ref) !S {
    return fmt("{s}{c}{s}{d}", .{
        if (a.ac) @as(S, "$") else "",
        @as(u8, @intCast(a.c - 1)) + 'A',
        if (a.ar) @as(S, "$") else "",
        a.r
    });
}

fn precedence(s: S) u8 {
    if (eq(s, "&")) return 2;
    if (eq(s, "+") or eq(s, "-")) return 3;
    if (eq(s, "*") or eq(s, "/")) return 4;
    return 1;
}

fn canonical(n: *Node) anyerror!S {
    return switch (n.k) {
        .num => fmt("{d}", .{ n.n }),
        .str => fmt("\"{s}\"", .{ n.s }),
        .name => n.s,
        .ref => refText(n.a),
        .range => fmt("{s}:{s}", .{ try refText(n.a), try refText(n.b) }),
        .invalid => "#REF!",
        .neg => if (n.args[0].k == .binary) fmt("-({s})", .{ try canonical(n.args[0]) }) else fmt("-{s}", .{ try canonical(n.args[0]) }),
        .binary => blk: {
            const x = n.args[0];
            const y = n.args[1];
            var l = try canonical(x);
            var r = try canonical(y);
            if (x.k == .binary and precedence(x.s) < precedence(n.s)) l = try fmt("({s})", .{ l });
            if (y.k == .binary and precedence(y.s) <= precedence(n.s)) r = try fmt("({s})", .{ r });
            break: blk fmt("{s}{s}{s}", .{ l, n.s, r });
        },
        .call => blk: {
            var s = try fmt("{s}(", .{ n.s });
            for (n.args, 0..) |a, i| s = try fmt("{s}{s}{s}", .{ s, if (i == 0) @as(S, "") else ",", try canonical(a) });
            break: blk fmt("{s})", .{ s });
        }
    };
}

const Token = struct {
    k: enum {
        num,
        str,
        name,
        ref,
        fun,
        sym,
        end
    },
    s: S,
    p: usize,
    a: Ref = .{ .c = 0, .r = 0 }
};

fn reference(s: S) ?Ref {
    var i: usize = 0;
    var r: Ref = .{ .c = 0, .r = 0 };
    if (i < s.len and s[i] == '$') {
        r.ac = true;
        i += 1;
    }
    if (i == s.len or s[i] < 'A' or s[i] > 'Z') return null;
    r.c = s[i] - 'A' + 1;
    i += 1;
    if (i < s.len and s[i] == '$') {
        r.ar = true;
        i += 1;
    }
    const start = i;
    if (start == s.len or s[start] == '0') return null;
    while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
    if (i != s.len) return null;
    r.r = std.fmt.parseInt(i32, s[start..], 10) catch return null;
    return if (valid(r)) r else null;
}

fn lex(s: S) ![]Token {
    var ts: std.ArrayList(Token) = .empty;
    var i: usize = 1;
    while (i < s.len) {
        if (s[i] == ' ') {
            i += 1;
            continue;
        }
        const start = i;
        const c = s[i];
        var t: Token = .{ .k = .sym, .s = "", .p = i + 1 };
        if (std.ascii.isDigit(c)) {
            while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
            if (i - start > 9) return fail("syntax error at {d}", .{ start + 1 });
            t.k = .num;
        } else if (c == '"') {
            i += 1;
            const begin = i;
            while (i < s.len and s[i] != '"') i += 1;
            if (i == s.len) return fail("syntax error at {d}", .{ start + 1 });
            t.k = .str;
            t.s = s[begin..i];
            i += 1;
            try ts.append(A, t);
            continue;
        } else if (std.ascii.isAlphabetic(c) or c == '$') {
            while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '$')) i += 1;
            const word = try A.dupe(u8, s[start..i]);
            for (word) |*ch| ch.* = std.ascii.toUpper(ch.*);
            t.s = word;
            if (reference(word)) |r| {
                t.k = .ref;
                t.a = r;
            } else {
                if (!std.ascii.isUpper(word[0])) return fail("syntax error at {d}", .{ start + 1 });
                for (word) |ch| if (!std.ascii.isUpper(ch) and !std.ascii.isDigit(ch)) return fail("syntax error at {d}", .{ start + 1 });
                var j = i;
                while (j < s.len and s[j] == ' ') j += 1;
                t.k = if (j < s.len and s[j] == '(').fun else .name;
            }
            try ts.append(A, t);
            continue;
        } else {
            if (std.mem.indexOfScalar(u8, "+-*/&(),:=<>", c) == null) return fail("syntax error at {d}", .{ i + 1 });
            i += 1;
            if (i < s.len and ((c == '<' and (s[i] == '>' or s[i] == '=')) or (c == '>' and s[i] == '='))) i += 1;
        }
        t.s = s[start..i];
        try ts.append(A, t);
    }
    try ts.append(A, .{ .k = .end, .s = "", .p = s.len + 1 });
    return ts.toOwnedSlice(A);
}

const Parser = struct {
    ts: []Token,
    i: usize = 0,
    fn accept(p: *Parser, s: S) bool {
        if (!eq(p.ts[p.i].s, s)) return false;
        p.i += 1;
        return true;
    }
    fn bad(p: *Parser) anyerror {
        return fail("syntax error at {d}", .{ p.ts[p.i].p });
    }
    fn primary(p: *Parser) anyerror! *Node {
        const t = p.ts[p.i];
        if (p.accept("-")) return node(.{
            .k = .neg,
            .args = try A.dupe(*Node, &.{ try p.primary() })
        });
        if (p.accept("(")) {
            const a = try p.expression(1);
            if (!p.accept(")")) return p.bad();
            return a;
        }
        p.i += 1;
        switch (t.k) {
            .num => return node(.{ .k = .num, .n = try std.fmt.parseInt(i64, t.s, 10) }),
            .str => return node(.{ .k = .str, .s = t.s }),
            .name => return node(.{ .k = .name, .s = t.s }),
            .ref => {
                if (p.accept(":")) {
                    const b = p.ts[p.i];
                    if (b.k != .ref) return p.bad();
                    p.i += 1;
                    const r = normalize(t.a, b.a);
                    return node(.{ .k = .range, .a = r.a, .b = r.b });
                }
                return node(.{ .k = .ref, .a = t.a });
            },
            .fun => {
                if (!p.accept("(")) return p.bad();
                var args: std.ArrayList(*Node) = .empty;
                if (!p.accept(")")) {
                    while (true) {
                        try args.append(A, try p.expression(1));
                        if (p.accept(")")) break;
                        if (!p.accept(",")) return p.bad();
                    }
                }
                return node(.{ .k = .call, .s = t.s, .args = try args.toOwnedSlice(A) });
            },
            else => {
                p.i -= 1;
                return p.bad();
            }
        }
    }
    fn expression(p: *Parser, min: u8) anyerror! *Node {
        var n = try p.primary();
        while (p.ts[p.i].k == .sym) {
            const op = p.ts[p.i].s;
            if (eq(op, ")") or eq(op, ",") or eq(op, ":") or eq(op, "(")) break;
            const pr = precedence(op);
            if (pr < min) break;
            p.i += 1;
            const r = try p.expression(pr + 1);
            n = try node(.{
                .k = .binary,
                .s = op,
                .args = try A.dupe(*Node, &.{ n, r })
            });
        }
        return n;
    }
};

const Cell = struct {
    n: ?*Node = null,
    formula: bool = false
};

var cells: [size]Cell = [_]Cell{
     .{}
} ** size;

var values: [size]Value = [_]Value{
     .{}
} ** size;

var deps: [size][size]bool = undefined;

var cycles: [size]bool = undefined;

var visited: [size]u8 = undefined;

var discovery: [size]usize = undefined;

var lowlink: [size]usize = undefined;

var clock: usize = 0;

var done: [size]bool = undefined;

var stack: std.ArrayList(usize) = .empty;

fn dependencies(n: *Node, b: *[size]bool) void {
    switch (n.k) {
        .ref => b[idx(n.a)] = true,
        .range => {
            for (0..size) |i| if (inside(at(i), .{ .a = n.a, .b = n.b })) {
                b[i] = true;
            };
        },
        else => for (n.args) |x| dependencies(x, b)
    }
}

fn visit(i: usize) anyerror!void {
    visited[i] = 1;
    discovery[i] = clock;
    lowlink[i] = clock;
    clock += 1;
    try stack.append(A, i);
    for (0..size) |j| if (deps[i][j]and cells[j].formula) {
        if (visited[j] == 0) {
            try visit(j);
            lowlink[i] = @min(lowlink[i], lowlink[j]);
        } else if (visited[j] == 1) lowlink[i] = @min(lowlink[i], discovery[j]);
    };
    if (lowlink[i] == discovery[i]) {
        var component: std.ArrayList(usize) = .empty;
        while (true) {
            const j = stack.pop().?;
            visited[j] = 2;
            try component.append(A, j);
            if (j == i) break;
        }
        if (component.items.len > 1 or deps[i][i]) for (component.items) |j| {
            cycles[j] = true;
        };
    }
}

fn cellValue(i: usize) anyerror!Value {
    if (done[i]) return values[i];
    done[i] = true;
    if (cycles[i]) {
        values[i] = err("#CYCLE!");
        return values[i];
    }
    if (cells[i].n) |n| {
        var v = try eval(n);
        if (cells[i].formula) {
            if (v.k == .empty) v = num(0);
            if (v.k == .range) v = err("#VALUE!");
        }
        values[i] = v;
    } else values[i] = .{};
    return values[i];
}

fn eval(n: *Node) anyerror!Value {
    switch (n.k) {
        .num => return num(n.n),
        .str => return .{ .k = .str, .s = n.s },
        .name => return err("#NAME?"),
        .invalid => return err("#REF!"),
        .ref => return cellValue(idx(n.a)),
        .range => return .{ .k = .range, .a = n.a, .b = n.b },
        .neg => {
            const v = numeric(try eval(n.args[0]));
            return if (v.k == .err) v else num( - v.n);
        },
        .binary => {
            var x = try eval(n.args[0]);
            var y = try eval(n.args[1]);
            if (x.k == .err) return x;
            if (y.k == .err) return y;
            if (eq(n.s, "&")) {
                x = try string(x);
                y = try string(y);
                if (x.k == .err) return x;
                if (y.k == .err) return y;
                return .{
                    .k = .str,
                    .s = try fmt("{s}{s}", .{ x.s, y.s })
                };
            }
            if (precedence(n.s) >= 3) {
                x = numeric(x);
                y = numeric(y);
                if (x.k == .err) return x;
                if (y.k == .err) return y;
                if (eq(n.s, "+")) return num(x.n + y.n);
                if (eq(n.s, "-")) return num(x.n - y.n);
                if (eq(n.s, "*")) return num(x.n * y.n);
                return if (y.n == 0) err("#DIV/0!") else num(@divTrunc(x.n, y.n));
            }
            if (x.k == .range or y.k == .range) return err("#VALUE!");
            var cmp: i32 = 0;
            if (x.k == .str and y.k == .num) cmp = 1 else if (x.k == .num and y.k == .str) cmp =  - 1 else if (x.k == .str or y.k == .str) {
                const ord = std.mem.order(u8, x.s, y.s);
                cmp = if (ord == .lt) - 1 else if (ord == .gt) 1 else 0;
            } else cmp = if (x.n < y.n) - 1 else if (x.n > y.n) 1 else 0;
            return num(@intFromBool(if (eq(n.s, "=")) cmp == 0 else if (eq(n.s, "<>")) cmp != 0 else if (eq(n.s, "<")) cmp < 0 else if (eq(n.s, "<=")) cmp <= 0 else if (eq(n.s, ">")) cmp > 0 else cmp >= 0));
        },
        .call => return function(n)
    }
}

fn function(n: *Node) anyerror!Value {
    const s = n.s;
    const aggregate = eq(s, "SUM") or eq(s, "MIN") or eq(s, "MAX") or eq(s, "COUNT") or eq(s, "AVERAGE") or eq(s, "AND") or eq(s, "OR") or eq(s, "CONCAT");
    if (!aggregate and !eq(s, "IF") and !eq(s, "ABS") and !eq(s, "NOT") and !eq(s, "LEN")) return err("#NAME?");
    if ((aggregate and n.args.len == 0) or (eq(s, "IF") and n.args.len != 2 and n.args.len != 3) or (!aggregate and !eq(s, "IF") and n.args.len != 1)) return err("#VALUE!");
    if (eq(s, "IF")) {
        const c = numeric(try eval(n.args[0]));
        if (c.k == .err) return c;
        return if (c.n != 0) eval(n.args[1]) else if (n.args.len == 3) eval(n.args[2]) else num(0);
    }
    if (!aggregate) {
        var x = try eval(n.args[0]);
        if (eq(s, "LEN")) {
            x = try string(x);
            return if (x.k == .err) x else num(@intCast(x.s.len));
        }
        x = numeric(x);
        if (x.k == .err) return x;
        return num(if (eq(s, "NOT")) @intFromBool(x.n == 0) else @intCast(@abs(x.n)));
    }
    var items: std.ArrayList(Value) = .empty;
    for (n.args) |a| {
        const v = try eval(a);
        if (v.k == .range) {
            for (0..size) |i| if (inside(at(i), .{ .a = v.a, .b = v.b })) {
                try items.append(A, try cellValue(i));
            };
        } else try items.append(A, v);
    }
    var count: i64 = 0;
    var sum: i64 = 0;
    var min: i64 = 0;
    var max: i64 = 0;
    var all = true;
    var any = false;
    var text: S = "";
    for (items.items) |v| {
        if (v.k == .err and !eq(s, "COUNT")) return v;
        if (v.k == .num) {
            if (count == 0) {
                min = v.n;
                max = v.n;
            }
            count += 1;
            sum += v.n;
            min = @min(min, v.n);
            max = @max(max, v.n);
            all = all and v.n != 0;
            any = any or v.n != 0;
        }
        if (eq(s, "CONCAT")) {
            const x = try string(v);
            text = try fmt("{s}{s}", .{ text, x.s });
        }
    }
    if (eq(s, "COUNT")) return num(count);
    if (eq(s, "CONCAT")) return .{ .k = .str, .s = text };
    if (eq(s, "MIN")) return num(min);
    if (eq(s, "MAX")) return num(max);
    if (eq(s, "AVERAGE")) return if (count == 0) err("#DIV/0!") else num(@divTrunc(sum, count));
    if (eq(s, "AND") or eq(s, "OR")) return if (count == 0) err("#VALUE!") else num(@intFromBool(if (eq(s, "AND")) all else any));
    return num(sum);
}

fn recalc() !void {
    for (0..size) |i| {
        @memset(&deps[i], false);
        if (cells[i].formula) dependencies(cells[i].n.?, &deps[i]);
    }
    @memset(&cycles, false);
    @memset(&visited, 0);
    @memset(&done, false);
    stack.clearRetainingCapacity();
    clock = 0;
    for (0..size) |i| if (cells[i].formula and visited[i] == 0) {
        try visit(i);
    };
    for (0..size) |i| {
        _ = try cellValue(i);
    }
}

const Rewrite = struct {
    mode: enum {
        copy,
        move,
        insert,
        delete
    },
    source: Rect = .{
        .a = .{ .c = 0, .r = 0 },
        .b = .{ .c = 0, .r = 0 }
    },
    dest: Rect = .{
        .a = .{ .c = 0, .r = 0 },
        .b = .{ .c = 0, .r = 0 }
    },
    dc: i32 = 0,
    dr: i32 = 0,
    col: bool = false,
    pos: i32 = 0
};

fn rewrite(n: *Node, rule: Rewrite) anyerror! *Node {
    var x = n.*;
    if (x.k == .ref or x.k == .range) {
        var rs = [_]Ref{
            x.a,
            x.b
        };
        var invalid = false;
        const range = x.k == .range;
        if (rule.mode == .move and range and !(inside(rs[0], rule.source) and inside(rs[1], rule.source))) return n;
        for (rs[0..if (range) @as(usize, 2) else 1], 0..) |*r, i| {
            switch (rule.mode) {
                .copy => {
                    if (!r.ac) r.c += rule.dc;
                    if (!r.ar) r.r += rule.dr;
                },
                .move => {
                    if (inside(r.*, rule.source)) {
                        r.c += rule.dc;
                        r.r += rule.dr;
                    } else if (!range and inside(r.*, rule.dest)) invalid = true;
                },
                .insert => {
                    const v = if (rule.col) & r.c else & r.r;
                    if (v.* >= rule.pos) v.* += 1;
                },
                .delete => {
                    const v = if (rule.col) & r.c else & r.r;
                    if (!range) {
                        if (v.* == rule.pos) invalid = true;
                        if (v.* > rule.pos) v.* -= 1;
                    } else {
                        const v0 = if (rule.col) x.a.c else x.a.r;
                        const v1 = if (rule.col) x.b.c else x.b.r;
                        if (v0 == rule.pos and v1 == rule.pos) invalid = true;
                        if (v.* > rule.pos or (i == 1 and v.* == rule.pos)) v.* -= 1;
                    }
                }
            }
            if (!valid(r.*)) invalid = true;
        }
        if (invalid) return node(.{ .k = .invalid });
        if (range) {
            const r = normalize(rs[0], rs[1]);
            x.a = r.a;
            x.b = r.b;
        } else x.a = rs[0];
    } else if (x.args.len > 0) {
        const args = try A.alloc(*Node, x.args.len);
        for (x.args, 0..) |v, i| args[i] = try rewrite(v, rule);
        x.args = args;
    }
    return node(x);
}

const Snapshot = struct {
    cells: []Cell,
    name: S
};

var history: std.ArrayList(Snapshot) = .empty;

fn content(c: Cell) !S {
    if (c.n) |n| return if (c.formula) fmt("={s}", .{ try canonical(n) }) else canonical(n);
    return "(empty)";
}

fn show(i: usize) !void {
    try line(try fmt("{s}: {s} -> {s}", .{ try refText(at(i)), try content(cells[i]), try display(values[i], true) }));
}

fn pad(n: usize, c: u8) !void {
    for (0..n) |_| try out.append(A, c);
}

fn table(r: Rect) !void {
    var widths: [26]usize = [_]usize{
        1
    } ** 26;
    for (0..size) |i| if (inside(at(i), r)) {
        widths[i % 26] = @max(widths[i % 26], (try display(values[i], false)).len);
    };
    const rw: usize = if (r.b.r >= 10) 2 else 1;
    var sep: std.ArrayList(u8) = .empty;
    try sep.append(A, '+');
    try sep.appendNTimes(A, '-', rw);
    try sep.append(A, '+');
    var c = r.a.c;
    while (c <= r.b.c): (c += 1) {
        try sep.appendNTimes(A, '-', widths[@intCast(c - 1)]);
        try sep.append(A, '+');
    }
    try line(sep.items);
    try put("|");
    try pad(rw, ' ');
    try put("|");
    c = r.a.c;
    while (c <= r.b.c): (c += 1) {
        try put(try fmt("{c}", .{ @as(u8, @intCast(c - 1)) + 'A' }));
        try pad(widths[@intCast(c - 1)] - 1, ' ');
        try put("|");
    }
    try put("\n");
    try line(sep.items);
    var row = r.a.r;
    while (row <= r.b.r): (row += 1) {
        const rs = try fmt("{d}", .{ row });
        try put("|");
        try pad(rw - rs.len, ' ');
        try put(rs);
        try put("|");
        c = r.a.c;
        while (c <= r.b.c): (c += 1) {
            const v = values[idx(.{ .r = row, .c = c })];
            const s = try display(v, false);
            const w = widths[@intCast(c - 1)];
            if (v.k == .num) try pad(w - s.len, ' ');
            try put(s);
            if (v.k != .num) try pad(w - s.len, ' ');
            try put("|");
        }
        try put("\n");
    }
    try line(sep.items);
}

fn command(text: S) anyerror!void {
    const split = std.mem.indexOfScalar(u8, text, ' ');
    const c = if (split) |i| text[0..i] else text;
    const rest = if (split) |i| text[i + 1..] else "";
    const space = std.mem.indexOfScalar(u8, rest, ' ');
    const a = if (space) |i| rest[0..i] else rest;
    const b = if (space) |i| rest[i + 1..] else "";
    if (eq(c, "LIST")) {
        var any = false;
        for (cells, 0..) |v, i| if (v.n != null) {
            any = true;
            try show(i);
        };
        if (!any) try line("(no cells)");
        return;
    }
    if (eq(c, "SHOW") or eq(c, "DEPS")) {
        const p = addr(a) orelse return fail("bad address", .{});
        const i = idx(p);
        if (eq(c, "SHOW")) {
            try show(i);
            return;
        }
        var pre: S = "";
        var dep: S = "";
        for (0..size) |j| {
            if (deps[i][j]) pre = try fmt("{s}{s}{s}", .{ pre, if (pre.len == 0) @as(S, "") else ",", try refText(at(j)) });
            if (deps[j][i]) dep = try fmt("{s}{s}{s}", .{ dep, if (dep.len == 0) @as(S, "") else ",", try refText(at(j)) });
        }
        try line(try fmt("{s}: precedents={s} dependents={s}", .{
            a,
            if (pre.len == 0) @as(S, "none") else pre,
            if (dep.len == 0) @as(S, "none") else dep
        }));
        return;
    }
    if (eq(c, "PRINT")) {
        try table(rectangle(a) orelse return fail("bad address", .{}));
        return;
    }
    const old = values;
    var target: ?Ref = null;
    var newcell: Cell = .{};
    var rect: Rect = undefined;
    var dest: Rect = undefined;
    var rule: Rewrite = undefined;
    var axis: i32 = 0;
    const row = eq(c, "INSERTROW") or eq(c, "DELETEROW");
    const col = eq(c, "INSERTCOL") or eq(c, "DELETECOL");
    const insert = eq(c, "INSERTROW") or eq(c, "INSERTCOL");
    if (eq(c, "SET")) {
        target = addr(a) orelse return fail("bad address", .{});
        if (b.len > 0 and b[0] == '=') {
            var p = Parser{
                .ts = try lex(b)
            };
            const n = try p.expression(1);
            if (p.ts[p.i].k != .end) return p.bad();
            newcell = .{ .n = n, .formula = true };
        } else if (b.len >= 2 and b[0] == '"' and b[b.len - 1] == '"' and std.mem.indexOfScalar(u8, b[1..b.len - 1], '"') == null) newcell.n = try node(.{ .k = .str, .s = b[1..b.len - 1] }) else {
            const off: usize = if (b.len > 0 and b[0] == '-') 1 else 0;
            if (!eq(b, "0")) {
                if (b.len <= off or b.len - off > 9 or b[off] < '1' or b[off] > '9') return fail("bad value", .{});
                for (b[off..]) |ch| if (!std.ascii.isDigit(ch)) return fail("bad value", .{});
            }
            newcell.n = try node(.{
                .k = .num,
                .n = std.fmt.parseInt(i64, b, 10) catch return fail("bad value", .{})
            });
        }
    } else if (eq(c, "CLEAR")) rect = rectangle(a) orelse return fail("bad address", .{}) else if (eq(c, "COPY") or eq(c, "MOVE")) {
        rect = rectangle(a) orelse return fail("bad address", .{});
        const p = addr(b) orelse return fail("bad address", .{});
        const dc = p.c - rect.a.c;
        const dr = p.r - rect.a.r;
        dest = .{
            .a = p,
            .b = .{ .c = rect.b.c + dc, .r = rect.b.r + dr }
        };
        if (!valid(dest.b)) return fail("out of grid", .{});
        rule = .{
            .mode = if (eq(c, "COPY")).copy else .move,
            .source = rect,
            .dest = dest,
            .dc = dc,
            .dr = dr
        };
    } else if (row or col) {
        if (row) {
            const p = addr(try fmt("A{s}", .{ a })) orelse return fail("bad address", .{});
            axis = p.r;
        } else {
            if (a.len != 1 or a[0] < 'A' or a[0] > 'Z') return fail("bad address", .{});
            axis = a[0] - 'A' + 1;
        }
        if (insert) {
            for (cells, 0..) |v, i| if (v.n != null and (if (col) at(i).c == 26 else at(i).r == 99)) return fail("last {s} not empty", .{ if (col) @as(S, "column") else "row" });
        }
        rule = .{ .mode = if (insert).insert else .delete, .col = col, .pos = axis };
    } else if (eq(c, "UNDO")) {
        if (history.items.len == 0) return fail("nothing to undo", .{});
        const h = history.pop().?;
        @memcpy(&cells, h.cells);
        try recalc();
        var changed: usize = 0;
        for (values, old) |v, x| if (!equal(v, x)) {
            changed += 1;
        };
        try line(try fmt("UNDO {s} changed={d}", .{ h.name, changed }));
        return;
    } else return fail("unknown command", .{});
    try history.append(A, .{ .cells = try A.dupe(Cell, &cells), .name = c });
    if (eq(c, "SET")) cells[idx(target.?)] = newcell else if (eq(c, "CLEAR")) {
        for (0..size) |i| if (inside(at(i), rect)) {
            cells[i] = .{};
        };
    } else if (eq(c, "COPY") or eq(c, "MOVE")) {
        if (eq(c, "MOVE")) {
            for (&cells) |*v| if (v.formula) {
                v.n = try rewrite(v.n.?, rule);
            };
        }
        const original = cells;
        if (eq(c, "MOVE")) for (0..size) |i| {
            if (inside(at(i), rect)) cells[i] = .{};
        };
        for (0..size) |i| if (inside(at(i), rect)) {
            const p = at(i);
            const j = idx(.{ .c = p.c + rule.dc, .r = p.r + rule.dr });
            cells[j] = original[i];
            if (eq(c, "COPY") and cells[j].formula) cells[j].n = try rewrite(cells[j].n.?, rule);
        };
    } else {
        const original = cells;
        cells = [_]Cell{
             .{}
        } ** size;
        for (0..size) |i| {
            var p = at(i);
            const v = if (col) & p.c else & p.r;
            if (!insert and v.* == axis) continue;
            if (v.* >= axis) v.* += if (insert) @as(i32, 1) else -1;
            if (valid(p)) cells[idx(p)] = original[i];
        }
        for (&cells) |*v| if (v.formula) {
            v.n = try rewrite(v.n.?, rule);
        };
    }
    try recalc();
    var changed: usize = 0;
    for (values, old) |v, x| if (!equal(v, x)) {
        changed += 1;
    };
    if (eq(c, "SET")) try line(try fmt("SET {s}={s} changed={d}", .{ a, try display(values[idx(target.?)], true), changed })) else try line(try fmt("{s} changed={d}", .{ c, changed }));
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const text = try input.interface.allocRemaining(A, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const n = try std.fmt.parseInt(usize, lines.next() orelse "0", 10);
    try recalc();
    for (0..n) |_| {
        command(std.mem.trimEnd(u8, lines.next() orelse "", "\r")) catch |e| {
            if (e != error.Invalid) return e;
            try line(try fmt("ERROR {s}", .{ why }));
        };
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(out.items);
    try sink.interface.flush();
}
