const std = @import("std");

fn fixed(out: *std.Io.Writer, value: f64, places: usize) !void {
    var scale: u64 = 1;
    for (0..places) |_| scale *= 10;
    const scaled: u64 = @intFromFloat(@floor(@abs(value) * @as(f64, @floatFromInt(scale)) + 0.5));
    if (value < 0) try out.writeByte('-');
    try out.print("{d}", .{scaled / scale});
    if (places > 0) try out.writeByte('.');
    var divisor = scale / 10;
    while (divisor > 0) : (divisor /= 10) {
        try out.writeByte('0' + @as(u8, @intCast((scaled / divisor) % 10)));
    }
}


pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const values=[_]i32{72,85,64,90,85,58,77,85,69,93,71};
    var sorted=values;std.mem.sort(i32,&sorted,{},std.sort.asc(i32));
    var total:i32=0;for(values) |v| total+=v;
    const mean=@as(f64,@floatFromInt(total))/@as(f64,@floatFromInt(values.len));
    var squares:f64=0;for(values) |v| {const d=@as(f64,@floatFromInt(v))-mean;squares+=d*d;}
    var mode=sorted[0];var best:usize=0;
    for(sorted) |v| {var count:usize=0;for(values) |x| {if(x==v) count+=1;}if(count>best) {best=count;mode=v;}}
    try out.writeAll("mean: ");try fixed(out,mean,3);
    try out.print("\nmedian: {d}\nmode: {d}\nrange: {d}\nstdev: ", .{sorted[values.len/2],mode,sorted[values.len-1]-sorted[0]});
    try fixed(out,@sqrt(squares/@as(f64,@floatFromInt(values.len))),3);try out.writeByte('\n');
    try out.flush();
}
