const std = @import("std");

pub fn knots(v: i64) i64 {
    return @divFloor(v * 1944 + 500, 1000);
}

pub fn inHg(v: i64) i64 {
    return @divFloor(v * 2953 + 500, 1000);
}

pub fn hPa(v: i64) i64 {
    return @divFloor(v * 33864 + 50000, 100000);
}

pub fn sin(x: i64) i64 {
    const table = [_]i64 { 0, 174, 342, 500, 643, 766, 866, 940, 985, 1000 };
    const y = @mod(x, 360);
    const angle = if (y <= 90) y else if (y <= 180) 180 - y else if (y <= 270) y - 180 else 360 - y;
    return table[@intCast(@divFloor(angle, 10))] *(if (y <= 180) @as(i64, 1) else - 1);
}

pub fn cos(x: i64) i64 {
    return sin(x + 90);
}

pub fn days(year: i64, month: i64) i64 {
    return switch (month) {
        4, 6, 9, 11 => 30, 2 => if (@mod(year, 400) == 0 or (@mod(year, 4) == 0 and @mod(year, 100) != 0)) 29 else 28, else => 31
    };
}

pub fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

fn n(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}

pub const Period = struct {
    start: i64,
    end: i64
};

pub const Calendar = struct {
    year: i64,
    month: i64,
    pub fn stamp(c: Calendar, gpa: std.mem.Allocator, time: i64) ![]const u8 {
        var y = c.year;
        var m = c.month;
        var t = time;
        const size = days(y, m) * 1440;
        if (t >= size) {
            t -= size;
            m += 1;
            if (m == 13) {
                m = 1;
                y += 1;
            }
        }
        return std.fmt.allocPrint(gpa, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}Z", .{ y, m, @divFloor(t, 1440) + 1, @divFloor(@mod(t, 1440), 60), @mod(t, 60) });
    }
    pub fn observation(c: Calendar, text: []const u8) ?i64 {
        if (text.len != 7 or text[6] != 'Z' or !digits(text[0..6])) return null;
        const d = n(text[0..2]);
        const h = n(text[2..4]);
        const m = n(text[4..6]);
        if (d < 1 or d > days(c.year, c.month) or h > 23 or m > 59) return null;
        return ((d - 1) * 24 + h) * 60 + m;
    }
    pub fn dayTime(c: Calendar, day: i64, hour: i64, minute: i64, issue_day: i64) ?i64 {
        const next = day < issue_day;
        const month = if (c.month == 12) @as(i64, 1) else c.month + 1;
        const max = if (next) days(c.year +(if (c.month == 12) @as(i64, 1) else 0), month) else days(c.year, c.month);
        if (day < 1 or day > max) return null;
        return (if (next) days(c.year, c.month) * 1440 else @as(i64, 0)) +((day - 1) * 24 + hour) * 60 + minute;
    }
    pub fn period(c: Calendar, text: []const u8, issue_day: i64, limit: i64) ?Period {
        if (text.len != 9 or text[4] != '/' or !digits(text[0..4]) or !digits(text[5..9])) return null;
        const h1 = n(text[2..4]);
        const h2 = n(text[7..9]);
        if (h1 > 23 or h2 < 1 or h2 > 24) return null;
        const start = c.dayTime(n(text[0..2]), h1, 0, issue_day) orelse return null;
        const end = c.dayTime(n(text[5..7]), h2, 0, issue_day) orelse return null;
        if (start >= end or (limit > 0 and end > start + limit)) return null;
        return .{.start = start, .end = end };
    }
    pub fn change(c: Calendar, text: []const u8, issue_day: i64) ?i64 {
        if (text.len != 8 or !std.mem.startsWith(u8, text, "FM") or !digits(text[2..8])) return null;
        const h = n(text[4..6]);
        const m = n(text[6..8]);
        if (h > 23 or m > 59) return null;
        return c.dayTime(n(text[2..4]), h, m, issue_day);
    }
};

pub const Fraction = struct {
    p: i64,
    q: i64
};

pub fn miles(name: []const u8, a: i64, b: i64, c: i64) Fraction {
    return if (std.mem.eql(u8, name, "mile")).{.p = a * c + b, .q = c } else .{.p = 1000 * a, .q = 1609344 };
}

pub fn meters(name: []const u8, a: i64, b: i64, c: i64) i64 {
    const f = miles(name, a, b, c);
    return if (std.mem.eql(u8, name, "mile")) @divFloor(1609344 * f.p, 1000 * f.q) else a;
}

pub fn fraction(gpa: std.mem.Allocator, p: i64, q: i64) ![]const u8 {
    if (q == 0) return "undefined";
    var a = if (p < 0) - p else p;
    var b = q;
    while (b != 0) {
        const r = @mod(a, b);
        a = b;
        b = r;
    }
    return std.fmt.allocPrint(gpa, "{d}/{d}", .{ @divTrunc(p, a), @divTrunc(q, a) });
}
