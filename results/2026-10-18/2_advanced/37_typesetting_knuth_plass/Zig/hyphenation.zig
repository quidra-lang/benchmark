const std = @import("std");
const d = @import("document_parser.zig");
pub const Dictionary = std.StringHashMap([]usize);
pub const Split = struct { position: usize, hyphen: bool };
pub fn register(dictionary: *Dictionary, word: []const u8) void {
    var key: d.Text = .{};
    var points: std.ArrayList(usize) = .empty;
    for (word) |c| {
        if (c == '-') d.append(usize, &points, key.data.items.len) else key.add("{c}", .{c});
    }
    dictionary.put(key.value(), points.items) catch @panic("allocation failed");
}
fn pointLess(_: void, a: Split, b: Split) bool {
    return a.position < b.position;
}
pub fn points(dictionary: Dictionary, word: []const u8, p: d.Params) []Split {
    var out: std.ArrayList(Split) = .empty;
    var first: usize = 0;
    var last = word.len;
    while (first < last and !d.letter(word[first])) first += 1;
    while (last > first and !d.letter(word[last - 1])) last -= 1;
    var valid = first < last;
    for (word[first..last]) |c| if (!d.letter(c)) {
        valid = false;
    };
    if (valid) if (dictionary.get(d.lower(word[first..last]))) |splits| {
        for (splits) |position| if (d.n(position) >= p.left_min and d.n(last - first - position) >= p.right_min) d.append(Split,
             &out, .{ .position = first + position, .hyphen = true });
    };
    if (word.len >= 3) for (1..word.len - 1) |i| {
        if (word[i] == '-' and d.letter(word[i - 1]) and d.letter(word[i + 1])) d.append(Split, &out,
             .{ .position = i + 1, .hyphen = false });
    };
    std.mem.sort(Split, out.items, {}, pointLess);
    return out.items;
}
