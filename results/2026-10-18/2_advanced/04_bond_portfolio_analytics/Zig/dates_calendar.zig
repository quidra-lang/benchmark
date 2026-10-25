const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), item: T) void { list.append(allocator, item) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, items: []const T) []T { return allocator.dupe(T, items) catch @panic("allocation failed"); }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub fn has(parts: Strings, word: []const u8) bool { for (parts) |part| { if (eq(part, word)) return true; } return false; }
pub fn split(text: []const u8, delimiter: u8) Strings { var parts: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, delimiter); while (it.next()) |part| append([]const u8, &parts, part); return parts.items; }
pub fn lines(text: []const u8) Strings { const all = split(text, '\n'); return all[0..all.len - 1]; }
pub fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn leap(year: i64) bool { return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0); }
pub fn yearLength(year: i64) i64 { return if (leap(year)) 366 else 365; }
pub fn monthLength(year: i64, month: i64) i64 { return if (month == 2 and leap(year)) 29 else ([_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[@intCast(month - 1)]; }
pub const Date = struct { year: i64, month: i64, day: i64 };
pub fn parts(text: []const u8) Date { return .{ .year = integer(text[0..4]), .month = integer(text[5..7]), .day = integer(text[8..10]) }; }
pub fn valid(text: []const u8) bool { const date = parts(text); return date.year >= 2001 and date.year <= 2099 and date.month >= 1 and date.month <= 12 and date.day >= 1 and date.day <= monthLength(date.year, date.month); }
pub fn dayNumber(year: i64, month: i64, day: i64) i64 {
    var result = day - 1;
    var y: i64 = 2000;
    while (y < year) : (y += 1) result += yearLength(y);
    var m: i64 = 1;
    while (m < month) : (m += 1) result += monthLength(year, m);
    return result;
}
pub fn parseDate(text: []const u8) i64 { const date = parts(text); return dayNumber(date.year, date.month, date.day); }
pub fn civil(number: i64) Date {
    var left = number;
    var year: i64 = 2000;
    while (left >= yearLength(year)) : (year += 1) left -= yearLength(year);
    var month: i64 = 1;
    while (left >= monthLength(year, month)) : (month += 1) left -= monthLength(year, month);
    return .{ .year = year, .month = month, .day = left + 1 };
}
pub fn formatDate(number: i64) []const u8 { const date = civil(number); return fmt("{d:0>4}-{d:0>2}-{d:0>2}", .{ date.year, date.month, date.day }); }
pub const Calendar = struct {
    holidays: []const i64,
    pub fn business(c: Calendar, day: i64) bool { return @mod(day + 5, 7) < 5 and std.mem.findScalar(i64, c.holidays, day) == null; }
    pub fn move(c: Calendar, day: i64, count: i64) i64 {
        var result = day;
        const step: i64 = if (count < 0) -1 else 1;
        var left = if (count < 0) -count else count;
        while (left > 0) { result += step; if (c.business(result)) left -= 1; }
        return result;
    }
    pub fn adjust(c: Calendar, day: i64, rule: []const u8) i64 {
        if (eq(rule, "UNADJUSTED")) return day;
        const step: i64 = if (eq(rule, "PRECEDING")) -1 else 1;
        var result = day;
        while (!c.business(result)) result += step;
        if (eq(rule, "MODIFIED_FOLLOWING") and civil(result).month != civil(day).month) return c.adjust(day, "PRECEDING");
        return result;
    }
};
