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
    const polygons=[_] []const [2]i32{&[_][2]i32{.{0,0},.{5,0},.{6,4},.{1,3}},
&[_][2]i32{.{2,1},.{0,4},.{3,7},.{7,6},.{8,2}},
&[_][2]i32{.{0,0},.{8,0},.{8,6},.{5,6},.{4,3},.{3,6},.{0,6}}};
    for(polygons,0..) |points,k| {
        var cross:i32=0;var perimeter:f64=0;
        for(points,0..) |a,i| {const b=points[(i+1)%points.len];cross+=a[0]*b[1]-b[0]*a[1];const dx=a[0]-b[0];const dy=a[1]-b[1];perimeter+=@sqrt(@as(f64,@floatFromInt(dx*dx+dy*dy)));}
        try out.print("polygon {d}: area=", .{k+1});try fixed(out,@as(f64,@floatFromInt(@abs(cross)))/2.0,1);try out.writeAll(" perimeter=");try fixed(out,perimeter,3);try out.writeByte('\n');
    }
    try out.flush();
}
