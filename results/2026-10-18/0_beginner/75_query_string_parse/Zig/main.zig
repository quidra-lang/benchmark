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

fn hex(c: u8) u8 {
    return if (c >= '0' and c <= '9') c - '0' else std.ascii.toLower(c) - 'a' + 10;
}

fn decode(s: []const u8, buffer: *[256]u8) usize {
    var i: usize = 0;
    var len: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '+') {
            buffer[len] = ' ';
        } else if (s[i] == '%') {
            buffer[len] = hex(s[i + 1]) * 16 + hex(s[i + 2]);
            i += 2;
        } else {
            buffer[len] = s[i];
        }
        len += 1;
    }
    return len;
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
            var split: usize = 0;
            while (split < item.len and item[split] != '=')
                split += 1;
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
