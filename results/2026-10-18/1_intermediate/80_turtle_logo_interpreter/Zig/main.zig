const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
var failureLine: usize = 0;
var failureReason: Text = "";
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn oneOf(value: Text, list: []const Text) bool {
    for (list) |item| if (equal(value, item)) return true;
    return false;
}
fn u(value: Int) usize {
    return @intCast(value);
}
fn si(value: usize) Int {
    return @intCast(value);
}
fn abs(value: Int) Int {
    return if (value < 0) -value else value;
}
const TokenKind = enum { number, variable, quoted, word, symbol };
const Token = struct { text: Text = "", name: Text = "", kind: TokenKind = .symbol, value: Int = 0, line: usize, sign: bool = false };
fn bad(gpa: Allocator, t: Token, comptime format: Text, args: anytype) Error {
    failureLine = t.line;
    failureReason = std.fmt.allocPrint(gpa, format, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        const text = try std.fmt.allocPrint(self.gpa, format, args);
        defer self.gpa.free(text);
        try self.add(text);
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        try self.print(format ++ "\n", args);
    }
    fn deinit(self: *Builder) void {
        self.bytes.deinit(self.gpa);
    }
};
const Primitive = struct { names: Text, canonical: Text, inputs: Text, function: bool = false };
const primitives = [_]Primitive{
    .{ .names = "FD FORWARD", .canonical = "FD", .inputs = "E" },                      .{ .names = "BK BACK", .canonical = "BK", .inputs = "E" },
    .{ .names = "RT RIGHT", .canonical = "RT", .inputs = "E" },                        .{ .names = "LT LEFT", .canonical = "LT", .inputs = "E" },
    .{ .names = "SETH SETHEADING", .canonical = "SETH", .inputs = "E" },               .{ .names = "PU PENUP", .canonical = "PU", .inputs = "" },
    .{ .names = "PD PENDOWN", .canonical = "PD", .inputs = "" },                       .{ .names = "PE PENERASE", .canonical = "PE", .inputs = "" },
    .{ .names = "SETPEN", .canonical = "SETPEN", .inputs = "E" },                      .{ .names = "SETXY", .canonical = "SETXY", .inputs = "EE" },
    .{ .names = "SETX", .canonical = "SETX", .inputs = "E" },                          .{ .names = "SETY", .canonical = "SETY", .inputs = "E" },
    .{ .names = "HOME", .canonical = "HOME", .inputs = "" },                           .{ .names = "CS CLEARSCREEN", .canonical = "CS", .inputs = "" },
    .{ .names = "CLEAN", .canonical = "CLEAN", .inputs = "" },                         .{ .names = "FILL", .canonical = "FILL", .inputs = "" },
    .{ .names = "LABEL", .canonical = "LABEL", .inputs = "P" },                        .{ .names = "SNAPSHOT", .canonical = "SNAPSHOT", .inputs = "" },
    .{ .names = "REPEAT", .canonical = "REPEAT", .inputs = "EL" },                     .{ .names = "FOR", .canonical = "FOR", .inputs = "QEEL" },
    .{ .names = "WHILE", .canonical = "WHILE", .inputs = "EL" },                       .{ .names = "IF", .canonical = "IF", .inputs = "EL" },
    .{ .names = "IFELSE", .canonical = "IFELSE", .inputs = "ELL" },                    .{ .names = "TEST", .canonical = "TEST", .inputs = "E" },
    .{ .names = "IFTRUE IFT", .canonical = "IFTRUE", .inputs = "L" },                  .{ .names = "IFFALSE IFF", .canonical = "IFFALSE", .inputs = "L" },
    .{ .names = "STOP", .canonical = "STOP", .inputs = "" },                           .{ .names = "OUTPUT OP", .canonical = "OUTPUT", .inputs = "E" },
    .{ .names = "MAKE", .canonical = "MAKE", .inputs = "QE" },                         .{ .names = "LOCAL", .canonical = "LOCAL", .inputs = "Q" },
    .{ .names = "LOCALMAKE", .canonical = "LOCALMAKE", .inputs = "QE" },               .{ .names = "TRACE", .canonical = "TRACE", .inputs = "Q" },
    .{ .names = "UNTRACE", .canonical = "UNTRACE", .inputs = "Q" },                    .{ .names = "SEED", .canonical = "SEED", .inputs = "E" },
    .{ .names = "PRINT PR", .canonical = "PRINT", .inputs = "P" },                     .{ .names = "XCOR", .canonical = "XCOR", .inputs = "", .function = true },
    .{ .names = "YCOR", .canonical = "YCOR", .inputs = "", .function = true },         .{ .names = "HEADING", .canonical = "HEADING", .inputs = "", .function = true },
    .{ .names = "REPCOUNT", .canonical = "REPCOUNT", .inputs = "", .function = true }, .{ .names = "RANDOM", .canonical = "RANDOM", .inputs = "E", .function = true },
    .{ .names = "ABS", .canonical = "ABS", .inputs = "E", .function = true },          .{ .names = "NOT", .canonical = "NOT", .inputs = "E", .function = true },
    .{ .names = "AND", .canonical = "AND", .inputs = "EE", .function = true },         .{ .names = "OR", .canonical = "OR", .inputs = "EE", .function = true },
    .{ .names = "MAX", .canonical = "MAX", .inputs = "EE", .function = true },         .{ .names = "MIN", .canonical = "MIN", .inputs = "EE", .function = true },
    .{ .names = "TO", .canonical = "TO", .inputs = "" },                               .{ .names = "END", .canonical = "END", .inputs = "" },
    .{ .names = "MOD", .canonical = "MOD", .inputs = "" },
};
fn findPrimitive(name: Text) ?Primitive {
    for (primitives) |item| {
        var iterator = std.mem.tokenizeScalar(u8, item.names, ' ');
        while (iterator.next()) |alias| if (equal(name, alias)) return item;
    }
    return null;
}
fn isName(text: Text) bool {
    if (text.len == 0 or text[0] < 'A' or text[0] > 'Z') return false;
    for (text) |c| if (!(c >= 'A' and c <= 'Z' or std.ascii.isDigit(c) or c == '_')) return false;
    return true;
}
fn numeric(text: Text) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
const SourceLine = struct { text: Text, number: usize };
fn lex(gpa: Allocator, line: SourceLine) Error![]Token {
    const end = std.mem.findScalar(u8, line.text, ';') orelse line.text.len;
    const text = try gpa.dupe(u8, line.text[0..end]);
    for (text) |*c| c.* = std.ascii.toUpper(c.*);
    var result: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == ' ') {
            i += 1;
            continue;
        }
        const start = i;
        var t: Token = .{ .line = line.number };
        const c = text[i];
        if (std.mem.findScalar(u8, "[]()+*/=", c) != null) {
            i += 1;
        } else if (c == '<' or c == '>') {
            i += 1;
            if (i < text.len and (text[i] == '=' or c == '<' and text[i] == '>')) i += 1;
        } else if (c == '-') {
            t.sign = (i == 0 or std.mem.findScalar(u8, " [(", text[i - 1]) != null) and i + 1 < text.len and text[i + 1] != ' ';
            i += 1;
        } else {
            while (i < text.len and std.mem.findScalar(u8, " []()+-*/=<>", text[i]) == null) i += 1;
            const word = text[start..i];
            if (numeric(word)) {
                t.kind = .number;
                t.value = std.fmt.parseInt(Int, word, 10) catch unreachable;
            } else if (word[0] == ':' and isName(word[1..])) {
                t.kind = .variable;
                t.name = word[1..];
            } else if (word[0] == '"' and isName(word[1..])) {
                t.kind = .quoted;
                t.name = word[1..];
            } else if (isName(word)) {
                t.kind = .word;
                t.name = word;
            } else return bad(gpa, t, "bad token '{s}'", .{word});
        }
        t.text = text[start..i];
        try result.append(gpa, t);
    }
    return result.items;
}
const ExpressionKind = enum { number, variable, unary, binary, function, procedure };
const Expression = struct { kind: ExpressionKind, token: Token, args: []const *Expression = &.{} };
const Input = union(enum) { expression: *Expression, quoted: Token, list: []const *Command };
const Command = struct { token: Token, kind: Text, inputs: []const Input = &.{} };
const Procedure = struct { name: Text, line: usize, parameters: []const Text, tokens: std.ArrayList(Token) = .empty, body: []const *Command = &.{} };
const ProcedureMap = std.StringHashMapUnmanaged(*Procedure);
const Parser = struct {
    gpa: Allocator,
    tokens: []const Token,
    procedures: ProcedureMap,
    inside: bool,
    position: usize = 0,
    fn peek(self: *Parser) ?Token {
        return if (self.position < self.tokens.len) self.tokens[self.position] else null;
    }
    fn take(self: *Parser) Token {
        const t = self.tokens[self.position];
        self.position += 1;
        return t;
    }
    fn unknown(self: *Parser, t: Token) bool {
        return t.kind == .word and findPrimitive(t.text) == null and !self.procedures.contains(t.text);
    }
    fn check(self: *Parser, owner: Token) Error!Token {
        const t = self.peek() orelse return bad(self.gpa, owner, "not enough inputs to {s}", .{owner.text});
        if (equal(t.text, "]") or equal(t.text, ")")) return bad(self.gpa, owner, "not enough inputs to {s}", .{owner.text});
        if (self.unknown(t)) return bad(self.gpa, t, "I don't know how to {s}", .{t.text});
        return t;
    }
    fn input(self: *Parser, kind: u8, owner: Token) Error!Input {
        const t = try self.check(owner);
        if (kind == 'L') {
            if (!equal(t.text, "[")) return bad(self.gpa, t, "{s} doesn't like {s} as input", .{ owner.text, t.text });
            const opening = self.take();
            var commands: std.ArrayList(*Command) = .empty;
            while (true) {
                const next = self.peek() orelse return bad(self.gpa, opening, "missing ]", .{});
                if (equal(next.text, "]")) {
                    _ = self.take();
                    break;
                }
                try commands.append(self.gpa, try self.command());
            }
            return .{ .list = commands.items };
        }
        if (kind == 'Q' or kind == 'P' and t.kind == .quoted) {
            if (t.kind != .quoted) return bad(self.gpa, t, "{s} doesn't like {s} as input", .{ owner.text, t.text });
            return .{ .quoted = self.take() };
        }
        return .{ .expression = try self.comparison(owner) };
    }
    fn node(self: *Parser, kind: ExpressionKind, t: Token, args: []const *Expression) Error!*Expression {
        const expression = try self.gpa.create(Expression);
        expression.* = .{ .kind = kind, .token = t, .args = args };
        return expression;
    }
    fn binary(self: *Parser, t: Token, a: *Expression, b: *Expression) Error!*Expression {
        const args = try self.gpa.alloc(*Expression, 2);
        args[0] = a;
        args[1] = b;
        return self.node(.binary, t, args);
    }
    fn term(self: *Parser, owner: Token) Error!*Expression {
        const t = try self.check(owner);
        _ = self.take();
        if (t.kind == .number) return self.node(.number, t, &.{});
        if (t.kind == .variable) return self.node(.variable, t, &.{});
        if (equal(t.text, "-")) {
            const args = try self.gpa.alloc(*Expression, 1);
            args[0] = try self.term(t);
            return self.node(.unary, t, args);
        }
        if (equal(t.text, "(")) {
            const value = try self.comparison(t);
            const next = self.peek();
            if (next == null or !equal(next.?.text, ")")) return bad(self.gpa, t, "missing )", .{});
            _ = self.take();
            return value;
        }
        var count: usize = 0;
        var kind: ExpressionKind = undefined;
        if (findPrimitive(t.text)) |primitive| {
            if (!primitive.function) return bad(self.gpa, t, "{s} doesn't like {s} as input", .{ owner.text, t.text });
            kind = .function;
            count = primitive.inputs.len;
        } else if (t.kind == .word and self.procedures.contains(t.text)) {
            kind = .procedure;
            count = self.procedures.get(t.text).?.parameters.len;
        } else return bad(self.gpa, t, "{s} doesn't like {s} as input", .{ owner.text, t.text });
        const args = try self.gpa.alloc(*Expression, count);
        for (args) |*arg| arg.* = (try self.input('E', t)).expression;
        return self.node(kind, t, args);
    }
    fn product(self: *Parser, owner: Token) Error!*Expression {
        var result = try self.term(owner);
        while (self.peek()) |t| {
            if (!oneOf(t.text, &.{ "*", "/", "MOD" })) break;
            _ = self.take();
            result = try self.binary(t, result, try self.term(t));
        }
        return result;
    }
    fn sum(self: *Parser, owner: Token) Error!*Expression {
        var result = try self.product(owner);
        while (self.peek()) |t| {
            if (!(equal(t.text, "+") or equal(t.text, "-") and !t.sign)) break;
            _ = self.take();
            result = try self.binary(t, result, try self.product(t));
        }
        return result;
    }
    fn comparison(self: *Parser, owner: Token) Error!*Expression {
        var result = try self.sum(owner);
        while (self.peek()) |t| {
            if (!oneOf(t.text, &.{ "=", "<>", "<", ">", "<=", ">=" })) break;
            _ = self.take();
            result = try self.binary(t, result, try self.sum(t));
        }
        return result;
    }
    fn command(self: *Parser) Error!*Command {
        const t = self.take();
        if (equal(t.text, "]")) return bad(self.gpa, t, "unexpected ]", .{});
        if (equal(t.text, "(")) {
            if (self.peek()) |next| {
                if (next.kind == .word and oneOf(next.text, &.{ "PRINT", "PR" })) {
                    const owner = self.take();
                    var inputs: std.ArrayList(Input) = .empty;
                    while (true) {
                        const nextToken = self.peek() orelse return bad(self.gpa, t, "missing )", .{});
                        if (equal(nextToken.text, "]")) return bad(self.gpa, t, "missing )", .{});
                        if (equal(nextToken.text, ")")) {
                            _ = self.take();
                            break;
                        }
                        try inputs.append(self.gpa, try self.input('P', owner));
                    }
                    const result = try self.gpa.create(Command);
                    result.* = .{ .token = owner, .kind = "multiple", .inputs = inputs.items };
                    return result;
                }
            }
        }
        if (t.kind == .word and oneOf(t.text, &.{ "TO", "END" })) return bad(self.gpa, t, "misplaced {s}", .{t.text});
        var kind: Text = undefined;
        var inputs: std.ArrayList(Input) = .empty;
        if (t.kind == .word and findPrimitive(t.text) != null and !findPrimitive(t.text).?.function and !equal(t.text, "MOD")) {
            const primitive = findPrimitive(t.text).?;
            kind = primitive.canonical;
            if (!self.inside and oneOf(kind, &.{ "STOP", "OUTPUT", "LOCAL", "LOCALMAKE" })) return bad(self.gpa, t, "can only use {s} inside a procedure", .{t.text});
            for (primitive.inputs) |inputKind| try inputs.append(self.gpa, try self.input(inputKind, t));
            if (oneOf(kind, &.{ "TRACE", "UNTRACE" })) {
                const quoted = inputs.items[0].quoted;
                if (!self.procedures.contains(quoted.name)) return bad(self.gpa, quoted, "I don't know how to {s}", .{quoted.name});
            }
        } else if (t.kind == .word and self.procedures.contains(t.text)) {
            kind = "procedure";
            for (0..self.procedures.get(t.text).?.parameters.len) |_| try inputs.append(self.gpa, try self.input('E', t));
        } else if (self.unknown(t)) {
            return bad(self.gpa, t, "I don't know how to {s}", .{t.text});
        } else return bad(self.gpa, t, "you don't say what to do with {s}", .{t.text});
        const result = try self.gpa.create(Command);
        result.* = .{ .token = t, .kind = kind, .inputs = inputs.items };
        return result;
    }
    fn sequence(self: *Parser) Error![]*Command {
        var commands: std.ArrayList(*Command) = .empty;
        while (self.peek() != null) try commands.append(self.gpa, try self.command());
        return commands.items;
    }
};
const Point = struct { x: Int, y: Int };
const Environment = struct { variables: std.StringHashMapUnmanaged(Int) = .empty, test_result: ?bool = null };
const Signal = struct { output: bool = false, value: Int = 0 };
const directions = [8]Point{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = -1 }, .{ .x = 0, .y = -1 }, .{ .x = -1, .y = -1 }, .{ .x = -1, .y = 0 }, .{ .x = -1, .y = 1 } };
fn truth(value: bool) Int {
    return @intFromBool(value);
}
const Bounds = struct { x1: Int, y1: Int, x2: Int, y2: Int };
const Runtime = struct {
    gpa: Allocator,
    errors: Allocator,
    out: *Builder,
    procedures: ProcedureMap,
    environments: std.ArrayList(*Environment) = .empty,
    calls: std.ArrayList(Text) = .empty,
    repetitions: std.ArrayList(Int) = .empty,
    traced: std.StringHashMapUnmanaged(void) = .empty,
    canvas: std.AutoHashMapUnmanaged(Point, u8) = .empty,
    x: Int = 0,
    y: Int = 0,
    heading: Int = 0,
    pen: Text = "DOWN",
    character: u8 = '*',
    random: Int = 1,
    fn deinit(self: *Runtime) void {
        for (self.environments.items) |environment| {
            environment.variables.deinit(self.gpa);
            self.gpa.destroy(environment);
        }
        self.environments.deinit(self.gpa);
        self.calls.deinit(self.gpa);
        self.repetitions.deinit(self.gpa);
        self.traced.deinit(self.gpa);
        self.canvas.deinit(self.gpa);
    }
    fn current(self: *Runtime) *Environment {
        return self.environments.items[self.environments.items.len - 1];
    }
    fn assign(self: *Runtime, name: Text, value: Int) Error!void {
        var i = self.environments.items.len;
        while (i > 1) {
            i -= 1;
            const environment = self.environments.items[i];
            if (environment.variables.contains(name)) {
                try environment.variables.put(self.gpa, name, value);
                return;
            }
        }
        try self.environments.items[0].variables.put(self.gpa, name, value);
    }
    fn evaluate(self: *Runtime, expression: *const Expression) Error!Int {
        const t = expression.token;
        if (expression.kind == .number) return t.value;
        if (expression.kind == .variable) {
            var i = self.environments.items.len;
            while (i > 0) {
                i -= 1;
                if (self.environments.items[i].variables.get(t.name)) |value| return value;
            }
            return bad(self.errors, t, "{s} has no value", .{t.name});
        }
        if (expression.kind == .unary) return -(try self.evaluate(expression.args[0]));
        const values = try self.gpa.alloc(Int, expression.args.len);
        defer self.gpa.free(values);
        for (expression.args, 0..) |argument, i| values[i] = try self.evaluate(argument);
        if (expression.kind == .procedure) {
            return (try self.call(t, values)) orelse return bad(self.errors, t, "{s} did not output", .{t.text});
        }
        if (expression.kind == .binary) {
            const a = values[0];
            const b = values[1];
            if (equal(t.text, "+")) return a + b;
            if (equal(t.text, "-")) return a - b;
            if (equal(t.text, "*")) return a * b;
            if (equal(t.text, "/") or equal(t.text, "MOD")) {
                if (b == 0) return bad(self.errors, t, "{s} doesn't like 0 as input", .{t.text});
                return if (equal(t.text, "/")) @divTrunc(a, b) else @rem(a, b);
            }
            if (equal(t.text, "=")) return truth(a == b);
            if (equal(t.text, "<>")) return truth(a != b);
            if (equal(t.text, "<")) return truth(a < b);
            if (equal(t.text, ">")) return truth(a > b);
            if (equal(t.text, "<=")) return truth(a <= b);
            return truth(a >= b);
        }
        if (equal(t.text, "XCOR")) return self.x;
        if (equal(t.text, "YCOR")) return self.y;
        if (equal(t.text, "HEADING")) return self.heading;
        if (equal(t.text, "REPCOUNT")) {
            if (self.repetitions.items.len == 0) return bad(self.errors, t, "REPCOUNT outside REPEAT", .{});
            return self.repetitions.items[self.repetitions.items.len - 1];
        }
        if (equal(t.text, "RANDOM")) {
            if (values[0] < 1) return bad(self.errors, t, "RANDOM doesn't like {d} as input", .{values[0]});
            self.random = @mod(48271 * self.random, 2147483647);
            return @mod(self.random, values[0]);
        }
        if (equal(t.text, "ABS")) return abs(values[0]);
        if (equal(t.text, "NOT")) return truth(values[0] == 0);
        if (equal(t.text, "AND")) return truth(values[0] != 0 and values[1] != 0);
        if (equal(t.text, "OR")) return truth(values[0] != 0 or values[1] != 0);
        if (equal(t.text, "MAX")) return @max(values[0], values[1]);
        return @min(values[0], values[1]);
    }
    fn call(self: *Runtime, t: Token, values: []const Int) Error!?Int {
        if (self.calls.items.len == 100) return bad(self.errors, t, "recursion too deep", .{});
        const procedure = self.procedures.get(t.text).?;
        const traced = self.traced.contains(procedure.name);
        const depth = self.calls.items.len;
        if (traced) {
            for (0..depth * 2) |_| try self.out.add(" ");
            try self.out.print("( {s}", .{procedure.name});
            for (values) |value| try self.out.print(" {d}", .{value});
            try self.out.add(" )\n");
        }
        const environment = try self.gpa.create(Environment);
        environment.* = .{};
        for (procedure.parameters, values) |name, value| try environment.variables.put(self.gpa, name, value);
        try self.environments.append(self.gpa, environment);
        try self.calls.append(self.gpa, procedure.name);
        const signal = try self.sequence(procedure.body);
        _ = self.environments.pop();
        _ = self.calls.pop();
        environment.variables.deinit(self.gpa);
        self.gpa.destroy(environment);
        if (traced) {
            for (0..depth * 2) |_| try self.out.add(" ");
            if (signal != null and signal.?.output) {
                try self.out.line("{s} outputs {d}", .{ procedure.name, signal.?.value });
            } else try self.out.line("{s} stops", .{procedure.name});
        }
        return if (signal != null and signal.?.output) signal.?.value else null;
    }
    fn apply(self: *Runtime, p: Point) Error!void {
        if (equal(self.pen, "DOWN")) {
            try self.canvas.put(self.gpa, p, self.character);
        } else if (equal(self.pen, "ERASE")) {
            _ = self.canvas.remove(p);
        }
    }
    fn forward(self: *Runtime, amount: Int) Error!void {
        var steps = amount;
        var delta = directions[u(@divTrunc(self.heading, 45))];
        if (steps < 0) {
            steps = -steps;
            delta.x = -delta.x;
            delta.y = -delta.y;
        }
        try self.apply(.{ .x = self.x, .y = self.y });
        var i: Int = 0;
        while (i < steps) : (i += 1) {
            self.x += delta.x;
            self.y += delta.y;
            try self.apply(.{ .x = self.x, .y = self.y });
        }
    }
    fn move(self: *Runtime, x: Int, y: Int) Error!void {
        const x0 = self.x;
        const y0 = self.y;
        const dx = x - x0;
        const dy = y - y0;
        const steps = @max(abs(dx), abs(dy));
        if (steps == 0) {
            try self.apply(.{ .x = x0, .y = y0 });
        } else {
            var i: Int = 0;
            while (i <= steps) : (i += 1) try self.apply(.{ .x = x0 + @divFloor(2 * i * dx + steps, 2 * steps), .y = y0 + @divFloor(2 * i * dy + steps, 2 * steps) });
        }
        self.x = x;
        self.y = y;
    }
    fn canvasBounds(self: *Runtime) Bounds {
        var result: ?Bounds = null;
        var iterator = self.canvas.keyIterator();
        while (iterator.next()) |p| {
            if (result == null) result = .{ .x1 = p.x, .y1 = p.y, .x2 = p.x, .y2 = p.y };
            result.?.x1 = @min(result.?.x1, p.x);
            result.?.y1 = @min(result.?.y1, p.y);
            result.?.x2 = @max(result.?.x2, p.x);
            result.?.y2 = @max(result.?.y2, p.y);
        }
        return result.?;
    }
    fn fill(self: *Runtime) Error!void {
        const start: Point = .{ .x = self.x, .y = self.y };
        if (self.canvas.count() == 0 or self.canvas.contains(start)) return;
        const b = self.canvasBounds();
        if (self.x < b.x1 or self.x > b.x2 or self.y < b.y1 or self.y > b.y2) return;
        var queue: std.ArrayList(Point) = .empty;
        defer queue.deinit(self.gpa);
        try queue.append(self.gpa, start);
        try self.canvas.put(self.gpa, start, self.character);
        var i: usize = 0;
        while (i < queue.items.len) : (i += 1) {
            const p = queue.items[i];
            for ([_]Point{ .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = 0, .y = -1 } }) |delta| {
                const q: Point = .{ .x = p.x + delta.x, .y = p.y + delta.y };
                if (q.x < b.x1 or q.x > b.x2 or q.y < b.y1 or q.y > b.y2 or self.canvas.contains(q)) continue;
                try self.canvas.put(self.gpa, q, self.character);
                try queue.append(self.gpa, q);
            }
        }
    }
    fn picture(self: *Runtime) Error!void {
        if (self.canvas.count() == 0) {
            try self.out.line("CANVAS 0 0 0", .{});
            return;
        }
        const b = self.canvasBounds();
        try self.out.line("CANVAS {d} {d} {d}", .{ b.x2 - b.x1 + 1, b.y2 - b.y1 + 1, self.canvas.count() });
        const row = try self.gpa.alloc(u8, u(b.x2 - b.x1 + 1));
        defer self.gpa.free(row);
        var y = b.y2;
        while (y >= b.y1) : (y -= 1) {
            for (row, 0..) |*c, i| c.* = self.canvas.get(.{ .x = b.x1 + si(i), .y = y }) orelse ' ';
            try self.out.line("{s}", .{std.mem.trimEnd(u8, row, " ")});
        }
    }
    fn item(self: *Runtime, value: Input) Error!Text {
        return switch (value) {
            .quoted => |quoted| try self.gpa.dupe(u8, quoted.name),
            .expression => |expression| try std.fmt.allocPrint(self.gpa, "{d}", .{try self.evaluate(expression)}),
            .list => unreachable,
        };
    }
    fn sequence(self: *Runtime, commands: []const *Command) Error!?Signal {
        for (commands) |command| if (try self.execute(command)) |signal| return signal;
        return null;
    }
    fn execute(self: *Runtime, command: *const Command) Error!?Signal {
        const kind = command.kind;
        const t = command.token;
        const inputs = command.inputs;
        if (equal(kind, "multiple")) {
            var line: Builder = .{ .gpa = self.gpa };
            defer line.deinit();
            for (inputs, 0..) |value, i| {
                const text = try self.item(value);
                defer self.gpa.free(text);
                if (i > 0) try line.add(" ");
                try line.add(text);
            }
            try self.out.line("{s}", .{line.bytes.items});
            return null;
        }
        if (equal(kind, "WHILE")) {
            while (try self.evaluate(inputs[0].expression) != 0) {
                if (try self.sequence(inputs[1].list)) |signal| return signal;
            }
            return null;
        }
        const values = try self.gpa.alloc(Int, inputs.len);
        defer self.gpa.free(values);
        for (inputs, 0..) |value, i| values[i] = switch (value) {
            .expression => |expression| try self.evaluate(expression),
            else => 0,
        };
        if (equal(kind, "procedure")) {
            if (try self.call(t, values)) |value| return bad(self.errors, t, "you don't say what to do with {d}", .{value});
            return null;
        }
        if (equal(kind, "FD")) {
            try self.forward(values[0]);
        } else if (equal(kind, "BK")) {
            try self.forward(-values[0]);
        } else if (oneOf(kind, &.{ "RT", "LT", "SETH" })) {
            var angle = values[0];
            if (@rem(angle, 45) != 0) return bad(self.errors, t, "{s} doesn't like {d} as input", .{ t.text, angle });
            if (equal(kind, "RT")) {
                angle += self.heading;
            } else if (equal(kind, "LT")) {
                angle = self.heading - angle;
            }
            self.heading = @mod(angle, 360);
        } else if (equal(kind, "PU")) {
            self.pen = "UP";
        } else if (equal(kind, "PD")) {
            self.pen = "DOWN";
        } else if (equal(kind, "PE")) {
            self.pen = "ERASE";
        } else if (equal(kind, "SETPEN")) {
            if (values[0] < 33 or values[0] > 126) return bad(self.errors, t, "SETPEN doesn't like {d} as input", .{values[0]});
            self.character = @intCast(values[0]);
        } else if (equal(kind, "SETXY")) {
            try self.move(values[0], values[1]);
        } else if (equal(kind, "SETX")) {
            try self.move(values[0], self.y);
        } else if (equal(kind, "SETY")) {
            try self.move(self.x, values[0]);
        } else if (equal(kind, "HOME")) {
            try self.move(0, 0);
            self.heading = 0;
        } else if (equal(kind, "CS")) {
            self.canvas.clearRetainingCapacity();
            self.x = 0;
            self.y = 0;
            self.heading = 0;
        } else if (equal(kind, "CLEAN")) {
            self.canvas.clearRetainingCapacity();
        } else if (equal(kind, "FILL")) {
            try self.fill();
        } else if (equal(kind, "LABEL") or equal(kind, "PRINT")) {
            const text = switch (inputs[0]) {
                .quoted => |quoted| try self.gpa.dupe(u8, quoted.name),
                else => try std.fmt.allocPrint(self.gpa, "{d}", .{values[0]}),
            };
            defer self.gpa.free(text);
            if (equal(kind, "PRINT")) {
                try self.out.line("{s}", .{text});
            } else {
                const delta = directions[u(@divTrunc(self.heading, 45))];
                for (text, 0..) |c, i| try self.canvas.put(self.gpa, .{ .x = self.x + si(i) * delta.x, .y = self.y + si(i) * delta.y }, c);
            }
        } else if (equal(kind, "SNAPSHOT")) {
            try self.picture();
        } else if (equal(kind, "REPEAT")) {
            if (inputs[1].list.len == 0) return null;
            var n: Int = 1;
            while (n <= values[0]) : (n += 1) {
                try self.repetitions.append(self.gpa, n);
                const signal = self.sequence(inputs[1].list) catch |err| {
                    _ = self.repetitions.pop();
                    return err;
                };
                _ = self.repetitions.pop();
                if (signal) |value| return value;
            }
        } else if (equal(kind, "FOR")) {
            if (inputs[3].list.len == 0) {
                try self.assign(inputs[0].quoted.name, values[2]);
                return null;
            }
            const a = values[1];
            const b = values[2];
            const step: Int = if (a <= b) 1 else -1;
            var value = a;
            while (true) {
                try self.assign(inputs[0].quoted.name, value);
                if (try self.sequence(inputs[3].list)) |signal| return signal;
                if (value == b) break;
                value += step;
            }
        } else if (equal(kind, "IF")) {
            if (values[0] != 0) return self.sequence(inputs[1].list);
        } else if (equal(kind, "IFELSE")) {
            return self.sequence(inputs[if (values[0] != 0) @as(usize, 1) else 2].list);
        } else if (equal(kind, "TEST")) {
            self.current().test_result = values[0] != 0;
        } else if (equal(kind, "IFTRUE") or equal(kind, "IFFALSE")) {
            const value = self.current().test_result orelse return bad(self.errors, t, "{s} without TEST", .{t.text});
            if (value == equal(kind, "IFTRUE")) return self.sequence(inputs[0].list);
        } else if (equal(kind, "STOP")) {
            return Signal{};
        } else if (equal(kind, "OUTPUT")) {
            return Signal{ .output = true, .value = values[0] };
        } else if (equal(kind, "MAKE")) {
            try self.assign(inputs[0].quoted.name, values[1]);
        } else if (equal(kind, "LOCAL")) {
            try self.current().variables.put(self.gpa, inputs[0].quoted.name, 0);
        } else if (equal(kind, "LOCALMAKE")) {
            try self.current().variables.put(self.gpa, inputs[0].quoted.name, values[1]);
        } else if (equal(kind, "TRACE")) {
            try self.traced.put(self.gpa, inputs[0].quoted.name, {});
        } else if (equal(kind, "UNTRACE")) {
            _ = self.traced.remove(inputs[0].quoted.name);
        } else if (equal(kind, "SEED")) {
            if (values[0] < 1) return bad(self.errors, t, "SEED doesn't like {d} as input", .{values[0]});
            self.random = values[0];
        }
        return null;
    }
};
const Program = struct {
    gpa: Allocator,
    out: *Builder,
    procedures: ProcedureMap = .empty,
    machine: ?*Runtime = null,
    fn process(self: *Program, lines: []const SourceLine) Error!void {
        var ordered: std.ArrayList(*Procedure) = .empty;
        var top: std.ArrayList(Token) = .empty;
        var current: ?*Procedure = null;
        for (lines) |line| {
            const tokens = try lex(self.gpa, line);
            if (tokens.len == 0) continue;
            const first = tokens[0];
            if (first.kind == .word and equal(first.text, "TO")) {
                if (current) |procedure| return bad(self.gpa, first, "TO inside definition of {s}", .{procedure.name});
                if (tokens.len < 2 or tokens[1].kind != .word) return bad(self.gpa, first, "bad procedure header", .{});
                const name = tokens[1].text;
                if (findPrimitive(name) != null) return bad(self.gpa, first, "{s} is a primitive", .{name});
                if (self.procedures.contains(name)) return bad(self.gpa, first, "{s} is already defined", .{name});
                var parameters: std.ArrayList(Text) = .empty;
                var seen: std.StringHashMapUnmanaged(void) = .empty;
                for (tokens[2..]) |t| {
                    if (t.kind != .variable) return bad(self.gpa, first, "bad procedure header", .{});
                    if (seen.contains(t.name)) return bad(self.gpa, first, "duplicate input {s}", .{t.text});
                    try seen.put(self.gpa, t.name, {});
                    try parameters.append(self.gpa, t.name);
                }
                const procedure = try self.gpa.create(Procedure);
                procedure.* = .{ .name = name, .line = first.line, .parameters = parameters.items };
                try self.procedures.put(self.gpa, name, procedure);
                try ordered.append(self.gpa, procedure);
                current = procedure;
            } else if (tokens.len == 1 and first.kind == .word and equal(first.text, "END")) {
                if (current == null) return bad(self.gpa, first, "END without TO", .{});
                current = null;
            } else if (current) |procedure| {
                try procedure.tokens.appendSlice(self.gpa, tokens);
            } else {
                try top.appendSlice(self.gpa, tokens);
            }
        }
        if (current) |procedure| return bad(self.gpa, .{ .line = procedure.line }, "missing END for {s}", .{procedure.name});
        for (ordered.items) |procedure| {
            var parser: Parser = .{ .gpa = self.gpa, .tokens = procedure.tokens.items, .procedures = self.procedures, .inside = true };
            procedure.body = try parser.sequence();
        }
        var parser: Parser = .{ .gpa = self.gpa, .tokens = top.items, .procedures = self.procedures, .inside = false };
        const commands = try parser.sequence();
        const machine = try self.gpa.create(Runtime);
        machine.* = .{ .gpa = std.heap.page_allocator, .errors = self.gpa, .out = self.out, .procedures = self.procedures };
        self.machine = machine;
        const environment = try machine.gpa.create(Environment);
        environment.* = .{};
        try machine.environments.append(machine.gpa, environment);
        _ = try machine.sequence(commands);
        try self.out.line("TURTLE {d} {d} {d} {s} {c}", .{ machine.x, machine.y, machine.heading, machine.pen, machine.character });
        try machine.picture();
    }
};
fn runProgram(name: Text, lines: []const SourceLine, out: *Builder) Error!void {
    try out.line("PROGRAM {s}", .{name});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var program: Program = .{ .gpa = arena.allocator(), .out = out };
    defer {
        if (program.machine) |machine| machine.deinit();
    }
    program.process(lines) catch |err| {
        if (err != error.Invalid) return err;
        try out.line("ERROR line {d}: {s}", .{ failureLine, failureReason });
        if (program.machine) |machine| {
            var i = machine.calls.items.len;
            while (i > 0) {
                i -= 1;
                const procedureName = machine.calls.items[i];
                var count: usize = 1;
                while (i > 0 and equal(machine.calls.items[i - 1], procedureName)) {
                    i -= 1;
                    count += 1;
                }
                if (count == 1) {
                    try out.line("  in {s}", .{procedureName});
                } else try out.line("  in {s} x{d}", .{ procedureName, count });
            }
        }
    };
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var out: Builder = .{ .gpa = gpa };
    var name: ?Text = null;
    var source: std.ArrayList(SourceLine) = .empty;
    var lineNumber: usize = 0;
    while (lines.next()) |raw| {
        lineNumber += 1;
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "#EOF")) {
            try runProgram(name.?, source.items, &out);
            break;
        }
        if (std.mem.startsWith(u8, line, "#PROGRAM ")) {
            if (name) |previous| try runProgram(previous, source.items, &out);
            name = line[9..];
            source.clearRetainingCapacity();
        } else try source.append(gpa, .{ .text = line, .number = lineNumber });
    }
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
