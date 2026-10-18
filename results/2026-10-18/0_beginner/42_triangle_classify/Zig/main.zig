const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for([_][3]u32{.{3,8,5},.{6,6,6},.{5,8,5},.{13,5,12},.{2,9,4},.{7,4,7},.{8,6,7},.{4,9,6}}) |original| {
        var s=original;std.mem.sort(u32,&s,{},std.sort.asc(u32));
        try out.print("{d} {d} {d}: ", .{original[0],original[1],original[2]});
        if(s[0]+s[1]<=s[2]) {try out.writeAll("not a triangle\n");continue;}
        const side:[]const u8=if(s[0]==s[2]) "equilateral" else if(s[0]==s[1] or s[1]==s[2]) "isosceles" else "scalene";
        const lhs=s[2]*s[2];const rhs=s[0]*s[0]+s[1]*s[1];
        const angle:[]const u8=if(lhs<rhs) "acute" else if(lhs==rhs) "right" else "obtuse";
        try out.print("{s} {s}\n", .{side,angle});
    }
    try out.flush();
}
