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
    const sets=[_][3]i32{.{1,-3,-10},.{-2,5,4},.{3,1,-2},.{4,-12,9},.{1,2,5},.{-2,3,-4}};
    for(sets) |s| {
        const a=s[0];const b=s[1];const c=s[2];const disc=b*b-4*a*c;
        const numerator=-@as(f64,@floatFromInt(b));const denominator=2.0*@as(f64,@floatFromInt(a));
        try out.print("{d} {d} {d}: ", .{a,b,c});
        if(disc>0) {
            const root=@sqrt(@as(f64,@floatFromInt(disc)));const r1=(numerator+root)/denominator;const r2=(numerator-root)/denominator;
            try out.writeAll("x1 = ");try fixed(out,@max(r1,r2),4);try out.writeAll(", x2 = ");try fixed(out,@min(r1,r2),4);
        } else if(disc==0) {try out.writeAll("x = ");try fixed(out,numerator/denominator,4);} else {
            const p=numerator/denominator;const q=@sqrt(@as(f64,@floatFromInt(-disc)))/(2.0*@as(f64,@floatFromInt(@abs(a))));
            try out.writeAll("x = ");try fixed(out,p,4);try out.writeAll(" + ");try fixed(out,q,4);try out.writeAll("i, ");try fixed(out,p,4);try out.writeAll(" - ");try fixed(out,q,4);try out.writeByte('i');
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
