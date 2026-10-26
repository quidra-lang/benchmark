const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;

var output: std.ArrayList(u8) = .empty;

var pending: std.ArrayList(u8) = .empty;

var error_code: usize = 0;
const messages = [_]S{ "NEXT WITHOUT FOR", "RETURN WITHOUT GOSUB", "OUT OF DATA", "ILLEGAL FUNCTION CALL", "OVERFLOW", "OUT OF MEMORY", "UNDEFINED LINE NUMBER", "SUBSCRIPT OUT OF RANGE", "DUPLICATE DEFINITION", "DIVISION BY ZERO", "TYPE MISMATCH", "STRING TOO LONG", "RESUME WITHOUT ERROR", "FOR WITHOUT NEXT", "WHILE WITHOUT WEND", "WEND WITHOUT WHILE", "INPUT PAST END" };
const codes = [_]usize{ 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 20, 26, 29, 30, 62 };

fn eq(a: S, b: S) bool {
    return std.mem.eql(u8, a, b);
}

fn fmt(comptime f: S, a: anytype) !S {
    return std.fmt.allocPrint(A, f, a);
}

fn runtime(code: usize) anyerror {
    error_code = code;
    return error.Runtime;
}

fn syntax() anyerror {
    return error.Syntax;
}

fn endLine() !void {
    try output.appendSlice(A, std.mem.trimEnd(u8, pending.items, " "));
    try output.append(A, '\n');
    pending.clearRetainingCapacity();
}

fn message(s: S) !void {
    if (pending.items.len > 0) try endLine();
    try output.appendSlice(A, s);
    try output.append(A, '\n');
}

fn checked(n: i64) !i64 {
    if (n < -32768 or n > 32767) return runtime(6);
    return n;
}

const Value = struct { string: bool = false, n: i64 = 0, s: S = "" };

fn integer(n: i64) Value {
    return .{ .n = n };
}

fn display(v: Value) !S {
    return if (v.string) v.s else fmt("{d}", .{v.n});
}

const TokenKind = enum { word, num, str, sym };

const Token = struct { k: TokenKind, s: S };

fn lex(s: S) ![]Token {
    var ts: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == ' ') {
            i += 1;
            continue;
        }
        const start = i;
        var k: TokenKind = .sym;
        var value: S = "";
        if (s[i] == '"') {
            i += 1;
            const begin = i;
            while (i < s.len and s[i] != '"') i += 1;
            if (i == s.len) return syntax();
            value = s[begin..i];
            i += 1;
            k = .str;
        } else if (std.ascii.isDigit(s[i])) {
            while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
            const n = std.fmt.parseInt(i64, s[start..i], 10) catch return syntax();
            if (n > 32767) return syntax();
            k = .num;
        } else if (std.ascii.isUpper(s[i])) {
            if (std.mem.startsWith(u8, s[i..], "REM")) {
                try ts.append(A, .{ .k = .word, .s = "REM" });
                break;
            }
            while (i < s.len and (std.ascii.isUpper(s[i]) or std.ascii.isDigit(s[i]))) i += 1;
            if (i < s.len and s[i] == '$') i += 1;
            k = .word;
        } else if (i + 1 < s.len and (eq(s[i .. i + 2], "<>") or eq(s[i .. i + 2], "<=") or eq(s[i .. i + 2], ">="))) i += 2 else if (std.mem.indexOfScalar(u8, "+-*/^=<>() ,;:", s[i]) != null) i += 1 else return syntax();
        if (k != .str) value = s[start..i];
        try ts.append(A, .{ .k = k, .s = value });
    }
    return ts.toOwnedSlice(A);
}

fn varId(s: S) ?usize {
    if (s.len == 0) return null;
    const str = s[s.len - 1] == '$';
    const v = if (str) s[0 .. s.len - 1] else s;
    if (v.len < 1 or v.len > 2 or !std.ascii.isUpper(v[0]) or (v.len == 2 and !std.ascii.isDigit(v[1]))) return null;
    return @as(usize, v[0] - 'A') * 11 + (if (v.len == 1) @as(usize, 0) else v[1] - '0' + 1) + (if (str) @as(usize, 286) else 0);
}

fn functionName(s: S) bool {
    for ([_]S{ "ABS", "SGN", "INT", "SQR", "RND", "LEN", "ASC", "VAL", "CHR$", "STR$", "LEFT$", "RIGHT$", "MID$", "INSTR" }) |v| if (eq(s, v)) return true;
    return false;
}

