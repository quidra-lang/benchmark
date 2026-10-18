const std = @import("std");

const Entry = struct {
    key: [256]u8,
    klen: usize,
    value: [256]u8,
    vlen: usize
};

fn less(_: void, a: Entry, b: Entry) bool {
    return std.mem.order(u8, a.key[0..a.klen], b.key[0..b.klen]) == .lt;
}

fn decode(s: []const u8, buffer: *[256]u8) usize {
    const component = buffer[0..s.len];
    @memcpy(component, s);
    for (component) |*ch| {
        if (ch.* == '+') ch.* = ' ';
    }
    const decoded = std.Uri.percentDecodeInPlace(component);
    std.mem.copyForwards(u8, buffer[0..decoded.len], decoded);
    return decoded.len;
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const queries = [_][]const u8{
        "name=Alice+Smith&age=30&city=New%20York",
        "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
        "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
        "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"
    };
    for (queries, 0..) |query, k| {
        var entries: [16]Entry = undefined;
        var len: usize = 0;
        var items = std.mem.splitScalar(u8, query, '&');
        while (items.next()) |item| {
            const split = std.mem.findScalar(u8, item, '=') orelse item.len;
            entries[len].klen = decode(item[0..split], &entries[len].key);
            entries[len].vlen = decode(if (split < item.len) item[split + 1..]else "", &entries[len].value);
            len += 1;
        }
        std.mem.sort(Entry, entries[0..len], {}, less);
        try out.print("query {d}:\n", .{ k + 1 });
        for (entries[0..len], 0..) |entry, i| {
            const same = i > 0 and std.mem.eql(u8, entry.key[0..entry.klen], entries[i - 1].key[0..entries[i - 1].klen]);
            if (same) {
                try out.writeAll(", ");
            } else {
                if (i > 0)
                    try out.writeByte('\n');
                try out.print("  {s}: ", .{ entry.key[0..entry.klen] });
            }
            try out.print("\"{s}\"", .{ entry.value[0..entry.vlen] });
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
