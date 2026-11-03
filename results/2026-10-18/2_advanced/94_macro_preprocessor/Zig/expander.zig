const std = @import("std");
const lex = @import("lexer.zig");
const defs = @import("definitions.zig");
fn contains(set: []const lex.Text, name: lex.Text) bool { for (set) |n| if (lex.eq(n, name)) return true; return false; }
fn unite(a: std.mem.Allocator, x: []const lex.Text, y: []const lex.Text) ![]const lex.Text { var names: std.ArrayList(lex.Text) = .empty; try names.appendSlice(a, x); for (y) |name| if (!contains(names.items, name)) { try names.append(a, name); }; return names.items; }
fn intersect(a: std.mem.Allocator, x: []const lex.Text, y: []const lex.Text) ![]const lex.Text { var names: std.ArrayList(lex.Text) = .empty; for (x) |name| if (contains(y, name)) { try names.append(a, name); }; return names.items; }
fn stringize(a: std.mem.Allocator, ts: []const lex.Token, space: bool) !lex.Token {
    var bytes: std.ArrayList(u8) = .empty; try bytes.append(a, '"');
    for (ts, 0..) |t, i| { if (i > 0 and t.space) try bytes.append(a, ' '); for (t.spelling) |c| { if ((t.kind == .string or t.kind == .character) and (c == '\\' or c == '"')) try bytes.append(a, '\\'); try bytes.append(a, c); } }
    try bytes.append(a, '"'); return .{ .kind = .string, .spelling = bytes.items, .space = space };
}
const Item = struct { paste: bool = false, tokens: []const lex.Token = &.{} };
pub fn expand(a: std.mem.Allocator, host: anytype, tokens: []const lex.Token, file: lex.Text, offset: i64) anyerror![]lex.Token {
    var input: std.ArrayList(lex.Token) = .empty; try input.appendSlice(a, tokens); var result: std.ArrayList(lex.Token) = .empty;
    while (input.items.len > 0) {
        const t = input.orderedRemove(0);
        if (t.kind != .identifier or contains(t.hide, t.spelling)) { try result.append(a, t); continue; }
        const pos: defs.Position = .{ .file = file, .line = t.line + offset };
        if (defs.builtin(t.spelling)) {
            var produced = t; produced.hide = &.{}; produced.kind = .number;
            if (lex.eq(t.spelling, "__COUNTER__")) { produced.spelling = try std.fmt.allocPrint(a, "{d}", .{host.builtins[0]}); host.builtins[0] += 1; }
            else if (lex.eq(t.spelling, "__FILE__")) { produced.kind = .string; produced.spelling = try std.fmt.allocPrint(a, "\"{s}\"", .{file}); host.builtins[1] += 1; }
            else { produced.spelling = try std.fmt.allocPrint(a, "{d}", .{pos.line}); host.builtins[2] += 1; }
            try result.append(a, produced); continue;
        }
        const macro = host.table.get(t.spelling) orelse { try result.append(a, t); continue; };
        var raw: std.ArrayList([]const lex.Token) = .empty; var hide = t.hide;
        if (macro.parameters) |ps| {
            if (input.items.len == 0 or !lex.eq(input.items[0].spelling, "(")) { try result.append(a, t); continue; }
            var depth: usize = 0; var first: usize = 1; var close: ?usize = null; var commas: std.ArrayList(lex.Token) = .empty;
            for (input.items[1..], 1..) |x, i| {
                if (lex.eq(x.spelling, ")") and depth == 0) { try raw.append(a, try a.dupe(lex.Token, input.items[first..i])); close = i; break; }
                if (lex.eq(x.spelling, ",") and depth == 0) { try raw.append(a, try a.dupe(lex.Token, input.items[first..i])); try commas.append(a, x); first = i + 1; }
                else if (lex.eq(x.spelling, "(")) depth += 1 else if (lex.eq(x.spelling, ")")) depth -= 1;
            }
            var message: ?lex.Text = null; const fixed = ps.len - @intFromBool(macro.variadic); const k = raw.items.len;
            if (close == null) message = try std.fmt.allocPrint(a, "unterminated argument list invoking macro \"{s}\"", .{macro.name})
            else if (ps.len == 0 and !(k == 1 and raw.items[0].len == 0)) message = try std.fmt.allocPrint(a, "macro \"{s}\" passed {d} arguments, but takes just 0", .{macro.name, k})
            else if (k < fixed) message = try std.fmt.allocPrint(a, "macro \"{s}\" requires {d} arguments, but only {d} given", .{macro.name, fixed, k})
            else if (k > fixed and !macro.variadic and ps.len != 0) message = try std.fmt.allocPrint(a, "macro \"{s}\" passed {d} arguments, but takes just {d}", .{macro.name, k, fixed});
            if (message) |msg| { try host.diag(pos, "error", msg); try result.append(a, t); continue; }
            hide = try intersect(a, hide, input.items[close.?].hide);
            if (macro.variadic) {
                var variable: std.ArrayList(lex.Token) = .empty;
                if (k > fixed) for (raw.items[fixed..], fixed..) |arg, i| { if (i > fixed) try variable.append(a, commas.items[i - 1]); try variable.appendSlice(a, arg); };
                raw.items.len = @min(fixed, raw.items.len); try raw.append(a, variable.items);
            }
            input.replaceRangeAssumeCapacity(0, close.? + 1, &.{});
        }
        hide = try unite(a, hide, &.{macro.name});
        const cache = try a.alloc(?[]lex.Token, if (macro.parameters) |ps| ps.len else 0); @memset(cache, null);
        var items: std.ArrayList(Item) = .empty; var i: usize = 0;
        while (i < macro.replacement.len) : (i += 1) {
            const x = macro.replacement[i];
            if (lex.eq(x.spelling, "##")) { try items.append(a, .{ .paste = true }); continue; }
            if (macro.parameters != null and lex.eq(x.spelling, "#")) {
                i += 1; const index = macro.parameter(macro.replacement[i].spelling).?; const value = try a.alloc(lex.Token, 1); value[0] = try stringize(a, raw.items[index], x.space); try items.append(a, .{ .tokens = value }); continue;
            }
            if (x.kind == .identifier) if (macro.parameter(x.spelling)) |index| {
                const pasted = (i > 0 and lex.eq(macro.replacement[i - 1].spelling, "##")) or (i + 1 < macro.replacement.len and lex.eq(macro.replacement[i + 1].spelling, "##"));
                var value: []lex.Token = undefined;
                if (pasted) value = try a.dupe(lex.Token, raw.items[index]) else { if (cache[index] == null) cache[index] = try expand(a, host, raw.items[index], file, offset); value = try a.dupe(lex.Token, cache[index].?); }
                if (value.len == 0) { value = try a.alloc(lex.Token, 1); value[0] = .{ .kind = .placemarker, .spelling = "", .space = x.space }; } else value[0].space = x.space;
                try items.append(a, .{ .tokens = value }); continue;
            };
            const value = try a.alloc(lex.Token, 1); value[0] = x; try items.append(a, .{ .tokens = value });
        }
        var substituted: std.ArrayList(lex.Token) = .empty; i = 0;
        while (i < items.items.len) : (i += 1) {
            const item = items.items[i]; if (!item.paste) { try substituted.appendSlice(a, item.tokens); continue; }
            const left = substituted.pop().?; i += 1; const next = items.items[i]; const fake = [_]lex.Token{.{ .kind = .punctuator, .spelling = "##" }}; const right = if (next.paste) fake[0..] else next.tokens; var r = right[0];
            if (left.kind == .placemarker) { r.space = left.space; try substituted.append(a, r); }
            else if (r.kind == .placemarker) try substituted.append(a, left)
            else { const joined = try std.mem.concat(a, u8, &.{left.spelling, r.spelling}); if (lex.single(joined)) |single| { var value = single; value.space = left.space; value.hide = try intersect(a, left.hide, r.hide); try substituted.append(a, value); }
                else { try host.diag(pos, "error", try std.fmt.allocPrint(a, "pasting \"{s}\" and \"{s}\" does not give a valid preprocessing token", .{left.spelling, r.spelling})); r.space = false; try substituted.append(a, left); try substituted.append(a, r); } }
            try substituted.appendSlice(a, right[1..]);
        }
        var cleaned: std.ArrayList(lex.Token) = .empty; var pending_space = false;
        for (substituted.items) |x| { if (x.kind == .placemarker) { pending_space = pending_space or x.space; continue; } var value = x; value.line = t.line; value.space = value.space or pending_space; pending_space = false; value.hide = try unite(a, value.hide, hide); try cleaned.append(a, value); }
        if (cleaned.items.len > 0) cleaned.items[0].space = t.space else if (t.space and input.items.len > 0) input.items[0].space = true;
        macro.expanded += 1; try input.insertSlice(a, 0, cleaned.items);
    }
    return result.items;
}
