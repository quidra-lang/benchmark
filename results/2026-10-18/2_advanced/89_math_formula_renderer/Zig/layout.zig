const b = @import("boxes.zig");
const p = @import("parser.zig");
pub const Params = struct { width: i64 = 80, indent: i64 = 2, rel_space: i64 = 1, bin_space: i64 = 1, punct_space: i64 = 1, col_gap: i64 = 2, row_gap: i64 = 0 };
pub const Types = struct { left: b.Type, right: b.Type };
pub fn types(n: *const p.Node) Types {
    if (b.eq(n.kind, "script")) return types(n.children[0]);
    if (b.eq(n.kind, "overset") or b.eq(n.kind, "underset")) return types(n.children[1]);
    if (b.eq(n.kind, "delim")) return .{ .left = .open, .right = .close };
    var t: b.Type = .ordinary;
    if (b.eq(n.kind, "symbol")) {
        if (b.eq(n.value, "+") or b.eq(n.value, "-") or b.eq(n.value, "*")) t = .binary
        else if (b.eq(n.value, "=") or b.eq(n.value, "<") or b.eq(n.value, ">") or b.eq(n.value, ":")) t = .relation
        else if (b.eq(n.value, "(") or b.eq(n.value, "[")) t = .open
        else if (b.eq(n.value, ")") or b.eq(n.value, "]") or b.eq(n.value, "!")) t = .close
        else if (b.eq(n.value, ",") or b.eq(n.value, ";")) t = .punctuation;
    } else if (b.eq(n.kind, "command")) t = b.symbol(n.value[1..]).?.typ;
    return .{ .left = t, .right = t };
}
pub fn word(n: *const p.Node) bool { if (b.eq(n.kind, "script")) return word(n.children[0]); return b.eq(n.kind, "command") and b.symbol(n.value[1..]).?.word; }
pub fn alphanumeric(n: *const p.Node) bool {
    if (b.eq(n.kind, "script")) return alphanumeric(n.children[0]);
    if (b.eq(n.kind, "accent") and !b.eq(n.value, "overbrace") and !b.eq(n.value, "underbrace")) return alphanumeric(n.children[0]);
    return b.eq(n.kind, "identifier") or b.eq(n.kind, "number") or word(n);
}
pub fn converted(nodes: []const *p.Node) []Types {
    const ts = b.alloc(Types, nodes.len); for (nodes, ts) |n, *t| t.* = types(n);
    for (ts, 0..) |*t, i| {
        if (t.left == .binary and (i == 0 or ts[i - 1].right == .binary or ts[i - 1].right == .operator or ts[i - 1].right == .relation or ts[i - 1].right == .open or ts[i - 1].right == .punctuation)) t.* = .{ .left = .ordinary, .right = .ordinary };
        if ((t.left == .relation or t.left == .close or t.left == .punctuation) and i > 0 and ts[i - 1].right == .binary) ts[i - 1] = .{ .left = .ordinary, .right = .ordinary };
    }
    if (ts.len > 0 and ts[ts.len - 1].right == .binary) ts[ts.len - 1] = .{ .left = .ordinary, .right = .ordinary }; return ts;
}
pub fn gaps(nodes: []const *p.Node, ts: []const Types, params: Params, script: bool) []i64 {
    const out = b.alloc(i64, if (nodes.len > 0) nodes.len - 1 else 0);
    const table = [_][7]i8{ .{0,1,-1,-2,0,0,0}, .{1,1,0,-2,0,0,0}, .{-1,-1,0,0,-1,0,0}, .{-2,-2,0,0,-2,0,0}, .{0,0,0,0,0,0,0}, .{0,1,-1,-2,0,0,0}, .{-3,-3,0,-3,-3,-3,-3} };
    for (out, 0..) |*g, i| {
        if (alphanumeric(nodes[i]) and alphanumeric(nodes[i + 1]) and (word(nodes[i]) or word(nodes[i + 1]))) { g.* = 1; continue; }
        const value = table[@intFromEnum(ts[i].right)][@intFromEnum(ts[i + 1].left)];
        g.* = if (value >= 0) value else if (script) 0 else switch (value) { -1 => params.bin_space, -2 => params.rel_space, else => params.punct_space };
    }
    return out;
}
pub fn row(boxes: []const *b.Box, spacing: []const i64, description: []const u8) *b.Box {
    var ascent: i64 = 0; var descent: i64 = 0; var width: i64 = 0;
    for (boxes, 0..) |x, i| { ascent = @max(ascent, x.baseline); descent = @max(descent, x.h - 1 - x.baseline); if (i > 0) width += spacing[i - 1]; width += x.w; }
    const out = b.box(description, width, ascent + descent + 1, ascent); var x: i64 = 0;
    for (boxes, 0..) |child, i| { if (i > 0) x += spacing[i - 1]; out.place(child, x, ascent - child.baseline, ""); x += child.w; } return out;
}
