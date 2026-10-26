const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;

var output: std.ArrayList(u8) = .empty;

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
    try output.appendSlice(A, s);
}

fn line(s: S) !void {
    try put(s);
    try put("\n");
}

fn listed(s: S, items: []const S) bool {
    for (items) |v| if (eq(s, v)) return true;
    return false;
}

const Type = enum { nil, int, text };

const Value = struct { t: Type = .nil, n: i64 = 0, s: S = "" };

fn integer(n: i64) Value {
    return .{ .t = .int, .n = n };
}

fn compatible(a: Type, b: Type) bool {
    return a == b or a == .nil or b == .nil;
}

fn cmp(a: Value, b: Value) i32 {
    if (a.t == .nil) return if (b.t == .nil) 0 else -1;
    if (b.t == .nil) return 1;
    if (a.t == .int) return if (a.n < b.n) -1 else if (a.n > b.n) 1 else 0;
    const o = std.mem.order(u8, a.s, b.s);
    return if (o == .lt) -1 else if (o == .gt) 1 else 0;
}

fn truth(v: Value) bool {
    return v.t != .nil and v.n != 0;
}

fn text(v: Value) !S {
    return switch (v.t) {
        .nil => "NULL",
        .int => fmt("{d}", .{v.n}),
        .text => v.s,
    };
}

fn same(a: []const Value, b: []const Value) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (cmp(x, y) != 0) return false;
    return true;
}

const TokenKind = enum { name, word, int, str, sym };

const Token = struct { k: TokenKind, raw: S, s: S };
const reserved = [_]S{ "SELECT", "DISTINCT", "FROM", "AS", "JOIN", "INNER", "LEFT", "OUTER", "ON", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "DROP", "PRIMARY", "KEY", "NOT", "NULL", "INT", "TEXT", "AND", "OR", "IS", "IN", "BETWEEN", "LIKE", "COUNT", "SUM", "MIN", "MAX", "AVG", "EXIT" };

fn lex(s: S) ![]Token {
    var ts: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == ' ' or c == '\n' or c == '\r') {
            i += 1;
            continue;
        }
        if (c == '-' and i + 1 < s.len and s[i + 1] == '-') {
            while (i < s.len and s[i] != '\n') i += 1;
            continue;
        }
        const start = i;
        var k: TokenKind = .sym;
        var value: S = "";
        if (c == '\'') {
            i += 1;
            const begin = i;
            while (i < s.len and s[i] != '\'') i += 1;
            value = s[begin..i];
            i += 1;
            k = .str;
        } else if (std.ascii.isDigit(c)) {
            while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
            k = .int;
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) i += 1;
            const upper = try A.dupe(u8, s[start..i]);
            for (upper) |*ch| ch.* = std.ascii.toUpper(ch.*);
            if (listed(upper, &reserved)) {
                k = .word;
                value = upper;
            } else k = .name;
        } else if (i + 1 < s.len and listed(s[i .. i + 2], &.{ "<>", "!=", "<=", ">=", "||" })) {
            i += 2;
        } else if (std.mem.indexOfScalar(u8, "(),.;*/%+-=<>", c) != null) i += 1 else return fail("unexpected character '{c}'", .{c});
        if (value.len == 0 and k != .str) value = s[start..i];
        try ts.append(A, .{ .k = k, .raw = s[start..i], .s = value });
    }
    return ts.toOwnedSlice(A);
}

const Expr = struct { k: enum { value, col, unary, binary, isnull, in, between, like, aggregate, paren }, s: S = "", qual: S = "", v: Value = .{}, args: []const *Expr = &.{}, neg: bool = false, distinct: bool = false, star: bool = false, index: usize = 0, t: Type = .nil, heading: S = "", bare: bool = false };

fn expr(n: Expr) !*Expr {
    const p = try A.create(Expr);
    p.* = n;
    return p;
}

const Column = struct { name: S, t: Type, notnull: bool = false, pk: usize = 0 };

const Table = struct { name: S, cols: []Column, rows: []const []Value = &.{} };

var tables: std.ArrayList(Table) = .empty;

fn findTable(s: S) ?usize {
    for (tables.items, 0..) |t, i| if (eq(t.name, s)) return i;
    return null;
}

fn tableId(s: S) !usize {
    return findTable(s) orelse fail("unknown table {s}", .{s});
}

const Source = struct { name: S, alias: S = "", on: ?*Expr = null, left: bool = false };

const Item = struct { e: *Expr, alias: S = "" };

const Order = struct { e: *Expr, desc: bool = false, key: ?usize = null };

const Assignment = struct { name: S, e: *Expr };

const Statement = struct { k: enum { empty, exit, create, drop, insert, update, delete, select }, name: S = "", cols: []Column = &.{}, targets: []S = &.{}, tuples: [][]*Expr = &.{}, assigns: []Assignment = &.{}, where: ?*Expr = null, sources: []Source = &.{}, items: []Item = &.{}, star: bool = false, distinct: bool = false, groups: []*Expr = &.{}, having: ?*Expr = null, orders: []Order = &.{}, limit: ?usize = null, offset: usize = 0 };

