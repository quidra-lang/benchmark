const std = @import("std");
const d = @import("doc_builder.zig");
pub fn tree(x: *const d.Doc, depth: usize, text: *d.Text) void {
    if (x.kind == .concat) { for (x.children) |y| tree(y, depth, text); return; }
    text.put("{s}", .{d.spaces(depth * 2)});
    switch (x.kind) {
        .text => text.line("text \"{s}\"", .{x.value}), .suffix => text.line("suffix \"{s}\"", .{x.value}), .if_break => text.line("if_break \"{s}\" \"{s}\"", .{x.value, x.alternate}),
        .group => text.line("group {s}", .{x.mode}), .nest => text.line("nest {d}", .{x.indentation}), else => text.line("{s}", .{@tagName(x.kind)}),
    }
    for (x.children) |y| tree(y, depth + 1, text);
}
const Operation = struct { insertion: bool, value: []const u8 };
const Hunk = struct { i: usize, j: usize, deleted: usize = 0, inserted: usize = 0, operations: std.ArrayList(Operation) = .empty };
pub fn diff(a: []const []const u8, b: []const []const u8, text: *d.Text) void {
    const m = b.len + 1; const table = d.alloc(usize, (a.len + 1) * m); @memset(table, 0);
    var i = a.len; while (i > 0) { i -= 1; var j = b.len; while (j > 0) { j -= 1; table[i * m + j] = if (d.eq(a[i], b[j])) table[(i + 1) * m + j + 1] + 1 else @max(table[(i + 1) * m + j], table[i * m + j + 1]); } }
    var hunks: std.ArrayList(Hunk) = .empty; i = 0; var j: usize = 0; var active: ?Hunk = null; var deleted: usize = 0; var inserted: usize = 0;
    while (i < a.len or j < b.len) {
        if (i < a.len and j < b.len and d.eq(a[i], b[j])) { if (active) |h| d.append(Hunk, &hunks, h); active = null; i += 1; j += 1; continue; }
        if (active == null) active = .{ .i = i, .j = j };
        if (j == b.len or (i < a.len and table[(i + 1) * m + j] >= table[i * m + j + 1])) { d.append(Operation, &active.?.operations, .{ .insertion = false, .value = a[i] }); active.?.deleted += 1; deleted += 1; i += 1; }
        else { d.append(Operation, &active.?.operations, .{ .insertion = true, .value = b[j] }); active.?.inserted += 1; inserted += 1; j += 1; }
    }
    if (active) |h| d.append(Hunk, &hunks, h);
    text.line("hunks={d} deleted={d} inserted={d}", .{hunks.items.len, deleted, inserted});
    for (hunks.items) |h| { text.line("@@ -{d},{d} +{d},{d} @@", .{h.i + @intFromBool(h.deleted > 0), h.deleted, h.j + @intFromBool(h.inserted > 0), h.inserted}); for (h.operations.items) |op| text.line("{s}{s}", .{if (op.insertion) "+" else "-", op.value}); }
}
