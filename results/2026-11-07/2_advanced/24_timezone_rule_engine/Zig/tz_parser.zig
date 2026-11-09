const std = @import("std");
const d = @import("day_rules.zig");
const r = @import("report.zig");
pub const FieldError = error{ Syntax, BadYear, BadMonth, BadDay, BadTime, BadSave, BadOffset, BadLetter, BadFormat };
pub fn errorText(value: FieldError) []const u8 {
    return switch (value) { error.Syntax => "syntax error", error.BadYear => "bad year", error.BadMonth => "bad month", error.BadDay => "bad day spec", error.BadTime => "bad time", error.BadSave => "bad save", error.BadOffset => "bad offset", error.BadLetter => "bad letter", error.BadFormat => "bad format" };
}
pub fn lineContent(raw: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, raw, '#') orelse raw.len;
    return std.mem.trimEnd(u8, raw[0..end], " ");
}
pub fn digits(text: []const u8, minimum: usize, maximum: usize) bool {
    if (text.len < minimum or text.len > maximum) return false;
    for (text) |character| if (character < '0' or character > '9') return false;
    return true;
}
fn hmsValue(text: []const u8, max_parts: usize) ?i64 {
    var iterator = std.mem.splitScalar(u8, text, ':');
    const first = iterator.next().?;
    if (!digits(first, 1, 2)) return null;
    var value = r.number(first) * 3600;
    var count: usize = 1;
    while (iterator.next()) |part| {
        count += 1;
        if (count > max_parts or !digits(part, 2, 2) or r.number(part) > 59) return null;
        value += r.number(part) * (if (count == 2) @as(i64, 60) else 1);
    }
    return value;
}
pub fn parseYear(text: []const u8) FieldError!i64 {
    if (!digits(text, 4, 4)) return error.BadYear;
    const year = r.number(text);
    if (year < 1800 or year > 2099) return error.BadYear;
    return year;
}
pub fn parseTo(text: []const u8, from: i64) FieldError!i64 {
    if (r.eq(text, "only")) return from;
    if (r.eq(text, "max")) return 2099;
    const year = try parseYear(text);
    if (year < from) return error.BadYear;
    return year;
}
pub fn parseMonth(text: []const u8) FieldError!i64 {
    for (d.month_names, 1..) |name, i| if (r.eq(name, text)) return r.n(i);
    return error.BadMonth;
}
fn parseWeekday(text: []const u8) FieldError!i64 {
    for (d.weekday_names, 0..) |name, i| if (r.eq(name, text)) return r.n(i);
    return error.BadDay;
}
fn dayOfMonth(text: []const u8, month: i64) FieldError!i64 {
    if (!digits(text, 1, 2) or text[0] == '0') return error.BadDay;
    const day = r.number(text);
    if (day > d.daysInMonth(2001, month)) return error.BadDay;
    return day;
}
pub fn parseDaySpec(text: []const u8, month: i64) FieldError!d.DaySpec {
    if (std.mem.startsWith(u8, text, "last")) return .{ .kind = .last, .weekday = try parseWeekday(text[4..]) };
    if (std.mem.indexOf(u8, text, ">=")) |position| return .{ .kind = .after, .weekday = try parseWeekday(text[0..position]), .day = try dayOfMonth(text[position + 2 ..], month) };
    if (std.mem.indexOf(u8, text, "<=")) |position| return .{ .kind = .before, .weekday = try parseWeekday(text[0..position]), .day = try dayOfMonth(text[position + 2 ..], month) };
    return .{ .day = try dayOfMonth(text, month) };
}
pub const Clock = struct { value: i64, kind: u8 };
pub fn parseTime(source: []const u8) FieldError!Clock {
    var text = source;
    var kind: u8 = 'w';
    if (text.len > 0 and std.mem.indexOfScalar(u8, "wsu", text[text.len - 1]) != null) { kind = text[text.len - 1]; text = text[0 .. text.len - 1]; }
    const value = hmsValue(text, 3) orelse return error.BadTime;
    if (value > 86400) return error.BadTime;
    return .{ .value = value, .kind = kind };
}
pub fn parseSave(text: []const u8) FieldError!i64 {
    const value = hmsValue(text, 2) orelse return error.BadSave;
    if (value > 7200) return error.BadSave;
    return value;
}
pub fn parseLetter(text: []const u8) FieldError![]const u8 {
    if (r.eq(text, "-")) return "";
    if (text.len == 0 or text.len > 5) return error.BadLetter;
    for (text) |character| if (character < 'A' or character > 'Z') return error.BadLetter;
    return text;
}
pub fn parseOffset(text: []const u8) FieldError!i64 {
    const negative = text.len > 0 and text[0] == '-';
    const value = hmsValue(if (negative) text[1..] else text, 3) orelse return error.BadOffset;
    if (value >= 57600) return error.BadOffset;
    return if (negative) -value else value;
}
pub fn checkFormat(text: []const u8, rule_set: bool) FieldError!void {
    var placeholders: usize = 0;
    var slashes: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '%') {
            if (i + 1 == text.len or text[i + 1] != 's') return error.BadFormat;
            placeholders += 1;
            i += 1;
        } else if (c == '/') {
            if (i == 0 or i + 1 == text.len) return error.BadFormat;
            slashes += 1;
        } else if (!((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '+' or c == '-')) return error.BadFormat;
    }
    if (placeholders > 1 or slashes > 1 or (placeholders > 0 and slashes > 0) or (!rule_set and placeholders > 0)) return error.BadFormat;
}
pub const Until = struct { year_text: []const u8, month_text: []const u8, day_text: []const u8, time: i64, kind: u8, value: i64 };
pub fn parseUntil(fields: []const []const u8) FieldError!Until {
    const year = try parseYear(fields[0]);
    const month_text = if (fields.len > 1) fields[1] else "Jan";
    const month = try parseMonth(month_text);
    const day_text = if (fields.len > 2) fields[2] else "1";
    const day = try parseDaySpec(day_text, month);
    const clock = if (fields.len > 3) try parseTime(fields[3]) else Clock{ .value = 0, .kind = 'w' };
    return .{ .year_text = fields[0], .month_text = month_text, .day_text = day_text, .time = clock.value, .kind = clock.kind, .value = day.value(year, month) * 86400 + clock.value };
}