const Parser = struct {
    ts: []Token,
    i: usize = 0,
    fn peek(p: *Parser) S {
        return if (p.i < p.ts.len) p.ts[p.i].s else "";
    }
    fn accept(p: *Parser, s: S) bool {
        if (!eq(p.peek(), s)) return false;
        p.i += 1;
        return true;
    }
    fn bad(p: *Parser) anyerror {
        return fail("syntax error at '{s}'", .{if (p.i < p.ts.len) p.ts[p.i].raw else ";"});
    }
    fn expect(p: *Parser, s: S) !void {
        if (!p.accept(s)) return p.bad();
    }
    fn name(p: *Parser) !S {
        if (p.i == p.ts.len or p.ts[p.i].k != .name) return p.bad();
        const s = p.peek();
        p.i += 1;
        return s;
    }
    fn number(p: *Parser) !usize {
        if (p.i == p.ts.len or p.ts[p.i].k != .int) return p.bad();
        const s = p.peek();
        p.i += 1;
        return std.fmt.parseInt(usize, s, 10);
    }
    fn heading(p: *Parser, start: usize, end: usize) !S {
        var s: S = "";
        for (p.ts[start..end], 0..) |t, i| s = try fmt("{s}{s}{s}", .{ s, if (i > 0 and t.k != .sym and p.ts[start + i - 1].k != .sym) @as(S, " ") else "", t.raw });
        return s;
    }
    fn primary(p: *Parser) anyerror!*Expr {
        const start = p.i;
        if (p.accept("-")) return expr(.{ .k = .unary, .s = "-", .args = try A.dupe(*Expr, &.{try p.parse(7)}) });
        if (p.accept("(")) {
            const x = try p.parse(1);
            try p.expect(")");
            return expr(.{ .k = .paren, .args = try A.dupe(*Expr, &.{x}) });
        }
        if (p.i >= p.ts.len) return p.bad();
        const t = p.ts[p.i];
        p.i += 1;
        if (t.k == .int) return expr(.{ .k = .value, .v = integer(try std.fmt.parseInt(i64, t.s, 10)), .bare = true });
        if (t.k == .str) return expr(.{ .k = .value, .v = .{ .t = .text, .s = t.s } });
        if (eq(t.s, "NULL")) return expr(.{ .k = .value });
        if (t.k == .name) {
            var qual: S = "";
            var s = t.s;
            if (p.accept(".")) {
                qual = s;
                s = try p.name();
            }
            return expr(.{ .k = .col, .s = s, .qual = qual, .bare = qual.len == 0 });
        }
        if (listed(t.s, &.{ "COUNT", "SUM", "MIN", "MAX", "AVG" })) {
            try p.expect("(");
            var n: Expr = .{ .k = .aggregate, .s = t.s };
            if (eq(t.s, "COUNT") and p.accept("*")) n.star = true else {
                n.distinct = p.accept("DISTINCT");
                n.args = try A.dupe(*Expr, &.{try p.parse(1)});
            }
            try p.expect(")");
            return expr(n);
        }
        p.i = start;
        return p.bad();
    }
    fn parse(p: *Parser, min: u8) anyerror!*Expr {
        const start = p.i;
        var n: *Expr = undefined;
        if (min <= 3 and p.accept("NOT")) n = try expr(.{ .k = .unary, .s = "NOT", .args = try A.dupe(*Expr, &.{try p.parse(3)}) }) else n = try p.primary();
        var compared = false;
        while (true) {
            const op = p.peek();
            const prec: u8 = if (eq(op, "OR")) 1 else if (eq(op, "AND")) 2 else if (listed(op, &.{ "=", "<>", "!=", "<", "<=", ">", ">=", "IS", "IN", "BETWEEN", "LIKE", "NOT" })) 4 else if (listed(op, &.{ "+", "-", "||" })) 5 else if (listed(op, &.{ "*", "/", "%" })) 6 else 0;
            if (prec == 0 or prec < min or (prec == 4 and compared)) break;
            p.i += 1;
            if (prec == 4) {
                var neg = false;
                var cmpop = op;
                if (eq(op, "NOT")) {
                    neg = true;
                    cmpop = p.peek();
                    if (!listed(cmpop, &.{ "IN", "BETWEEN", "LIKE" })) return p.bad();
                    p.i += 1;
                }
                if (eq(cmpop, "IS")) {
                    neg = p.accept("NOT");
                    try p.expect("NULL");
                    n = try expr(.{ .k = .isnull, .neg = neg, .args = try A.dupe(*Expr, &.{n}) });
                } else if (eq(cmpop, "IN")) {
                    try p.expect("(");
                    var args: std.ArrayList(*Expr) = .empty;
                    try args.append(A, n);
                    while (true) {
                        try args.append(A, try p.parse(1));
                        if (!p.accept(",")) break;
                    }
                    try p.expect(")");
                    n = try expr(.{ .k = .in, .neg = neg, .args = try args.toOwnedSlice(A) });
                } else if (eq(cmpop, "BETWEEN")) {
                    const a = try p.parse(5);
                    try p.expect("AND");
                    const b = try p.parse(5);
                    n = try expr(.{ .k = .between, .neg = neg, .args = try A.dupe(*Expr, &.{ n, a, b }) });
                } else {
                    const r = try p.parse(5);
                    n = try expr(.{ .k = if (eq(cmpop, "LIKE")) .like else .binary, .s = cmpop, .neg = neg, .args = try A.dupe(*Expr, &.{ n, r }) });
                }
                compared = true;
                continue;
            }
            const r = try p.parse(prec + 1);
            n = try expr(.{ .k = .binary, .s = op, .args = try A.dupe(*Expr, &.{ n, r }) });
        }
        n.heading = try p.heading(start, p.i);
        return n;
    }
    fn source(p: *Parser) !Source {
        var s: Source = .{ .name = try p.name() };
        if (p.accept("AS")) s.alias = try p.name() else if (p.i < p.ts.len and p.ts[p.i].k == .name) s.alias = try p.name();
        return s;
    }
    fn statement(p: *Parser) anyerror!Statement {
        var s: Statement = .{ .k = .empty };
        if (p.accept(";")) return s;
        if (p.accept("EXIT")) s.k = .exit else if (p.accept("CREATE")) {
            s.k = .create;
            try p.expect("TABLE");
            s.name = try p.name();
            try p.expect("(");
            var cs: std.ArrayList(Column) = .empty;
            while (true) {
                var c: Column = .{ .name = try p.name(), .t = .int };
                if (p.accept("INT")) c.t = .int else if (p.accept("TEXT")) c.t = .text else return p.bad();
                while (true) {
                    if (p.accept("PRIMARY")) {
                        try p.expect("KEY");
                        c.pk += 1;
                        c.notnull = true;
                    } else if (p.accept("NOT")) {
                        try p.expect("NULL");
                        c.notnull = true;
                    } else break;
                }
                try cs.append(A, c);
                if (!p.accept(",")) break;
            }
            try p.expect(")");
            s.cols = try cs.toOwnedSlice(A);
        } else if (p.accept("DROP")) {
            s.k = .drop;
            try p.expect("TABLE");
            s.name = try p.name();
        } else if (p.accept("INSERT")) {
            s.k = .insert;
            try p.expect("INTO");
            s.name = try p.name();
            var targets: std.ArrayList(S) = .empty;
            if (p.accept("(")) {
                while (true) {
                    try targets.append(A, try p.name());
                    if (!p.accept(",")) break;
                }
                try p.expect(")");
            }
            s.targets = try targets.toOwnedSlice(A);
            try p.expect("VALUES");
            var tuples: std.ArrayList([]*Expr) = .empty;
            while (true) {
                try p.expect("(");
                var es: std.ArrayList(*Expr) = .empty;
                while (true) {
                    try es.append(A, try p.parse(1));
                    if (!p.accept(",")) break;
                }
                try p.expect(")");
                try tuples.append(A, try es.toOwnedSlice(A));
                if (!p.accept(",")) break;
            }
            s.tuples = try tuples.toOwnedSlice(A);
        } else if (p.accept("UPDATE")) {
            s.k = .update;
            s.name = try p.name();
            try p.expect("SET");
            var assignments: std.ArrayList(Assignment) = .empty;
            while (true) {
                const n = try p.name();
                try p.expect("=");
                try assignments.append(A, .{ .name = n, .e = try p.parse(1) });
                if (!p.accept(",")) break;
            }
            s.assigns = try assignments.toOwnedSlice(A);
            if (p.accept("WHERE")) s.where = try p.parse(1);
        } else if (p.accept("DELETE")) {
            s.k = .delete;
            try p.expect("FROM");
            s.name = try p.name();
            if (p.accept("WHERE")) s.where = try p.parse(1);
        } else if (p.accept("SELECT")) {
            s.k = .select;
            s.distinct = p.accept("DISTINCT");
            s.star = p.accept("*");
            var items: std.ArrayList(Item) = .empty;
            if (!s.star) {
                while (true) {
                    var item: Item = .{ .e = try p.parse(1) };
                    if (p.accept("AS")) item.alias = try p.name() else if (p.i < p.ts.len and p.ts[p.i].k == .name) item.alias = try p.name();
                    try items.append(A, item);
                    if (!p.accept(",")) break;
                }
            }
            s.items = try items.toOwnedSlice(A);
            try p.expect("FROM");
            var sources: std.ArrayList(Source) = .empty;
            try sources.append(A, try p.source());
            while (listed(p.peek(), &.{ "JOIN", "INNER", "LEFT" })) {
                const left = p.accept("LEFT");
                if (left) {
                    _ = p.accept("OUTER");
                } else {
                    _ = p.accept("INNER");
                }
                try p.expect("JOIN");
                var src = try p.source();
                src.left = left;
                try p.expect("ON");
                src.on = try p.parse(1);
                try sources.append(A, src);
            }
            s.sources = try sources.toOwnedSlice(A);
            if (p.accept("WHERE")) s.where = try p.parse(1);
            var gs: std.ArrayList(*Expr) = .empty;
            if (p.accept("GROUP")) {
                try p.expect("BY");
                while (true) {
                    const n = try p.name();
                    const r = try expr(.{ .k = .col, .s = n });
                    if (p.accept(".")) {
                        r.qual = n;
                        r.s = try p.name();
                    }
                    try gs.append(A, r);
                    if (!p.accept(",")) break;
                }
            }
            s.groups = try gs.toOwnedSlice(A);
            if (p.accept("HAVING")) s.having = try p.parse(1);
            var orders: std.ArrayList(Order) = .empty;
            if (p.accept("ORDER")) {
                try p.expect("BY");
                while (true) {
                    var o: Order = .{ .e = try p.parse(1) };
                    o.desc = p.accept("DESC");
                    if (!o.desc) _ = p.accept("ASC");
                    try orders.append(A, o);
                    if (!p.accept(",")) break;
                }
            }
            s.orders = try orders.toOwnedSlice(A);
            if (p.accept("LIMIT")) {
                s.limit = try p.number();
                if (p.accept("OFFSET")) s.offset = try p.number();
            }
        } else return p.bad();
        try p.expect(";");
        if (p.i != p.ts.len) return p.bad();
        return s;
    }
};

