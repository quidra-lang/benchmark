const std = @import("std");
pub const Text = []const u8;
pub fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
pub const Kind = enum { identifier, number, character, string, header, punctuator, other, placemarker };
pub const Token = struct { spelling: Text, kind: Kind, line: i64 = 1, space: bool = false, hide: []const Text = &.{} };
pub const Line = struct { tokens: []Token, start: i64, end: i64 };
pub const Document = struct { lines: []const Line, physical: i64 };
pub fn one(text: Text) Token {
    const c = text[0]; var end: usize = 1; var kind: Kind = .other;
    if (std.ascii.isAlphabetic(c) or c == '_') { kind = .identifier; while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1; }
    else if (std.ascii.isDigit(c) or (c == '.' and text.len > 1 and std.ascii.isDigit(text[1]))) {
        kind = .number; while (end < text.len) { const x = text[end]; if (std.mem.indexOfScalar(u8, "eEpP", x) != null and end + 1 < text.len and (text[end + 1] == '+' or text[end + 1] == '-')) end += 2 else if (std.ascii.isAlphanumeric(x) or x == '_' or x == '.') end += 1 else break; }
    } else if (c == '\'' or c == '"') {
        var p: usize = 1; while (p < text.len and text[p] != 10) { if (text[p] == c) { end = p + 1; kind = if (c == '\'') .character else .string; break; } if (text[p] == '\\' and p + 1 < text.len and text[p + 1] != 10) p += 2 else p += 1; }
    }
    if (kind == .other) {
        const punct = [_]Text{"...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##"};
        for (punct) |s| if (std.mem.startsWith(u8, text, s)) { end = s.len; kind = .punctuator; break; };
        if (kind == .other and std.mem.indexOfScalar(u8, "[](){}.&*+-~!/%<>^|?:;=,#", c) != null) kind = .punctuator;
    }
    return .{ .spelling = text[0..end], .kind = kind };
}
pub fn single(text: Text) ?Token { if (text.len == 0 or std.mem.startsWith(u8, text, "//") or std.mem.startsWith(u8, text, "/*")) return null; const t = one(text); return if (t.spelling.len == text.len) t else null; }
pub fn lex(a: std.mem.Allocator, source: Text) !Document {
    var bytes: std.ArrayList(u8) = .empty; var positions: std.ArrayList(i64) = .empty; var physical: i64 = 1; var p: usize = 0;
    while (p < source.len) { if (source[p] == '\\' and p + 1 < source.len and source[p + 1] == 10) { p += 2; physical += 1; continue; } try bytes.append(a, source[p]); try positions.append(a, physical); if (source[p] == 10) physical += 1; p += 1; }
    var lines: std.ArrayList(Line) = .empty; var tokens: std.ArrayList(Token) = .empty; var start: i64 = 1; var space = true; p = 0;
    while (p < bytes.items.len) {
        const text = bytes.items; const c = text[p];
        if (c == ' ') { space = true; p += 1; continue; }
        if (c == 10) { try lines.append(a, .{ .tokens = tokens.items, .start = start, .end = positions.items[p] }); tokens = .empty; start = positions.items[p] + 1; space = true; p += 1; continue; }
        if (std.mem.startsWith(u8, text[p..], "/*")) { p += 2; while (!std.mem.startsWith(u8, text[p..], "*/")) p += 1; p += 2; space = true; continue; }
        if (std.mem.startsWith(u8, text[p..], "//")) { while (p < text.len and text[p] != 10) p += 1; space = true; continue; }
        var token = one(text[p..]);
        if (c == '<' and tokens.items.len == 2 and eq(tokens.items[0].spelling, "#") and eq(tokens.items[1].spelling, "include")) {
            var end = p + 1; while (end < text.len and text[end] != 10 and text[end] != '>') end += 1;
            if (end < text.len and text[end] == '>') token = .{ .spelling = text[p..end + 1], .kind = .header };
        }
        token.line = positions.items[p]; token.space = space; try tokens.append(a, token); p += token.spelling.len; space = false;
    }
    if (tokens.items.len > 0) try lines.append(a, .{ .tokens = tokens.items, .start = start, .end = physical });
    return .{ .lines = lines.items, .physical = physical - 1 };
}
pub fn render(a: std.mem.Allocator, tokens: []const Token, output: bool) !Text {
    var bytes: std.ArrayList(u8) = .empty;
    for (tokens, 0..) |t, i| {
        var sep = t.space;
        if (output and i > 0 and !sep) { const left = tokens[i - 1].spelling; const joined = try std.mem.concat(a, u8, &.{left, t.spelling}); sep = (eq(left, "/") and t.spelling.len > 0 and (t.spelling[0] == '/' or t.spelling[0] == '*')) or one(joined).spelling.len != left.len; }
        if (i > 0 and sep) try bytes.append(a, ' '); try bytes.appendSlice(a, t.spelling);
    }
    return bytes.items;
}
