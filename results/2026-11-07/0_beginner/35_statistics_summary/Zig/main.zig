const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const values = [_]i32{ 72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71 };
    var sorted = values;
    std.mem.sort(i32, &sorted, {}, std.sort.asc(i32));
    var total: i32 = 0;
    for (values) |v|
        total += v;
    const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(values.len));
    var squares: f64 = 0;
    for (values) |v| {
        const d = @as(f64, @floatFromInt(v)) - mean;
        squares += d * d;
    }
    var mode = sorted[0];
    var best: usize = 0;
    for (sorted, 0..) |v, i| {
        if (i > 0 and v == sorted[i - 1])
            continue;
        const count = std.mem.countScalar(i32, &values, v);
        if (count > best) {
            best = count;
            mode = v;
        }
    }
    const deviation = @sqrt(squares / @as(f64, @floatFromInt(values.len)));
    try out.print("mean: {d:.3}\nmedian: {d}\nmode: {d}\nrange: {d}\nstdev: {d:.3}\n", .{
        mean,
        sorted[values.len / 2],
        mode,
        sorted[values.len - 1] - sorted[0],
        deviation,
    });
    try out.flush();
}
