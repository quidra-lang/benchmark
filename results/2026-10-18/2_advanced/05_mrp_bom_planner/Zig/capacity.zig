const std = @import("std");
const r = @import("report.zig");
const master = @import("items.zig");
const bom = @import("bom.zig");
pub const Center = struct { id: []const u8, minutes: i64, efficiency: i64, available: i64, description: []const u8 };
pub const Operation = struct { number: i64, center: usize, setup: i64, run: i64, pub fn minutes(operation: Operation, quantity: i64) i64 { return operation.setup + quantity * operation.run; } };
pub fn find(centers: []const Center, id: []const u8) ?usize { for (centers, 0..) |center, i| { if (r.eq(center.id, id)) return i; } return null; }
fn centerLess(_: void, a: Center, b: Center) bool { return r.less(a.id, b.id); }
fn operationLess(_: void, a: Operation, b: Operation) bool { return a.number < b.number; }
pub fn loadCenters(text: []const u8, errors: *std.ArrayList([]const u8)) []const Center {
    var result: std.ArrayList(Center) = .empty;
    for (r.rows(text)) |row| {
        const f = row.fields;
        if (find(result.items, f[0]) != null) { r.problem(errors, "workcenters.csv", row.number, r.fmt("duplicate center {s}", .{f[0]})); continue; }
        const efficiency = r.integer(f[2]);
        if (efficiency < 50 or efficiency > 150) { r.problem(errors, "workcenters.csv", row.number, r.fmt("bad efficiency {d}", .{efficiency})); continue; }
        const minutes = r.integer(f[1]);
        r.append(Center, &result, .{ .id = f[0], .minutes = minutes, .efficiency = efficiency, .available = @divFloor(minutes * efficiency, 100), .description = f[3] });
    }
    std.mem.sort(Center, result.items, {}, centerLess);
    return result.items;
}
pub fn loadRoutings(text: []const u8, items: []const master.Item, centers: []const Center, graph: bom.Graph, errors: *std.ArrayList([]const u8)) []std.ArrayList(Operation) {
    const result = r.alloc(std.ArrayList(Operation), items.len);
    @memset(result, .empty);
    for (r.rows(text)) |row| {
        const f = row.fields;
        const item = master.find(items, f[0]) orelse { r.problem(errors, "routings.csv", row.number, r.fmt("unknown item {s}", .{f[0]})); continue; };
        const center = find(centers, f[2]) orelse { r.problem(errors, "routings.csv", row.number, r.fmt("unknown center {s}", .{f[2]})); continue; };
        if (!graph.manufactured(item)) { r.problem(errors, "routings.csv", row.number, r.fmt("purchased item {s}", .{f[0]})); continue; }
        const run = r.integer(f[4]);
        if (run < 1) { r.problem(errors, "routings.csv", row.number, r.fmt("bad run time {d}", .{run})); continue; }
        const number = r.integer(f[1]);
        var duplicate = false;
        for (result[item].items) |operation| { if (operation.number == number) duplicate = true; }
        if (duplicate) { r.problem(errors, "routings.csv", row.number, r.fmt("duplicate {s} operation {d}", .{ f[0], number })); continue; }
        r.append(Operation, &result[item], .{ .number = number, .center = center, .setup = r.integer(f[3]), .run = run });
    }
    for (result) |operations| std.mem.sort(Operation, operations.items, {}, operationLess);
    return result;
}
pub fn operationWeek(receipt: usize, lead: i64, index: usize, count: usize) usize { return @intCast(@max(1, @as(i64, @intCast(receipt)) - lead + @divFloor(@as(i64, @intCast(index)) * lead, @as(i64, @intCast(count))))); }
pub fn level(loads: []const i64, available: i64) []const i64 {
    const result = r.alloc(i64, loads.len);
    @memset(result, 0);
    var carry: i64 = 0;
    var week = loads.len - 1;
    while (week > 1) : (week -= 1) { const total = loads[week] + carry; result[week] = @min(total, available); carry = total - result[week]; }
    result[1] = loads[1] + carry;
    return result;
}
