const std = @import("std");
const s = @import("schema_io.zig");
const b = @import("bitstream.zig");
pub const Method = enum(u8) { plain, dictionary, rle, delta_binary_packed, delta_length_byte_array };
pub const methods = [_][]const u8{ "PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY" };
pub fn findMethod(name: []const u8) ?Method {
    for (methods, 0..) |method, i| if (s.eq(name, method)) return @enumFromInt(i);
    return null;
}
pub fn candidates(kind: s.Type) []const Method {
    return switch (kind) {
        .boolean => &.{ .plain, .rle },
        .string => &.{ .plain, .dictionary, .delta_length_byte_array },
        else => &.{ .plain, .dictionary, .delta_binary_packed },
    };
}
pub fn deltaEncode(values: s.Numbers) []const u8 {
    var out: b.Writer = .{};
    out.uleb(128);
    out.uleb(4);
    out.uleb(s.n(values.len));
    out.zigzag(if (values.len == 0) 0 else values[0]);
    const differences = s.alloc(i64, if (values.len == 0) 0 else values.len - 1);
    for (differences, 1..) |*value, i| value.* = values[i] - values[i - 1];
    var start: usize = 0;
    while (start < differences.len) : (start += 128) {
        const end = @min(start + 128, differences.len);
        var minimum = differences[start];
        for (differences[start..end]) |value| minimum = @min(minimum, value);
        out.zigzag(minimum);
        var blocks: [4][32]i64 = std.mem.zeroes([4][32]i64);
        var widths: [4]usize = @splat(0);
        var counts: [4]usize = @splat(0);
        for (differences[start..end], 0..) |value, i| {
            const t = i / 32;
            const delta = value - minimum;
            blocks[t][i % 32] = delta;
            widths[t] = @max(widths[t], b.bits(delta));
            counts[t] += 1;
        }
        for (widths) |width| out.byte(@intCast(width));
        for (0..4) |t| if (counts[t] > 0) out.raw(b.pack(&blocks[t], widths[t]));
    }
    return out.bytes();
}
pub fn deltaDecode(reader: *b.Reader) s.Numbers {
    const block_size = s.u(reader.uleb());
    const miniblock_count = s.u(reader.uleb());
    const count = s.u(reader.uleb());
    const first = reader.zigzag();
    var values: std.ArrayList(i64) = .empty;
    if (count > 0) s.append(i64, &values, first);
    const miniblock_size = block_size / miniblock_count;
    while (values.items.len < count) {
        const minimum = reader.zigzag();
        const widths = reader.read(miniblock_count);
        for (widths) |width| {
            if (values.items.len == count) break;
            const differences = b.unpack(reader, width, miniblock_size);
            const remaining = count - values.items.len;
            for (differences[0..@min(miniblock_size, remaining)]) |difference| s.append(i64,
                 &values, values.items[values.items.len - 1] + minimum + difference);
        }
    }
    return values.items;
}
pub fn encodeValues(kind: s.Type, method: Method, values: s.Values, dictionary: s.Values) []const u8 {
    var out: b.Writer = .{};
    if (method == .plain) {
        if (kind == .integer or kind == .date) for (values) |value| out.integer(value.integer) else if (kind == .string) for (values) |value| {
            out.integer(s.n(value.string.len));
            out.raw(value.string);
        } else {
            const numbers = s.zero(i64, (values.len + 7) / 8 * 8, 0);
            for (values, 0..) |value, i| numbers[i] = value.integer;
            out.raw(b.pack(numbers, 1));
        }
        return out.bytes();
    }
    if (method == .dictionary) {
        const width = b.bits(s.n(dictionary.len) - 1);
        out.byte(@intCast(width));
        const ranks = s.alloc(i64, values.len);
        for (values, ranks) |value, *rank| {
            var i: usize = 0;
            while (!s.valueEqual(dictionary[i], value)) i += 1;
            rank.* = s.n(i);
        }
        out.raw(b.hybridEncode(ranks, width));
        return out.bytes();
    }
    const numbers = s.alloc(i64, values.len);
    for (values, numbers) |value, *number| number.* = if (kind == .string) s.n(value.string.len) else value.integer;
    if (method == .rle) {
        const encoded = b.hybridEncode(numbers, 1);
        out.integer(s.n(encoded.len));
        out.raw(encoded);
    } else {
        out.raw(deltaEncode(numbers));
        if (method == .delta_length_byte_array) for (values) |value| out.raw(value.string);
    }
    return out.bytes();
}
pub fn decodeValues(reader: *b.Reader, kind: s.Type, method: Method, count: usize, dictionary: s.Values) s.Values {
    const out = s.alloc(s.Value, count);
    if (method == .plain) {
        if (kind == .integer or kind == .date) for (out) |*value| {
            value.* = .{ .integer = reader.integer(true) };
        } else if (kind == .string) for (out) |*value| {
            const length = s.u(reader.integer(false));
            value.* = .{ .string = reader.read(length) };
        } else {
            const numbers = b.unpack(reader, 1, (count + 7) / 8 * 8);
            for (out, numbers[0..count]) |*value, number| value.* = .{ .integer = @intFromBool(number != 0) };
        }
        return out;
    }
    if (method == .dictionary) {
        const width = reader.byte();
        const ranks = b.hybridDecode(reader, width, count);
        for (out, ranks) |*value, rank| value.* = dictionary[s.u(rank)];
        return out;
    }
    if (method == .rle) {
        const length = s.u(reader.integer(false));
        var encoded: b.Reader = .{ .data = reader.read(length) };
        for (out, b.hybridDecode(&encoded, 1, count)) |*value, number| value.* = .{ .integer = @intFromBool(number != 0) };
        return out;
    }
    const numbers = deltaDecode(reader);
    for (out, numbers) |*value, number| value.* = if (method == .delta_binary_packed) .{ .integer = number } else .{ .string = reader.read(s.u(number)) };
    return out;
}
pub fn encodeStatistics(kind: s.Type, bounds: ?s.Bounds) []const u8 {
    var out: b.Writer = .{};
    out.byte(@intFromBool(bounds != null));
    if (bounds) |range| for ([_]s.Value{ range.low, range.high }) |value| {
        if (kind == .integer or kind == .date) out.zigzag(value.integer) else if (kind == .string) {
            out.uleb(s.n(value.string.len));
            out.raw(value.string);
        } else out.byte(@intCast(value.integer));
    };
    return out.bytes();
}
pub fn decodeStatistics(reader: *b.Reader, kind: s.Type) ?s.Bounds {
    if (reader.byte() == 0) return null;
    var values: [2]s.Value = undefined;
    for (&values) |*value| {
        if (kind == .integer or kind == .date) value.* = .{ .integer = reader.zigzag() } else if (kind == .string) {
            const length = s.u(reader.uleb());
            value.* = .{ .string = reader.read(length) };
        } else value.* = .{ .integer = @intFromBool(reader.byte() != 0) };
    }
    return .{ .low = values[0], .high = values[1] };
}
