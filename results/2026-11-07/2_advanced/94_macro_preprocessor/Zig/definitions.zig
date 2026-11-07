const std = @import("std");
const lex = @import("lexer.zig");
pub const Text = lex.Text;
pub const Position = struct { file: Text, line: i64 };
pub const Macro = struct {
    name: Text, parameters: ?[]const Text = null, variadic: bool = false, replacement: []lex.Token, position: Position, main: bool, expanded: usize = 0, tested: usize = 0,
    pub fn parameter(m: *const Macro, name: Text) ?usize { const ps = m.parameters orelse return null; for (ps, 0..) |p, i| if (lex.eq(p, name)) return i; return null; }
    pub fn signature(m: *const Macro, a: std.mem.Allocator) !Text {
        if (m.parameters == null) return m.name; var text: std.ArrayList(u8) = .empty; try text.appendSlice(a, m.name); try text.append(a, '(');
        for (m.parameters.?, 0..) |p, i| { if (i > 0) try text.appendSlice(a, ", "); try text.appendSlice(a, if (m.variadic and i + 1 == m.parameters.?.len) "..." else p); }
        try text.append(a, ')'); return text.items;
    }
};
pub fn builtin(name: Text) bool { return lex.eq(name, "__LINE__") or lex.eq(name, "__FILE__") or lex.eq(name, "__COUNTER__"); }
pub fn nameError(a: std.mem.Allocator, tokens: []const lex.Token, directive: Text) !?Text {
    if (tokens.len == 0) return try std.fmt.allocPrint(a, "no macro name given in #{s} directive", .{directive}); if (tokens[0].kind != .identifier) return "macro names must be identifiers";
    const name = tokens[0].spelling; if (lex.eq(name, "defined")) return "\"defined\" cannot be used as a macro name";
    if (builtin(name)) return try std.fmt.allocPrint(a, "cannot {s} builtin macro \"{s}\"", .{if (lex.eq(directive, "define")) "redefine" else "undefine", name}); return null;
}
pub const Parsed = union(enum) { macro: *Macro, message: Text };
const va_error = "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro";
pub fn parse(a: std.mem.Allocator, tokens: []const lex.Token, position: Position, main: bool) !Parsed {
    if (try nameError(a, tokens, "define")) |message| return .{ .message = message };
    const name = tokens[0].spelling; if (lex.eq(name, "__VA_ARGS__")) return .{ .message = va_error };
    var index: usize = 1; var params: ?[]const Text = null; var variadic = false;
    if (tokens.len > 1 and lex.eq(tokens[1].spelling, "(") and !tokens[1].space) {
        index = 2; var list: std.ArrayList(Text) = .empty;
        if (index == tokens.len) return .{ .message = "missing ')' in macro parameter list" };
        if (!lex.eq(tokens[index].spelling, ")")) while (true) {
            if (index == tokens.len) return .{ .message = "missing ')' in macro parameter list" }; const t = tokens[index]; index += 1;
            if (lex.eq(t.spelling, "...")) { variadic = true; try list.append(a, "__VA_ARGS__"); }
            else if (t.kind == .identifier) { if (lex.eq(t.spelling, "__VA_ARGS__")) return .{ .message = va_error }; for (list.items) |p| if (lex.eq(p, t.spelling)) return .{ .message = try std.fmt.allocPrint(a, "duplicate macro parameter \"{s}\"", .{p}) }; try list.append(a, t.spelling); }
            else return .{ .message = try std.fmt.allocPrint(a, "expected parameter name, found \"{s}\"", .{t.spelling}) };
            if (index == tokens.len) return .{ .message = "missing ')' in macro parameter list" };
            const next = tokens[index].spelling; if (lex.eq(next, ")")) break;
            if (variadic) return .{ .message = try std.fmt.allocPrint(a, "expected ')' after \"...\", found \"{s}\"", .{next}) };
            if (!lex.eq(next, ",")) return .{ .message = try std.fmt.allocPrint(a, "expected ',' or ')', found \"{s}\"", .{next}) }; index += 1;
        };
        index += 1; params = list.items;
    }
    const m = try a.create(Macro); m.* = .{ .name = name, .parameters = params, .variadic = variadic, .replacement = try a.dupe(lex.Token, tokens[index..]), .position = position, .main = main };
    if (m.replacement.len > 0) { m.replacement[0].space = false; if (lex.eq(m.replacement[0].spelling, "##") or lex.eq(m.replacement[m.replacement.len - 1].spelling, "##")) return .{ .message = "'##' cannot appear at either end of a macro expansion" }; }
    for (m.replacement, 0..) |t, i| {
        if (t.kind == .identifier and lex.eq(t.spelling, "__VA_ARGS__") and !variadic) return .{ .message = va_error };
        if (params != null and lex.eq(t.spelling, "#") and (i + 1 == m.replacement.len or m.replacement[i + 1].kind != .identifier or m.parameter(m.replacement[i + 1].spelling) == null)) return .{ .message = "'#' is not followed by a macro parameter" };
    }
    return .{ .macro = m };
}
pub fn identical(a: *Macro, b: *Macro) bool {
    if ((a.parameters == null) != (b.parameters == null) or a.variadic != b.variadic or a.replacement.len != b.replacement.len) return false;
    if (a.parameters) |ps| { if (ps.len != b.parameters.?.len) return false; for (ps, b.parameters.?) |x, y| if (!lex.eq(x, y)) return false; }
    for (a.replacement, b.replacement) |x, y| if (!lex.eq(x.spelling, y.spelling) or x.space != y.space) return false; return true;
}