const Scope = struct { name: S, table: usize, offset: usize };

fn written(n: *Expr) !S {
    return if (n.qual.len == 0) n.s else fmt("{s}.{s}", .{ n.qual, n.s });
}

fn resolve(n: *Expr, scope: []const Scope) !Type {
    var found: ?struct { index: usize, t: Type } = null;
    var has_table = false;
    for (scope) |s| {
        if (n.qual.len > 0 and !eq(n.qual, s.name)) continue;
        has_table = true;
        for (tables.items[s.table].cols, 0..) |c, i| if (eq(c.name, n.s)) {
            if (found != null) return fail("ambiguous column {s}", .{n.s});
            found = .{ .index = s.offset + i, .t = c.t };
        };
    }
    if (!has_table and n.qual.len > 0) return fail("unknown table {s}", .{n.qual});
    const f = found orelse return fail("unknown column {s}", .{try written(n)});
    n.index = f.index;
    return f.t;
}

fn checked(n: *Expr, scope: []const Scope, aggregates: bool, grouping: bool, groups: []const usize, inside: bool) anyerror!Type {
    var t: Type = .int;
    switch (n.k) {
        .value => t = n.v.t,
        .col => {
            t = try resolve(n, scope);
            if (grouping and !inside) {
                var found = false;
                for (groups) |i| if (i == n.index) {
                    found = true;
                };
                if (!found) return fail("column {s} is not grouped", .{try written(n)});
            }
        },
        .aggregate => {
            if (!aggregates or inside) return fail("misuse of aggregate {s}", .{n.s});
            if (!n.star) {
                const a = try checked(n.args[0], scope, aggregates, grouping, groups, true);
                if ((eq(n.s, "SUM") or eq(n.s, "AVG")) and !compatible(a, .int)) return fail("type mismatch for {s}", .{n.s});
                if (eq(n.s, "MIN") or eq(n.s, "MAX")) t = a;
            }
        },
        .paren => t = try checked(n.args[0], scope, aggregates, grouping, groups, inside),
        else => {
            const types = try A.alloc(Type, n.args.len);
            for (n.args, 0..) |a, i| types[i] = try checked(a, scope, aggregates, grouping, groups, inside);
            const op = if (n.k == .in) @as(S, "IN") else if (n.k == .between) "BETWEEN" else if (n.k == .like) "LIKE" else n.s;
            if (n.k == .isnull) {} else if (n.k == .in or n.k == .between or (n.k == .binary and listed(n.s, &.{ "=", "<>", "!=", "<", "<=", ">", ">=" }))) {
                for (types[1..]) |x| if (!compatible(types[0], x)) return fail("type mismatch for {s}", .{op});
            } else {
                const want: Type = if (eq(op, "||") or n.k == .like) .text else .int;
                for (types) |x| if (!compatible(x, want)) return fail("type mismatch for {s}", .{op});
                if (eq(op, "||")) t = .text;
            }
        },
    }
    n.t = t;
    return t;
}

