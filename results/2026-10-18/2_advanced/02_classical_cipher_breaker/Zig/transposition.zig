const std = @import("std");

pub fn railNumber(position: usize, rails: usize) usize {
    const cycle = 2 * rails - 2;
    const offset = position % cycle;
    return @min(offset, cycle - offset);
}

pub fn railFence(gpa: std.mem.Allocator, text: []const u8, rails: usize, decrypt: bool) []const u8 {
    const result = gpa.alloc(u8, text.len) catch @panic("allocation failed");
    var index: usize = 0;
    for (0..rails) |rail| {
        for (0..text.len) |position| {
            if (railNumber(position, rails) == rail) {
                if (decrypt) result[position] = text[index] else result[index] = text[position];
                index += 1;
            }
        }
    }
    return result;
}

pub fn columnRanks(key: []const u8) [9]usize {
    var ranks: [9]usize = @splat(0);
    for (key, 0..) |c, i| {
        ranks[i] = 1;
        for (key, 0..) |other, j| {
            if (other < c or (other == c and j < i)) ranks[i] += 1;
        }
    }
    return ranks;
}

pub fn rankString(gpa: std.mem.Allocator, key: []const u8) []const u8 {
    const ranks = columnRanks(key);
    const result = gpa.alloc(u8, key.len) catch @panic("allocation failed");
    for (result, 0..) |*c, i| c.* = '0' + @as(u8, @intCast(ranks[i]));
    return result;
}

pub fn columnar(gpa: std.mem.Allocator, text: []const u8, key: []const u8, decrypt: bool) []const u8 {
    const ranks = columnRanks(key);
    const result = gpa.alloc(u8, text.len) catch @panic("allocation failed");
    var index: usize = 0;
    for (1..key.len + 1) |rank| {
        for (0..key.len) |column| {
            if (ranks[column] != rank) continue;
            var position = column;
            while (position < text.len) : (position += key.len) {
                if (decrypt) result[position] = text[index] else result[index] = text[position];
                index += 1;
            }
        }
    }
    return result;
}
