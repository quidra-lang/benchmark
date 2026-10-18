const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for ([_]i64{0,7,999,1000,-456789,3141592,9876543210}) |n| {
        var buf:[32]u8=undefined;
        const digits=try std.fmt.bufPrint(&buf,"{d}", .{@abs(n)});
        if (n<0) try out.writeByte('-');
        for (digits,0..) |c,i| {
            if (i>0 and (digits.len-i)%3==0) try out.writeByte(',');
            try out.writeByte(c);
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
