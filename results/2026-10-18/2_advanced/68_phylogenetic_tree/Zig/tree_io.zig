const std = @import("std");
const d = @import("alignment.zig");
const building = @import("tree_building.zig");
const Tree = building.Tree;
const Rooted = building.Rooted;
pub fn real(value: f64, comptime digits: usize) []const u8 {
    const rendered = d.fmt("{d:." ++ std.fmt.comptimePrint("{d}", .{digits}) ++ "}", .{value});
    if (rendered.len > 0 and rendered[0] == '-') {
        var zero = true;
        for (rendered[1..]) |character| if (character != '0' and character != '.') {
            zero = false;
        };
        if (zero) return rendered[1..];
    }
    return rendered;
}
pub fn symbols(mask: u32, size: usize) []const u8 {
    const out = d.alloc(u8, size);
    for (out, 0..) |*character, t| character.* = if (mask & d.bit(t) != 0) '*' else '.';
    return out;
}
fn orderedRoot(tree: *const Tree, names: []const []const u8, outgroup: usize) Rooted {
    var root = Rooted.init(tree, outgroup);
    var minimum = [_][]const u8{""} ** 32;
    var i = root.count;
    while (i > 0) {
        i -= 1;
        const node = root.order[i];
        if (node < tree.size) minimum[node] = names[node] else {
            const children = root.children[node][0..root.child_count[node]];
            for (1..children.len) |j| {
                const child = children[j];
                var k = j;
                while (k > 0 and std.mem.order(u8, minimum[children[k - 1]], minimum[child]) == .gt) : (k -= 1) children[k] = children[k - 1];
                children[k] = child;
            }
            minimum[node] = minimum[children[0]];
        }
    }
    return root;
}
fn render(text: *d.Text, tree: *const Tree, root: *const Rooted, names: []const []const u8,
     node: usize, lengths: bool, support: ?[]const i64) void {
    if (node < tree.size) text.add("{s}", .{names[node]}) else {
        text.add("(", .{});
        for (root.children[node][0..root.child_count[node]], 0..) |child, i| {
            if (i > 0) text.add(",", .{});
            render(text, tree, root, names, child, lengths, support);
        }
        text.add(")", .{});
        if (support) |counts| if (node != root.root) text.add("{d}", .{counts[root.masks[node]]});
    }
    if (lengths and node != root.root) text.add(":{s}", .{real(tree.length[node][root.parent[node].?], 5)});
}
pub fn newick(tree: *const Tree, names: []const []const u8, outgroup: usize, lengths: bool,
     support: ?[]const i64) []const u8 {
    const root = orderedRoot(tree, names, outgroup);
    var text: d.Text = .{};
    render(&text, tree, &root, names, root.root, lengths, support);
    text.add(";", .{});
    return text.value();
}
fn draw(out: *d.Lines, tree: *const Tree, root: *const Rooted, names: []const []const u8, support: []const i64,
     node: usize, prefix: []const u8) void {
    const children = root.children[node][0..root.child_count[node]];
    for (children, 0..) |child, i| {
        const last = i + 1 == children.len;
        const label = if (child < tree.size) names[child] else d.fmt("[{d}]", .{support[root.masks[child]]});
        out.add("{s}{s}{s}", .{ prefix, if (last) "`-- " else "|-- ", label });
        draw(out, tree, root, names, support, child, d.fmt("{s}{s}", .{ prefix, if (last) "    " else "|   " }));
    }
}
pub fn cladogram(tree: *const Tree, names: []const []const u8, outgroup: usize, support: []const i64) d.Lines {
    const root = orderedRoot(tree, names, outgroup);
    var out: d.Lines = .{};
    out.add("*", .{});
    draw(&out, tree, &root, names, support, root.root, "");
    return out;
}
pub fn save(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
