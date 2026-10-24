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
    _ = std.ascii.lowerString(&lower, text);
    var counts: std.StringHashMapUnmanaged(u32) = .empty;
    defer counts.deinit(std.heap.page_allocator);
    var words = std.mem.tokenizeAny(u8, &lower, " ,.");
    while (words.next()) |word| {
        const entry = try counts.getOrPut(std.heap.page_allocator, word);
        if (!entry.found_existing)
            entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
    var entries: [100]Entry = undefined;
    const len = counts.count();
    var iterator = counts.iterator();
    var i: usize = 0;
    while (iterator.next()) |entry| : (i += 1) {
        entries[i] = .{ .word = entry.key_ptr.*, .count = entry.value_ptr.* };
    }
    std.mem.sort(Entry, entries[0..len], {}, less);
    for (entries[0..5]) |entry|
        try out.print("{s}: {d}\n", .{ entry.word, entry.count });
    try out.print("distinct words: {d}\n", .{ len });
    try out.flush();
}
