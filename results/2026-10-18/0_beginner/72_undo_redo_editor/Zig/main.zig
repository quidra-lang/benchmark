const std = @import("std");

const Snapshot = struct {
    text: [128]u8 = undefined,
    len: usize = 0
};

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const commands = [_][]const u8{
        "undo",
        "type hello world",
        "delete 5",
        "type there",
        "undo",
        "undo",
        "redo",
        "type friend",
        "redo",
        "delete 20",
        "undo",
        "redo",
        "redo",
        "type see you"
    };
    var current = Snapshot{};
    var undo: [14]Snapshot = undefined;
    var redo: [14]Snapshot = undefined;
    var ulen: usize = 0;
    var rlen: usize = 0;
    for (commands) |command| {
        try out.print("{s} => ", .{ command });
        if (std.mem.eql(u8, command, "undo")) {
            if (ulen == 0) {
                try out.writeAll("nothing to undo\n");
                continue;
            }
            redo[rlen] = current;
            rlen += 1;
            ulen -= 1;
            current = undo[ulen];
        } else if (std.mem.eql(u8, command, "redo")) {
            if (rlen == 0) {
                try out.writeAll("nothing to redo\n");
                continue;
            }
            undo[ulen] = current;
            ulen += 1;
            rlen -= 1;
            current = redo[rlen];
        } else {
            undo[ulen] = current;
            ulen += 1;
            rlen = 0;
            if (std.mem.startsWith(u8, command, "type ")) {
                const text = command[5..];
                @memcpy(current.text[current.len..][0..text.len], text);
                current.len += text.len;
            } else {
                const n = try std.fmt.parseInt(usize, command[7..], 10);
                current.len -= @min(current.len, n);
            }
        }
        try out.print("\"{s}\"\n", .{ current.text[0..current.len] });
    }
    try out.flush();
}
