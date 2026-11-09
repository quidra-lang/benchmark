const std = @import("std");
const c = @import("bitio.zig");
pub const Statistics = struct { codes: usize = 0, clears: usize = 0, longest: usize = 0, widths: [4]usize = std.mem.zeroes([4]usize) };
fn emit(writer: *c.Writer, stats: *Statistics, counter: *usize, code: usize) void {
    const width = @min(12, c.bits(258 + counter.*));
    writer.write(@intCast(code), width);
    stats.codes += 1;
    stats.widths[width - 9] += 1;
    if (code == 256) {
        stats.clears += 1;
        counter.* = 0;
    } else counter.* += 1;
}
pub fn encode(data: []const u8, stats: *Statistics) []const u8 {
    var prefix = std.mem.zeroes([4096]usize);
    var length = std.mem.zeroes([4096]usize);
    var suffix = std.mem.zeroes([4096]u8);
    @memset(length[0..256], 1);
    var next: usize = 258;
    var counter: usize = 0;
    var current: ?usize = null;
    var writer: c.Writer = .{};
    emit(&writer, stats, &counter, 256);
    for (data) |byte| {
        if (current == null) {
            current = byte;
            continue;
        }
        var candidate: ?usize = null;
        for (258..next) |code| if (prefix[code] == current.? and suffix[code] == byte) {
            candidate = code;
            break;
        };
        if (candidate) |code| current = code else {
            emit(&writer, stats, &counter, current.?);
            stats.longest = @max(stats.longest, length[current.?]);
            prefix[next] = current.?;
            suffix[next] = byte;
            length[next] = length[current.?] + 1;
            next += 1;
            if (next == 4096) {
                emit(&writer, stats, &counter, 256);
                next = 258;
            }
            current = byte;
        }
    }
    if (current) |code| {
        emit(&writer, stats, &counter, code);
        stats.longest = @max(stats.longest, length[code]);
    }
    emit(&writer, stats, &counter, 257);
    return writer.bytes.items;
}
fn expand(code_: usize, prefix: *const [4096]usize, suffix: *const [4096]u8, out: *[4096]u8) usize {
    var reverse: [4096]u8 = undefined;
    var code = code_;
    var length: usize = 0;
    while (code >= 258) {
        reverse[length] = suffix[code];
        length += 1;
        code = prefix[code];
    }
    reverse[length] = @intCast(code);
    length += 1;
    for (0..length) |i| out[i] = reverse[length - 1 - i];
    return length;
}
pub fn decode(payload: []const u8, size: usize, output: *c.Bytes) c.DecodeError!void {
    var prefix = std.mem.zeroes([4096]usize);
    var suffix = std.mem.zeroes([4096]u8);
    var entry: [4096]u8 = undefined;
    var next: usize = 258;
    var previous: ?usize = null;
    var counter: usize = 0;
    var reader: c.Reader = .{ .bytes = payload };
    while (true) {
        const before = counter;
        const code: usize = try reader.read(@min(12, c.bits(258 + counter)));
        if (code == 256) {
            next = 258;
            previous = null;
            counter = 0;
            continue;
        }
        counter += 1;
        if (code == 257) {
            if (output.items.len < size) return error.early_end;
            return;
        }
        if (before == 3838) return error.bad_code;
        var length: usize = 0;
        if (previous == null) {
            if (code >= 256) return error.bad_code;
            entry[0] = @intCast(code);
            length = 1;
        } else if (code < next) length = expand(code, &prefix, &suffix, &entry) else if (code == next) {
            length = expand(previous.?, &prefix, &suffix, &entry);
            entry[length] = entry[0];
            length += 1;
        } else return error.bad_code;
        if (output.items.len + length > size) return error.overrun;
        for (entry[0..length]) |byte| c.append(u8, output, byte);
        if (previous) |old| {
            prefix[next] = old;
            suffix[next] = entry[0];
            next += 1;
        }
        previous = code;
    }
}
