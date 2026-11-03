const std = @import("std");
const obj = @import("object_parser.zig");
const res = @import("resolver.zig");
pub fn alignUp(x: i64, n: i64) i64 { return @divFloor(x + n - 1, n) * n; }
pub const Component = struct {
    kind: enum { input, merged, common, veneer }, size: usize, alignment: i64, address: i64 = 0,
    section: ?*obj.Section = null, resolution: ?*res.Resolution = null, sources: []const *obj.Section = &.{},
    contents: std.ArrayList(u8) = .empty, strings: usize = 0, unique: usize = 0, saved: usize = 0,
};
pub const Output = struct { name: obj.Text, segment: usize, keep: bool = false, sorted: bool = false, components: std.ArrayList(*Component) = .empty, base_count: usize = 0, address: i64 = 0, size: usize = 0, alignment: i64 = 1 };
pub const Segment = struct { name: obj.Text, base: i64, length: i64, fill: u8, outputs: std.ArrayList(usize) = .empty, paddr: i64 = 0, filesz: usize = 0, memsz: usize = 0, used: i64 = 0, image: []u8 = &.{} };
pub fn assign(segment: *Segment, outputs: []Output) void {
    var cursor = segment.base; segment.filesz = 0;
    for (segment.outputs.items) |oi| {
        const o = &outputs[oi]; o.alignment = 1; for (o.components.items) |c| o.alignment = @max(o.alignment, c.alignment);
        cursor = alignUp(cursor, o.alignment); o.address = cursor;
        for (o.components.items) |c| {
            cursor = alignUp(cursor, c.alignment); c.address = cursor; cursor += @as(i64, @intCast(c.size));
            if (c.section) |s| s.address = c.address;
            if (c.kind == .common) c.resolution.?.address = c.address;
            if (c.kind == .merged) for (c.sources) |s| { s.address = c.address; };
        }
        o.size = @intCast(cursor - o.address); if (!obj.belongs(o.name, ".bss")) segment.filesz = @intCast(cursor - segment.base);
    }
    segment.memsz = @intCast(cursor - segment.base); segment.paddr = segment.base; segment.used = @intCast(segment.memsz);
}
pub fn merged(a: std.mem.Allocator, sections: []const *obj.Section) !*Component {
    const c = try a.create(Component); c.* = .{ .kind = .merged, .size = 0, .alignment = 1, .sources = sections };
    var strings: std.StringHashMapUnmanaged(usize) = .empty; var total: usize = 0;
    for (sections) |s| {
        total += s.size; var p: usize = 0;
        while (p < s.size) { const end = std.mem.indexOfScalarPos(u8, s.contents.items, p, 0).? + 1; const text = s.contents.items[p..end]; var position = strings.get(text); if (position == null) { position = c.contents.items.len; try strings.put(a, text, position.?); try c.contents.appendSlice(a, text); } try s.merged.append(a, .{ .original = p, .merged = position.? }); c.strings += 1; p = end; }
    }
    c.size = c.contents.items.len; c.unique = strings.count(); c.saved = total - c.size; return c;
}
