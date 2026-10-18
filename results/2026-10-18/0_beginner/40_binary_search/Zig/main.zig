const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const a=[_]i32{3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77};
    for([_]i32{42,3,77,31,50,1}) |target| {
        var lo:i32=0;var hi:i32=15;var found:?i32=null;
        try out.print("{d}: probes", .{target});
        while(lo<=hi) {
            const mid=@divTrunc(lo+hi,2);try out.print(" {d}", .{mid});const value=a[@intCast(mid)];
            if(value==target) {found=mid;break;} else if(value<target) {lo=mid+1;} else {hi=mid-1;}
        }
        if(found) |index| {try out.print(" -> index {d}\n", .{index});} else {try out.writeAll(" -> not found\n");}
    }
    try out.flush();
}
