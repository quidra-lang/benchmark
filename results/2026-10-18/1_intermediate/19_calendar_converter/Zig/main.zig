const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{ InvalidCommand, InvalidDate, OutOfRange } || Allocator.Error || std.Io.Writer.Error;
const DateError = error{ FORMAT, YEAR, MONTH, WEEK, DAY, FIELD, RANGE };
const max_fixed = 3652059;
const weekdays = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
const tz = [_][]const u8{ "Imix", "Ik", "Akbal", "Kan", "Chicchan", "Cimi", "Manik", "Lamat", "Muluc", "Oc", "Chuen", "Eb", "Ben", "Ix", "Men", "Cib", "Caban", "Etznab", "Cauac", "Ahau" };
const hb = [_][]const u8{ "Pop", "Uo", "Zip", "Zotz", "Tzec", "Xul", "Yaxkin", "Mol", "Chen", "Yax", "Zac", "Ceh", "Mac", "Kankin", "Muan", "Pax", "Kayab", "Cumku", "Uayeb" };
const decade = [_][]const u8{ "Primidi", "Duodi", "Tridi", "Quartidi", "Quintidi", "Sextidi", "Septidi", "Octidi", "Nonidi", "Decadi" };
const festivals = [_][]const u8{ "Vertu", "Genie", "Travail", "Opinion", "Recompenses", "Revolution" };

fn ix(n: i64) usize {
    return @intCast(n);
}
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn inRange(f: i64) bool {
    return f >= 1 and f <= max_fixed;
}
fn indexOf(list: []const []const u8, text: []const u8) ?i64 {
    for (list, 0..) |name, i| if (equal(name, text)) return @intCast(i);
    return null;
}
fn number(text: []const u8, digits: usize, signed: bool) ?i64 {
    const negative = signed and text.len > 0 and text[0] == '-';
    const body = text[@intFromBool(negative)..];
    if (body.len == 0 or body.len > digits) return null;
    for (body) |ch| if (!std.ascii.isDigit(ch)) return null;
    return std.fmt.parseInt(i64, text, 10) catch null;
}
fn yearNumber(text: []const u8) ?i64 {
    const y = number(text, 5, false) orelse return null;
    return if (y > 0) y else null;
}
fn integer(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}

const Date = struct { year: i64, month: i64, day: i64 };
const Molad = struct {
    day: i64,
    parts: i64,
    fixed: i64,
    first_rule: ?[]const u8,
    adu: bool,
};
fn molad(y: i64) Molad {
    const q = 5604 + 765433 * @divFloor(235 * y - 234, 19);
    const d = @divFloor(q, 25920);
    const t = @mod(q, 25920);
    const wd = @mod(d - 1373427, 7);
    var r = d;
    var rule: ?[]const u8 = null;
    if (t >= 19440) {
        r += 1;
        rule = "ZAKEN";
    } else if (!Calendar.HEBREW.leap(y) and wd == 2 and t >= 9924) {
        r += 2;
        rule = "GATARAD";
    } else if (Calendar.HEBREW.leap(y - 1) and wd == 1 and t >= 16789) {
        r += 1;
        rule = "BETUTAKPAT";
    }
    const rw = @mod(r - 1373427, 7);
    const adu = rw == 0 or rw == 3 or rw == 5;
    return .{ .day = d, .parts = t, .fixed = r + @intFromBool(adu) - 1373427, .first_rule = rule, .adu = adu };
}

