const std = @import("std");
const obj = @import("object_parser.zig");
pub const Resolution = struct {
    name: obj.Text, kind: enum { script, global, common, weak, @"undefined", weakundef }, definer: obj.Text = "-", definition: ?*obj.Symbol = null,
    entries: std.ArrayList(*obj.Symbol) = .empty, strong: std.ArrayList(obj.Text) = .empty, commons: std.ArrayList(*obj.Symbol) = .empty,
    referrers: std.ArrayList(obj.Text) = .empty, unresolved: std.ArrayList(obj.Text) = .empty,
    size: usize = 0, alignment: i64 = 1, address: i64 = 0, live: bool = false,
    pub fn kept(r: *Resolution) bool { return switch (r.kind) { .global, .weak => r.definition.?.section.?.live, .common => r.live, .script => true, else => false }; }
    pub fn value(r: *Resolution) ?i64 { return switch (r.kind) { .global, .weak => r.definition.?.section.?.location(r.definition.?.offset), .common, .script => r.address, .weakundef => 0, .@"undefined" => null }; }
};
pub fn unique(a: std.mem.Allocator, list: *std.ArrayList(obj.Text), name: obj.Text) !void { for (list.items) |n| if (obj.eq(n, name)) return; try list.append(a, name); }
pub fn resolve(a: std.mem.Allocator, name: obj.Text, objects: []const *obj.Object, script: bool) !*Resolution {
    const r = try a.create(Resolution); r.* = .{ .name = name, .kind = .weakundef };
    if (script) try r.strong.append(a, "*script*");
    var strong: ?*obj.Symbol = null; var weak: ?*obj.Symbol = null; var global_ref = false;
    for (objects) |o| for (o.symbols.items) |s| {
        if (s.binding == .local or !obj.eq(s.name, name)) continue; try r.entries.append(a, s);
        switch (s.kind) {
            .defined => if (s.binding == .global) { if (strong == null) strong = s; try r.strong.append(a, o.name); } else { if (weak == null) weak = s; },
            .common => { try r.commons.append(a, s); r.size = @max(r.size, s.size); r.alignment = @max(r.alignment, s.alignment); },
            .@"undefined" => { try unique(a, &r.referrers, o.name); global_ref = global_ref or s.binding == .global; },
        }
    };
    if (script) { r.kind = .script; r.definer = "*script*"; }
    else if (strong) |s| { r.kind = .global; r.definition = s; r.definer = s.owner.name; }
    else if (r.commons.items.len > 0) { r.kind = .common; for (r.commons.items) |s| if (s.size == r.size) { r.definer = s.owner.name; break; }; }
    else if (weak) |s| { r.kind = .weak; r.definition = s; r.definer = s.owner.name; }
    else if (global_ref) r.kind = .@"undefined";
    return r;
}
