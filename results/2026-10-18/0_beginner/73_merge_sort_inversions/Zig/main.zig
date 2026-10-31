const std = @import("std");

fn mergeSort(out: *std.Io.Writer, a: *[10]i32, l: usize, r: usize, inversions: *usize) std.Io.Writer.Error!void {
    if (l == r)
        return;
    const m = (l + r) / 2;
    try mergeSort(out, a, l, m, inversions);
    try mergeSort(out, a, m + 1, r, inversions);
    var temp: [10]i32 = undefined;
    var len: usize = 0;
    var i = l;
    var j = m + 1;
    while (i <= m and j <= r) {
        if (a[i] < a[j]) {
            temp[len] = a[i];
            i += 1;
        } else {
            inversions.* += m - i + 1;
            temp[len] = a[j];
            j += 1;
        }
        len += 1;
    }
    const left = m + 1 - i;
    @memcpy(temp[len..][0..left], a[i .. m + 1]);
    len += left;
    const right = r + 1 - j;
    @memcpy(temp[len..][0..right], a[j .. r + 1]);
    len += right;
    @memcpy(a[l .. r + 1], temp[0..len]);
    try out.print("merge [{d}..{d}]:", .{ l, r });
    for (temp[0..len]) |v|
        try out.print(" {d}", .{v});
    try out.writeByte('\n');
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var a = [_]i32{ 47, 12, 85, 33, 6, 71, 29, 58, 90, 14 };
    var inversions: usize = 0;
    try mergeSort(out, &a, 0, 9, &inversions);
    try out.writeAll("sorted:");
    for (a) |v|
        try out.print(" {d}", .{v});
    try out.print("\ninversions: {d}\n", .{inversions});
    try out.flush();
}
