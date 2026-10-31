const std = @import("std");
const s = @import("schema_io.zig");
pub const Reader = struct {
    data: []const u8,
    position: usize = 0,
    pub fn byte(self: *Reader) u8 {
        const value = self.data[self.position];
        self.position += 1;
        return value;
    }
    pub fn read(self: *Reader, count: usize) []const u8 {
        const start = self.position;
        self.position += count;
        return self.data[start..self.position];
    }
    pub fn uleb(self: *Reader) i64 {
        var value: i64 = 0;
        var shift: u6 = 0;
        while (true) {
            const next = self.byte();
            value |= @as(i64, next & 127) << shift;
            if (next < 128) return value;
            shift += 7;
        }
    }
    pub fn zigzag(self: *Reader) i64 {
        const value = self.uleb();
        return if (@mod(value, 2) == 0) @divTrunc(value, 2) else -@divTrunc(value + 1, 2);
    }
    pub fn integer(self: *Reader, signed_value: bool) i64 {
        var value: i64 = 0;
        for (0..4) |i| value |= @as(i64, self.byte()) << @intCast(8 * i);
        return if (signed_value and value >= (@as(i64, 1) << 31)) value - (@as(i64, 1) << 32) else value;
    }
};
pub const Writer = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn byte(self: *Writer, value: u8) void {
        s.append(u8, &self.data, value);
    }
    pub fn raw(self: *Writer, values: []const u8) void {
        self.data.appendSlice(s.allocator, values) catch @panic("allocation failed");
    }
    pub fn bytes(self: Writer) []const u8 {
        return self.data.items;
    }
    pub fn uleb(self: *Writer, value: i64) void {
        var next = value;
        while (next >= 128) {
            self.byte(@intCast(@mod(next, 128) + 128));
            next = @divTrunc(next, 128);
        }
        self.byte(@intCast(next));
    }
    pub fn zigzag(self: *Writer, value: i64) void {
        self.uleb(if (value >= 0) 2 * value else -2 * value - 1);
    }
    pub fn integer(self: *Writer, value: i64) void {
        const unsigned = if (value < 0) value + (@as(i64, 1) << 32) else value;
        for (0..4) |i| self.byte(@intCast((unsigned >> @intCast(8 * i)) & 255));
    }
};
pub fn bits(value: i64) usize {
    var n = value;
    var width: usize = 0;
    while (n > 0) {
        n >>= 1;
        width += 1;
    }
    return width;
}
pub fn pack(values: s.Numbers, width: usize) []const u8 {
    var out: Writer = .{};
    var buffer: u64 = 0;
    var occupied: usize = 0;
    for (values) |value| {
        buffer |= @as(u64, @intCast(value)) << @intCast(occupied);
        occupied += width;
        while (occupied >= 8) {
            out.byte(@intCast(buffer & 255));
            buffer >>= 8;
            occupied -= 8;
        }
    }
    return out.bytes();
}
pub fn unpack(reader: *Reader, width: usize, count: usize) s.Numbers {
    const out = s.alloc(i64, count);
    var buffer: u64 = 0;
    const mask = (@as(u64, 1) << @intCast(width)) - 1;
    var occupied: usize = 0;
    for (out) |*value| {
        while (occupied < width) {
            buffer |= @as(u64, reader.byte()) << @intCast(occupied);
            occupied += 8;
        }
        value.* = @intCast(buffer & mask);
        buffer >>= @intCast(width);
        occupied -= width;
    }
    return out;
}
pub fn adler32(data: []const u8) i64 {
    var first: i64 = 1;
    var second: i64 = 0;
    for (data) |byte| {
        first = @mod(first + byte, 65521);
        second = @mod(second + first, 65521);
    }
    return second * 65536 + first;
}
pub fn hybridEncode(values: s.Numbers, width: usize) []const u8 {
    const runs = s.alloc(usize, values.len);
    var i = values.len;
    while (i > 0) {
        i -= 1;
        runs[i] = 1 + (if (i + 1 < values.len and values[i] == values[i + 1]) runs[i + 1] else @as(usize, 0));
    }
    var out: Writer = .{};
    while (i < values.len) {
        if (runs[i] >= 8) {
            out.uleb(2 * s.n(runs[i]));
            for (0..(width + 7) / 8) |j| out.byte(@intCast((values[i] >> @intCast(8 * j)) & 255));
            i += runs[i];
        } else {
            var end = i;
            var groups: usize = 0;
            while (true) {
                end += 8;
                groups += 1;
                if (end >= values.len or groups == 63 or runs[end] >= 8) break;
            }
            out.uleb(2 * s.n(groups) + 1);
            const block = s.zero(i64, end - i, 0);
            @memcpy(block[0 .. @min(end, values.len) - i], values[i..@min(end, values.len)]);
            out.raw(pack(block, width));
            i = end;
        }
    }
    return out.bytes();
}
pub fn hybridDecode(reader: *Reader, width: usize, count: usize) s.Numbers {
    var values: std.ArrayList(i64) = .empty;
    while (values.items.len < count) {
        const header = reader.uleb();
        if (@mod(header, 2) == 0) {
            var value: i64 = 0;
            for (0..(width + 7) / 8) |i| value |= @as(i64, reader.byte()) << @intCast(8 * i);
            for (0..s.u(@divTrunc(header, 2))) |_| s.append(i64, &values, value);
        } else for (unpack(reader, width, s.u(@divTrunc(header - 1, 2) * 8))) |value| s.append(i64, &values, value);
    }
    return values.items[0..count];
}
pub fn hexadecimal(data: []const u8) []const u8 {
    const digits = "0123456789abcdef";
    const out = s.alloc(u8, 2 * data.len);
    for (data, 0..) |byte, i| {
        out[2 * i] = digits[byte >> 4];
        out[2 * i + 1] = digits[byte & 15];
    }
    return out;
}
pub fn checksumText(value: i64) []const u8 {
    return s.fmt("{x:0>8}", .{value});
}
