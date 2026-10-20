const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Command = enum {
    DEFINE, UNDEF, DEFS, CONVERT, INVERT, DIM, REDUCE, SIMPLIFY, ADD, SUB, MUL,
    DIV, TEMP, COMPARE, LIST, TABLE, AUTO, SPLIT, LET, EVAL, VARS,
};

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn letter(c: u8) bool { return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z'); }
fn digit(c: u8) bool { return c >= '0' and c <= '9'; }
fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!digit(c)) return false;
    return true;
}
fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn absolute(value: i64) i64 { return if (value < 0) -value else value; }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
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
    const one: Fraction = .{ .n = 1 };

    fn init(n: i64, d: i64) Fraction {
        const divisor = gcd(n, d) * @as(i64, if (d < 0) -1 else 1);
        return .{ .n = @divTrunc(n, divisor), .d = @divTrunc(d, divisor) };
    }
    fn whole(n: i64) Fraction { return .{ .n = n }; }
    fn add(a: Fraction, b: Fraction) Fraction { return init(a.n * b.d + b.n * a.d, a.d * b.d); }
    fn sub(a: Fraction, b: Fraction) Fraction { return init(a.n * b.d - b.n * a.d, a.d * b.d); }
    fn mul(a: Fraction, b: Fraction) Fraction { return init(a.n * b.n, a.d * b.d); }
    fn div(a: Fraction, b: Fraction) Fraction { return init(a.n * b.d, a.d * b.n); }
    fn neg(a: Fraction) Fraction { return .{ .n = -a.n, .d = a.d }; }
    fn abs(a: Fraction) Fraction { return .{ .n = absolute(a.n), .d = a.d }; }
    fn eq(a: Fraction, b: Fraction) bool { return a.n == b.n and a.d == b.d; }
    fn less(a: Fraction, b: Fraction) bool { return a.n * b.d < b.n * a.d; }
    fn power(a: Fraction, exponent: i64) Fraction {
        const factor = if (exponent < 0) one.div(a) else a;
        var result = one;
        var i: i64 = 0;
        while (i < absolute(exponent)) : (i += 1) result = result.mul(factor);
        return result;
    }
    pub fn format(value: Fraction, out: *Writer) Writer.Error!void {
        try out.print("{d}", .{value.n});
        if (value.d != 1) try out.print("/{d}", .{value.d});
    }
};
const Decimal = struct {
    value: Fraction,
    pub fn format(decimal: Decimal, out: *Writer) Writer.Error!void {
        const magnitude = absolute(decimal.value.n);
        if (decimal.value.n < 0) try out.writeByte('-');
        try out.print("{d}.{d:0>6}", .{
            @divTrunc(magnitude, decimal.value.d),
            @divTrunc(@mod(magnitude, decimal.value.d) * 1_000_000, decimal.value.d),
        });
    }
};
const Notation = struct {
    value: Fraction,
    unit: []const u8,
    pub fn format(quantity: Notation, out: *Writer) Writer.Error!void {
        try out.print("{f} {s} ({f})", .{ quantity.value, quantity.unit, Decimal{ .value = quantity.value } });
    }
};
fn notation(value: Fraction, unit: []const u8) Notation { return .{ .value = value, .unit = unit }; }

