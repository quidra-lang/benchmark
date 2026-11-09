const std = @import("std");
const c = @import("bitio.zig");
pub const Token = struct { literal: u8 = 0, distance: usize = 0, length: usize = 0 };
pub fn tokenize(data: []const u8, offset_bits: usize, length_bits: usize) []const Token {
    const window = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(offset_bits));
    const lookahead = (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(length_bits))) + 2;
    var out: std.ArrayList(Token) = .empty;
    var position: usize = 0;
    while (position < data.len) {
        var best: usize = 0;
        var distance: usize = 0;
        const maximum = @min(lookahead, data.len - position);
        for (1..@min(window, position) + 1) |d| {
            var length: usize = 0;
            while (length < maximum and data[position + length] == data[position + length - d]) length += 1;
            if (length > best) {
                best = length;
                distance = d;
            }
        }
        if (best >= 3) {
            c.append(Token, &out, .{ .distance = distance, .length = best });
            position += best;
        } else {
            c.append(Token, &out, .{ .literal = data[position] });
            position += 1;
        }
    }
    return out.items;
}
pub fn outputMatch(output: *c.Bytes, size: usize, distance: usize, length: usize) c.DecodeError!void {
    if (distance > output.items.len) return error.bad_offset;
    if (output.items.len + length > size) return error.overrun;
    for (0..length) |_| c.append(u8, output, output.items[output.items.len - distance]);
}