const Expr = struct { k: enum { value, variable, array, call, unary, binary, special }, s: S = "", v: Value = .{}, id: usize = 0, string: bool = false, args: []const *Expr = &.{} };

fn expression(n: Expr) !*Expr {
    const p = try A.create(Expr);
    p.* = n;
    return p;
}

const Stmt = struct { kind: S, line: usize, args: []const *Expr = &.{}, targets: []const *Expr = &.{}, nums: []const usize = &.{}, yes: []*Stmt = &.{}, no: []*Stmt = &.{}, yesline: ?usize = null, noline: ?usize = null, next: ?*Stmt = null, index: usize = 0, option: S = "" };

fn statement(n: Stmt) !*Stmt {
    const p = try A.create(Stmt);
    p.* = n;
    return p;
}

const Parser = struct {
    ts: []Token,
    i: usize = 0,
    line: usize,
    fn peek(p: *Parser) S {
        return if (p.i < p.ts.len) p.ts[p.i].s else "";
    }
    fn accept(p: *Parser, s: S) bool {
        if (!eq(p.peek(), s)) return false;
        p.i += 1;
        return true;
    }
    fn expect(p: *Parser, s: S) !void {
        if (!p.accept(s)) return syntax();
    }
    fn num(p: *Parser) !usize {
        if (p.i == p.ts.len or p.ts[p.i].k != .num) return syntax();
        const n = try std.fmt.parseInt(usize, p.peek(), 10);
        p.i += 1;
        return n;
    }
    fn integerExpr(p: *Parser) !*Expr {
        const e = try p.parse(1);
        if (e.string) return syntax();
        return e;
    }
    fn target(p: *Parser, scalar: bool, integer_only: bool) !*Expr {
        const s = p.peek();
        const id = varId(s) orelse return syntax();
        if (integer_only and id >= 286) return syntax();
        p.i += 1;
        var e: Expr = .{ .k = .variable, .s = s, .id = id, .string = id >= 286 };
        if (!scalar and p.accept("(")) {
            var args: std.ArrayList(*Expr) = .empty;
            try args.append(A, try p.integerExpr());
            if (p.accept(",")) try args.append(A, try p.integerExpr());
            try p.expect(")");
            e.k = .array;
            e.args = try args.toOwnedSlice(A);
        }
        return expression(e);
    }
    fn primary(p: *Parser) anyerror!*Expr {
        if (p.accept("-")) {
            const x = try p.parse(7);
            if (x.string) return syntax();
            return expression(.{ .k = .unary, .s = "-", .args = try A.dupe(*Expr, &.{x}) });
        }
        if (p.accept("(")) {
            const x = try p.parse(1);
            try p.expect(")");
            return x;
        }
        if (p.i == p.ts.len) return syntax();
        const t = p.ts[p.i];
        if (t.k == .num) {
            p.i += 1;
            return expression(.{ .k = .value, .v = integer(try std.fmt.parseInt(i64, t.s, 10)) });
        }
        if (t.k == .str) {
            p.i += 1;
            return expression(.{ .k = .value, .string = true, .v = .{ .string = true, .s = t.s } });
        }
        if (eq(t.s, "ERR") or eq(t.s, "ERL")) {
            p.i += 1;
            return expression(.{ .k = .special, .s = t.s });
        }
        if (varId(t.s) != null) return p.target(false, false);
        if (functionName(t.s)) {
            p.i += 1;
            try p.expect("(");
            var args: std.ArrayList(*Expr) = .empty;
            while (true) {
                try args.append(A, try p.parse(1));
                if (!p.accept(",")) break;
            }
            try p.expect(")");
            const s = t.s;
            const count: usize = if (eq(s, "LEFT$") or eq(s, "RIGHT$") or eq(s, "INSTR")) 2 else 1;
            if (eq(s, "MID$")) {
                if (args.items.len != 2 and args.items.len != 3) return syntax();
            } else if (args.items.len != count) return syntax();
            for (args.items, 0..) |a, i| {
                const want = if (eq(s, "LEN") or eq(s, "ASC") or eq(s, "VAL") or eq(s, "INSTR")) true else if (eq(s, "LEFT$") or eq(s, "RIGHT$") or eq(s, "MID$")) i == 0 else false;
                if (a.string != want) return syntax();
            }
            return expression(.{ .k = .call, .s = s, .string = eq(s, "CHR$") or eq(s, "STR$") or eq(s, "LEFT$") or eq(s, "RIGHT$") or eq(s, "MID$"), .args = try args.toOwnedSlice(A) });
        }
        return syntax();
    }
    fn parse(p: *Parser, min: u8) anyerror!*Expr {
        var n: *Expr = undefined;
        if (min <= 3 and p.accept("NOT")) {
            const x = try p.parse(3);
            if (x.string) return syntax();
            n = try expression(.{ .k = .unary, .s = "NOT", .args = try A.dupe(*Expr, &.{x}) });
        } else n = try p.primary();
        while (true) {
            const op = p.peek();
            const pr: u8 = if (eq(op, "OR")) 1 else if (eq(op, "AND")) 2 else if (eq(op, "=") or eq(op, "<>") or eq(op, "<") or eq(op, ">") or eq(op, "<=") or eq(op, ">=")) 4 else if (eq(op, "+") or eq(op, "-")) 5 else if (eq(op, "*") or eq(op, "/") or eq(op, "MOD")) 6 else if (eq(op, "^")) 8 else 0;
            if (pr == 0 or pr < min) break;
            p.i += 1;
            const r = try p.parse(if (pr == 8) 7 else pr + 1);
            if ((pr == 4 or eq(op, "+")) and n.string != r.string) return syntax();
            if (pr != 4 and !eq(op, "+") and (n.string or r.string)) return syntax();
            n = try expression(.{ .k = .binary, .s = op, .string = eq(op, "+") and n.string, .args = try A.dupe(*Expr, &.{ n, r }) });
        }
        return n;
    }
    fn ended(p: *Parser) bool {
        return p.i == p.ts.len or eq(p.peek(), ":") or eq(p.peek(), "ELSE");
    }
    fn list(p: *Parser, clause: bool) anyerror![]*Stmt {
        var a: std.ArrayList(*Stmt) = .empty;
        while (true) {
            try a.append(A, try p.stmt(clause));
            if (!p.accept(":")) break;
        }
        return a.toOwnedSlice(A);
    }
    fn stmt(p: *Parser, clause: bool) anyerror!*Stmt {
        const kind = p.peek();
        if (kind.len == 0) return syntax();
        p.i += 1;
        var s: Stmt = .{ .kind = kind, .line = p.line };
        var args: std.ArrayList(*Expr) = .empty;
        var targets: std.ArrayList(*Expr) = .empty;
        var nums: std.ArrayList(usize) = .empty;
        if (eq(kind, "REM")) {} else if (eq(kind, "LET") or varId(kind) != null) {
            s.kind = "LET";
            if (!eq(kind, "LET")) p.i -= 1;
            const target = try p.target(false, false);
            try p.expect("=");
            const value = try p.parse(1);
            if (target.string != value.string) return syntax();
            try targets.append(A, target);
            try args.append(A, value);
        } else if (eq(kind, "PRINT")) {
            var need_separator = false;
            while (!p.ended()) {
                if (p.accept(";") or p.accept(",")) {
                    try args.append(A, try expression(.{ .k = .special, .s = p.ts[p.i - 1].s }));
                    need_separator = false;
                } else {
                    if (eq(p.peek(), "TAB") or eq(p.peek(), "SPC")) {
                        const op = p.peek();
                        p.i += 1;
                        try p.expect("(");
                        const e = try p.integerExpr();
                        try p.expect(")");
                        try args.append(A, try expression(.{ .k = .special, .s = op, .args = try A.dupe(*Expr, &.{e}) }));
                        need_separator = false;
                    } else {
                        if (need_separator) return syntax();
                        try args.append(A, try p.parse(1));
                        need_separator = true;
                    }
                }
            }
        } else if (eq(kind, "INPUT") or eq(kind, "READ") or eq(kind, "DIM")) {
            while (true) {
                const e = try p.target(false, false);
                if (eq(kind, "DIM") and e.k != .array) return syntax();
                try targets.append(A, e);
                if (!p.accept(",")) break;
            }
        } else if (eq(kind, "DATA")) {
            if (clause) return syntax();
            while (true) {
                const neg = p.accept("-");
                if (p.i == p.ts.len) return syntax();
                const t = p.ts[p.i];
                if (t.k != .num and t.k != .str) return syntax();
                if (neg and t.k != .num) return syntax();
                p.i += 1;
                try args.append(A, try expression(.{ .k = .value, .string = t.k == .str, .v = if (t.k == .str) .{ .string = true, .s = t.s } else integer((if (neg) @as(i64, -1) else 1) * try std.fmt.parseInt(i64, t.s, 10)) }));
                if (!p.accept(",")) break;
            }
        } else if (eq(kind, "IF")) {
            if (clause) return syntax();
            try args.append(A, try p.integerExpr());
            try p.expect("THEN");
            if (p.i < p.ts.len and p.ts[p.i].k == .num) s.yesline = try p.num() else s.yes = try p.list(true);
            if (p.accept("ELSE")) {
                if (p.i < p.ts.len and p.ts[p.i].k == .num) s.noline = try p.num() else s.no = try p.list(true);
            }
            if (p.i != p.ts.len) return syntax();
        } else if (eq(kind, "GOTO") or eq(kind, "GOSUB")) try nums.append(A, try p.num()) else if (eq(kind, "ON")) {
            if (p.accept("ERROR")) {
                s.kind = "ERROR";
                try p.expect("GOTO");
                try nums.append(A, try p.num());
            } else {
                try args.append(A, try p.integerExpr());
                if (p.accept("GOTO")) s.option = "GOTO" else if (p.accept("GOSUB")) s.option = "GOSUB" else return syntax();
                while (true) {
                    try nums.append(A, try p.num());
                    if (!p.accept(",")) break;
                }
            }
        } else if (eq(kind, "RESUME")) {
            if (p.accept("NEXT")) s.option = "NEXT" else if (p.i < p.ts.len and p.ts[p.i].k == .num) try nums.append(A, try p.num());
        } else if (eq(kind, "FOR")) {
            if (clause) return syntax();
            try targets.append(A, try p.target(true, true));
            try p.expect("=");
            try args.append(A, try p.integerExpr());
            try p.expect("TO");
            try args.append(A, try p.integerExpr());
            if (p.accept("STEP")) try args.append(A, try p.integerExpr()) else try args.append(A, try expression(.{ .k = .value, .v = integer(1) }));
        } else if (eq(kind, "NEXT")) {
            if (clause) return syntax();
            if (!p.ended()) try targets.append(A, try p.target(true, true));
        } else if (eq(kind, "WHILE")) {
            if (clause) return syntax();
            try args.append(A, try p.integerExpr());
        } else if (eq(kind, "WEND")) {
            if (clause) return syntax();
        } else if (eq(kind, "RESTORE")) {
            if (!p.ended()) try nums.append(A, try p.num());
        } else if (eq(kind, "RANDOMIZE")) try args.append(A, try p.integerExpr()) else if (!eq(kind, "RETURN") and !eq(kind, "END") and !eq(kind, "STOP")) return syntax();
        if (!p.ended()) return syntax();
        s.args = try args.toOwnedSlice(A);
        s.targets = try targets.toOwnedSlice(A);
        s.nums = try nums.toOwnedSlice(A);
        return statement(s);
    }
};

