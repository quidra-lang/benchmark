const std = @import("std");
const Allocator = std.mem.Allocator;
const Values = std.ArrayList(Value);
const Value = union(enum) {
    integer: i64, boolean: bool, string: []const u8, symbol: []const u8, nil, pair: *Pair, procedure: *Procedure, void_value, uninitialized
};
const Pair = struct {
    car: Value, cdr: Value
};
const Environment = struct {
    frame: std.StringHashMapUnmanaged(Value) = .empty, parent: ?*Environment = null
};
const Procedure = struct {
    name: []const u8 = "", minimum: usize = 0, variadic: bool = false, builtin: bool = false, params: []const []const u8 = &.{
    }, rest: []const u8 = "", body: []const Value = &.{
    }, env: ?*Environment = null
};
fn eqs(a: []const u8, b: []const u8)bool{
    return std.mem.eql(u8, a, b);
}
fn is(v: Value, tag: std.meta.Tag(Value))bool{
    return std.meta.activeTag(v) == tag;
}
fn truth(v: Value)bool{
    return !is(v, .boolean) or v.boolean;
}
fn proper(v0: Value)bool{
    var v = v0;
    while (is(v, .pair))v = v.pair.cdr;
    return is(v, .nil);
}
fn equal(a: Value, b: Value, deep: bool)bool{
    if (std.meta.activeTag(a) != std.meta.activeTag(b))return false;
    return switch (a){
        .integer=>|n|n == b.integer,
        .boolean=>|flag|flag == b.boolean,
        .string=>|s|eqs(s, b.string),
        .symbol=>|s|eqs(s, b.symbol),
        .pair=>|p|if (deep)equal(p.car, b.pair.car, true) and equal(p.cdr, b.pair.cdr, true) else p == b.pair,
        .procedure=>|p|p == b.procedure,
        else=>true
    };
}
const Machine = struct{
    gpa: Allocator, why: []const u8 = "", output: std.ArrayList(u8) = .empty, mid: bool = false,
    fn fail(m: *Machine, comptime fmt: []const u8, args: anytype)anyerror{
        m.why = std.fmt.allocPrint(m.gpa, fmt, args) catch unreachable;
        return error.Failure;
    }
    fn pair(m: *Machine, a: Value, b: Value)anyerror!Value{
        const p = try m.gpa.create(Pair);
        p.*= .{
            .car = a, .cdr = b
        };
        return .{
            .pair = p
        };
    }
    fn list(m: *Machine, a: []const Value, tail: Value)anyerror!Value{
        var v = tail;
        var i = a.len;
        while (i>0){
            i -= 1;
            v = try m.pair(a[i], v);
        }
        return v;
    }
    fn items(m: *Machine, v0: Value)anyerror!?[]const Value{
        var a: Values = .empty;
        var v = v0;
        while (is(v, .pair)){
            try a.append(m.gpa, v.pair.car);
            v = v.pair.cdr;
        }
        return if (is(v, .nil))try a.toOwnedSlice(m.gpa) else null;
    }
    fn appendText(m: *Machine, a: *std.ArrayList(u8), s: []const u8)anyerror!void{
        try a.appendSlice(m.gpa, s);
    }
    fn render(m: *Machine, v0: Value, quoted: bool, a: *std.ArrayList(u8))anyerror!void{
        switch (v0){
            .integer=>|n|try m.appendText(a, try std.fmt.allocPrint(m.gpa, "{d}", .{
                n
            })), .boolean=>|b|try m.appendText(a, if (b)"#t" else "#f"), .symbol=>|s|try m.appendText(a, s), .nil=>try m.appendText(a, "()"), .void_value, .uninitialized=>try m.appendText(a, "#<void>"), .string=>|s|{
                if (!quoted){
                    try m.appendText(a, s);
                    return;
                }
                try a.append(m.gpa, '"');
                for (s)|c|{
                    switch (c){
                        '"'=>try m.appendText(a, "\\\""), '\\'=>try m.appendText(a, "\\\\"), '\n'=>try m.appendText(a, "\\n"), else=>try a.append(m.gpa, c)
                    }
                }
                try a.append(m.gpa, '"');
            }, .procedure=>|p|{
                try m.appendText(a, "#<procedure");
                if (p.name.len>0){
                    try a.append(m.gpa, ' ');
                    try m.appendText(a, p.name);
                }
                try a.append(m.gpa, '>');
            }, .pair=>{
                var v = v0;
                try a.append(m.gpa, '(');
                var first = true;
                while (is(v, .pair)){
                    if (!first)try a.append(m.gpa, ' ');
                    first = false;
                    try m.render(v.pair.car, quoted, a);
                    v = v.pair.cdr;
                }
                if (!is(v, .nil)){
                    try m.appendText(a, " . ");
                    try m.render(v, quoted, a);
                }
                try a.append(m.gpa, ')');
            }
        }
    }
    fn repr(m: *Machine, v: Value, quoted: bool)anyerror![]const u8{
        var a: std.ArrayList(u8) = .empty;
        try m.render(v, quoted, &a);
        return a.toOwnedSlice(m.gpa);
    }
    fn shape(m: *Machine, ok: bool, x: Value)anyerror!void{
        if (!ok)return m.fail("bad syntax: {s}", .{
            try m.repr(x, true)
        });
    }
    fn env(m: *Machine, parent: ?*Environment)anyerror!*Environment{
        const e = try m.gpa.create(Environment);
        e.*= .{
            .parent = parent
        };
        return e;
    }
    fn bind(m: *Machine, e: *Environment, n: []const u8, v: Value)anyerror!void{
        try e.frame.put(m.gpa, n, v);
    }
    fn find(m: *Machine, e0: *Environment, n: []const u8)anyerror!*Environment{
        var e: ?*Environment = e0;
        while (e)|scope|{
            if (scope.frame.contains(n))return scope;
            e = scope.parent;
        }
        return m.fail("unbound variable: {s}", .{
            n
        });
    }
    fn lookup(m: *Machine, e: *Environment, n: []const u8)anyerror!Value{
        const scope = try m.find(e, n);
        const v = scope.frame.get(n).?;
        if (is(v, .uninitialized))return m.fail("uninitialized variable: {s}", .{
            n
        });
        return v;
    }
    const Parameters = struct{
        names: []const []const u8, rest: []const u8
    };
    fn parameters(m: *Machine, v0: Value)anyerror!?Parameters{
        var names: std.ArrayList([]const u8) = .empty;
        var v = v0;
        while (is(v, .pair)){
            if (!is(v.pair.car, .symbol))return null;
            const n = v.pair.car.symbol;
            for (names.items)|old|if (eqs(n, old))return null;
            try names.append(m.gpa, n);
            v = v.pair.cdr;
        }
        var rest: []const u8 = "";
        if (!is(v, .nil)){
            if (!is(v, .symbol))return null;
            rest = v.symbol;
            for (names.items)|old|if (eqs(rest, old))return null;
        }
        return .{
            .names = try names.toOwnedSlice(m.gpa), .rest = rest
        };
    }
    fn closure(m: *Machine, p: Parameters, b: []const Value, e: *Environment, n: []const u8)anyerror!Value{
        const f = try m.gpa.create(Procedure);
        f.*= .{
            .name = n, .minimum = p.names.len, .variadic = p.rest.len>0, .params = p.names, .rest = p.rest, .body = b, .env = e
        };
        return .{
            .procedure = f
        };
    }
    const Binding = struct{
        name: []const u8, expr: Value
    };
    fn bindings(m: *Machine, v: Value, unique: bool)anyerror!?[]const Binding{
        const a = (try m.items(v)) orelse return null;
        var bs: std.ArrayList(Binding) = .empty;
        for (a)|x|{
            const b = (try m.items(x)) orelse return null;
            if (b.len != 2 or !is(b[0], .symbol))return null;
            const n = b[0].symbol;
            if (unique){
                for (bs.items)|old|{
                    if (eqs(n, old.name))return null;
                }
            }
            try bs.append(m.gpa, .{
                .name = n, .expr = b[1]
            });
        }
        return bs.toOwnedSlice(m.gpa);
    }
    fn body(m: *Machine, a: []const Value, e: *Environment)anyerror!Value{
        var v: Value = .void_value;
        for (a)|x|v = try m.evaluate(x, e);
        return v;
    }
    fn evaluate(m: *Machine, x: Value, e: *Environment)anyerror!Value{
        if (is(x, .symbol))return m.lookup(e, x.symbol);
        if (!is(x, .pair)){
            try m.shape(!is(x, .nil), x);
            return x;
        }
        const a = (try m.items(x)) orelse return m.fail("bad syntax: {s}", .{
            try m.repr(x, true)
        });
        const n = a.len;
        const h = if (is(a[0], .symbol))a[0].symbol else "";
        if (eqs(h, "quote")){
            try m.shape(n == 2, x);
            return a[1];
        }
        if (eqs(h, "if")){
            try m.shape(n == 3 or n == 4, x);
            if (truth(try m.evaluate(a[1], e)))return m.evaluate(a[2], e);
            return if (n == 4)m.evaluate(a[3], e) else .void_value;
        }
        if (eqs(h, "begin"))return m.body(a[1..], e);
        if (eqs(h, "lambda")){
            try m.shape(n >= 3, x);
            const p = (try m.parameters(a[1])) orelse return m.fail("bad syntax: {s}", .{
                try m.repr(x, true)
            });
            return m.closure(p, a[2..], e, "");
        }
        if (eqs(h, "define")){
            try m.shape(n >= 3, x);
            if (is(a[1], .symbol)){
                try m.shape(n == 3, x);
                const v = try m.evaluate(a[2], e);
                if (is(v, .procedure) and !v.procedure.builtin and v.procedure.name.len == 0)v.procedure.name = a[1].symbol;
                try m.bind(e, a[1].symbol, v);
            }
            else{
                try m.shape(is(a[1], .pair) and is(a[1].pair.car, .symbol), x);
                const p = (try m.parameters(a[1].pair.cdr)) orelse return m.fail("bad syntax: {s}", .{
                    try m.repr(x, true)
                });
                const name = a[1].pair.car.symbol;
                try m.bind(e, name, try m.closure(p, a[2..], e, name));
            }
            return .void_value;
        }
        if (eqs(h, "set!")){
            try m.shape(n == 3 and is(a[1], .symbol), x);
            const v = try m.evaluate(a[2], e);
            const scope = try m.find(e, a[1].symbol);
            try m.bind(scope, a[1].symbol, v);
            return .void_value;
        }
        if (eqs(h, "let") or eqs(h, "let*") or eqs(h, "letrec")){
            const named = eqs(h, "let") and n>1 and is(a[1], .symbol);
            const at: usize = if (named)2 else 1;
            try m.shape(n >= at+2, x);
            const bs = (try m.bindings(a[at], !eqs(h, "let*"))) orelse return m.fail("bad syntax: {s}", .{
                try m.repr(x, true)
            });
            var scope = try m.env(e);
            if (eqs(h, "let*")){
                if (bs.len>0)scope = e;
                for (bs)|b|{
                    const v = try m.evaluate(b.expr, scope);
                    scope = try m.env(scope);
                    try m.bind(scope, b.name, v);
                }
            }
            else if (eqs(h, "letrec")){
                for (bs)|b|try m.bind(scope, b.name, .uninitialized);
                for (bs)|b|try m.bind(scope, b.name, try m.evaluate(b.expr, scope));
            }
            else{
                var vs: Values = .empty;
                var names: std.ArrayList([]const u8) = .empty;
                for (bs)|b|{
                    try vs.append(m.gpa, try m.evaluate(b.expr, e));
                    try names.append(m.gpa, b.name);
                }
                if (named){
                    const name = a[1].symbol;
                    const f = try m.closure(.{
                        .names = names.items, .rest = ""
                    }, a[3..], scope, name);
                    try m.bind(scope, name, f);
                    return m.call(f, vs.items);
                }
                for (bs, vs.items)|b, v|try m.bind(scope, b.name, v);
            }
            return m.body(a[at+1..], scope);
        }
        if (eqs(h, "cond")){
            var cs: std.ArrayList([]const Value) = .empty;
            for (a[1..], 1..)|x0, i|{
                const c = (try m.items(x0)) orelse return m.fail("bad syntax: {s}", .{
                    try m.repr(x, true)
                });
                try m.shape(c.len>0, x);
                if (is(c[0], .symbol) and eqs(c[0].symbol, "else"))try m.shape(c.len >= 2 and i == n-1, x);
                try cs.append(m.gpa, c);
            }
            for (cs.items)|c|{
                if (is(c[0], .symbol) and eqs(c[0].symbol, "else"))return m.body(c[1..], e);
                const v = try m.evaluate(c[0], e);
                if (truth(v))return if (c.len == 1)v else m.body(c[1..], e);
            }
            return .void_value;
        }
        if (eqs(h, "and")){
            var v: Value = .{
                .boolean = true
            };
            for (a[1..])|z|{
                v = try m.evaluate(z, e);
                if (!truth(v))break;
            }
            return v;
        }
        if (eqs(h, "or")){
            for (a[1..])|z|{
                const v = try m.evaluate(z, e);
                if (truth(v))return v;
            }
            return .{
                .boolean = false
            };
        }
        if (eqs(h, "when") or eqs(h, "unless")){
            try m.shape(n >= 3, x);
            return if (truth(try m.evaluate(a[1], e)) == eqs(h, "when"))m.body(a[2..], e) else .void_value;
        }
        const f = try m.evaluate(a[0], e);
        var args: Values = .empty;
        for (a[1..])|z|try args.append(m.gpa, try m.evaluate(z, e));
        return m.call(f, args.items);
    }
    fn call(m: *Machine, f: Value, a: []const Value)anyerror!Value{
        if (!is(f, .procedure))return m.fail("not a procedure: {s}", .{
            try m.repr(f, true)
        });
        const p = f.procedure;
        if (a.len<p.minimum or (!p.variadic and a.len != p.minimum))return m.fail("{s}: wrong number of arguments (expected {s}{d}, got {d})", .{
            if (p.name.len == 0)"lambda" else p.name, if (p.variadic)"at least " else "", p.minimum, a.len
        });
        if (p.builtin)return m.builtin(p.name, a);
        const e = try m.env(p.env);
        for (p.params, 0..)|name, i|try m.bind(e, name, a[i]);
        if (p.rest.len>0)try m.bind(e, p.rest, try m.list(a[p.minimum..], .nil));
        return m.body(p.body, e);
    }
    fn write(m: *Machine, s: []const u8)anyerror!void{
        try m.output.appendSlice(m.gpa, s);
        if (s.len>0)m.mid = s[s.len-1] != '\n';
    }
    fn line(m: *Machine, s: []const u8)anyerror!void{
        if (m.mid)try m.write("\n");
        try m.write(s);
        try m.write("\n");
    }
    fn expect(m: *Machine, n: []const u8, v: Value, k: []const u8)anyerror!Value{
        const ok = if (eqs(k, "integer"))is(v, .integer) else if (eqs(k, "string"))is(v, .string) else if (eqs(k, "pair"))is(v, .pair) else if (eqs(k, "procedure"))is(v, .procedure) else proper(v);
        if (!ok)return m.fail("{s}: expected {s}, got {s}", .{
            n, k, try m.repr(v, true)
        });
        return v;
    }
    fn asList(m: *Machine, n: []const u8, v: Value)anyerror![]const Value{
        _ = try m.expect(n, v, "list");
        return (try m.items(v)).?;
    }
    fn builtin(m: *Machine, n: []const u8, a: []const Value)anyerror!Value{
        if (contains(&.{
            "+", "*", "-", "quotient", "remainder", "modulo", "abs", "min", "max", "gcd", "=", "<", ">", "<=", ">="
        }, n)){
            for (a)|v|_ = try m.expect(n, v, "integer");
            var v: i64 = if (a.len>0)a[0].integer else 0;
            if (eqs(n, "+") or eqs(n, "*")){
                v = if (eqs(n, "+"))0 else 1;
                for (a)|x|v = if (eqs(n, "+"))v+x.integer else v*x.integer;
                return .{
                    .integer = v
                };
            }
            if (eqs(n, "-")){
                if (a.len == 1)return .{
                    .integer = -v
                };
                for (a[1..])|x|v -= x.integer;
                return .{
                    .integer = v
                };
            }
            if (eqs(n, "abs"))return .{
                .integer = if (v<0)-v else v
            };
            if (eqs(n, "min") or eqs(n, "max")){
                for (a)|x|v = if (eqs(n, "min"))@min(v, x.integer) else @max(v, x.integer);
                return .{
                    .integer = v
                };
            }
            if (eqs(n, "gcd")){
                v = 0;
                for (a)|x|{
                    var b = if (x.integer<0)-x.integer else x.integer;
                    while (b != 0){
                        const r = @rem(v, b);
                        v = b;
                        b = r;
                    }
                }
                return .{
                    .integer = v
                };
            }
            if (eqs(n, "quotient") or eqs(n, "remainder") or eqs(n, "modulo")){
                const b = a[1].integer;
                if (b == 0)return m.fail("{s}: division by zero", .{
                    n
                });
                const r = @rem(v, b);
                return .{
                    .integer = if (eqs(n, "quotient"))@divTrunc(v, b) else if (eqs(n, "modulo") and r != 0 and ((r<0) != (b<0)))r+b else r
                };
            }
            for (a[1..], 0..)|x, i|{
                const l = a[i].integer;
                const r = x.integer;
                const ok = if (eqs(n, "="))l == r else if (eqs(n, "<"))l<r else if (eqs(n, ">"))l>r else if (eqs(n, "<="))l <= r else l >= r;
                if (!ok)return .{
                    .boolean = false
                };
            }
            return .{
                .boolean = true
            };
        }
        if (eqs(n, "not"))return .{
            .boolean = !truth(a[0])
        };
        if (eqs(n, "eq?") or eqs(n, "equal?"))return .{
            .boolean = equal(a[0], a[1], eqs(n, "equal?"))
        };
        if (contains(&.{
            "null?", "pair?", "list?", "number?", "symbol?", "procedure?"
        }, n))return .{
            .boolean = if (eqs(n, "null?"))is(a[0], .nil) else if (eqs(n, "pair?"))is(a[0], .pair) else if (eqs(n, "list?"))proper(a[0]) else if (eqs(n, "number?"))is(a[0], .integer) else if (eqs(n, "symbol?"))is(a[0], .symbol) else is(a[0], .procedure)
        };
        if (eqs(n, "cons"))return m.pair(a[0], a[1]);
        if (eqs(n, "list"))return m.list(a, .nil);
        if (eqs(n, "car") or eqs(n, "cdr") or eqs(n, "cadr")){
            const p = (try m.expect(n, a[0], "pair")).pair;
            return if (eqs(n, "car"))p.car else if (eqs(n, "cdr"))p.cdr else (try m.expect(n, p.cdr, "pair")).pair.car;
        }
        if (eqs(n, "length") or eqs(n, "reverse") or eqs(n, "list-ref")){
            const z = try m.asList(n, a[0]);
            if (eqs(n, "length"))return .{
                .integer = @intCast(z.len)
            };
            if (eqs(n, "reverse")){
                var v: Value = .nil;
                for (z)|x|v = try m.pair(x, v);
                return v;
            }
            const k = (try m.expect(n, a[1], "integer")).integer;
            if (k<0 or k >= @as(i64, @intCast(z.len)))return m.fail("list-ref: index out of range: {d}", .{
                k
            });
            return z[@intCast(k)];
        }
        if (eqs(n, "append")){
            if (a.len == 0)return .nil;
            var z: Values = .empty;
            for (a[0..a.len-1])|v|try z.appendSlice(m.gpa, try m.asList(n, v));
            return m.list(z.items, a[a.len-1]);
        }
        if (contains(&.{
            "map", "filter", "fold-left", "apply"
        }, n)){
            const f = try m.expect(n, a[0], "procedure");
            if (eqs(n, "apply")){
                const spread = try m.asList(n, a[a.len-1]);
                var z: Values = .empty;
                try z.appendSlice(m.gpa, a[1..a.len-1]);
                try z.appendSlice(m.gpa, spread);
                return m.call(f, z.items);
            }
            var ls: std.ArrayList([]const Value) = .empty;
            var count: usize = std.math.maxInt(usize);
            const first: usize = if (eqs(n, "fold-left"))2 else 1;
            for (a[first..])|v|{
                const z = try m.asList(n, v);
                try ls.append(m.gpa, z);
                count = @min(count, z.len);
            }
            var result: Values = .empty;
            var acc = a[1];
            for (0..count)|i|{
                if (eqs(n, "filter")){
                    if (truth(try m.call(f, &.{
                        ls.items[0][i]
                    })))try result.append(m.gpa, ls.items[0][i]);
                }else{
                    var args: Values = .empty;
                    if (eqs(n, "fold-left"))try args.append(m.gpa, acc);
                    for (ls.items)|l|try args.append(m.gpa, l[i]);
                    const v = try m.call(f, args.items);
                    if (eqs(n, "map"))try result.append(m.gpa, v) else acc = v;
                }
            }
            return if (eqs(n, "fold-left"))acc else m.list(result.items, .nil);
        }
        if (eqs(n, "string-append")){
            var s: std.ArrayList(u8) = .empty;
            for (a)|v|try s.appendSlice(m.gpa, (try m.expect(n, v, "string")).string);
            return .{
                .string = try s.toOwnedSlice(m.gpa)
            };
        }
        if (eqs(n, "number->string"))return .{
            .string = try m.repr(try m.expect(n, a[0], "integer"), true)
        };
        if (eqs(n, "display")){
            try m.write(try m.repr(a[0], false));
            return .void_value;
        }
        if (eqs(n, "newline")){
            try m.write("\n");
            return .void_value;
        }
        var s: std.ArrayList(u8) = .empty;
        try s.appendSlice(m.gpa, (try m.expect(n, a[0], "string")).string);
        for (a[1..])|v|{
            try s.append(m.gpa, ' ');
            try s.appendSlice(m.gpa, try m.repr(v, true));
        }
        return m.fail("{s}", .{
            s.items
        });
    }
    fn global(m: *Machine)anyerror!*Environment{
        const e = try m.env(null);
        const names = [_] []const u8{
            "+", "*", "-", "quotient", "remainder", "modulo",
            "abs", "min", "max", "gcd", "=", "<",
            ">", "<=", ">=", "not", "eq?", "equal?",
            "null?", "pair?", "list?", "number?", "symbol?", "procedure?",
            "cons", "car", "cdr", "cadr", "list", "length",
            "append", "reverse", "list-ref", "map", "filter", "fold-left",
            "apply", "string-append", "number->string", "display", "newline", "error"
        };
        const minima = [_]usize{
            0, 0, 1, 2, 2, 2, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 0, 1, 0, 1, 2, 2, 2, 3, 2, 0, 1, 1, 0, 1
        };
        for (names, minima)|n, minimum|{
            const p = try m.gpa.create(Procedure);
            p.*= .{
                .name = n, .minimum = minimum, .variadic = contains(&.{
                    "+", "*", "-", "min", "max", "gcd", "=", "<", ">", "<=", ">=", "list", "append", "map", "fold-left", "apply", "string-append", "error"
                }, n), .builtin = true
            };
            try m.bind(e, n, .{
                .procedure = p
            });
        }
        return e;
    }
};
fn contains(choices: []const []const u8, n: []const u8)bool{
    for (choices)|x|if (eqs(x, n))return true;
    return false;
}
const Token = struct{
    kind: u8, value: Value = .nil
};
const Reader = struct{
    m: *Machine, lines: []const []const u8, row: usize = 0, col: usize = 0,
    fn skip(r: *Reader)void{
        r.row += 1;
        r.col = 0;
    }
    fn end(r: *Reader)bool{
        while (r.row<r.lines.len){
            const s = r.lines[r.row];
            while (r.col<s.len and s[r.col] == ' ')r.col += 1;
            if (r.col<s.len and s[r.col] != ';')return false;
            r.skip();
        }
        return true;
    }
    fn token(r: *Reader)anyerror!Token{
        if (r.end())return r.m.fail("unexpected end of input", .{
        });
        const s = r.lines[r.row];
        var c = s[r.col];
        r.col += 1;
        if (std.mem.indexOfScalar(u8, "()'", c) != null)return .{
            .kind = c
        };
        if (c == '"'){
            var v: std.ArrayList(u8) = .empty;
            while (r.col<s.len){
                c = s[r.col];
                r.col += 1;
                if (c == '"')return .{
                    .kind = 'v', .value = .{
                        .string = try v.toOwnedSlice(r.m.gpa)
                    }
                };
                if (c == '\\'){
                    if (r.col == s.len)break;
                    c = s[r.col];
                    r.col += 1;
                    if (c != '"' and c != '\\' and c != 'n')return r.m.fail("bad escape", .{
                    });
                    if (c == 'n')c = '\n';
                }
                try v.append(r.m.gpa, c);
            }
            return r.m.fail("unterminated string", .{
            });
        }
        const start = r.col-1;
        while (r.col<s.len and std.mem.indexOfScalar(u8, " ()'\";", s[r.col]) == null)r.col += 1;
        const a = s[start..r.col];
        if (eqs(a, "."))return .{
            .kind = '.'
        };
        const first: usize = if (a[0] == '+' or a[0] == '-')1 else 0;
        var integer = first<a.len;
        for (a[first..])|d|integer = integer and std.ascii.isDigit(d);
        if (integer)return .{
            .kind = 'v', .value = .{
                .integer = try std.fmt.parseInt(i64, a, 10)
            }
        };
        if (eqs(a, "#t") or eqs(a, "#f"))return .{
            .kind = 'v', .value = .{
                .boolean = eqs(a, "#t")
            }
        };
        if (a[0] == '#')return r.m.fail("bad token: {s}", .{
            a
        });
        return .{
            .kind = 'v', .value = .{
                .symbol = a
            }
        };
    }
    fn datum(r: *Reader)anyerror!Value{
        return r.from(try r.token());
    }
    fn from(r: *Reader, t: Token)anyerror!Value{
        if (t.kind == 'v')return t.value;
        if (t.kind == '\'')return r.m.list(&.{
            .{
                .symbol = "quote"
            }, try r.datum()
        }, .nil);
        if (t.kind != '(')return r.m.fail("unexpected {c}", .{
            t.kind
        });
        var a: Values = .empty;
        while (true){
            const next = try r.token();
            if (next.kind == ')')return r.m.list(a.items, .nil);
            if (next.kind == '.' and a.items.len>0){
                const tail = try r.datum();
                if ((try r.token()).kind != ')')return r.m.fail("expected )", .{
                });
                return r.m.list(a.items, tail);
            }
            try a.append(r.m.gpa, try r.from(next));
        }
    }
};
pub fn main(init: std.process.Init)!void{
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var split = std.mem.splitScalar(u8, text, '\n');
    var lines: std.ArrayList([]const u8) = .empty;
    while (split.next())|s|{
        if (eqs(s, "(exit)"))break;
        try lines.append(gpa, s);
    }
    var m: Machine = .{
        .gpa = gpa
    };
    const env = try m.global();
    var r: Reader = .{
        .m = &m, .lines = lines.items
    };
    while (!r.end()){
        const x = r.datum() catch |err|{
            if (err != error.Failure)return err;
            try m.line(try std.fmt.allocPrint(gpa, "Error: read: {s}", .{
                m.why
            }));
            if (eqs(m.why, "unexpected end of input"))break;
            r.skip();
            continue;
        };
        const v = m.evaluate(x, env) catch |err|{
            if (err != error.Failure)return err;
            try m.line(try std.fmt.allocPrint(gpa, "Error: {s}", .{
                m.why
            }));
            continue;
        };
        if (!is(v, .void_value))try m.line(try m.repr(v, true));
    }
    if (m.mid)try m.write("\n");
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output.interface.writeAll(m.output.items);
    try output.interface.flush();
}