const Calendar = enum {
    GREGORIAN,
    JULIAN,
    ISO,
    ISLAMIC,
    HEBREW,
    PERSIAN,
    COPTIC,
    ETHIOPIC,
    FRENCH,
    MAYAN,
    JD,
    FIXED,

    fn isYear(c: Calendar) bool {
        return @backingInt(c) <= @backingInt(Calendar.FRENCH);
    }
    fn isYmd(c: Calendar) bool {
        return c.isYear() and c != .ISO;
    }
    fn leap(c: Calendar, y: i64) bool {
        return switch (c) {
            .GREGORIAN => @mod(y, 4) == 0 and (@mod(y, 100) != 0 or @mod(y, 400) == 0),
            .JULIAN => @mod(y, 4) == 0,
            .ISO => c.start(y + 1) - c.start(y) == 371,
            .ISLAMIC => switch (@mod(y, 30)) {
                2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29 => true,
                else => false,
            },
            .HEBREW => @mod(7 * y + 1, 19) < 7,
            .PERSIAN => blk: {
                const b = @mod(y - 474, 2820) + 474;
                break :blk @mod((b + 38) * 682, 2816) < 682;
            },
            .COPTIC, .ETHIOPIC => @mod(y, 4) == 3,
            .FRENCH => @mod(y, 4) == 0 and @mod(y, 400) != 100 and @mod(y, 400) != 200 and @mod(y, 400) != 300 and @mod(y, 4000) != 0,
            else => unreachable,
        };
    }
    fn start(c: Calendar, y: i64) i64 {
        const p = y - 1;
        return switch (c) {
            .GREGORIAN => 365 * p + @divFloor(p, 4) - @divFloor(p, 100) + @divFloor(p, 400) + 1,
            .JULIAN => 365 * p + @divFloor(p, 4) - 1,
            .ISO => blk: {
                const jan4 = Calendar.GREGORIAN.start(y) + 3;
                break :blk jan4 - @mod(jan4 - 1, 7);
            },
            .ISLAMIC => 227015 + 354 * p + @divFloor(3 + 11 * y, 30),
            .HEBREW => molad(y).fixed,
            .PERSIAN => blk: {
                const a = y - 474;
                const b = @mod(a, 2820) + 474;
                break :blk 226896 + 1029983 * @divFloor(a, 2820) + 365 * (b - 1) + @divFloor(682 * b - 110, 2816);
            },
            .COPTIC => 103605 + 365 * p + @divFloor(y, 4),
            .ETHIOPIC => 2796 + 365 * p + @divFloor(y, 4),
            .FRENCH => 654415 + 365 * p + @divFloor(p, 4) - @divFloor(p, 100) + @divFloor(p, 400) - @divFloor(p, 4000),
            else => unreachable,
        };
    }
    fn names(c: Calendar, y: i64) []const []const u8 {
        return switch (c) {
            .GREGORIAN, .JULIAN => &.{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" },
            .ISLAMIC => &.{ "Muharram", "Safar", "RabiI", "RabiII", "JumadaI", "JumadaII", "Rajab", "Shaban", "Ramadan", "Shawwal", "DhuAlQidah", "DhuAlHijjah" },
            .HEBREW => if (c.leap(y)) &.{ "Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "AdarI", "AdarII", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul" } else &.{ "Tishri", "Heshvan", "Kislev", "Tevet", "Shevat", "Adar", "Nisan", "Iyyar", "Sivan", "Tammuz", "Av", "Elul" },
            .PERSIAN => &.{ "Farvardin", "Ordibehesht", "Khordad", "Tir", "Mordad", "Shahrivar", "Mehr", "Aban", "Azar", "Dey", "Bahman", "Esfand" },
            .COPTIC => &.{ "Thout", "Paopi", "Hathor", "Koiak", "Tobi", "Meshir", "Paremhat", "Parmouti", "Pashons", "Paoni", "Epip", "Mesori", "Nasie" },
            .ETHIOPIC => &.{ "Meskerem", "Tekemt", "Hedar", "Tahsas", "Ter", "Yekatit", "Megabit", "Miazia", "Genbot", "Sene", "Hamle", "Nehase", "Pagume" },
            .FRENCH => &.{ "Vendemiaire", "Brumaire", "Frimaire", "Nivose", "Pluviose", "Ventose", "Germinal", "Floreal", "Prairial", "Messidor", "Thermidor", "Fructidor", "Sansculottides" },
            else => unreachable,
        };
    }
    fn monthCount(c: Calendar, y: i64) i64 {
        return @intCast(c.names(y).len);
    }
    fn yearType(c: Calendar, y: i64) []const u8 {
        return switch (c.start(y + 1) - c.start(y)) {
            353, 383 => "DEFICIENT",
            354, 384 => "REGULAR",
            else => "COMPLETE",
        };
    }
    fn monthDays(c: Calendar, y: i64, m: i64) i64 {
        const extra: i64 = @intFromBool(c.leap(y));
        return switch (c) {
            .GREGORIAN, .JULIAN => if (m == 2) 28 + extra else if (m == 4 or m == 6 or m == 9 or m == 11) 30 else 31,
            .ISLAMIC => if (@mod(m, 2) == 1) 30 else if (m == 12) 29 + extra else 29,
            .PERSIAN => if (m <= 6) 31 else if (m <= 11) 30 else 29 + extra,
            .COPTIC, .ETHIOPIC, .FRENCH => if (m <= 12) 30 else 5 + extra,
            .HEBREW => blk: {
                const length = c.start(y + 1) - c.start(y);
                if (m == 2) break :blk if (@mod(length, 10) == 5) 30 else 29;
                if (m == 3) break :blk if (@mod(length, 10) == 3) 29 else 30;
                const common = [_]i64{ 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29 };
                const intercalary = [_]i64{ 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29 };
                break :blk if (extra == 1) intercalary[ix(m - 1)] else common[ix(m - 1)];
            },
            else => unreachable,
        };
    }
    fn fixed(c: Calendar, d: Date) i64 {
        if (c == .ISO) return c.start(d.year) + 7 * (d.month - 1) + d.day - 1;
        var f = c.start(d.year) + d.day - 1;
        var m: i64 = 1;
        while (m < d.month) : (m += 1) f += c.monthDays(d.year, m);
        return f;
    }
    fn yearOf(c: Calendar, f: i64) i64 {
        if (f < c.start(1)) return 0;
        var low: i64 = 1;
        var high: i64 = 100000;
        while (low + 1 < high) {
            const middle = @divFloor(low + high, 2);
            if (c.start(middle) <= f) low = middle else high = middle;
        }
        return low;
    }
    fn parts(c: Calendar, f: i64) ?Date {
        const y = c.yearOf(f);
        if (y == 0) return null;
        var offset = f - c.start(y);
        if (c == .ISO) return .{ .year = y, .month = @divFloor(offset, 7) + 1, .day = @mod(offset, 7) + 1 };
        var m: i64 = 1;
        while (offset >= c.monthDays(y, m)) : (m += 1) offset -= c.monthDays(y, m);
        return .{ .year = y, .month = m, .day = offset + 1 };
    }
    fn monthsBefore(c: Calendar, y: i64) i64 {
        return if (c == .HEBREW) @divFloor(235 * y - 234, 19) else c.monthCount(y) * (y - 1);
    }
    fn shift(c: Calendar, f: i64, years: i64, months: i64) ?i64 {
        const d = c.parts(f).?;
        const next_year = d.year + years;
        if (c == .ISO) {
            if (next_year < 1 or next_year > 99999) return null;
            const weeks = @divFloor(c.start(next_year + 1) - c.start(next_year), 7);
            return c.fixed(.{ .year = next_year, .month = @min(d.month, weeks), .day = d.day });
        }
        var m = d.month;
        if (c == .HEBREW) {
            var name = c.names(d.year)[ix(m - 1)];
            if (indexOf(c.names(next_year), name) == null) name = if (equal(name, "Adar")) "AdarII" else "Adar";
            m = indexOf(c.names(next_year), name).? + 1;
        }
        const absolute = c.monthsBefore(next_year) + m - 1 + months;
        var y: i64 = undefined;
        if (c == .HEBREW) {
            y = @divFloor(19 * absolute + 234, 235);
            while (c.monthsBefore(y) > absolute) y -= 1;
            while (c.monthsBefore(y + 1) <= absolute) y += 1;
        } else y = @divFloor(absolute, c.monthCount(next_year)) + 1;
        if (y < 1 or y > 99999) return null;
        m = absolute - c.monthsBefore(y) + 1;
        return c.fixed(.{ .year = y, .month = m, .day = @min(d.day, c.monthDays(y, m)) });
    }
};

fn parseDate(c: Calendar, text: []const u8) DateError!i64 {
    var f: i64 = undefined;
    if (c.isYear()) {
        var split = std.mem.splitScalar(u8, text, '-');
        const a = split.next() orelse return error.FORMAT;
        var b = split.next() orelse return error.FORMAT;
        const d = split.next() orelse return error.FORMAT;
        if (split.next() != null) return error.FORMAT;
        const y = number(a, 5, false) orelse return error.FORMAT;
        if (c == .ISO) {
            if (b.len == 0 or b[0] != 'W') return error.FORMAT;
            b = b[1..];
        }
        const m = number(b, 2, false) orelse return error.FORMAT;
        const day = number(d, if (c == .ISO) 1 else 2, false) orelse return error.FORMAT;
        if (y == 0) return error.YEAR;
        if (c == .ISO) {
            if (m < 1 or m > @divFloor(c.start(y + 1) - c.start(y), 7)) return error.WEEK;
            if (day < 1 or day > 7) return error.DAY;
        } else {
            if (m < 1 or m > c.monthCount(y)) return error.MONTH;
            if (day < 1 or day > c.monthDays(y, m)) return error.DAY;
        }
        f = c.fixed(.{ .year = y, .month = m, .day = day });
    } else if (c == .MAYAN) {
        var split = std.mem.splitScalar(u8, text, '.');
        var values: [5]i64 = undefined;
        for (&values) |*v| v.* = number(split.next() orelse return error.FORMAT, 2, false) orelse return error.FORMAT;
        if (split.next() != null) return error.FORMAT;
        if (values[1] > 19 or values[2] > 19 or values[3] > 17 or values[4] > 19) return error.FIELD;
        f = (((values[0] * 20 + values[1]) * 20 + values[2]) * 18 + values[3]) * 20 + values[4] - 1137142;
    } else {
        f = number(text, 8, true) orelse return error.FORMAT;
        if (c == .JD) f -= 1721425;
    }
    if (!inRange(f)) return error.RANGE;
    return f;
}
fn checkedDate(c: Calendar, text: []const u8) Error!i64 {
    return parseDate(c, text) catch |err| return if (err == error.RANGE) error.OutOfRange else error.InvalidDate;
}
fn writeDate(out: *std.Io.Writer, c: Calendar, f: i64) Error!void {
    if (!inRange(f)) return error.OutOfRange;
    if (c.isYear()) {
        const d = c.parts(f) orelse return error.OutOfRange;
        if (c == .ISO) try out.print("{d:0>4}-W{d:0>2}-{d}", .{ d.year, d.month, d.day }) else try out.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day });
    } else if (c == .MAYAN) {
        const count = f + 1137142;
        const h = @mod(count + 348, 365);
        try out.print("{d}.{d}.{d}.{d}.{d} {d} {s} {d} {s}", .{
            @divFloor(count, 144000), @mod(@divFloor(count, 7200), 20), @mod(@divFloor(count, 360), 20), @mod(@divFloor(count, 20), 18), @mod(count, 20),
            @mod(count + 3, 13) + 1,  tz[ix(@mod(count + 19, 20))],     @mod(h, 20),                     hb[ix(@divFloor(h, 20))],
        });
    } else try out.print("{d}", .{f + @as(i64, if (c == .JD) 1721425 else 0)});
}

