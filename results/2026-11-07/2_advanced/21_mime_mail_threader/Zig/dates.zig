const h = @import("headers.zig");

pub const Date = struct { seconds: ?i64 = null, error_text: ?[]const u8 = null };

fn leap(year: i64) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or @mod(year, 400) == 0;
}

fn monthDays(year: i64, month: i64) i64 {
    const lengths = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return if (month == 2 and leap(year)) 29 else lengths[h.u(month - 1)];
}

fn yearDays(year: i64) i64 {
    return if (leap(year)) 366 else 365;
}

fn digits(text: []const u8, first: usize, second: usize) bool {
    if (text.len != first and text.len != second) return false;
    for (text) |character| if (character < '0' or character > '9') return false;
    return true;
}

pub fn parse(source: []const u8) Date {
    const syntax: Date = .{ .error_text = "bad Date syntax" };
    const range: Date = .{ .error_text = "Date out of range" };
    const weekdays = [_][]const u8{ "mon", "tue", "wed", "thu", "fri", "sat", "sun" };
    const months = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
    const zones = [_][]const u8{ "ut", "gmt", "z", "est", "edt", "cst", "cdt", "mst", "mdt", "pst", "pdt" };
    const offsets = [_]i64{ 0, 0, 0, -300, -240, -360, -300, -420, -360, -480, -420 };
    const clean = h.removeComments(source) orelse return syntax;
    var spaced: h.Text = .{};
    for (clean) |character| {
        if (character == ',') spaced.write(" , ") else spaced.add("{c}", .{character});
    }
    const tokens = h.splitWords(spaced.value());
    var weekday: ?usize = null;
    var start: usize = 0;
    if (tokens.len >= 3 and h.eq(tokens[1], ",")) {
        for (weekdays, 0..) |name, i| if (h.equalCase(tokens[0], name)) { weekday = i; };
        if (weekday != null) start = 2;
    }
    if (tokens.len - start != 5) return syntax;
    const day_text = tokens[start];
    const month_text = tokens[start + 1];
    const year_text = tokens[start + 2];
    const time = h.split(tokens[start + 3], ':');
    const zone = tokens[start + 4];
    var month: i64 = 0;
    var zone_index: ?usize = null;
    for (months, 0..) |name, i| if (h.equalCase(month_text, name)) { month = h.n(i + 1); };
    for (zones, 0..) |name, i| if (h.equalCase(zone, name)) { zone_index = i; };
    const numeric_zone = zone.len == 5 and (zone[0] == '+' or zone[0] == '-') and digits(zone[1..], 4, 4);
    var time_valid = time.len == 2 or time.len == 3;
    for (time) |part| if (!digits(part, 2, 2)) { time_valid = false; };
    if (!digits(day_text, 1, 2) or month == 0 or !digits(year_text, 2, 4) or !time_valid or (!numeric_zone and zone_index == null)) return syntax;
    var year = h.number(year_text);
    if (year_text.len == 2) year += if (year < 50) @as(i64, 2000) else 1900;
    const day = h.number(day_text);
    const hour = h.number(time[0]);
    const minute = h.number(time[1]);
    const second = if (time.len == 3) h.number(time[2]) else 0;
    var offset: i64 = undefined;
    if (numeric_zone) {
        const hours = h.number(zone[1..3]);
        const minutes = h.number(zone[3..]);
        if (hours > 23 or minutes > 59) return range;
        offset = hours * 60 + minutes;
        if (zone[0] == '-') offset = -offset;
    } else offset = offsets[zone_index.?];
    if (year < 1970 or year > 2099 or day < 1 or day > monthDays(year, month) or hour > 23 or minute > 59 or second > 59) return range;
    var days: i64 = 0;
    var current: i64 = 1970;
    while (current < year) : (current += 1) days += yearDays(current);
    current = 1;
    while (current < month) : (current += 1) days += monthDays(year, current);
    days += day - 1;
    const seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60;
    if (seconds < 0) return range;
    if (weekday) |value| if (@mod(days + 3, 7) != h.n(value)) return .{ .error_text = "Date weekday mismatch" };
    return .{ .seconds = seconds };
}

pub fn formatUtc(seconds: i64) []const u8 {
    var days = @divTrunc(seconds, 86400);
    const rest = @mod(seconds, 86400);
    var year: i64 = 1970;
    var month: i64 = 1;
    while (days >= yearDays(year)) : (year += 1) days -= yearDays(year);
    while (days >= monthDays(year, month)) : (month += 1) days -= monthDays(year, month);
    return h.fmt("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ year, month, days + 1, @divTrunc(rest, 3600), @divTrunc(@mod(rest, 3600), 60), @mod(rest, 60) });
}
