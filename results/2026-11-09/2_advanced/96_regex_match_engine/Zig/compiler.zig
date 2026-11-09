const std = @import("std");
const chars = @import("charset.zig");
pub const Node = struct {
    kind: enum { literal, any, class, assertion, backref, group, look, concat, alternation, repeat },
    value: usize = 0, set: chars.Set = chars.Set.initEmpty(), neg: bool = false,
    children: []*Node = &.{}, child: ?*Node = null, lower: usize = 0, upper: ?usize = null,
    mode: enum { greedy, lazy, possessive } = .greedy, name: ?[]const u8 = null, column: usize = 0,
};
pub const Op = enum { CHAR, ANY, CLASS, SPLIT, JMP, SAVE, ASSERT, BACKREF, LOOK, MATCH };
pub const Look = enum { AHEAD, NOT, ATOMIC };
pub const Instruction = struct { op: Op, x: usize = 0, y: usize = 0, set: chars.Set = chars.Set.initEmpty(), neg: bool = false, assertion: chars.Assertion = .BOL, look: Look = .AHEAD };
pub const Builder = struct {
    a: std.mem.Allocator, instructions: std.ArrayList(Instruction) = .empty,
    fn emit(b: *Builder, ins: Instruction) !usize { const p = b.instructions.items.len; try b.instructions.append(b.a, ins); return p; }
    pub fn node(b: *Builder, n: *const Node) anyerror!void {
        switch (n.kind) {
            .literal => { _ = try b.emit(.{ .op = .CHAR, .x = n.value }); },
            .any => { _ = try b.emit(.{ .op = .ANY }); },
            .class => { _ = try b.emit(.{ .op = .CLASS, .set = n.set, .neg = n.neg }); },
            .assertion => { _ = try b.emit(.{ .op = .ASSERT, .assertion = @enumFromInt(n.value) }); },
            .backref => { _ = try b.emit(.{ .op = .BACKREF, .x = n.value }); },
            .group => { _ = try b.emit(.{ .op = .SAVE, .x = 2 * n.value }); try b.node(n.child.?); _ = try b.emit(.{ .op = .SAVE, .x = 2 * n.value + 1 }); },
            .look => { const p = try b.emit(.{ .op = .LOOK, .look = if (n.neg) .NOT else .AHEAD }); try b.node(n.child.?); _ = try b.emit(.{ .op = .MATCH }); b.instructions.items[p].x = b.instructions.items.len; },
            .concat => for (n.children) |c| try b.node(c),
            .alternation => {
                var jumps: std.ArrayList(usize) = .empty;
                for (n.children[0..n.children.len - 1]) |c| {
                    const p = try b.emit(.{ .op = .SPLIT, .x = b.instructions.items.len + 1 });
                    try b.node(c); try jumps.append(b.a, try b.emit(.{ .op = .JMP })); b.instructions.items[p].y = b.instructions.items.len;
                }
                try b.node(n.children[n.children.len - 1]);
                for (jumps.items) |p| b.instructions.items[p].x = b.instructions.items.len;
            },
            .repeat => {
                if (n.mode == .possessive) {
                    const p = try b.emit(.{ .op = .LOOK, .look = .ATOMIC });
                    var copy = n.*; copy.mode = .greedy; try b.node(&copy);
                    _ = try b.emit(.{ .op = .MATCH }); b.instructions.items[p].x = b.instructions.items.len; return;
                }
                if (n.upper == null and n.lower == 0) {
                    const p = try b.emit(.{ .op = .SPLIT }); const next = b.instructions.items.len;
                    try b.node(n.child.?); _ = try b.emit(.{ .op = .JMP, .x = p }); b.split(p, next, b.instructions.items.len, n.mode == .lazy);
                } else if (n.upper == null) {
                    for (0..n.lower - 1) |_| try b.node(n.child.?);
                    const first = b.instructions.items.len; try b.node(n.child.?); const p = try b.emit(.{ .op = .SPLIT }); b.split(p, first, b.instructions.items.len, n.mode == .lazy);
                } else {
                    for (0..n.lower) |_| try b.node(n.child.?);
                    var optional: std.ArrayList(usize) = .empty;
                    for (n.lower..n.upper.?) |_| { const p = try b.emit(.{ .op = .SPLIT }); try optional.append(b.a, p); try b.node(n.child.?); }
                    for (optional.items) |p| b.split(p, p + 1, b.instructions.items.len, n.mode == .lazy);
                }
            },
        }
    }
    fn split(b: *Builder, p: usize, yes: usize, no: usize, lazy: bool) void { b.instructions.items[p].x = if (lazy) no else yes; b.instructions.items[p].y = if (lazy) yes else no; }
    pub fn compile(b: *Builder, root: *Node) ![]const Instruction { _ = try b.emit(.{ .op = .SAVE }); try b.node(root); _ = try b.emit(.{ .op = .SAVE, .x = 1 }); _ = try b.emit(.{ .op = .MATCH }); return b.instructions.items; }
};
pub const Properties = struct { min: usize = 0, max: ?usize = 0, first: chars.Set = chars.Set.initEmpty(), nullable: bool = true };
pub fn properties(n: *const Node, flags: []const u8) Properties {
    var p: Properties = .{};
    switch (n.kind) {
        .literal, .any, .class => {
            p.min = 1; p.max = 1; p.nullable = false;
            for (0..128) |x| { const c: u8 = @intCast(x); if (switch (n.kind) { .literal => chars.same(c, @intCast(n.value), flags), .any => c != 10 or std.mem.indexOfScalar(u8, flags, 's') != null, .class => chars.class(n.set, n.neg, c, flags), else => false }) p.first.set(x); }
        },
        .assertion, .look => {},
        .backref => { p.max = null; p.first = chars.Set.initFull(); },
        .group => return properties(n.child.?, flags),
        .repeat => { p = properties(n.child.?, flags); p.min *= n.lower; p.max = if (p.max == 0) 0 else if (p.max == null or n.upper == null) null else p.max.? * n.upper.?; if (n.upper == 0) p.first = chars.Set.initEmpty(); p.nullable = n.lower == 0 or n.upper == 0 or p.nullable; },
        .concat => for (n.children) |c| { const v = properties(c, flags); p.min += v.min; p.max = if (p.max != null and v.max != null) p.max.? + v.max.? else null; if (p.nullable) { p.first.setUnion(v.first); p.nullable = v.nullable; } },
        .alternation => { p.min = std.math.maxInt(usize); p.nullable = false; for (n.children) |c| { const v = properties(c, flags); p.min = @min(p.min, v.min); p.max = if (p.max != null and v.max != null) @max(p.max.?, v.max.?) else null; p.first.setUnion(v.first); p.nullable = p.nullable or v.nullable; } },
    }
    return p;
}
