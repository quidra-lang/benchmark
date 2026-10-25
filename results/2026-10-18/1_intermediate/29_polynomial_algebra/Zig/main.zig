const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const SemanticError = error{
    BadCommand, SameName, ZeroDenominator, DivisionByZero, NonconstantDivisor,
    DegreeLimit, ZeroPolynomial, BadInterval, DegreeTooLow, NotCoprime,
};
const Error = SemanticError || Allocator.Error || Writer.Error;
const Command = enum {
    DEF, PRINT, DELETE, LIST, DEGREE, ADD, SUB, MUL, POW, DIV, GCD, XGCD, LCM,
    INVMOD, CRT, MODPOW, DERIV, INTEG, AREA, TANGENT, TAYLOR, COMPOSE, EVAL,
    ROOTS, FACTOR, SQFREE, DESCARTES, STURM, ISOLATE, RESULTANT, DISCRIM,
    POWERSUM, INTERP, SPECIAL,
};

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn natural(text: []const u8) usize { return @intCast(integer(text)); }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
fn absolute(value: i64) i64 { return if (value < 0) -value else value; }
fn gcd(a: i64, b: i64) i64 {
    var x = absolute(a);
    var y = absolute(b);
    while (y != 0) {
        const remainder = @mod(x, y);
        x = y;
        y = remainder;
    }
    return x;
}

const Fraction = struct {
    n: i64 = 0,
    d: i64 = 1,
    const zero: Fraction = .{};
    const one: Fraction = .{ .n = 1 };

    fn init(n: i64, d: i64) Fraction {
        const divisor = gcd(n, d) * @as(i64, if (d < 0) -1 else 1);
        return .{ .n = @divTrunc(n, divisor), .d = @divTrunc(d, divisor) };
    }
    fn whole(n: i64) Fraction { return .{ .n = n }; }
    fn parse(text: []const u8) SemanticError!Fraction {
        const slash = std.mem.findScalar(u8, text, '/');
        const n = integer(if (slash) |i| text[0..i] else text);
        const d = if (slash) |i| integer(text[i + 1 ..]) else 1;
        if (d == 0) return error.ZeroDenominator;
        return init(n, d);
    }
    fn add(a: Fraction, b: Fraction) Fraction { return init(a.n * b.d + b.n * a.d, a.d * b.d); }
    fn sub(a: Fraction, b: Fraction) Fraction { return init(a.n * b.d - b.n * a.d, a.d * b.d); }
    fn mul(a: Fraction, b: Fraction) Fraction { return init(a.n * b.n, a.d * b.d); }
    fn div(a: Fraction, b: Fraction) Fraction { return init(a.n * b.d, a.d * b.n); }
    fn neg(a: Fraction) Fraction { return .{ .n = -a.n, .d = a.d }; }
    fn abs(a: Fraction) Fraction { return .{ .n = absolute(a.n), .d = a.d }; }
    fn isZero(a: Fraction) bool { return a.n == 0; }
    fn sign(a: Fraction) i32 { return if (a.n < 0) -1 else if (a.n > 0) 1 else 0; }
    fn eq(a: Fraction, b: Fraction) bool { return a.n == b.n and a.d == b.d; }
    fn less(a: Fraction, b: Fraction) bool { return a.n * b.d < b.n * a.d; }
    fn lessThan(_: void, a: Fraction, b: Fraction) bool { return a.less(b); }
    fn power(a: Fraction, exponent: usize) Fraction {
        var result = one;
        for (0..exponent) |_| result = result.mul(a);
        return result;
    }
    pub fn format(value: Fraction, out: *Writer) Writer.Error!void {
        try out.print("{d}", .{value.n});
        if (value.d != 1) try out.print("/{d}", .{value.d});
    }
};

