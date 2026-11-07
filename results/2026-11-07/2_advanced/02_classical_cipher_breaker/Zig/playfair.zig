const std = @import("std");

pub const alphabet = "ABCDEFGHIKLMNOPQRSTUVWXYZ";

pub fn normalize(c: u8) u8 {
    return if (c == 'J') 'I' else c;
}

pub fn square(key: []const u8) [25]u8 {
    var result: [25]u8 = undefined;
    var seen: [26]bool = @splat(false);
    var count: usize = 0;
    for ([_][]const u8{ key, alphabet }) |part| {
        for (part) |c| {
            const letter = normalize(c);
            if (seen[letter - 'A']) continue;
            seen[letter - 'A'] = true;
            result[count] = letter;
            count += 1;
        }
    }
    return result;
}

pub fn plaintextPairs(gpa: std.mem.Allocator, text: []const u8) []const u8 {
    var result: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        const first = normalize(text[i]);
        const paired = i + 1 < text.len and normalize(text[i + 1]) != first;
        const second = if (paired) normalize(text[i + 1]) else if (first == 'X') @as(u8, 'Q') else 'X';
        result.appendSlice(gpa, &.{ first, second }) catch @panic("allocation failed");
        i += if (paired) @as(usize, 2) else 1;
    }
    return result.items;
}

pub fn validCiphertext(text: []const u8) bool {
    if (text.len % 2 != 0) return false;
    var i: usize = 0;
    while (i < text.len) : (i += 2) {
        if (normalize(text[i]) == normalize(text[i + 1])) return false;
    }
    return true;
}

fn transform(gpa: std.mem.Allocator, text: []const u8, key: []const u8, step: usize) []const u8 {
    const grid = square(key);
    var positions: [26]usize = undefined;
    for (grid, 0..) |c, i| positions[c - 'A'] = i;
    const result = gpa.alloc(u8, text.len) catch @panic("allocation failed");
    var i: usize = 0;
    while (i < text.len) : (i += 2) {
        const a = positions[normalize(text[i]) - 'A'];
        const b = positions[normalize(text[i + 1]) - 'A'];
        var ra = a / 5;
        var ca = a % 5;
        var rb = b / 5;
        var cb = b % 5;
        if (ra == rb) {
            ca = (ca + step) % 5;
            cb = (cb + step) % 5;
        } else if (ca == cb) {
            ra = (ra + step) % 5;
            rb = (rb + step) % 5;
        } else {
            const previous = ca;
            ca = cb;
            cb = previous;
        }
        result[i] = grid[ra * 5 + ca];
        result[i + 1] = grid[rb * 5 + cb];
    }
    return result;
}

pub fn encrypt(gpa: std.mem.Allocator, text: []const u8, key: []const u8) []const u8 {
    const pairs = plaintextPairs(gpa, text);
    defer gpa.free(pairs);
    return transform(gpa, pairs, key, 1);
}

pub fn decrypt(gpa: std.mem.Allocator, text: []const u8, key: []const u8) []const u8 {
    return transform(gpa, text, key, 4);
}
