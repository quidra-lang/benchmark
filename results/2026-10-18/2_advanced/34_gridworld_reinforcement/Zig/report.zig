const std = @import("std");
const e = @import("environment.zig");
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(e.allocator, e.fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        e.append([]const u8, &self.data, e.fmt(pattern, args));
    }
    pub fn extend(self: *Lines, other: Lines) void {
        for (other.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn fixed(value: i64) []const u8 {
    const magnitude = @abs(value);
    return e.fmt("{s}{d}.{d:0>4}", .{ if (value < 0) "-" else "", magnitude / 10000, magnitude % 10000 });
}
pub fn average(total: i64, count: usize) []const u8 {
    return fixed(@divFloor(10000 * total, e.n(count)));
}
pub fn cell(w: *const e.World, id: usize) []const u8 {
    return e.fmt("{d},{d}", .{ id / w.cols, id % w.cols });
}
pub fn cells(w: *const e.World, ids: []const usize) []const u8 {
    var text: Text = .{};
    for (ids, 0..) |id, i| text.add("{s}{s}", .{ if (i == 0) "" else " ", cell(w, id) });
    return text.value();
}
pub fn grid(w: *const e.World, fields: []const []const u8, separator: []const u8) Lines {
    var out: Lines = .{};
    for (0..w.rows) |row| {
        var text: Text = .{};
        for (0..w.cols) |column| {
            const id = row * w.cols + column;
            if (column > 0) text.add("{s}", .{separator});
            if (w.index[id]) |state| text.add("{s}", .{fields[state]}) else text.add("{c}", .{w.cells[id]});
        }
        out.add("{s}", .{text.value()});
    }
    return out;
}
pub fn valueGrid(w: *const e.World, values: []const i64) Lines {
    const fields = e.alloc([]const u8, values.len);
    for (values, fields) |value, *field| field.* = fixed(value);
    return grid(w, fields, " ");
}
pub fn policyGrid(w: *const e.World, policy: []const usize) Lines {
    const fields = e.alloc([]const u8, policy.len);
    for (policy, fields) |action, *field| field.* = e.fmt("{c}", .{"^>v<"[action]});
    return grid(w, fields, "");
}
pub fn qRows(w: *const e.World, name: []const u8, q: []const [4]i64, visits: ?e.Table) Lines {
    var out: Lines = .{};
    for (q, w.states, 0..) |row, id, state| for (row, 0..) |value, action| {
        out.add("{s},{s},{c},{s},{s}", .{ name, cell(w, id), "NESW"[action], fixed(value), if (visits) |counts| e.fmt("{d}",
             .{counts[state][action]}) else "-" });
    };
    return out;
}
pub fn parts(parts_: []const Lines) Lines {
    var out: Lines = .{};
    for (parts_, 0..) |part, i| {
        if (i > 0) out.add("", .{});
        out.extend(part);
    }
    return out;
}
pub fn write(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = e.fmt("output/{s}", .{name}), .data = text.value() });
}