const Array = struct { bounds: [2]usize = .{ 0, 0 }, dim: usize, values: []Value };

const FrameKind = enum { gosub, forloop, whileloop };

const Frame = struct { k: FrameKind, position: ?*Stmt = null, id: usize = 0, final: i64 = 0, step: i64 = 0 };

const Datum = struct { line: usize, v: Value };

const Machine = struct {
    vars: [572]Value = @as([572]Value, @splat(.{})),
    arrays: [572]?Array = @as([572]?Array, @splat(null)),
    stack: std.ArrayList(Frame) = .empty,
    program: []*Stmt,
    lines: std.AutoHashMapUnmanaged(usize, *Stmt) = .empty,
    data: std.ArrayList(Datum) = .empty,
    read: usize = 0,
    inputs: []S,
    input: usize = 0,
    random: u64 = 1,
    handler: usize = 0,
    handling: bool = false,
    err: i64 = 0,
    erl: i64 = 0,
    error_stmt: ?*Stmt = null,
    fn create(m: *Machine, id: usize, bounds: [2]usize, dim: usize) !void {
        const count = (bounds[0] + 1) * (if (dim == 2) bounds[1] + 1 else 1);
        if (count > 10000) return runtime(7);
        const values = try A.alloc(Value, count);
        @memset(values, .{ .string = id >= 286 });
        m.arrays[id] = .{ .bounds = bounds, .dim = dim, .values = values };
    }
    fn reference(m: *Machine, e: *Expr) anyerror!*Value {
        if (e.k == .variable) return &m.vars[e.id];
        var indices: [2]i64 = .{ 0, 0 };
        for (e.args, 0..) |a, i| indices[i] = (try m.eval(a)).n;
        if (m.arrays[e.id] == null) try m.create(e.id, .{ 10, 10 }, e.args.len);
        const array = &m.arrays[e.id].?;
        if (array.dim != e.args.len) return runtime(9);
        for (indices[0..e.args.len], 0..) |v, i| if (v < 0 or v > @as(i64, @intCast(array.bounds[i]))) return runtime(9);
        const index: usize = @intCast(if (e.args.len == 1) indices[0] else indices[0] * @as(i64, @intCast(array.bounds[1] + 1)) + indices[1]);
        return &array.values[index];
    }
    fn eval(m: *Machine, e: *Expr) anyerror!Value {
        switch (e.k) {
            .value => return e.v,
            .variable, .array => return (try m.reference(e)).*,
            .special => return integer(if (eq(e.s, "ERR")) m.err else m.erl),
            .unary => {
                const v = (try m.eval(e.args[0])).n;
                return integer(if (eq(e.s, "NOT")) -1 - v else try checked(-v));
            },
            .call => {
                const vals = try A.alloc(Value, e.args.len);
                for (e.args, 0..) |a, i| vals[i] = try m.eval(a);
                return m.function(e.s, vals);
            },
            .binary => {
                const a = try m.eval(e.args[0]);
                const b = try m.eval(e.args[1]);
                const op = e.s;
                if (eq(op, "+") and a.string) {
                    const s = try fmt("{s}{s}", .{ a.s, b.s });
                    if (s.len > 255) return runtime(15);
                    return .{ .string = true, .s = s };
                }
                if (eq(op, "AND")) return integer(a.n & b.n);
                if (eq(op, "OR")) return integer(a.n | b.n);
                if (eq(op, "+")) return integer(try checked(a.n + b.n));
                if (eq(op, "-")) return integer(try checked(a.n - b.n));
                if (eq(op, "*")) return integer(try checked(a.n * b.n));
                if (eq(op, "/") or eq(op, "MOD")) {
                    if (b.n == 0) return runtime(11);
                    return integer(if (eq(op, "MOD")) @rem(a.n, b.n) else try checked(@divTrunc(a.n, b.n)));
                }
                if (eq(op, "^")) {
                    if (b.n < 0) return runtime(5);
                    var n: i64 = 1;
                    var base = a.n;
                    var exp = b.n;
                    while (exp > 0) {
                        if (@mod(exp, 2) == 1) n = try checked(n * base);
                        exp = @divTrunc(exp, 2);
                        if (exp > 0) base = try checked(base * base);
                    }
                    return integer(n);
                }
                const order = if (a.string) std.mem.order(u8, a.s, b.s) else if (a.n < b.n) std.math.Order.lt else if (a.n > b.n) std.math.Order.gt else std.math.Order.eq;
                const yes = if (eq(op, "=")) order == .eq else if (eq(op, "<>")) order != .eq else if (eq(op, "<")) order == .lt else if (eq(op, "<=")) order != .gt else if (eq(op, ">")) order == .gt else order != .lt;
                return integer(if (yes) -1 else 0);
            },
        }
    }
    fn function(m: *Machine, s: S, a: []Value) !Value {
        const x = a[0];
        if (eq(s, "ABS")) return integer(try checked(@intCast(@abs(x.n))));
        if (eq(s, "SGN")) return integer(if (x.n < 0) -1 else if (x.n > 0) 1 else 0);
        if (eq(s, "INT")) return x;
        if (eq(s, "SQR")) {
            if (x.n < 0) return runtime(5);
            var n: i64 = 0;
            while ((n + 1) * (n + 1) <= x.n) n += 1;
            return integer(n);
        }
        if (eq(s, "RND")) {
            if (x.n < 1) return runtime(5);
            m.random = m.random * 48271 % 2147483647;
            return integer(@as(i64, @intCast(m.random % @as(u64, @intCast(x.n)))) + 1);
        }
        if (eq(s, "LEN")) return integer(@intCast(x.s.len));
        if (eq(s, "ASC")) {
            if (x.s.len == 0) return runtime(5);
            return integer(x.s[0]);
        }
        if (eq(s, "VAL")) {
            var u = std.mem.trimStart(u8, x.s, " ");
            var sign: i64 = 1;
            if (u.len > 0 and (u[0] == '-' or u[0] == '+')) {
                if (u[0] == '-') sign = -1;
                u = u[1..];
            }
            var n: i64 = 0;
            for (u) |c| {
                if (!std.ascii.isDigit(c)) break;
                n = n * 10 + c - '0';
            }
            return integer(try checked(sign * n));
        }
        if (eq(s, "CHR$")) {
            if (x.n < 32 or x.n > 126) return runtime(5);
            return .{ .string = true, .s = try fmt("{c}", .{@as(u8, @intCast(x.n))}) };
        }
        if (eq(s, "STR$")) return .{ .string = true, .s = try fmt("{d}", .{x.n}) };
        if (eq(s, "INSTR")) return integer(if (std.mem.indexOf(u8, x.s, a[1].s)) |i| @intCast(i + 1) else 0);
        if (eq(s, "LEFT$") or eq(s, "RIGHT$")) {
            if (a[1].n < 0) return runtime(5);
            const n = @min(x.s.len, @as(usize, @intCast(a[1].n)));
            return .{ .string = true, .s = if (eq(s, "LEFT$")) x.s[0..n] else x.s[x.s.len - n ..] };
        }
        if (a[1].n < 1 or (a.len == 3 and a[2].n < 0)) return runtime(5);
        const begin = @min(x.s.len, @as(usize, @intCast(a[1].n - 1)));
        const end = if (a.len == 3) @min(x.s.len, begin + @as(usize, @intCast(a[2].n))) else x.s.len;
        return .{ .string = true, .s = x.s[begin..end] };
    }
    fn goto(m: *Machine, n: usize) !*Stmt {
        return m.lines.get(n) orelse runtime(8);
    }
    fn push(m: *Machine, f: Frame) !void {
        if (m.stack.items.len == 100) return runtime(7);
        try m.stack.append(A, f);
    }
    fn search(m: *Machine, kind: FrameKind, id: ?usize) ?usize {
        var i = m.stack.items.len;
        while (i > 0) {
            i -= 1;
            const f = m.stack.items[i];
            if (f.k == .gosub) break;
            if (f.k == kind and (id == null or f.id == id.?)) return i;
        }
        return null;
    }
    fn matching(m: *Machine, s: *Stmt, open: S, close: S) !?*Stmt {
        var depth: usize = 0;
        for (m.program[s.index + 1 ..]) |q| {
            if (eq(q.kind, open)) depth += 1;
            if (eq(q.kind, close)) {
                if (depth == 0) return q.next;
                depth -= 1;
            }
        }
        return runtime(if (eq(open, "FOR")) 26 else 29);
    }
    fn execute(m: *Machine, s: *Stmt) anyerror!?*Stmt {
        const c = s.kind;
        var next = s.next;
        if (eq(c, "LET")) {
            const target = try m.reference(s.targets[0]);
            const value = try m.eval(s.args[0]);
            target.* = value;
        } else if (eq(c, "PRINT")) {
            for (s.args) |e| {
                if (e.k == .special and !eq(e.s, "ERR") and !eq(e.s, "ERL")) {
                    var count: usize = 0;
                    if (eq(e.s, ",")) count = 10 - pending.items.len % 10 else if (eq(e.s, "TAB") or eq(e.s, "SPC")) {
                        const n = (try m.eval(e.args[0])).n;
                        if (n < 0) return runtime(5);
                        count = if (eq(e.s, "SPC")) @intCast(n) else @as(usize, @intCast(n)) -| pending.items.len;
                    }
                    try pending.appendNTimes(A, ' ', count);
                } else try pending.appendSlice(A, try display(try m.eval(e)));
            }
            if (s.args.len == 0 or !(eq(s.args[s.args.len - 1].s, ";") or eq(s.args[s.args.len - 1].s, ","))) try endLine();
        } else if (eq(c, "INPUT")) {
            for (s.targets) |e| {
                const target = try m.reference(e);
                while (true) {
                    if (m.input == m.inputs.len) return runtime(62);
                    const data = m.inputs[m.input];
                    m.input += 1;
                    if (e.string) {
                        target.* = .{ .string = true, .s = data };
                        break;
                    }
                    var valid = data.len > 0;
                    const off: usize = if (data.len > 0 and data[0] == '-') 1 else 0;
                    if (off == data.len) valid = false;
                    for (data[off..]) |ch| if (!std.ascii.isDigit(ch)) {
                        valid = false;
                    };
                    const n = std.fmt.parseInt(i64, data, 10) catch 32768;
                    if (valid and n >= -32768 and n <= 32767) {
                        target.* = integer(n);
                        break;
                    }
                    try message("?REDO FROM START");
                }
            }
        } else if (eq(c, "READ")) {
            for (s.targets) |e| {
                const target = try m.reference(e);
                if (m.read == m.data.items.len) return runtime(4);
                const v = m.data.items[m.read].v;
                m.read += 1;
                if (v.string != e.string) return runtime(13);
                target.* = v;
            }
        } else if (eq(c, "DIM")) {
            for (s.targets) |e| {
                var bounds: [2]usize = .{ 0, 0 };
                var negative = false;
                for (e.args, 0..) |a, i| {
                    const n = (try m.eval(a)).n;
                    if (n < 0) negative = true else bounds[i] = @intCast(n);
                }
                if (m.arrays[e.id] != null) return runtime(10);
                if (negative) return runtime(5);
                try m.create(e.id, bounds, e.args.len);
            }
        } else if (eq(c, "IF")) {
            const yes = (try m.eval(s.args[0])).n != 0;
            if (yes) {
                if (s.yesline) |n| next = try m.goto(n) else if (s.yes.len > 0) next = s.yes[0];
            } else {
                if (s.noline) |n| next = try m.goto(n) else if (s.no.len > 0) next = s.no[0];
            }
        } else if (eq(c, "GOTO") or eq(c, "GOSUB")) {
            const target = try m.goto(s.nums[0]);
            if (eq(c, "GOSUB")) try m.push(.{ .k = .gosub, .position = s.next });
            next = target;
        } else if (eq(c, "ON")) {
            const n = (try m.eval(s.args[0])).n;
            if (n < 0) return runtime(5);
            if (n > 0 and n <= @as(i64, @intCast(s.nums.len))) {
                const target = try m.goto(s.nums[@intCast(n - 1)]);
                if (eq(s.option, "GOSUB")) try m.push(.{ .k = .gosub, .position = s.next });
                next = target;
            }
        } else if (eq(c, "RETURN")) {
            var i = m.stack.items.len;
            var found = false;
            while (i > 0) {
                i -= 1;
                if (m.stack.items[i].k == .gosub) {
                    next = m.stack.items[i].position;
                    m.stack.shrinkRetainingCapacity(i);
                    found = true;
                    break;
                }
            }
            if (!found) return runtime(3);
        } else if (eq(c, "FOR")) {
            const a = (try m.eval(s.args[0])).n;
            const b = (try m.eval(s.args[1])).n;
            const step = (try m.eval(s.args[2])).n;
            if (step == 0) return runtime(5);
            const id = s.targets[0].id;
            if (m.search(.forloop, id)) |i| m.stack.shrinkRetainingCapacity(i);
            m.vars[id] = integer(a);
            if ((step > 0 and a > b) or (step < 0 and a < b)) next = try m.matching(s, "FOR", "NEXT") else try m.push(.{ .k = .forloop, .position = s.next, .id = id, .final = b, .step = step });
        } else if (eq(c, "NEXT")) {
            const i = m.search(.forloop, if (s.targets.len > 0) s.targets[0].id else null) orelse return runtime(1);
            m.stack.shrinkRetainingCapacity(i + 1);
            const f = m.stack.items[i];
            const n = try checked(m.vars[f.id].n + f.step);
            m.vars[f.id] = integer(n);
            if ((f.step > 0 and n > f.final) or (f.step < 0 and n < f.final)) m.stack.shrinkRetainingCapacity(i) else next = f.position;
        } else if (eq(c, "WHILE")) {
            if ((try m.eval(s.args[0])).n != 0) try m.push(.{ .k = .whileloop, .position = s }) else next = try m.matching(s, "WHILE", "WEND");
        } else if (eq(c, "WEND")) {
            const i = m.search(.whileloop, null) orelse return runtime(30);
            next = m.stack.items[i].position;
            m.stack.shrinkRetainingCapacity(i);
        } else if (eq(c, "RESTORE")) {
            if (s.nums.len > 0) {
                _ = try m.goto(s.nums[0]);
                m.read = 0;
                while (m.read < m.data.items.len and m.data.items[m.read].line < s.nums[0]) m.read += 1;
            } else m.read = 0;
        } else if (eq(c, "RANDOMIZE")) {
            const n = (try m.eval(s.args[0])).n;
            if (n < 1) return runtime(5);
            m.random = @intCast(n);
        } else if (eq(c, "ERROR")) {
            const n = s.nums[0];
            if (n != 0) {
                _ = try m.goto(n);
            }
            m.handler = n;
        } else if (eq(c, "RESUME")) {
            if (!m.handling) return runtime(20);
            if (s.nums.len > 0) next = try m.goto(s.nums[0]) else if (eq(s.option, "NEXT")) next = m.error_stmt.?.next else next = m.error_stmt;
            m.handling = false;
        } else if (eq(c, "END")) next = null else if (eq(c, "STOP")) {
            try message(try fmt("BREAK IN LINE {d}", .{s.line}));
            next = null;
        }
        return next;
    }
    fn run(m: *Machine) !void {
        for (286..572) |i| m.vars[i].string = true;
        for (m.program) |s| {
            if (!m.lines.contains(s.line)) try m.lines.put(A, s.line, s);
            if (eq(s.kind, "DATA")) for (s.args) |e| {
                try m.data.append(A, .{ .line = s.line, .v = e.v });
            };
        }
        var pc: ?*Stmt = if (m.program.len > 0) m.program[0] else null;
        while (pc) |s| {
            pc = m.execute(s) catch |e| {
                if (e != error.Runtime) return e;
                if (m.handler != 0 and !m.handling) {
                    m.err = @intCast(error_code);
                    m.erl = @intCast(s.line);
                    m.error_stmt = s;
                    m.handling = true;
                    pc = try m.goto(m.handler);
                    continue;
                }
                var msg: S = "";
                for (codes, messages) |code, label| if (code == error_code) {
                    msg = label;
                    break;
                };
                try message(try fmt("ERROR IN LINE {d}: {s}", .{ s.line, msg }));
                break;
            };
        }
    }
};

