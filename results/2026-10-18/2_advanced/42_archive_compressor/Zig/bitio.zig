const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub const Bytes = std.ArrayList(u8);
pub const DecodeError = error{ end_of_data, bad_code, bad_offset, bad_table, overrun, early_end };
pub fn bits(value_: usize) usize {
    var value = value_;
    var count: usize = 0;
    while (value > 0) {
        count += 1;
        value >>= 1;
    }
    return count;
}
pub const Writer = struct {
    bytes: Bytes = .empty,
    count: usize = 0,
    pub fn write(self: *Writer, value: u32, width: usize) void {
        var remaining = width;
        while (remaining > 0) {
            remaining -= 1;
            if (self.count % 8 == 0) append(u8, &self.bytes, 0);
            const bit = (value >> @as(u5, @intCast(remaining))) & 1;
            self.bytes.items[self.bytes.items.len - 1] |= @as(u8, @intCast(bit)) << @as(u3, @intCast(7 - self.count % 8));
            self.count += 1;
        }
    }
};
pub const Reader = struct {
    bytes: []const u8,
    position: usize = 0,
    zero_extend: bool = false,
    pub fn read(self: *Reader, width: usize) DecodeError!u32 {
        if (!self.zero_extend and self.position + width > self.bytes.len * 8) return error.end_of_data;
        var value: u32 = 0;
        for (0..width) |_| {
            value <<= 1;
            if (self.position < self.bytes.len * 8) value |= (self.bytes[self.position / 8] >> @as(u3,
                 @intCast(7 - self.position % 8))) & 1;
            self.position += 1;
        }
        return value;
    }
};
