const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for ([_]u64{1,6,27,97,871}) |initial| {
        var n=initial; var steps:u32=0; var maximum=n;
        while (n != 1) {
            n=if (n%2==0) n/2 else 3*n+1;
            steps+=1; maximum=@max(maximum,n);
        }
        try out.print("{d}: steps={d} max={d}\n", .{initial,steps,maximum});
    }
    try out.flush();
}
