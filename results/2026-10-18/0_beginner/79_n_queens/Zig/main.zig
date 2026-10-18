const std = @import("std");

fn solve(n: usize, row: usize, queens: *[8]usize, count: *u32, first: *[8]usize) void {
    if (row == n) {
        count.* += 1;
        if (n == 8 and count.* == 1)
            first.* = queens.*;
        return;
    }
    for (0..n) |col| {
        var safe = true;
        for (0..row) |r| {
            const delta = if (queens[r] > col) queens[r] - col else col - queens[r];
            if (queens[r] == col or delta == row - r) {
                safe = false;
                break;
            }
        }
        if (safe) {
            queens[row] = col;
            solve(n, row + 1, queens, count, first);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var first: [8]usize = undefined;
    for (4..9) |n| {
        var queens: [8]usize = undefined;
        var count: u32 = 0;
        solve(n, 0, &queens, &count, &first);
        try out.print("N={d}: {d} solutions\n", .{ n, count });
    }
    for (0..8) |r| {
        for (0..8) |c|
            try out.writeByte(if (first[r] == c) 'Q' else
                '.');
        try out.writeByte('\n');
    }
    try out.flush();
}
