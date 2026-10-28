const std = @import("std");
const h = @import("heap.zig");
pub const Config = struct { heap: usize, width: usize, collectors: []h.Collector, maps: []const []const u8, windows: []i64 };
pub fn readConfig(io: std.Io) !Config {
    const lines = try h.readLines(io, "config.txt");
    var collectors: std.ArrayList(h.Collector) = .empty;
    var maps: []const []const u8 = &.{};
    var windows: []i64 = &.{};
    var size: usize = 0;
    var width: usize = 0;
    for (lines) |line| {
        const fields = h.split(line, ' ');
        if (h.eq(fields[0], "HEAP")) size = h.u(h.number(fields[1])) else if (h.eq(fields[0], "COLLECTOR")) {
            const kind = std.meta.stringToEnum(h.CollectorType, fields[2]).?;
            h.append(h.Collector, &collectors, .{ .name = fields[1], .kind = kind, .young = if (kind == .GENERATIONAL) h.u(h.number(fields[3])) else 0,
                 .promotion_age = if (kind == .GENERATIONAL) h.u(h.number(fields[4])) else 0 });
        } else if (h.eq(fields[0], "MAPS")) maps = fields[1..] else if (h.eq(fields[0], "MMU")) {
            windows = h.alloc(i64, fields.len - 1);
            for (fields[1..], windows) |field, *value| value.* = h.number(field);
        } else width = h.u(h.number(fields[1]));
    }
    return .{ .heap = size, .width = width, .collectors = collectors.items, .maps = maps, .windows = windows };
}
pub const Kind = enum { ALLOC, PUSH, LOAD, POP, SET, OVERWRITE, CHECKPOINT };
pub const Command = struct { line: usize, kind: Kind = .ALLOC, label: []const u8 = "", reason: ?[]const u8 = null,
     args: [3]i64 = .{ 0, 0, 0 }, object: usize = 0, checkpoint: usize = 0 };
fn numberToken(token: []const u8) bool {
    if (token.len == 0 or token.len > 4 or (token.len > 1 and token[0] == '0')) return false;
    for (token) |c| if (c < '0' or c > '9') return false;
    return true;
}
fn labelToken(token: []const u8) bool {
    if (token.len == 0 or token.len > 16) return false;
    for (token) |c| if (!((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_')) return false;
    return true;
}
pub fn readCommands(io: std.Io) ![]Command {
    const lines = try h.readLines(io, "mutator.txt");
    const commands = h.alloc(Command, lines.len);
    const forms = [_][]const u8{ "nn", "r", "nn", "n", "nnr", "nr", "l" };
    for (lines, commands, 1..) |line, *command, number| {
        command.* = .{ .line = number };
        const fields = h.split(line, ' ');
        const kind = std.meta.stringToEnum(Kind, fields[0]) orelse {
            command.reason = "syntax";
            continue;
        };
        command.kind = kind;
        const form = forms[@intFromEnum(kind)];
        if (fields.len != form.len + 1) {
            command.reason = "syntax";
            continue;
        }
        for (form, fields[1..], 0..) |type_, token, index| {
            const valid = if (type_ == 'l') labelToken(token) else if (type_ == 'r') h.eq(token, "-") or numberToken(token) else numberToken(token);
            if (!valid) {
                command.reason = "syntax";
                break;
            }
            if (type_ == 'l') command.label = token else command.args[index] = if (h.eq(token, "-")) -1 else h.number(token);
        }
        if (command.reason == null and ((kind == .ALLOC and (command.args[0] > 6 or command.args[1] > 24)) or (kind == .POP and command.args[0] == 0))) command.reason = "range";
    }
    return commands;
}
