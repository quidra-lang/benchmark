pub const neg_infinity: i64 = -(@as(i64, 1) << 62);
pub const pos_infinity: i64 = @as(i64, 1) << 62;
pub const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
pub const weekday_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
pub fn leapYear(year: i64) bool { return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or @mod(year, 400) == 0; }
pub fn daysInMonth(year: i64, month: i64) i64 {
    const lengths = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return if (month == 2 and leapYear(year)) 29 else lengths[@intCast(month - 1)];
}
fn daysBeforeYear(year: i64) i64 {
    const previous = year - 1;
    return previous * 365 + @divFloor(previous, 4) - @divFloor(previous, 100) + @divFloor(previous, 400);
}
pub fn dayNumber(year: i64, month: i64, day: i64) i64 {
    var result = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1;
    var earlier: i64 = 1;
    while (earlier < month) : (earlier += 1) result += daysInMonth(year, earlier);
    return result;
}
pub fn weekdayOf(number: i64) i64 { return @mod(number + 4, 7); }
pub const DaySpec = struct {
    kind: enum { day, last, after, before } = .day,
    weekday: i64 = 0,
    day: i64 = 0,
    pub fn value(self: DaySpec, year: i64, month: i64) i64 {
        if (self.kind == .last) {
            const last = dayNumber(year, month, daysInMonth(year, month));
            return last - @mod(weekdayOf(last) - self.weekday, 7);
        }
        const base = dayNumber(year, month, self.day);
        return switch (self.kind) {
            .after => base + @mod(self.weekday - weekdayOf(base), 7),
            .before => base - @mod(weekdayOf(base) - self.weekday, 7),
            else => base,
        };
    }
};
pub const DateTime = struct { year: i64, month: i64 = 1, day: i64 = 1, hour: i64 = 0, minute: i64 = 0, second: i64 = 0 };
pub fn timeValue(date: DateTime) i64 { return dayNumber(date.year, date.month, date.day) * 86400 + date.hour * 3600 + date.minute * 60 + date.second; }
pub fn splitTime(time: i64) DateTime {
    const number = @divFloor(time, 86400);
    const seconds = @mod(time, 86400);
    var year = 1970 + @divFloor(number, 366);
    while (dayNumber(year, 1, 1) > number) year -= 1;
    while (dayNumber(year + 1, 1, 1) <= number) year += 1;
    var month: i64 = 1;
    var day = number - dayNumber(year, 1, 1) + 1;
    while (day > daysInMonth(year, month)) : (month += 1) day -= daysInMonth(year, month);
    return .{ .year = year, .month = month, .day = day, .hour = @divTrunc(seconds, 3600), .minute = @mod(@divTrunc(seconds, 60), 60), .second = @mod(seconds, 60) };
}
