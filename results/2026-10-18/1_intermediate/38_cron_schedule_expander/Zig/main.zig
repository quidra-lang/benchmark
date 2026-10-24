const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Command = enum { JOB, VALIDATE, REMOVE, RENAME, ENABLE, DISABLE, RUNTIME, LIST, EXPAND, DESCRIBE, MATCH, NEXT, PREV, COUNT, GAP, OVERLAP, TIMELINE, CONFLICTS, WEEK, CALENDAR, SIMULATE, EXCLUDE, INCLUDE, HOLIDAYS };
const Policy = enum { ALLOW, FORBID, REPLACE };
const weekdays = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
const months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
const field_names = [_][]const u8{ "minute", "hour", "day-of-month", "month", "day-of-week" };
const minimum = [_]usize{ 0, 0, 1, 1, 0 };
const maximum = [_]usize{ 59, 23, 31, 12, 7 };

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
fn integer(text: []const u8) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
fn digits(text: []const u8, low: usize, high: usize) bool {
    if (text.len < low or text.len > high) return false;
    for (text) |character| if (character < '0' or character > '9') return false;
    return true;
}
fn Text(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        bytes: [capacity]u8 = undefined,
        len: usize = 0,
        fn init(value: []const u8) Self {
            var result: Self = .{ .len = value.len };
            @memcpy(result.bytes[0..value.len], value);
            return result;
        }
        fn slice(value: *const Self) []const u8 { return value.bytes[0..value.len]; }
        pub fn format(value: Self, out: *Writer) Writer.Error!void { try out.writeAll(value.slice()); }
    };
}
fn leap(year: usize) bool { return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0); }
fn monthLength(year: usize, month: usize) usize {
    const lengths = [_]usize{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return if (month == 2 and leap(year)) 29 else lengths[month - 1];
}
const Date = struct {
    year: usize,
    month: usize,
    day: usize,
    fn number(date: Date) usize {
        var result = date.day - 1;
        for (2000..date.year) |year| result += if (leap(year)) 366 else 365;
        for (1..date.month) |month| result += monthLength(date.year, month);
        return result;
    }
    fn weekday(date: Date) usize { return (date.number() + 6) % 7; }
    fn fromNumber(value: usize) Date {
        var rest = value;
        var year: usize = 2000;
        while (rest >= @as(usize, if (leap(year)) 366 else 365)) : (year += 1) rest -= if (leap(year)) 366 else 365;
        var month: usize = 1;
        while (rest >= monthLength(year, month)) : (month += 1) rest -= monthLength(year, month);
        return .{ .year = year, .month = month, .day = rest + 1 };
    }
    fn parse(text: []const u8) ?Date {
        if (text.len != 10 or text[4] != '-' or text[7] != '-' or !digits(text[0..4], 4, 4) or !digits(text[5..7], 2, 2) or !digits(text[8..], 2, 2)) return null;
        const result: Date = .{ .year = integer(text[0..4]), .month = integer(text[5..7]), .day = integer(text[8..]) };
        if (result.year < 2001 or result.year > 2098 or result.month < 1 or result.month > 12 or result.day < 1 or result.day > monthLength(result.year, result.month)) return null;
        return result;
    }
    pub fn format(date: Date, out: *Writer) Writer.Error!void {
        try out.print("{d:0>4}-{d:0>2}-{d:0>2} {s}", .{ date.year, date.month, date.day, weekdays[date.weekday()][0..3] });
    }
};
const Datetime = struct {
    minute: usize,
    pub fn format(value: Datetime, out: *Writer) Writer.Error!void {
        const date = Date.fromNumber(value.minute / 1440);
        try out.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2} {s}", .{ date.year, date.month, date.day, value.minute % 1440 / 60, value.minute % 60, weekdays[date.weekday()][0..3] });
    }
};
fn datetime(minute: usize) Datetime { return .{ .minute = minute }; }
const Span = struct {
    minutes: usize,
    pub fn format(value: Span, out: *Writer) Writer.Error!void {
        try out.print("{d}d{d:0>2}h{d:0>2}m", .{ value.minutes / 1440, value.minutes % 1440 / 60, value.minutes % 60 });
    }
};
fn span(minutes: usize) Span { return .{ .minutes = minutes }; }
const Special = struct {
    kind: enum { last, last_weekday, before_last, nearest_weekday, nth_weekday, last_occurrence },
    value: usize = 0,
    occurrence: usize = 0,
    fn eql(a: Special, b: Special) bool { return a.kind == b.kind and a.value == b.value and a.occurrence == b.occurrence; }
    pub fn format(value: Special, out: *Writer) Writer.Error!void {
        switch (value.kind) {
            .last => try out.writeAll("L"),
            .last_weekday => try out.writeAll("LW"),
            .before_last => try out.print("L-{d}", .{value.value}),
            .nearest_weekday => try out.print("{d}W", .{value.value}),
            .nth_weekday => try out.print("{d}#{d}", .{ value.value, value.occurrence }),
            .last_occurrence => try out.print("{d}L", .{value.value}),
        }
    }
};
const Field = struct {
    values: [60]bool = @splat(false),
    specials: [50]Special = undefined,
    special_count: usize = 0,
    restricted: bool = false,
    fn count(field: *const Field) usize {
        var result: usize = 0;
        for (field.values) |present| result += @intFromBool(present);
        return result;
    }
    fn addSpecial(field: *Field, special: Special) void {
        for (field.specials[0..field.special_count]) |old| if (old.eql(special)) return;
        field.specials[field.special_count] = special;
        field.special_count += 1;
    }
    fn stepped(field: *const Field, index: usize) usize {
        if (!field.values[0] or field.count() < 2) return 0;
        var step: usize = 1;
        while (!field.values[step]) : (step += 1) {}
        if (step == 1) return 0;
        for (0..maximum[index] + 1) |value| if (field.values[value] != (value % step == 0)) return 0;
        return step;
    }
};
const DayMatch = struct { month_day: bool, week_day: bool, condition: bool };
const Cron = struct {
    fields: [5]Field,
    expanded: Text(100),
    daily: [1440]u16 = undefined,
    daily_count: usize = 0,
    fn orRule(cron: *const Cron) bool { return cron.fields[2].restricted and cron.fields[4].restricted; }
    fn rule(cron: *const Cron) []const u8 { return if (cron.orRule()) "OR" else "AND"; }
    fn nearest(date: Date, day: usize) usize {
        const weekday = (date.number() + 6 + day - date.day) % 7;
        return switch (weekday) {
            6 => if (day == 1) 3 else day - 1,
            0 => if (day == monthLength(date.year, date.month)) day - 2 else day + 1,
            else => day,
        };
    }
    fn matchDay(cron: *const Cron, date: Date) DayMatch {
        const last = monthLength(date.year, date.month);
        var month_day = cron.fields[2].values[date.day];
        var week_day = cron.fields[4].values[date.weekday()];
        for (cron.fields[2].specials[0..cron.fields[2].special_count]) |special| {
            const matches = switch (special.kind) {
                .last => date.day == last,
                .last_weekday => date.day == nearest(date, last),
                .before_last => special.value < last and date.day == last - special.value,
                .nearest_weekday => special.value <= last and date.day == nearest(date, special.value),
                else => unreachable,
            };
            month_day = month_day or matches;
        }
        for (cron.fields[4].specials[0..cron.fields[4].special_count]) |special| {
            const matches = date.weekday() == special.value and (if (special.kind == .nth_weekday) (date.day - 1) / 7 + 1 == special.occurrence else date.day + 7 > last);
            week_day = week_day or matches;
        }
        return .{ .month_day = month_day, .week_day = week_day, .condition = if (cron.orRule()) month_day or week_day else month_day and week_day };
    }
    fn scheduled(cron: *const Cron, date: Date) bool { return cron.fields[3].values[date.month] and cron.matchDay(date).condition; }
    fn fires(cron: *const Cron, minute: usize, holidays: *const [36526]bool) bool {
        return cron.fields[0].values[minute % 60] and cron.fields[1].values[minute % 1440 / 60] and !holidays[minute / 1440] and cron.scheduled(Date.fromNumber(minute / 1440));
    }
    fn iterator(cron: *const Cron, holidays: *const [36526]bool, low: usize, high: usize, reverse: bool) FireIterator {
        return .{ .cron = cron, .holidays = holidays, .low = low, .high = high, .first = @intCast(low / 1440), .last = @intCast(high / 1440), .day = @intCast(if (reverse) high / 1440 else low / 1440), .index = if (reverse) @as(i32, @intCast(cron.daily_count)) - 1 else 0, .reverse = reverse };
    }
};
const FireIterator = struct {
    cron: *const Cron,
    holidays: *const [36526]bool,
    low: usize,
    high: usize,
    first: i32,
    last: i32,
    day: i32,
    index: i32,
    reverse: bool,
    ready: bool = false,
    fn advance(iterator: *FireIterator) void {
        iterator.day += if (iterator.reverse) @as(i32, -1) else 1;
        iterator.index = if (iterator.reverse) @as(i32, @intCast(iterator.cron.daily_count)) - 1 else 0;
        iterator.ready = false;
    }
    fn next(iterator: *FireIterator) ?usize {
        while (iterator.day >= iterator.first and iterator.day <= iterator.last) {
            const day: usize = @intCast(iterator.day);
            if (!iterator.ready) {
                if (iterator.holidays[day] or !iterator.cron.scheduled(Date.fromNumber(day))) { iterator.advance(); continue; }
                iterator.ready = true;
            }
            while (iterator.index >= 0 and iterator.index < @as(i32, @intCast(iterator.cron.daily_count))) {
                const time = day * 1440 + iterator.cron.daily[@intCast(iterator.index)];
                iterator.index += if (iterator.reverse) @as(i32, -1) else 1;
                if (time >= iterator.low and time <= iterator.high) return time;
            }
            iterator.advance();
        }
        return null;
    }
};
const Job = struct { id: Text(16), cron: Cron, text: Text(100), enabled: bool = true, duration: usize = 1, policy: Policy = .ALLOW };
const OrderedJobs = struct {
    values: [40]*const Job = undefined,
    len: usize = 0,
    fn less(_: void, a: *const Job, b: *const Job) bool { return std.mem.order(u8, a.id.slice(), b.id.slice()) == .lt; }
};
const State = struct {
    jobs: [40]Job = undefined,
    job_count: usize = 0,
    holidays: [36526]bool = @splat(false),
    holiday_count: usize = 0,
    fn find(state: *State, id: []const u8) ?usize {
        for (state.jobs[0..state.job_count], 0..) |*job, index| if (equal(job.id.slice(), id)) return index;
        return null;
    }
    fn ordered(state: *const State, enabled_only: bool) OrderedJobs {
        var result: OrderedJobs = .{};
        for (state.jobs[0..state.job_count]) |*job| {
            if (enabled_only and !job.enabled) continue;
            result.values[result.len] = job;
            result.len += 1;
        }
        std.sort.heap(*const Job, result.values[0..result.len], {}, OrderedJobs.less);
        return result;
    }
};

