const std = @import("std");
const scoring = @import("scoring.zig");

pub const multipliers = [_]i64{ 1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25 };
pub const Cipher = enum { caesar, affine, vigenere, autokey };
pub const Key = struct { a: i64 = 1, b: i64 = 0, word: []const u8 = "" };

pub fn inverse(a: i64) i64 {
    var candidate: i64 = 1;
    while (@mod(a * candidate, 26) != 1) : (candidate += 1) {}
    return candidate;
}

pub fn transform(gpa: std.mem.Allocator, text: []const u8, cipher: Cipher, key: Key, decrypt: bool) []const u8 {
    const result = gpa.dupe(u8, text) catch @panic("allocation failed");
    const plain = gpa.alloc(u8, if (cipher == .autokey) text.len else 0) catch @panic("allocation failed");
    defer gpa.free(plain);
    const factor = if (cipher == .affine and decrypt) inverse(key.a) else key.a;
    var t: usize = 0;
    for (text, 0..) |c, position| {
        if (!scoring.isLetter(c)) continue;
        const x: i64 = @intCast(scoring.value(c));
        const shift: i64 = switch (cipher) {
            .caesar, .affine => key.b,
            .vigenere => @intCast(scoring.value(key.word[t % key.word.len])),
            .autokey => if (t < key.word.len) @intCast(scoring.value(key.word[t])) else plain[t - key.word.len],
        };
        const y = @mod(if (decrypt) factor * (x - shift) else factor * x + shift, 26);
        result[position] = @as(u8, if (c >= 'A' and c <= 'Z') 'A' else 'a') + @as(u8, @intCast(y));
        if (cipher == .autokey) plain[t] = @intCast(if (decrypt) y else x);
        t += 1;
    }
    return result;
}
