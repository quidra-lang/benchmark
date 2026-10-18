const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const boards = [_][3][]const u8{
        .{ "XXX", "OO.", "O.X" },
        .{ "X.O", ".X.", "O.." },
        .{ "XO.", ".OX", "XO." },
        .{ "XOX", "XOO", "OXX" },
        .{ "X.O", "XO.", "O.X" },
        .{ "XOX", "OXO", "OXX" }
    };
    const lines = [_][3]usize{
        .{ 0, 1, 2 },
        .{ 3, 4, 5 },
        .{ 6, 7, 8 },
        .{ 0, 3, 6 },
        .{ 1, 4, 7 },
        .{ 2, 5, 8 },
        .{ 0, 4, 8 },
        .{ 2, 4, 6 }
    };
    for (boards, 0..) |board, i| {
        var cells: [9]u8 = undefined;
        var empty = false;
        for (0..9) |j| {
            cells[j] = board[j / 3][j % 3];
            if (cells[j] == '.')
                empty = true;
        }
        var winner: u8 = '.';
        for (lines) |line| {
            const mark = cells[line[0]];
            if (mark != '.' and mark == cells[line[1]] and mark == cells[line[2]]) {
                winner = mark;
                break;
            }
        }
        const result: []const u8 = if (winner == 'X') "X wins" else if (winner == 'O') "O wins" else if (empty) "in progress" else "draw";
        try out.print("board {d}: {s}\n", .{ i + 1, result });
    }
    try out.flush();
}
