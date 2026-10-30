const std = @import("std");
const s = @import("schema_io.zig");
pub const Literal = struct { kind: s.Type, value: s.Value };
pub const Condition = struct { operation: []const u8, name: []const u8 = "", column: ?usize = null,
     literals: std.ArrayList(Literal) = .empty, left: ?*Condition = null, right: ?*Condition = null };
pub const Item = struct { operation: []const u8, name: []const u8, column: ?usize = null };
pub const Query = struct { items: std.ArrayList(Item) = .empty, star: bool = false, condition: ?*Condition = null,
     group_name: ?[]const u8 = null, order_name: ?[]const u8 = null, group: ?usize = null,
     order: ?usize = null, limit: ?usize = null, descending: bool = false, aggregate: bool = false,
     needed: u16 = 0, condition_columns: u16 = 0, headers: s.Names = &.{} };
fn node(operation: []const u8, left: ?*Condition, right: ?*Condition) *Condition {
    return s.create(Condition, .{ .operation = operation, .left = left, .right = right });
}
const Parser = struct {
    tokens: s.Names,
    position: usize = 0,
    fn peek(self: Parser) []const u8 {
        return if (self.position < self.tokens.len) self.tokens[self.position] else "";
    }
    fn take(self: *Parser) []const u8 {
        const value = self.tokens[self.position];
        self.position += 1;
        return value;
    }
    fn accept(self: *Parser, token: []const u8) bool {
        if (!s.eq(self.peek(), token)) return false;
        self.position += 1;
        return true;
    }
    fn item(self: *Parser) Item {
        const name = self.take();
        if (name[0] >= 'a' and name[0] <= 'z') return .{ .operation = "COLUMN", .name = name };
        _ = self.take();
        const operation = if (self.accept("DISTINCT")) "COUNT_DISTINCT" else name;
        const column = if (self.accept("*")) "" else self.take();
        _ = self.take();
        return .{ .operation = operation, .name = column };
    }
    fn literal(self: *Parser) Literal {
        const token = self.take();
        if (token[0] == '\'') return .{ .kind = .string, .value = .{ .string = token[1 .. token.len - 1] } };
        if (s.eq(token, "TRUE") or s.eq(token, "FALSE")) return .{ .kind = .boolean, .value = .{ .integer = @intFromBool(s.eq(token,
             "TRUE")) } };
        return .{ .kind = .integer, .value = .{ .integer = s.number(token) } };
    }
    fn condition(self: *Parser) *Condition {
        var tree = self.conjunction();
        while (self.accept("OR")) tree = node("OR", tree, self.conjunction());
        return tree;
    }
    fn conjunction(self: *Parser) *Condition {
        var tree = self.negation();
        while (self.accept("AND")) tree = node("AND", tree, self.negation());
        return tree;
    }
    fn negation(self: *Parser) *Condition {
        if (self.accept("NOT")) return node("NOT", self.negation(), null);
        if (self.accept("(")) {
            const tree = self.condition();
            _ = self.take();
            return tree;
        }
        const name = self.take();
        const operation = self.take();
        const tree = node(operation, null, null);
        tree.name = name;
        if (s.eq(operation, "IS")) {
            tree.operation = if (self.accept("NOT")) "IS_NOT_NULL" else "IS_NULL";
            _ = self.take();
        } else if (s.eq(operation, "BETWEEN")) {
            s.append(Literal, &tree.literals, self.literal());
            _ = self.take();
            s.append(Literal, &tree.literals, self.literal());
        } else if (s.eq(operation, "IN")) {
            _ = self.take();
            s.append(Literal, &tree.literals, self.literal());
            while (self.accept(",")) s.append(Literal, &tree.literals, self.literal());
            _ = self.take();
        } else s.append(Literal, &tree.literals, self.literal());
        return tree;
    }
    fn parse(self: *Parser) Query {
        var out: Query = .{};
        _ = self.take();
        out.star = self.accept("*");
        if (!out.star) {
            s.append(Item, &out.items, self.item());
            while (self.accept(",")) s.append(Item, &out.items, self.item());
        }
        if (self.accept("WHERE")) out.condition = self.condition();
        if (self.accept("GROUP")) {
            _ = self.take();
            out.group_name = self.take();
        }
        if (self.accept("ORDER")) {
            _ = self.take();
            out.order_name = self.take();
            out.descending = self.accept("DESC");
            if (!out.descending) _ = self.accept("ASC");
        }
        if (self.accept("LIMIT")) out.limit = s.u(s.number(self.take()));
        return out;
    }
};
fn letter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
pub fn parse(source: []const u8) Query {
    var tokens: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < source.len) {
        if (source[i] == ' ') {
            i += 1;
            continue;
        }
        const start = i;
        i += 1;
        const character = source[start];
        if (character == '\'') {
            while (source[i] != '\'') : (i += 1) {}
            i += 1;
        } else if (letter(character) or character == '_') {
            while (i < source.len and (letter(source[i]) or (source[i] >= '0' and source[i] <= '9') or source[i] == '_')) : (i += 1) {}
        } else if ((character >= '0' and character <= '9') or character == '-') {
            while (i < source.len and source[i] >= '0' and source[i] <= '9') : (i += 1) {}
        } else if (i < source.len and ((character == '<' and (source[i] == '=' or source[i] == '>')) or (character == '>' and source[i] == '='))) i += 1;
        s.append([]const u8, &tokens, source[start..i]);
    }
    var parser: Parser = .{ .tokens = tokens.items };
    return parser.parse();
}
