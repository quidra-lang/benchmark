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
    const Person=struct{name:[]const u8,height:u32,weight:u32};
    const people=[_]Person{.{.name="Aiko",.height=158,.weight=45},.{.name="Kenji",.height=172,.weight=68},.{.name="Mika",.height=165,.weight=70},.{.name="Ryo",.height=180,.weight=101},.{.name="Yuki",.height=150,.weight=52}};
    for (people) |p| {
        const bmi=@as(f64,@floatFromInt(p.weight*10000))/@as(f64,@floatFromInt(p.height*p.height));
        const category:[]const u8=if(bmi<18.5) "underweight" else if(bmi<25) "normal" else if(bmi<30) "overweight" else "obese";
        try out.print("{s}: BMI ", .{p.name}); try fixed(out,bmi,1);
        try out.print(" ({s})\n", .{category});
    }
    try out.flush();
}
