const std = @import("std");
const t = @import("tiles.zig");
pub const Decomposition = struct { pair: usize, sets: [4]t.Block, count: usize };
fn blockLess(_: void, left: t.Block, right: t.Block) bool {
    return if (left.first == right.first) !left.sequence and right.sequence else left.first < right.first;
}
fn visit(counts: *t.Counts, pair: usize, sets: *[4]t.Block, used: usize, needed: usize, found: *std.ArrayList(Decomposition)) void {
    var first: usize = 0;
    while (first < 34 and counts[first] == 0) : (first += 1) {}
    if (used == needed) {
        if (first < 34) return;
        var ordered = sets.*;
        std.mem.sort(t.Block, ordered[0..used], {}, blockLess);
        for (found.items) |existing| {
            if (existing.pair != pair) continue;
            var same = true;
            for (existing.sets[0..used], ordered[0..used]) |a, b| same = same and a.same(b);
            if (same) return;
        }
        t.append(Decomposition, found, .{ .pair = pair, .sets = ordered, .count = used });
        return;
    }
    if (first == 34) return;
    if (counts[first] >= 3) {
        counts[first] -= 3;
        sets[used] = .{ .first = first };
        visit(counts, pair, sets, used + 1, needed, found);
        counts[first] += 3;
    }
    if (first < 27 and first % 9 <= 6 and counts[first + 1] > 0 and counts[first + 2] > 0) {
        for (first..first + 3) |kind| counts[kind] -= 1;
        sets[used] = .{ .first = first, .sequence = true };
        visit(counts, pair, sets, used + 1, needed, found);
        for (first..first + 3) |kind| counts[kind] += 1;
    }
}
pub fn standard(source: t.Counts, meld_count: usize) []const Decomposition {
    var out: std.ArrayList(Decomposition) = .empty;
    var total: usize = 0;
    for (source) |count| total += count;
    if (meld_count > 4 or total != (4 - meld_count) * 3 + 2) return out.items;
    var counts = source;
    var sets: [4]t.Block = @splat(.{ .first = 0 });
    for (0..34) |pair| if (counts[pair] >= 2) {
        counts[pair] -= 2;
        visit(&counts, pair, &sets, 0, 4 - meld_count, &out);
        counts[pair] += 2;
    };
    return out.items;
}
pub fn sevenPairs(counts: t.Counts) bool {
    var pairs: usize = 0;
    for (counts) |count| {
        if (count == 2) pairs += 1 else if (count != 0) return false;
    }
    return pairs == 7;
}
pub fn thirteenOrphans(counts: t.Counts) bool {
    var total: usize = 0;
    for (counts, 0..) |count, kind| {
        total += count;
        if (t.yaochuu(kind)) {
            if (count == 0) return false;
        } else if (count != 0) return false;
    }
    return total == 14;
}
pub fn winning(counts: t.Counts, meld_count: usize) bool {
    return standard(counts, meld_count).len > 0 or (meld_count == 0 and (sevenPairs(counts) or thirteenOrphans(counts)));
}
pub fn waitingTiles(hand: t.Counts, melds: t.Counts, meld_count: usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    var counts = hand;
    for (0..34) |kind| {
        if (@as(usize, hand[kind]) + melds[kind] >= 4) continue;
        counts[kind] += 1;
        if (winning(counts, meld_count)) t.append(usize, &out, kind);
        counts[kind] -= 1;
    }
    return out.items;
}
pub const Wait = enum { ryanmen, kanchan, penchan, shanpon, tanki, single, thirteen };
pub const wait_names = [_][]const u8{ "ryanmen", "kanchan", "penchan", "shanpon", "tanki", "single", "thirteen" };
pub fn waitShape(block: t.Block, winning: usize) Wait {
    if (block.size == 2) return .tanki;
    if (!block.sequence) return .shanpon;
    if (winning == block.first + 1) return .kanchan;
    if ((block.first % 9 == 0 and winning == block.first + 2) or (block.first % 9 == 6 and winning == block.first)) return .penchan;
    return .ryanmen;
}
pub fn orphanWait(hand: t.Counts) Wait {
    for (t.orphans) |kind| if (hand[kind] != 1) return .single;
    return .thirteen;
}