const Dimension = struct {
    exponents: [7]i64 = .{0} ** 7,
    const zero: Dimension = .{};
    fn eq(a: Dimension, b: Dimension) bool { return std.mem.eql(i64, &a.exponents, &b.exponents); }
    fn add(a: Dimension, b: Dimension) Dimension {
        var result: Dimension = .{};
        for (&result.exponents, a.exponents, b.exponents) |*value, x, y| value.* = x + y;
        return result;
    }
    fn sub(a: Dimension, b: Dimension) Dimension {
        var result: Dimension = .{};
        for (&result.exponents, a.exponents, b.exponents) |*value, x, y| value.* = x - y;
        return result;
    }
    fn scale(a: Dimension, k: i64) Dimension {
        var result: Dimension = .{};
        for (&result.exponents, a.exponents) |*value, x| value.* = x * k;
        return result;
    }
    fn half(a: Dimension) Dimension {
        var result: Dimension = .{};
        for (&result.exponents, a.exponents) |*value, x| value.* = @divTrunc(x, 2);
        return result;
    }
    fn even(a: Dimension) bool {
        for (a.exponents) |value| if (@mod(value, 2) != 0) return false;
        return true;
    }
    pub fn format(dimension: Dimension, out: *Writer) Writer.Error!void {
        const symbols = [_][]const u8{ "kg", "m", "s", "A", "K", "mol", "cd" };
        var first = true;
        for (dimension.exponents, symbols) |value, symbol| {
            if (value == 0) continue;
            if (!first) try out.writeByte(' ');
            first = false;
            try out.writeAll(symbol);
            if (value != 1) try out.print("^{d}", .{value});
        }
        if (first) try out.writeByte('1');
    }
};
const Quantity = struct { value: Fraction, dimension: Dimension };
const Definition = struct { value: Fraction, expression: []const u8 };
const Unit = struct { symbol: []const u8, quantity: Quantity, prefix: bool, definition: ?Definition = null };
const Variable = struct { name: []const u8, quantity: Quantity };
const Kind = enum {
    dimensionless, length, mass, time, current, temperature, amount, luminous_intensity,
    area, volume, speed, acceleration, density, momentum, force, energy, power, pressure,
    frequency, charge, voltage, resistance, conductance, capacitance, magnetic_flux,
    flux_density, inductance, illuminance, catalytic_activity,
};
const kind_dimensions = [_]Dimension{
    .{}, .{ .exponents = .{ 0, 1, 0, 0, 0, 0, 0 } }, .{ .exponents = .{ 1, 0, 0, 0, 0, 0, 0 } },
    .{ .exponents = .{ 0, 0, 1, 0, 0, 0, 0 } }, .{ .exponents = .{ 0, 0, 0, 1, 0, 0, 0 } },
    .{ .exponents = .{ 0, 0, 0, 0, 1, 0, 0 } }, .{ .exponents = .{ 0, 0, 0, 0, 0, 1, 0 } },
    .{ .exponents = .{ 0, 0, 0, 0, 0, 0, 1 } }, .{ .exponents = .{ 0, 2, 0, 0, 0, 0, 0 } },
    .{ .exponents = .{ 0, 3, 0, 0, 0, 0, 0 } }, .{ .exponents = .{ 0, 1, -1, 0, 0, 0, 0 } },
    .{ .exponents = .{ 0, 1, -2, 0, 0, 0, 0 } }, .{ .exponents = .{ 1, -3, 0, 0, 0, 0, 0 } },
    .{ .exponents = .{ 1, 1, -1, 0, 0, 0, 0 } }, .{ .exponents = .{ 1, 1, -2, 0, 0, 0, 0 } },
    .{ .exponents = .{ 1, 2, -2, 0, 0, 0, 0 } }, .{ .exponents = .{ 1, 2, -3, 0, 0, 0, 0 } },
    .{ .exponents = .{ 1, -1, -2, 0, 0, 0, 0 } }, .{ .exponents = .{ 0, 0, -1, 0, 0, 0, 0 } },
    .{ .exponents = .{ 0, 0, 1, 1, 0, 0, 0 } }, .{ .exponents = .{ 1, 2, -3, -1, 0, 0, 0 } },
    .{ .exponents = .{ 1, 2, -3, -2, 0, 0, 0 } }, .{ .exponents = .{ -1, -2, 3, 2, 0, 0, 0 } },
    .{ .exponents = .{ -1, -2, 4, 2, 0, 0, 0 } }, .{ .exponents = .{ 1, 2, -2, -1, 0, 0, 0 } },
    .{ .exponents = .{ 1, 0, -2, -1, 0, 0, 0 } }, .{ .exponents = .{ 1, 2, -2, -2, 0, 0, 0 } },
    .{ .exponents = .{ 0, -2, 0, 0, 0, 0, 1 } }, .{ .exponents = .{ 0, 0, -1, 0, 0, 1, 0 } },
};
fn kindName(dimension: Dimension) []const u8 {
    for (kind_dimensions, 0..) |candidate, i| if (candidate.eq(dimension)) return @tagName(@as(Kind, @enumFromInt(i)));
    return "-";
}
fn builtin(symbol: []const u8, n: i64, d: i64, kind: Kind, prefix: bool) Unit {
    return .{ .symbol = symbol, .quantity = .{ .value = Fraction.init(n, d), .dimension = kind_dimensions[@intFromEnum(kind)] }, .prefix = prefix };
}
const builtins = [_]Unit{
    builtin("m", 1, 1, .length, true), builtin("g", 1, 1000, .mass, true),
    builtin("s", 1, 1, .time, true), builtin("A", 1, 1, .current, true), builtin("K", 1, 1, .temperature, true),
    builtin("mol", 1, 1, .amount, true), builtin("cd", 1, 1, .luminous_intensity, true),
    builtin("N", 1, 1, .force, true), builtin("J", 1, 1, .energy, true), builtin("W", 1, 1, .power, true),
    builtin("Pa", 1, 1, .pressure, true), builtin("Hz", 1, 1, .frequency, true), builtin("C", 1, 1, .charge, true),
    builtin("V", 1, 1, .voltage, true), builtin("ohm", 1, 1, .resistance, true),
    builtin("S", 1, 1, .conductance, true), builtin("F", 1, 1, .capacitance, true),
    builtin("Wb", 1, 1, .magnetic_flux, true), builtin("T", 1, 1, .flux_density, true),
    builtin("H", 1, 1, .inductance, true), builtin("lx", 1, 1, .illuminance, true),
    builtin("kat", 1, 1, .catalytic_activity, true), builtin("L", 1, 1000, .volume, true),
    builtin("t", 1000, 1, .mass, false), builtin("min", 60, 1, .time, false),
    builtin("h", 3600, 1, .time, false), builtin("day", 86400, 1, .time, false),
    builtin("in", 127, 5000, .length, false), builtin("ft", 381, 1250, .length, false),
    builtin("yd", 1143, 1250, .length, false), builtin("mi", 201168, 125, .length, false),
    builtin("nmi", 1852, 1, .length, false), builtin("ha", 10000, 1, .area, false),
    builtin("kn", 463, 900, .speed, false), builtin("bar", 100000, 1, .pressure, true),
    builtin("atm", 101325, 1, .pressure, false), builtin("Torr", 20265, 152, .pressure, false),
    builtin("cal", 523, 125, .energy, true), builtin("Wh", 3600, 1, .energy, true),
    builtin("Ah", 3600, 1, .charge, true), builtin("dC", 1, 1, .temperature, false), builtin("dF", 5, 9, .temperature, false),
};
const Prefix = struct { symbol: []const u8, factor: Fraction };
const prefixes = [_]Prefix{
    .{ .symbol = "G", .factor = Fraction.whole(1_000_000_000) }, .{ .symbol = "M", .factor = Fraction.whole(1_000_000) },
    .{ .symbol = "k", .factor = Fraction.whole(1000) }, .{ .symbol = "h", .factor = Fraction.whole(100) },
    .{ .symbol = "da", .factor = Fraction.whole(10) }, .{ .symbol = "d", .factor = Fraction.init(1, 10) },
    .{ .symbol = "c", .factor = Fraction.init(1, 100) }, .{ .symbol = "m", .factor = Fraction.init(1, 1000) },
    .{ .symbol = "u", .factor = Fraction.init(1, 1_000_000) }, .{ .symbol = "n", .factor = Fraction.init(1, 1_000_000_000) },
};

