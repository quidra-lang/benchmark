const std = @import("std");
const values = @import("values_fields.zig");
const Value = values.Value;
pub const Issue = enum { invalid_format, not_enough_arguments, invalid_character_code };
pub fn format(a: std.mem.Allocator, fmt: []const u8, args: []const Value, issue: *Issue) ![]const u8 {
    var result: std.ArrayList(u8) = .empty; var p: usize = 0; var argument: usize = 0;
    while (p < fmt.len) {
        if (fmt[p] != '%') { try result.append(a, fmt[p]); p += 1; continue; } p += 1;
        if (p < fmt.len and fmt[p] == '%') { try result.append(a, '%'); p += 1; continue; }
        var left = false; var zero = false;
        while (p < fmt.len and (fmt[p] == '-' or fmt[p] == '0')) : (p += 1) { left = left or fmt[p] == '-'; zero = zero or fmt[p] == '0'; }
        var width: usize = 0; while (p < fmt.len and std.ascii.isDigit(fmt[p])) : (p += 1) width = width * 10 + fmt[p] - '0';
        var precision: ?usize = null; if (p < fmt.len and fmt[p] == '.') { p += 1; precision = 0; while (p < fmt.len and std.ascii.isDigit(fmt[p])) : (p += 1) precision = precision.? * 10 + fmt[p] - '0'; }
        if (p == fmt.len or std.mem.indexOfScalar(u8, "dis cxo", fmt[p]) == null or fmt[p] == ' ') { issue.* = .invalid_format; return error.Format; } const kind = fmt[p]; p += 1;
        if (argument == args.len) { issue.* = .not_enough_arguments; return error.Format; } const v = args[argument]; argument += 1; var body: []const u8 = ""; var numeric = false; var negative = false;
        if (kind == 'd' or kind == 'i' or kind == 'x' or kind == 'o') {
            numeric = true; const n = v.num(); negative = n < 0; const magnitude: u64 = @intCast(@abs(n)); var digits = switch (kind) { 'x' => try std.fmt.allocPrint(a, "{x}", .{magnitude}), 'o' => try std.fmt.allocPrint(a, "{o}", .{magnitude}), else => try std.fmt.allocPrint(a, "{d}", .{magnitude}) };
            if (precision == 0 and n == 0) digits = "";
            var bytes: std.ArrayList(u8) = .empty; if (negative) try bytes.append(a, '-'); if (precision) |limit| while (bytes.items.len - @intFromBool(negative) + digits.len < limit) { try bytes.append(a, '0'); };
            try bytes.appendSlice(a, digits); body = bytes.items;
        } else if (kind == 's') { const s = try v.text(a); body = s[0..@min(s.len, precision orelse s.len)]; }
        else if (v.kind == .number or v.kind == .strnum) { const n = v.num(); if (n != 10 and (n < 32 or n > 126)) { issue.* = .invalid_character_code; return error.Format; } const byte = try a.alloc(u8, 1); byte[0] = @intCast(n); body = byte; }
        else { const s = try v.text(a); body = s[0..@min(s.len, 1)]; }
        const padding = width -| body.len;
        if (left) { try result.appendSlice(a, body); for (0..padding) |_| try result.append(a, ' '); }
        else if (numeric and zero and precision == null) { if (negative) try result.append(a, '-'); for (0..padding) |_| try result.append(a, '0'); try result.appendSlice(a, body[@intFromBool(negative)..]); }
        else { for (0..padding) |_| try result.append(a, ' '); try result.appendSlice(a, body); }
    }
    return result.items;
}
pub fn substr(s: []const u8, start: i64, count: ?i64) []const u8 { const end = @min(@as(i64, @intCast(s.len)) + 1, if (count) |n| start + n else @as(i64, @intCast(s.len)) + 1); const first = @max(start, 1); return if (end <= first) "" else s[@intCast(first - 1)..@intCast(end - 1)]; }
pub fn index(s: []const u8, t: []const u8) i64 { if (t.len == 0) return 0; return if (std.mem.indexOf(u8, s, t)) |i| @as(i64, @intCast(i)) + 1 else 0; }
pub fn case(a: std.mem.Allocator, s: []const u8, upper: bool) ![]const u8 { const result = try a.dupe(u8, s); for (result) |*c| c.* = if (upper) std.ascii.toUpper(c.*) else std.ascii.toLower(c.*); return result; }
