const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const cases=[_][4]u32{.{1999,12,25,10},.{2000,2,27,3},.{2021,2,20,14},.{2023,11,15,120},.{2026,10,17,1500}};
    const lengths=[_]u32{31,28,31,30,31,30,31,31,30,31,30,31};
    for(cases) |c| {var y=c[0];var m=c[1];var d=c[2];
        for(0..c[3]) |_| {var days=lengths[m-1];if(m==2 and y%4==0 and (y%100!=0 or y%400==0)) days=29;d+=1;if(d>days) {d=1;m+=1;if(m>12) {m=1;y+=1;}}}
        try out.print("{d:0>4}-{d:0>2}-{d:0>2} + {d} days = {d:0>4}-{d:0>2}-{d:0>2}\n", .{c[0],c[1],c[2],c[3],y,m,d});
    }
    try out.flush();
}
