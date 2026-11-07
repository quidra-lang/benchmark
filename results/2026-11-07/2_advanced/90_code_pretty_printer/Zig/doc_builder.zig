const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, n: usize) []T { return allocator.alloc(T, n) catch @panic("allocation failed"); }
pub fn create(comptime T: type, value: T) *T { const p = allocator.create(T) catch @panic("allocation failed"); p.* = value; return p; }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime s: []const u8, a: anytype) []const u8 { return std.fmt.allocPrint(allocator, s, a) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn spaces(n: usize) []const u8 { const s = alloc(u8, n); @memset(s, ' '); return s; }
pub fn trim(s: []const u8) []const u8 { return std.mem.trimEnd(u8, s, " "); }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn put(self: *Text, comptime s: []const u8, a: anytype) void { self.data.appendSlice(allocator, fmt(s, a)) catch @panic("allocation failed"); }
    pub fn line(self: *Text, comptime s: []const u8, a: anytype) void { self.put(s, a); self.put("\n", .{}); }
};
pub const Kind = enum { text, line, softline, hardline, break_parent, suffix, if_break, group, nest, align, concat };
pub const Doc = struct { kind: Kind, value: []const u8 = "", alternate: []const u8 = "", children: []const *Doc = &.{}, indentation: usize = 0, mode: []const u8 = "flat" };
pub fn text(s: []const u8) *Doc { return create(Doc, .{ .kind = .text, .value = s }); }
pub fn marker(kind: Kind) *Doc { return create(Doc, .{ .kind = kind }); }
pub fn child(kind: Kind, x: *Doc) *Doc { const c = alloc(*Doc, 1); c[0] = x; return create(Doc, .{ .kind = kind, .children = c }); }
pub fn nest(n: usize, x: *Doc) *Doc { const out = child(.nest, x); out.indentation = n; return out; }
pub fn conditional(a: []const u8, b: []const u8) *Doc { return create(Doc, .{ .kind = .if_break, .value = a, .alternate = b }); }
pub fn sequence(input: []const *Doc) *Doc {
    var out: std.ArrayList(*Doc) = .empty;
    for (input) |item| {
        const items = if (item.kind == .concat) item.children else &[_]*Doc{item};
        for (items) |x| { if (x.kind == .text and x.value.len == 0) continue;
            if (x.kind == .text and out.items.len > 0 and out.items[out.items.len - 1].kind == .text) { const old = out.items[out.items.len - 1]; out.items[out.items.len - 1] = text(fmt("{s}{s}", .{old.value, x.value})); }
            else append(*Doc, &out, x);
        }
    }
    return if (out.items.len == 0) text("") else if (out.items.len == 1) out.items[0] else create(Doc, .{ .kind = .concat, .children = out.items });
}
pub fn forced(x: *const Doc) bool { if (x.kind == .hardline or x.kind == .break_parent) return true; for (x.children) |y| if (forced(y)) return true; return false; }
pub const Metrics = struct { groups: usize = 0, broken: usize = 0, forced: usize = 0 };
pub fn metrics(x: *const Doc) Metrics {
    var m: Metrics = .{}; if (x.kind == .group) { m.groups = 1; m.broken = @intFromBool(!eq(x.mode, "flat")); m.forced = @intFromBool(eq(x.mode, "forced")); }
    for (x.children) |y| { const sub = metrics(y); m.groups += sub.groups; m.broken += sub.broken; m.forced += sub.forced; } return m;
}
