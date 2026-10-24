const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names = [_][]const u8{ "Sato", "Suzuki", "Takahashi", "Tanaka", "Ito", "Watanabe" };
    const usages = [_]u32{ 85, 120, 254, 300, 438, 176 };
    var total: u32 = 0;
    for (names, usages) |name, usage| {
        var bill: u32 = 900 + @min(usage, 120) * 30;
        if (usage > 120)
            bill += @min(usage - 120, 180) * 36;
        if (usage > 300)
            bill += (usage - 300) * 40;
        total += bill;
        try out.print("{s}: {d} kWh, {d} yen\n", .{ name, usage, bill });
    }
    try out.print("total: {d} yen\n", .{ total });
    try out.flush();
}
