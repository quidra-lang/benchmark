const std = @import("std");
const b = @import("boxes.zig");
pub const Token = struct { kind: []const u8, value: []const u8, column: usize };
pub const Failure = struct { column: usize, message: []const u8 };
pub const Result = struct { tokens: []const Token, failure: ?Failure = null };
fn failed(tokens: []const Token, column: usize, comptime s: []const u8, a: anytype) Result { return .{ .tokens = tokens, .failure = .{ .column = column, .message = b.fmt(s, a) } }; }
pub fn environment(s: []const u8) bool { for ([_][]const u8{ "matrix", "pmatrix", "bmatrix", "vmatrix", "cases" }) |n| if (b.eq(n, s)) return true; return false; }
pub fn scan(s: []const u8) Result {
    var tokens: std.ArrayList(Token) = .empty; var i: usize = 0;
    while (i < s.len) {
        if (s[i] == ' ') { i += 1; continue; }
        const start = i; var kind: []const u8 = "symbol"; var value: []const u8 = undefined;
        if (std.ascii.isAlphabetic(s[i])) { i += 1; while (i < s.len and std.ascii.isAlphabetic(s[i])) : (i += 1) {} kind = "identifier"; value = s[start..i]; }
        else if (std.ascii.isDigit(s[i])) { i += 1; while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {} if (i + 1 < s.len and s[i] == '.' and std.ascii.isDigit(s[i + 1])) { i += 2; while (i < s.len and std.ascii.isDigit(s[i])) : (i += 1) {} } kind = "number"; value = s[start..i]; }
        else if (s[i] == '\\') {
            i += 1; if (i < s.len and (s[i] == '\\' or s[i] == '{' or s[i] == '}' or s[i] == ',')) { kind = if (s[i] == '\\') "newline" else "command"; i += 1; value = s[start..i]; }
            else {
                const command_start = i; while (i < s.len and std.ascii.isAlphabetic(s[i])) : (i += 1) {}
                if (command_start == i) return failed(tokens.items, start + 1, "invalid command", .{});
                const name = s[command_start..i]; var raw = false;
                for ([_][]const u8{ "text", "begin", "end", "tag", "label", "eqref" }) |n| if (b.eq(name, n)) { raw = true; break; };
                if (raw) { while (i < s.len and s[i] == ' ') : (i += 1) {} if (i == s.len or s[i] != '{') return failed(tokens.items, i + 1, "expected {{", .{}); const end = std.mem.indexOfScalarPos(u8, s, i + 1, '}') orelse return failed(tokens.items, start + 1, "unterminated argument", .{}); value = s[i + 1 .. end]; i = end + 1; kind = name; if ((b.eq(name, "begin") or b.eq(name, "end")) and !environment(value)) return failed(tokens.items, start + 1, "unknown environment \"{s}\"", .{value}); }
                else if (b.symbol(name) != null) { kind = "command"; value = s[start..i]; }
                else {
                    var known = false; for ([_][]const u8{ "overline", "hat", "vec", "dot", "tilde", "overbrace", "underbrace" }) |n| if (b.eq(n, name)) { kind = "accent"; value = name; known = true; break; };
                    if (!known) for ([_][]const u8{ "frac", "binom", "overset", "underset", "sqrt", "left", "right" }) |n| if (b.eq(n, name)) { kind = name; value = name; known = true; break; };
                    if (!known) return failed(tokens.items, start + 1, "unknown command \\{s}", .{name});
                }
            }
        } else if (std.mem.indexOfScalar(u8, "+-*/=<>:()[],;.!|'", s[i]) != null) { i += 1; value = s[start..i]; }
        else if (std.mem.indexOfScalar(u8, "{}^_&", s[i]) != null) { i += 1; value = s[start..i]; kind = value; }
        else return failed(tokens.items, i + 1, "invalid character {c}", .{s[i]});
        b.append(Token, &tokens, .{ .kind = kind, .value = value, .column = start + 1 });
    }
    b.append(Token, &tokens, .{ .kind = "eof", .value = "", .column = s.len + 1 }); return .{ .tokens = tokens.items };
}
