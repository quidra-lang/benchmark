const std = @import("std");

fn fixed(out: *std.Io.Writer, value: f64, places: usize) !void {
    var scale: u64 = 1;
    for (0..places) |_|
        scale *= 10;
    const scaled: u64 = @intFromFloat(@floor(@abs(value) * @as(f64, @floatFromInt(scale)) + 0.5));
    if (value < 0)
        try out.writeByte('-');
    try out.print("{d}", .{ scaled / scale });
    if (places > 0)
        try out.writeByte('.');
    var divisor = scale / 10;
    while (divisor > 0) : (divisor /= 10) {
        try out.writeByte('0' + @as(u8, @intCast((scaled / divisor) % 10)));
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const sales = [_]u32{ 120, 135, 98, 143, 160, 152, 171, 149, 188, 176 };
    for (2..sales.len) |i| {
        const average = @as(f64, @floatFromInt(sales[i - 2] + sales[i - 1] + sales[i])) / 3.0;
        try out.print("day {d}: ", .{ i + 1 });
        try fixed(out, average, 2);
        try out.writeByte('\n');
    }
    try out.flush();
}
