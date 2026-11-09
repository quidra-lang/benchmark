const std = @import("std");
const b = @import("baskets.zig");
pub const Candidates = struct { joined: usize, excluded: usize, pruned: usize, masks: []const u128 };
fn prefix(mask: u128) u128 { return mask ^ b.bit(127 - @as(usize, @intCast(@clz(mask)))); }
pub fn generate(previous: []const b.Frequent, size: usize, taxonomy: []const u128) Candidates {
    const ordered = b.alloc(u128, previous.len); var known: b.Counts = .empty;
    for (previous, ordered) |entry, *mask| { mask.* = entry.mask; b.put(&known, entry.mask, entry.count); }
    std.mem.sort(u128, ordered, {}, b.maskLess);
    var result: Candidates = .{ .joined = 0, .excluded = 0, .pruned = 0, .masks = &.{} }; var masks: std.ArrayList(u128) = .empty;
    for (ordered, 0..) |first, i| {
        for (ordered[i + 1..]) |second| {
            if (prefix(first) != prefix(second)) break;
            result.joined += 1; const mask = first | second; var excluded = false;
            if (size == 2) for (taxonomy) |pair| { if (b.contains(mask, pair)) { excluded = true; break; } };
            if (excluded) { result.excluded += 1; continue; }
            var it = b.iterator(mask); var pruned = false;
            while (it.next()) |code| { if (!known.contains(mask ^ b.bit(code))) { pruned = true; break; } }
            if (pruned) result.pruned += 1 else b.append(u128, &masks, mask);
        }
    }
    result.masks = masks.items; return result;
}
pub fn support(baskets: []const u128, mask: u128) i64 { var total: i64 = 0; for (baskets) |basket| { if (b.contains(basket, mask)) total += 1; } return total; }
pub fn count(baskets: []const u128, candidates: []const u128) []const b.Frequent { const result = b.alloc(b.Frequent, candidates.len); for (candidates, result) |mask, *entry| entry.* = .{ .mask = mask, .count = support(baskets, mask) }; return result; }
