const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
pub const literal_dollar: u8 = 1;
pub const Problem = struct { code: Text, message: Text };
pub const LogicalLine = struct { number: usize, segments: []const Text, problem: ?Problem };

pub fn logicalLines(gpa: Allocator, source: Text) Allocator.Error![]const LogicalLine {
    var physical: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    while (start < source.len) {
        const end = if (std.mem.findScalar(u8, source[start..], '\n')) |offset| start + offset else source.len;
        try physical.append(gpa, source[start..end]);
        start = end + 1;
    }
    var lines: std.ArrayList(LogicalLine) = .empty;
    var index: usize = 0;
    while (index < physical.items.len) {
        const number = index + 1;
        var input = physical.items[index];
        index += 1;
        var position: usize = 0;
        var quoted = false;
        var segments: std.ArrayList(Text) = .empty;
        var current: std.ArrayList(u8) = .empty;
        var problem: ?Problem = null;
        while (position < input.len) {
            const byte = input[position];
            if (byte == '\\' and position + 1 == input.len) {
                input = std.mem.trimStart(u8, physical.items[index], " ");
                index += 1;
                position = 0;
            } else if (quoted and byte == '\\') {
                const follower = input[position + 1];
                const decoded: ?u8 = switch (follower) {
                    '\\', '"' => follower, 'n' => '\n', 't' => '\t', '$' => literal_dollar, else => null,
                };
                if (decoded) |c| {
                    try current.append(gpa, c);
                } else if (problem == null) {
                    problem = .{ .code = "E_ESCAPE", .message = try std.fmt.allocPrint(gpa, "invalid escape sequence \\{c}", .{follower}) };
                }
                position += 2;
            } else if (byte == '"') {
                try segments.append(gpa, try current.toOwnedSlice(gpa));
                current = .empty;
                quoted = !quoted;
                position += 1;
            } else if (!quoted and (byte == ';' or byte == '#')) {
                break;
            } else {
                try current.append(gpa, byte);
                position += 1;
            }
        }
        if (quoted and problem == null) problem = .{ .code = "E_UNTERMINATED", .message = "unterminated string" };
        try segments.append(gpa, try current.toOwnedSlice(gpa));
        try lines.append(gpa, .{ .number = number, .segments = try segments.toOwnedSlice(gpa), .problem = problem });
    }
    return lines.toOwnedSlice(gpa);
}