const Easter = struct { epact: i64, letters: [2]u8, letter_count: usize, moon: i64, sunday: i64 };
fn easter(y: i64, c: Calendar) Easter {
    const g = @mod(y, 19);
    var e = @mod(14 + 11 * g, 30);
    if (c == .GREGORIAN) {
        const century = @divFloor(y, 100) + 1;
        e = @mod(14 + 11 * g - @divFloor(3 * century, 4) + @divFloor(5 + 8 * century, 25), 30);
        if (e == 0 or (e == 1 and g > 10)) e += 1;
    }
    const p = c.fixed(.{ .year = y, .month = 4, .day = 19 }) - e;
    const s = @mod(-c.start(y), 7);
    return .{ .epact = e, .letters = .{ "ABCDEFG"[ix(s)], "ABCDEFG"[ix(@mod(s - 1, 7))] }, .letter_count = if (c.leap(y)) 2 else 1, .moon = p, .sunday = p + 7 - @mod(p, 7) };
}
const Holiday = struct { name: []const u8, calendar: Calendar, month: []const u8, day: i64 };
const holidays = [_]Holiday{
    .{ .name = "Christmas", .calendar = .GREGORIAN, .month = "December", .day = 25 },
    .{ .name = "OrthodoxChristmas", .calendar = .JULIAN, .month = "December", .day = 25 },
    .{ .name = "RoshHashanah", .calendar = .HEBREW, .month = "Tishri", .day = 1 },
    .{ .name = "YomKippur", .calendar = .HEBREW, .month = "Tishri", .day = 10 },
    .{ .name = "Sukkot", .calendar = .HEBREW, .month = "Tishri", .day = 15 },
    .{ .name = "Hanukkah", .calendar = .HEBREW, .month = "Kislev", .day = 25 },
    .{ .name = "Purim", .calendar = .HEBREW, .month = "Adar", .day = 14 },
    .{ .name = "Passover", .calendar = .HEBREW, .month = "Nisan", .day = 15 },
    .{ .name = "Shavuot", .calendar = .HEBREW, .month = "Sivan", .day = 6 },
    .{ .name = "IslamicNewYear", .calendar = .ISLAMIC, .month = "Muharram", .day = 1 },
    .{ .name = "Ashura", .calendar = .ISLAMIC, .month = "Muharram", .day = 10 },
    .{ .name = "Mawlid", .calendar = .ISLAMIC, .month = "RabiI", .day = 12 },
    .{ .name = "RamadanStart", .calendar = .ISLAMIC, .month = "Ramadan", .day = 1 },
    .{ .name = "EidAlFitr", .calendar = .ISLAMIC, .month = "Shawwal", .day = 1 },
    .{ .name = "EidAlAdha", .calendar = .ISLAMIC, .month = "DhuAlHijjah", .day = 10 },
    .{ .name = "Nowruz", .calendar = .PERSIAN, .month = "Farvardin", .day = 1 },
    .{ .name = "SizdahBedar", .calendar = .PERSIAN, .month = "Farvardin", .day = 13 },
    .{ .name = "Yalda", .calendar = .PERSIAN, .month = "Azar", .day = 30 },
    .{ .name = "Nayrouz", .calendar = .COPTIC, .month = "Thout", .day = 1 },
    .{ .name = "CopticChristmas", .calendar = .COPTIC, .month = "Koiak", .day = 29 },
    .{ .name = "Enkutatash", .calendar = .ETHIOPIC, .month = "Meskerem", .day = 1 },
    .{ .name = "Meskel", .calendar = .ETHIOPIC, .month = "Meskerem", .day = 17 },
    .{ .name = "Timkat", .calendar = .ETHIOPIC, .month = "Ter", .day = 11 },
    .{ .name = "RepublicDay", .calendar = .FRENCH, .month = "Vendemiaire", .day = 1 },
    .{ .name = "RevolutionDay", .calendar = .FRENCH, .month = "Sansculottides", .day = 6 },
};
const Occurrence = struct {
    fixed: i64,
    order: usize,
    name: []const u8,
    calendar: Calendar,
    fn less(_: void, a: Occurrence, b: Occurrence) bool {
        return if (a.fixed == b.fixed) a.order < b.order else a.fixed < b.fixed;
    }
};
fn writeHolidays(gpa: Allocator, out: *std.Io.Writer, y: i64) Error!void {
    const first = Calendar.GREGORIAN.start(y);
    const last = Calendar.GREGORIAN.start(y + 1) - 1;
    const sunday = easter(y, .GREGORIAN).sunday;
    var entries: std.ArrayList(Occurrence) = .empty;
    const movable = [_][]const u8{ "AshWednesday", "GoodFriday", "Easter", "Ascension", "Pentecost" };
    for (movable, [_]i64{ -46, -2, 0, 39, 49 }, 0..) |name, offset, i| try entries.append(gpa, .{ .fixed = sunday + offset, .order = i, .name = name, .calendar = .GREGORIAN });
    try entries.append(gpa, .{ .fixed = easter(y, .JULIAN).sunday, .order = 5, .name = "OrthodoxEaster", .calendar = .JULIAN });
    for (holidays, 6..) |holiday, order| {
        const c = holiday.calendar;
        var candidate = @max(1, c.yearOf(first));
        while (c.start(candidate) <= last) : (candidate += 1) {
            const name = if (c == .HEBREW and equal(holiday.month, "Adar") and c.leap(candidate)) "AdarII" else holiday.month;
            const m = indexOf(c.names(candidate), name).? + 1;
            if (holiday.day > c.monthDays(candidate, m)) continue;
            const f = c.fixed(.{ .year = candidate, .month = m, .day = holiday.day });
            if (f >= first and f <= last) try entries.append(gpa, .{ .fixed = f, .order = order, .name = holiday.name, .calendar = c });
        }
    }
    std.mem.sort(Occurrence, entries.items, {}, Occurrence.less);
    for (entries.items) |entry| {
        try writeDate(out, .GREGORIAN, entry.fixed);
        try out.print(" {s} {s} {s} ", .{ weekdays[ix(@mod(entry.fixed, 7))], entry.name, @tagName(entry.calendar) });
        try writeDate(out, entry.calendar, entry.fixed);
        try out.writeAll("\n");
    }
}

