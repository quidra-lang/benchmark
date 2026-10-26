const std = @import("std");

fn hanoi(out: *std.Io.Writer, n: u32, source: u8, target: u8, auxiliary: u8, count: *u32) std.Io.Writer.Error!void {
    if (n == 0)
        return;
    try hanoi(out, n - 1, source, auxiliary, target, count);
    try out.print("move disk {d} from {c} to {c}\n", .{ n, source, target });
    count.* += 1;
    try hanoi(out, n - 1, auxiliary, target, source, count);
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var count: u32 = 0;
    try hanoi(out, 4, 'A', 'C', 'B', &count);
    try out.print("total moves: {d}\n", .{count});
    try out.flush();
}
