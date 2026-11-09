const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}

pub const Names = []const []const u8;
pub fn join(values: Names, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}
pub fn splitBy(value: []const u8, separator: []const u8) Names {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, value, start, separator)) |end| {
        append([]const u8, &out, value[start..end]);
        start = end + separator.len;
    }
    append([]const u8, &out, value[start..]);
    return out.items;
}
pub const Value = union(enum) { integer: i64, string: []const u8, boolean: bool, bag: Names, failure: []const u8 };
pub const Attributes = std.StringHashMapUnmanaged(Value);
pub fn set(values: *Attributes, name: []const u8, value: Value) void {
    values.put(allocator, name, value) catch @panic("allocation failed");
}
pub const Expression = struct { operation: []const u8, literal: Value = .{ .boolean = false },
     arguments: std.ArrayList(*Expression) = .empty };
fn node(operation: []const u8) *Expression {
    return create(Expression, .{ .operation = operation });
}
fn unaryNode(operation: []const u8, a: *Expression) *Expression {
    const out = node(operation);
    append(*Expression, &out.arguments, a);
    return out;
}
fn binaryNode(operation: []const u8, a: *Expression, b: *Expression) *Expression {
    const out = unaryNode(operation, a);
    append(*Expression, &out.arguments, b);
    return out;
}
const Parser = struct {
    tokens: Names,
    position: usize = 0,
    fn peek(self: Parser) []const u8 {
        return if (self.position < self.tokens.len) self.tokens[self.position] else "";
    }
    fn take(self: *Parser) []const u8 {
        const value = self.tokens[self.position];
        self.position += 1;
        return value;
    }
    fn joined(self: *Parser, comptime next: anytype, operations: Names) *Expression {
        var expression = next(self);
        while (true) {
            var accepted = false;
            for (operations) |op| if (eq(self.peek(), op)) {
                accepted = true;
                break;
            };
            if (!accepted) break;
            const op = self.take();
            expression = binaryNode(op, expression, next(self));
        }
        return expression;
    }
    fn disjunction(self: *Parser) *Expression {
        return self.joined(conjunction, &.{"or"});
    }
    fn conjunction(self: *Parser) *Expression {
        return self.joined(negation, &.{"and"});
    }
    fn negation(self: *Parser) *Expression {
        if (eq(self.peek(), "not")) {
            _ = self.take();
            return unaryNode("not", self.negation());
        }
        return self.comparison();
    }
    fn comparison(self: *Parser) *Expression {
        var expression = self.sum();
        const op = self.peek();
        if (eq(op, "==") or eq(op, "!=") or eq(op, "<") or eq(op, "<=") or eq(op, ">") or eq(op,
             ">=") or eq(op, "in")) {
            _ = self.take();
            expression = binaryNode(op, expression, self.sum());
        }
        return expression;
    }
    fn sum(self: *Parser) *Expression {
        return self.joined(product, &.{ "+", "-" });
    }
    fn product(self: *Parser) *Expression {
        return self.joined(unary, &.{"*"});
    }
    fn unary(self: *Parser) *Expression {
        if (eq(self.peek(), "-")) {
            _ = self.take();
            return unaryNode("-", self.unary());
        }
        return self.primary();
    }
    fn primary(self: *Parser) *Expression {
        const token = self.take();
        var out = node("literal");
        if (token[0] >= '0' and token[0] <= '9') out.literal = .{ .integer = number(token) } else if (token[0] == '"') out.literal = .{ .string = token[1 .. token.len - 1] } else if (eq(token,
             "true") or eq(token, "false")) out.literal = .{ .boolean = eq(token, "true") } else if (eq(token,
             "it")) out.operation = "it" else if (std.mem.indexOfScalar(u8, token, '.') != null) {
            out.operation = "attribute";
            out.literal = .{ .string = token };
        } else if (eq(token, "(")) {
            out = self.disjunction();
            _ = self.take();
        } else if (eq(token, "[")) {
            var values: std.ArrayList([]const u8) = .empty;
            while (!eq(self.peek(), "]")) {
                const item = self.take();
                append([]const u8, &values, item[1 .. item.len - 1]);
                if (!eq(self.peek(), "]")) _ = self.take();
            }
            _ = self.take();
            out.literal = .{ .bag = values.items };
        } else {
            out.operation = token;
            _ = self.take();
            while (!eq(self.peek(), ")")) {
                append(*Expression, &out.arguments, self.disjunction());
                if (!eq(self.peek(), ")")) _ = self.take();
            }
            _ = self.take();
        }
        return out;
    }
};
fn letter(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}
pub fn parse(source: []const u8) *Expression {
    var tokens: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < source.len) {
        if (source[i] == ' ') {
            i += 1;
            continue;
        }
        const start = i;
        i += 1;
        const c = source[start];
        if (c == '"') {
            while (source[i] != '"') : (i += 1) {}
            i += 1;
        } else if (letter(c) or (c >= '0' and c <= '9')) {
            const word = letter(c);
            while (i < source.len and ((source[i] >= '0' and source[i] <= '9') or (word and (letter(source[i]) or source[i] == '_' or source[i] == '.')))) : (i += 1) {}
        } else if (i < source.len and source[i] == '=' and (c == '=' or c == '!' or c == '<' or c == '>')) i += 1;
        append([]const u8, &tokens, source[start..i]);
    }
    var parser: Parser = .{ .tokens = tokens.items };
    return parser.disjunction();
}
