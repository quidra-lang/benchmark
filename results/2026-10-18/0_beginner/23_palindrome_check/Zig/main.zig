const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const phrases = [_][]const u8{
        "Never odd or even",
        "Race a car",
        "Was it a car or a cat I saw?",
        "Hello, World!",
        "Step on no pets.",
        "No lemon, no melon"
    };
    for (phrases) |phrase| {
        var clean: [100]u8 = undefined;
        var len: usize = 0;
        for (phrase) |c| {
            const lower = std.ascii.toLower(c);
            if (lower >= 'a' and lower <= 'z') {
                clean[len] = lower;
                len += 1;
            }
        }
        var palindrome = true;
        for (0..len / 2) |i| {
            if (clean[i] != clean[len - 1 - i]) {
                palindrome = false;
                break;
            }
        }
        try out.print("{s} -> {s}\n", .{ phrase, if (palindrome) @as([]const u8, "yes") else "no" });
    }
    try out.flush();
}