const Command = enum { CONVERT, ALL, VALID, WEEKDAY, INFO, LEAP, MONTHS, MONTHCAL, NTH, NEWYEAR, DIFF, COUNT, ADD, SPAN, EASTER, COMPUTUS, PASSOVER, HOLIDAYS, MOLAD, ROUND };
const Unit = enum { DAYS, WEEKS, MONTHS, YEARS };
fn calendar(text: []const u8) ?Calendar {
    return std.meta.stringToEnum(Calendar, text);
}
fn validate(cmd: Command, a: []const []const u8) Error!void {
    const count: usize = switch (cmd) {
        .CONVERT, .DIFF, .COUNT, .ADD => 4,
        .MONTHCAL, .SPAN => 3,
        .NTH => 5,
        .PASSOVER, .HOLIDAYS, .MOLAD => 1,
        .ROUND => 6,
        else => 2,
    };
    if (a.len != count) return error.InvalidCommand;
    switch (cmd) {
        .EASTER, .COMPUTUS => {
            if (yearNumber(a[0]) == null or (!equal(a[1], "GREGORIAN") and !equal(a[1], "JULIAN"))) return error.InvalidCommand;
            return;
        },
        .PASSOVER, .HOLIDAYS, .MOLAD => {
            if (yearNumber(a[0]) == null) return error.InvalidCommand;
            return;
        },
        else => {},
    }
    const c = calendar(a[0]) orelse return error.InvalidCommand;
    switch (cmd) {
        .INFO, .MONTHS, .MONTHCAL, .NTH, .SPAN => if (!c.isYmd()) return error.InvalidCommand,
        .LEAP, .NEWYEAR => if (!c.isYear()) return error.InvalidCommand,
        else => {},
    }
    switch (cmd) {
        .CONVERT => if (!equal(a[2], "TO") or calendar(a[3]) == null) return error.InvalidCommand,
        .DIFF => if (calendar(a[2]) == null) return error.InvalidCommand,
        .LEAP, .MONTHS, .MONTHCAL, .NTH, .NEWYEAR => {
            if (yearNumber(a[1]) == null) return error.InvalidCommand;
            if (cmd == .MONTHCAL or cmd == .NTH) if (number(a[2], 2, false) == null) return error.InvalidCommand;
            if (cmd == .NTH) {
                if (indexOf(&.{ "1", "2", "3", "4", "5", "LAST" }, a[3]) == null or indexOf(&weekdays, a[4]) == null) return error.InvalidCommand;
            }
        },
        .COUNT => if (indexOf(&weekdays, a[3]) == null) return error.InvalidCommand,
        .ADD => {
            if (number(a[2], 7, true) == null) return error.InvalidCommand;
            const unit = std.meta.stringToEnum(Unit, a[3]) orelse return error.InvalidCommand;
            if ((unit == .MONTHS and !c.isYmd()) or (unit == .YEARS and !c.isYear())) return error.InvalidCommand;
        },
        .ROUND => {
            const n = number(a[2], 2, false) orelse return error.InvalidCommand;
            const d = number(a[4], 2, false) orelse return error.InvalidCommand;
            const month = indexOf(&hb, a[5]) orelse return error.InvalidCommand;
            if (n < 1 or n > 13 or indexOf(&tz, a[3]) == null or d > @as(i64, if (month == 18) 4 else 19)) return error.InvalidCommand;
        },
        else => {},
    }
}

