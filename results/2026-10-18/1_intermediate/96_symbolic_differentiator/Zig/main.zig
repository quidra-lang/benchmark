const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Expressions = std.ArrayList(*Expr);
const Strings = std.ArrayList(Text);

const Rational = struct {
    p: i128 = 0,
    q: i128 = 1,
};

const Expr = struct {
    k: u8,
    q: Rational = .{},
    s: Text = "",
    a: []const *Expr = &.{},
};

const Tree = union(enum) {
    value: *Expr,
    operation: struct {
        name: Text,
        a: []const *Tree,
    },
};

fn eql(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn among(s: Text, items: []const Text) bool {
    for (items) |item| if (eql(s, item)) return true;
    return false;
}

fn comparison(comptime T: type, a: T, b: T) i32 {
    return if (a < b) -1 else if (a > b) 1 else 0;
}

fn gcd(a0: i128, b0: i128) i128 {
    var a: i128 = @intCast(@abs(a0));
    var b: i128 = @intCast(@abs(b0));
    while (b != 0) {
        const r = @rem(a, b);
        a = b;
        b = r;
    }
    return a;
}

fn rational(p0: i128, q0: i128) Rational {
    var p = p0;
    var q = q0;
    if (q < 0) {
        p = -p;
        q = -q;
    }
    const d = gcd(p, q);
    return .{ .p = @divTrunc(p, d), .q = @divTrunc(q, d) };
}

fn plus(a: Rational, b: Rational) Rational {
    return rational(a.p * b.q + b.p * a.q, a.q * b.q);
}

fn times(a: Rational, b: Rational) Rational {
    return rational(a.p * b.p, a.q * b.q);
}

fn negate(a: Rational) Rational {
    return .{ .p = -a.p, .q = a.q };
}

const Machine = struct {
    gpa: Allocator,
    names: std.StringHashMapUnmanaged(*Expr) = .empty,
    why: Text = "",
    output: std.ArrayList(u8) = .empty,
    zero: *Expr = undefined,
    one: *Expr = undefined,
    minus: *Expr = undefined,
    half: *Expr = undefined,

    fn init(m: *Machine) !void {
        m.zero = try m.num(0, 1);
        m.one = try m.num(1, 1);
        m.minus = try m.num(-1, 1);
        m.half = try m.num(1, 2);
    }

    fn fail(m: *Machine, comptime fmt: Text, args: anytype) anyerror {
        m.why = std.fmt.allocPrint(m.gpa, fmt, args) catch unreachable;
        return error.Failure;
    }

    fn formatted(m: *Machine, comptime fmt: Text, args: anytype) !Text {
        return std.fmt.allocPrint(m.gpa, fmt, args);
    }

    fn concat(m: *Machine, strings: []const Text) !Text {
        return std.mem.concat(m.gpa, u8, strings);
    }

    fn join(m: *Machine, strings: []const Text, separator: Text) !Text {
        return std.mem.join(m.gpa, separator, strings);
    }

    fn line(m: *Machine, s: Text) !void {
        try m.output.appendSlice(m.gpa, s);
        try m.output.append(m.gpa, '\n');
    }

    fn num(m: *Machine, p: i128, q: i128) !*Expr {
        if (q == 0) return m.fail("division by zero", .{});
        const result = try m.gpa.create(Expr);
        result.* = .{ .k = 5, .q = rational(p, q) };
        return result;
    }

    fn node(m: *Machine, k: u8, args: []const *Expr, name: Text) !*Expr {
        const result = try m.gpa.create(Expr);
        result.* = .{ .k = k, .a = try m.gpa.dupe(*Expr, args), .s = name };
        return result;
    }

    fn isInteger(f: *Expr) bool {
        return f.k == 5 and f.q.q == 1;
    }

    fn negative(f: *Expr) bool {
        return f.k == 3 and f.a[1].k == 5 and f.a[1].q.p < 0;
    }

    fn base(f: *Expr) *Expr {
        return if (f.k == 3) f.a[0] else f;
    }

    fn exponent(m: *Machine, f: *Expr) *Expr {
        return if (f.k == 3) f.a[1] else m.one;
    }

    fn compare(a: *Expr, b: *Expr) i32 {
        if (a.k != b.k) return comparison(u8, a.k, b.k);
        if (a.k == 5) return comparison(i128, a.q.p * b.q.q, b.q.p * a.q.q);
        const c = std.mem.order(u8, a.s, b.s);
        if (c != .eq) return if (c == .lt) -1 else 1;
        for (a.a, 0..) |item, i| {
            if (i >= b.a.len) break;
            const k = compare(item, b.a[i]);
            if (k != 0) return k;
        }
        return comparison(usize, a.a.len, b.a.len);
    }

    fn equal(a: *Expr, b: *Expr) bool {
        return compare(a, b) == 0;
    }

    const Coefficient = struct {
        c: Rational,
        factors: []const *Expr,
    };

    fn coefficient(f: *Expr) Coefficient {
        if (f.k == 5) return .{ .c = f.q, .factors = &.{} };
        if (f.k == 2) {
            if (f.a[0].k == 5) return .{ .c = f.a[0].q, .factors = f.a[1..] };
            return .{ .c = .{ .p = 1 }, .factors = f.a };
        }
        return .{ .c = .{ .p = 1 }, .factors = &.{f} };
    }

    fn product(m: *Machine, c: Rational, factors: []const *Expr) !*Expr {
        if (factors.len == 0) return m.num(c.p, c.q);
        if (c.p == c.q) return if (factors.len == 1) factors[0] else m.node(2, factors, "");
        var collected: Expressions = .empty;
        try collected.append(m.gpa, try m.num(c.p, c.q));
        try collected.appendSlice(m.gpa, factors);
        return m.node(2, collected.items, "");
    }

    fn compareExponent(a: *Expr, b: *Expr) i32 {
        if (a.k == 5 and b.k != 5) return -1;
        if (a.k != 5 and b.k == 5) return 1;
        return compare(a, b);
    }

    fn termOrder(m: *Machine, first: *Expr, second: *Expr) i32 {
        const a = coefficient(first).factors;
        const b = coefficient(second).factors;
        var i: usize = 0;
        var j: usize = 0;
        while (i < a.len or j < b.len) {
            const order: i32 = if (i == a.len) 1 else if (j == b.len) -1 else compare(base(a[i]), base(b[j]));
            var x = m.zero;
            var y = m.zero;
            if (order <= 0) {
                x = m.exponent(a[i]);
                i += 1;
            }
            if (order >= 0) {
                y = m.exponent(b[j]);
                j += 1;
            }
            const cmp = compareExponent(x, y);
            if (cmp != 0) return -cmp;
        }
        return 0;
    }

    fn lessTerm(m: *Machine, a: *Expr, b: *Expr) bool {
        return m.termOrder(a, b) < 0;
    }

    fn lessFactor(_: void, a: *Expr, b: *Expr) bool {
        return compare(base(a), base(b)) < 0;
    }

    fn sameSequence(a: []const *Expr, b: []const *Expr) bool {
        if (a.len != b.len) return false;
        for (a, b) |x, y| if (!equal(x, y)) return false;
        return true;
    }

    const SumGroup = struct {
        c: Rational,
        factors: []const *Expr,
    };

    fn add(m: *Machine, values: []const *Expr) anyerror!*Expr {
        var terms: Expressions = .empty;
        for (values) |f| {
            if (f.k == 1) {
                try terms.appendSlice(m.gpa, f.a);
            } else if (f.k == 2 and f.a.len == 2 and f.a[0].k == 5 and f.a[1].k == 1) {
                for (f.a[1].a) |term| try terms.append(m.gpa, try m.mul(&.{ f.a[0], term }));
            } else {
                try terms.append(m.gpa, f);
            }
        }
        var groups: std.ArrayList(SumGroup) = .empty;
        for (terms.items) |f| {
            const info = coefficient(f);
            var found = false;
            for (groups.items) |*g| {
                if (sameSequence(g.factors, info.factors)) {
                    g.c = plus(g.c, info.c);
                    found = true;
                    break;
                }
            }
            if (!found) try groups.append(m.gpa, .{ .c = info.c, .factors = info.factors });
        }
        var result: Expressions = .empty;
        for (groups.items) |g| if (g.c.p != 0) {
            try result.append(m.gpa, try m.product(g.c, g.factors));
        };
        std.mem.sort(*Expr, result.items, m, lessTerm);
        if (result.items.len == 0) return m.zero;
        if (result.items.len == 1) return result.items[0];
        return m.node(1, result.items, "");
    }

    const ProductGroup = struct {
        b: *Expr,
        values: Expressions,
    };

    fn mul(m: *Machine, input: []const *Expr) anyerror!*Expr {
        var pending = try m.gpa.dupe(*Expr, input);
        while (true) {
            var factors: Expressions = .empty;
            for (pending) |f| {
                if (f.k == 2) try factors.appendSlice(m.gpa, f.a)
                else try factors.append(m.gpa, f);
            }
            var c = Rational{ .p = 1 };
            var groups: std.ArrayList(ProductGroup) = .empty;
            for (factors.items) |f| {
                if (f.k == 5) {
                    c = times(c, f.q);
                } else {
                    const b = base(f);
                    var found = false;
                    for (groups.items) |*g| if (equal(g.b, b)) {
                        try g.values.append(m.gpa, f);
                        found = true;
                        break;
                    };
                    if (!found) {
                        var parts: Expressions = .empty;
                        try parts.append(m.gpa, f);
                        try groups.append(m.gpa, .{ .b = b, .values = parts });
                    }
                }
            }
            if (c.p == 0) return m.zero;
            var reduced: Expressions = .empty;
            for (groups.items) |group| {
                if (group.values.items.len == 1) {
                    try reduced.append(m.gpa, group.values.items[0]);
                } else {
                    var exponents: Expressions = .empty;
                    for (group.values.items) |f| try exponents.append(m.gpa, m.exponent(f));
                    try reduced.append(m.gpa, try m.power(group.b, try m.add(exponents.items)));
                }
            }
            var retry = false;
            for (reduced.items, 0..) |f, i| {
                if (f.k == 2 or f.k == 5) retry = true;
                for (reduced.items[0..i]) |other| {
                    if (equal(base(f), base(other))) retry = true;
                }
            }
            if (retry) {
                var again: Expressions = .empty;
                try again.append(m.gpa, try m.num(c.p, c.q));
                try again.appendSlice(m.gpa, reduced.items);
                pending = try again.toOwnedSlice(m.gpa);
                continue;
            }
            std.mem.sort(*Expr, reduced.items, {}, lessFactor);
            return m.product(c, reduced.items);
        }
    }

    fn exactRoot(value: i128, degree: i128) ?i128 {
        if (value == 1) return 1;
        if (degree > 20 or degree <= 0 or value < 0) return null;
        var candidate: i128 = 0;
        while (candidate <= 1000) : (candidate += 1) {
            var product_value: i128 = 1;
            var k: i128 = 0;
            while (k < degree) : (k += 1) {
                if (candidate != 0 and product_value > @divTrunc(value, candidate)) {
                    product_value = value + 1;
                    break;
                }
                product_value *= candidate;
                if (product_value > value) break;
            }
            if (product_value == value) return candidate;
            if (product_value > value) break;
        }
        return null;
    }

    fn rationalPower(m: *Machine, fraction: Rational, exp: i128) anyerror!*Expr {
        var b = if (exp < 0) rational(fraction.q, fraction.p) else fraction;
        var n: u128 = @intCast(@abs(exp));
        var value = Rational{ .p = 1 };
        while (n != 0) {
            if (n & 1 != 0) value = times(value, b);
            n >>= 1;
            if (n != 0) b = times(b, b);
        }
        return m.num(value.p, value.q);
    }

    fn power(m: *Machine, b: *Expr, x: *Expr) anyerror!*Expr {
        if (equal(x, m.zero)) return m.one;
        if (equal(x, m.one)) return b;
        if (b.k == 5) {
            if (equal(b, m.one)) return m.one;
            if (x.k == 5) {
                if (b.q.p == 0) {
                    if (x.q.p > 0) return m.zero;
                    return m.fail("division by zero", .{});
                }
                if (isInteger(x)) return m.rationalPower(b.q, x.q.p);
                if (b.q.p > 0) {
                    if (exactRoot(b.q.p, x.q.q)) |p| {
                        if (exactRoot(b.q.q, x.q.q)) |q| {
                            return m.rationalPower(rational(p, q), x.q.p);
                        }
                    }
                }
            }
        } else if (isInteger(x)) {
            if (b.k == 3) return m.power(b.a[0], try m.mul(&.{ b.a[1], x }));
            if (b.k == 2) {
                var factors: Expressions = .empty;
                for (b.a) |f| try factors.append(m.gpa, try m.power(f, x));
                return m.mul(factors.items);
            }
        }
        return m.node(3, &.{ b, x }, "");
    }

    fn function(m: *Machine, name: Text, a: *Expr) anyerror!*Expr {
        if (eql(name, "sqrt")) return m.power(a, m.half);
        if (equal(a, m.zero)) {
            if (among(name, &.{ "sin", "tan" })) return m.zero;
            if (among(name, &.{ "cos", "exp" })) return m.one;
        }
        if (eql(name, "ln") and equal(a, m.one)) return m.zero;
        if (among(name, &.{ "sin", "cos", "tan" }) and coefficient(a).c.p < 0) {
            const positive = try m.mul(&.{ m.minus, a });
            const transformed = try m.function(name, positive);
            return if (eql(name, "cos")) transformed else m.mul(&.{ m.minus, transformed });
        }
        if (a.k == 4 and ((eql(name, "ln") and eql(a.s, "exp")) or
            (eql(name, "exp") and eql(a.s, "ln")))) return a.a[0];
        return m.node(4, &.{a}, name);
    }

    fn collectVariables(m: *Machine, f: *Expr, vars: *Strings) !void {
        if (f.k == 0) {
            for (vars.items) |name| if (eql(f.s, name)) return;
            try vars.append(m.gpa, f.s);
        }
        for (f.a) |child| try m.collectVariables(child, vars);
    }

    fn lessText(_: void, a: Text, b: Text) bool {
        return std.mem.order(u8, a, b) == .lt;
    }

    fn variables(m: *Machine, f: *Expr) ![]Text {
        var found: Strings = .empty;
        try m.collectVariables(f, &found);
        std.mem.sort(Text, found.items, {}, lessText);
        return found.toOwnedSlice(m.gpa);
    }

    fn containsVariable(m: *Machine, f: *Expr, name: Text) !bool {
        const values = try m.variables(f);
        return among(name, values);
    }

    fn derivative(m: *Machine, f: *Expr, variable: Text) anyerror!*Expr {
        if (f.k == 5) return m.zero;
        if (f.k == 0) return if (eql(f.s, variable)) m.one else m.zero;
        if (f.k == 1) {
            var a: Expressions = .empty;
            for (f.a) |term| try a.append(m.gpa, try m.derivative(term, variable));
            return m.add(a.items);
        }
        if (f.k == 2) {
            var terms: Expressions = .empty;
            for (f.a, 0..) |_, i| {
                var factors: Expressions = .empty;
                for (f.a, 0..) |g, j|
                    try factors.append(m.gpa, if (i == j) try m.derivative(g, variable) else g);
                try terms.append(m.gpa, try m.mul(factors.items));
            }
            return m.add(terms.items);
        }
        if (f.k == 3) {
            const b = f.a[0];
            const x = f.a[1];
            if (!try m.containsVariable(x, variable)) return m.mul(&.{
                x, try m.power(b, try m.add(&.{ x, m.minus })), try m.derivative(b, variable),
            });
            if (!try m.containsVariable(b, variable)) return m.mul(&.{
                f, try m.function("ln", b), try m.derivative(x, variable),
            });
            return m.mul(&.{ f, try m.add(&.{
                try m.mul(&.{ try m.derivative(x, variable), try m.function("ln", b) }),
                try m.mul(&.{ x, try m.derivative(b, variable), try m.power(b, m.minus) }),
            }) });
        }
        const a = f.a[0];
        const factor = if (eql(f.s, "sin"))
            try m.function("cos", a)
        else if (eql(f.s, "cos"))
            try m.mul(&.{ m.minus, try m.function("sin", a) })
        else if (eql(f.s, "tan"))
            try m.power(try m.function("cos", a), try m.num(-2, 1))
        else if (eql(f.s, "exp"))
            f
        else
            try m.power(a, m.minus);
        return m.mul(&.{ factor, try m.derivative(a, variable) });
    }

    fn substitute(m: *Machine, f: *Expr, names: []const Text, replacements: []const *Expr) anyerror!*Expr {
        if (f.k == 5) return f;
        if (f.k == 0) {
            for (names, 0..) |name, i| if (eql(f.s, name)) return replacements[i];
            return f;
        }
        var args: Expressions = .empty;
        for (f.a) |child| try args.append(m.gpa, try m.substitute(child, names, replacements));
        if (f.k == 1) return m.add(args.items);
        if (f.k == 2) return m.mul(args.items);
        if (f.k == 3) return m.power(args.items[0], args.items[1]);
        return m.function(f.s, args.items[0]);
    }

    fn distribute(m: *Machine, a: *Expr, b: *Expr) anyerror!*Expr {
        const x: []const *Expr = if (a.k == 1) a.a else &.{a};
        const y: []const *Expr = if (b.k == 1) b.a else &.{b};
        var terms: Expressions = .empty;
        for (x) |first| for (y) |second|
            try terms.append(m.gpa, try m.mul(&.{ first, second }));
        return m.add(terms.items);
    }

    fn expand(m: *Machine, f: *Expr) anyerror!*Expr {
        if (f.k == 0 or f.k == 5) return f;
        var args: Expressions = .empty;
        for (f.a) |child| try args.append(m.gpa, try m.expand(child));
        if (f.k == 1) return m.add(args.items);
        if (f.k == 4) return m.function(f.s, args.items[0]);
        if (f.k == 2) {
            var result = args.items[0];
            for (args.items[1..]) |b| result = try m.distribute(result, b);
            return result;
        }
        const b = args.items[0];
        const x = args.items[1];
        if (b.k == 1 and isInteger(x) and x.q.p > 0) {
            var result = b;
            var k: i128 = 1;
            while (k < x.q.p) : (k += 1) result = try m.distribute(result, b);
            return result;
        }
        return m.power(b, x);
    }

    fn numericalValue(m: *Machine, f: *Expr) anyerror!f64 {
        if (f.k == 5) return @as(f64, @floatFromInt(f.q.p)) / @as(f64, @floatFromInt(f.q.q));
        if (f.k == 1 or f.k == 2) {
            var result: f64 = if (f.k == 1) 0.0 else 1.0;
            for (f.a) |child| {
                const value = try m.numericalValue(child);
                if (f.k == 1) result += value else result *= value;
            }
            return result;
        }
        if (f.k == 3) {
            const u = try m.numericalValue(f.a[0]);
            const z = try m.numericalValue(f.a[1]);
            if (u < 0 and !(if (f.a[1].k == 5) isInteger(f.a[1]) else @floor(z) == z))
                return m.fail("domain error", .{});
            return if (equal(f.a[1], m.half)) @sqrt(u) else std.math.pow(f64, u, z);
        }
        const a = try m.numericalValue(f.a[0]);
        if (eql(f.s, "sin")) return @sin(a);
        if (eql(f.s, "cos")) return @cos(a);
        if (eql(f.s, "tan")) return std.math.tan(a);
        if (eql(f.s, "exp")) return @exp(a);
        if (a <= 0) return m.fail("domain error", .{});
        return @log(a);
    }

    fn atomic(m: *Machine, f: *Expr) bool {
        return f.k == 0 or f.k == 4 or (isInteger(f) and f.q.p >= 0) or
            (f.k == 3 and equal(f.a[1], m.half));
    }

    fn showAtom(m: *Machine, f: *Expr) anyerror!Text {
        const inner = try m.show(f);
        return if (m.atomic(f)) inner else m.formatted("({s})", .{inner});
    }

    fn showPower(m: *Machine, b: *Expr, x: *Expr) anyerror!Text {
        if (equal(x, m.half)) return m.formatted("sqrt({s})", .{try m.show(b)});
        return m.formatted("{s}^{s}", .{ try m.showAtom(b), try m.showAtom(x) });
    }

    fn showFactor(m: *Machine, f: *Expr) anyerror!Text {
        if (f.k == 1) return m.formatted("({s})", .{try m.show(f)});
        if (f.k == 3) return m.showPower(f.a[0], f.a[1]);
        return m.show(f);
    }

    fn quotient(m: *Machine, c: Rational, factors: []const *Expr) anyerror!Text {
        var top: Strings = .empty;
        var bottom: Strings = .empty;
        const p: i128 = @intCast(@abs(c.p));
        if (p != 1) try top.append(m.gpa, try m.formatted("{d}", .{p}));
        if (c.q != 1) try bottom.append(m.gpa, try m.formatted("{d}", .{c.q}));
        for (factors) |f| {
            if (negative(f)) {
                const exponent = try m.num(-f.a[1].q.p, f.a[1].q.q);
                try bottom.append(m.gpa, if (equal(exponent, m.one))
                    try m.showFactor(f.a[0]) else try m.showPower(f.a[0], exponent));
            } else {
                try top.append(m.gpa, try m.showFactor(f));
            }
        }
        const numerator = if (top.items.len == 0) "1" else try m.join(top.items, "*");
        const result = if (bottom.items.len == 0)
            numerator
        else if (bottom.items.len == 1)
            try m.formatted("{s}/{s}", .{ numerator, bottom.items[0] })
        else
            try m.formatted("{s}/({s})", .{ numerator, try m.join(bottom.items, "*") });
        return if (c.p < 0) m.formatted("-{s}", .{result}) else result;
    }

    fn show(m: *Machine, f: *Expr) anyerror!Text {
        if (f.k == 5) return if (f.q.q == 1)
            m.formatted("{d}", .{f.q.p})
        else m.formatted("{d}/{d}", .{ f.q.p, f.q.q });
        if (f.k == 0) return f.s;
        if (f.k == 4) return m.formatted("{s}({s})", .{ f.s, try m.show(f.a[0]) });
        if (f.k == 3) return if (negative(f))
            m.quotient(.{ .p = 1 }, &.{f})
        else m.showPower(f.a[0], f.a[1]);
        if (f.k == 2) {
            const info = coefficient(f);
            return m.quotient(info.c, info.factors);
        }
        var text: Text = try m.show(f.a[0]);
        for (f.a[1..]) |term| {
            const next = try m.show(term);
            text = if (std.mem.startsWith(u8, next, "-"))
                try m.formatted("{s} - {s}", .{ text, next[1..] })
            else
                try m.formatted("{s} + {s}", .{ text, next });
        }
        return text;
    }

    fn tokenize(m: *Machine, text: Text) anyerror![]Text {
        var tokens: Strings = .empty;
        var i: usize = 0;
        while (i < text.len) {
            const c = text[i];
            if (c == ' ') {
                i += 1;
                continue;
            }
            const start = i;
            if (std.ascii.isDigit(c)) {
                while (i < text.len and std.ascii.isDigit(text[i])) i += 1;
            } else if (std.ascii.isLower(c)) {
                while (i < text.len and (std.ascii.isLower(text[i]) or std.ascii.isDigit(text[i]))) i += 1;
            } else if (std.ascii.isUpper(c)) {
                while (i < text.len and (std.ascii.isUpper(text[i]) or std.ascii.isDigit(text[i]))) i += 1;
            } else if (std.mem.indexOfScalar(u8, "-+*/^()", c) != null) {
                i += 1;
            } else {
                return m.fail("invalid character '{c}'", .{c});
            }
            try tokens.append(m.gpa, text[start..i]);
        }
        return tokens.toOwnedSlice(m.gpa);
    }

    fn tree(m: *Machine, name: Text, args: []const *Tree) !*Tree {
        const ptr = try m.gpa.create(Tree);
        ptr.* = .{ .operation = .{ .name = name, .a = try m.gpa.dupe(*Tree, args) } };
        return ptr;
    }

    fn leaf(m: *Machine, value: *Expr) !*Tree {
        const ptr = try m.gpa.create(Tree);
        ptr.* = .{ .value = value };
        return ptr;
    }

    fn evaluateTree(m: *Machine, value: *Tree) anyerror!*Expr {
        switch (value.*) {
            .value => |f| return f,
            .operation => |op| {
                var a: Expressions = .empty;
                for (op.a) |child| try a.append(m.gpa, try m.evaluateTree(child));
                const x = a.items;
                if (eql(op.name, "+")) return m.add(x);
                if (eql(op.name, "-")) return m.add(&.{ x[0], try m.mul(&.{ m.minus, x[1] }) });
                if (eql(op.name, "*")) return m.mul(x);
                if (eql(op.name, "/")) return m.mul(&.{ x[0], try m.power(x[1], m.minus) });
                if (eql(op.name, "^")) return m.power(x[0], x[1]);
                if (eql(op.name, "neg")) return m.mul(&.{ m.minus, x[0] });
                return m.function(op.name, x[0]);
            },
        }
    }

    const Parser = struct {
        m: *Machine,
        tokens: []Text,
        position: usize = 0,

        fn peek(p: *Parser) Text {
            return if (p.position < p.tokens.len) p.tokens[p.position] else "";
        }

        fn unexpected(p: *Parser) anyerror {
            return if (p.position == p.tokens.len)
                p.m.fail("unexpected end of expression", .{})
            else
                p.m.fail("unexpected '{s}'", .{p.peek()});
        }

        fn accept(p: *Parser, s: Text) bool {
            if (!eql(p.peek(), s)) return false;
            p.position += 1;
            return true;
        }

        fn expect(p: *Parser, s: Text) anyerror!void {
            if (!p.accept(s)) return p.unexpected();
        }

        fn atom(p: *Parser) anyerror!*Tree {
            if (p.accept("(")) {
                const f = try p.expression();
                try p.expect(")");
                return f;
            }
            const word = p.peek();
            if (word.len == 0) return p.unexpected();
            if (std.ascii.isDigit(word[0])) {
                p.position += 1;
                return p.m.leaf(try p.m.num(try std.fmt.parseInt(i128, word, 10), 1));
            }
            if (std.ascii.isUpper(word[0])) {
                p.position += 1;
                const definition = p.m.names.get(word) orelse
                    return p.m.fail("undefined name '{s}'", .{word});
                return p.m.leaf(definition);
            }
            if (std.ascii.isLower(word[0])) {
                p.position += 1;
                if (!among(word, &.{ "sin", "cos", "tan", "exp", "ln", "sqrt" })) {
                    return p.m.leaf(try p.m.node(0, &.{}, word));
                }
                try p.expect("(");
                const a = try p.expression();
                try p.expect(")");
                return p.m.tree(word, &.{a});
            }
            return p.unexpected();
        }

        fn unary(p: *Parser) anyerror!*Tree {
            if (p.accept("-")) return p.m.tree("neg", &.{try p.unary()});
            const a = try p.atom();
            return if (p.accept("^")) p.m.tree("^", &.{ a, try p.unary() }) else a;
        }

        fn term(p: *Parser) anyerror!*Tree {
            var a = try p.unary();
            while (eql(p.peek(), "*") or eql(p.peek(), "/")) {
                const op = p.peek();
                p.position += 1;
                a = try p.m.tree(op, &.{ a, try p.unary() });
            }
            return a;
        }

        fn expression(p: *Parser) anyerror!*Tree {
            var a = try p.term();
            while (eql(p.peek(), "+") or eql(p.peek(), "-")) {
                const op = p.peek();
                p.position += 1;
                a = try p.m.tree(op, &.{ a, try p.term() });
            }
            return a;
        }
    };

    fn parse(m: *Machine, expression: Text) anyerror!*Expr {
        var reader = Parser{ .m = m, .tokens = try m.tokenize(expression) };
        const result = try reader.expression();
        if (reader.position != reader.tokens.len) return reader.unexpected();
        return m.evaluateTree(result);
    }

    fn validVariable(name: Text) bool {
        if (name.len == 0 or !std.ascii.isLower(name[0]) or
            among(name, &.{ "sin", "cos", "tan", "exp", "ln", "sqrt" })) return false;
        for (name[1..]) |c| if (!std.ascii.isLower(c) and !std.ascii.isDigit(c)) return false;
        return true;
    }

    fn validName(name: Text) bool {
        if (name.len == 0 or !std.ascii.isUpper(name[0])) return false;
        for (name[1..]) |c| if (!std.ascii.isUpper(c) and !std.ascii.isDigit(c)) return false;
        return true;
    }

    fn literal(m: *Machine, text: Text) anyerror!*Expr {
        if (text.len == 0) return m.fail("invalid number '{s}'", .{text});
        const start: usize = if (text[0] == '-') 1 else 0;
        if (start == text.len) return m.fail("invalid number '{s}'", .{text});
        var slash: ?usize = null;
        for (text[start..], start..) |c, i| {
            if (c == '/') {
                if (slash != null) return m.fail("invalid number '{s}'", .{text});
                slash = i;
            } else if (!std.ascii.isDigit(c)) return m.fail("invalid number '{s}'", .{text});
        }
        const numerator = text[0 .. slash orelse text.len];
        const denominator = if (slash) |i| text[i + 1 ..] else "1";
        if (numerator.len == start or denominator.len == 0) return m.fail("invalid number '{s}'", .{text});
        if (denominator[0] == '/' or numerator[numerator.len - 1] == '/') return m.fail("invalid number '{s}'", .{text});
        return m.num(try std.fmt.parseInt(i128, numerator, 10), try std.fmt.parseInt(i128, denominator, 10));
    }

    fn checkedVariable(m: *Machine, name: Text) anyerror!Text {
        if (!validVariable(name)) return m.fail("invalid variable '{s}'", .{name});
        return name;
    }

    fn order(m: *Machine, text: Text) anyerror!usize {
        if (text.len != 1 or text[0] < '1' or text[0] > '8') return m.fail("invalid order '{s}'", .{text});
        return text[0] - '0';
    }

    fn command(m: *Machine, line_text: Text) anyerror!void {
        const split = std.mem.indexOfScalar(u8, line_text, ' ');
        const command_name = if (split) |p| line_text[0..p] else line_text;
        const arg = if (split) |p| line_text[p + 1 ..] else "";
        if (eql(command_name, "LET")) {
            const idx = std.mem.indexOfScalar(u8, arg, '=') orelse
                return m.fail("wrong number of arguments", .{});
            const name = std.mem.trim(u8, arg[0..idx], " ");
            if (!validName(name)) return m.fail("invalid name '{s}'", .{name});
            const expr = try m.parse(std.mem.trim(u8, arg[idx + 1 ..], " "));
            try m.names.put(m.gpa, name, expr);
            try m.line(try m.formatted("{s} = {s}", .{ name, try m.show(expr) }));
            return;
        }

        const kind: Text = if (among(command_name, &.{ "SIMPLIFY", "EXPAND", "GRAD", "HESSIAN" }))
            "e"
        else if (eql(command_name, "DIFF")) "ev"
        else if (eql(command_name, "DIFFN")) "evn"
        else if (eql(command_name, "IMPLICIT")) "evv"
        else if (eql(command_name, "SUBST")) "eve"
        else if (eql(command_name, "EVAL")) "ea"
        else if (among(command_name, &.{ "TANGENT", "LIMIT" })) "evc"
        else if (eql(command_name, "TAYLOR")) "evcn"
        else return m.fail("unknown command {s}", .{command_name});

        var fields: Strings = .empty;
        if (split != null) {
            var iterator = std.mem.splitScalar(u8, arg, ';');
            while (iterator.next()) |part| try fields.append(m.gpa, std.mem.trim(u8, part, " "));
        }
        if (eql(command_name, "EVAL")) {
            if (fields.items.len != 1 and fields.items.len != 2) return m.fail("wrong number of arguments", .{});
        } else if (fields.items.len != kind.len) return m.fail("wrong number of arguments", .{});

        var exprs: Expressions = .empty;
        var strings: Strings = .empty;
        var orders: std.ArrayList(usize) = .empty;
        for (fields.items, 0..) |field, i| {
            const field_type = kind[i];
            if (field_type == 'e') {
                try exprs.append(m.gpa, try m.parse(field));
            } else if (field_type == 'v') {
                try strings.append(m.gpa, try m.checkedVariable(field));
            } else if (field_type == 'n') {
                try orders.append(m.gpa, try m.order(field));
            } else if (field_type == 'c') {
                try exprs.append(m.gpa, try m.literal(field));
            }
        }
        var f = exprs.items[0];
        const variable = if (strings.items.len > 0) strings.items[0] else "";
        if (eql(command_name, "SIMPLIFY")) {
            try m.line(try m.formatted("simplified: {s}", .{try m.show(f)}));
        } else if (eql(command_name, "EXPAND")) {
            try m.line(try m.formatted("expanded: {s}", .{try m.show(try m.expand(f))}));
        } else if (eql(command_name, "DIFF")) {
            try m.line(try m.formatted("d/d{s} = {s}", .{ variable, try m.show(try m.derivative(f, variable)) }));
        } else if (eql(command_name, "DIFFN")) {
            const n = orders.items[0];
            for (1..n + 1) |k| {
                f = try m.derivative(f, variable);
                try m.line(try m.formatted("d^{d}/d{s}^{d} = {s}", .{ k, variable, k, try m.show(f) }));
            }
        } else if (eql(command_name, "GRAD") or eql(command_name, "HESSIAN")) {
            const vars = try m.variables(f);
            if (vars.len == 0) {
                try m.line("no variables");
                return;
            }
            for (vars, 0..) |v, i| {
                const first = try m.derivative(f, v);
                if (eql(command_name, "GRAD")) {
                    try m.line(try m.formatted("d/d{s} = {s}", .{v, try m.show(first)}));
                } else {
                    for (vars[i..]) |w| {
                        try m.line(try m.formatted("d2/d{s}d{s} = {s}", .{
                            v, w, try m.show(try m.derivative(first, w)),
                        }));
                    }
                }
            }
        } else if (eql(command_name, "IMPLICIT")) {
            const other = strings.items[1];
            if (eql(variable, other)) return m.fail("same variable", .{});
            const value = try m.mul(&.{
                m.minus, try m.derivative(f, variable),
                try m.power(try m.derivative(f, other), m.minus),
            });
            try m.line(try m.formatted("d{s}/d{s} = {s}", .{ other, variable, try m.show(value) }));
        } else if (eql(command_name, "SUBST")) {
            const result = try m.substitute(f, &.{variable}, &.{exprs.items[1]});
            try m.line(try m.formatted("substituted: {s}", .{try m.show(result)}));
        } else if (eql(command_name, "EVAL")) {
            var assignments: Strings = .empty;
            var values: Expressions = .empty;
            if (fields.items.len == 2) {
                var words = std.mem.tokenizeScalar(u8, fields.items[1], ' ');
                while (words.next()) |word| {
                    const equal_pos = std.mem.indexOfScalar(u8, word, '=') orelse
                        return m.fail("invalid assignment '{s}'", .{word});
                    const name = word[0..equal_pos];
                    const lit = word[equal_pos + 1 ..];
                    if (!validVariable(name) or lit.len == 0) return m.fail("invalid assignment '{s}'", .{word});
                    if (!validLiteral(lit)) return m.fail("invalid assignment '{s}'", .{word});
                    const value = try m.literal(lit);
                    if (among(name, assignments.items)) return m.fail("duplicate variable {s}", .{name});
                    try assignments.append(m.gpa, name);
                    try values.append(m.gpa, value);
                }
            }
            for (try m.variables(f)) |name| {
                if (!among(name, assignments.items)) return m.fail("no value for {s}", .{name});
            }
            const result = try m.substitute(f, assignments.items, values.items);
            if (result.k == 5) {
                try m.line(try m.formatted("exact: {s}", .{try m.show(result)}));
            } else {
                const value = try m.numericalValue(result);
                const rounded = @floor(@abs(value) * 1000000.0 + 0.5);
                const scaled: i128 = @intFromFloat(rounded);
                const whole = @divTrunc(scaled, 1000000);
                const decimals = @mod(scaled, 1000000);
                try m.line(try m.formatted("approx: {s}{d}.{d:0>6}", .{
                    if (value < 0) @as(Text, "-") else "", whole, decimals,
                }));
            }
        } else {
            const point = exprs.items[1];
            if (eql(command_name, "TANGENT")) {
                const slope = try m.substitute(try m.derivative(f, variable), &.{variable}, &.{point});
                const y = try m.substitute(f, &.{variable}, &.{point});
                const v = try m.node(0, &.{}, variable);
                const neg = try m.num(-point.q.p, point.q.q);
                const tangent = try m.add(&.{
                    try m.mul(&.{ slope, v }), y, try m.mul(&.{ neg, slope }),
                });
                try m.line(try m.formatted("tangent: y = {s}", .{try m.show(tangent)}));
                if (equal(slope, m.zero)) {
                    try m.line(try m.formatted("normal: {s} = {s}", .{ variable, try m.show(point) }));
                } else {
                    const reciprocal = try m.power(slope, m.minus);
                    const normal = try m.add(&.{
                        try m.mul(&.{ m.minus, reciprocal, v }), y,
                        try m.mul(&.{ point, reciprocal }),
                    });
                    try m.line(try m.formatted("normal: y = {s}", .{try m.show(normal)}));
                }
            } else if (eql(command_name, "LIMIT")) {
                var tops: Expressions = .empty;
                var bottoms: Expressions = .empty;
                const parts = if (f.k == 2) f.a else &.{f};
                for (parts) |part| {
                    if (negative(part)) try bottoms.append(m.gpa, try m.power(
                        part.a[0], try m.num(-part.a[1].q.p, part.a[1].q.q),
                    )) else try tops.append(m.gpa, part);
                }
                var numerator = try m.mul(tops.items);
                var denominator = try m.mul(bottoms.items);
                for (0..6) |k| {
                    const a = try m.substitute(numerator, &.{variable}, &.{point});
                    const b = try m.substitute(denominator, &.{variable}, &.{point});
                    if (!equal(b, m.zero)) {
                        const result = try m.mul(&.{ a, try m.power(b, m.minus) });
                        try m.line(try m.formatted("limit: {s}", .{try m.show(result)}));
                        return;
                    }
                    if (!equal(a, m.zero)) {
                        try m.line("limit: unbounded");
                        return;
                    }
                    if (k == 5) {
                        try m.line("limit: unknown");
                        return;
                    }
                    numerator = try m.derivative(numerator, variable);
                    denominator = try m.derivative(denominator, variable);
                }
            } else if (eql(command_name, "TAYLOR")) {
                const n = orders.items[0];
                var derivatives: Expressions = .empty;
                try derivatives.append(m.gpa, f);
                for (0..n) |_| {
                    try derivatives.append(m.gpa, try m.derivative(derivatives.items[derivatives.items.len - 1], variable));
                }
                const negative_point = try m.num(-point.q.p, point.q.q);
                const offset = try m.add(&.{ try m.node(0, &.{}, variable), negative_point });
                var factorial: i128 = 1;
                var terms: Expressions = .empty;
                for (0..n + 1) |k| {
                    if (k > 0) factorial *= @intCast(k);
                    const value = try m.substitute(derivatives.items[k], &.{variable}, &.{point});
                    const coefficient_value = try m.mul(&.{ value, try m.num(1, factorial) });
                    try terms.append(m.gpa, try m.mul(&.{
                        coefficient_value, try m.power(offset, try m.num(@intCast(k), 1)),
                    }));
                }
                try m.line(try m.formatted("taylor: {s}", .{try m.show(try m.expand(try m.add(terms.items)))}));
            }
        }
    }

    fn validLiteral(text: Text) bool {
        if (text.len == 0) return false;
        const first: usize = if (text[0] == '-') 1 else 0;
        if (first == text.len) return false;
        var slash: ?usize = null;
        for (text[first..], first..) |c, i| {
            if (c == '/') {
                if (slash != null) return false;
                slash = i;
            } else if (!std.ascii.isDigit(c)) return false;
        }
        return if (slash) |i| i > first and i + 1 < text.len else true;
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count = try std.fmt.parseInt(usize, lines.next() orelse "0", 10);
    var machine = Machine{ .gpa = gpa };
    try machine.init();
    for (0..count) |_| {
        const line = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
        machine.command(line) catch |failure| {
            if (failure != error.Failure) return failure;
            try machine.line(try machine.formatted("error: {s}", .{machine.why}));
        };
    }
    var output_buffer: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try sink.interface.writeAll(machine.output.items);
    try sink.interface.flush();
}