const Calculator = struct {
    storage: Allocator,
    units: [72]Unit = undefined,
    unit_count: usize = builtins.len,
    variables: [50]Variable = undefined,
    variable_count: usize = 0,

    fn init(storage: Allocator) Calculator {
        var result: Calculator = .{ .storage = storage };
        @memcpy(result.units[0..builtins.len], &builtins);
        return result;
    }
    fn resolve(calculator: *const Calculator, name: []const u8) ?Quantity {
        for (calculator.units[0..calculator.unit_count]) |unit| if (equal(unit.symbol, name)) return unit.quantity;
        for (prefixes) |prefix| {
            if (!std.mem.startsWith(u8, name, prefix.symbol)) continue;
            const suffix = name[prefix.symbol.len..];
            for (builtins) |unit| {
                if (unit.prefix and equal(unit.symbol, suffix))
                    return .{ .value = prefix.factor.mul(unit.quantity.value), .dimension = unit.quantity.dimension };
            }
        }
        return null;
    }
    fn variableIndex(calculator: *const Calculator, name: []const u8) ?usize {
        for (calculator.variables[0..calculator.variable_count], 0..) |variable, i| if (equal(variable.name, name)) return i;
        return null;
    }
    fn unitLess(calculator: *const Calculator, left: usize, right: usize) bool {
        const a = calculator.units[left];
        const b = calculator.units[right];
        return if (a.quantity.value.eq(b.quantity.value)) std.mem.order(u8, a.symbol, b.symbol) == .lt else a.quantity.value.less(b.quantity.value);
    }
    fn variableLess(calculator: *const Calculator, left: usize, right: usize) bool {
        return std.mem.order(u8, calculator.variables[left].name, calculator.variables[right].name) == .lt;
    }
};

