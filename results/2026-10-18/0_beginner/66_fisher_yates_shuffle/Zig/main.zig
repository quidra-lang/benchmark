const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const ranks = "A23456789TJQK";
    const suits = "SHDC";
    var deck: [52][2]u8 = undefined;
    for (0..52) |i|
        deck[i] = .{ ranks[i % 13], suits[i / 13] };
    var state: u64 = 2026;
    var i: usize = 51;
    while (i > 0) : (i -= 1) {
        state = (state * 48271) % 2147483647;
        const j: usize = @intCast(state % (i + 1));
        const temp = deck[i];
        deck[i] = deck[j];
        deck[j] = temp;
    }
    for (deck, 0..) |card, k| {
        if (k % 13 > 0)
            try out.writeByte(' ');
        try out.print("{s}", .{ card });
        if (k % 13 == 12)
            try out.writeByte('\n');
    }
    try out.flush();
}