fn writeMonth(out: *std.Io.Writer, c: Calendar, y: i64, m: i64, first: i64, last: i64) Error!void {
    if (!inRange(first) or !inRange(last)) return error.OutOfRange;
    try out.print("{s} {d} (", .{ c.names(y)[ix(m - 1)], y });
    try writeDate(out, .GREGORIAN, first);
    try out.writeAll(" to ");
    try writeDate(out, .GREGORIAN, last);
    try out.writeAll(")\nMo Tu We Th Fr Sa Su\n");
    var cursor = first - @mod(first - 1, 7);
    while (cursor <= last) : (cursor += 7) {
        var row: [20]u8 = @splat(' ');
        for (0..7) |i| {
            const f = cursor + @as(i64, @intCast(i));
            if (f < first or f > last) continue;
            const d = f - first + 1;
            if (d >= 10) row[i * 3] = '0' + @as(u8, @intCast(@divFloor(d, 10)));
            row[i * 3 + 1] = '0' + @as(u8, @intCast(@mod(d, 10)));
        }
        try out.print("{s}\n", .{std.mem.trimEnd(u8, &row, " ")});
    }
}
fn writeSpan(out: *std.Io.Writer, c: Calendar, f1: i64, f2: i64) Error!void {
    const first = @min(f1, f2);
    const last = @max(f1, f2);
    var low: i64 = 0;
    var high = c.parts(last).?.year - c.parts(first).?.year + 2;
    while (low + 1 < high) {
        const middle = @divFloor(low + high, 2);
        if ((c.shift(first, middle, 0) orelse max_fixed + 1) <= last) low = middle else high = middle;
    }
    var months: i64 = 0;
    while (true) {
        const shifted = c.shift(first, low, months + 1) orelse break;
        if (shifted > last) break;
        months += 1;
    }
    try out.print("{s}{d}y {d}m {d}d", .{ if (f1 > f2) "-" else "", low, months, last - c.shift(first, low, months).? });
}