fn condition(n: *Expr, scope: []const Scope, ag: bool, grouping: bool, groups: []const usize, kind: S) !void {
    const t = try checked(n, scope, ag, grouping, groups, false);
    if (!compatible(t, .int)) return fail("type mismatch for {s}", .{kind});
}

fn logical(op: S, a: Value, b: Value) Value {
    if (eq(op, "AND")) {
        if ((a.t != .nil and a.n == 0) or (b.t != .nil and b.n == 0)) return integer(0);
        if (a.t == .nil or b.t == .nil) return .{};
        return integer(1);
    }
    if (truth(a) or truth(b)) return integer(1);
    if (a.t == .nil or b.t == .nil) return .{};
    return integer(0);
}

fn relation(op: S, a: Value, b: Value) Value {
    if (a.t == .nil or b.t == .nil) return .{};
    const c = cmp(a, b);
    return integer(@intFromBool(if (eq(op, "=")) c == 0 else if (eq(op, "<>") or eq(op, "!=")) c != 0 else if (eq(op, "<")) c < 0 else if (eq(op, "<=")) c <= 0 else if (eq(op, ">")) c > 0 else c >= 0));
}

fn negate(v: Value) Value {
    return if (v.t == .nil) v else integer(@intFromBool(v.n == 0));
}