const Polynomial = struct {
    coefficients: []const Fraction = &.{},
    const zero: Polynomial = .{};
    const one: Polynomial = .{ .coefficients = &.{Fraction.one} };
    const variable: Polynomial = .{ .coefficients = &.{ Fraction.zero, Fraction.one } };
    const Division = struct { quotient: Polynomial, remainder: Polynomial };
    const Extended = struct { g: Polynomial, s: Polynomial, t: Polynomial };

    fn fromOwned(values: []const Fraction) Polynomial {
        var length = values.len;
        while (length > 0 and values[length - 1].isZero()) length -= 1;
        return .{ .coefficients = values[0..length] };
    }
    fn init(gpa: Allocator, values: []const Fraction) Allocator.Error!Polynomial {
        return fromOwned(try gpa.dupe(Fraction, values));
    }
    fn constant(gpa: Allocator, value: Fraction) Allocator.Error!Polynomial {
        return if (value.isZero()) zero else init(gpa, &.{value});
    }
    fn degree(value: Polynomial) i32 { return @as(i32, @intCast(value.coefficients.len)) - 1; }
    fn isZero(value: Polynomial) bool { return value.coefficients.len == 0; }
    fn leading(value: Polynomial) Fraction { return value.coefficients[value.coefficients.len - 1]; }
    fn at(value: Polynomial, index: usize) Fraction { return if (index < value.coefficients.len) value.coefficients[index] else Fraction.zero; }
    fn add(a: Polynomial, gpa: Allocator, b: Polynomial) Allocator.Error!Polynomial {
        const result = try gpa.alloc(Fraction, @max(a.coefficients.len, b.coefficients.len));
        for (result, 0..) |*value, i| value.* = a.at(i).add(b.at(i));
        return fromOwned(result);
    }
    fn sub(a: Polynomial, gpa: Allocator, b: Polynomial) Allocator.Error!Polynomial {
        const result = try gpa.alloc(Fraction, @max(a.coefficients.len, b.coefficients.len));
        for (result, 0..) |*value, i| value.* = a.at(i).sub(b.at(i));
        return fromOwned(result);
    }
    fn neg(a: Polynomial, gpa: Allocator) Allocator.Error!Polynomial {
        const result = try gpa.alloc(Fraction, a.coefficients.len);
        for (result, a.coefficients) |*value, coefficient| value.* = coefficient.neg();
        return fromOwned(result);
    }
    fn mul(a: Polynomial, gpa: Allocator, b: Polynomial) Allocator.Error!Polynomial {
        if (a.isZero() or b.isZero()) return zero;
        const result = try gpa.alloc(Fraction, a.coefficients.len + b.coefficients.len - 1);
        @memset(result, Fraction.zero);
        for (a.coefficients, 0..) |left, i| {
            for (b.coefficients, 0..) |right, j| result[i + j] = result[i + j].add(left.mul(right));
        }
        return fromOwned(result);
    }
    fn scale(a: Polynomial, gpa: Allocator, factor: Fraction) Allocator.Error!Polynomial {
        const result = try gpa.alloc(Fraction, a.coefficients.len);
        for (result, a.coefficients) |*value, coefficient| value.* = coefficient.mul(factor);
        return fromOwned(result);
    }
    fn divideScalar(a: Polynomial, gpa: Allocator, divisor: Fraction) Allocator.Error!Polynomial {
        const result = try gpa.alloc(Fraction, a.coefficients.len);
        for (result, a.coefficients) |*value, coefficient| value.* = coefficient.div(divisor);
        return fromOwned(result);
    }
    fn monic(a: Polynomial, gpa: Allocator) Allocator.Error!Polynomial {
        return if (a.isZero()) zero else a.divideScalar(gpa, a.leading());
    }
    fn power(a: Polynomial, gpa: Allocator, exponent: usize) Allocator.Error!Polynomial {
        if (exponent == 0) return one;
        if (a.isZero()) return zero;
        if (a.degree() == 0 and a.leading().d == 1 and absolute(a.leading().n) == 1) {
            return if (a.leading().n == 1 or exponent % 2 == 0) one else a;
        }
        var result = one;
        for (0..exponent) |_| result = try result.mul(gpa, a);
        return result;
    }
    fn evaluate(a: Polynomial, point: Fraction) Fraction {
        var result = Fraction.zero;
        var i = a.coefficients.len;
        while (i > 0) {
            i -= 1;
            result = result.mul(point).add(a.at(i));
        }
        return result;
    }
    fn compose(a: Polynomial, gpa: Allocator, inner: Polynomial) Allocator.Error!Polynomial {
        var result = zero;
        var i = a.coefficients.len;
        while (i > 0) {
            i -= 1;
            result = try (try result.mul(gpa, inner)).add(gpa, try constant(gpa, a.at(i)));
        }
        return result;
    }
    fn derivative(a: Polynomial, gpa: Allocator, order: usize) Allocator.Error!Polynomial {
        var result = a;
        for (0..order) |_| {
            const values = try gpa.alloc(Fraction, result.coefficients.len -| 1);
            for (values, 1..) |*value, i| value.* = Fraction.whole(@intCast(i)).mul(result.at(i));
            result = fromOwned(values);
        }
        return result;
    }
    fn integral(a: Polynomial, gpa: Allocator) Allocator.Error!Polynomial {
        if (a.isZero()) return zero;
        const result = try gpa.alloc(Fraction, a.coefficients.len + 1);
        result[0] = Fraction.zero;
        for (a.coefficients, 1..) |value, i| result[i] = value.div(Fraction.whole(@intCast(i)));
        return fromOwned(result);
    }
    fn divide(a: Polynomial, gpa: Allocator, b: Polynomial) Allocator.Error!Division {
        const length = if (a.coefficients.len >= b.coefficients.len) a.coefficients.len - b.coefficients.len + 1 else 0;
        const quotient = try gpa.alloc(Fraction, length);
        @memset(quotient, Fraction.zero);
        const remainder = try gpa.dupe(Fraction, a.coefficients);
        var remaining = remainder.len;
        while (remaining > 0 and remaining >= b.coefficients.len) {
            const factor = remainder[remaining - 1].div(b.leading());
            const shift = remaining - b.coefficients.len;
            quotient[shift] = factor;
            for (b.coefficients, 0..) |value, j| remainder[shift + j] = remainder[shift + j].sub(factor.mul(value));
            while (remaining > 0 and remainder[remaining - 1].isZero()) remaining -= 1;
        }
        return .{ .quotient = fromOwned(quotient), .remainder = fromOwned(remainder[0..remaining]) };
    }
    fn greatestCommonDivisor(gpa: Allocator, left: Polynomial, right: Polynomial) Allocator.Error!Polynomial {
        var a = left;
        var b = right;
        while (!b.isZero()) {
            const remainder = (try a.divide(gpa, b)).remainder;
            a = b;
            b = remainder;
        }
        return a.monic(gpa);
    }
    fn extendedGcd(gpa: Allocator, a: Polynomial, b: Polynomial) Allocator.Error!Extended {
        var r0 = a;
        var r1 = b;
        var s0 = one;
        var s1 = zero;
        var t0 = zero;
        var t1 = one;
        while (!r1.isZero()) {
            const division = try r0.divide(gpa, r1);
            r0 = r1;
            r1 = division.remainder;
            const next_s = try s0.sub(gpa, try division.quotient.mul(gpa, s1));
            s0 = s1;
            s1 = next_s;
            const next_t = try t0.sub(gpa, try division.quotient.mul(gpa, t1));
            t0 = t1;
            t1 = next_t;
        }
        if (r0.isZero()) return .{ .g = r0, .s = s0, .t = t0 };
        return .{ .g = try r0.monic(gpa), .s = try s0.divideScalar(gpa, r0.leading()), .t = try t0.divideScalar(gpa, r0.leading()) };
    }
    fn content(a: Polynomial) Fraction {
        var denominator: i64 = 1;
        var numerator: i64 = 0;
        for (a.coefficients) |value| {
            denominator = @divTrunc(denominator * value.d, gcd(denominator, value.d));
            numerator = gcd(numerator, value.n);
        }
        return Fraction.init(if (a.leading().n < 0) -numerator else numerator, denominator);
    }
    fn primitive(a: Polynomial, gpa: Allocator) Allocator.Error!Polynomial { return a.divideScalar(gpa, a.content()); }
    fn squareFreePart(a: Polynomial, gpa: Allocator) Allocator.Error!Polynomial {
        if (a.degree() < 1) return a;
        const common = try greatestCommonDivisor(gpa, a, try a.derivative(gpa, 1));
        return (try a.divide(gpa, common)).quotient;
    }
    fn notation(a: Polynomial, variable_text: []const u8) Notation { return .{ .value = a, .variable = variable_text }; }
    pub fn format(a: Polynomial, out: *Writer) Writer.Error!void { try a.notation("x").format(out); }
};
const Notation = struct {
    value: Polynomial,
    variable: []const u8,
    pub fn format(notation: Notation, out: *Writer) Writer.Error!void {
        if (notation.value.isZero()) return out.writeByte('0');
        var first = true;
        var i = notation.value.coefficients.len;
        while (i > 0) {
            i -= 1;
            const coefficient = notation.value.at(i);
            if (coefficient.isZero()) continue;
            if (first) {
                if (coefficient.n < 0) try out.writeByte('-');
            } else try out.writeAll(if (coefficient.n < 0) " - " else " + ");
            const magnitude = coefficient.abs();
            if (i == 0 or !magnitude.eq(Fraction.one)) try out.print("{f}", .{magnitude});
            if (i > 0) try out.writeAll(notation.variable);
            if (i > 1) try out.print("^{d}", .{i});
            first = false;
        }
    }
};

