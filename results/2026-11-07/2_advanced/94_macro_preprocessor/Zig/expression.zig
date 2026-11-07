const std = @import("std");
const lex = @import("lexer.zig");
const defs = @import("definitions.zig");
const Node = struct { kind: enum { constant, identifier, unary, binary, conditional }, value: i64 = 0, text: lex.Text = "", left: ?*Node = null, right: ?*Node = null, third: ?*Node = null };
pub const Parser = struct {
    a: std.mem.Allocator, tokens: []const lex.Token, p: usize = 0, message: lex.Text = "",
    fn fail(p: *Parser, text: lex.Text) error{InvalidExpression} { p.message = text; return error.InvalidExpression; }
    fn peek(p: *Parser) lex.Text { return if (p.p < p.tokens.len) p.tokens[p.p].spelling else ""; }
    fn node(p: *Parser, n: Node) !*Node { const r = try p.a.create(Node); r.* = n; return r; }
    fn integer(p: *Parser, text: lex.Text) !i64 {
        var t = text; for ([_]lex.Text{"ll", "LL", "l", "L"}) |suffix| if (t.len > suffix.len and std.mem.endsWith(u8, t, suffix)) { t = t[0..t.len - suffix.len]; break; };
        var base: u8 = 10; if (std.mem.startsWith(u8, t, "0x") or std.mem.startsWith(u8, t, "0X")) { t = t[2..]; base = 16; } else if (t[0] == '0') base = 8;
        if (t.len > 0) { var valid = true; for (t) |c| { const digit = std.fmt.charToDigit(c, base) catch { valid = false; break; }; _ = digit; } if (valid) return std.fmt.parseInt(i64, t, base) catch unreachable; }
        return p.fail(try std.fmt.allocPrint(p.a, "invalid integer constant \"{s}\"", .{text}));
    }
    fn primary(p: *Parser) anyerror!*Node {
        if (p.p == p.tokens.len) return p.fail("expected value at end of expression"); const t = p.tokens[p.p]; p.p += 1;
        if (t.kind == .number) return p.node(.{ .kind = .constant, .value = try p.integer(t.spelling) });
        if (t.kind == .identifier) return p.node(.{ .kind = .identifier, .text = t.spelling });
        if (t.kind == .character) {
            const inside = t.spelling[1..t.spelling.len - 1]; var value: ?i64 = null;
            if (inside.len == 1 and inside[0] != '\\' and inside[0] != '\'') value = inside[0];
            if (inside.len == 2 and inside[0] == '\\') value = switch (inside[1]) { 'n' => 10, 't' => 9, '\\' => 92, '\'' => 39, '"' => 34, '0' => 0, else => null };
            return if (value) |v| p.node(.{ .kind = .constant, .value = v }) else p.fail(try std.fmt.allocPrint(p.a, "invalid character constant {s}", .{t.spelling}));
        }
        if (lex.eq(t.spelling, "(")) { const n = try p.expression(); if (!lex.eq(p.peek(), ")")) return p.fail("missing ')' in expression"); p.p += 1; return n; }
        return p.fail(try std.fmt.allocPrint(p.a, "expected value before \"{s}\"", .{t.spelling}));
    }
    fn unary(p: *Parser) anyerror!*Node { const op = p.peek(); if (lex.eq(op, "+") or lex.eq(op, "-") or lex.eq(op, "!") or lex.eq(op, "~")) { p.p += 1; return p.node(.{ .kind = .unary, .text = op, .left = try p.unary() }); } return p.primary(); }
    fn precedence(op: lex.Text) usize { const levels = [_]lex.Text{"||", "&&", "|", "^", "&", "== !=", "< > <= >=", "<< >>", "+ -", "* / %"}; for (levels, 1..) |ops, i| { var it = std.mem.splitScalar(u8, ops, ' '); while (it.next()) |s| if (lex.eq(s, op)) return i; } return 0; }
    fn binary(p: *Parser, minimum: usize) anyerror!*Node { var left = try p.unary(); while (precedence(p.peek()) >= minimum) { const op = p.peek(); const level = precedence(op); p.p += 1; left = try p.node(.{ .kind = .binary, .text = op, .left = left, .right = try p.binary(level + 1) }); } return left; }
    fn expression(p: *Parser) anyerror!*Node { var left = try p.binary(1); if (lex.eq(p.peek(), "?")) { p.p += 1; const yes = try p.expression(); if (!lex.eq(p.peek(), ":")) return p.fail("'?' without following ':'"); p.p += 1; left = try p.node(.{ .kind = .conditional, .left = left, .right = yes, .third = try p.expression() }); } return left; }
    pub fn parse(p: *Parser, directive: lex.Text) !*Node { if (p.tokens.len == 0) return p.fail(try std.fmt.allocPrint(p.a, "#{s} with no expression", .{directive})); const n = try p.expression(); if (p.p != p.tokens.len) return p.fail(try std.fmt.allocPrint(p.a, "missing binary operator before \"{s}\"", .{p.peek()})); return n; }
};
pub fn evaluate(n: *Node, host: anytype, pos: defs.Position) anyerror!?i64 {
    if (n.kind == .constant) return n.value;
    if (n.kind == .identifier) { try host.diag(pos, "warning", try std.fmt.allocPrint(host.a, "identifier \"{s}\" evaluates to 0", .{n.text})); return 0; }
    const a = (try evaluate(n.left.?, host, pos)) orelse return null;
    if (n.kind == .unary) return if (lex.eq(n.text, "+")) a else if (lex.eq(n.text, "-")) -a else if (lex.eq(n.text, "!")) @intFromBool(a == 0) else -a - 1;
    if (n.kind == .conditional) return evaluate(if (a != 0) n.right.? else n.third.?, host, pos);
    const op = n.text;
    if (lex.eq(op, "&&") and a == 0) return 0; if (lex.eq(op, "||") and a != 0) return 1;
    const b = (try evaluate(n.right.?, host, pos)) orelse return null;
    if (lex.eq(op, "&&") or lex.eq(op, "||")) return @intFromBool(b != 0);
    if ((lex.eq(op, "/") or lex.eq(op, "%")) and b == 0) { try host.diag(pos, "error", "division by zero in #if"); return null; }
    if (lex.eq(op, "+")) return a + b; if (lex.eq(op, "-")) return a - b; if (lex.eq(op, "*")) return a * b; if (lex.eq(op, "/")) return @divTrunc(a, b); if (lex.eq(op, "%")) return @rem(a, b);
    if (lex.eq(op, "<<")) return a << @intCast(b); if (lex.eq(op, ">>")) return a >> @intCast(b); if (lex.eq(op, "&")) return a & b; if (lex.eq(op, "|")) return a | b; if (lex.eq(op, "^")) return a ^ b;
    return @intFromBool(if (lex.eq(op, "==")) a == b else if (lex.eq(op, "!=")) a != b else if (lex.eq(op, "<")) a < b else if (lex.eq(op, ">")) a > b else if (lex.eq(op, "<=")) a <= b else a >= b);
}