fn wire(list: []*Stmt, next: ?*Stmt) void {
    for (list, 0..) |s, i| {
        s.next = if (i + 1 < list.len) list[i + 1] else next;
        wire(s.yes, s.next);
        wire(s.no, s.next);
    }
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const all = try input.interface.allocRemaining(A, .unlimited);
    var it = std.mem.splitScalar(u8, all, '\n');
    const count = try std.fmt.parseInt(usize, it.next() orelse "0", 10);
    for (0..count) |_| {
        var stored: [10000]?S = @as([10000]?S, @splat(null));
        while (it.next()) |raw| {
            const s = std.mem.trimEnd(u8, raw, "\r");
            if (eq(s, "RUN")) break;
            const space = std.mem.indexOfScalar(u8, s, ' ');
            const n = try std.fmt.parseInt(usize, if (space) |i| s[0..i] else s, 10);
            stored[n] = if (space) |i| std.mem.trimStart(u8, s[i + 1 ..], " ") else null;
        }
        var inputs: std.ArrayList(S) = .empty;
        while (it.next()) |raw| {
            const s = std.mem.trimEnd(u8, raw, "\r");
            if (eq(s, "END")) break;
            try inputs.append(A, s);
        }
        var program: std.ArrayList(*Stmt) = .empty;
        var bad: ?usize = null;
        for (stored, 0..) |source, n| if (source) |s| {
            const ts = lex(s) catch |e| {
                if (e != error.Syntax) return e;
                bad = n;
                break;
            };
            var p = Parser{ .ts = ts, .line = n };
            const statements = p.list(false) catch |e| {
                if (e != error.Syntax) return e;
                bad = n;
                break;
            };
            if (p.i != p.ts.len) {
                bad = n;
                break;
            }
            try program.appendSlice(A, statements);
        };
        if (bad) |n| try message(try fmt("ERROR IN LINE {d}: SYNTAX ERROR", .{n})) else {
            wire(program.items, null);
            for (program.items, 0..) |s, i| s.index = i;
            var m = Machine{ .program = program.items, .inputs = inputs.items };
            try m.run();
        }
        if (pending.items.len > 0) try endLine();
        try message("READY");
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(output.items);
    try sink.interface.flush();
}