fn checkProduct(a: Polynomial, b: Polynomial) SemanticError!void {
    if (!a.isZero() and !b.isZero() and a.degree() + b.degree() > 30) return error.DegreeLimit;
}
fn checkPower(a: Polynomial, exponent: usize) SemanticError!void {
    if (!a.isZero() and @as(usize, @intCast(a.degree())) * exponent > 30) return error.DegreeLimit;
}
fn checkComposition(a: Polynomial, b: Polynomial) SemanticError!void {
    if (a.degree() >= 1 and b.degree() >= 1 and a.degree() * b.degree() > 30) return error.DegreeLimit;
}
fn checkNonzero(a: Polynomial) SemanticError!void { if (a.isZero()) return error.ZeroPolynomial; }
fn checkDivisor(a: Polynomial) SemanticError!void { if (a.isZero()) return error.DivisionByZero; }
fn checkPositiveDegree(a: Polynomial) SemanticError!void { if (a.degree() == 0) return error.DegreeTooLow; }

const Expression = union(enum) {
    number: i64,
    variable,
    name: struct { text: []const u8, order: usize },
    negative: *const Expression,
    power: struct { operand: *const Expression, exponent: usize },
    binary: struct { operation: u8, left: *const Expression, right: *const Expression },
    call: struct { function: *const Expression, argument: *const Expression },

    fn evaluate(expression: *const Expression, session: *Session) Error!Polynomial {
        const gpa = session.gpa;
        switch (expression.*) {
            .number => |value| return Polynomial.constant(gpa, Fraction.whole(value)),
            .variable => return Polynomial.variable,
            .name => |name| return (try session.lookup(name.text)).derivative(gpa, name.order),
            .negative => |operand| return (try operand.evaluate(session)).neg(gpa),
            .power => |power| {
                const value = try power.operand.evaluate(session);
                try checkPower(value, power.exponent);
                return value.power(gpa, power.exponent);
            },
            .binary => |binary| {
                const a = try binary.left.evaluate(session);
                const b = try binary.right.evaluate(session);
                switch (binary.operation) {
                    '+' => return a.add(gpa, b),
                    '-' => return a.sub(gpa, b),
                    '*' => { try checkProduct(a, b); return a.mul(gpa, b); },
                    else => {
                        try checkDivisor(b);
                        if (b.degree() >= 1) return error.NonconstantDivisor;
                        return a.divideScalar(gpa, b.at(0));
                    },
                }
            },
            .call => |call| {
                const outer = try call.function.evaluate(session);
                const inner = try call.argument.evaluate(session);
                try checkComposition(outer, inner);
                return outer.compose(gpa, inner);
            },
        }
    }
};
const TokenKind = enum { number, name, symbol, end };
const Token = struct { kind: TokenKind, text: []const u8, position: usize };
const Parser = struct {
    session: *Session,
    tokens: [101]Token = undefined,
    count: usize = 0,
    position: usize = 0,

    fn digit(ch: u8) bool { return ch >= '0' and ch <= '9'; }
    fn upper(ch: u8) bool { return ch >= 'A' and ch <= 'Z'; }
    fn init(session: *Session, source: []const u8) Parser {
        var parser: Parser = .{ .session = session };
        var i: usize = 0;
        while (i < source.len) {
            if (source[i] == ' ') { i += 1; continue; }
            const start = i;
            i += 1;
            const kind: TokenKind = if (digit(source[start])) .number else if (upper(source[start])) .name else .symbol;
            if (kind == .number) {
                while (i < source.len and digit(source[i])) i += 1;
            } else if (kind == .name) {
                while (i < source.len and (upper(source[i]) or digit(source[i]))) i += 1;
            }
            parser.tokens[parser.count] = .{ .kind = kind, .text = source[start..i], .position = start + 1 };
            parser.count += 1;
        }
        parser.tokens[parser.count] = .{ .kind = .end, .text = "", .position = source.len + 1 };
        return parser;
    }
    fn current(parser: *const Parser) Token { return parser.tokens[parser.position]; }
    fn at(parser: *const Parser, symbol: []const u8) bool { return equal(parser.current().text, symbol); }
    fn syntax(parser: *Parser) Error {
        if (parser.current().kind == .end) return parser.session.fail("SYNTAX AT END", .{});
        return parser.session.fail("SYNTAX AT {d}", .{parser.current().position});
    }
    fn expect(parser: *Parser, symbol: []const u8) Error!void {
        if (!parser.at(symbol)) return parser.syntax();
        parser.position += 1;
    }
    fn node(parser: *Parser, tree: Expression) Allocator.Error!*const Expression {
        const result = try parser.session.gpa.create(Expression);
        result.* = tree;
        return result;
    }
    fn parse(parser: *Parser) Error!*const Expression {
        const result = try parser.expression();
        if (parser.current().kind != .end) return parser.syntax();
        return result;
    }
    fn expression(parser: *Parser) Error!*const Expression {
        const negative = parser.at("-");
        if (negative) parser.position += 1;
        var result = try parser.term();
        if (negative) result = try parser.node(.{ .negative = result });
        while (parser.at("+") or parser.at("-")) {
            const operation = parser.current().text[0];
            parser.position += 1;
            const right = try parser.term();
            result = try parser.node(.{ .binary = .{ .operation = operation, .left = result, .right = right } });
        }
        return result;
    }
    fn term(parser: *Parser) Error!*const Expression {
        var result = try parser.factor();
        while (true) {
            var operation: u8 = '*';
            if (parser.at("*") or parser.at("/")) {
                operation = parser.current().text[0];
                parser.position += 1;
            } else if (!parser.at("x") and !parser.at("(") and parser.current().kind != .name) break;
            const right = try parser.factor();
            result = try parser.node(.{ .binary = .{ .operation = operation, .left = result, .right = right } });
        }
        return result;
    }
    fn factor(parser: *Parser) Error!*const Expression {
        var result = try parser.primary();
        if (parser.at("^")) {
            parser.position += 1;
            if (parser.current().kind != .number) return parser.syntax();
            const exponent = natural(parser.current().text);
            parser.position += 1;
            result = try parser.node(.{ .power = .{ .operand = result, .exponent = exponent } });
        }
        return result;
    }
    fn primary(parser: *Parser) Error!*const Expression {
        const token = parser.current();
        if (token.kind == .number) {
            parser.position += 1;
            return parser.node(.{ .number = integer(token.text) });
        }
        if (parser.at("x")) { parser.position += 1; return parser.node(.variable); }
        if (token.kind == .name) {
            parser.position += 1;
            var order: usize = 0;
            while (parser.at("'")) { parser.position += 1; order += 1; }
            const reference = try parser.node(.{ .name = .{ .text = token.text, .order = order } });
            if (!parser.at("(")) return reference;
            parser.position += 1;
            const argument = try parser.expression();
            try parser.expect(")");
            return parser.node(.{ .call = .{ .function = reference, .argument = argument } });
        }
        if (parser.at("(")) {
            parser.position += 1;
            const result = try parser.expression();
            try parser.expect(")");
            return result;
        }
        return parser.syntax();
    }
};

