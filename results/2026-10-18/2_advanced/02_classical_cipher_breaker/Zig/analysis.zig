const std = @import("std");
const scoring = @import("scoring.zig");

pub fn letterCounts(text: []const u8) [26]i64 {
    var counts: [26]i64 = @splat(0);
    for (text) |c| counts[scoring.value(c)] += 1;
    return counts;
}

fn coincidence(counts: [26]i64, length: usize) i64 {
    if (length < 2) return 0;
    var sum: i64 = 0;
    for (counts) |count| sum += count * (count - 1);
    const n: i64 = @intCast(length);
    return @divFloor(100000 * sum, n * (n - 1));
}

pub fn indexOfCoincidence(text: []const u8) i64 {
    return coincidence(letterCounts(text), text.len);
}

pub fn columnIndices(gpa: std.mem.Allocator, text: []const u8, period: usize) []const i64 {
    const indices = gpa.alloc(i64, period) catch @panic("allocation failed");
    for (0..period) |column| {
        var counts: [26]i64 = @splat(0);
        var length: usize = 0;
        var position = column;
        while (position < text.len) : (position += period) {
            counts[scoring.value(text[position])] += 1;
            length += 1;
        }
        indices[column] = coincidence(counts, length);
    }
    return indices;
}

fn gcd(first: usize, second: usize) usize {
    var a = first;
    var b = second;
    while (b != 0) {
        const next = a % b;
        a = b;
        b = next;
    }
    return a;
}

pub const Repeat = struct {
    trigram: [3]u8,
    positions: []const usize,
    gaps: []const usize,
    divisor: usize,
};

fn repeatLess(_: void, a: Repeat, b: Repeat) bool {
    for (a.trigram, b.trigram) |first, second| {
        if (first != second) return first < second;
    }
    return false;
}

pub fn repeatedTrigrams(gpa: std.mem.Allocator, text: []const u8) []const Repeat {
    var positions: std.AutoHashMapUnmanaged(usize, std.ArrayList(usize)) = .empty;
    defer positions.deinit(gpa);
    var start: usize = 0;
    while (start + 2 < text.len) : (start += 1) {
        const code = (scoring.value(text[start]) * 26 + scoring.value(text[start + 1])) * 26 + scoring.value(text[start + 2]);
        const entry = positions.getOrPut(gpa, code) catch @panic("allocation failed");
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        entry.value_ptr.append(gpa, start + 1) catch @panic("allocation failed");
    }
    var result: std.ArrayList(Repeat) = .empty;
    var it = positions.iterator();
    while (it.next()) |entry| {
        const found = entry.value_ptr.items;
        if (found.len < 2) {
            entry.value_ptr.deinit(gpa);
            continue;
        }
        const code = entry.key_ptr.*;
        const gaps = gpa.alloc(usize, found.len - 1) catch @panic("allocation failed");
        var divisor: usize = 0;
        for (gaps, 0..) |*gap, i| {
            gap.* = found[i + 1] - found[i];
            divisor = gcd(divisor, gap.*);
        }
        result.append(gpa, .{
            .trigram = .{ 'A' + @as(u8, @intCast(code / 676)), 'A' + @as(u8, @intCast(code / 26 % 26)), 'A' + @as(u8, @intCast(code % 26)) },
            .positions = found,
            .gaps = gaps,
            .divisor = divisor,
        }) catch @panic("allocation failed");
    }
    std.mem.sort(Repeat, result.items, {}, repeatLess);
    return result.items;
}

pub fn percentage(gpa: std.mem.Allocator, count: i64, length: usize) []const u8 {
    const n: i64 = @intCast(length);
    const tenths = @divFloor(2000 * count + n, 2 * n);
    return std.fmt.allocPrint(gpa, "{d}.{d}", .{ @divFloor(tenths, 10), @mod(tenths, 10) }) catch @panic("allocation failed");
}

pub const PairCount = struct { pair: [2]u8, count: usize };

fn pairLess(_: void, a: PairCount, b: PairCount) bool {
    if (a.count != b.count) return a.count > b.count;
    if (a.pair[0] != b.pair[0]) return a.pair[0] < b.pair[0];
    return a.pair[1] < b.pair[1];
}

pub fn pairCounts(gpa: std.mem.Allocator, text: []const u8, step: usize, merge_j: bool) []const PairCount {
    var counts: [676]usize = @splat(0);
    var i: usize = 0;
    while (i + 1 < text.len) : (i += step) {
        const first = if (merge_j and text[i] == 'J') @as(u8, 'I') else text[i];
        const second = if (merge_j and text[i + 1] == 'J') @as(u8, 'I') else text[i + 1];
        counts[scoring.value(first) * 26 + scoring.value(second)] += 1;
    }
    var result: std.ArrayList(PairCount) = .empty;
    for (counts, 0..) |count, code| {
        if (count != 0) result.append(gpa, .{
            .pair = .{ 'A' + @as(u8, @intCast(code / 26)), 'A' + @as(u8, @intCast(code % 26)) },
            .count = count,
        }) catch @panic("allocation failed");
    }
    std.mem.sort(PairCount, result.items, {}, pairLess);
    return result.items;
}
