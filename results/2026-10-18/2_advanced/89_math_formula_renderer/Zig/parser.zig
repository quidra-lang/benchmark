const std = @import("std");
const b = @import("boxes.zig");
const l = @import("lexer.zig");
pub const Node = struct { kind: []const u8, value: []const u8 = "", column: usize = 0, children: []const *Node = &.{}, sub: ?*Node = null, sup: ?*Node = null, left: []const u8 = "", right: []const u8 = "", right_column: usize = 0, rows: []const []const *Node = &.{} };
pub fn node(kind: []const u8, children: []const *Node) *Node { const c = b.alloc(*Node, children.len); @memcpy(c, children); return b.create(Node, .{ .kind = kind, .children = c }); }
pub fn collapse(nodes: []const *Node) *Node { return if (nodes.len == 1) nodes[0] else node("row", nodes); }
pub fn braceCheck(tokens: []const l.Token) ?l.Failure {
    var stack: std.ArrayList(usize) = .empty;
    for (tokens) |t| { if (b.eq(t.kind, "{")) b.append(usize, &stack, t.column) else if (b.eq(t.kind, "}")) { if (stack.pop() == null) return .{ .column = t.column, .message = "unmatched }" }; } }
    return if (stack.items.len > 0) .{ .column = stack.items[stack.items.len - 1], .message = "unclosed {" } else null;
}
pub const Parser = struct {
    tokens: []const l.Token, at: usize = 0, failure: ?l.Failure = null, tag: ?l.Token = null, label: ?l.Token = null,
    const Error = error{Parse};
    fn next(self: *Parser) l.Token { return self.tokens[self.at]; }
    fn is(self: *Parser, kind: []const u8) bool { return b.eq(self.next().kind, kind); }
    fn read(self: *Parser) l.Token { const t = self.next(); if (!self.is("eof")) self.at += 1; return t; }
    fn fail(self: *Parser, column: usize, comptime message: []const u8, args: anytype) Error { self.failure = .{ .column = column, .message = b.fmt(message, args) }; return error.Parse; }
    fn unexpected(self: *Parser) Error { const t = self.next(); const message: []const u8 = if (b.eq(t.kind, "right")) "unexpected \\right" else if (b.eq(t.kind, "end")) "unexpected \\end" else if (b.eq(t.kind, "&")) "misplaced &" else "misplaced \\\\"; return self.fail(t.column, "{s}", .{message}); }
    pub fn formula(self: *Parser) Error![]const *Node { const out = try self.elements(true, false); if (!self.is("eof")) return self.unexpected(); return out; }
    fn terminator(self: *Parser) bool { for ([_][]const u8{ "}", "&", "newline", "right", "end", "eof" }) |k| if (self.is(k)) return true; return false; }
    fn elements(self: *Parser, top: bool, index: bool) Error![]const *Node {
        var out: std.ArrayList(*Node) = .empty;
        while (!self.terminator() and !(index and self.is("symbol") and b.eq(self.next().value, "]"))) {
            if (self.is("tag") or self.is("label")) { const t = self.read(); if (!top) return self.fail(t.column, "misplaced \\{s}", .{t.kind}); const target = if (b.eq(t.kind, "tag")) &self.tag else &self.label; if (target.* != null) return self.fail(t.column, "duplicate \\{s}", .{t.kind}); target.* = t; }
            else b.append(*Node, &out, try self.element());
        }
        return out.items;
    }
    fn element(self: *Parser) Error!*Node {
        const base = if (self.is("^") or self.is("_")) node("row", &.{}) else try self.nucleus(); var sub: ?*Node = null; var sup: ?*Node = null;
        while (self.is("^") or self.is("_")) { const t = self.read(); const target = if (b.eq(t.kind, "^")) &sup else &sub; if (target.* != null) return self.fail(t.column, "double {s}", .{if (b.eq(t.kind, "^")) "superscript" else "subscript"}); target.* = try self.argument(t.kind); }
        if (sub == null and sup == null) return base; const out = node("script", &.{base}); out.sub = sub; out.sup = sup; return out;
    }
    fn argument(self: *Parser, name: []const u8) Error!*Node {
        for ([_][]const u8{ "identifier", "number", "symbol", "command", "text", "eqref", "{", "frac", "binom", "overset", "underset", "sqrt", "accent" }) |k| if (self.is(k)) return self.nucleus();
        return self.fail(self.next().column, "missing argument for {s}", .{name});
    }
    fn delimiter(self: *Parser) Error!l.Token {
        const t = self.read(); if (b.eq(t.kind, "symbol")) for ([_][]const u8{ "(", ")", "[", "]", "|", "." }) |s| if (b.eq(t.value, s)) return t;
        if (b.eq(t.kind, "command") and (b.eq(t.value, "\\{") or b.eq(t.value, "\\}"))) return t;
        return self.fail(t.column, "invalid delimiter", .{});
    }
    fn nucleus(self: *Parser) Error!*Node {
        const t = self.read();
        if (b.eq(t.kind, "{")) { const elements_list = try self.elements(false, false); if (!self.is("}")) return self.unexpected(); _ = self.read(); return collapse(elements_list); }
        if (b.eq(t.kind, "frac") or b.eq(t.kind, "binom") or b.eq(t.kind, "overset") or b.eq(t.kind, "underset")) { const a = try self.argument(b.fmt("\\{s}", .{t.kind})); const c = try self.argument(b.fmt("\\{s}", .{t.kind})); return node(t.kind, &.{a, c}); }
        if (b.eq(t.kind, "sqrt")) {
            var index: ?*Node = null;
            if (self.is("symbol") and b.eq(self.next().value, "[")) { const opening = self.read(); index = collapse(try self.elements(false, true)); if (!self.is("symbol") or !b.eq(self.next().value, "]")) return self.fail(opening.column, "missing ]", .{}); _ = self.read(); }
            const body = try self.argument("\\sqrt"); return if (index) |i| node("root", &.{i, body}) else node("sqrt", &.{body});
        }
        if (b.eq(t.kind, "accent")) { const body = try self.argument(b.fmt("\\{s}", .{t.value})); const out = node("accent", &.{body}); out.value = t.value; return out; }
        if (b.eq(t.kind, "left")) { const left = try self.delimiter(); const body = collapse(try self.elements(false, false)); if (!self.is("right")) return self.fail(t.column, "missing \\right", .{}); const right_token = self.read(); const right = try self.delimiter(); const out = node("delim", &.{body}); out.left = left.value; out.right = right.value; out.right_column = right_token.column; return out; }
        if (b.eq(t.kind, "begin")) {
            var rows: std.ArrayList([]const *Node) = .empty; var cells: std.ArrayList(*Node) = .empty;
            while (true) { b.append(*Node, &cells, collapse(try self.elements(false, false))); const end = self.read();
                if (b.eq(end.kind, "&")) continue;
                if (b.eq(end.kind, "newline")) { b.append([]const *Node, &rows, cells.items); cells = .empty; continue; }
                if (b.eq(end.kind, "end")) { if (!b.eq(t.value, end.value)) return self.fail(end.column, "mismatched \\end", .{}); b.append([]const *Node, &rows, cells.items); break; }
                return self.fail(t.column, "missing \\end", .{});
            }
            const last = rows.items[rows.items.len - 1]; if (rows.items.len > 1 and last.len == 1 and b.eq(last[0].kind, "row") and last[0].children.len == 0) _ = rows.pop();
            var width: usize = 0; for (rows.items) |row| width = @max(width, row.len);
            for (rows.items) |*row| if (row.len < width) { const filled = b.alloc(*Node, width); @memcpy(filled[0..row.len], row.*); for (row.len..width) |i| filled[i] = node("row", &.{}); row.* = filled; };
            const out = node("matrix", &.{}); out.value = t.value; out.rows = rows.items; return out;
        }
        return b.create(Node, .{ .kind = t.kind, .value = t.value, .column = t.column });
    }
};
