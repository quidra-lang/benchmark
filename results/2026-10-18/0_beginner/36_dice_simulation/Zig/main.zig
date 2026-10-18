const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var state:u64=12345;var counts=[_]u32{0} ** 13;
    for(0..1000) |_| {state=(state*48271)%2147483647;const a=state%6+1;state=(state*48271)%2147483647;const b=state%6+1;counts[@intCast(a+b)]+=1;}
    var best:usize=2;
    for(2..13) |sum| {try out.print("{d}: {d}\n", .{sum,counts[sum]});if(counts[sum]>counts[best]) best=sum;}
    try out.print("most frequent: {d}\n", .{best});
    try out.flush();
}