fn like(s: S, p: S) bool {
    var i: usize = 0;
    var j: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (i < s.len) {
        if (j < p.len and (p[j] == '_' or p[j] == s[i])) {
            i += 1;
            j += 1;
        } else if (j < p.len and p[j] == '%') {
            star = j;
            j += 1;
            retry = i;
        } else if (star) |at| {
            retry += 1;
            i = retry;
            j = at + 1;
        } else return false;
    }
    while (j < p.len and p[j] == '%') j += 1;
    return j == p.len;
}

fn eval(n: *Expr, row: []const Value, group: []const []Value) anyerror!Value {
    switch (n.k) {
        .value => return n.v,
        .col => return row[n.index],
        .paren => return eval(n.args[0], row, group),
        .aggregate => {
            if (n.star) return integer(@intCast(group.len));
            var vals: std.ArrayList(Value) = .empty;
            for (group) |r| {
                const v = try eval(n.args[0], r, &.{});
                if (v.t == .nil) continue;
                var duplicate = false;
                if (n.distinct) for (vals.items) |x| {
                    if (cmp(v, x) == 0) duplicate = true;
                };
                if (!duplicate) try vals.append(A, v);
            }
            if (eq(n.s, "COUNT")) return integer(@intCast(vals.items.len));
            if (vals.items.len == 0) return .{};
            var value = vals.items[0];
            if (eq(n.s, "MIN") or eq(n.s, "MAX")) {
                for (vals.items[1..]) |v| {
                    const c = cmp(v, value);
                    if ((eq(n.s, "MIN") and c < 0) or (eq(n.s, "MAX") and c > 0)) value = v;
                }
                return value;
            }
            var sum: i64 = 0;
            for (vals.items) |v| sum += v.n;
            return integer(if (eq(n.s, "AVG")) @divTrunc(sum, @as(i64, @intCast(vals.items.len))) else sum);
        },
        .unary => {
            const v = try eval(n.args[0], row, group);
            if (eq(n.s, "NOT")) return negate(v);
            return if (v.t == .nil) v else integer(-v.n);
        },
        .isnull => {
            const v = try eval(n.args[0], row, group);
            return integer(@intFromBool((v.t == .nil) != n.neg));
        },
        .in => {
            const v = try eval(n.args[0], row, group);
            var result = integer(0);
            var unknown = v.t == .nil;
            var found = false;
            for (n.args[1..]) |a| {
                const x = try eval(a, row, group);
                if (x.t == .nil) unknown = true else if (v.t != .nil and cmp(v, x) == 0) found = true;
            }
            result = if (found) integer(1) else if (unknown) .{} else integer(0);
            return if (n.neg) negate(result) else result;
        },
        .between => {
            const x = try eval(n.args[0], row, group);
            const a = try eval(n.args[1], row, group);
            const b = try eval(n.args[2], row, group);
            const v = logical("AND", relation(">=", x, a), relation("<=", x, b));
            return if (n.neg) negate(v) else v;
        },
        .like => {
            const a = try eval(n.args[0], row, group);
            const b = try eval(n.args[1], row, group);
            const v = if (a.t == .nil or b.t == .nil) @as(Value, .{}) else integer(@intFromBool(like(a.s, b.s)));
            return if (n.neg) negate(v) else v;
        },
        .binary => {
            const a = try eval(n.args[0], row, group);
            const b = try eval(n.args[1], row, group);
            if (eq(n.s, "AND") or eq(n.s, "OR")) return logical(n.s, a, b);
            if (listed(n.s, &.{ "=", "<>", "!=", "<", "<=", ">", ">=" })) return relation(n.s, a, b);
            if (a.t == .nil or b.t == .nil) return .{};
            if (eq(n.s, "||")) return .{ .t = .text, .s = try fmt("{s}{s}", .{ a.s, b.s }) };
            if (eq(n.s, "+")) return integer(a.n + b.n);
            if (eq(n.s, "-")) return integer(a.n - b.n);
            if (eq(n.s, "*")) return integer(a.n * b.n);
            if (b.n == 0) return .{};
            return integer(if (eq(n.s, "/")) @divTrunc(a.n, b.n) else @rem(a.n, b.n));
        },
    }
}

