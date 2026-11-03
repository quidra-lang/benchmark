const std = @import("std");
const d = @import("doc_builder.zig");
const l = @import("lexer.zig");
pub const Kind = enum { atom, paren, unary, binary, conditional, call, index, member, list, parameter, dimension, declaration, function, block, simple, assignment, return_stmt, transfer, while_stmt, for_stmt, if_stmt, switch_stmt, clause, empty };
pub const Node = struct { kind: Kind, first: usize, last: usize, tokens: []const usize = &.{}, children: []const *Node = &.{} };
fn make(kind: Kind, first: usize, last: usize, tokens: []const usize, children: []const *Node) *Node { const ts = d.alloc(usize, tokens.len); @memcpy(ts, tokens); const cs = d.alloc(*Node, children.len); @memcpy(cs, children); return d.create(Node, .{ .kind = kind, .first = first, .last = last, .tokens = ts, .children = cs }); }
pub fn precedence(s: []const u8) usize { const groups = [_][]const []const u8{ &.{"||"}, &.{"&&"}, &.{"==", "!="}, &.{"<", "<=", ">", ">="}, &.{"+", "-"}, &.{"*", "/", "%"} }; for (groups, 1..) |g, p| for (g) |x| { if (d.eq(s, x)) return p; }; return 0; }
pub fn level(n: *const Node) usize { return switch (n.kind) { .conditional => 0, .binary => n.tokens[1], .unary => 7, else => 8 }; }
pub const Parser = struct {
    tokens: []l.Token, at: usize = 0, failure: ?l.Failure = null,
    const Error = error{Syntax};
    fn is(self: *Parser, s: []const u8) bool { return d.eq(self.tokens[self.at].value, s); }
    fn bad(self: *Parser, expected: []const u8) Error { const token = self.tokens[self.at]; self.failure = .{ .position = token.position, .message = d.fmt("expected {s}, found {s}", .{expected, if (token.kind == .end) "end of file" else d.fmt("'{s}'", .{token.value})}) }; return error.Syntax; }
    fn take(self: *Parser, s: []const u8) Error!usize { if (!self.is(s)) return self.bad(d.fmt("'{s}'", .{s})); const i = self.at; self.at += 1; return i; }
    fn identifier(self: *Parser) Error!usize { if (self.tokens[self.at].kind != .identifier) return self.bad("identifier"); const i = self.at; self.at += 1; return i; }
    fn typeToken(self: *Parser) Error!usize { if (!l.typeName(self.tokens[self.at].value)) return self.bad("type"); const i = self.at; self.at += 1; return i; }
    pub fn program(self: *Parser) Error![]const *Node {
        var items: std.ArrayList(*Node) = .empty;
        while (self.tokens[self.at].kind != .end) { self.tokens[self.at].allowed = true; const typ = try self.typeToken(); const name = try self.identifier();
            if (self.is("(")) { const params = try self.list(.parameter, "(", ")", false); const function_body = try self.block(); d.append(*Node, &items, make(.function, typ, function_body.last, &.{typ, name}, &.{params, function_body})); }
            else d.append(*Node, &items, try self.declaration(typ, name, true));
        }
        return items.items;
    }
    fn declaration(self: *Parser, typ: usize, name: usize, semicolon: bool) Error!*Node {
        var children: std.ArrayList(*Node) = .empty; var tokens: std.ArrayList(usize) = .empty; d.append(usize, &tokens, typ); d.append(usize, &tokens, name);
        while (self.is("[")) { const open = try self.take("["); var c: std.ArrayList(*Node) = .empty; if (!self.is("]")) d.append(*Node, &c, try self.expression()); const close = try self.take("]"); d.append(*Node, &children, make(.dimension, open, close, &.{open, close}, c.items)); }
        if (self.is("=")) { d.append(usize, &tokens, try self.take("=")); d.append(*Node, &children, try self.initializer()); }
        if (semicolon) d.append(usize, &tokens, try self.take(";"));
        return make(.declaration, typ, self.at - 1, tokens.items, children.items);
    }
    fn initializer(self: *Parser) Error!*Node { return if (self.is("{")) self.list(.list, "{", "}", true) else self.expression(); }
    fn list(self: *Parser, element_kind: Kind, opening: []const u8, closing: []const u8, trailing: bool) Error!*Node {
        const start = try self.take(opening); var items: std.ArrayList(*Node) = .empty; var tokens: std.ArrayList(usize) = .empty; d.append(usize, &tokens, start);
        if (!self.is(closing)) while (true) {
            self.tokens[self.at].allowed = true;
            const element = if (element_kind == .parameter) blk: { const typ = try self.typeToken(); const name = try self.identifier(); var pairs: std.ArrayList(usize) = .empty; d.append(usize, &pairs, typ); d.append(usize, &pairs, name); while (self.is("[")) { d.append(usize, &pairs, try self.take("[")); d.append(usize, &pairs, try self.take("]")); } break :blk make(.parameter, typ, self.at - 1, pairs.items, &.{}); } else if (trailing) try self.initializer() else try self.expression();
            d.append(*Node, &items, element); if (!self.is(",")) break;
            const comma = try self.take(","); d.append(usize, &tokens, comma);
            if (trailing and self.is(closing)) { self.tokens[comma].trailing_comma = true; break; }
        };
        d.append(usize, &tokens, try self.take(closing)); return make(.list, start, self.at - 1, tokens.items, items.items);
    }
    fn block(self: *Parser) Error!*Node {
        const start = try self.take("{"); var items: std.ArrayList(*Node) = .empty;
        while (!self.is("}") and self.tokens[self.at].kind != .end) { self.tokens[self.at].allowed = true; d.append(*Node, &items, try self.statement()); }
        self.tokens[self.at].allowed = true; const close = try self.take("}"); return make(.block, start, close, &.{start, close}, items.items);
    }
    fn body(self: *Parser) Error!*Node { if (!self.is("{")) self.tokens[self.at].allowed = true; return self.statement(); }
    fn simple(self: *Parser) Error!*Node {
        const left = try self.expression(); for ([_][]const u8{ "=", "+=", "-=", "*=", "/=", "%=" }) |op| if (self.is(op)) { const token = try self.take(op); const right = try self.expression(); return make(.assignment, left.first, right.last, &.{token}, &.{left, right}); };
        return make(.simple, left.first, left.last, &.{}, &.{left});
    }
    fn statement(self: *Parser) Error!*Node {
        if (self.is("{")) return self.block();
        if (l.typeName(self.tokens[self.at].value)) { const typ = try self.typeToken(); const name = try self.identifier(); return self.declaration(typ, name, true); }
        const start = self.at;
        if (self.is("if") or self.is("while") or self.is("for") or self.is("switch")) {
            const word = self.tokens[self.at].value; self.at += 1; const open = try self.take("("); var tokens: std.ArrayList(usize) = .empty; var children: std.ArrayList(*Node) = .empty; d.append(usize, &tokens, start); d.append(usize, &tokens, open);
            if (d.eq(word, "for")) {
                var initial = make(.empty, self.at, self.at, &.{}, &.{});
                if (!self.is(";")) { if (l.typeName(self.tokens[self.at].value)) { const typ = try self.typeToken(); const name = try self.identifier(); initial = try self.declaration(typ, name, false); } else initial = try self.simple(); }
                d.append(*Node, &children, initial); d.append(usize, &tokens, try self.take(";"));
                d.append(*Node, &children, if (self.is(";")) make(.empty, self.at, self.at, &.{}, &.{}) else try self.expression()); d.append(usize, &tokens, try self.take(";"));
                d.append(*Node, &children, if (self.is(")")) make(.empty, self.at, self.at, &.{}, &.{}) else try self.simple());
            } else d.append(*Node, &children, try self.expression());
            d.append(usize, &tokens, try self.take(")"));
            if (d.eq(word, "switch")) {
                d.append(usize, &tokens, try self.take("{"));
                while (self.is("case") or self.is("default")) {
                    self.tokens[self.at].allowed = true; const label = self.at; self.at += 1; var cc: std.ArrayList(*Node) = .empty;
                    if (d.eq(self.tokens[label].value, "case")) d.append(*Node, &cc, try self.expression()); const colon = try self.take(":");
                    while (!self.is("case") and !self.is("default") and !self.is("}") and self.tokens[self.at].kind != .end) { self.tokens[self.at].allowed = true; d.append(*Node, &cc, try self.statement()); }
                    d.append(*Node, &children, make(.clause, label, self.at - 1, &.{label, colon}, cc.items));
                }
                self.tokens[self.at].allowed = true; d.append(usize, &tokens, try self.take("}")); return make(.switch_stmt, start, self.at - 1, tokens.items, children.items);
            }
            d.append(*Node, &children, try self.body());
            if (d.eq(word, "if") and self.is("else")) { d.append(usize, &tokens, try self.take("else")); d.append(*Node, &children, if (self.is("if")) try self.statement() else try self.body()); }
            return make(if (d.eq(word, "if")) .if_stmt else if (d.eq(word, "while")) .while_stmt else .for_stmt, start, self.at - 1, tokens.items, children.items);
        }
        if (self.is("return") or self.is("break") or self.is("continue")) {
            const returning = self.is("return"); self.at += 1; var children: std.ArrayList(*Node) = .empty; if (returning and !self.is(";")) d.append(*Node, &children, try self.expression()); const semi = try self.take(";"); return make(if (returning) .return_stmt else .transfer, start, semi, &.{start, semi}, children.items);
        }
        const value = try self.simple(); const semi = try self.take(";"); return make(.simple, start, semi, &.{semi}, &.{value});
    }
    fn expression(self: *Parser) Error!*Node { const cond = try self.binary(1); if (!self.is("?")) return cond; const question = try self.take("?"); const yes = try self.expression(); const colon = try self.take(":"); const no = try self.expression(); return make(.conditional, cond.first, no.last, &.{question, colon}, &.{cond, yes, no}); }
    fn binary(self: *Parser, k: usize) Error!*Node { if (k == 7) return self.unary(); var left = try self.binary(k + 1); while (precedence(self.tokens[self.at].value) == k) { const op = self.at; self.at += 1; const right = try self.binary(k + 1); left = make(.binary, left.first, right.last, &.{op, k}, &.{left, right}); } return left; }
    fn unary(self: *Parser) Error!*Node {
        if (self.is("-") or self.is("!")) { const op = self.at; self.at += 1; const operand = try self.unary(); return make(.unary, op, operand.last, &.{op}, &.{operand}); }
        var target: *Node = undefined;
        if (self.is("(")) { const open = try self.take("("); const value = try self.expression(); const close = try self.take(")"); target = make(.paren, open, close, &.{open, close}, &.{value}); }
        else { const token = self.tokens[self.at]; if (token.kind != .identifier and token.kind != .number and token.kind != .string and !self.is("true") and !self.is("false")) return self.bad("expression"); const at = self.at; self.at += 1; target = make(.atom, at, at, &.{at}, &.{}); }
        while (true) {
            if (self.is("(")) { const args = try self.list(.atom, "(", ")", false); target = make(.call, target.first, args.last, &.{}, &.{target, args}); }
            else if (self.is("[")) { const open = try self.take("["); const index = try self.expression(); const close = try self.take("]"); target = make(.index, target.first, close, &.{open, close}, &.{target, index}); }
            else if (self.is(".")) { const dot = try self.take("."); const name = try self.identifier(); target = make(.member, target.first, name, &.{dot, name}, &.{target}); }
            else break;
        }
        return target;
    }
};
