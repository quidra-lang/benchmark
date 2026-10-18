const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for ([_]u32{0,10,255,1000,43981,65535}) |n| {
        try out.print("{d}: bin={b} oct={o} hex={X}\n", .{n,n,n,n});
    }
    try out.flush();
}
