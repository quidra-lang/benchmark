const std = @import("std");

fn shift(c: u8, amount: u8) u8 {
    const base: u8 = if (c >= 'a' and c <= 'z') 'a' else if (c >= 'A' and c <= 'Z') 'A' else return c;
    return base + (c - base + amount) % 26;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const message = "Zoe, meet Max by the Old Bridge at six!";
    var cipher: [message.len]u8 = undefined;
    var plain: [message.len]u8 = undefined;
    for (message, 0..) |c, i|
        cipher[i] = shift(c, 3);
    for (cipher, 0..) |c, i|
        plain[i] = shift(c, 23);
    try out.print("{s}\n{s}\n", .{ cipher, plain });
    try out.flush();
}