const Endpoint = struct {
    infinity: i32 = 0,
    value: Fraction = Fraction.zero,
    fn parse(text: []const u8) SemanticError!Endpoint {
        if (equal(text, "-inf")) return .{ .infinity = -1 };
        if (equal(text, "inf")) return .{ .infinity = 1 };
        return .{ .value = try Fraction.parse(text) };
    }
    fn less(a: Endpoint, b: Endpoint) bool {
        return if (a.infinity == 0 and b.infinity == 0) a.value.less(b.value) else a.infinity < b.infinity;
    }
    pub fn format(value: Endpoint, out: *Writer) Writer.Error!void {
        if (value.infinity == 0) try out.print("{f}", .{value.value})
        else try out.writeAll(if (value.infinity < 0) "-inf" else "inf");
    }
};
const Root = struct {
    value: Fraction,
    multiplicity: usize,
    fn lessThan(_: void, a: Root, b: Root) bool { return a.value.less(b.value); }
};
const Roots = struct { content: Fraction, remaining: Polynomial, roots: []const Root };
const Factor = struct { value: Polynomial, multiplicity: usize };
const Interval = struct { left: Fraction, right: Fraction };

fn rationalRoots(gpa: Allocator, value: Polynomial) Allocator.Error!Roots {
    const content = value.content();
    var remaining = try value.divideScalar(gpa, content);
    var zeros: usize = 0;
    while (remaining.at(0).isZero()) {
        remaining = .{ .coefficients = remaining.coefficients[1..] };
        zeros += 1;
    }
    const a = absolute(remaining.at(0).n);
    const b = remaining.leading().n;
    var candidates: std.ArrayList(Fraction) = .empty;
    var s: i64 = 1;
    while (s <= a) : (s += 1) {
        if (@mod(a, s) != 0) continue;
        var t: i64 = 1;
        while (t <= b) : (t += 1) {
            if (@mod(b, t) != 0 or gcd(s, t) != 1) continue;
            try candidates.append(gpa, Fraction.init(s, t));
            try candidates.append(gpa, Fraction.init(-s, t));
        }
    }
    std.sort.heap(Fraction, candidates.items, {}, Fraction.lessThan);
    var roots: std.ArrayList(Root) = .empty;
    for (candidates.items) |candidate| {
        const divisor = try Polynomial.init(gpa, &.{ Fraction.whole(-candidate.n), Fraction.whole(candidate.d) });
        var count: usize = 0;
        while (remaining.degree() >= 1 and remaining.evaluate(candidate).isZero()) {
            remaining = (try remaining.divide(gpa, divisor)).quotient;
            count += 1;
        }
        if (count > 0) try roots.append(gpa, .{ .value = candidate, .multiplicity = count });
    }
    if (zeros > 0) try roots.append(gpa, .{ .value = Fraction.zero, .multiplicity = zeros });
    std.sort.heap(Root, roots.items, {}, Root.lessThan);
    return .{ .content = content, .remaining = remaining, .roots = roots.items };
}

