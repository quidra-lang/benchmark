const std = @import("std");
const r = @import("report.zig");
pub const Rule = enum { LFL, FOQ, POQ, MIN };
pub const Item = struct {
    id: []const u8,
    lead: i64,
    rule: Rule,
    first: i64,
    second: i64,
    safety: i64,
    on_hand: i64,
    material: i64,
    labor: i64,
    description: []const u8,
    pub fn label(item: Item) []const u8 { return switch (item.rule) { .LFL => "LFL", .MIN => r.fmt("MIN {d}/{d}", .{ item.first, item.second }), else => r.fmt("{s} {d}", .{ @tagName(item.rule), item.first }) }; }
};
pub fn find(items: []const Item, id: []const u8) ?usize { for (items, 0..) |item, i| { if (r.eq(item.id, id)) return i; } return null; }
fn lotValues(rule: Rule, text: []const u8) ?[2]i64 {
    const parts = r.split(text, '/');
    const first = r.integer(parts[0]);
    if (rule == .MIN) { if (parts.len != 2 or first < 1 or r.integer(parts[1]) < 1) return null; return .{ first, r.integer(parts[1]) }; }
    if (parts.len != 1 or (rule == .LFL and first != 0) or (rule != .LFL and first < 1)) return null;
    return .{ first, 0 };
}
fn itemLess(_: void, a: Item, b: Item) bool { return r.less(a.id, b.id); }
pub fn load(text: []const u8, errors: *std.ArrayList([]const u8)) []const Item {
    var result: std.ArrayList(Item) = .empty;
    for (r.rows(text)) |row| {
        const f = row.fields;
        if (find(result.items, f[0]) != null) { r.problem(errors, "items.csv", row.number, r.fmt("duplicate item {s}", .{f[0]})); continue; }
        var rule: ?Rule = null;
        inline for (@typeInfo(Rule).@"enum".field_names) |name| { if (r.eq(name, f[2])) rule = @field(Rule, name); }
        if (rule == null) { r.problem(errors, "items.csv", row.number, r.fmt("unknown lot rule {s}", .{f[2]})); continue; }
        const lot = lotValues(rule.?, f[3]) orelse { r.problem(errors, "items.csv", row.number, r.fmt("bad lot parameter {s} for {s}", .{ f[3], f[2] })); continue; };
        r.append(Item, &result, .{ .id = f[0], .lead = r.integer(f[1]), .rule = rule.?, .first = lot[0], .second = lot[1], .safety = r.integer(f[4]), .on_hand = r.integer(f[5]), .material = r.integer(f[6]), .labor = r.integer(f[7]), .description = f[8] });
    }
    std.mem.sort(Item, result.items, {}, itemLess);
    return result.items;
}
