const std = @import("std");
const p = @import("protocol.zig");
pub const Change = struct { sign: u8, character: u8, argument: ?[]const u8 = null };
pub fn channelItems(mode: []const u8, arguments: []const []const u8) []const Change {
    var out: std.ArrayList(Change) = .empty;
    var sign: u8 = '+';
    var position: usize = 0;
    for (mode) |c| {
        if (c == '+' or c == '-') {
            sign = c;
            continue;
        }
        var argument: ?[]const u8 = null;
        if (c == 'o' or c == 'v' or c == 'b' or c == 'k' or (c == 'l' and sign == '+')) {
            if (position < arguments.len) {
                argument = arguments[position];
                position += 1;
            }
        }
        if (c == 'k' and sign == '-') argument = "*" else if (c == 'l' and sign == '+') {
            if (argument) |value| {
                if (!p.digits(value) or value.len > 4 or p.number(value) < 1) argument = null;
            }
        }
        p.append(Change, &out, .{ .sign = sign, .character = c, .argument = argument });
    }
    return out.items;
}
pub fn changeString(changes: []const Change) []const u8 {
    var mode: p.Text = .{};
    var arguments: p.Text = .{};
    var previous: u8 = 0;
    for (changes) |change| {
        if (change.sign != previous) {
            mode.add("{c}", .{change.sign});
            previous = change.sign;
        }
        mode.add("{c}", .{change.character});
        if (change.argument) |value| arguments.add(" {s}", .{value});
    }
    return p.fmt("{s}{s}", .{ mode.value(), arguments.value() });
}
