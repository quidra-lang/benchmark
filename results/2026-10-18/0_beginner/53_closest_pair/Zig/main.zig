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
    const p=[_][2]i32{.{12,-7},.{-33,25},.{41,18},.{-8,-44},.{27,39},.{-46,-12},.{5,14},.{36,-29},.{-19,47},.{-2,3}};
    var nearest:i32=std.math.maxInt(i32);var farthest:i32=-1;var near_pair:[2]usize=undefined;var far_pair:[2]usize=undefined;
    for(0..p.len) |i| {for(i+1..p.len) |j| {const dx=p[i][0]-p[j][0];const dy=p[i][1]-p[j][1];const d=dx*dx+dy*dy;if(d<nearest) {nearest=d;near_pair=.{i,j};}if(d>farthest) {farthest=d;far_pair=.{i,j};}}}
    try out.print("closest: P{d} P{d} ", .{near_pair[0],near_pair[1]});try fixed(out,@sqrt(@as(f64,@floatFromInt(nearest))),4);
    try out.print("\nfarthest: P{d} P{d} ", .{far_pair[0],far_pair[1]});try fixed(out,@sqrt(@as(f64,@floatFromInt(farthest))),4);try out.writeByte('\n');
    try out.flush();
}