fn execute(gpa: Allocator, out: *std.Io.Writer, words: []const []const u8) Error!void {
    const cmd = std.meta.stringToEnum(Command, words[0]) orelse return error.InvalidCommand;
    const a = words[1..];
    try validate(cmd, a);
    switch (cmd) {
        .EASTER, .COMPUTUS => {
            const y = integer(a[0]);
            if (y > 9999) return error.OutOfRange;
            const c = calendar(a[1]).?;
            const e = easter(y, c);
            if (cmd == .EASTER) try writeDate(out, .GREGORIAN, e.sunday) else {
                try out.print("golden={d} epact={d} letters={s} moon=", .{ @mod(y, 19) + 1, e.epact, e.letters[0..e.letter_count] });
                try writeDate(out, c, e.moon);
                try out.writeAll(" easter=");
                try writeDate(out, c, e.sunday);
            }
        },
        .PASSOVER, .HOLIDAYS, .MOLAD => {
            const y = integer(a[0]);
            if (cmd == .MOLAD) {
                const m = molad(y);
                if (!inRange(m.fixed)) return error.OutOfRange;
                try out.print("{s} {d}h {d}p ", .{ weekdays[ix(@mod(m.day - 1373427, 7))], @divFloor(m.parts, 1080), @mod(m.parts, 1080) });
                if (m.first_rule) |rule| try out.writeAll(rule);
                if (m.adu) try out.writeAll(if (m.first_rule == null) "ADU" else "+ADU");
                if (m.first_rule == null and !m.adu) try out.writeAll("NONE");
                try out.print(" {s} ", .{weekdays[ix(@mod(m.fixed, 7))]});
                try writeDate(out, .GREGORIAN, m.fixed);
            } else {
                if (y > 9999) return error.OutOfRange;
                if (cmd == .HOLIDAYS) return writeHolidays(gpa, out, y);
                const hy = y + 3760;
                const m = indexOf(Calendar.HEBREW.names(hy), "Nisan").? + 1;
                const f = Calendar.HEBREW.fixed(.{ .year = hy, .month = m, .day = 15 });
                try writeDate(out, .GREGORIAN, f);
                try out.print(" {s}", .{weekdays[ix(@mod(f, 7))]});
            }
        },
        .LEAP, .MONTHS, .MONTHCAL, .NTH, .NEWYEAR => {
            const c = calendar(a[0]).?;
            const y = integer(a[1]);
            switch (cmd) {
                .LEAP => {
                    try out.print("{s} {d}", .{ if (c.leap(y)) "YES" else "NO", c.start(y + 1) - c.start(y) });
                    if (c == .HEBREW) try out.print(" {s}", .{c.yearType(y)});
                },
                .MONTHS => for (c.names(y), 1..) |name, m| {
                    if (m > 1) try out.writeAll(" ");
                    try out.print("{s}={d}", .{ name, c.monthDays(y, @intCast(m)) });
                },
                .NEWYEAR => {
                    if (y > 9999) return error.OutOfRange;
                    const first = Calendar.GREGORIAN.start(y);
                    const last = Calendar.GREGORIAN.start(y + 1) - 1;
                    var candidate = @max(1, c.yearOf(first));
                    var any = false;
                    while (c.start(candidate) <= last) : (candidate += 1) {
                        const f = c.start(candidate);
                        if (f < first) continue;
                        if (any) try out.writeAll(" ");
                        try out.print("{d}:", .{candidate});
                        try writeDate(out, .GREGORIAN, f);
                        any = true;
                    }
                    if (!any) try out.writeAll("NONE");
                },
                .MONTHCAL, .NTH => {
                    const m = integer(a[2]);
                    if (m < 1 or m > c.monthCount(y)) return error.InvalidDate;
                    const first = c.fixed(.{ .year = y, .month = m, .day = 1 });
                    const last = first + c.monthDays(y, m) - 1;
                    if (cmd == .MONTHCAL) return writeMonth(out, c, y, m, first, last);
                    const wd = indexOf(&weekdays, a[4]).?;
                    const f = if (equal(a[3], "LAST")) last - @mod(last - wd, 7) else first + @mod(wd - first, 7) + 7 * (integer(a[3]) - 1);
                    if (f > last) try out.writeAll("NONE") else try writeDate(out, c, f);
                },
                else => unreachable,
            }
        },
        else => {
            const c = calendar(a[0]).?;
            if (cmd == .VALID) {
                const f = parseDate(c, a[1]) catch |err| {
                    try out.print("NO {s}\n", .{@errorName(err)});
                    return;
                };
                try out.writeAll("YES ");
                try writeDate(out, c, f);
                try out.writeAll("\n");
                return;
            }
            const f = try checkedDate(c, a[1]);
            switch (cmd) {
                .CONVERT => try writeDate(out, calendar(a[3]).?, f),
                .WEEKDAY => try out.writeAll(weekdays[ix(@mod(f, 7))]),
                .ALL => {
                    for (std.enums.values(Calendar)) |target| {
                        try out.print("{s} ", .{@tagName(target)});
                        if (target.isYmd() and target.parts(f) == null) {
                            try out.writeAll("OUT OF RANGE\n");
                            continue;
                        }
                        try writeDate(out, target, f);
                        if (target.isYmd()) {
                            const d = target.parts(f).?;
                            try out.print(" {s}", .{target.names(d.year)[ix(d.month - 1)]});
                        }
                        try out.writeAll("\n");
                    }
                    return;
                },
                .INFO => {
                    const d = c.parts(f).?;
                    const name = if (c != .FRENCH) weekdays[ix(@mod(f, 7))] else if (d.month <= 12) decade[ix(@mod(d.day - 1, 10))] else festivals[ix(d.day - 1)];
                    try out.print("{s} {d} {s} {d} day={d}/{d}", .{ name, d.day, c.names(d.year)[ix(d.month - 1)], d.year, f - c.start(d.year) + 1, c.start(d.year + 1) - c.start(d.year) });
                },
                .DIFF => try out.print("{d}", .{try checkedDate(calendar(a[2]).?, a[3]) - f}),
                .COUNT, .SPAN => {
                    const last = try checkedDate(c, a[2]);
                    if (cmd == .SPAN) try writeSpan(out, c, f, last) else {
                        const lo = @min(f, last);
                        const hi = @max(f, last);
                        const occurrence = lo + @mod(indexOf(&weekdays, a[3]).? - lo, 7);
                        try out.print("{d}", .{if (occurrence > hi) @as(i64, 0) else @divFloor(hi - occurrence, 7) + 1});
                    }
                },
                .ADD => {
                    const amount = integer(a[2]);
                    const unit = std.meta.stringToEnum(Unit, a[3]).?;
                    const result = switch (unit) {
                        .DAYS => f + amount,
                        .WEEKS => f + 7 * amount,
                        .YEARS => c.shift(f, amount, 0) orelse return error.OutOfRange,
                        .MONTHS => c.shift(f, 0, amount) orelse return error.OutOfRange,
                    };
                    try writeDate(out, c, result);
                },
                .ROUND => {
                    const num = integer(a[2]);
                    const tz_name = indexOf(&tz, a[3]).?;
                    const haab = 20 * indexOf(&hb, a[5]).? + integer(a[4]);
                    var candidate = f;
                    while (@mod(candidate + 1137142 + 3, 13) + 1 != num or @mod(candidate + 1137142 + 19, 20) != tz_name) candidate += 1;
                    while (candidate <= f + 18979) : (candidate += 260) {
                        if (@mod(candidate + 1137142 + 348, 365) == haab) {
                            try writeDate(out, c, candidate);
                            try out.writeAll("\n");
                            return;
                        }
                    }
                    try out.writeAll("NONE");
                },
                else => unreachable,
            }
        },
    }
    try out.writeAll("\n");
}

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = integer((try input.interface.takeDelimiter('\n')).?);
    var n: i64 = 0;
    while (n < count) : (n += 1) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const line = (try input.interface.takeDelimiter('\n')).?;
        var words: std.ArrayList([]const u8) = .empty;
        var split = std.mem.splitScalar(u8, line, ' ');
        while (split.next()) |word| try words.append(gpa, word);
        var result: std.Io.Writer.Allocating = .init(gpa);
        execute(gpa, &result.writer, words.items) catch |err| {
            const message = switch (err) {
                error.InvalidCommand => "INVALID COMMAND\n",
                error.InvalidDate => "INVALID DATE\n",
                error.OutOfRange => "OUT OF RANGE\n",
                else => return err,
            };
            try output.interface.writeAll(message);
            continue;
        };
        try output.interface.writeAll(result.written());
    }
    try output.interface.flush();
}