fn squareFreeFactors(gpa: Allocator, value: Polynomial) Allocator.Error![]const Factor {
    var result: std.ArrayList(Factor) = .empty;
    if (value.degree() < 1) return result.items;
    const monic = try value.monic(gpa);
    var c = try Polynomial.greatestCommonDivisor(gpa, monic, try monic.derivative(gpa, 1));
    var w = (try monic.divide(gpa, c)).quotient;
    var i: usize = 1;
    while (w.degree() >= 1) : (i += 1) {
        const y = try Polynomial.greatestCommonDivisor(gpa, w, c);
        const factor = (try w.divide(gpa, y)).quotient;
        if (factor.degree() >= 1) try result.append(gpa, .{ .value = try factor.primitive(gpa), .multiplicity = i });
        c = (try c.divide(gpa, y)).quotient;
        w = y;
    }
    return result.items;
}

fn sturmSequence(gpa: Allocator, value: Polynomial) Allocator.Error![]const Polynomial {
    var previous = try value.squareFreePart(gpa);
    var current = try previous.derivative(gpa, 1);
    var result: std.ArrayList(Polynomial) = .empty;
    try result.append(gpa, previous);
    while (!current.isZero()) {
        try result.append(gpa, current);
        const next = try (try previous.divide(gpa, current)).remainder.neg(gpa);
        previous = current;
        current = next;
    }
    return result.items;
}
fn variations(sequence: []const Polynomial, point: Endpoint) i32 {
    var previous: i32 = 0;
    var count: i32 = 0;
    for (sequence) |value| {
        var sign = if (point.infinity == 0) value.evaluate(point.value).sign() else value.leading().sign();
        if (point.infinity < 0 and @mod(value.degree(), 2) != 0) sign = -sign;
        if (sign == 0) continue;
        if (previous != 0 and sign != previous) count += 1;
        previous = sign;
    }
    return count;
}
fn rootCount(sequence: []const Polynomial, left: Endpoint, right: Endpoint) i32 {
    const left_count = variations(sequence, left);
    const right_count = variations(sequence, right);
    return left_count - right_count;
}
const Isolation = struct {
    gpa: Allocator,
    sequence: []const Polynomial,
    width: Fraction,
    intervals: std.ArrayList(Interval) = .empty,
    fn count(isolation: *const Isolation, left: Fraction, right: Fraction) i32 {
        return rootCount(isolation.sequence, .{ .value = left }, .{ .value = right });
    }
    fn examine(isolation: *Isolation, low: Fraction, high: Fraction) Allocator.Error!void {
        const root_count = isolation.count(low, high);
        if (root_count >= 2) {
            const middle = low.add(high).div(Fraction.whole(2));
            try isolation.examine(low, middle);
            try isolation.examine(middle, high);
        } else if (root_count == 1) {
            var left = low;
            var right = high;
            while (isolation.width.less(right.sub(left))) {
                const middle = left.add(right).div(Fraction.whole(2));
                if (isolation.count(left, middle) >= 1) right = middle else left = middle;
            }
            try isolation.intervals.append(isolation.gpa, .{ .left = left, .right = right });
        }
    }
};
fn isolate(gpa: Allocator, value: Polynomial, precision: usize) Allocator.Error![]const Interval {
    const sequence = try sturmSequence(gpa, value);
    const first = sequence[0];
    var maximum = Fraction.zero;
    for (first.coefficients[0 .. first.coefficients.len - 1]) |coefficient| {
        const candidate = coefficient.div(first.leading()).abs();
        if (maximum.less(candidate)) maximum = candidate;
    }
    const beta = Fraction.one.add(maximum);
    var isolation: Isolation = .{ .gpa = gpa, .sequence = sequence, .width = Fraction.init(1, @as(i64, 1) << @intCast(precision)) };
    try isolation.examine(beta.neg(), beta);
    return isolation.intervals.items;
}
fn resultant(gpa: Allocator, a: Polynomial, b: Polynomial) Allocator.Error!Fraction {
    var p = a;
    var q = b;
    var result = Fraction.one;
    while (q.degree() >= 1) {
        const remainder = (try p.divide(gpa, q)).remainder;
        if (remainder.isZero()) return Fraction.zero;
        result = result.mul(q.leading().power(@intCast(p.degree() - remainder.degree())));
        if (@mod(p.degree() * q.degree(), 2) != 0) result = result.neg();
        p = q;
        q = remainder;
    }
    return result.mul(q.at(0).power(@intCast(p.degree())));
}
fn descartes(value: Polynomial, negative: bool) usize {
    var previous: i32 = 0;
    var count: usize = 0;
    var i = value.coefficients.len;
    while (i > 0) {
        i -= 1;
        var sign = value.at(i).sign();
        if (negative and i % 2 != 0) sign = -sign;
        if (sign == 0) continue;
        if (previous != 0 and sign != previous) count += 1;
        previous = sign;
    }
    return count;
}

