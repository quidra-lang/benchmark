const std = @import("std");
fn add(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn hexValue(character: u8) ?u8 {
    if (character >= '0' and character <= '9') return character - '0';
    if (character >= 'A' and character <= 'F') return character - 'A' + 10;
    if (character >= 'a' and character <= 'f') return character - 'a' + 10;
    return null;
}
pub fn strictBase64(allocator: std.mem.Allocator, source: []const u8) ?[]const u8 {
    if (source.len % 4 != 0) return null;
    var end = source.len;
    while (end > 0 and source[end - 1] == '=') end -= 1;
    if (source.len - end >= 3) return null;
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var output: std.ArrayList(u8) = .empty;
    var buffer: u16 = 0;
    var bits: u4 = 0;
    for (source[0..end]) |character| {
        const value = std.mem.indexOfScalar(u8, alphabet, character) orelse return null;
        buffer = (buffer << 6) | @as(u16, @intCast(value));
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            add(&output, allocator, @intCast(buffer >> bits));
            buffer &= (@as(u16, 1) << bits) - 1;
        }
    }
    return output.items;
}
pub fn decodeBase64Body(allocator: std.mem.Allocator, source: []const u8) ?[]const u8 {
    var compact: std.ArrayList(u8) = .empty;
    for (source) |character| if (character != ' ' and character != '\t' and character != '\n') { add(&compact, allocator, character); };
    const bytes = strictBase64(allocator, compact.items) orelse return null;
    var output: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        var value = bytes[i];
        if (value == 13 and i + 1 < bytes.len and bytes[i + 1] == 10) { value = 10; i += 1; }
        if (value != 9 and value != 10 and (value < 32 or value > 126)) return null;
        add(&output, allocator, value);
    }
    return output.items;
}
pub const Decoded = struct { text: []const u8, failed: bool };
pub fn decodeQuotedPrintable(allocator: std.mem.Allocator, source: []const u8) Decoded {
    var output: std.ArrayList(u8) = .empty;
    var failed = false;
    var start: usize = 0;
    while (true) {
        const end = if (std.mem.indexOfScalarPos(u8, source, start, '\n')) |index| index else source.len;
        var line = std.mem.trimEnd(u8, source[start..end], " \t");
        const soft = line.len > 0 and line[line.len - 1] == '=';
        if (soft) line = line[0 .. line.len - 1];
        var position: usize = 0;
        while (position < line.len) {
            var value: ?u8 = null;
            if (line[position] == '=' and position + 2 < line.len) {
                if (hexValue(line[position + 1])) |first| {
                    if (hexValue(line[position + 2])) |second| {
                        const decoded = 16 * first + second;
                        if (decoded == 9 or (decoded >= 32 and decoded <= 126)) value = decoded;
                    }
                }
            }
            if (value) |decoded| { add(&output, allocator, decoded); position += 3; } else {
                failed = failed or line[position] == '=';
                add(&output, allocator, line[position]);
                position += 1;
            }
        }
        if (end == source.len) break;
        if (!soft) add(&output, allocator, '\n');
        start = end + 1;
    }
    return .{ .text = output.items, .failed = failed };
}
