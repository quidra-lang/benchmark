const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Integer = i64;
pub const DissectionError = error{Malformed};
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |value| append([]const u8, &out, value);
    return out.items;
}
pub fn join(values: []const []const u8, delimiter: []const u8) []const u8 {
    var text: Text = .{};
    for (values, 0..) |value, i| {
        if (i > 0) text.add("{s}", .{delimiter});
        text.add("{s}", .{value});
    }
    return text.value();
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
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn seconds(value: i64) []const u8 {
    return fmt("{d}.{d:0>6}", .{ @divTrunc(value, 1000000), @mod(value, 1000000) });
}
pub fn decimal(value: i64) []const u8 {
    return fmt("{d}", .{value});
}
pub const Value = struct { number: i64 = 0, text: []const u8 = "" };
pub const Answer = struct { type_: i64, body: []const u8 };
pub const Packet = struct {
    number: i64 = 0,
    time: i64 = 0,
    length: i64 = 0,
    raw: []const u8 = &.{},
    remaining: []const u8 = &.{},
    reason: ?[]const u8 = null,
    layers: std.ArrayList([]const u8) = .empty,
    fields: std.StringHashMapUnmanaged(std.ArrayList(Value)) = .empty,
    dns_answers: std.ArrayList(Answer) = .empty,
    duplicate_origin: i64 = 0,
    duplicate_count: i64 = 0,
    pub fn set(self: *Packet, name: []const u8, value: Value, multiple: bool) void {
        const entry = self.fields.getOrPut(allocator, name) catch @panic("allocation failed");
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        if (!multiple) entry.value_ptr.items.len = 0;
        append(Value, entry.value_ptr, value);
    }
    pub fn put(self: *Packet, name: []const u8, value: i64) void {
        self.set(name, .{ .number = value }, false);
    }
    pub fn text(self: *Packet, name: []const u8, value: []const u8) void {
        self.set(name, .{ .text = value }, false);
    }
    pub fn flag(self: *Packet, name: []const u8) void {
        self.put(name, 0);
    }
    pub fn values(self: Packet, name: []const u8) []const Value {
        return if (self.fields.get(name)) |values_| values_.items else &.{};
    }
    pub fn has(self: Packet, name: []const u8) bool {
        return self.values(name).len > 0;
    }
    pub fn num(self: Packet, name: []const u8) i64 {
        const list = self.values(name);
        return if (list.len > 0) list[0].number else 0;
    }
    pub fn str(self: Packet, name: []const u8) []const u8 {
        const list = self.values(name);
        return if (list.len > 0) list[0].text else "";
    }
    pub fn fail(self: *Packet, reason: []const u8) DissectionError {
        self.reason = reason;
        return error.Malformed;
    }
};
fn lowerHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
}
fn wellFormed(text: []const u8) bool {
    if (text.len < 8 or text.len > 53 or (text.len - 8) % 3 != 0 or text[4] != ' ' or text[5] != ' ') return false;
    for (text[0..4]) |c| if (!lowerHex(c)) return false;
    var i: usize = 6;
    while (i < text.len) : (i += 3) {
        if (!lowerHex(text[i]) or !lowerHex(text[i + 1]) or (i + 2 < text.len and text[i + 2] != ' ')) return false;
    }
    return true;
}
fn finish(packet: *Packet) void {
    if (packet.reason == null and n(packet.raw.len) != packet.length) packet.reason = fmt("dump: length mismatch (header {d}, data {d})",
         .{ packet.length, packet.raw.len });
}
pub fn readCapture(io: std.Io) ![]Packet {
    const lines = try readLines(io, "input/capture.txt");
    var packets: std.ArrayList(Packet) = .empty;
    var raw: std.ArrayList(u8) = .empty;
    for (lines, 1..) |line, line_number| {
        if (std.mem.startsWith(u8, line, "PACKET ")) {
            if (packets.items.len > 0) finish(&packets.items[packets.items.len - 1]);
            const fields = split(line, ' ');
            append(Packet, &packets, .{ .number = number(fields[1]), .time = number(fields[2]), .length = number(fields[3]) });
            raw = .empty;
            continue;
        }
        const packet = &packets.items[packets.items.len - 1];
        if (line.len == 0 or packet.reason != null) continue;
        if (!wellFormed(line)) {
            packet.reason = fmt("dump: bad line {d}", .{line_number});
            continue;
        }
        const offset = std.fmt.parseInt(usize, line[0..4], 16) catch unreachable;
        if (offset != raw.items.len) {
            packet.reason = fmt("dump: offset mismatch at line {d}", .{line_number});
            continue;
        }
        var i: usize = 6;
        while (i < line.len) : (i += 3) append(u8, &raw, std.fmt.parseInt(u8, line[i .. i + 2], 16) catch unreachable);
        packet.raw = raw.items;
    }
    finish(&packets.items[packets.items.len - 1]);
    return packets.items;
}
pub fn dumpLines(data: []const u8) Lines {
    var out: Lines = .{};
    var start: usize = 0;
    while (start < data.len) : (start += 16) {
        var bytes: Text = .{};
        var characters: Text = .{};
        for (data[start..@min(start + 16, data.len)], 0..) |byte, i| {
            bytes.add("{s}{x:0>2}", .{ if (i == 0) "" else " ", byte });
            characters.add("{c}", .{if (byte >= 32 and byte <= 126) byte else @as(u8, '.')});
        }
        out.add("{x:0>4}  {s: <47}  |{s}|", .{ start, bytes.value(), characters.value() });
    }
    return out;
}