const TokenKind = enum { number, identifier, unit, symbol, invalid, end };
const Token = struct { kind: TokenKind, text: []const u8, position: usize };
const UnitTerm = struct { op: u8, node: *const UnitNode };
const UnitNode = union(enum) {
    name: []const u8,
    number: i64,
    power: struct { atom: *const UnitNode, exponent: []const u8 },
    product: []const UnitTerm,
};
const QuantityNode = union(enum) {
    literal: struct { number: []const u8, unit: ?[]const u8 = null },
    variable: []const u8,
    negative: *const QuantityNode,
    power: struct { atom: *const QuantityNode, exponent: []const u8 },
    binary: struct { op: u8, left: *const QuantityNode, right: *const QuantityNode },
    call: struct { name: []const u8, arguments: []const *const QuantityNode },
};
const Parser = struct {
    session: *Session,
    source: []const u8,
    tokens: [201]Token = undefined,
    length: usize = 0,
    position: usize = 0,

    fn init(session: *Session, source: []const u8, quantity: bool) Parser {
        var parser: Parser = .{ .session = session, .source = source };
        var i: usize = 0;
        while (i < source.len) {
            const start = i;
            const c = source[i];
            i += 1;
            var kind: TokenKind = .invalid;
            if (letter(c)) {
                while (i < source.len and letter(source[i])) i += 1;
                kind = .identifier;
            } else if (digit(c)) {
                while (i < source.len and digit(source[i])) i += 1;
                if (quantity and i + 1 < source.len and source[i] == '.' and digit(source[i + 1])) {
                    i += 2;
                    while (i < source.len and digit(source[i])) i += 1;
                }
                kind = .number;
            } else if (quantity and c == '[') {
                if (std.mem.findScalar(u8, source[i..], ']')) |offset| {
                    if (offset > 0) {
                        i += offset + 1;
                        kind = .unit;
                    }
                }
            } else if (std.mem.findScalar(u8, if (quantity) "+-*/^()," else "*/^()-", c) != null) kind = .symbol;
            parser.tokens[parser.length] = .{ .kind = kind, .text = source[start..i], .position = start + 1 };
            parser.length += 1;
        }
        parser.tokens[parser.length] = .{ .kind = .end, .text = "", .position = source.len + 1 };
        parser.length += 1;
        return parser;
    }
    fn current(parser: *const Parser) Token { return parser.tokens[parser.position]; }
    fn advance(parser: *Parser) Token {
        const token = parser.current();
        parser.position += 1;
        return token;
    }
    fn take(parser: *Parser, text: []const u8) bool {
        if (!equal(parser.current().text, text)) return false;
        parser.position += 1;
        return true;
    }
    fn syntax(parser: *Parser) Error {
        const token = parser.current();
        return if (token.kind == .end) parser.session.fail("SYNTAX {s} AT END", .{parser.source})
            else parser.session.fail("SYNTAX {s} AT {d}", .{ parser.source, token.position });
    }
    fn expect(parser: *Parser, text: []const u8) Error!void { if (!parser.take(text)) return parser.syntax(); }
    fn finish(parser: *Parser) Error!void { if (parser.current().kind != .end) return parser.syntax(); }
    fn exponent(parser: *Parser) Error![]const u8 {
        const start = parser.current().position - 1;
        _ = parser.take("-");
        const token = parser.current();
        if (token.kind != .number or std.mem.findScalar(u8, token.text, '.') != null) return parser.syntax();
        _ = parser.advance();
        return parser.source[start .. token.position - 1 + token.text.len];
    }
    fn unitNode(parser: *Parser, value: UnitNode) Allocator.Error!*const UnitNode {
        const node = try parser.session.gpa.create(UnitNode);
        node.* = value;
        return node;
    }
    fn quantityNode(parser: *Parser, value: QuantityNode) Allocator.Error!*const QuantityNode {
        const node = try parser.session.gpa.create(QuantityNode);
        node.* = value;
        return node;
    }
    fn unitExpression(parser: *Parser) Error!*const UnitNode {
        var terms: std.ArrayList(UnitTerm) = .empty;
        try terms.append(parser.session.gpa, .{ .op = '*', .node = try parser.unitTerm() });
        while (equal(parser.current().text, "*") or equal(parser.current().text, "/")) {
            const op = parser.advance().text[0];
            try terms.append(parser.session.gpa, .{ .op = op, .node = try parser.unitTerm() });
        }
        return parser.unitNode(.{ .product = try terms.toOwnedSlice(parser.session.gpa) });
    }
    fn unitTerm(parser: *Parser) Error!*const UnitNode {
        const token = parser.current();
        var atom: *const UnitNode = undefined;
        if (token.kind == .identifier) {
            _ = parser.advance();
            atom = try parser.unitNode(.{ .name = token.text });
        } else if (token.kind == .number and token.text[0] != '0') {
            _ = parser.advance();
            atom = try parser.unitNode(.{ .number = integer(token.text) });
        } else if (parser.take("(")) {
            atom = try parser.unitExpression();
            try parser.expect(")");
        } else return parser.syntax();
        return if (parser.take("^")) parser.unitNode(.{ .power = .{ .atom = atom, .exponent = try parser.exponent() } }) else atom;
    }
    fn quantityExpression(parser: *Parser) Error!*const QuantityNode {
        var node = try parser.quantityProduct();
        while (equal(parser.current().text, "+") or equal(parser.current().text, "-")) {
            const op = parser.advance().text[0];
            const right = try parser.quantityProduct();
            node = try parser.quantityNode(.{ .binary = .{ .op = op, .left = node, .right = right } });
        }
        return node;
    }
    fn quantityProduct(parser: *Parser) Error!*const QuantityNode {
        var node = try parser.quantityUnary();
        while (equal(parser.current().text, "*") or equal(parser.current().text, "/")) {
            const op = parser.advance().text[0];
            const right = try parser.quantityUnary();
            node = try parser.quantityNode(.{ .binary = .{ .op = op, .left = node, .right = right } });
        }
        return node;
    }
    fn quantityUnary(parser: *Parser) Error!*const QuantityNode {
        if (parser.take("-")) return parser.quantityNode(.{ .negative = try parser.quantityUnary() });
        const atom = try parser.quantityPrimary();
        return if (parser.take("^")) parser.quantityNode(.{ .power = .{ .atom = atom, .exponent = try parser.exponent() } }) else atom;
    }
    fn quantityPrimary(parser: *Parser) Error!*const QuantityNode {
        const token = parser.current();
        if (token.kind == .number) {
            _ = parser.advance();
            const unit_text: ?[]const u8 = if (parser.current().kind == .unit) blk: {
                const unit_token = parser.advance();
                break :blk unit_token.text[1 .. unit_token.text.len - 1];
            } else null;
            return parser.quantityNode(.{ .literal = .{ .number = token.text, .unit = unit_text } });
        }
        if (token.kind == .unit) {
            _ = parser.advance();
            return parser.quantityNode(.{ .literal = .{ .number = "1", .unit = token.text[1 .. token.text.len - 1] } });
        }
        if (token.kind == .identifier) {
            _ = parser.advance();
            if (!parser.take("(")) return parser.quantityNode(.{ .variable = token.text });
            var arguments: std.ArrayList(*const QuantityNode) = .empty;
            try arguments.append(parser.session.gpa, try parser.quantityExpression());
            while (parser.take(",")) try arguments.append(parser.session.gpa, try parser.quantityExpression());
            try parser.expect(")");
            return parser.quantityNode(.{ .call = .{ .name = token.text, .arguments = try arguments.toOwnedSlice(parser.session.gpa) } });
        }
        if (parser.take("(")) {
            const node = try parser.quantityExpression();
            try parser.expect(")");
            return node;
        }
        return parser.syntax();
    }
};

const ParsedUnit = struct { tree: *const UnitNode, quantity: Quantity, names: []const []const u8 };
const Reduced = struct { coefficient: Fraction, exponents: []i64 };
const Function = enum { abs, sqrt, min, max };
const Scale = enum { C, F, K, R };

fn integerRoot(number: i64) i64 {
    var low: i64 = 0;
    var high = number + 1;
    while (high - low > 1) {
        const middle = low + @divTrunc(high - low, 2);
        if (middle <= @divTrunc(number, middle)) low = middle else high = middle;
    }
    return low;
}