fn interpolate(session: *Session, values: []const Fraction) Error!Polynomial {
    const gpa = session.gpa;
    const count = values.len / 2;
    const points = try gpa.alloc(Fraction, count);
    const differences = try gpa.alloc(Fraction, count);
    for (0..count) |i| { points[i] = values[2 * i]; differences[i] = values[2 * i + 1]; }
    for (1..count) |j| {
        for (0..j) |i| if (points[j].eq(points[i])) return session.fail("DUPLICATE X {f}", .{points[j]});
    }
    for (1..count) |j| {
        var i = count;
        while (i > j) {
            i -= 1;
            differences[i] = differences[i].sub(differences[i - 1]).div(points[i].sub(points[i - j]));
        }
    }
    var result = Polynomial.zero;
    var i = count;
    while (i > 0) {
        i -= 1;
        const factor = try Polynomial.init(gpa, &.{ points[i].neg(), Fraction.one });
        result = try (try result.mul(gpa, factor)).add(gpa, try Polynomial.constant(gpa, differences[i]));
    }
    return result;
}
const SpecialKind = enum { chebyshev, chebyshev2, legendre, hermite, laguerre };
fn special(session: *Session, text: []const u8, degree: usize) Error!Polynomial {
    const kind = std.meta.stringToEnum(SpecialKind, text) orelse return session.fail("UNKNOWN KIND {s}", .{text});
    if (degree > 30) return error.DegreeLimit;
    const gpa = session.gpa;
    var previous = Polynomial.one;
    if (degree == 0) return previous;
    var current = switch (kind) {
        .chebyshev2, .hermite => try Polynomial.init(gpa, &.{ Fraction.zero, Fraction.whole(2) }),
        .laguerre => try Polynomial.init(gpa, &.{ Fraction.one, Fraction.whole(-1) }),
        else => Polynomial.variable,
    };
    for (1..degree) |step| {
        const j: i64 = @intCast(step);
        const factor = switch (kind) {
            .legendre => try Polynomial.init(gpa, &.{ Fraction.zero, Fraction.whole(2 * j + 1) }),
            .laguerre => try Polynomial.init(gpa, &.{ Fraction.whole(2 * j + 1), Fraction.whole(-1) }),
            else => try Polynomial.init(gpa, &.{ Fraction.zero, Fraction.whole(2) }),
        };
        const scale = switch (kind) { .legendre, .laguerre => j, .hermite => 2 * j, else => 1 };
        var next = try (try factor.mul(gpa, current)).sub(gpa, try previous.scale(gpa, Fraction.whole(scale)));
        if (kind == .legendre or kind == .laguerre) next = try next.scale(gpa, Fraction.init(1, j + 1));
        previous = current;
        current = next;
    }
    return current;
}

