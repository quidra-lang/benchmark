const std = @import("std");
const d = @import("doc_builder.zig");
const Command = struct { indentation: usize, flat: bool, doc: *d.Doc };
fn pushChildren(stack: *std.ArrayList(Command), c: Command) void { var i = c.doc.children.len; while (i > 0) { i -= 1; d.append(Command, stack, .{ .indentation = c.indentation, .flat = c.flat, .doc = c.doc.children[i] }); } }
fn fits(remaining: i64, first: Command, original: []const Command) bool {
    var r = remaining; if (r < 0) return false;
    var stack: std.ArrayList(Command) = .empty; d.append(Command, &stack, first); var unused = original.len;
    while (true) {
        if (stack.items.len == 0) { if (unused == 0) return true; unused -= 1; d.append(Command, &stack, original[unused]); }
        var c = stack.pop().?; const x = c.doc;
        switch (x.kind) {
            .text => r -= @intCast(x.value.len),
            .if_break => r -= @intCast((if (c.flat) x.alternate else x.value).len),
            .line => { if (!c.flat) return true; r -= 1; },
            .softline => if (!c.flat) return true,
            .hardline => return true,
            .concat => pushChildren(&stack, c),
            .group => { c.doc = x.children[0]; if (d.forced(x)) c.flat = false; d.append(Command, &stack, c); },
            .nest, .align => { c.doc = x.children[0]; d.append(Command, &stack, c); },
            .suffix, .break_parent => {},
        }
        if (r < 0) return false;
    }
}
fn finalize(lines: *std.ArrayList([]const u8), current: *d.Text, pending: *std.ArrayList([]const u8), width: usize, column: usize) void {
    var line = d.trim(current.data.items);
    if (pending.items.len > 0) { const suffix = std.mem.join(d.allocator, " ", pending.items) catch @panic("allocation failed"); const gap = if (column > 0 and line.len < column - 1 and column - 1 + suffix.len <= width) column - 1 - line.len else 1; line = d.fmt("{s}{s}{s}", .{line, d.spaces(gap), suffix}); }
    d.append([]const u8, lines, line); pending.* = .empty; current.* = .{};
}
pub fn layout(root: *d.Doc, width: usize, column: usize) []const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty; var current: d.Text = .{}; var pending: std.ArrayList([]const u8) = .empty; var stack: std.ArrayList(Command) = .empty;
    d.append(Command, &stack, .{ .indentation = 0, .flat = false, .doc = root });
    while (stack.pop()) |command| {
        var c = command; const x = c.doc;
        switch (x.kind) {
            .text => current.put("{s}", .{x.value}),
            .if_break => current.put("{s}", .{if (c.flat) x.alternate else x.value}),
            .line, .softline, .hardline => {
                if (x.kind == .hardline or !c.flat) { finalize(&lines, &current, &pending, width, column); current.put("{s}", .{d.spaces(c.indentation)}); }
                else if (x.kind == .line) current.put(" ", .{});
            },
            .concat => pushChildren(&stack, c),
            .nest => { c.indentation += x.indentation; c.doc = x.children[0]; d.append(Command, &stack, c); },
            .align => { c.indentation = current.data.items.len; c.doc = x.children[0]; d.append(Command, &stack, c); },
            .suffix => d.append([]const u8, &pending, x.value),
            .break_parent => {},
            .group => {
                if (c.flat) x.mode = "flat" else if (d.forced(x)) x.mode = "forced" else { const flat = Command{ .indentation = c.indentation, .flat = true, .doc = x.children[0] }; x.mode = if (fits(@as(i64, @intCast(width)) - @as(i64, @intCast(current.data.items.len)), flat, stack.items)) "flat" else "break"; }
                c.flat = d.eq(x.mode, "flat"); c.doc = x.children[0]; d.append(Command, &stack, c);
            },
        }
    }
    finalize(&lines, &current, &pending, width, column); return lines.items;
}
