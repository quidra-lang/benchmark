const dates = @import("dates_calendar.zig");
pub const conventions = [_][]const u8{ "30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT" };
pub const Fraction = struct { n: i64, m: i64, pub fn value(f: Fraction) f64 { return dates.real(f.n) / dates.real(f.m); } };

pub fn fraction(convention: []const u8, start: i64, end: i64) Fraction {
    var a = dates.civil(start);
    var b = dates.civil(end);
    if (dates.eq(convention, "30/360")) {
        const february = a.month == 2 and a.day == dates.monthLength(a.year, a.month);
        if (february and b.month == 2 and b.day == dates.monthLength(b.year, b.month)) b.day = 30;
        if (february) a.day = 30;
        if (b.day == 31 and a.day >= 30) b.day = 30;
        if (a.day == 31) a.day = 30;
    } else if (dates.eq(convention, "30E/360")) {
        a.day = @min(a.day, 30);
        b.day = @min(b.day, 30);
    } else if (dates.eq(convention, "ACT/360")) return .{ .n = end - start, .m = 360 } else if (dates.eq(convention, "ACT/365F")) return .{ .n = end - start, .m = 365 } else {
        var left = start;
        var year = a.year;
        var numerator: i64 = 0;
        while (left < end) : (year += 1) {
            const boundary = @min(dates.dayNumber(year + 1, 1, 1), end);
            numerator += (if (dates.leap(year)) @as(i64, 365) else 366) * (boundary - left);
            left = boundary;
        }
        return .{ .n = numerator, .m = 133590 };
    }
    return .{ .n = 360 * (b.year - a.year) + 30 * (b.month - a.month) + b.day - a.day, .m = 360 };
}
