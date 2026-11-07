const std = @import("std");
const d = @import("dataset.zig");
const a = @import("agglomerative.zig");
pub const Children = struct { upper: usize, lower: usize };
pub fn orderedChildren(merges: []const a.Merge, count: usize) []Children {
    var minimum: [239]usize = undefined;
    for (0..count) |index| minimum[index] = index;
    const children = d.alloc(Children, merges.len);
    for (merges, children, 0..) |merge, *pair, step| {
        pair.* = if (minimum[merge.a] < minimum[merge.b]) .{ .upper = merge.a, .lower = merge.b } else .{ .upper = merge.b, .lower = merge.a };
        minimum[count + step] = @min(minimum[merge.a], minimum[merge.b]);
    }
    return children;
}
pub fn leafOrder(children: []const Children, count: usize) []usize {
    const order = d.alloc(usize, count);
    var pending: [239]usize = undefined;
    pending[0] = count + children.len - 1;
    var length: usize = 1;
    var position: usize = 0;
    while (length > 0) {
        length -= 1;
        const node = pending[length];
        if (node < count) {
            order[position] = node;
            position += 1;
        } else {
            const pair = children[node - count];
            pending[length] = pair.lower;
            pending[length + 1] = pair.upper;
            length += 2;
        }
    }
    return order;
}
pub fn column(height: f64, height_max: f64, width: usize) usize {
    const value = @floor(height / height_max * d.f(width));
    return if (value > d.f(width)) width + 1 else @intFromFloat(value);
}
fn mark(grid: *[120][101]u8, row: usize, x: usize, priority: u8) void { grid[row][x] = @max(grid[row][x], priority); }
pub fn rows(merges: []const a.Merge, children: []const Children, order: []const usize, idents: []const []const u8, labels: []const []const u8, height_max: f64, cut_columns: []const usize, width: usize) d.Lines {
    const count = order.len;
    var grid: [120][101]u8 = @splat(@splat(0));
    var anchors: [239]usize = undefined;
    for (order, 0..) |leaf, row| anchors[leaf] = row;
    for (cut_columns) |x| {
        if (x <= width) for (0..count) |row| { mark(&grid, row, x, 1); };
    }
    var columns: [119]usize = undefined;
    for (merges, 0..) |merge, step| columns[step] = column(merge.height, height_max, width);
    for (children, 0..) |pair, step| {
        const x = columns[step];
        mark(&grid, anchors[pair.upper], x, 4);
        mark(&grid, anchors[pair.lower], x, 4);
        for (anchors[pair.upper] + 1..anchors[pair.lower]) |row| mark(&grid, row, x, 3);
        for ([_]usize{ pair.upper, pair.lower }) |child| {
            const start = if (child < count) 0 else columns[child - count] + 1;
            if (start < x) for (start..x) |position| { mark(&grid, anchors[child], position, 2); };
        }
        anchors[count + step] = (anchors[pair.upper] + anchors[pair.lower]) / 2;
    }
    var id_width: usize = 0;
    var label_width: usize = 0;
    for (idents, labels) |ident, label| { id_width = @max(id_width, ident.len); label_width = @max(label_width, label.len); }
    var result: d.Lines = .{};
    for (order, 0..) |leaf, row| {
        var text: d.Text = .{};
        text.add("{s}{s} {s}{s} ", .{ idents[leaf], d.repeat(' ', id_width - idents[leaf].len), labels[leaf], d.repeat(' ', label_width - labels[leaf].len) });
        for (grid[row][0 .. width + 1]) |priority| text.add("{c}", .{" :-|+"[priority]});
        result.write(std.mem.trimEnd(u8, text.value(), " "));
    }
    var scale: d.Text = .{};
    scale.write(d.repeat(' ', id_width + label_width + 2));
    for (0..width + 1) |x| scale.add("{c}", .{if (x % 10 == 0) @as(u8, '+') else '-'});
    result.write(scale.value());
    return result;
}
