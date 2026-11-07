const std = @import("std");
const terms = @import("terms.zig");
const Text = terms.Text;
const Term = terms.Term;
pub const symbols = "+-*/\\^<>=~:.?@#&$";
pub fn symbol(c: u8) bool { return std.mem.indexOfScalar(u8, symbols, c) != null; }
pub const Operator = struct { priority: usize, left: usize, right: usize };
pub fn infix(name: Text) ?Operator {
    if (terms.eq(name, ":-")) return .{ .priority = 1200, .left = 1199, .right = 1199 };
    if (terms.eq(name, ";")) return .{ .priority = 1100, .left = 1099, .right = 1100 };
    if (terms.eq(name, "->")) return .{ .priority = 1050, .left = 1049, .right = 1050 };
    if (terms.eq(name, ",")) return .{ .priority = 1000, .left = 999, .right = 1000 };
    for ([_]Text{"=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=.."}) |op| if (terms.eq(name, op)) return .{ .priority = 700, .left = 699, .right = 699 };
    if (terms.eq(name, "+") or terms.eq(name, "-")) return .{ .priority = 500, .left = 500, .right = 499 };
    for ([_]Text{"*", "/", "//", "mod", "rem"}) |op| if (terms.eq(name, op)) return .{ .priority = 400, .left = 400, .right = 399 }; return null;
}
pub fn prefix(name: Text) ?usize { return if (terms.eq(name, "\\+")) 900 else if (terms.eq(name, "-")) 200 else null; }
pub const Token = struct { kind: enum { integer, variable, name, quoted, punctuation, end, eof, invalid }, spelling: Text, name: Text = "", integer: i64 = 0, line: usize, column: usize, space: bool = true, index: usize = 0 };
pub const Variable = struct { name: Text, variable: *Term, count: usize = 0 };
fn tokenize(a: std.mem.Allocator, source: Text, column: usize) ![]const Token {
    var tokens: std.ArrayList(Token) = .empty; var p: usize = 0; var line: usize = 1; var col = column; var whitespace = true;
    while (p < source.len) {
        const c = source[p]; if (c == ' ' or c == 10) { if (c == 10) { line += 1; col = 1; } else col += 1; p += 1; whitespace = true; continue; }
        if (c == '%') { while (p < source.len and source[p] != 10) { p += 1; col += 1; } whitespace = true; continue; }
        var t: Token = .{ .kind = .name, .spelling = "", .line = line, .column = col, .space = whitespace, .index = tokens.items.len }; var end = p + 1;
        if (std.ascii.isDigit(c)) { while (end < source.len and std.ascii.isDigit(source[end])) end += 1; const number = std.fmt.parseInt(i64, source[p..end], 10) catch 2147483648; if (number > 2147483647) { t.kind = .invalid; t.name = "integer too large"; } else { t.kind = .integer; t.integer = number; } }
        else if (std.ascii.isAlphabetic(c) or c == '_') { while (end < source.len and (std.ascii.isAlphanumeric(source[end]) or source[end] == '_')) end += 1; t.kind = if (std.ascii.isLower(c)) .name else .variable; }
        else if (symbol(c)) { while (end < source.len and symbol(source[end])) end += 1; if (end == p + 1 and c == '.' and (end == source.len or source[end] == ' ' or source[end] == 10 or source[end] == '%')) t.kind = .end; }
        else if (c == '!' or c == ';') {}
        else if (std.mem.indexOfScalar(u8, ",|()[]", c) != null) t.kind = .punctuation
        else if (c == '\'') {
            var bytes: std.ArrayList(u8) = .empty; var incorrect = false; var closed = false;
            while (end < source.len and source[end] != 10) {
                if (source[end] == '\'') { if (end + 1 < source.len and source[end + 1] == '\'') { try bytes.append(a, '\''); end += 2; continue; } end += 1; closed = true; break; }
                if (source[end] == '\\') { if (end + 1 == source.len or source[end + 1] == 10) { end += 1; continue; } end += 1; const value: ?u8 = switch (source[end]) { 'n' => 10, 't' => 9, '\\' => 92, '\'' => 39, else => null }; if (value) |x| try bytes.append(a, x) else incorrect = true; end += 1; }
                else { try bytes.append(a, source[end]); end += 1; }
            }
            if (!closed) { t.kind = .invalid; t.name = "unterminated quoted atom"; } else if (incorrect) { t.kind = .invalid; t.name = "undefined escape sequence"; } else { t.kind = .quoted; t.name = bytes.items; }
        } else { t.kind = .invalid; t.name = try std.fmt.allocPrint(a, "illegal character '{c}'", .{c}); }
        t.spelling = source[p..end]; if (t.kind == .name or t.kind == .variable) t.name = t.spelling; try tokens.append(a, t); col += end - p; p = end; whitespace = false;
    }
    try tokens.append(a, .{ .kind = .eof, .spelling = "", .line = line, .column = col, .index = tokens.items.len }); return tokens.items;
}
pub const Reader = struct {
    a: std.mem.Allocator, tokens: []const Token, p: usize = 0, names: std.ArrayList(Variable) = .empty, issue: Token = undefined, message: Text = "",
    pub fn init(a: std.mem.Allocator, source: Text, column: usize) !Reader { return .{ .a = a, .tokens = try tokenize(a, source, column) }; }
    pub fn peek(r: *Reader) Token { return r.tokens[r.p]; }
    fn take(r: *Reader) Token { const t = r.peek(); r.p += 1; return t; }
    pub fn fail(r: *Reader, t: Token, explicit: ?Text) !noreturn { r.issue = t; r.message = explicit orelse switch (t.kind) { .invalid => t.name, .eof => "unexpected end of file", .end => "unexpected end of clause", .name => if (infix(t.name) != null) "operator priority clash" else try std.fmt.allocPrint(r.a, "unexpected \"{s}\"", .{t.spelling}), else => try std.fmt.allocPrint(r.a, "unexpected \"{s}\"", .{t.spelling}) }; return error.Syntax; }
    fn expect(r: *Reader, s: Text) !void { const t = r.take(); if (t.kind != .punctuation or !terms.eq(t.spelling, s)) try r.fail(t, null); }
    fn canStart(t: Token) bool { return switch (t.kind) { .integer, .variable, .quoted => true, .punctuation => terms.eq(t.spelling, "(") or terms.eq(t.spelling, "["), .name => infix(t.name) == null or prefix(t.name) != null, else => false }; }
    const Parsed = struct { term: *Term, priority: usize = 0 };
    fn primary(r: *Reader, limit: usize) anyerror!Parsed {
        const t = r.take();
        switch (t.kind) {
            .integer => return .{ .term = try terms.integer(r.a, t.integer) },
            .variable => {
                if (!terms.eq(t.name, "_")) for (r.names.items) |*v| { if (terms.eq(v.name, t.name)) { v.count += 1; return .{ .term = v.variable }; } };
                const v = try terms.variable(r.a); try r.names.append(r.a, .{ .name = t.name, .variable = v, .count = 1 }); return .{ .term = v };
            },
            .punctuation => {
                if (terms.eq(t.spelling, "(")) { const value = try r.term(1200); try r.expect(")"); return .{ .term = value.term }; }
                if (terms.eq(t.spelling, "[")) {
                    if (terms.eq(r.peek().spelling, "]")) { _ = r.take(); return .{ .term = try terms.atom(r.a, "[]") }; }
                    var elements: std.ArrayList(*Term) = .empty; try elements.append(r.a, (try r.term(999)).term); while (terms.eq(r.peek().spelling, ",")) { _ = r.take(); try elements.append(r.a, (try r.term(999)).term); }
                    var tail: ?*Term = null; if (terms.eq(r.peek().spelling, "|")) { _ = r.take(); tail = (try r.term(999)).term; } try r.expect("]"); return .{ .term = try terms.list(r.a, elements.items, tail) };
                }
            },
            .name, .quoted => {
                const next = r.peek(); if (next.kind == .punctuation and terms.eq(next.spelling, "(") and !next.space) { _ = r.take(); var args: std.ArrayList(*Term) = .empty; try args.append(r.a, (try r.term(999)).term); while (terms.eq(r.peek().spelling, ",")) { _ = r.take(); try args.append(r.a, (try r.term(999)).term); } try r.expect(")"); return .{ .term = try terms.compound(r.a, t.name, args.items) }; }
                if (t.kind == .name and terms.eq(t.name, "-") and next.kind == .integer and !next.space) { _ = r.take(); return .{ .term = try terms.integer(r.a, -next.integer) }; }
                if (t.kind == .name) if (prefix(t.name)) |priority| { if (canStart(next)) { if (priority > limit) try r.fail(t, "operator priority clash"); const x = try r.term(priority); return .{ .term = try terms.compound(r.a, t.name, &.{x.term}), .priority = priority }; } };
                return .{ .term = try terms.atom(r.a, t.name) };
            },
            else => {},
        }
        try r.fail(t, null);
    }
    fn term(r: *Reader, limit: usize) anyerror!Parsed {
        var left = try r.primary(limit);
        while (true) {
            const t = r.peek(); if (t.kind != .name and !(t.kind == .punctuation and terms.eq(t.spelling, ","))) break; const op = infix(if (t.kind == .name) t.name else t.spelling) orelse break;
            if (op.priority > limit or left.priority > op.left) break; _ = r.take(); const right = try r.term(op.right); left = .{ .term = try terms.compound(r.a, if (t.kind == .name) t.name else t.spelling, &.{left.term, right.term}), .priority = op.priority };
        }
        return left;
    }
    pub fn clause(r: *Reader, query: bool) !*Term { r.names = .empty; const parsed = try r.term(1200); const end = r.take(); if (end.kind != .end) try r.fail(end, null); if (query and r.peek().kind != .eof) try r.fail(r.peek(), null); return parsed.term; }
};