const Session = struct {
    state: *State,
    gpa: Allocator,
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = try std.fmt.allocPrint(session.gpa, fmt, args);
        return error.Invalid;
    }
    fn fieldError(session: *Session, index: usize, reason: []const u8) Error { return session.fail("{s} {s}", .{ field_names[index], reason }); }
    fn readValue(session: *Session, text: []const u8, index: usize) Error!usize {
        const month_names = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
        const day_names = [_][]const u8{ "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };
        if (index == 3) {
            for (month_names, 1..) |name, value| if (equal(text, name)) return value;
        }
        if (index == 4) {
            for (day_names, 0..) |name, value| if (equal(text, name)) return value;
        }
        if (!digits(text, 1, 2)) return session.fieldError(index, "invalid value");
        const value = integer(text);
        if (value < minimum[index] or value > maximum[index]) return session.fieldError(index, "out of range");
        return value;
    }
    fn specialNumber(session: *Session, text: []const u8, index: usize, upper: usize, size: usize) Error!usize {
        if (!digits(text, 1, size)) return session.fieldError(index, "invalid value");
        const value = integer(text);
        if (value < 1 or value > upper) return session.fieldError(index, "out of range");
        return value;
    }
    fn readField(session: *Session, text: []const u8, index: usize) Error!Field {
        var result: Field = .{ .restricted = text[0] != '*' };
        var items = std.mem.splitScalar(u8, text, ',');
        while (items.next()) |item| {
            if (item.len == 0) return session.fieldError(index, "empty item");
            var special: ?Special = null;
            if (index == 2 and (item[0] == 'L' or item[item.len - 1] == 'W')) {
                if (equal(item, "L")) special = .{ .kind = .last }
                else if (equal(item, "LW")) special = .{ .kind = .last_weekday }
                else if (std.mem.startsWith(u8, item, "L-")) special = .{ .kind = .before_last, .value = try session.specialNumber(item[2..], index, 30, 2) }
                else if (item[item.len - 1] == 'W') special = .{ .kind = .nearest_weekday, .value = try session.specialNumber(item[0 .. item.len - 1], index, 31, 2) }
                else return session.fieldError(index, "invalid value");
            } else if (index == 4 and std.mem.findScalar(u8, item, '#') != null) {
                const hash = std.mem.findScalar(u8, item, '#').?;
                const weekday = try session.readValue(item[0..hash], index);
                const occurrence = try session.specialNumber(item[hash + 1 ..], index, 5, 1);
                special = .{ .kind = .nth_weekday, .value = weekday % 7, .occurrence = occurrence };
            } else if (index == 4 and item.len >= 2 and item[item.len - 1] == 'L') {
                special = .{ .kind = .last_occurrence, .value = (try session.readValue(item[0 .. item.len - 1], index)) % 7 };
            }
            if (special) |value| { result.addSpecial(value); continue; }
            const slash = std.mem.findScalar(u8, item, '/');
            const base = item[0 .. slash orelse item.len];
            var low: usize = undefined;
            var high: usize = undefined;
            if (equal(base, "*")) { low = minimum[index]; high = maximum[index]; }
            else if (std.mem.findScalar(u8, base, '-')) |dash| {
                low = try session.readValue(base[0..dash], index);
                high = try session.readValue(base[dash + 1 ..], index);
                if (low > high) return session.fieldError(index, "invalid range");
            } else { low = try session.readValue(base, index); high = if (slash == null) low else maximum[index]; }
            var step: usize = 1;
            if (slash) |position| {
                const part = item[position + 1 ..];
                if (!digits(part, 1, 2) or integer(part) == 0) return session.fieldError(index, "invalid step");
                step = integer(part);
            }
            var value = low;
            while (value <= high) : (value += step) result.values[if (index == 4) value % 7 else value] = true;
        }
        return result;
    }
    fn joinWords(session: *Session, words: []const []const u8) Error![]const u8 {
        var result: Writer.Allocating = .init(session.gpa);
        defer result.deinit();
        for (words, 0..) |word, index| {
            if (index != 0) try result.writer.writeByte(' ');
            try result.writer.writeAll(word);
        }
        return result.toOwnedSlice();
    }
    fn parseCron(session: *Session, input: []const []const u8) Error!Cron {
        var words = input;
        if (words.len == 1 and words[0][0] == '@') {
            const macro = words[0];
            words = if (equal(macro, "@yearly") or equal(macro, "@annually")) &.{ "0", "0", "1", "1", "*" }
            else if (equal(macro, "@monthly")) &.{ "0", "0", "1", "*", "*" }
            else if (equal(macro, "@weekly")) &.{ "0", "0", "*", "*", "0" }
            else if (equal(macro, "@daily") or equal(macro, "@midnight")) &.{ "0", "0", "*", "*", "*" }
            else if (equal(macro, "@hourly")) &.{ "0", "*", "*", "*", "*" }
            else return session.fail("unknown macro", .{});
        }
        if (words.len != 5) return session.fail("field count", .{});
        var result: Cron = .{ .fields = undefined, .expanded = Text(100).init(try session.joinWords(words)) };
        for (words, 0..) |word, index| result.fields[index] = try session.readField(word, index);
        for (0..24) |hour| {
            if (!result.fields[1].values[hour]) continue;
            for (0..60) |minute| {
                if (!result.fields[0].values[minute]) continue;
                result.daily[result.daily_count] = @intCast(hour * 60 + minute);
                result.daily_count += 1;
            }
        }
        return result;
    }
    fn readDate(session: *Session, text: []const u8) Error!Date {
        const date = Date.parse(text) orelse return session.fail("invalid date", .{});
        return date;
    }
    fn readMinute(session: *Session, date_text: []const u8, time: []const u8) Error!usize {
        const date = Date.parse(date_text) orelse return session.fail("invalid datetime", .{});
        if (time.len != 5 or time[2] != ':' or !digits(time[0..2], 2, 2) or !digits(time[3..], 2, 2)) return session.fail("invalid datetime", .{});
        const hour = integer(time[0..2]);
        const minute = integer(time[3..]);
        if (hour > 23 or minute > 59) return session.fail("invalid datetime", .{});
        return date.number() * 1440 + hour * 60 + minute;
    }
    fn readMonth(session: *Session, text: []const u8) Error!Date {
        if (text.len != 7 or text[4] != '-' or !digits(text[0..4], 4, 4) or !digits(text[5..], 2, 2)) return session.fail("invalid month", .{});
        const year = integer(text[0..4]);
        const month = integer(text[5..]);
        if (year < 2001 or year > 2098 or month < 1 or month > 12) return session.fail("invalid month", .{});
        return .{ .year = year, .month = month, .day = 1 };
    }
    fn checkWindow(session: *Session, low: usize, high: usize) Error!void {
        if (low > high) return session.fail("invalid window", .{});
        if (high - low > 44640) return session.fail("window too long", .{});
    }
    fn positive(session: *Session, text: []const u8, size: usize, upper: usize, reason: []const u8) Error!usize {
        if (!digits(text, 1, size) or text[0] == '0' or integer(text) > upper) return session.fail("{s}", .{reason});
        return integer(text);
    }
    fn newId(session: *Session, id: []const u8) Error!void {
        if (id.len == 0 or id.len > 16 or id[0] < 'a' or id[0] > 'z') return session.fail("invalid id", .{});
        for (id) |character| if (!(character >= 'a' and character <= 'z') and !(character >= '0' and character <= '9') and character != '_') return session.fail("invalid id", .{});
        if (session.state.find(id) != null) return session.fail("duplicate job", .{});
    }
    fn getJob(session: *Session, id: []const u8) Error!*Job {
        const index = session.state.find(id) orelse return session.fail("unknown job", .{});
        return &session.state.jobs[index];
    }
    fn listJoin(session: *Session, parts: []const []const u8, either: bool) Error![]const u8 {
        var result: Writer.Allocating = .init(session.gpa);
        defer result.deinit();
        for (parts, 0..) |part, index| {
            if (index != 0) try result.writer.writeAll(if (index + 1 == parts.len) (if (either) " or " else " and ") else ", ");
            try result.writer.writeAll(part);
        }
        return result.toOwnedSlice();
    }
    fn valueName(session: *Session, index: usize, value: usize) Error![]const u8 {
        return switch (index) { 3 => months[value - 1], 4 => weekdays[value], else => try std.fmt.allocPrint(session.gpa, "{d}", .{value}) };
    }
    fn valueList(session: *Session, field: *const Field, index: usize, either: bool) Error![]const u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        var start: usize = 0;
        while (start < 60) {
            if (!field.values[start]) { start += 1; continue; }
            var end = start;
            while (end + 1 < 60 and field.values[end + 1]) : (end += 1) {}
            if (end - start >= 2) try parts.append(session.gpa, try std.fmt.allocPrint(session.gpa, "{s} through {s}", .{ try session.valueName(index, start), try session.valueName(index, end) }))
            else for (start..end + 1) |value| try parts.append(session.gpa, try session.valueName(index, value));
            start = end + 1;
        }
        return session.listJoin(parts.items, either);
    }
    fn dayClause(session: *Session, cron: *const Cron, weekday: bool, either: bool) Error![]const u8 {
        const index: usize = if (weekday) 4 else 2;
        const field = &cron.fields[index];
        var parts: std.ArrayList([]const u8) = .empty;
        if (field.count() != 0) {
            const values = try session.valueList(field, index, either);
            try parts.append(session.gpa, if (weekday) values else try std.fmt.allocPrint(session.gpa, "{s} {s}", .{ if (field.count() == 1) "day" else "days", values }));
        }
        const ordinals = [_][]const u8{ "1st", "2nd", "3rd", "4th", "5th" };
        for (field.specials[0..field.special_count]) |special| {
            const part: []const u8 = switch (special.kind) {
                .last => "the last day",
                .last_weekday => "the last weekday",
                .before_last => try std.fmt.allocPrint(session.gpa, "{d} {s} before the last day", .{ special.value, if (special.value == 1) "day" else "days" }),
                .nearest_weekday => try std.fmt.allocPrint(session.gpa, "the weekday nearest day {d}", .{special.value}),
                .nth_weekday => try std.fmt.allocPrint(session.gpa, "the {s} {s}", .{ ordinals[special.occurrence - 1], weekdays[special.value] }),
                .last_occurrence => try std.fmt.allocPrint(session.gpa, "the last {s}", .{weekdays[special.value]}),
            };
            try parts.append(session.gpa, part);
        }
        return std.fmt.allocPrint(session.gpa, "{s}{s}", .{ try session.listJoin(parts.items, either), if (!weekday or field.special_count != 0) " of the month" else "" });
    }
    fn describe(session: *Session, cron: *const Cron) Error!void {
        const out = session.out;
        const minute = &cron.fields[0];
        const hour = &cron.fields[1];
        if (cron.daily_count <= 4) {
            try out.writeAll("At ");
            for (cron.daily[0..cron.daily_count], 0..) |time, index| {
                if (index != 0) try out.writeAll(if (index + 1 == cron.daily_count) " and " else ", ");
                try out.print("{d:0>2}:{d:0>2}", .{ time / 60, time % 60 });
            }
        } else {
            const minute_step = minute.stepped(0);
            if (minute.count() == 60) try out.writeAll("Every minute")
            else if (minute_step != 0) try out.print("Every {d} minutes", .{minute_step})
            else try out.print("At {s} {s}", .{ if (minute.count() == 1) "minute" else "minutes", try session.valueList(minute, 0, false) });
            if (hour.count() == 24) {
                if (minute.count() != 60 and minute_step == 0) try out.writeAll(" of every hour");
            } else if (hour.stepped(1) != 0) try out.print(", every {d} hours", .{hour.stepped(1)})
            else {
                var first: usize = 0;
                while (!hour.values[first]) : (first += 1) {}
                var last: usize = 23;
                while (!hour.values[last]) : (last -= 1) {}
                if (last - first + 1 == hour.count()) try out.print(", between {d:0>2}:00 and {d:0>2}:59", .{ first, last })
                else try out.print(", during hours {s}", .{try session.valueList(hour, 1, false)});
            }
        }
        const month_full = cron.fields[2].count() == 31;
        const week_full = cron.fields[4].count() == 7;
        if (cron.orRule()) {
            if (!month_full and !week_full) try out.print(", on {s} or on {s}", .{ try session.dayClause(cron, false, false), try session.dayClause(cron, true, false) });
        } else if (!month_full and !week_full) try out.print(", on {s} if it is {s}", .{ try session.dayClause(cron, false, false), try session.dayClause(cron, true, true) })
        else if (!month_full) try out.print(", on {s}", .{try session.dayClause(cron, false, false)})
        else if (!week_full) try out.print(", on {s}", .{try session.dayClause(cron, true, false)});
        if (cron.fields[3].count() != 12) try out.print(", in {s}", .{try session.valueList(&cron.fields[3], 3, false)});
        try out.writeByte('\n');
    }
    fn timeline(session: *Session, low: usize, high: usize, conflicts: bool) Error!void {
        const jobs = session.state.ordered(true);
        const masks = try session.gpa.alloc(u64, high - low + 1);
        @memset(masks, 0);
        for (jobs.values[0..jobs.len], 0..) |job, index| {
            var times = job.cron.iterator(&session.state.holidays, low, high, false);
            while (times.next()) |time| masks[time - low] |= @as(u64, 1) << @as(u6, @intCast(index));
        }
        var count: usize = 0;
        var peak: usize = 0;
        for (masks) |mask| {
            const size = @popCount(mask);
            if (conflicts) {
                if (size < 2) continue;
                count += 1;
                peak = @max(peak, size);
            } else count += size;
        }
        if (conflicts) try line(session.out, "CONFLICTS {d} peak {d}", .{ count, peak })
        else try line(session.out, "TIMELINE {d}", .{count});
        var written: usize = 0;
        for (masks, 0..) |mask, offset| {
            if (written == 100) break;
            const size = @popCount(mask);
            if (size == 0 or (conflicts and size < 2)) continue;
            if (conflicts) try session.out.print("{f} {d}", .{ datetime(low + offset), size });
            for (jobs.values[0..jobs.len], 0..) |job, index| {
                if ((mask & (@as(u64, 1) << @as(u6, @intCast(index)))) == 0) continue;
                if (conflicts) try session.out.print(" {f}", .{job.id})
                else {
                    try line(session.out, "{f} {f}", .{ datetime(low + offset), job.id });
                    written += 1;
                    if (written == 100) break;
                }
            }
            if (conflicts) { try session.out.writeByte('\n'); written += 1; }
        }
        if (count > 100) try line(session.out, "... {d} more", .{count - 100});
    }
    fn week(session: *Session, input: []const u8, date: Date) Error!void {
        var counts: [7][24]usize = @splat(@splat(0));
        const low = date.number() * 1440;
        var total: usize = 0;
        for (session.state.jobs[0..session.state.job_count]) |*job| {
            if (!job.enabled) continue;
            var times = job.cron.iterator(&session.state.holidays, low, low + 7 * 1440 - 1, false);
            while (times.next()) |time| { counts[(time - low) / 1440][time % 1440 / 60] += 1; total += 1; }
        }
        try line(session.out, "WEEK {s} {d}", .{ input, total });
        for (counts, 0..) |hours, day| {
            var marks: [24]u8 = undefined;
            var subtotal: usize = 0;
            for (hours, 0..) |count, hour| {
                subtotal += count;
                marks[hour] = if (count == 0) '.' else if (count >= 10) '+' else '0' + @as(u8, @intCast(count));
            }
            try line(session.out, "{f} {s} {d}", .{ Date.fromNumber(date.number() + day), &marks, subtotal });
        }
    }
    fn calendar(session: *Session, job: *const Job, input: []const u8, first: Date) Error!void {
        var cells: [42][3]u8 = @splat(.{ '.', '.', '.' });
        const padding = first.weekday();
        const length = monthLength(first.year, first.month);
        var count: usize = 0;
        for (1..length + 1) |day| {
            const date: Date = .{ .year = first.year, .month = first.month, .day = day };
            const mark: u8 = if (!job.cron.scheduled(date)) '-' else if (session.state.holidays[date.number()]) 'x' else '*';
            count += @intFromBool(mark == '*');
            cells[padding + day - 1] = .{ '0' + @as(u8, @intCast(day / 10)), '0' + @as(u8, @intCast(day % 10)), mark };
        }
        try line(session.out, "CALENDAR {f} {s} days {d} runs {d}", .{ job.id, input, count, count * job.cron.daily_count });
        try line(session.out, "Sun Mon Tue Wed Thu Fri Sat", .{});
        const end = (padding + length + 6) / 7 * 7;
        for (cells[0..end], 0..) |cell, index| {
            if (index % 7 != 0) try session.out.writeByte(' ');
            try session.out.writeAll(&cell);
            if (index % 7 == 6) try session.out.writeByte('\n');
        }
    }
    fn simulate(session: *Session, low: usize, high: usize) Error!void {
        const jobs = session.state.ordered(true);
        const Stats = struct { started: usize = 0, skipped: usize = 0, replaced: usize = 0, busy: usize = 0 };
        var stats: [40]Stats = @splat(.{});
        const events = try session.gpa.alloc(i32, high - low + 1441);
        @memset(events, 0);
        for (jobs.values[0..jobs.len], 0..) |job, index| {
            var times = job.cron.iterator(&session.state.holidays, low, high, false);
            var last_end: usize = 0;
            while (times.next()) |time| {
                if (last_end > time) {
                    if (job.policy == .FORBID) { stats[index].skipped += 1; continue; }
                    if (job.policy == .REPLACE) {
                        events[last_end - low] += 1;
                        events[time - low] -= 1;
                        stats[index].busy -= last_end - time;
                        stats[index].replaced += 1;
                    }
                }
                last_end = time + job.duration;
                events[time - low] += 1;
                events[last_end - low] -= 1;
                stats[index].started += 1;
                stats[index].busy += job.duration;
            }
        }
        var running: i32 = 0;
        var peak: i32 = 0;
        var at: usize = 0;
        for (events, 0..) |delta, offset| {
            running += delta;
            if (running > peak) { peak = running; at = low + offset; }
        }
        try session.out.print("SIMULATE {d} peak {d}", .{ jobs.len, peak });
        if (peak != 0) try session.out.print(" at {f}", .{datetime(at)});
        try session.out.writeByte('\n');
        for (jobs.values[0..jobs.len], stats[0..jobs.len]) |job, result| {
            try line(session.out, "{f} {s} started {d} skipped {d} replaced {d} busy {d}", .{ job.id, @tagName(job.policy), result.started, result.skipped, result.replaced, result.busy });
        }
    }
    fn execute(session: *Session, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]) orelse return session.fail("unknown command", .{});
        const arity: i8 = switch (command) {
            .JOB => -2, .VALIDATE => -1,
            .LIST, .HOLIDAYS => 0,
            .REMOVE, .ENABLE, .DISABLE, .DESCRIBE, .WEEK, .EXCLUDE, .INCLUDE => 1,
            .RENAME, .EXPAND, .CALENDAR => 2,
            .RUNTIME, .MATCH, .GAP => 3,
            .NEXT, .PREV, .TIMELINE, .CONFLICTS, .SIMULATE => 4,
            .COUNT => 5, .OVERLAP => 6,
        };
        const count = words.len - 1;
        if (if (arity < 0) count < @as(usize, @intCast(-arity)) else count != @as(usize, @intCast(arity))) return session.fail("wrong arguments", .{});
        const out = session.out;
        const state = session.state;
        switch (command) {
            .JOB => {
                try session.newId(words[1]);
                const cron = try session.parseCron(words[2..]);
                const text = Text(100).init(try session.joinWords(words[2..]));
                state.jobs[state.job_count] = .{ .id = Text(16).init(words[1]), .cron = cron, .text = text };
                state.job_count += 1;
                try line(out, "JOB {s} added", .{words[1]});
            },
            .VALIDATE => {
                const cron = try session.parseCron(words[1..]);
                try line(out, "VALID {f} {s} {d}", .{ cron.expanded, cron.rule(), cron.daily_count });
            },
            .REMOVE => {
                const index = state.find(words[1]) orelse return session.fail("unknown job", .{});
                for (index..state.job_count - 1) |position| state.jobs[position] = state.jobs[position + 1];
                state.job_count -= 1;
                try line(out, "REMOVE {s}", .{words[1]});
            },
            .RENAME => {
                const job = try session.getJob(words[1]);
                try session.newId(words[2]);
                job.id = Text(16).init(words[2]);
                try line(out, "RENAME {s} {s}", .{ words[1], words[2] });
            },
            .ENABLE, .DISABLE => {
                const job = try session.getJob(words[1]);
                const enabled = command == .ENABLE;
                if (job.enabled == enabled) return session.fail("already {s}", .{if (enabled) "enabled" else "disabled"});
                job.enabled = enabled;
                try line(out, "{s} {f}", .{ @tagName(command), job.id });
            },
            .RUNTIME => {
                const job = try session.getJob(words[1]);
                const duration = try session.positive(words[2], 4, 1440, "invalid duration");
                const policy = std.meta.stringToEnum(Policy, words[3]) orelse return session.fail("invalid policy", .{});
                job.duration = duration;
                job.policy = policy;
                try line(out, "RUNTIME {f} {d} {s}", .{ job.id, duration, @tagName(policy) });
            },
            .LIST => {
                const jobs = state.ordered(false);
                try line(out, "LIST {d}", .{jobs.len});
                for (jobs.values[0..jobs.len]) |job| try line(out, "{f} {s} {d} {s} {f}", .{ job.id, if (job.enabled) "on" else "off", job.duration, @tagName(job.policy), job.text });
            },
            .EXPAND => {
                const job = try session.getJob(words[1]);
                var selected: ?usize = null;
                for (field_names, 0..) |name, index| if (equal(name, words[2])) { selected = index; break; };
                const index = selected orelse return session.fail("invalid field", .{});
                const field = &job.cron.fields[index];
                try out.print("EXPAND {f} {s} {d}", .{ job.id, words[2], field.count() });
                for (field.values, 0..) |present, value| if (present) try out.print(" {d}", .{value});
                for (field.specials[0..field.special_count]) |special| try out.print(" {f}", .{special});
                try out.writeByte('\n');
            },
            .DESCRIBE => {
                const job = try session.getJob(words[1]);
                try out.print("DESCRIBE {f} ", .{job.id});
                try session.describe(&job.cron);
            },
            .MATCH => {
                const job = try session.getJob(words[1]);
                const time = try session.readMinute(words[2], words[3]);
                const date = Date.fromNumber(time / 1440);
                const matched = job.cron.matchDay(date);
                const reasons = [_]bool{ !job.cron.fields[0].values[time % 60], !job.cron.fields[1].values[time % 1440 / 60], !matched.condition and !matched.month_day, !job.cron.fields[3].values[date.month], !matched.condition and !matched.week_day, state.holidays[date.number()] };
                const labels = field_names ++ [_][]const u8{"excluded"};
                var yes = true;
                for (reasons) |reason| if (reason) { yes = false; break; };
                try out.print("MATCH {f} {f} {s}", .{ job.id, datetime(time), if (yes) "yes" else "no" });
                for (reasons, labels) |reason, label| if (reason) try out.print(" {s}", .{label});
                try out.writeByte('\n');
            },
            .NEXT, .PREV => {
                const job = try session.getJob(words[1]);
                const start = try session.readMinute(words[2], words[3]);
                const limit = try session.positive(words[4], 2, 50, "invalid count");
                const reverse = command == .PREV;
                var iterator = job.cron.iterator(&state.holidays, if (reverse) start - 527040 else start + 1, if (reverse) start - 1 else start + 527040, reverse);
                var times: [50]usize = undefined;
                var found: usize = 0;
                while (found < limit) {
                    times[found] = iterator.next() orelse break;
                    found += 1;
                }
                try line(out, "{s} {f} {d}", .{ @tagName(command), job.id, found });
                for (times[0..found]) |time| try line(out, "{f} {s}{f}", .{ datetime(time), if (reverse) "-" else "+", span(if (reverse) start - time else time - start) });
                if (found < limit) try line(out, "NONE", .{});
            },
            .COUNT => {
                const job = try session.getJob(words[1]);
                const low = try session.readMinute(words[2], words[3]);
                const high = try session.readMinute(words[4], words[5]);
                try session.checkWindow(low, high);
                var times = job.cron.iterator(&state.holidays, low, high, false);
                var runs: usize = 0;
                var days: usize = 0;
                var previous: ?usize = null;
                while (times.next()) |time| {
                    const day = time / 1440;
                    runs += 1;
                    if (previous == null or previous.? != day) days += 1;
                    previous = day;
                }
                try line(out, "COUNT {f} runs {d} days {d}", .{ job.id, runs, days });
            },
            .GAP => {
                const job = try session.getJob(words[1]);
                const start = try session.readMinute(words[2], words[3]);
                var times = job.cron.iterator(&state.holidays, start, start + 44640, false);
                const frequencies = try session.gpa.alloc(usize, 44641);
                @memset(frequencies, 0);
                var previous: ?usize = null;
                var runs: usize = 0;
                var shortest: usize = 44641;
                var longest: usize = 0;
                var from: usize = 0;
                var to: usize = 0;
                while (times.next()) |time| {
                    runs += 1;
                    if (previous) |old| {
                        const gap = time - old;
                        frequencies[gap] += 1;
                        shortest = @min(shortest, gap);
                        if (gap > longest) { longest = gap; from = old; to = time; }
                    }
                    previous = time;
                }
                if (runs < 2) return line(out, "GAP {f} runs {d} none", .{ job.id, runs });
                try line(out, "GAP {f} runs {d} shortest {f} longest {f} from {f} to {f}", .{ job.id, runs, span(shortest), span(longest), datetime(from), datetime(to) });
                for (frequencies, 0..) |frequency, gap| if (frequency != 0) try line(out, "{f} {d}", .{ span(gap), frequency });
            },
            .OVERLAP => {
                const first = try session.getJob(words[1]);
                const second = try session.getJob(words[2]);
                const low = try session.readMinute(words[3], words[4]);
                const high = try session.readMinute(words[5], words[6]);
                try session.checkWindow(low, high);
                var times = first.cron.iterator(&state.holidays, low, high, false);
                var common: usize = 0;
                var earliest: usize = 0;
                var latest: usize = 0;
                while (times.next()) |time| {
                    if (!second.cron.fires(time, &state.holidays)) continue;
                    if (common == 0) earliest = time;
                    latest = time;
                    common += 1;
                }
                try out.print("OVERLAP {f} {f} {d}", .{ first.id, second.id, common });
                if (common != 0) try out.print(" first {f} last {f}", .{ datetime(earliest), datetime(latest) });
                try out.writeByte('\n');
            },
            .TIMELINE, .CONFLICTS, .SIMULATE => {
                const low = try session.readMinute(words[1], words[2]);
                const high = try session.readMinute(words[3], words[4]);
                try session.checkWindow(low, high);
                if (command == .SIMULATE) try session.simulate(low, high) else try session.timeline(low, high, command == .CONFLICTS);
            },
            .WEEK => {
                const date = try session.readDate(words[1]);
                try session.week(words[1], date);
            },
            .CALENDAR => {
                const job = try session.getJob(words[1]);
                const first = try session.readMonth(words[2]);
                try session.calendar(job, words[2], first);
            },
            .EXCLUDE, .INCLUDE => {
                const date = try session.readDate(words[1]);
                const day = date.number();
                if (command == .EXCLUDE) {
                    if (state.holidays[day]) return session.fail("already excluded", .{});
                    state.holidays[day] = true;
                    state.holiday_count += 1;
                } else {
                    if (!state.holidays[day]) return session.fail("not excluded", .{});
                    state.holidays[day] = false;
                    state.holiday_count -= 1;
                }
                try line(out, "{s} {f} holidays {d}", .{ @tagName(command), date, state.holiday_count });
            },
            .HOLIDAYS => {
                try line(out, "HOLIDAYS {d}", .{state.holiday_count});
                for (state.holidays, 0..) |present, day| if (present) try line(out, "{f}", .{Date.fromNumber(day)});
            },
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var header = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer header.deinit();
    var state: State = .{};
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = integer(try readLine(header.allocator(), &input.interface));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var words: std.ArrayList([]const u8) = .empty;
        var tokens = std.mem.tokenizeScalar(u8, text, ' ');
        while (tokens.next()) |word| try words.append(gpa, word);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .state = &state, .gpa = gpa, .out = &response.writer };
        session.execute(words.items) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            try output.interface.flush();
            continue;
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
