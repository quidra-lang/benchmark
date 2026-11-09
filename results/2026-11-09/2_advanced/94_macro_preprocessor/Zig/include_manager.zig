const std = @import("std");
const lex = @import("lexer.zig");
pub const File = struct { path: lex.Text, document: lex.Document, guard: ?lex.Text, entered: usize = 0, skipped: usize = 0, once: bool = false, output_lines: usize = 0, skipped_lines: i64 = 0 };
pub const Manager = struct {
    a: std.mem.Allocator, io: std.Io, files: std.ArrayList(*File) = .empty, order: std.ArrayList(*File) = .empty,
    pub fn get(m: *Manager, path: lex.Text) !?*File {
        for (m.files.items) |f| if (lex.eq(f.path, path)) return f;
        const source = std.Io.Dir.cwd().readFileAlloc(m.io, try std.fmt.allocPrint(m.a, "input/{s}", .{path}), m.a, .unlimited) catch |err| switch (err) { error.FileNotFound => return null, else => return err };
        const f = try m.a.create(File); f.* = .{ .path = path, .document = try lex.lex(m.a, source), .guard = null }; f.guard = guard(f.document); try m.files.append(m.a, f); return f;
    }
    pub fn search(m: *Manager, name: lex.Text, quoted: bool) !?*File { if (quoted) if (try m.get(name)) |f| return f; return m.get(try std.fmt.allocPrint(m.a, "include/{s}", .{name})); }
    pub fn enter(m: *Manager, f: *File) !void { if (f.entered == 0) try m.order.append(m.a, f); f.entered += 1; }
};
fn guard(d: lex.Document) ?lex.Text {
    var first: ?[]const lex.Token = null; var last: []const lex.Token = &.{}; var depth: i64 = 0; var ended = false;
    for (d.lines) |line| {
        const ts = line.tokens; if (ts.len == 0) continue;
        if (ended) return null; if (first == null) { if (ts.len != 3 or !lex.eq(ts[0].spelling, "#") or !lex.eq(ts[1].spelling, "ifndef") or ts[2].kind != .identifier) return null; first = ts; }
        last = ts;
        if (ts.len >= 2 and lex.eq(ts[0].spelling, "#")) { const k = ts[1].spelling;
            if (lex.eq(k, "if") or lex.eq(k, "ifdef") or lex.eq(k, "ifndef")) depth += 1
            else if (lex.eq(k, "endif")) { depth -= 1; if (depth == 0) ended = true; }
            else if (depth == 1 and (lex.eq(k, "else") or std.mem.startsWith(u8, k, "elif"))) return null;
        }
    }
    if (first == null or !ended or last.len != 2 or !lex.eq(last[1].spelling, "endif")) return null; return first.?[2].spelling;
}
