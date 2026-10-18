const std = @import("std");

const Entry = struct {
    word: []const u8,
    count: u32
};

fn less(_: void, a: Entry, b: Entry) bool {
    return if (a.count != b.count) a.count > b.count else std.mem.order(u8, a.word, b.word) == .lt;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
    var lower: [text.len]u8 = undefined;
    for (text, 0..) |c, i|
        lower[i] = std.ascii.toLower(c);
    var entries: [100]Entry = undefined;
    var len: usize = 0;
    var i: usize = 0;
    while (i < lower.len) {
        if (lower[i] < 'a' or lower[i] > 'z') {
            i += 1;
            continue;
        }
        const start = i;
        while (i < lower.len and lower[i] >= 'a' and lower[i] <= 'z')
            i += 1;
        const word = lower[start..i];
        var found = false;
        for (entries[0..len]) | * entry| {
            if (std.mem.eql(u8, entry.word, word)) {
                entry.count += 1;
                found = true;
                break;
            }
        }
        if (!found) {
            entries[len] = .{ .word = word, .count = 1 };
            len += 1;
        }
    }
    std.mem.sort(Entry, entries[0..len], {}, less);
    for (entries[0..5]) |entry|
        try out.print("{s}: {d}\n", .{ entry.word, entry.count });
    try out.print("distinct words: {d}\n", .{ len });
    try out.flush();
}
