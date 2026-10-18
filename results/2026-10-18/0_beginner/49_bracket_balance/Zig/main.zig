const std = @import("std");


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const strings=[_] []const u8{"(a + b) * [c - d]","{x = [1, 2, (3 + 4)]}","f(a[i] + g(b)}","(1 + 2)) * 3","if (a < b) { c = d[0]; }","((a + b] * c","[{(x * y) - z}"};
    for(strings) |s| {var stack:[100]u8=undefined;var len:usize=0;var err:?usize=null;
        for(s,0..) |c,i| {
            if(c=='(' or c=='[' or c=='{') {stack[len]=c;len+=1;}
            else if(c==')' or c==']' or c=='}') {const expected:u8=if(c==')') '(' else if(c==']') '[' else '{';if(len==0 or stack[len-1]!=expected) {err=i;break;}len-=1;}
        }
        if(err==null and len>0) err=s.len;
        try out.print("{s} -> ", .{s});if(err) |i| {try out.print("error at index {d}\n", .{i});}else{try out.writeAll("balanced\n");}
    }
    try out.flush();
}
