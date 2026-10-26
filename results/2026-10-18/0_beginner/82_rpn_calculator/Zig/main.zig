const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const expressions = [_][]const u8{
        "3 4 + 2 *",
        "-17 5 / 4 -3 * -",
        "1 2 + * 3",
        "15 7 1 1 + - / 3 * 2 1 1 + + -",
        "4 2 5 * + 1 3 2 * - 5 + /",
        "2 3 4 + 5",
        "46341 46339 * -2 /",
    };
    for (expressions) |expression| {
        var stack: [32]i64 = undefined;
        var len: usize = 0;
        var err: ?[]const u8 = null;
        var tokens = std.mem.splitScalar(u8, expression, ' ');
        while (tokens.next()) |token| {
            const operator = token.len == 1 and
                (token[0] == '+' or token[0] == '-' or token[0] == '*' or token[0] == '/');
            if (!operator) {
                stack[len] = try std.fmt.parseInt(i64, token, 10);
                len += 1;
                continue;
            }
            if (len < 2) {
                err = "stack underflow";
                break;
            }
            const b = stack[len - 1];
            const a = stack[len - 2];
            len -= 2;
            if (token[0] == '/' and b == 0) {
                err = "division by zero";
                break;
            }
            stack[len] = switch (token[0]) {
                '+' => a + b,
                '-' => a - b,
                '*' => a * b,
                '/' => @divTrunc(a, b),
                else => unreachable,
            };
            len += 1;
        }
        if (err == null and len != 1)
            err = "leftover operands";
        try out.print("{s} => ", .{expression});
        if (err) |message| {
            try out.print("error: {s}\n", .{message});
        } else {
            try out.print("{d}\n", .{stack[0]});
        }
    }
    try out.flush();
}
