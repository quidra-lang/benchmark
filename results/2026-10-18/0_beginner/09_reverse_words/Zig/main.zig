const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const sentence = "every program starts with a single line";
    var buffer: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    var index: usize = sentence.len;
    while (index > 0) {
        index -= 1;
        try out.writeByte(sentence[index]);
    }
    try out.writeByte('\n');
    var end: usize = sentence.len;
    while (end > 0) {
        var start = end;
        while (start > 0 and sentence[start - 1] != ' ')
            start -= 1;
        try out.writeAll(sentence[start..end]);
        if (start == 0)
            break;
        try out.writeByte(' ');
        end = start - 1;
    }
    try out.writeByte('\n');
    try out.flush();
}
