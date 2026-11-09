const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const initial = [_][]const u8{
        ".#......",
        "..#.....",
        "###.....",
        "........",
        "........",
        "........",
        ".....###",
        "........",
    };
    var board: [8][8]bool = undefined;
    for (0..8) |r| {
        for (0..8) |c|
            board[r][c] = initial[r][c] == '#';
    }
    for (0..5) |g| {
        try out.print("generation {d}\n", .{g});
        for (board) |row| {
            for (row) |alive|
                try out.writeByte(if (alive) '#' else '.');
            try out.writeByte('\n');
        }
        if (g == 4)
            break;
        var next: [8][8]bool = undefined;
        for (0..8) |r| {
            for (0..8) |c| {
                var count: u32 = 0;
                var dr: i32 = -1;
                while (dr <= 1) : (dr += 1) {
                    var dc: i32 = -1;
                    while (dc <= 1) : (dc += 1) {
                        if (dr == 0 and dc == 0)
                            continue;
                        const rr = @as(i32, @intCast(r)) + dr;
                        const cc = @as(i32, @intCast(c)) + dc;
                        if (rr >= 0 and rr < 8 and cc >= 0 and cc < 8 and board[@intCast(rr)][@intCast(cc)])
                            count += 1;
                    }
                }
                next[r][c] = count == 3 or (board[r][c] and count == 2);
            }
        }
        board = next;
    }
    var alive: usize = 0;
    for (board) |row|
        alive += std.mem.countScalar(bool, &row, true);
    try out.print("alive: {d}\n", .{alive});
    try out.flush();
}