fn column(t: Table, s: S) !usize {
    for (t.cols, 0..) |c, i| if (eq(c.name, s)) return i;
    return fail("unknown column {s}", .{s});
}

fn constraints(t: Table, rows: []const []Value, targets: []const bool) !void {
    var pk: ?usize = null;
    for (t.cols, 0..) |c, i| if (c.pk > 0) {
        pk = i;
    };
    for (rows, 0..) |r, i| {
        if (!targets[i]) continue;
        for (t.cols, 0..) |c, j| if (c.notnull and r[j].t == .nil) return fail("NULL value in column {s}", .{c.name});
        if (pk) |k| for (rows, 0..) |s, j| {
            if (i != j and cmp(r[k], s[k]) == 0) return fail("duplicate primary key {s}", .{try text(r[k])});
        };
    }
}

fn hasAggregate(n: *Expr) bool {
    if (n.k == .aggregate) return true;
    for (n.args) |a| if (hasAggregate(a)) return true;
    return false;
}

const Result = struct { vals: []Value, keys: []Value, serial: usize };

fn pad(n: usize) !void {
    for (0..n) |_| try put(" ");
}

fn printResult(items: []Item, rows: []Result) !void {
    const widths = try A.alloc(usize, items.len);
    const headings = try A.alloc(S, items.len);
    for (items, 0..) |item, i| {
        headings[i] = if (item.alias.len > 0) item.alias else if (item.e.k == .col) item.e.s else item.e.heading;
        widths[i] = headings[i].len;
        for (rows) |r| widths[i] = @max(widths[i], (try text(r.vals[i])).len);
    }
    var sep: std.ArrayList(u8) = .empty;
    try sep.append(A, '+');
    for (widths) |w| {
        try sep.appendNTimes(A, '-', w + 2);
        try sep.append(A, '+');
    }
    try line(sep.items);
    try put("|");
    for (headings, 0..) |h, i| {
        try put(" ");
        try put(h);
        try pad(widths[i] - h.len);
        try put(" |");
    }
    try put("\n");
    try line(sep.items);
    for (rows) |r| {
        try put("|");
        for (r.vals, 0..) |v, i| {
            const s = try text(v);
            try put(" ");
            if (items[i].e.t == .int) try pad(widths[i] - s.len);
            try put(s);
            if (items[i].e.t != .int) try pad(widths[i] - s.len);
            try put(" |");
        }
        try put("\n");
    }
    try line(sep.items);
    try line(try fmt("({d} {s})", .{ rows.len, if (rows.len == 1) @as(S, "row") else "rows" }));
}

