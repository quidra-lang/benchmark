const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var state: u64 = 42;
    var free = [_]u32{ 0, 0 };
    var arrival: u32 = 0;
    var total_wait: u32 = 0;
    var max_wait: u32 = 0;
    for (1..21) |customer| {
        state = (state * 48271) % 2147483647;
        arrival += @as(u32, @intCast(state % 5 + 1));
        state = (state * 48271) % 2147483647;
        const service: u32 = @intCast(state % 7 + 2);
        const teller: usize = if (free[0] <= free[1]) 0 else 1;
        const start = @max(arrival, free[teller]);
        const end = start + service;
        const wait = start - arrival;
        free[teller] = end;
        total_wait += wait;
        max_wait = @max(max_wait, wait);
        try out.print("customer {d}: arrive={d} start={d} end={d} teller={d} wait={d}\n", .{ customer,
            arrival, start, end, teller + 1, wait });
    }
    const hundredths = total_wait * 5;
    try out.print("average wait: {d}.{d:0>2}\nmax wait: {d}\nlast departure: {d}\n", .{ hundredths / 100,
        hundredths % 100, max_wait, @max(free[0], free[1]) });
    try out.flush();
}
