const std = @import("std");

fn solve(board: *[81]u8, placements: *u64) bool {
    const cell = std.mem.findScalar(u8, board, 0) orelse return true;
    const r = cell / 9;
    const c = cell % 9;
    var digit: u8 = 1;
    while (digit <= 9) : (digit += 1) {
        var valid = true;
        for (0..9) |k| {
            if (board[r * 9 + k] == digit or board[k * 9 + c] == digit or
                board[(r / 3 * 3 + k / 3) * 9 + c / 3 * 3 + k % 3] == digit)
            {
                valid = false;
                break;
            }
        }
        if (valid) {
            board[cell] = digit;
            placements.* += 1;
            if (solve(board, placements))
                return true;
            board[cell] = 0;
        }
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const initial = [_][]const u8{
        "800025000",
        "070080005",
        "260400070",
        "000001900",
        "010000040",
        "600200000",
        "900010000",
        "700000004",
        "020000036",
    };
    var board: [81]u8 = undefined;
    for (0..81) |i|
        board[i] = initial[i / 9][i % 9] - '0';
    var placements: u64 = 0;
    _ = solve(&board, &placements);
    for (0..9) |r| {
        for (0..9) |c| {
            if (c > 0)
                try out.writeByte(' ');
            try out.print("{d}", .{board[r * 9 + c]});
        }
        try out.writeByte('\n');
    }
    try out.print("placements: {d}\n", .{placements});
    try out.flush();
}
