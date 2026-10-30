const std = @import("std");
const d = @import("eventlog.zig");
pub const Trace = struct { activities: []const usize, weight: i64 = 1 };
pub const Counts = [12][12]i64;
pub const Relation = enum { unrelated, forward, backward, parallel };
pub const Relations = [12][12]Relation;
pub fn directlyFollows(log: []const Trace) Counts {
    var out: Counts = std.mem.zeroes(Counts);
    for (log) |trace| {
        var i: usize = 1;
        while (i < trace.activities.len) : (i += 1) out[trace.activities[i - 1]][trace.activities[i]] += trace.weight;
    }
    return out;
}
pub fn basicRelation(counts: *const Counts, a: usize, b: usize) Relation {
    const forward = counts[a][b] > 0;
    const backward = counts[b][a] > 0;
    return if (forward) (if (backward) .parallel else .forward) else (if (backward) .backward else .unrelated);
}
pub fn symbol(relation: Relation) []const u8 {
    return switch (relation) {
        .unrelated => "#",
        .forward => "->",
        .backward => "<-",
        .parallel => "||",
    };
}
fn padded(text: *d.Text, value: []const u8, width: usize) void {
    if (value.len < width) for (0..width - value.len) |_| text.add(" ", .{});
    text.add("{s}", .{value});
}
pub fn table(rows: []const []const []const u8, width: usize) d.Lines {
    var out: d.Lines = .{};
    var heading: d.Text = .{};
    heading.add("    ", .{});
    for (0..rows.len) |i| padded(&heading, d.fmt("{d}", .{i + 1}), width);
    out.add("{s}", .{heading.value()});
    for (rows, 0..) |row, i| {
        var text: d.Text = .{};
        padded(&text, d.fmt("{d}", .{i + 1}), 4);
        for (row) |value| padded(&text, value, width);
        out.add("{s}", .{text.value()});
    }
    return out;
}
pub fn footprint(activities: []const []const u8, ids: []const usize, relations: *const Relations) d.Lines {
    var out: d.Lines = .{};
    const rows = d.alloc([]const []const u8, ids.len);
    for (ids, rows, 0..) |a, *row, i| {
        out.add("ACTIVITY {d} {s}", .{ i + 1, activities[a] });
        const cells = d.alloc([]const u8, ids.len);
        for (ids, cells) |b, *cell| cell.* = symbol(relations[a][b]);
        row.* = cells;
    }
    out.extend(table(rows, 4));
    return out;
}
