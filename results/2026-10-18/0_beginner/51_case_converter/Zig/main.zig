const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const identifiers = [_][]const u8{
        "user_name",
        "maxRetryCount",
        "ShoppingCartItem",
        "background-color",
        "get_last_login_time",
        "isEmailAddressValid"
    };
    for (identifiers) |id| {
        var lower: [100]u8 = undefined;
        for (id, 0..) |c, i|
            lower[i] = std.ascii.toLower(c);
        var words: [10][]const u8 = undefined;
        var count: usize = 0;
        var start: usize = 0;
        for (id, 0..) |c, i| {
            if (c == '_' or c == '-') {
                if (i > start) {
                    words[count] = lower[start..i];
                    count += 1;
                }
                start = i + 1;
            } else if (c >= 'A' and c <= 'Z' and i > start) {
                words[count] = lower[start..i];
                count += 1;
                start = i;
            }
        }
        if (start < id.len) {
            words[count] = lower[start..id.len];
            count += 1;
        }
        try out.print("{s}: snake=", .{ id });
        for (0..4) |style| {
            if (style == 1)
                try out.writeAll(", camel=");
            if (style == 2)
                try out.writeAll(", pascal=");
            if (style == 3)
                try out.writeAll(", kebab=");
            for (words[0..count], 0..) |word, i| {
                if (i > 0 and (style == 0 or style == 3))
                    try out.writeByte(if (style == 0) '_' else
                        '-');
                for (word, 0..) |c, j|
                    try out.writeByte(if (j == 0 and (style == 2 or (style == 1 and i > 0))) std.ascii.toUpper(c) else
                        c);
            }
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
