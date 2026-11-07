const std = @import("std");

pub const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

pub fn isLetter(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

pub fn upper(c: u8) u8 {
    return if (c >= 'a' and c <= 'z') c - 'a' + 'A' else c;
}

pub fn value(c: u8) usize {
    return upper(c) - 'A';
}

pub fn uppercase(gpa: std.mem.Allocator, text: []const u8) []u8 {
    const result = gpa.dupe(u8, text) catch @panic("allocation failed");
    for (result) |*c| c.* = upper(c.*);
    return result;
}

pub fn letterString(gpa: std.mem.Allocator, text: []const u8) []const u8 {
    var result: std.ArrayList(u8) = .empty;
    for (text) |c| {
        if (isLetter(c)) result.append(gpa, upper(c)) catch @panic("allocation failed");
    }
    return result.items;
}

pub const Weights = struct {
    monograms: [26]i64,
    bigrams: [26][26]i64,

    pub fn parse(text: []const u8) Weights {
        var words = std.mem.tokenizeAny(u8, text, " \n");
        var result: Weights = undefined;
        _ = words.next();
        for (&result.monograms) |*weight| weight.* = std.fmt.parseInt(i64, words.next().?, 10) catch unreachable;
        _ = words.next();
        for (&result.bigrams) |*row| {
            for (row) |*weight| weight.* = std.fmt.parseInt(i64, words.next().?, 10) catch unreachable;
        }
        return result;
    }

    pub fn monogram(w: Weights, text: []const u8) i64 {
        var total: i64 = 0;
        for (text) |c| total += w.monograms[value(c)];
        return total;
    }

    pub fn bigram(w: Weights, text: []const u8) i64 {
        var total: i64 = 0;
        var i: usize = 1;
        while (i < text.len) : (i += 1) total += w.bigrams[value(text[i - 1])][value(text[i])];
        return total;
    }
};
