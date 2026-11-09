const std = @import("std");
const d = @import("document_parser.zig");
pub const Line = struct { text: []const u8 = "", footnotes: []usize = &.{}, indices: []usize = &.{},
     first_block: ?usize = null, toc_target: ?usize = null, index_entry: ?usize = null, dynamic_width: usize = 0 };
pub const Type = enum { heading, solid, flow };
pub const Block = struct { lines: []Line, type_: Type, list: bool = false, page_break: bool = false };
pub const Page = struct { content: []Line = &.{}, footnotes: []usize = &.{}, height: usize = 0, forced: bool = false,
     blank: bool = false, display: []const u8 = "", body_number: i64 = 0 };
const Boundary = struct { end: usize, next: usize, forced: bool };
fn boundaryLess(_: void, a: Boundary, b: Boundary) bool {
    return if (a.end != b.end) a.end < b.end else if (a.next != b.next) a.next < b.next else @intFromBool(a.forced) < @intFromBool(b.forced);
}
pub fn build(blocks: []const Block, footnotes: []const d.Lines, p: d.Params, height: usize) []Page {
    var stream: std.ArrayList(Line) = .empty;
    var boundaries: std.ArrayList(Boundary) = .empty;
    for (blocks, 0..) |block, i| {
        if (i > 0) {
            const before = stream.items.len;
            if (!(blocks[i - 1].list and block.list)) d.append(Line, &stream, .{});
            const after = stream.items.len;
            if (block.page_break or blocks[i - 1].type_ != .heading) d.append(Boundary, &boundaries,
                 .{ .end = before, .next = after, .forced = block.page_break });
        }
        const start = stream.items.len;
        for (block.lines) |line| d.append(Line, &stream, line);
        if (block.type_ == .flow and block.lines.len > 1) for (1..block.lines.len) |k| {
            if (d.n(k) >= p.orphan_lines and d.n(block.lines.len - k) >= p.widow_lines) d.append(Boundary,
                 &boundaries, .{ .end = start + k, .next = start + k, .forced = false });
        };
    }
    d.append(Boundary, &boundaries, .{ .end = stream.items.len, .next = stream.items.len, .forced = true });
    std.mem.sort(Boundary, boundaries.items, {}, boundaryLess);
    var pages: std.ArrayList(Page) = .empty;
    var start: usize = 0;
    while (start < stream.items.len) {
        var selected: ?Boundary = null;
        var chosen: Page = .{};
        const ids = d.alloc(bool, footnotes.len);
        var notes: std.ArrayList(usize) = .empty;
        for (boundaries.items) |boundary| {
            if (boundary.end <= start) continue;
            @memset(ids, false);
            notes.items.len = 0;
            for (stream.items[start..boundary.end]) |line| for (line.footnotes) |id| {
                ids[id] = true;
            };
            var page_height = boundary.end - start;
            for (ids, footnotes, 0..) |present, note, id| if (present) {
                d.append(usize, &notes, id);
                page_height += note.data.items.len;
            };
            if (notes.items.len > 0) page_height += 1;
            if (page_height <= height) {
                selected = boundary;
                chosen = .{ .content = stream.items[start..boundary.end], .footnotes = d.dupe(usize,
                     notes.items), .height = page_height, .forced = boundary.forced };
            }
            if (boundary.forced) break;
        }
        d.append(Page, &pages, chosen);
        start = selected.?.next;
    }
    return pages.items;
}
