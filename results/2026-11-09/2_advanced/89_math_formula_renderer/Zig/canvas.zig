const std = @import("std");
const b = @import("boxes.zig");
pub const Counts = struct { kinds: std.StringHashMap(usize), boxes: usize = 0, depth: usize = 0 };
fn visit(place: b.Placement, x0: i64, y0: i64, level: usize, grid: [][]u8, text: *b.Text, counts: *Counts) void {
    const box = place.box; const x = x0 + place.x; const y = y0 + place.y;
    text.line("{s}{s}{s} x={d} y={d} w={d} h={d} b={d}", .{b.repeat(' ', @intCast(level * 2)), place.role, box.description, x, y, box.w, box.h, box.baseline});
    counts.boxes += 1; counts.depth = @max(counts.depth, level + 1);
    const end = std.mem.indexOfScalar(u8, box.description, ' ') orelse box.description.len; const kind = box.description[0..end]; const entry = counts.kinds.getOrPut(kind) catch @panic("allocation failed"); if (!entry.found_existing) entry.value_ptr.* = 0; entry.value_ptr.* += 1;
    for (box.strokes.items) |stroke| for (stroke.value, 0..) |c, i| { if (c != ' ') grid[@intCast(y + stroke.y)][@intCast(x + stroke.x + @as(i64, @intCast(i)))] = c; };
    for (box.children.items) |child| visit(child, x, y, level + 1, grid, text, counts);
}
pub const Result = struct { rendered: []const []const u8, boxes: b.Text, count: usize, depth: usize };
pub fn render(roots: []const b.Placement, width: i64, height: i64, totals: *Counts) Result {
    const grid = b.alloc([]u8, @intCast(height)); for (grid) |*line| { line.* = b.alloc(u8, @intCast(width)); @memset(line.*, ' '); }
    var text: b.Text = .{}; var counts = Counts{ .kinds = std.StringHashMap(usize).init(b.allocator) };
    for (roots) |root| visit(root, 0, 0, 0, grid, &text, &counts);
    const rendered = b.alloc([]const u8, grid.len); for (grid, rendered) |line, *s| s.* = std.mem.trimEnd(u8, line, " ");
    totals.boxes += counts.boxes; totals.depth = @max(totals.depth, counts.depth); var it = counts.kinds.iterator(); while (it.next()) |entry| { const total = totals.kinds.getOrPut(entry.key_ptr.*) catch @panic("allocation failed"); if (!total.found_existing) total.value_ptr.* = 0; total.value_ptr.* += entry.value_ptr.*; }
    return .{ .rendered = rendered, .boxes = text, .count = counts.boxes, .depth = counts.depth };
}
