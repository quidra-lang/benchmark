const std = @import("std");
const d = @import("sequence_io.zig");
const fm = @import("fm_index.zig");
pub fn lowerBounds(sequence: []const u8, reverse: fm.Index, allocator: std.mem.Allocator) []i64 {
    const out = allocator.alloc(i64, sequence.len) catch @panic("allocation failed");
    var interval: fm.Interval = .{ .lower = 0, .upper = reverse.size };
    var mismatches: i64 = 0;
    for (sequence, out) |base, *value| {
        interval = reverse.extend(interval, base);
        if (interval.empty()) {
            mismatches += 1;
            interval = .{ .lower = 0, .upper = reverse.size };
        }
        value.* = mismatches;
    }
    return out;
}
pub const Leaf = struct { lower: usize, upper: usize, mismatches: i64 };
pub const Search = struct { nodes: i64 = 0, positions: i64 = 0, leaves: []Leaf = &.{} };
pub fn backtrack(sequence: []const u8, maximum: i64, forward: fm.Index, reverse: fm.Index,
     allocator: std.mem.Allocator) Search {
    const State = struct { position: i64, remaining: i64, interval: fm.Interval };
    const bounds = lowerBounds(sequence, reverse, allocator);
    defer allocator.free(bounds);
    var stack: std.ArrayList(State) = .empty;
    defer stack.deinit(allocator);
    stack.append(allocator, .{ .position = d.n(sequence.len) - 1, .remaining = maximum, .interval = .{ .lower = 0,
         .upper = forward.size } }) catch @panic("allocation failed");
    var leaves: std.ArrayList(Leaf) = .empty;
    defer leaves.deinit(allocator);
    var out: Search = .{};
    while (stack.pop()) |state| {
        out.nodes += 1;
        if (state.remaining < (if (state.position < 0) @as(i64, 0) else bounds[d.u(state.position)])) continue;
        if (state.position == -1) {
            leaves.append(allocator, .{ .lower = state.interval.lower, .upper = state.interval.upper,
                 .mismatches = maximum - state.remaining }) catch @panic("allocation failed");
            out.positions += d.n(state.interval.upper - state.interval.lower);
            continue;
        }
        for ("TGCA") |base| {
            const next = forward.extend(state.interval, base);
            if (next.empty()) continue;
            const mismatch = base != sequence[d.u(state.position)];
            if (!mismatch or state.remaining >= 1) stack.append(allocator, .{ .position = state.position - 1,
                 .remaining = state.remaining - @as(i64, @intFromBool(mismatch)), .interval = next }) catch @panic("allocation failed");
        }
    }
    out.leaves = allocator.dupe(Leaf, leaves.items) catch @panic("allocation failed");
    return out;
}