fn query(s: Statement) anyerror!void {
    var scope: std.ArrayList(Scope) = .empty;
    var width: usize = 0;
    for (s.sources) |src| {
        const ti = try tableId(src.name);
        const n = if (src.alias.len > 0) src.alias else src.name;
        for (scope.items) |old| if (eq(n, old.name)) return fail("duplicate table name {s}", .{n});
        try scope.append(A, .{ .name = n, .table = ti, .offset = width });
        width += tables.items[ti].cols.len;
        if (src.on) |on| try condition(on, scope.items, false, false, &.{}, "ON");
    }
    if (s.where) |w| try condition(w, scope.items, false, false, &.{}, "WHERE");
    const groups = try A.alloc(usize, s.groups.len);
    for (s.groups, 0..) |g, i| {
        _ = try resolve(g, scope.items);
        groups[i] = g.index;
    }
    var aggregate = s.groups.len > 0 or s.having != null;
    for (s.items) |i| aggregate = aggregate or hasAggregate(i.e);
    for (s.orders) |o| aggregate = aggregate or hasAggregate(o.e);
    var items: std.ArrayList(Item) = .empty;
    if (s.star) {
        for (scope.items) |src| for (tables.items[src.table].cols) |c| {
            try items.append(A, .{ .e = try expr(.{ .k = .col, .s = c.name, .qual = src.name }) });
        };
    } else try items.appendSlice(A, s.items);
    for (items.items) |item| {
        _ = try checked(item.e, scope.items, true, aggregate, groups, false);
    }
    if (s.having) |h| try condition(h, scope.items, true, aggregate, groups, "HAVING");
    for (s.orders) |*order| {
        const e = order.e;
        if (e.k == .value and e.v.t == .int and e.bare) {
            if (e.v.n < 1 or e.v.n > @as(i64, @intCast(items.items.len))) return fail("ORDER BY position {d} is out of range", .{e.v.n});
            order.key = @intCast(e.v.n - 1);
        } else if (e.k == .col and e.bare) {
            for (items.items, 0..) |item, i| if (item.alias.len > 0 and eq(item.alias, e.s)) {
                order.key = i;
                break;
            };
        }
        if (order.key == null) {
            _ = try checked(e, scope.items, true, aggregate, groups, false);
        }
    }
    var rows: std.ArrayList([]Value) = .empty;
    for (tables.items[scope.items[0].table].rows) |r| try rows.append(A, try A.dupe(Value, r));
    for (s.sources[1..], 1..) |src, j| {
        var joined: std.ArrayList([]Value) = .empty;
        const t = tables.items[scope.items[j].table];
        for (rows.items) |left| {
            var found = false;
            for (t.rows) |right| {
                const combined = try A.alloc(Value, left.len + right.len);
                @memcpy(combined[0..left.len], left);
                @memcpy(combined[left.len..], right);
                if (truth(try eval(src.on.?, combined, &.{}))) {
                    try joined.append(A, combined);
                    found = true;
                }
            }
            if (src.left and !found) {
                const combined = try A.alloc(Value, left.len + t.cols.len);
                @memcpy(combined[0..left.len], left);
                @memset(combined[left.len..], .{});
                try joined.append(A, combined);
            }
        }
        rows = joined;
    }
    if (s.where) |w| {
        var filtered: std.ArrayList([]Value) = .empty;
        for (rows.items) |r| if (truth(try eval(w, r, &.{}))) {
            try filtered.append(A, r);
        };
        rows = filtered;
    }
    var grouped: std.ArrayList(std.ArrayList([]Value)) = .empty;
    if (aggregate) {
        if (groups.len == 0) {
            var g: std.ArrayList([]Value) = .empty;
            try g.appendSlice(A, rows.items);
            try grouped.append(A, g);
        } else for (rows.items) |r| {
            var found = false;
            for (grouped.items) |*g| {
                var match = true;
                for (groups) |i| if (cmp(g.items[0][i], r[i]) != 0) {
                    match = false;
                };
                if (match) {
                    try g.append(A, r);
                    found = true;
                    break;
                }
            }
            if (!found) {
                var g: std.ArrayList([]Value) = .empty;
                try g.append(A, r);
                try grouped.append(A, g);
            }
        }
    } else for (rows.items) |r| {
        var g: std.ArrayList([]Value) = .empty;
        try g.append(A, r);
        try grouped.append(A, g);
    }
    var result: std.ArrayList(Result) = .empty;
    const empty = try A.alloc(Value, width);
    @memset(empty, .{});
    for (grouped.items) |g| {
        const row = if (g.items.len == 0) empty else g.items[0];
        if (s.having) |h| if (!truth(try eval(h, row, g.items))) continue;
        const vals = try A.alloc(Value, items.items.len);
        for (items.items, 0..) |item, i| vals[i] = try eval(item.e, row, g.items);
        const keys = try A.alloc(Value, s.orders.len);
        for (s.orders, 0..) |o, i| keys[i] = if (o.key) |k| vals[k] else try eval(o.e, row, g.items);
        try result.append(A, .{ .vals = vals, .keys = keys, .serial = result.items.len });
    }
    const C = struct {
        fn less(orders: []Order, a: Result, b: Result) bool {
            for (orders, 0..) |o, i| {
                const c = cmp(a.keys[i], b.keys[i]);
                if (c != 0) return if (o.desc) c > 0 else c < 0;
            }
            return a.serial < b.serial;
        }
    };
    std.mem.sort(Result, result.items, s.orders, C.less);
    if (s.distinct) {
        var unique: std.ArrayList(Result) = .empty;
        for (result.items) |r| {
            var duplicate = false;
            for (unique.items) |old| if (same(old.vals, r.vals)) {
                duplicate = true;
                break;
            };
            if (!duplicate) try unique.append(A, r);
        }
        result = unique;
    }
    const begin = @min(s.offset, result.items.len);
    const end = if (s.limit) |n| @min(result.items.len, begin + n) else result.items.len;
    try printResult(items.items, result.items[begin..end]);
}

