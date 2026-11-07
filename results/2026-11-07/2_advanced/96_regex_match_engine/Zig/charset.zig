const std = @import("std");
pub const Set = std.StaticBitSet(128);
pub fn word(c: u8) bool { return std.ascii.isAlphanumeric(c) or c == '_'; }
pub fn switched(c: u8) u8 { return if (std.ascii.isLower(c)) std.ascii.toUpper(c) else if (std.ascii.isUpper(c)) std.ascii.toLower(c) else c; }
pub fn standard(c: u8) Set {
    var s = Set.initEmpty();
    for (0..128) |n| {
        const x: u8 = @intCast(n);
        const yes = switch (std.ascii.toLower(c)) { 'd' => std.ascii.isDigit(x), 'w' => word(x), 's' => x == 9 or x == 10 or x == 11 or x == 12 or x == 13 or x == 32, else => false };
        if (yes) s.set(n);
    }
    return s;
}
pub fn same(a: u8, b: u8, flags: []const u8) bool { return a == b or (std.mem.indexOfScalar(u8, flags, 'i') != null and std.ascii.toLower(a) == std.ascii.toLower(b)); }
pub fn class(s: Set, neg: bool, c: u8, flags: []const u8) bool {
    const yes = s.isSet(c) or (std.mem.indexOfScalar(u8, flags, 'i') != null and s.isSet(switched(c)));
    return yes != neg;
}
pub const Assertion = enum { BOL, EOL, WORD, NOTWORD };
pub fn assertion(kind: Assertion, text: []const u8, q: usize, flags: []const u8) bool {
    const multiline = std.mem.indexOfScalar(u8, flags, 'm') != null;
    const before = q > 0 and word(text[q - 1]);
    const after = q < text.len and word(text[q]);
    return switch (kind) { .BOL => q == 0 or (multiline and text[q - 1] == '\n'), .EOL => q == text.len or (multiline and text[q] == '\n'), .WORD => before != after, .NOTWORD => before == after };
}
