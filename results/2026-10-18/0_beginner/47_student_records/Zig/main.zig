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

const Student = struct {
    name: []const u8,
    scores: [3]u32
};

fn total(s: Student) u32 {
    return s.scores[0] + s.scores[1] + s.scores[2];
}

fn less(_: void, a: Student, b: Student) bool {
    return if (total(a) != total(b)) total(a) > total(b) else std.mem.order(u8, a.name, b.name) == .lt;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var students = [_]Student{
        .{ .name = "Tanaka", .scores = .{ 78, 85, 94 } },
        .{ .name = "Suzuki", .scores = .{ 88, 74, 82 } },
        .{ .name = "Yamada", .scores = .{ 65, 90, 71 } },
        .{ .name = "Ito", .scores = .{ 80, 79, 85 } },
        .{ .name = "Kato", .scores = .{ 92, 88, 95 } },
        .{ .name = "Mori", .scores = .{ 70, 62, 78 } }
    };
    std.mem.sort(Student, &students, {}, less);
    var rank: usize = 0;
    var previous: u32 = 0;
    for (students, 0..) |s, i| {
        const t = total(s);
        if (i == 0 or t != previous)
            rank = i + 1;
        previous = t;
        try out.print("{d}. {s} total={d} average=", .{ rank, s.name, t });
        try fixed(out, @as(f64, @floatFromInt(t)) / 3.0, 2);
        try out.writeByte('\n');
    }
    try out.flush();
}
