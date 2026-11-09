const std = @import("std");
const d = @import("sequence_io.zig");
pub fn symbolNumber(symbol: u8) usize {
    return switch (symbol) {
        '$' => 0,
        '#' => 1,
        'A' => 2,
        'C' => 3,
        'G' => 4,
        'T' => 5,
        else => unreachable,
    };
}
pub fn countingSort(positions: []const usize, keys: []const usize, key_count: usize) []usize {
    const counts = d.alloc(usize, key_count);
    @memset(counts, 0);
    for (positions) |position| counts[keys[position]] += 1;
    var offset: usize = 0;
    for (counts) |*count| {
        const size = count.*;
        count.* = offset;
        offset += size;
    }
    const out = d.alloc(usize, positions.len);
    for (positions) |position| {
        const key = keys[position];
        out[counts[key]] = position;
        counts[key] += 1;
    }
    return out;
}
pub const SuffixArray = struct { order: []const usize, classes: []const usize };
pub fn build(text: []const u8) SuffixArray {
    const size = text.len;
    const positions = d.alloc(usize, size);
    const codes = d.alloc(usize, size);
    var ranks = d.alloc(usize, size);
    for (text, positions, codes, 0..) |character, *position, *code, i| {
        position.* = i;
        code.* = symbolNumber(character);
    }
    var order = countingSort(positions, codes, 6);
    var count: usize = 0;
    var previous: ?usize = null;
    for (order) |position| {
        if (previous == null or codes[position] != previous.?) {
            count += 1;
            previous = codes[position];
        }
        ranks[position] = count - 1;
    }
    var classes: std.ArrayList(usize) = .empty;
    d.append(usize, &classes, count);
    var width: usize = 1;
    while (count < size) : (width *= 2) {
        const second = d.alloc(usize, size);
        for (second, 0..) |*key, i| key.* = if (i + width < size) ranks[i + width] + 1 else 0;
        order = countingSort(countingSort(positions, second, count + 1), ranks, count);
        const updated = d.alloc(usize, size);
        count = 0;
        var previous_first: ?usize = null;
        var previous_second: ?usize = null;
        for (order) |position| {
            if (previous_first == null or previous_first.? != ranks[position] or previous_second.? != second[position]) {
                count += 1;
                previous_first = ranks[position];
                previous_second = second[position];
            }
            updated[position] = count - 1;
        }
        ranks = updated;
        d.append(usize, &classes, count);
    }
    return .{ .order = order, .classes = classes.items };
}
fn directLess(text: []const u8, a: usize, b: usize) bool {
    return std.mem.order(u8, text[a..], text[b..]) == .lt;
}
pub fn directSort(text: []const u8) []const usize {
    const out = d.alloc(usize, text.len);
    for (out, 0..) |*position, i| position.* = i;
    std.mem.sort(usize, out, text, directLess);
    return out;
}
pub const Check = struct { ordered: usize = 0, lcp_sum: i64 = 0, maximum: usize = 0, row: usize = 1 };
pub fn adjacentCheck(text: []const u8, suffixes: []const usize) Check {
    var out: Check = .{};
    for (1..suffixes.len) |row| {
        const left = suffixes[row - 1];
        const right = suffixes[row];
        var common: usize = 0;
        while (text[left + common] == text[right + common]) common += 1;
        out.ordered += @intFromBool(symbolNumber(text[left + common]) < symbolNumber(text[right + common]));
        out.lcp_sum += d.n(common);
        if (common > out.maximum) {
            out.maximum = common;
            out.row = row;
        }
    }
    return out;
}