const Session = struct {
    gpa: Allocator,
    calculator: *Calculator,
    out: *Writer,
    problem: []const u8 = "",

    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn number(session: *Session, text: []const u8) Error!Fraction {
        const negative = text.len > 0 and text[0] == '-';
        const body = if (negative) text[1..] else text;
        var separator: ?usize = null;
        for (body, 0..) |c, i| {
            if (c == '.' or c == '/') { separator = i; break; }
        }
        const first = if (separator) |i| body[0..i] else body;
        const second = if (separator) |i| body[i + 1 ..] else "1";
        if (!digits(first) or !digits(second)) return session.fail("BAD NUMBER {s}", .{text});
        var n = integer(first);
        var d: i64 = 1;
        if (separator) |i| {
            if (body[i] == '/') {
                d = integer(second);
                if (d == 0) return session.fail("BAD NUMBER {s}", .{text});
            } else {
                for (second) |_| d *= 10;
                n = n * d + integer(second);
            }
        }
        return Fraction.init(if (negative) -n else n, d);
    }
    fn checkExponent(session: *Session, text: []const u8) Error!i64 {
        const value = integer(text);
        if (value < -3 or value == 0 or value > 3) return session.fail("BAD EXPONENT {s}", .{text});
        return value;
    }
    fn checkName(session: *Session, name: []const u8, variable: bool) Error!void {
        if (name.len < 1 or name.len > 12) return session.fail("BAD NAME {s}", .{name});
        for (name) |c| if (!letter(c)) return session.fail("BAD NAME {s}", .{name});
        if (variable and std.meta.stringToEnum(Function, name) != null) return session.fail("BAD NAME {s}", .{name});
    }
    fn match(session: *Session, a: Dimension, b: Dimension) Error!void {
        if (!a.eq(b)) return session.fail("DIMENSION MISMATCH {f} vs {f}", .{ a, b });
    }
    fn simplified(session: *Session, dimension: Dimension) Allocator.Error![]const u8 {
        const calculator = session.calculator;
        for (calculator.units[0..calculator.unit_count]) |unit|
            if (unit.quantity.dimension.eq(dimension) and unit.quantity.value.eq(Fraction.one)) return unit.symbol;
        return std.fmt.allocPrint(session.gpa, "{f}", .{dimension});
    }
    fn quantityNotation(session: *Session, quantity: Quantity) Allocator.Error!Notation {
        return notation(quantity.value, try session.simplified(quantity.dimension));
    }
    fn validateUnit(session: *Session, node: *const UnitNode, names: *std.ArrayList([]const u8)) Error!void {
        switch (node.*) {
            .number => {},
            .name => |name| {
                if (session.calculator.resolve(name) == null) return session.fail("UNKNOWN UNIT {s}", .{name});
                for (names.items) |existing| if (equal(name, existing)) return;
                try names.append(session.gpa, name);
            },
            .power => |power| { try session.validateUnit(power.atom, names); _ = try session.checkExponent(power.exponent); },
            .product => |terms| for (terms) |term| try session.validateUnit(term.node, names),
        }
    }
    fn unitValue(session: *Session, node: *const UnitNode) Quantity {
        switch (node.*) {
            .number => |value| return .{ .value = Fraction.whole(value), .dimension = Dimension.zero },
            .name => |name| return session.calculator.resolve(name).?,
            .power => |power| {
                const atom = session.unitValue(power.atom);
                const exponent = integer(power.exponent);
                return .{ .value = atom.value.power(exponent), .dimension = atom.dimension.scale(exponent) };
            },
            .product => |terms| {
                var result: Quantity = .{ .value = Fraction.one, .dimension = Dimension.zero };
                for (terms) |term| {
                    const value = session.unitValue(term.node);
                    result = if (term.op == '*') .{ .value = result.value.mul(value.value), .dimension = result.dimension.add(value.dimension) }
                        else .{ .value = result.value.div(value.value), .dimension = result.dimension.sub(value.dimension) };
                }
                return result;
            },
        }
    }
    fn parseUnit(session: *Session, text: []const u8) Error!ParsedUnit {
        var parser = Parser.init(session, text, false);
        const tree = try parser.unitExpression();
        try parser.finish();
        var names: std.ArrayList([]const u8) = .empty;
        try session.validateUnit(tree, &names);
        return .{ .tree = tree, .quantity = session.unitValue(tree), .names = names.items };
    }
    fn reduce(session: *Session, node: *const UnitNode, names: []const []const u8) Allocator.Error!Reduced {
        switch (node.*) {
            .power => |power| {
                var result = try session.reduce(power.atom, names);
                const exponent = integer(power.exponent);
                result.coefficient = result.coefficient.power(exponent);
                for (result.exponents) |*value| value.* *= exponent;
                return result;
            },
            else => {},
        }
        const exponents = try session.gpa.alloc(i64, names.len);
        @memset(exponents, 0);
        var result: Reduced = .{ .coefficient = Fraction.one, .exponents = exponents };
        switch (node.*) {
            .name => |name| {
                for (names, 0..) |existing, i| {
                    if (equal(existing, name)) { exponents[i] = 1; break; }
                }
            },
            .number => |value| result.coefficient = Fraction.whole(value),
            .product => |terms| {
                for (terms) |term| {
                    const value = try session.reduce(term.node, names);
                    result.coefficient = if (term.op == '*') result.coefficient.mul(value.coefficient) else result.coefficient.div(value.coefficient);
                    for (result.exponents, value.exponents) |*target, source| target.* += if (term.op == '*') source else -source;
                }
            },
            .power => unreachable,
        }
        return result;
    }
    fn reducedText(session: *Session, parsed: ParsedUnit) Error![]const u8 {
        const reduced = try session.reduce(parsed.tree, parsed.names);
        var output: Writer.Allocating = .init(session.gpa);
        defer output.deinit();
        var first = true;
        if (!reduced.coefficient.eq(Fraction.one)) { try output.writer.print("{f}", .{reduced.coefficient}); first = false; }
        for (parsed.names, reduced.exponents) |name, exponent| {
            if (exponent == 0) continue;
            if (!first) try output.writer.writeByte(' ');
            first = false;
            try output.writer.writeAll(name);
            if (exponent != 1) try output.writer.print("^{d}", .{exponent});
        }
        if (first) try output.writer.writeByte('1');
        return output.toOwnedSlice();
    }
    fn evaluate(session: *Session, node: *const QuantityNode) Error!Quantity {
        switch (node.*) {
            .literal => |literal| {
                if (literal.unit) |text| {
                    const unit = (try session.parseUnit(text)).quantity;
                    return .{ .value = (try session.number(literal.number)).mul(unit.value), .dimension = unit.dimension };
                }
                return .{ .value = try session.number(literal.number), .dimension = Dimension.zero };
            },
            .variable => |name| {
                const index = session.calculator.variableIndex(name) orelse return session.fail("UNKNOWN VARIABLE {s}", .{name});
                return session.calculator.variables[index].quantity;
            },
            .negative => |operand| {
                const value = try session.evaluate(operand);
                return .{ .value = value.value.neg(), .dimension = value.dimension };
            },
            .power => |power| {
                const value = try session.evaluate(power.atom);
                const exponent = try session.checkExponent(power.exponent);
                if (value.value.n == 0 and exponent < 0) return session.fail("DIVISION BY ZERO", .{});
                return .{ .value = value.value.power(exponent), .dimension = value.dimension.scale(exponent) };
            },
            .binary => |binary| {
                const a = try session.evaluate(binary.left);
                const b = try session.evaluate(binary.right);
                if (binary.op == '+' or binary.op == '-') {
                    try session.match(a.dimension, b.dimension);
                    return .{ .value = if (binary.op == '+') a.value.add(b.value) else a.value.sub(b.value), .dimension = a.dimension };
                }
                if (binary.op == '*') return .{ .value = a.value.mul(b.value), .dimension = a.dimension.add(b.dimension) };
                if (b.value.n == 0) return session.fail("DIVISION BY ZERO", .{});
                return .{ .value = a.value.div(b.value), .dimension = a.dimension.sub(b.dimension) };
            },
            .call => |call| {
                const function = std.meta.stringToEnum(Function, call.name) orelse return session.fail("UNKNOWN FUNCTION {s}", .{call.name});
                const count: usize = if (function == .abs or function == .sqrt) 1 else 2;
                if (call.arguments.len != count) return session.fail("BAD ARGUMENTS {s}", .{call.name});
                const a = try session.evaluate(call.arguments[0]);
                if (function == .abs) return .{ .value = a.value.abs(), .dimension = a.dimension };
                if (function == .sqrt) {
                    if (a.value.n < 0) return session.fail("NEGATIVE ROOT", .{});
                    if (!a.dimension.even()) return session.fail("ODD DIMENSION {f}", .{a.dimension});
                    const p = integerRoot(a.value.n);
                    const q = integerRoot(a.value.d);
                    if (p * p != a.value.n or q * q != a.value.d) return session.fail("NOT EXACT", .{});
                    return .{ .value = Fraction.init(p, q), .dimension = a.dimension.half() };
                }
                const b = try session.evaluate(call.arguments[1]);
                try session.match(a.dimension, b.dimension);
                return if (function == .min) (if (b.value.less(a.value)) b else a) else (if (a.value.less(b.value)) b else a);
            },
        }
    }
    fn parseQuantity(session: *Session, text: []const u8) Error!Quantity {
        var parser = Parser.init(session, text, true);
        const tree = try parser.quantityExpression();
        try parser.finish();
        return session.evaluate(tree);
    }
    fn matching(session: *Session, dimension: Dimension) Allocator.Error![]usize {
        var selected: std.ArrayList(usize) = .empty;
        const calculator: *const Calculator = session.calculator;
        for (calculator.units[0..calculator.unit_count], 0..) |unit, i|
            if (unit.quantity.dimension.eq(dimension)) try selected.append(session.gpa, i);
        std.sort.heap(usize, selected.items, calculator, Calculator.unitLess);
        return selected.items;
    }

    fn execute(session: *Session, text: []const u8) Error!void {
        var words: std.ArrayList([]const u8) = .empty;
        var tokens = std.mem.splitScalar(u8, text, ' ');
        while (tokens.next()) |word| try words.append(session.gpa, word);
        const w = words.items;
        const command = std.meta.stringToEnum(Command, w[0]) orelse return session.fail("UNKNOWN COMMAND {s}", .{w[0]});
        const calculator = session.calculator;
        const out = session.out;
        switch (command) {
            .DEFINE => {
                try session.checkName(w[1], false);
                const value = try session.number(w[3]);
                const unit = (try session.parseUnit(w[4])).quantity;
                if (std.meta.stringToEnum(Kind, w[1]) != null or calculator.resolve(w[1]) != null)
                    return session.fail("NAME TAKEN {s}", .{w[1]});
                if (value.n <= 0) return session.fail("NOT POSITIVE {s}", .{w[3]});
                const defined: Quantity = .{ .value = value.mul(unit.value), .dimension = unit.dimension };
                const name = try calculator.storage.dupe(u8, w[1]);
                const expression = try calculator.storage.dupe(u8, w[4]);
                calculator.units[calculator.unit_count] = .{
                    .symbol = name, .quantity = defined, .prefix = false,
                    .definition = .{ .value = value, .expression = expression },
                };
                calculator.unit_count += 1;
                try line(out, "DEFINE {s} factor={f} dim={f} kind={s}", .{ name, defined.value, defined.dimension, kindName(defined.dimension) });
            },
            .UNDEF => {
                var found: ?usize = null;
                for (calculator.units[0..calculator.unit_count], 0..) |unit, i| {
                    if (equal(unit.symbol, w[1])) { found = i; break; }
                }
                const index = found orelse return session.fail("NOT DEFINED {s}", .{w[1]});
                if (index < builtins.len) return session.fail("BUILTIN UNIT {s}", .{w[1]});
                for (index + 1 .. calculator.unit_count) |i| calculator.units[i - 1] = calculator.units[i];
                calculator.unit_count -= 1;
                try line(out, "UNDEF {s}", .{w[1]});
            },
            .DEFS => {
                try line(out, "DEFS count={d}", .{calculator.unit_count - builtins.len});
                for (calculator.units[builtins.len..calculator.unit_count]) |unit| {
                    const definition = unit.definition.?;
                    try line(out, "DEF {s} = {f} {s} factor={f} dim={f}", .{ unit.symbol, definition.value, definition.expression, unit.quantity.value, unit.quantity.dimension });
                }
            },
            .CONVERT, .INVERT => {
                const value = try session.number(w[1]);
                const a = (try session.parseUnit(w[2])).quantity;
                const b = (try session.parseUnit(w[4])).quantity;
                if (command == .CONVERT) try session.match(a.dimension, b.dimension) else {
                    if (a.dimension.eq(Dimension.zero) or !a.dimension.add(b.dimension).eq(Dimension.zero))
                        return session.fail("NOT RECIPROCAL {f} vs {f}", .{ a.dimension, b.dimension });
                    if (value.n == 0) return session.fail("DIVISION BY ZERO", .{});
                }
                const result = if (command == .CONVERT) value.mul(a.value).div(b.value) else Fraction.one.div(value.mul(a.value)).div(b.value);
                try line(out, "{s} {f} {s} = {f}", .{ w[0], value, w[2], notation(result, w[4]) });
            },
            .DIM, .REDUCE, .SIMPLIFY => {
                const parsed = try session.parseUnit(w[1]);
                const unit = parsed.quantity;
                if (command == .DIM) try line(out, "DIM {s} = {f} factor={f} kind={s}", .{ w[1], unit.dimension, unit.value, kindName(unit.dimension) })
                else if (command == .REDUCE) try line(out, "REDUCE {s} = {s}", .{ w[1], try session.reducedText(parsed) })
                else try line(out, "SIMPLIFY {s} = {f}", .{ w[1], try session.quantityNotation(unit) });
            },
            .ADD, .SUB, .MUL, .DIV, .COMPARE => {
                const x = try session.number(w[1]);
                const a = (try session.parseUnit(w[2])).quantity;
                const y = try session.number(w[3]);
                const b = (try session.parseUnit(w[4])).quantity;
                const target: ?Quantity = if (w.len == 7) (try session.parseUnit(w[6])).quantity else null;
                if (command == .COMPARE) {
                    try session.match(a.dimension, b.dimension);
                    const left = x.mul(a.value);
                    const right = y.mul(b.value);
                    const relation: u8 = if (left.less(right)) '<' else if (right.less(left)) '>' else '=';
                    try out.print("COMPARE {f} {s} {c} {f} {s} ratio=", .{ x, w[2], relation, y, w[4] });
                    if (right.n == 0) try line(out, "undefined", .{}) else try line(out, "{f}", .{left.div(right)});
                    return;
                }
                const op: u8 = switch (command) { .ADD => '+', .SUB => '-', .MUL => '*', else => '/' };
                if (command == .ADD or command == .SUB) {
                    try session.match(a.dimension, b.dimension);
                    if (target) |destination| try session.match(a.dimension, destination.dimension);
                    const left = x.mul(a.value);
                    const right = y.mul(b.value);
                    const result = (if (command == .ADD) left.add(right) else left.sub(right)).div(if (target) |destination| destination.value else a.value);
                    try line(out, "{s} {f} {s} {c} {f} {s} = {f}", .{ w[0], x, w[2], op, y, w[4], notation(result, if (target != null) w[6] else w[2]) });
                    return;
                }
                const dimension = if (command == .MUL) a.dimension.add(b.dimension) else a.dimension.sub(b.dimension);
                if (command == .DIV and y.n == 0) return session.fail("DIVISION BY ZERO", .{});
                if (target) |destination| try session.match(dimension, destination.dimension);
                const product = if (command == .MUL) x.mul(y) else x.div(y);
                const first = x.mul(a.value);
                const second = y.mul(b.value);
                const coherent = if (command == .MUL) first.mul(second) else first.div(second);
                try out.print("{s} {f} {s} {c} {f} {s} = ", .{ w[0], x, w[2], op, y, w[4] });
                if (target) |destination| try line(out, "{f}", .{notation(coherent.div(destination.value), w[6])}) else {
                    try out.print("{f} {s}{c}", .{ product, w[2], op });
                    if (command == .DIV and (std.mem.findScalar(u8, w[4], '*') != null or std.mem.findScalar(u8, w[4], '/') != null))
                        try out.print("({s})", .{w[4]}) else try out.writeAll(w[4]);
                    try line(out, " = {f}", .{notation(coherent, try session.simplified(dimension))});
                }
            },
            .TEMP => {
                const value = try session.number(w[1]);
                const source = std.meta.stringToEnum(Scale, w[2]) orelse return session.fail("UNKNOWN SCALE {s}", .{w[2]});
                const target = std.meta.stringToEnum(Scale, w[4]) orelse return session.fail("UNKNOWN SCALE {s}", .{w[4]});
                const kelvin = switch (source) {
                    .C => value.add(Fraction.init(5463, 20)),
                    .F => value.add(Fraction.init(45967, 100)).mul(Fraction.whole(5)).div(Fraction.whole(9)),
                    .R => value.mul(Fraction.whole(5)).div(Fraction.whole(9)), .K => value,
                };
                if (kelvin.n < 0) return session.fail("BELOW ABSOLUTE ZERO", .{});
                const result = switch (target) {
                    .C => kelvin.sub(Fraction.init(5463, 20)),
                    .F => kelvin.mul(Fraction.whole(9)).div(Fraction.whole(5)).sub(Fraction.init(45967, 100)),
                    .R => kelvin.mul(Fraction.whole(9)).div(Fraction.whole(5)), .K => kelvin,
                };
                try line(out, "TEMP {f} {s} = {f}", .{ value, w[2], notation(result, w[4]) });
            },
            .LIST => {
                const dimension = if (std.meta.stringToEnum(Kind, w[1])) |kind| kind_dimensions[@intFromEnum(kind)] else (try session.parseUnit(w[1])).quantity.dimension;
                const selected = try session.matching(dimension);
                try line(out, "LIST {s} dim={f} kind={s} count={d}", .{ w[1], dimension, kindName(dimension), selected.len });
                for (selected) |i| {
                    const unit = calculator.units[i];
                    try line(out, "UNIT {s} factor={f} origin={s} prefix={s}", .{
                        unit.symbol, unit.quantity.value, @as([]const u8, if (unit.definition == null) "builtin" else "user"),
                        @as([]const u8, if (unit.prefix) "yes" else "no"),
                    });
                }
            },
            .TABLE, .AUTO, .SPLIT => {
                const value = try session.number(w[1]);
                const unit = (try session.parseUnit(w[2])).quantity;
                if (command == .TABLE) {
                    const selected = try session.matching(unit.dimension);
                    try line(out, "TABLE {f} {s} dim={f} count={d}", .{ value, w[2], unit.dimension, selected.len });
                    for (selected) |i| {
                        const row = calculator.units[i];
                        try line(out, "ROW {f}", .{notation(value.mul(unit.value).div(row.quantity.value), row.symbol)});
                    }
                    return;
                }
                if (command == .AUTO) {
                    var basis: ?Unit = null;
                    for (builtins) |candidate| {
                        if (candidate.prefix and candidate.quantity.dimension.eq(unit.dimension)) { basis = candidate; break; }
                    }
                    const reference = basis orelse return session.fail("NO PREFIXABLE UNIT {f}", .{unit.dimension});
                    const scaled = value.mul(unit.value).div(reference.quantity.value);
                    const magnitude = scaled.abs();
                    var exponent: i64 = 0;
                    if (!magnitude.less(Fraction.one)) {
                        while (exponent < 9 and !magnitude.less(Fraction.whole(10).power(exponent + 3))) exponent += 3;
                    } else if (magnitude.n != 0) {
                        while (exponent > -9 and magnitude.less(Fraction.whole(10).power(exponent))) exponent -= 3;
                    }
                    const prefix: []const u8 = switch (exponent) { 9 => "G", 6 => "M", 3 => "k", -3 => "m", -6 => "u", -9 => "n", else => "" };
                    const symbol = try std.fmt.allocPrint(session.gpa, "{s}{s}", .{ prefix, reference.symbol });
                    try line(out, "AUTO {f} {s} = {f}", .{ value, w[2], notation(scaled.div(Fraction.whole(10).power(exponent)), symbol) });
                    return;
                }
                var parts: std.ArrayList([]const u8) = .empty;
                var destinations: std.ArrayList(Quantity) = .empty;
                var part_tokens = std.mem.splitScalar(u8, w[4], ',');
                while (part_tokens.next()) |part| {
                    try parts.append(session.gpa, part);
                    try destinations.append(session.gpa, (try session.parseUnit(part)).quantity);
                }
                if (value.n < 0) return session.fail("NEGATIVE VALUE", .{});
                for (destinations.items) |destination| try session.match(unit.dimension, destination.dimension);
                for (1..destinations.items.len) |i|
                    if (!destinations.items[i].value.less(destinations.items[i - 1].value)) return session.fail("UNIT ORDER", .{});
                var remaining = value.mul(unit.value);
                try out.print("SPLIT {f} {s} = ", .{ value, w[2] });
                for (0..parts.items.len - 1) |i| {
                    const quotient = remaining.div(destinations.items[i].value);
                    const whole = @divTrunc(quotient.n, quotient.d);
                    remaining = remaining.sub(Fraction.whole(whole).mul(destinations.items[i].value));
                    try out.print("{d} {s} ", .{ whole, parts.items[i] });
                }
                const last = parts.items.len - 1;
                try line(out, "{f}", .{notation(remaining.div(destinations.items[last].value), parts.items[last])});
            },
            .LET => {
                try session.checkName(w[1], true);
                const value = try session.parseQuantity(w[3]);
                if (calculator.variableIndex(w[1])) |index| calculator.variables[index].quantity = value else {
                    const name = try calculator.storage.dupe(u8, w[1]);
                    calculator.variables[calculator.variable_count] = .{ .name = name, .quantity = value };
                    calculator.variable_count += 1;
                }
                try line(out, "LET {s} = {f}", .{ w[1], try session.quantityNotation(value) });
            },
            .EVAL => {
                const value = try session.parseQuantity(w[1]);
                if (w.len == 4) {
                    const unit = (try session.parseUnit(w[3])).quantity;
                    try session.match(value.dimension, unit.dimension);
                    try line(out, "EVAL {s} = {f}", .{ w[1], notation(value.value.div(unit.value), w[3]) });
                } else try line(out, "EVAL {s} = {f}", .{ w[1], try session.quantityNotation(value) });
            },
            .VARS => {
                var indices: [50]usize = undefined;
                for (indices[0..calculator.variable_count], 0..) |*index, i| index.* = i;
                std.sort.heap(usize, indices[0..calculator.variable_count], @as(*const Calculator, calculator), Calculator.variableLess);
                try line(out, "VARS count={d}", .{calculator.variable_count});
                for (indices[0..calculator.variable_count]) |index| {
                    const variable = calculator.variables[index];
                    try line(out, "VAR {s} = {f}", .{ variable.name, try session.quantityNotation(variable.quantity) });
                }
            },
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    var calculator = Calculator.init(storage.allocator());
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count: usize = @intCast(integer(try readLine(storage.allocator(), &input.interface)));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = gpa, .calculator = &calculator, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
