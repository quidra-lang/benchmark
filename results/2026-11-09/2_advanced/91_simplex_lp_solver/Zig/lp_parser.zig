const std = @import("std");
const r = @import("rational.zig");
pub const Term = struct { name: []const u8, coefficient: r.Q };
pub const Row = struct { name: []const u8, terms: []const Term, op: []const u8, rhs: r.Q, line: usize };
pub const Record = struct { words: []const []const u8, line: usize };
pub const Model = struct {
    name: []const u8, maximize: bool = false, objective: []const Term = &.{},
    rows: std.ArrayList(Row) = .empty, bounds: std.ArrayList(Record) = .empty,
    integers: std.ArrayList(Record) = .empty, binaries: std.ArrayList(Record) = .empty,
    error_line: usize = 0, message: []const u8 = "syntax error", log: usize = 0, limit: usize = 1,
};
pub fn name(s: []const u8) bool {
    if (s.len == 0 or s[0] < 'a' or s[0] > 'z') return false;
    for (s[1..]) |c| if (!(c >= 'a' and c <= 'z') and !std.ascii.isDigit(c) and c != '_') return false;
    for ([_][]const u8{ "bounds", "integer", "binary", "free", "inf" }) |v| if (r.eq(v, s)) return false;
    return true;
}
fn named(s: []const u8) bool { return s.len > 1 and s[s.len - 1] == ':' and name(s[0 .. s.len - 1]); }
pub fn expression(w: []const []const u8) ?[]const Term {
    var terms: std.ArrayList(Term) = .empty; var i: usize = 0; var negative = false;
    if (w.len > 0 and r.eq(w[0], "-")) { i = 1; negative = true; }
    while (i < w.len) {
        var q = r.Q.int(1); var n = w[i];
        if (!name(n)) { q = r.parse(n) orelse return null; if (n[0] == '-') return null; i += 1; if (i == w.len or !name(w[i])) return null; n = w[i]; }
        r.add(Term, &terms, .{ .name = n, .coefficient = if (negative) q.neg() else q }); i += 1;
        if (i == w.len) return terms.items;
        if (!r.eq(w[i], "+") and !r.eq(w[i], "-")) return null;
        negative = r.eq(w[i], "-"); i += 1;
    }
    return null;
}
fn boundLine(w: []const []const u8) bool {
    if (w.len == 2) return name(w[0]) and r.eq(w[1], "free");
    if (w.len == 3 and name(w[0])) {
        const b = r.bound(w[2]) orelse return false;
        return (r.eq(w[1], ">=") and b.infinity <= 0) or (r.eq(w[1], "<=") and b.infinity >= 0) or (r.eq(w[1], "=") and b.infinity == 0);
    }
    if (w.len == 5 and r.eq(w[1], "<=") and name(w[2]) and r.eq(w[3], "<=")) {
        const a = r.bound(w[0]) orelse return false; const b = r.bound(w[4]) orelse return false;
        return a.infinity <= 0 and b.infinity >= 0;
    }
    return false;
}
pub fn models(text: []const u8) []Model {
    var out: std.ArrayList(Model) = .empty; var current: Model = undefined; var state: u8 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n'); var line: usize = 0;
    while (lines.next()) |s| {
        line += 1; if (s.len == 0 or s[0] == '#') continue;
        const w = r.words(s);
        if (r.eq(w[0], "model")) { current = .{ .name = w[1] }; state = 0; continue; }
        if (r.eq(s, "end")) { if (current.error_line == 0 and state < 4) current.error_line = line; r.add(Model, &out, current); continue; }
        if (current.error_line != 0) continue;
        var ok = false;
        if (state == 0) { ok = r.eq(s, "maximize") or r.eq(s, "minimize"); current.maximize = r.eq(s, "maximize"); if (ok) state = 1; }
        else if (state == 1) {
            if (w.len >= 2 and named(w[0])) if (expression(w[1..])) |e| { current.objective = e; state = 2; ok = true; };
        } else if (state == 2) { ok = r.eq(s, "subject to"); if (ok) state = 3; }
        else if (state == 3 or state == 4) {
            if (state == 4 and r.eq(s, "bounds")) { state = 5; ok = true; }
            else if (state == 4 and r.eq(s, "integer")) { state = 6; ok = true; }
            else if (state == 4 and r.eq(s, "binary")) { state = 7; ok = true; }
            else if (w.len >= 4 and named(w[0]) and (r.eq(w[w.len - 2], "<=") or r.eq(w[w.len - 2], ">=") or r.eq(w[w.len - 2], "="))) {
                if (r.parse(w[w.len - 1])) |rhs| if (expression(w[1 .. w.len - 2])) |e| { r.add(Row, &current.rows, .{ .name = w[0][0 .. w[0].len - 1], .terms = e, .op = w[w.len - 2], .rhs = rhs, .line = line }); state = 4; ok = true; };
            }
        } else if (state == 5) {
            if (r.eq(s, "integer")) { state = 6; ok = true; } else if (r.eq(s, "binary")) { state = 7; ok = true; }
            else if (boundLine(w)) { r.add(Record, &current.bounds, .{ .words = w, .line = line }); ok = true; }
        } else if (state == 6 and r.eq(s, "binary")) { state = 7; ok = true; }
        else { ok = true; for (w) |v| if (!name(v)) { ok = false; break; }; if (ok) r.add(Record, if (state == 6) &current.integers else &current.binaries, .{ .words = w, .line = line }); }
        if (!ok) current.error_line = line;
    }
    return out.items;
}
pub fn settings(text: []const u8, items: []Model) void {
    var level: usize = 0; var limit: usize = 1;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |s| { const w = r.words(s); if (w.len < 2) continue;
        const v = std.fmt.parseInt(usize, w[w.len - 1], 10) catch unreachable;
        if (r.eq(w[0], "log_level")) level = v else if (r.eq(w[0], "node_limit")) limit = v;
    }
    for (items) |*item| { item.log = level; item.limit = limit; }
    lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |s| { const w = r.words(s); if (w.len != 3) continue; for (items) |*item| if (r.eq(item.name, w[1])) { const v = std.fmt.parseInt(usize, w[2], 10) catch unreachable; if (r.eq(w[0], "log")) item.log = v else item.limit = v; }; }
}
