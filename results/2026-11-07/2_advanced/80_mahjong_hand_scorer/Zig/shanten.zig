const std = @import("std");
const t = @import("tiles.zig");
const Patterns = [5][2]i8;
pub var cache_allocator: std.mem.Allocator = undefined;
var pattern_cache: std.AutoHashMapUnmanaged(u64, Patterns) = .empty;
var number_cache: std.AutoHashMapUnmanaged(t.Counts, [3]i64) = .empty;
fn keyOf(counts: [9]u8, suited: bool) u64 {
    var key: u64 = @intFromBool(suited);
    for (counts) |count| key = key * 5 + count;
    return key;
}
fn addChoice(best: *Patterns, counts: [9]u8, suited: bool, sets: usize, partial: i8, pair: usize) void {
    const child = patterns(counts, suited);
    for (0..5 - sets) |m| for (0..2 - pair) |h| if (child[m][h] >= 0) {
        best[m + sets][h + pair] = @max(best[m + sets][h + pair], @min(4, child[m][h] + partial));
    };
}
fn patterns(counts: [9]u8, suited: bool) Patterns {
    const key = keyOf(counts, suited);
    if (pattern_cache.get(key)) |value| return value;
    var best: Patterns = @splat(@splat(-1));
    var first: usize = 0;
    while (first < 9 and counts[first] == 0) : (first += 1) {}
    if (first == 9) best[0][0] = 0 else {
        var rest = counts;
        rest[first] -= 1;
        addChoice(&best, rest, suited, 0, 0, 0);
        if (counts[first] >= 3) {
            rest = counts;
            rest[first] -= 3;
            addChoice(&best, rest, suited, 1, 0, 0);
        }
        if (counts[first] >= 2) {
            rest = counts;
            rest[first] -= 2;
            addChoice(&best, rest, suited, 0, 1, 0);
            addChoice(&best, rest, suited, 0, 0, 1);
        }
        if (suited) {
            if (first <= 6 and counts[first + 1] > 0 and counts[first + 2] > 0) {
                rest = counts;
                for (first..first + 3) |i| rest[i] -= 1;
                addChoice(&best, rest, true, 1, 0, 0);
            }
            for (1..3) |difference| {
                const other = first + difference;
                if (other < 9 and counts[other] > 0) {
                    rest = counts;
                    rest[first] -= 1;
                    rest[other] -= 1;
                    addChoice(&best, rest, true, 0, 1, 0);
                }
            }
        }
    }
    pattern_cache.put(cache_allocator, key, best) catch @panic("allocation failed");
    return best;
}
pub fn standard(counts: t.Counts) i64 {
    var states: Patterns = @splat(@splat(-1));
    states[0][0] = 0;
    for (0..4) |suit| {
        var local_counts: [9]u8 = @splat(0);
        const size: usize = if (suit == 3) 7 else 9;
        for (0..size) |i| local_counts[i] = @intCast(counts[suit * 9 + i]);
        const local = patterns(local_counts, suit < 3);
        var next: Patterns = @splat(@splat(-1));
        for (0..5) |m| for (0..2) |h| if (states[m][h] >= 0) {
            for (0..5 - m) |lm| for (0..2 - h) |lh| if (local[lm][lh] >= 0) {
                next[m + lm][h + lh] = @max(next[m + lm][h + lh], @min(4, states[m][h] + local[lm][lh]));
            };
        };
        states = next;
    }
    var best: i64 = 8;
    for (0..5) |m| for (0..2) |h| if (states[m][h] >= 0) {
        best = @min(best, 8 - 2 * t.n(m) - @min(@as(i64, states[m][h]), 4 - t.n(m)) - t.n(h));
    };
    return best;
}
pub fn numbers(counts: t.Counts) [3]i64 {
    if (number_cache.get(counts)) |value| return value;
    var pairs: i64 = 0;
    var kinds: i64 = 0;
    for (counts) |count| {
        pairs += @intFromBool(count >= 2);
        kinds += @intFromBool(count > 0);
    }
    var orphans: i64 = 13;
    var duplicate = false;
    for (t.orphans) |kind| {
        orphans -= @intFromBool(counts[kind] > 0);
        duplicate = duplicate or counts[kind] >= 2;
    }
    orphans -= @intFromBool(duplicate);
    const result = [3]i64{ standard(counts), 6 - pairs + @max(0, 7 - kinds), orphans };
    number_cache.put(cache_allocator, counts, result) catch @panic("allocation failed");
    return result;
}
pub fn minimum(values: [3]i64) i64 {
    return @min(values[0], @min(values[1], values[2]));
}
