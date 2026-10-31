const std = @import("std");
const dates = @import("dates_calendar.zig");

pub fn build(issue: i64, maturity: i64, frequency: i64, eom: bool, long_stub: bool) []const i64 {
    const end = dates.civil(maturity);
    const end_rule = eom and end.day == dates.monthLength(end.year, end.month);
    var result: std.ArrayList(i64) = .empty;
    var boundary = maturity;
    while (boundary > issue) {
        dates.append(i64, &result, boundary);
        const index = end.year * 12 + end.month - 1 - @divFloor(12, frequency) * @as(i64, @intCast(result.items.len));
        const year = @divFloor(index, 12);
        const month = @mod(index, 12) + 1;
        const day = if (end_rule) dates.monthLength(year, month) else @min(end.day, dates.monthLength(year, month));
        boundary = dates.dayNumber(year, month, day);
    }
    if (long_stub and boundary != issue and result.items.len >= 2) result.items.len -= 1;
    dates.append(i64, &result, issue);
    std.mem.reverse(i64, result.items);
    return result.items;
}
