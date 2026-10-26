const std = @import("std");

const Hand = struct { original: []const u8, category: u8, sequence: [5]u8, len: usize };

fn rankLess(counts: *const [15]u8, a: u8, b: u8) bool {
    return if (counts[a] != counts[b]) counts[a] > counts[b] else a > b;
}

fn evaluate(original: []const u8) Hand {
    var counts: [15]u8 = @splat(0);
    var flush = true;
    var suit: u8 = 0;
    var tokens = std.mem.splitScalar(u8, original, ' ');
    while (tokens.next()) |card| {
        const rank = std.mem.findScalar(u8, "23456789TJQKA", card[0]).? + 2;
        counts[rank] += 1;
        if (suit == 0)
            suit = card[1];
        if (card[1] != suit)
            flush = false;
    }
    var sequence: [5]u8 = undefined;
    var len: usize = 0;
    var pairs: u8 = 0;
    var triple = false;
    var four = false;
    for (2..15) |r| {
        if (counts[r] > 0) {
            sequence[len] = @intCast(r);
            len += 1;
        }
        if (counts[r] == 2)
            pairs += 1;
        if (counts[r] == 3)
            triple = true;
        if (counts[r] == 4)
            four = true;
    }
    const wheel = len == 5 and counts[14] == 1 and
        counts[2] == 1 and counts[3] == 1 and counts[4] == 1 and counts[5] == 1;
    const straight = len == 5 and (wheel or sequence[4] - sequence[0] == 4);
    std.mem.sort(u8, sequence[0..len], @as(*const [15]u8, &counts), rankLess);
    if (wheel)
        sequence = .{ 5, 4, 3, 2, 1 };
    const category: u8 = if (straight and flush)
        8
    else if (four)
        7
    else if (triple and pairs == 1)
        6
    else if (flush)
        5
    else if (straight)
        4
    else if (triple)
        3
    else if (pairs == 2)
        2
    else if (pairs == 1)
        1
    else
        0;
    return .{ .original = original, .category = category, .sequence = sequence, .len = len };
}

fn less(_: void, a: Hand, b: Hand) bool {
    if (a.category != b.category)
        return a.category > b.category;
    for (0..a.len) |i| {
        if (a.sequence[i] != b.sequence[i])
            return a.sequence[i] > b.sequence[i];
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const originals = [_][]const u8{
        "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
        "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D",
    };
    var hands: [8]Hand = undefined;
    for (originals, 0..) |s, i|
        hands[i] = evaluate(s);
    std.mem.sort(Hand, &hands, {}, less);
    const categories = [_][]const u8{
        "high card",
        "one pair",
        "two pair",
        "three of a kind",
        "straight",
        "flush",
        "full house",
        "four of a kind",
        "straight flush",
    };
    for (hands, 0..) |hand, i|
        try out.print("{d}. {s}: {s}\n", .{ i + 1, hand.original, categories[hand.category] });
    try out.flush();
}
