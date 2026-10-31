const std = @import("std");
const d = @import("image_io.zig");
pub const DecodeError = error{ Marker, Code, Index, Sync };
pub const Writer = struct {
    data: std.ArrayList(u8) = .empty,
    buffer: u32 = 0,
    pending: usize = 0,
    padding: usize = 0,
    stuffed: usize = 0,
    pub fn write(self: *Writer, value: u32, width: usize) void {
        var shift = width;
        while (shift > 0) {
            shift -= 1;
            self.buffer = 2 * self.buffer + ((value >> @as(u5, @intCast(shift))) & 1);
            self.pending += 1;
            if (self.pending == 8) {
                d.append(u8, &self.data, @intCast(self.buffer));
                if (self.buffer == 255) {
                    d.append(u8, &self.data, 0);
                    self.stuffed += 1;
                }
                self.buffer = 0;
                self.pending = 0;
            }
        }
    }
    pub fn pad(self: *Writer) void {
        if (self.pending > 0) {
            const width = 8 - self.pending;
            self.padding += width;
            self.write((@as(u32, 1) << @as(u5, @intCast(width))) - 1, width);
        }
    }
    pub fn restart(self: *Writer, number: usize) void {
        self.pad();
        d.append(u8, &self.data, 255);
        d.append(u8, &self.data, @intCast(0xd0 + number % 8));
    }
};
pub const Reader = struct {
    data: []const u8,
    position: usize,
    buffer: u8 = 0,
    remaining: usize = 0,
    pub fn bit(self: *Reader) DecodeError!u32 {
        if (self.remaining == 0) {
            const value = self.data[self.position];
            if (value == 255) {
                if (self.data[self.position + 1] != 0) return error.Marker;
                self.position += 2;
            } else self.position += 1;
            self.buffer = value;
            self.remaining = 8;
        }
        self.remaining -= 1;
        return (self.buffer >> @as(u3, @intCast(self.remaining))) & 1;
    }
    pub fn read(self: *Reader, width: usize) DecodeError!u32 {
        var value: u32 = 0;
        for (0..width) |_| value = 2 * value + try self.bit();
        return value;
    }
    pub fn discard(self: *Reader) void {
        self.buffer = 0;
        self.remaining = 0;
    }
};
pub fn findResync(data: []const u8, position: usize) usize {
    var offset = position;
    while (offset + 1 < data.len) : (offset += 1) {
        if (data[offset] == 255 and ((data[offset + 1] >= 0xd0 and data[offset + 1] <= 0xd7) or data[offset + 1] == 0xd9)) return offset;
    }
    return data.len - 2;
}
