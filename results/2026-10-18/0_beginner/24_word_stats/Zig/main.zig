const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var words = std.mem.splitScalar(u8, "we planted beans and carrots in the garden behind our old house",
        ' ');
    var count: usize = 0;
    var total: usize = 0;
    var longest: []const u8 = "";
    var shortest: []const u8 = "";
    while (words.next()) |word| {
        if (count == 0 or word.len > longest.len)
            longest = word;
        if (count == 0 or word.len < shortest.len)
            shortest = word;
        count += 1;
        total += word.len;
    }
    const average = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(count));
    try out.print("words: {d}\nlongest: {s}\nshortest: {s}\naverage length: {d:.2}\n",
        .{ count, longest, shortest, average });
    try out.flush();
}