const Name = struct {
    bytes: [8]u8 = @splat(0),
    len: usize = 0,
    fn init(text: []const u8) Name {
        var name: Name = .{ .len = text.len };
        @memcpy(name.bytes[0..text.len], text);
        return name;
    }
    fn matches(name: Name, text: []const u8) bool { return equal(name.bytes[0..name.len], text); }
    pub fn format(name: Name, out: *Writer) Writer.Error!void { try out.writeAll(name.bytes[0..name.len]); }
};
const Stored = struct {
    name: Name,
    value: Polynomial,
    fn lessThan(_: void, a: Stored, b: Stored) bool {
        return std.mem.order(u8, a.name.bytes[0..a.name.len], b.name.bytes[0..b.name.len]) == .lt;
    }
};
const Storage = struct {
    gpa: Allocator,
    entries: std.ArrayList(Stored) = .empty,
    fn find(storage: *const Storage, text: []const u8) ?usize {
        for (storage.entries.items, 0..) |entry, i| if (entry.name.matches(text)) return i;
        return null;
    }
    fn set(storage: *Storage, entry: Stored) Allocator.Error!void {
        const saved: Stored = .{ .name = entry.name, .value = try Polynomial.init(storage.gpa, entry.value.coefficients) };
        if (storage.find(entry.name.bytes[0..entry.name.len])) |i| storage.entries.items[i] = saved
        else try storage.entries.append(storage.gpa, saved);
    }
};
fn nameArguments(command: Command) []const usize {
    return switch (command) {
        .PRINT, .DELETE, .DEGREE, .AREA, .TAYLOR, .EVAL, .ROOTS, .FACTOR, .SQFREE,
        .DESCARTES, .STURM, .ISOLATE, .DISCRIM, .POWERSUM => &.{1},
        .ADD, .SUB, .MUL, .GCD, .LCM, .INVMOD, .COMPOSE => &.{ 2, 3 },
        .POW, .DERIV, .INTEG, .TANGENT => &.{2},
        .DIV => &.{ 3, 4 }, .XGCD => &.{ 4, 5 }, .CRT => &.{ 2, 3, 4, 5 },
        .MODPOW => &.{ 2, 4 }, .RESULTANT => &.{ 1, 2 }, else => &.{},
    };
}
const Session = struct {
    gpa: Allocator,
    storage: *Storage,
    out: *Writer,
    problem: ?[]const u8 = null,
    pending: [3]Stored = undefined,
    pending_count: usize = 0,
    deletion: ?usize = null,

    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn lookup(session: *Session, text: []const u8) Error!Polynomial {
        const i = session.storage.find(text) orelse return session.fail("UNKNOWN {s}", .{text});
        return session.storage.entries.items[i].value;
    }
    fn save(session: *Session, name: []const u8, value: Polynomial) Writer.Error!void {
        session.pending[session.pending_count] = .{ .name = Name.init(name), .value = value };
        session.pending_count += 1;
        try line(session.out, "{s} = {f}", .{ name, value });
    }
    fn commit(session: *Session) Allocator.Error!void {
        if (session.deletion) |i| _ = session.storage.entries.orderedRemove(i);
        for (session.pending[0..session.pending_count]) |entry| try session.storage.set(entry);
    }
    fn process(session: *Session, text: []const u8) Error!void {
        const gpa = session.gpa;
        const out = session.out;
        if (std.mem.startsWith(u8, text, "DEF ")) {
            const separator = 4 + std.mem.findScalar(u8, text[4..], ' ').?;
            var parser = Parser.init(session, text[separator + 1 ..]);
            const expression = try parser.parse();
            return session.save(text[4..separator], try expression.evaluate(session));
        }
        var words_buffer: [64][]const u8 = undefined;
        var word_count: usize = 0;
        var iterator = std.mem.splitScalar(u8, text, ' ');
        while (iterator.next()) |word| { words_buffer[word_count] = word; word_count += 1; }
        const words = words_buffer[0..word_count];
        const command = std.meta.stringToEnum(Command, words[0]).?;
        if (command == .DIV and equal(words[1], words[2]) or command == .XGCD and
            (equal(words[1], words[2]) or equal(words[1], words[3]) or equal(words[2], words[3]))) return error.SameName;
        var operands: [4]Polynomial = @splat(Polynomial.zero);
        for (nameArguments(command), 0..) |index, i| operands[i] = try session.lookup(words[index]);
        var literals: [62]Fraction = undefined;
        var literal_count: usize = 0;
        const literal_indices: []const usize = switch (command) { .AREA => &.{ 2, 3 }, .TANGENT => &.{3}, .TAYLOR => &.{2}, else => &.{} };
        for (literal_indices) |index| { literals[literal_count] = try Fraction.parse(words[index]); literal_count += 1; }
        if (command == .EVAL or command == .INTERP) {
            for (words[2..]) |word| { literals[literal_count] = try Fraction.parse(word); literal_count += 1; }
        }
        var left: Endpoint = .{};
        var right: Endpoint = .{};
        if (command == .STURM) { left = try Endpoint.parse(words[2]); right = try Endpoint.parse(words[3]); }
        const a = operands[0];
        const b = operands[1];
        switch (command) {
            .DEF => unreachable,
            .PRINT => try line(out, "{s} = {f}", .{ words[1], a }),
            .DELETE => {
                session.deletion = session.storage.find(words[1]).?;
                try line(out, "deleted {s}", .{words[1]});
            },
            .LIST => {
                if (session.storage.entries.items.len == 0) return line(out, "no polynomials", .{});
                const entries = try gpa.dupe(Stored, session.storage.entries.items);
                std.sort.heap(Stored, entries, {}, Stored.lessThan);
                for (entries) |entry| try line(out, "{f} = {f}", .{ entry.name, entry.value });
            },
            .DEGREE => {
                if (a.isZero()) try line(out, "deg({s}) = -inf", .{words[1]})
                else try line(out, "deg({s}) = {d}", .{ words[1], a.degree() });
            },
            .ADD => try session.save(words[1], try a.add(gpa, b)),
            .SUB => try session.save(words[1], try a.sub(gpa, b)),
            .MUL => { try checkProduct(a, b); try session.save(words[1], try a.mul(gpa, b)); },
            .POW => {
                const exponent = natural(words[3]);
                try checkPower(a, exponent);
                try session.save(words[1], try a.power(gpa, exponent));
            },
            .DIV => {
                try checkDivisor(b);
                const division = try a.divide(gpa, b);
                try session.save(words[1], division.quotient);
                try session.save(words[2], division.remainder);
            },
            .GCD => try session.save(words[1], try Polynomial.greatestCommonDivisor(gpa, a, b)),
            .XGCD => {
                const result = try Polynomial.extendedGcd(gpa, a, b);
                try session.save(words[1], result.g);
                try session.save(words[2], result.s);
                try session.save(words[3], result.t);
            },
            .LCM => {
                var result = Polynomial.zero;
                if (!a.isZero() and !b.isZero()) {
                    const common = try Polynomial.greatestCommonDivisor(gpa, a, b);
                    if (a.degree() + b.degree() - common.degree() > 30) return error.DegreeLimit;
                    result = try (try (try a.divide(gpa, common)).quotient.mul(gpa, b)).monic(gpa);
                }
                try session.save(words[1], result);
            },
            .INVMOD => {
                try checkDivisor(b);
                try checkPositiveDegree(b);
                const result = try Polynomial.extendedGcd(gpa, a, b);
                if (result.g.degree() != 0 or !result.g.at(0).eq(Fraction.one)) return error.NotCoprime;
                try session.save(words[1], (try result.s.divide(gpa, b)).remainder);
            },
            .CRT => {
                const a2 = operands[2];
                const m2 = operands[3];
                try checkDivisor(b);
                try checkDivisor(m2);
                if (b.degree() + m2.degree() > 30) return error.DegreeLimit;
                const result = try Polynomial.extendedGcd(gpa, b, m2);
                if (result.g.degree() != 0 or !result.g.at(0).eq(Fraction.one)) return error.NotCoprime;
                const r1 = (try a.divide(gpa, b)).remainder;
                const r2 = (try a2.divide(gpa, m2)).remainder;
                const u = (try (try (try r2.sub(gpa, r1)).mul(gpa, result.s)).divide(gpa, m2)).remainder;
                try session.save(words[1], try r1.add(gpa, try b.mul(gpa, u)));
            },
            .MODPOW => {
                try checkDivisor(b);
                if (2 * b.degree() - 2 > 30) return error.DegreeLimit;
                var x = (try Polynomial.one.divide(gpa, b)).remainder;
                var y = (try a.divide(gpa, b)).remainder;
                var exponent = natural(words[3]);
                while (exponent > 0) {
                    if (exponent % 2 != 0) x = (try (try x.mul(gpa, y)).divide(gpa, b)).remainder;
                    exponent /= 2;
                    if (exponent != 0) y = (try (try y.mul(gpa, y)).divide(gpa, b)).remainder;
                }
                try session.save(words[1], x);
            },
            .DERIV => try session.save(words[1], try a.derivative(gpa, natural(words[3]))),
            .INTEG => {
                if (a.degree() == 30) return error.DegreeLimit;
                try session.save(words[1], try a.integral(gpa));
            },
            .AREA => {
                const antiderivative = try a.integral(gpa);
                const upper = antiderivative.evaluate(literals[1]);
                const lower = antiderivative.evaluate(literals[0]);
                try line(out, "integral({s}, {f}, {f}) = {f}", .{ words[1], literals[0], literals[1], upper.sub(lower) });
            },
            .TANGENT => {
                const point = literals[0];
                const height = a.evaluate(point);
                const slope = (try a.derivative(gpa, 1)).evaluate(point);
                try session.save(words[1], try Polynomial.init(gpa, &.{ height.sub(slope.mul(point)), slope }));
            },
            .TAYLOR => {
                const point = literals[0];
                const shifted = try a.compose(gpa, try Polynomial.init(gpa, &.{ point, Fraction.one }));
                const variable_text = if (point.isZero()) "x" else if (point.n > 0) try std.fmt.allocPrint(gpa, "(x - {f})", .{point})
                    else try std.fmt.allocPrint(gpa, "(x + {f})", .{point.neg()});
                try line(out, "taylor({s}, {f}) = {f}", .{ words[1], point, shifted.notation(variable_text) });
            },
            .COMPOSE => { try checkComposition(a, b); try session.save(words[1], try a.compose(gpa, b)); },
            .EVAL => for (literals[0..literal_count]) |point| try line(out, "{s}({f}) = {f}", .{ words[1], point, a.evaluate(point) }),
            .ROOTS, .FACTOR => {
                try checkNonzero(a);
                const result = try rationalRoots(gpa, a);
                if (command == .ROOTS) {
                    try out.print("roots({s}) = ", .{words[1]});
                    if (result.roots.len == 0) try out.writeAll("none");
                    for (result.roots, 0..) |root, i| {
                        if (i > 0) try out.writeAll(", ");
                        try out.print("{f} ({d})", .{ root.value, root.multiplicity });
                    }
                } else {
                    try out.print("factor({s}) = {f}", .{ words[1], result.content });
                    for (result.roots) |root| {
                        if (root.value.isZero()) try out.writeAll(" * x") else {
                            const factor = try Polynomial.init(gpa, &.{ Fraction.whole(-root.value.n), Fraction.whole(root.value.d) });
                            try out.print(" * ({f})", .{factor});
                        }
                        if (root.multiplicity >= 2) try out.print("^{d}", .{root.multiplicity});
                    }
                    if (result.remaining.degree() >= 1) try out.print(" * ({f})", .{result.remaining});
                }
                try out.writeByte('\n');
            },
            .SQFREE => {
                try checkNonzero(a);
                const factors = try squareFreeFactors(gpa, a);
                try out.print("sqfree({s}) = {f}", .{ words[1], a.content() });
                for (factors) |factor| {
                    const is_x = factor.value.degree() == 1 and factor.value.at(0).isZero() and factor.value.at(1).eq(Fraction.one);
                    if (is_x) try out.writeAll(" * x") else try out.print(" * ({f})", .{factor.value});
                    if (factor.multiplicity >= 2) try out.print("^{d}", .{factor.multiplicity});
                }
                try out.writeByte('\n');
            },
            .DESCARTES => {
                try checkNonzero(a);
                try line(out, "descartes({s}) = positive {d}, negative {d}", .{ words[1], descartes(a, false), descartes(a, true) });
            },
            .STURM => {
                try checkNonzero(a);
                if (!left.less(right)) return error.BadInterval;
                const sequence = try sturmSequence(gpa, a);
                try line(out, "sturm({s}, {f}, {f}) = {d}", .{ words[1], left, right, rootCount(sequence, left, right) });
            },
            .ISOLATE => {
                try checkNonzero(a);
                const precision = natural(words[2]);
                const intervals = try isolate(gpa, a, precision);
                try out.print("isolate({s}, {d}) = ", .{ words[1], precision });
                if (intervals.len == 0) try out.writeAll("none");
                for (intervals, 0..) |interval, i| {
                    if (i > 0) try out.writeAll(", ");
                    try out.print("({f}, {f}]", .{ interval.left, interval.right });
                }
                try out.writeByte('\n');
            },
            .RESULTANT => {
                try checkNonzero(a);
                try checkNonzero(b);
                try line(out, "res({s}, {s}) = {f}", .{ words[1], words[2], try resultant(gpa, a, b) });
            },
            .DISCRIM => {
                try checkNonzero(a);
                try checkPositiveDegree(a);
                var value = (try resultant(gpa, a, try a.derivative(gpa, 1))).div(a.leading());
                if (@mod(@divTrunc(a.degree() * (a.degree() - 1), 2), 2) != 0) value = value.neg();
                try line(out, "disc({s}) = {f}", .{ words[1], value });
            },
            .POWERSUM => {
                try checkNonzero(a);
                try checkPositiveDegree(a);
                const count = natural(words[2]);
                const monic = try a.monic(gpa);
                const degree: usize = @intCast(a.degree());
                var sums: [31]Fraction = @splat(Fraction.zero);
                for (1..count + 1) |j| {
                    var value = if (j <= degree) Fraction.whole(@intCast(j)).mul(monic.at(degree - j)) else Fraction.zero;
                    for (1..@min(j - 1, degree) + 1) |i| value = value.add(monic.at(degree - i).mul(sums[j - i]));
                    sums[j] = value.neg();
                }
                try out.print("powersum({s}) = ", .{words[1]});
                for (sums[1 .. count + 1], 0..) |value, i| {
                    if (i > 0) try out.writeAll(", ");
                    try out.print("{f}", .{value});
                }
                try out.writeByte('\n');
            },
            .INTERP => try session.save(words[1], try interpolate(session, literals[0..literal_count])),
            .SPECIAL => try session.save(words[1], try special(session, words[2], natural(words[3]))),
        }
    }
};

fn errorReason(err: anyerror, session: *const Session) ?[]const u8 {
    return switch (err) {
        error.BadCommand => session.problem.?, error.SameName => "SAME NAME",
        error.ZeroDenominator => "ZERO DENOMINATOR", error.DivisionByZero => "DIVISION BY ZERO",
        error.NonconstantDivisor => "NONCONSTANT DIVISOR", error.DegreeLimit => "DEGREE LIMIT",
        error.ZeroPolynomial => "ZERO POLYNOMIAL", error.BadInterval => "BAD INTERVAL",
        error.DegreeTooLow => "DEGREE TOO LOW", error.NotCoprime => "NOT COPRIME", else => null,
    };
}
fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len != 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}

pub fn main(init: std.process.Init) !void {
    var storage_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage_arena.deinit();
    var storage: Storage = .{ .gpa = storage_arena.allocator() };
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = natural(try readLine(storage.gpa, &input.interface));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = gpa, .storage = &storage, .out = &response.writer };
        session.process(text) catch |err| {
            const reason = errorReason(err, &session) orelse return err;
            try line(&output.interface, "ERROR {s}", .{reason});
            continue;
        };
        try session.commit();
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
