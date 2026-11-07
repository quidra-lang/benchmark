const std = @import("std");
const d = @import("doc_builder.zig");
pub const Position = struct { line: usize, column: usize };
pub const Failure = struct { position: Position, message: []const u8 };
pub const Comment = struct { value: []const u8, position: Position, blank: usize, own: bool = false, line_comment: bool };
pub const Token = struct { value: []const u8, kind: enum { identifier, keyword, number, string, symbol, end }, position: Position, blank: usize, leading: std.ArrayList(Comment) = .empty, trailing: std.ArrayList(Comment) = .empty, allowed: bool = false, trailing_comma: bool = false };
pub const Result = struct { tokens: []Token, comments: usize, failure: ?Failure = null };
const Event = union(enum) { token: usize, comment: usize };
pub fn typeName(s: []const u8) bool { for ([_][]const u8{ "int", "float", "bool", "string", "void" }) |x| if (d.eq(s, x)) return true; return false; }
pub fn scan(lines: []const []const u8) Result {
    var tokens: std.ArrayList(Token) = .empty; var comments: std.ArrayList(Comment) = .empty; var events: std.ArrayList(Event) = .empty; var previous: usize = 0; var failure: ?Failure = null;
    outer: for (lines, 1..) |s, line| {
        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == ' ') { i += 1; continue; }
            const start = i; const position = Position{ .line = line, .column = i + 1 }; const blank = line - previous - @intFromBool(line > previous); previous = line;
            if (std.mem.startsWith(u8, s[i..], "//") or std.mem.startsWith(u8, s[i..], "/*")) {
                const isline = s[i + 1] == '/'; var end = s.len;
                if (!isline) { const offset = std.mem.indexOf(u8, s[i + 2 ..], "*/") orelse { failure = .{ .position = position, .message = "unterminated comment" }; break :outer; }; end = i + 2 + offset + 2; }
                d.append(Event, &events, .{ .comment = comments.items.len }); d.append(Comment, &comments, .{ .value = if (isline) d.trim(s[start..end]) else s[start..end], .position = position, .blank = blank, .line_comment = isline }); i = end; continue;
            }
            var kind: @FieldType(Token, "kind") = .symbol;
            if (std.ascii.isAlphabetic(s[i]) or s[i] == '_') {
                i += 1; while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) : (i += 1) {} kind = .identifier;
                for ([_][]const u8{ "int", "float", "bool", "string", "void", "if", "else", "while", "for", "return", "break", "continue", "true", "false", "switch", "case", "default" }) |k| if (d.eq(s[start..i], k)) { kind = .keyword; break; };
            } else if (std.ascii.isDigit(s[i])) { i += 1; while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {} if (i + 1 < s.len and s[i] == '.' and std.ascii.isDigit(s[i + 1])) { i += 2; while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {} } kind = .number; }
            else if (s[i] == '"') { i += 1; while (i < s.len and s[i] != '"') { if (s[i] == '\\') i += 1; i += 1; } if (i >= s.len) { failure = .{ .position = position, .message = "unterminated string" }; break :outer; } i += 1; kind = .string; }
            else {
                var pair = false; if (i + 1 < s.len) for ([_][]const u8{ "<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%=" }) |x| if (d.eq(s[i .. i + 2], x)) { pair = true; break; };
                if (pair) i += 2 else if (std.mem.indexOfScalar(u8, "+-*/%<>=!()[]{},;.?:", s[i]) != null) i += 1 else { failure = .{ .position = position, .message = d.fmt("unexpected character '{c}'", .{s[i]}) }; break :outer; }
            }
            d.append(Event, &events, .{ .token = tokens.items.len }); d.append(Token, &tokens, .{ .value = s[start..i], .kind = kind, .position = position, .blank = blank });
        }
    }
    d.append(Token, &tokens, .{ .value = "", .kind = .end, .position = .{ .line = lines.len + 1, .column = 1 }, .blank = 0, .allowed = true });
    for (events.items, 0..) |event, ei| switch (event) {
        .token => {}, .comment => |ci| {
            var before: ?usize = null; var after: ?usize = null;
            var j = ei; while (j > 0) { j -= 1; switch (events.items[j]) { .token => |ti| { before = ti; break; }, else => {} } }
            for (events.items[ei + 1 ..]) |next| switch (next) { .token => |ti| { after = ti; break; }, else => {} };
            var comment = comments.items[ci]; var nextline: ?usize = null;
            if (ei + 1 < events.items.len) nextline = switch (events.items[ei + 1]) { .token => |ti| tokens.items[ti].position.line, .comment => |c| comments.items[c].position.line };
            if (before != null and tokens.items[before.?].position.line == comment.position.line and (after == null or tokens.items[after.?].position.line > comment.position.line)) d.append(Comment, &tokens.items[before.?].trailing, comment)
            else { comment.own = comment.line_comment or nextline == null or nextline.? > comment.position.line; d.append(Comment, &tokens.items[after orelse tokens.items.len - 1].leading, comment); }
        },
    };
    return .{ .tokens = tokens.items, .comments = comments.items.len, .failure = failure };
}
