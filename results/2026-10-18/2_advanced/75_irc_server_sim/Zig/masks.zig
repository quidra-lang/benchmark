const std = @import("std");
const p = @import("protocol.zig");
pub fn matches(mask: []const u8, value: []const u8) bool {
    const m = mask;
    const s = value;
    var i: usize = 0;
    var j: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (j < s.len) {
        if (i < m.len and (m[i] == '?' or p.foldCharacter(m[i]) == p.foldCharacter(s[j]))) {
            i += 1;
            j += 1;
        } else if (i < m.len and m[i] == '*') {
            star = i;
            i += 1;
            retry = j;
        } else if (star) |at| {
            i = at + 1;
            retry += 1;
            j = retry;
        } else return false;
    }
    while (i < m.len and m[i] == '*') : (i += 1) {}
    return i == m.len;
}
pub fn normalize(value: []const u8) []const u8 {
    const bang = std.mem.indexOfScalar(u8, value, '!') != null;
    const at = std.mem.indexOfScalar(u8, value, '@') != null;
    if (bang and at) return value;
    if (at) return p.fmt("*!{s}", .{value});
    if (bang) return p.fmt("{s}@*", .{value});
    if (std.mem.indexOfScalar(u8, value, '.') != null) return p.fmt("*!*@{s}", .{value});
    return p.fmt("{s}!*@*", .{value});
}
