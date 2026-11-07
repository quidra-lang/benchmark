const std = @import("std");
const v = @import("values_fields.zig");
pub const Position = struct { line: usize = 1, column: usize = 1 };
pub const Token = struct { kind: enum { number, string, name, function_name, keyword, builtin, symbol, newline, eof }, spelling: v.Text, value: v.Value = .{}, position: Position };
pub fn member(s: v.Text, words: v.Text) bool { var it = std.mem.splitScalar(u8, words, ' '); while (it.next()) |w| if (v.eq(s, w)) return true; return false; }
pub const Lexer = struct {
    a: std.mem.Allocator, source: v.Text, issue: Position = .{},
    pub fn tokenize(l: *Lexer) ![]const Token {
        var tokens: std.ArrayList(Token) = .empty; var p: usize = 0; var pos: Position = .{};
        while (p < l.source.len) {
            const s = l.source; const c = s[p]; const start = pos;
            if (c == ' ') { p += 1; pos.column += 1; continue; }
            if (c == '\\' and p + 1 < s.len and s[p + 1] == 10) { p += 2; pos.line += 1; pos.column = 1; continue; }
            if (c == '#') { while (p < s.len and s[p] != 10) { p += 1; pos.column += 1; } continue; }
            if (c == 10) { try tokens.append(l.a, .{ .kind = .newline, .spelling = "\n", .position = pos }); p += 1; pos.line += 1; pos.column = 1; continue; }
            var end = p + 1; var token: Token = .{ .kind = .symbol, .spelling = "", .position = start };
            if (std.ascii.isDigit(c)) { while (end < s.len and std.ascii.isDigit(s[end])) end += 1; token.kind = .number; token.value = v.Value.number(try std.fmt.parseInt(i64, s[p..end], 10)); }
            else if (std.ascii.isAlphabetic(c) or c == '_') {
                while (end < s.len and (std.ascii.isAlphanumeric(s[end]) or s[end] == '_')) end += 1; const word = s[p..end];
                token.kind = if (member(word, "BEGIN END function if else while for do break continue next exit return delete in getline print printf")) .keyword else if (member(word, "length substr index split sprintf toupper tolower close int")) .builtin else if (end < s.len and s[end] == '(') .function_name else .name;
            } else if (c == '"') {
                var bytes: std.ArrayList(u8) = .empty;
                while (end < s.len and s[end] != '"') {
                    if (s[end] == 10) { l.issue = start; return error.Syntax; }
                    if (s[end] == '\\') { if (end + 1 == s.len or std.mem.indexOfScalar(u8, "nt\\\"/", s[end + 1]) == null) { l.issue = .{ .line = pos.line, .column = pos.column + end - p }; return error.Syntax; } end += 1; try bytes.append(l.a, switch (s[end]) { 'n' => 10, 't' => 9, else => s[end] }); }
                    else try bytes.append(l.a, s[end]); end += 1;
                }
                if (end == s.len) { l.issue = start; return error.Syntax; } end += 1; token.kind = .string; token.value = v.Value.string(bytes.items);
            } else if (end < s.len and member(s[p..end + 1], "+= -= *= /= %= ^= == <= >= != ++ -- && || >>")) end += 1
            else if (std.mem.indexOfScalar(u8, "+-*/%^!><?:=()[]{},;$", c) == null) { l.issue = start; return error.Syntax; }
            token.spelling = s[p..end]; try tokens.append(l.a, token); pos.column += end - p; p = end;
        }
        try tokens.append(l.a, .{ .kind = .eof, .spelling = "", .position = .{ .line = pos.line, .column = 1 } }); return tokens.items;
    }
};
