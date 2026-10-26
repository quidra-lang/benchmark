const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";
fn sameText(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn inList(text: Text, list: []const Text) bool {
    for (list) |item| if (sameText(text, item)) return true;
    return false;
}
fn asciiLower(c: u8) bool {
    return c >= 'a' and c <= 'z';
}
fn asciiUpper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}
fn asciiDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
fn wordCharacter(c: u8) bool {
    return asciiLower(c) or asciiUpper(c) or asciiDigit(c) or c == '_';
}
fn bad(gpa: Allocator, comptime format: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, format, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const reserved = [_]Text{ "not", "mod", "count", "sum", "min", "max", "retract", "dump", "why", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt" };
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.print(format ++ "\n", args);
    }
};
fn sortedKeys(gpa: Allocator, map: anytype) Error![]const Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, struct {
        fn less(_: void, a: Text, b: Text) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return result.items;
}
const Value = union(enum) { integer: i64, symbol: Text };
fn compareValue(a: Value, b: Value) std.math.Order {
    return switch (a) {
        .integer => |n| switch (b) {
            .integer => |m| std.math.order(n, m),
            .symbol => .lt,
        },
        .symbol => |s| switch (b) {
            .integer => .gt,
            .symbol => |t| std.mem.order(u8, s, t),
        },
    };
}
fn compareTuple(a: []const Value, b: []const Value) std.math.Order {
    for (a, b) |x, y| {
        const order = compareValue(x, y);
        if (order != .eq) return order;
    }
    return .eq;
}
fn valueText(gpa: Allocator, value: Value) Error!Text {
    if (value == .integer) return std.fmt.allocPrint(gpa, "{d}", .{value.integer});
    const text = value.symbol;
    var simple = text.len > 0 and asciiLower(text[0]) and !inList(text, &reserved);
    for (text) |c| if (!wordCharacter(c)) {
        simple = false;
        break;
    };
    return if (simple) text else try std.fmt.allocPrint(gpa, "\"{s}\"", .{text});
}
const Term = struct { kind: enum { constant, variable, anonymous }, name: Text = "", value: Value = .{ .integer = 0 } };
const Expression = struct { kind: enum { leaf, group, operation }, term: Term = .{ .kind = .anonymous }, operator: Text = "", left: ?*Expression = null, right: ?*Expression = null };
const Atom = struct { name: Text, terms: []const Term = &.{} };
const Literal = struct { kind: enum { positive, negative, comparison }, atom: Atom = .{ .name = "" }, operator: Text = "", left: ?*Expression = null, right: ?*Expression = null };
const StatementKind = enum { fact, rule, constraint, query, retract, why, dump, forget, listing, strata, stats, check, predicates, undo, halt };
const Statement = struct { kind: StatementKind, name: Text = "", aggregate: Text = "", variable: Text = "", number: usize = 0, head: ?Atom = null, body: []const Literal = &.{} };
const Token = struct { kind: Text, text: Text, number: i64 = 0 };
fn lexical(gpa: Allocator, source: Text) Error![]const Token {
    var tokens: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < source.len) {
        const c = source[i];
        if (c == ' ') {
            i += 1;
            continue;
        }
        if (c == '%') break;
        const start = i;
        if (c == '"') {
            i += 1;
            while (i < source.len and source[i] != '"') i += 1;
            if (i == source.len) return bad(gpa, "unterminated string", .{});
            i += 1;
            try tokens.append(gpa, .{ .kind = "string", .text = source[start..i] });
            continue;
        }
        if (i + 1 < source.len and inList(source[i .. i + 2], &.{ ":-", "?-", "!=", "<=", ">=" })) {
            try tokens.append(gpa, .{ .kind = source[i .. i + 2], .text = source[i .. i + 2] });
            i += 2;
            continue;
        }
        if (std.mem.findScalar(u8, "(),.:=<>+-*/", c) != null) {
            try tokens.append(gpa, .{ .kind = source[i .. i + 1], .text = source[i .. i + 1] });
            i += 1;
            continue;
        }
        if (!wordCharacter(c)) return bad(gpa, "bad character '{c}'", .{c});
        while (i < source.len and wordCharacter(source[i])) i += 1;
        const text = source[start..i];
        var item: Token = .{ .kind = "", .text = text };
        if (asciiLower(c)) {
            item.kind = if (inList(text, &reserved)) text else "name";
        } else if (asciiUpper(c)) {
            item.kind = "variable";
        } else if (sameText(text, "_")) {
            item.kind = "anonymous";
        } else {
            for (text) |character| if (!asciiDigit(character)) return bad(gpa, "bad token '{s}'", .{text});
            item.kind = "integer";
            item.number = std.fmt.parseInt(i64, text, 10) catch unreachable;
            if (item.number > 1000000000) return bad(gpa, "integer out of range '{s}'", .{text});
        }
        try tokens.append(gpa, item);
    }
    return tokens.items;
}
const Parser = struct {
    gpa: Allocator,
    tokens: []const Token,
    position: usize = 0,
    fn peek(self: *Parser) Text {
        return if (self.position < self.tokens.len) self.tokens[self.position].kind else "end";
    }
    fn invalid(self: *Parser) Error {
        return if (sameText(self.peek(), "end")) bad(self.gpa, "syntax error at end of line", .{}) else bad(self.gpa, "syntax error at '{s}'", .{self.tokens[self.position].text});
    }
    fn take(self: *Parser, kind: Text) Error!Token {
        if (!sameText(self.peek(), kind)) return self.invalid();
        const item = self.tokens[self.position];
        self.position += 1;
        return item;
    }
    fn readTerm(self: *Parser) Error!Term {
        const kind = self.peek();
        if (sameText(kind, "name")) return .{ .kind = .constant, .value = .{ .symbol = (try self.take(kind)).text } };
        if (sameText(kind, "string")) {
            const text = (try self.take(kind)).text;
            return .{ .kind = .constant, .value = .{ .symbol = text[1 .. text.len - 1] } };
        }
        if (sameText(kind, "integer")) return .{ .kind = .constant, .value = .{ .integer = (try self.take(kind)).number } };
        if (sameText(kind, "-")) {
            _ = try self.take("-");
            return .{ .kind = .constant, .value = .{ .integer = -(try self.take("integer")).number } };
        }
        if (sameText(kind, "variable")) return .{ .kind = .variable, .name = (try self.take(kind)).text };
        if (sameText(kind, "anonymous")) {
            _ = try self.take(kind);
            return .{ .kind = .anonymous };
        }
        return self.invalid();
    }
    fn readAtom(self: *Parser) Error!Atom {
        const name = (try self.take("name")).text;
        var terms: std.ArrayList(Term) = .empty;
        if (sameText(self.peek(), "(")) {
            _ = try self.take("(");
            try terms.append(self.gpa, try self.readTerm());
            while (sameText(self.peek(), ",")) {
                _ = try self.take(",");
                try terms.append(self.gpa, try self.readTerm());
            }
            _ = try self.take(")");
        }
        return .{ .name = name, .terms = terms.items };
    }
    fn newExpression(self: *Parser, node: Expression) Error!*Expression {
        const result = try self.gpa.create(Expression);
        result.* = node;
        return result;
    }
    fn factor(self: *Parser) Error!*Expression {
        if (sameText(self.peek(), "(")) {
            _ = try self.take("(");
            const inside = try self.readExpression();
            _ = try self.take(")");
            return self.newExpression(.{ .kind = .group, .left = inside });
        }
        return self.newExpression(.{ .kind = .leaf, .term = try self.readTerm() });
    }
    fn product(self: *Parser) Error!*Expression {
        var result = try self.factor();
        while (inList(self.peek(), &.{ "*", "/", "mod" })) {
            const operator = (try self.take(self.peek())).kind;
            result = try self.newExpression(.{ .kind = .operation, .operator = operator, .left = result, .right = try self.factor() });
        }
        return result;
    }
    fn readExpression(self: *Parser) Error!*Expression {
        var result = try self.product();
        while (inList(self.peek(), &.{ "+", "-" })) {
            const operator = (try self.take(self.peek())).kind;
            result = try self.newExpression(.{ .kind = .operation, .operator = operator, .left = result, .right = try self.product() });
        }
        return result;
    }
    fn readLiteral(self: *Parser) Error!Literal {
        if (sameText(self.peek(), "not")) {
            _ = try self.take("not");
            return .{ .kind = .negative, .atom = try self.readAtom() };
        }
        if (sameText(self.peek(), "name")) {
            const next = if (self.position + 1 < self.tokens.len) self.tokens[self.position + 1].kind else "end";
            if (!inList(next, &.{ "=", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "mod" })) return .{ .kind = .positive, .atom = try self.readAtom() };
        }
        const left = try self.readExpression();
        if (!inList(self.peek(), &.{ "=", "!=", "<", "<=", ">", ">=" })) return self.invalid();
        const operator = (try self.take(self.peek())).kind;
        return .{ .kind = .comparison, .operator = operator, .left = left, .right = try self.readExpression() };
    }
    fn readBody(self: *Parser) Error![]const Literal {
        var result: std.ArrayList(Literal) = .empty;
        try result.append(self.gpa, try self.readLiteral());
        while (sameText(self.peek(), ",")) {
            _ = try self.take(",");
            try result.append(self.gpa, try self.readLiteral());
        }
        return result.items;
    }
    fn readStatement(self: *Parser) Error!Statement {
        const kind = self.peek();
        var result: Statement = .{ .kind = .halt };
        if (sameText(kind, "name")) {
            result.head = try self.readAtom();
            result.kind = .fact;
            if (sameText(self.peek(), ":-")) {
                _ = try self.take(":-");
                result.kind = .rule;
                result.body = try self.readBody();
            }
        } else if (sameText(kind, ":-")) {
            _ = try self.take(kind);
            result.kind = .constraint;
            result.body = try self.readBody();
        } else if (sameText(kind, "?-")) {
            _ = try self.take(kind);
            result.kind = .query;
            if (inList(self.peek(), &.{ "count", "sum", "min", "max" })) {
                result.aggregate = (try self.take(self.peek())).kind;
                if (!sameText(result.aggregate, "count")) {
                    result.variable = (try self.take("variable")).text;
                    _ = try self.take(":");
                }
            }
            result.body = try self.readBody();
        } else if (inList(kind, &.{ "retract", "why" })) {
            _ = try self.take(kind);
            result.kind = if (sameText(kind, "retract")) .retract else .why;
            result.head = try self.readAtom();
        } else if (sameText(kind, "dump")) {
            _ = try self.take(kind);
            result.kind = .dump;
            result.name = (try self.take("name")).text;
        } else if (sameText(kind, "forget")) {
            _ = try self.take(kind);
            result.kind = .forget;
            result.number = @intCast((try self.take("integer")).number);
        } else if (sameText(kind, "listing")) {
            _ = try self.take(kind);
            result.kind = .listing;
            if (sameText(self.peek(), "name")) result.name = (try self.take("name")).text;
        } else if (inList(kind, &.{ "strata", "stats", "check", "predicates", "undo", "halt" })) {
            _ = try self.take(kind);
            result.kind = std.meta.stringToEnum(StatementKind, kind).?;
        } else return self.invalid();
        _ = try self.take(".");
        if (!sameText(self.peek(), "end")) return self.invalid();
        return result;
    }
};
const Assignment = std.StringHashMapUnmanaged(Value);
fn termText(gpa: Allocator, term: Term, assignment: ?Assignment) Error!Text {
    return switch (term.kind) {
        .constant => valueText(gpa, term.value),
        .anonymous => "_",
        .variable => if (assignment) |binding| valueText(gpa, binding.get(term.name).?) else term.name,
    };
}
fn atomText(gpa: Allocator, atom: Atom, assignment: ?Assignment) Error!Text {
    if (atom.terms.len == 0) return atom.name;
    var out: Builder = .{ .gpa = gpa };
    try out.print("{s}(", .{atom.name});
    for (atom.terms, 0..) |term, i| {
        if (i > 0) try out.add(", ");
        try out.add(try termText(gpa, term, assignment));
    }
    try out.add(")");
    return out.bytes.items;
}
fn expressionText(gpa: Allocator, node: *const Expression, assignment: ?Assignment) Error!Text {
    if (node.kind == .leaf) return termText(gpa, node.term, assignment);
    if (node.kind == .group) return std.fmt.allocPrint(gpa, "({s})", .{try expressionText(gpa, node.left.?, assignment)});
    return std.fmt.allocPrint(gpa, "{s} {s} {s}", .{ try expressionText(gpa, node.left.?, assignment), node.operator, try expressionText(gpa, node.right.?, assignment) });
}
fn literalText(gpa: Allocator, literal: Literal, assignment: ?Assignment) Error!Text {
    if (literal.kind == .comparison) return std.fmt.allocPrint(gpa, "{s} {s} {s}", .{ try expressionText(gpa, literal.left.?, assignment), literal.operator, try expressionText(gpa, literal.right.?, assignment) });
    return std.fmt.allocPrint(gpa, "{s}{s}", .{ if (literal.kind == .negative) "not " else "", try atomText(gpa, literal.atom, assignment) });
}
fn ruleText(gpa: Allocator, statement: Statement) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    if (statement.head) |head| try out.print("{s} ", .{try atomText(gpa, head, null)});
    try out.add(":- ");
    for (statement.body, 0..) |literal, i| {
        if (i > 0) try out.add(", ");
        try out.add(try literalText(gpa, literal, null));
    }
    try out.add(".");
    return out.bytes.items;
}
fn expressionTerms(gpa: Allocator, node: *const Expression, result: *std.ArrayList(Term)) Error!void {
    if (node.kind == .leaf) {
        try result.append(gpa, node.term);
    } else {
        try expressionTerms(gpa, node.left.?, result);
        if (node.kind == .operation) try expressionTerms(gpa, node.right.?, result);
    }
}
fn literalTerms(gpa: Allocator, literal: Literal) Error![]const Term {
    if (literal.kind != .comparison) return literal.atom.terms;
    var result: std.ArrayList(Term) = .empty;
    try expressionTerms(gpa, literal.left.?, &result);
    try expressionTerms(gpa, literal.right.?, &result);
    return result.items;
}
fn allTerms(gpa: Allocator, statement: Statement) Error![]const Term {
    var result: std.ArrayList(Term) = .empty;
    if (statement.head) |head| try result.appendSlice(gpa, head.terms);
    for (statement.body) |literal| try result.appendSlice(gpa, try literalTerms(gpa, literal));
    return result.items;
}
fn variables(gpa: Allocator, terms: []const Term) Error![]const Text {
    var result: std.ArrayList(Text) = .empty;
    for (terms) |term| if (term.kind == .variable and !inList(term.name, result.items)) try result.append(gpa, term.name);
    return result.items;
}
fn tupleKey(gpa: Allocator, values: []const Value) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (values) |value| switch (value) {
        .integer => |n| try out.print("i{d};", .{n}),
        .symbol => |s| try out.print("s{d}:{s}", .{ s.len, s }),
    };
    return out.bytes.items;
}
const Tuple = struct { values: []const Value, round: usize = 0, rule: usize = 0 };
const TupleSet = std.StringHashMapUnmanaged(Tuple);
const Facts = std.StringHashMapUnmanaged([]const Value);
const Predicate = struct { arity: usize, facts: Facts = .empty };
const Predicates = std.StringHashMapUnmanaged(Predicate);
const Rule = struct { number: usize, statement: Statement };
const Snapshot = struct { predicates: Predicates, rules: []const Rule, line: usize };
const ArityMap = std.StringHashMapUnmanaged(usize);
const Levels = struct { values: ArityMap, recursive: std.StringHashMapUnmanaged(bool), maximum: ?usize };
fn statementAtoms(gpa: Allocator, statement: Statement) Error![]const Atom {
    var result: std.ArrayList(Atom) = .empty;
    if (statement.head) |head| try result.append(gpa, head);
    for (statement.body) |literal| if (literal.kind != .comparison) try result.append(gpa, literal.atom);
    return result.items;
}
fn safety(gpa: Allocator, statement: Statement) Error!void {
    if (statement.head) |head| for (head.terms) |term| if (term.kind == .anonymous) return bad(gpa, "anonymous variable in head", .{});
    var bound: std.StringHashMapUnmanaged(void) = .empty;
    for (statement.body) |literal| {
        if (literal.kind == .comparison) for (try literalTerms(gpa, literal)) |term| if (term.kind == .anonymous) return bad(gpa, "anonymous variable in comparison", .{});
        if (literal.kind == .positive) for (literal.atom.terms) |term| if (term.kind == .variable) try bound.put(gpa, term.name, {});
    }
    var checked: std.ArrayList(Term) = .empty;
    if (statement.head) |head| try checked.appendSlice(gpa, head.terms);
    if (statement.aggregate.len > 0 and !sameText(statement.aggregate, "count")) try checked.append(gpa, .{ .kind = .variable, .name = statement.variable });
    for (statement.body) |literal| if (literal.kind != .positive) try checked.appendSlice(gpa, try literalTerms(gpa, literal));
    for (checked.items) |term| if (term.kind == .variable and !bound.contains(term.name)) return bad(gpa, "unsafe variable {s}", .{term.name});
}
fn stratification(gpa: Allocator, arities: ArityMap, rules: []const Rule) Error!?Levels {
    const names = try sortedKeys(gpa, arities);
    const n = names.len;
    var indices: ArityMap = .empty;
    var result: Levels = .{ .values = .empty, .recursive = .empty, .maximum = if (n == 0) null else 0 };
    for (names, 0..) |name, i| {
        try indices.put(gpa, name, i);
        try result.values.put(gpa, name, 0);
    }
    const reach = try gpa.alloc(bool, n * n);
    @memset(reach, false);
    for (rules) |rule| if (rule.statement.head) |head| {
        for (rule.statement.body) |literal| if (literal.kind != .comparison) {
            reach[indices.get(head.name).? * n + indices.get(literal.atom.name).?] = true;
        };
    };
    for (0..n) |k| for (0..n) |i| for (0..n) |j| {
        if (reach[i * n + k] and reach[k * n + j]) reach[i * n + j] = true;
    };
    for (names, 0..) |name, i| try result.recursive.put(gpa, name, reach[i * n + i]);
    for (rules) |rule| if (rule.statement.head) |head| {
        for (rule.statement.body) |literal| if (literal.kind == .negative and (sameText(head.name, literal.atom.name) or reach[indices.get(literal.atom.name).? * n + indices.get(head.name).?])) return null;
    };
    var changed = true;
    while (changed) {
        changed = false;
        for (rules) |rule| if (rule.statement.head) |head| {
            for (rule.statement.body) |literal| {
                if (literal.kind == .comparison) continue;
                const required = result.values.get(literal.atom.name).? + @as(usize, if (literal.kind == .negative) 1 else 0);
                if (result.values.get(head.name).? < required) {
                    try result.values.put(gpa, head.name, required);
                    changed = true;
                }
            }
        };
    }
    var iterator = result.values.valueIterator();
    while (iterator.next()) |level| result.maximum = @max(result.maximum.?, level.*);
    return result;
}
fn copyAssignment(gpa: Allocator, assignment: Assignment) Error!Assignment {
    var result: Assignment = .empty;
    var iterator = assignment.iterator();
    while (iterator.next()) |entry| try result.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
    return result;
}
fn atomMatches(atom: Atom, values: []const Value, assignment: Assignment) bool {
    for (atom.terms, values, 0..) |term, value, i| {
        if (term.kind == .constant and compareValue(term.value, value) != .eq) return false;
        if (term.kind == .variable) {
            if (assignment.get(term.name)) |previous| {
                if (compareValue(previous, value) != .eq) return false;
            } else for (atom.terms[0..i], values[0..i]) |earlier, oldValue| {
                if (earlier.kind == .variable and sameText(earlier.name, term.name) and compareValue(oldValue, value) != .eq) return false;
            }
        }
    }
    return true;
}
fn matchAtom(gpa: Allocator, atom: Atom, values: []const Value, assignment: Assignment) Error!?Assignment {
    if (!atomMatches(atom, values, assignment)) return null;
    var result = try copyAssignment(gpa, assignment);
    for (atom.terms, values) |term, value| if (term.kind == .variable) try result.put(gpa, term.name, value);
    return result;
}
fn evaluate(node: *const Expression, assignment: Assignment) ?Value {
    if (node.kind == .leaf) return if (node.term.kind == .constant) node.term.value else assignment.get(node.term.name);
    if (node.kind == .group) return evaluate(node.left.?, assignment);
    const a = evaluate(node.left.?, assignment) orelse return null;
    const b = evaluate(node.right.?, assignment) orelse return null;
    if (a != .integer or b != .integer) return null;
    const x = a.integer;
    const y = b.integer;
    const number: i64 = if (sameText(node.operator, "+")) x + y else if (sameText(node.operator, "-")) x - y else if (sameText(node.operator, "*")) x * y else blk: {
        if (y == 0) return null;
        const quotient = @divFloor(x, y);
        break :blk if (sameText(node.operator, "mod")) x - y * quotient else quotient;
    };
    return .{ .integer = number };
}
fn comparison(literal: Literal, assignment: Assignment) bool {
    const a = evaluate(literal.left.?, assignment) orelse return false;
    const b = evaluate(literal.right.?, assignment) orelse return false;
    const order = compareValue(a, b);
    if (sameText(literal.operator, "=")) return order == .eq;
    if (sameText(literal.operator, "!=")) return order != .eq;
    if (a != .integer or b != .integer) return false;
    if (sameText(literal.operator, "<")) return order == .lt;
    if (sameText(literal.operator, "<=")) return order != .gt;
    if (sameText(literal.operator, ">")) return order == .gt;
    return order != .lt;
}
fn orderedTuples(gpa: Allocator, set: TupleSet) Error![]const Tuple {
    var result: std.ArrayList(Tuple) = .empty;
    var iterator = set.valueIterator();
    while (iterator.next()) |tuple| try result.append(gpa, tuple.*);
    std.mem.sort(Tuple, result.items, {}, struct {
        fn less(_: void, a: Tuple, b: Tuple) bool {
            return compareTuple(a.values, b.values) == .lt;
        }
    }.less);
    return result.items;
}
const ModelTuples = std.StringHashMapUnmanaged(TupleSet);
fn expressionReady(node: *const Expression, binding: Assignment) bool {
    if (node.kind == .leaf) return node.term.kind != .variable or binding.contains(node.term.name);
    return expressionReady(node.left.?, binding) and (node.kind != .operation or expressionReady(node.right.?, binding));
}
fn filtersAccept(body: []const Literal, model: ModelTuples, binding: Assignment) bool {
    for (body) |literal| {
        if (literal.kind == .comparison) {
            if (expressionReady(literal.left.?, binding) and expressionReady(literal.right.?, binding) and !comparison(literal, binding)) return false;
        } else if (literal.kind == .negative) {
            var ready = true;
            for (literal.atom.terms) |term| if (term.kind == .variable and !binding.contains(term.name)) {
                ready = false;
                break;
            };
            if (!ready) continue;
            var iterator = model.get(literal.atom.name).?.valueIterator();
            while (iterator.next()) |tuple| if (atomMatches(literal.atom, tuple.values, binding)) return false;
        }
    }
    return true;
}
fn assignmentKey(gpa: Allocator, binding: Assignment) Error!Text {
    var values: std.ArrayList(Value) = .empty;
    for (try sortedKeys(gpa, binding)) |name| try values.append(gpa, binding.get(name).?);
    return tupleKey(gpa, values.items);
}
const SolutionSearch = struct {
    gpa: Allocator,
    body: []const Literal,
    model: ModelTuples,
    before: ?usize,
    result: std.ArrayList(Assignment) = .empty,
    finished: std.StringHashMapUnmanaged(void) = .empty,

    fn visit(self: *SolutionSearch, binding: Assignment, remaining: []const Literal) Error!void {
        if (!filtersAccept(self.body, self.model, binding)) return;
        if (remaining.len == 0) {
            const key = try assignmentKey(self.gpa, binding);
            if (!self.finished.contains(key)) {
                try self.finished.put(self.gpa, key, {});
                try self.result.append(self.gpa, try copyAssignment(self.gpa, binding));
            }
            return;
        }
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const local = scratch.allocator();
        var selected: ?usize = null;
        var candidates: []const Assignment = &.{};
        for (remaining, 0..) |literal, i| {
            var matches: std.ArrayList(Assignment) = .empty;
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            var iterator = self.model.get(literal.atom.name).?.valueIterator();
            while (iterator.next()) |tuple| {
                if (self.before) |limit| if (tuple.round >= limit) continue;
                if (try matchAtom(local, literal.atom, tuple.values, binding)) |matched| {
                    if (!filtersAccept(self.body, self.model, matched)) continue;
                    const key = try assignmentKey(local, matched);
                    if (!seen.contains(key)) {
                        try seen.put(local, key, {});
                        try matches.append(local, matched);
                    }
                }
            }
            if (matches.items.len == 0) return;
            if (selected == null or matches.items.len < candidates.len) {
                selected = i;
                candidates = matches.items;
            }
        }
        var nextRemaining: std.ArrayList(Literal) = .empty;
        try nextRemaining.appendSlice(local, remaining[0..selected.?]);
        try nextRemaining.appendSlice(local, remaining[selected.? + 1 ..]);
        for (candidates) |matched| try self.visit(matched, nextRemaining.items);
    }
};
fn solutions(gpa: Allocator, body: []const Literal, model: ModelTuples, before: ?usize) Error![]const Assignment {
    var positives: std.ArrayList(Literal) = .empty;
    for (body) |literal| if (literal.kind == .positive) try positives.append(gpa, literal);
    var search: SolutionSearch = .{ .gpa = gpa, .body = body, .model = model, .before = before };
    try search.visit(.empty, positives.items);
    return search.result.items;
}
fn atomValues(gpa: Allocator, atom: Atom, assignment: Assignment) Error![]const Value {
    var result: std.ArrayList(Value) = .empty;
    for (atom.terms) |term| try result.append(gpa, if (term.kind == .constant) term.value else assignment.get(term.name).?);
    return result.items;
}
const Model = struct { tuples: ModelTuples, levels: Levels, rounds: []usize, added: []usize };
const Answers = struct { names: []const Text, rows: []const []const Value };
fn answerRows(gpa: Allocator, statement: Statement, model: Model) Error!Answers {
    const names = try variables(gpa, try allTerms(gpa, .{ .kind = .query, .body = statement.body }));
    var rows: std.ArrayList([]const Value) = .empty;
    for (try solutions(gpa, statement.body, model.tuples, null)) |binding| {
        const row = try gpa.alloc(Value, names.len);
        for (names, row) |name, *value| value.* = binding.get(name).?;
        try rows.append(gpa, row);
    }
    std.mem.sort([]const Value, rows.items, {}, struct {
        fn less(_: void, a: []const Value, b: []const Value) bool {
            return compareTuple(a, b) == .lt;
        }
    }.less);
    return .{ .names = names, .rows = rows.items };
}
fn answerText(gpa: Allocator, names: []const Text, row: []const Value) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (names, row, 0..) |name, value, i| {
        if (i > 0) try out.add(", ");
        try out.print("{s} = {s}", .{ name, try valueText(gpa, value) });
    }
    return out.bytes.items;
}
fn tupleAtom(gpa: Allocator, name: Text, values: []const Value) Error!Atom {
    const terms = try gpa.alloc(Term, values.len);
    for (terms, values) |*term, value| term.* = .{ .kind = .constant, .value = value };
    return .{ .name = name, .terms = terms };
}
fn plural(count: usize, singular: Text, multiple: Text) Text {
    return if (count == 1) singular else multiple;
}
const Database = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Builder,
    predicates: Predicates = .empty,
    rules: []const Rule = &.{},
    history: std.ArrayList(Snapshot) = .empty,
    nextNumber: usize = 1,
    fn save(self: *Database, line: usize) Error!void {
        var predicates: Predicates = .empty;
        var iterator = self.predicates.iterator();
        while (iterator.next()) |entry| {
            var predicate: Predicate = .{ .arity = entry.value_ptr.arity };
            var facts = entry.value_ptr.facts.iterator();
            while (facts.next()) |fact| try predicate.facts.put(self.gpa, fact.key_ptr.*, fact.value_ptr.*);
            try predicates.put(self.gpa, entry.key_ptr.*, predicate);
        }
        try self.history.append(self.gpa, .{ .predicates = predicates, .rules = try self.gpa.dupe(Rule, self.rules), .line = line });
    }
    fn checkPredicates(self: *Database, statement: Statement, clause: bool) Error!ArityMap {
        var result: ArityMap = .empty;
        var iterator = self.predicates.iterator();
        while (iterator.next()) |entry| try result.put(self.scratch, entry.key_ptr.*, entry.value_ptr.arity);
        for (try statementAtoms(self.scratch, statement)) |atom| {
            const expected = result.get(atom.name);
            if (expected == null and !clause) return bad(self.scratch, "unknown predicate {s}", .{atom.name});
            if (expected) |arity| if (arity != atom.terms.len) return bad(self.scratch, "arity mismatch for {s}: expected {d}, got {d}", .{ atom.name, arity, atom.terms.len });
            try result.put(self.scratch, atom.name, atom.terms.len);
        }
        return result;
    }
    fn getLevels(self: *Database) Error!Levels {
        var arities: ArityMap = .empty;
        var iterator = self.predicates.iterator();
        while (iterator.next()) |entry| try arities.put(self.scratch, entry.key_ptr.*, entry.value_ptr.arity);
        return (try stratification(self.scratch, arities, self.rules)).?;
    }
    fn computeModel(self: *Database) Error!Model {
        const levels = try self.getLevels();
        const count = if (levels.maximum) |maximum| maximum + 1 else 0;
        var result: Model = .{ .tuples = .empty, .levels = levels, .rounds = try self.scratch.alloc(usize, count), .added = try self.scratch.alloc(usize, count) };
        @memset(result.rounds, 0);
        @memset(result.added, 0);
        var predicates = self.predicates.iterator();
        while (predicates.next()) |entry| {
            var set: TupleSet = .empty;
            var facts = entry.value_ptr.facts.iterator();
            while (facts.next()) |fact| try set.put(self.scratch, fact.key_ptr.*, .{ .values = fact.value_ptr.* });
            try result.tuples.put(self.scratch, entry.key_ptr.*, set);
        }
        var serial: usize = 0;
        for (0..count) |level| while (true) {
            var pending: ModelTuples = .empty;
            var added: usize = 0;
            for (self.rules) |rule| {
                const head = rule.statement.head orelse continue;
                if (levels.values.get(head.name).? != level) continue;
                if (!pending.contains(head.name)) try pending.put(self.scratch, head.name, .empty);
                var evaluationArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer evaluationArena.deinit();
                for (try solutions(evaluationArena.allocator(), rule.statement.body, result.tuples, null)) |binding| {
                    const values = try atomValues(self.scratch, head, binding);
                    const key = try tupleKey(self.scratch, values);
                    if (result.tuples.get(head.name).?.contains(key) or pending.get(head.name).?.contains(key)) continue;
                    added += 1;
                    try pending.getPtr(head.name).?.put(self.scratch, key, .{ .values = values, .rule = rule.number });
                }
            }
            if (added == 0) break;
            serial += 1;
            result.rounds[level] += 1;
            result.added[level] += added;
            var sets = pending.iterator();
            while (sets.next()) |entry| {
                var tuples = entry.value_ptr.iterator();
                while (tuples.next()) |item| {
                    var tuple = item.value_ptr.*;
                    tuple.round = serial;
                    try result.tuples.getPtr(entry.key_ptr.*).?.put(self.scratch, item.key_ptr.*, tuple);
                }
            }
        };
        return result;
    }
    fn proof(self: *Database, name: Text, target: Tuple, depth: usize, model: Model) Error!void {
        const indent = try self.scratch.alloc(u8, depth * 2);
        @memset(indent, ' ');
        const prefix = try std.fmt.allocPrint(self.scratch, "{s}{s}", .{ indent, try atomText(self.scratch, try tupleAtom(self.scratch, name, target.values), null) });
        if (target.round == 0) {
            try self.out.line("{s} [fact]", .{prefix});
            return;
        }
        for (self.rules) |rule| {
            const head = rule.statement.head orelse continue;
            if (!sameText(head.name, name)) continue;
            const names = try variables(self.scratch, try allTerms(self.scratch, rule.statement));
            var selected: ?Assignment = null;
            for (try solutions(self.scratch, rule.statement.body, model.tuples, target.round)) |binding| {
                if (compareTuple(try atomValues(self.scratch, head, binding), target.values) != .eq) continue;
                var better = selected == null;
                if (selected) |previous| for (names) |variable| {
                    const order = compareValue(binding.get(variable).?, previous.get(variable).?);
                    if (order != .eq) {
                        better = order == .lt;
                        break;
                    }
                };
                if (better) selected = binding;
            }
            const binding = selected orelse continue;
            try self.out.line("{s} [rule {d}]", .{ prefix, rule.number });
            for (rule.statement.body) |literal| {
                if (literal.kind == .positive) {
                    for (try orderedTuples(self.scratch, model.tuples.get(literal.atom.name).?)) |tuple| {
                        if (tuple.round >= target.round) continue;
                        if (try matchAtom(self.scratch, literal.atom, tuple.values, binding) != null) {
                            try self.proof(literal.atom.name, tuple, depth + 1, model);
                            break;
                        }
                    }
                } else try self.out.line("{s}  {s}", .{ indent, try literalText(self.scratch, literal, binding) });
            }
            return;
        }
    }
    fn execute(self: *Database, statement: Statement, line: usize) Error!void {
        const kind = statement.kind;
        if (kind == .fact or kind == .rule or kind == .constraint) {
            const arities = try self.checkPredicates(statement, true);
            try safety(self.scratch, statement);
            if (kind == .fact) {
                const head = statement.head.?;
                const values = try atomValues(self.gpa, head, .empty);
                const key = try tupleKey(self.gpa, values);
                if (self.predicates.get(head.name)) |predicate| if (predicate.facts.contains(key)) return;
                try self.save(line);
                if (!self.predicates.contains(head.name)) try self.predicates.put(self.gpa, head.name, .{ .arity = head.terms.len });
                try self.predicates.getPtr(head.name).?.facts.put(self.gpa, key, values);
                return;
            }
            const notation = try ruleText(self.scratch, statement);
            for (self.rules) |rule| if (sameText(try ruleText(self.scratch, rule.statement), notation)) return bad(self.scratch, "duplicate of rule {d}", .{rule.number});
            const candidate = try self.gpa.alloc(Rule, self.rules.len + 1);
            @memcpy(candidate[0..self.rules.len], self.rules);
            candidate[self.rules.len] = .{ .number = self.nextNumber, .statement = statement };
            if (kind == .rule and try stratification(self.scratch, arities, candidate) == null) return bad(self.scratch, "negative cycle through {s}", .{statement.head.?.name});
            try self.save(line);
            var iterator = arities.iterator();
            while (iterator.next()) |entry| if (!self.predicates.contains(entry.key_ptr.*)) try self.predicates.put(self.gpa, entry.key_ptr.*, .{ .arity = entry.value_ptr.* });
            self.rules = candidate;
            self.nextNumber += 1;
            const terms = try allTerms(self.scratch, statement);
            for (try variables(self.scratch, terms)) |name| {
                var occurrences: usize = 0;
                for (terms) |term| if (term.kind == .variable and sameText(term.name, name)) {
                    occurrences += 1;
                };
                if (occurrences == 1) try self.out.line("WARNING line {d}: singleton variable {s}", .{ line, name });
            }
            return;
        }
        if (kind == .undo) {
            const previous = self.history.pop() orelse return bad(self.scratch, "nothing to undo", .{});
            self.predicates = previous.predicates;
            self.rules = previous.rules;
            try self.out.line("undid line {d}", .{previous.line});
            return;
        }
        if (kind == .forget) {
            var found: ?usize = null;
            for (self.rules, 0..) |rule, i| if (rule.number == statement.number) {
                found = i;
                break;
            };
            const index = found orelse return bad(self.scratch, "no rule {d}", .{statement.number});
            try self.save(line);
            const next = try self.gpa.alloc(Rule, self.rules.len - 1);
            @memcpy(next[0..index], self.rules[0..index]);
            @memcpy(next[index..], self.rules[index + 1 ..]);
            self.rules = next;
            return;
        }
        if (kind == .listing) {
            if (statement.name.len > 0 and !self.predicates.contains(statement.name)) return bad(self.scratch, "unknown predicate {s}", .{statement.name});
            var found = false;
            for (self.rules) |rule| {
                if (statement.name.len > 0 and (rule.statement.head == null or !sameText(rule.statement.head.?.name, statement.name))) continue;
                found = true;
                try self.out.line("{d}: {s}", .{ rule.number, try ruleText(self.scratch, rule.statement) });
            }
            if (!found) try self.out.line("no rules", .{});
            return;
        }
        if (kind == .strata) {
            const levels = try self.getLevels();
            const names = try sortedKeys(self.scratch, self.predicates);
            const maximum = levels.maximum orelse {
                try self.out.line("no predicates", .{});
                return;
            };
            for (0..maximum + 1) |level| {
                try self.out.print("stratum {d}: ", .{level});
                var first = true;
                for (names) |name| if (levels.values.get(name).? == level) {
                    if (!first) try self.out.add(", ");
                    first = false;
                    try self.out.print("{s}{s}", .{ name, if (levels.recursive.get(name).?) "*" else "" });
                };
                try self.out.add("\n");
            }
            return;
        }
        if (kind == .query or kind == .retract or kind == .why) {
            _ = try self.checkPredicates(statement, false);
            if (kind == .query) try safety(self.scratch, statement);
        }
        if (kind == .retract) {
            const head = statement.head.?;
            var removed: std.ArrayList(Text) = .empty;
            var facts = self.predicates.get(head.name).?.facts.iterator();
            while (facts.next()) |entry| if (try matchAtom(self.scratch, head, entry.value_ptr.*, .empty) != null) try removed.append(self.scratch, entry.key_ptr.*);
            if (removed.items.len == 0) return bad(self.scratch, "no matching facts", .{});
            try self.save(line);
            for (removed.items) |key| _ = self.predicates.getPtr(head.name).?.facts.remove(key);
            try self.out.line("{d} {s} retracted", .{ removed.items.len, plural(removed.items.len, "fact", "facts") });
            return;
        }
        if (kind == .why) for (statement.head.?.terms) |term| if (term.kind != .constant) return bad(self.scratch, "why needs a ground atom", .{});
        if (kind == .dump and !self.predicates.contains(statement.name)) return bad(self.scratch, "unknown predicate {s}", .{statement.name});
        const model = try self.computeModel();
        switch (kind) {
            .query => {
                const answers = try answerRows(self.scratch, statement, model);
                if (sameText(statement.aggregate, "count")) {
                    try self.out.line("{d}", .{answers.rows.len});
                } else if (sameText(statement.aggregate, "sum")) {
                    var column: usize = 0;
                    for (answers.names, 0..) |name, i| if (sameText(name, statement.variable)) {
                        column = i;
                        break;
                    };
                    var total: i64 = 0;
                    for (answers.rows) |row| {
                        if (row[column] != .integer) return bad(self.scratch, "non-integer value in sum", .{});
                        total += row[column].integer;
                    }
                    try self.out.line("{d}", .{total});
                } else if (inList(statement.aggregate, &.{ "min", "max" })) {
                    if (answers.rows.len == 0) {
                        try self.out.line("no answers", .{});
                    } else {
                        var column: usize = 0;
                        for (answers.names, 0..) |name, i| if (sameText(name, statement.variable)) {
                            column = i;
                            break;
                        };
                        var selected = answers.rows[0][column];
                        for (answers.rows) |row| {
                            const order = compareValue(row[column], selected);
                            if (sameText(statement.aggregate, "min") and order == .lt or sameText(statement.aggregate, "max") and order == .gt) selected = row[column];
                        }
                        try self.out.line("{s}", .{try valueText(self.scratch, selected)});
                    }
                } else if (answers.names.len == 0) {
                    try self.out.line("{s}", .{if (answers.rows.len > 0) "true." else "false."});
                } else {
                    for (answers.rows) |row| try self.out.line("{s}", .{try answerText(self.scratch, answers.names, row)});
                    try self.out.line("{d} {s}", .{ answers.rows.len, plural(answers.rows.len, "answer", "answers") });
                }
            },
            .dump => {
                const rows = try orderedTuples(self.scratch, model.tuples.get(statement.name).?);
                for (rows) |tuple| try self.out.line("{s}.", .{try atomText(self.scratch, try tupleAtom(self.scratch, statement.name, tuple.values), null)});
                try self.out.line("{d} {s}", .{ rows.len, plural(rows.len, "tuple", "tuples") });
            },
            .why => {
                const head = statement.head.?;
                const key = try tupleKey(self.scratch, try atomValues(self.scratch, head, .empty));
                if (model.tuples.get(head.name).?.get(key)) |tuple| {
                    try self.proof(head.name, tuple, 0, model);
                } else try self.out.line("false.", .{});
            },
            .check => {
                var found = false;
                for (self.rules) |rule| {
                    if (rule.statement.head != null) continue;
                    found = true;
                    const answers = try answerRows(self.scratch, rule.statement, model);
                    if (answers.rows.len == 0) {
                        try self.out.line("constraint {d}: ok", .{rule.number});
                    } else {
                        try self.out.line("constraint {d}: {d} {s}", .{ rule.number, answers.rows.len, plural(answers.rows.len, "violation", "violations") });
                        if (answers.names.len > 0) for (answers.rows) |row| try self.out.line("  {s}", .{try answerText(self.scratch, answers.names, row)});
                    }
                }
                if (!found) try self.out.line("no constraints", .{});
            },
            .predicates => {
                const names = try sortedKeys(self.scratch, self.predicates);
                if (names.len == 0) try self.out.line("no predicates", .{});
                for (names) |name| {
                    var count: usize = 0;
                    for (self.rules) |rule| if (rule.statement.head != null and sameText(rule.statement.head.?.name, name)) {
                        count += 1;
                    };
                    const predicate = self.predicates.get(name).?;
                    try self.out.line("{s}/{d}: facts {d}, rules {d}, tuples {d}", .{ name, predicate.arity, predicate.facts.count(), count, model.tuples.get(name).?.count() });
                }
            },
            .stats => {
                var facts: usize = 0;
                var rules: usize = 0;
                var constraints: usize = 0;
                var tuples: usize = 0;
                var predicates = self.predicates.iterator();
                while (predicates.next()) |entry| {
                    facts += entry.value_ptr.facts.count();
                    tuples += model.tuples.get(entry.key_ptr.*).?.count();
                }
                for (self.rules) |rule| {
                    if (rule.statement.head == null) {
                        constraints += 1;
                    } else rules += 1;
                }
                try self.out.line("facts {d}, rules {d}, constraints {d}, tuples {d}", .{ facts, rules, constraints, tuples });
                for (model.rounds, model.added, 0..) |rounds, added, i| try self.out.line("stratum {d}: rounds {d}, new {d}", .{ i, rounds, added });
                for (self.rules) |rule| {
                    if (rule.statement.head == null) continue;
                    var count: usize = 0;
                    var sets = model.tuples.valueIterator();
                    while (sets.next()) |set| {
                        var iterator = set.valueIterator();
                        while (iterator.next()) |tuple| if (tuple.round > 0 and tuple.rule == rule.number) {
                            count += 1;
                        };
                    }
                    try self.out.line("rule {d}: new {d}", .{ rule.number, count });
                }
            },
            else => unreachable,
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    var unused: Builder = .{ .gpa = gpa };
    var database: Database = .{ .gpa = gpa, .scratch = gpa, .out = &unused };
    var lineNumber: usize = 0;
    while (lines.next()) |raw| {
        lineNumber += 1;
        const source = std.mem.trimEnd(u8, raw, "\r");
        var commandArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer commandArena.deinit();
        const scratch = commandArena.allocator();
        var out: Builder = .{ .gpa = scratch };
        database.scratch = scratch;
        database.out = &out;
        const tokens = lexical(gpa, source) catch |err| {
            if (err != error.Invalid) return err;
            try out.line("ERROR line {d}: {s}", .{ lineNumber, failure });
            try output.interface.writeAll(out.bytes.items);
            continue;
        };
        if (tokens.len == 0) continue;
        var parser: Parser = .{ .gpa = gpa, .tokens = tokens };
        const statement = parser.readStatement() catch |err| {
            if (err != error.Invalid) return err;
            try out.line("ERROR line {d}: {s}", .{ lineNumber, failure });
            try output.interface.writeAll(out.bytes.items);
            continue;
        };
        if (statement.kind == .halt) break;
        database.execute(statement, lineNumber) catch |err| {
            if (err != error.Invalid) return err;
            out.bytes.clearRetainingCapacity();
            try out.line("ERROR line {d}: {s}", .{ lineNumber, failure });
        };
        try output.interface.writeAll(out.bytes.items);
    }
    try output.interface.flush();
}
