const std = @import("std");

const ones = [_][]const u8{
    "zero", "one",    "two",    "three",    "four",     "five",    "six",     "seven",     "eight",    "nine",
    "ten",  "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
};
const tens = [_][]const u8{ "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" };

fn under(out: *std.Io.Writer, n: u32) std.Io.Writer.Error!void {
    const h = n / 100;
    const y = n % 100;
    if (h > 0)
        try out.print("{s} hundred", .{ones[h]});
    if (y > 0) {
        if (h > 0)
            try out.writeByte(' ');
        if (y < 20) {
            try out.writeAll(ones[y]);
        } else {
            try out.writeAll(tens[y / 10]);
            if (y % 10 > 0)
                try out.print("-{s}", .{ones[y % 10]});
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    for ([_]u32{ 0, 13, 40, 100, 568, 71000, 300019, 999999 }) |n| {
        var text: [256]u8 = undefined;
        var words = std.Io.Writer.fixed(&text);
        if (n == 0) {
            try words.writeAll("zero");
        } else {
            const thousands = n / 1000;
            const rest = n % 1000;
            if (thousands > 0) {
                try under(&words, thousands);
                try words.writeAll(" thousand");
            }
            if (rest > 0) {
                if (thousands > 0)
                    try words.writeByte(' ');
                try under(&words, rest);
            }
        }
        const result = words.buffered();
        try out.print("{d}: {s}\n", .{ n, result });
    }
    try out.flush();
}