fn execute(s: Statement) anyerror!void {
    switch (s.k) {
        .empty, .exit => {},
        .create => {
            if (findTable(s.name) != null) return fail("table {s} already exists", .{s.name});
            var pks: usize = 0;
            for (s.cols, 0..) |c, i| {
                for (s.cols[0..i]) |old| if (eq(c.name, old.name)) return fail("duplicate column {s}", .{c.name});
                pks += c.pk;
                if (pks > 1) return fail("multiple primary keys", .{});
            }
            try tables.append(A, .{ .name = s.name, .cols = s.cols });
            try line(try fmt("Table {s} created.", .{s.name}));
        },
        .drop => {
            const i = try tableId(s.name);
            _ = tables.orderedRemove(i);
            try line(try fmt("Table {s} dropped.", .{s.name}));
        },
        .select => try query(s),
        .insert => {
            const ti = try tableId(s.name);
            const t = tables.items[ti];
            var targets: std.ArrayList(usize) = .empty;
            if (s.targets.len == 0) {
                for (t.cols, 0..) |_, i| try targets.append(A, i);
            } else for (s.targets) |n| {
                const i = try column(t, n);
                for (targets.items) |old| if (old == i) return fail("duplicate column {s}", .{n});
                try targets.append(A, i);
            }
            for (s.tuples) |tuple| {
                if (tuple.len != targets.items.len) return fail("expected {d} values, got {d}", .{ targets.items.len, tuple.len });
                for (tuple, targets.items) |e, i| {
                    const ty = try checked(e, &.{}, false, false, &.{}, false);
                    if (!compatible(ty, t.cols[i].t)) return fail("type mismatch for column {s}", .{t.cols[i].name});
                }
            }
            var rows: std.ArrayList([]Value) = .empty;
            try rows.appendSlice(A, t.rows);
            for (s.tuples) |tuple| {
                const row = try A.alloc(Value, t.cols.len);
                @memset(row, .{});
                for (tuple, targets.items) |e, i| row[i] = try eval(e, &.{}, &.{});
                try rows.append(A, row);
            }
            const changed = try A.alloc(bool, rows.items.len);
            @memset(changed, false);
            @memset(changed[t.rows.len..], true);
            try constraints(t, rows.items, changed);
            tables.items[ti].rows = try rows.toOwnedSlice(A);
            try line(try fmt("{d} {s} inserted.", .{ s.tuples.len, if (s.tuples.len == 1) @as(S, "row") else "rows" }));
        },
        .update, .delete => {
            const ti = try tableId(s.name);
            const t = tables.items[ti];
            const scope = [_]Scope{.{ .name = t.name, .table = ti, .offset = 0 }};
            const targets = try A.alloc(usize, s.assigns.len);
            for (s.assigns, 0..) |assignment, j| {
                const i = try column(t, assignment.name);
                for (targets[0..j]) |old| if (old == i) return fail("duplicate column {s}", .{assignment.name});
                targets[j] = i;
            }
            for (s.assigns, targets) |assignment, i| {
                const ty = try checked(assignment.e, &scope, false, false, &.{}, false);
                if (!compatible(ty, t.cols[i].t)) return fail("type mismatch for column {s}", .{t.cols[i].name});
            }
            if (s.where) |w| try condition(w, &scope, false, false, &.{}, "WHERE");
            var rows: std.ArrayList([]Value) = .empty;
            const changed = try A.alloc(bool, t.rows.len);
            @memset(changed, false);
            var count: usize = 0;
            for (t.rows, 0..) |row, j| {
                const match = if (s.where) |w| truth(try eval(w, row, &.{})) else true;
                if (match) {
                    count += 1;
                    changed[j] = true;
                    if (s.k == .delete) continue;
                    const r = try A.dupe(Value, row);
                    for (s.assigns, targets) |assignment, i| r[i] = try eval(assignment.e, row, &.{});
                    try rows.append(A, r);
                } else try rows.append(A, row);
            }
            if (s.k == .update) try constraints(t, rows.items, changed);
            tables.items[ti].rows = try rows.toOwnedSlice(A);
            try line(try fmt("{d} {s} {s}.", .{ count, if (count == 1) @as(S, "row") else "rows", if (s.k == .update) @as(S, "updated") else "deleted" }));
        },
    }
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const all = try input.interface.allocRemaining(A, .unlimited);
    var i: usize = 0;
    var start: usize = 0;
    var quoted = false;
    var comment = false;
    while (i < all.len) : (i += 1) {
        const c = all[i];
        if (comment) {
            if (c == '\n') comment = false;
            continue;
        }
        if (c == '\'') {
            quoted = !quoted;
            continue;
        }
        if (!quoted and c == '-' and i + 1 < all.len and all[i + 1] == '-') {
            comment = true;
            continue;
        }
        if (!quoted and c == ';') {
            const s = all[start .. i + 1];
            start = i + 1;
            const ts = lex(s) catch |e| {
                if (e != error.Invalid) return e;
                try line(try fmt("ERROR: {s}", .{why}));
                continue;
            };
            var parser = Parser{ .ts = ts };
            const statement = parser.statement() catch |e| {
                if (e != error.Invalid) return e;
                try line(try fmt("ERROR: {s}", .{why}));
                continue;
            };
            if (statement.k == .exit) break;
            execute(statement) catch |e| {
                if (e != error.Invalid) return e;
                try line(try fmt("ERROR: {s}", .{why}));
            };
        }
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(output.items);
    try sink.interface.flush();
}
