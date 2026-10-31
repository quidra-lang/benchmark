const std = @import("std");
const g = @import("groups.zig");
const u = @import("units.zig");
pub const slots = [_]g.Kind {.wind, .visibility, .weather, .cloud };

pub const Change = struct {
    kind: []const u8,
    start: i64 = 0,
    end: i64 = 0,
    body: []const g.Group,
    state: g.Section = .{}
};

pub const Parts = struct {
    base: []const g.Group,
    changes: []Change
};

pub const Temporary = struct {
    kind: []const u8,
    state: g.Section
};

pub const Hour = struct {
    time: i64,
    prevailing: g.Section,
    temporary: []const Temporary
};

pub fn indicator(text: []const u8) bool {
    return g.index(&.{ "BECMG", "TEMPO", "PROB30", "PROB40" }, text) != null or (text.len == 8 and std.mem.startsWith(u8, text, "FM") and g.digits(text[2..], 6, 6));
}

pub fn split(a: g.A, body: []const g.Group, calendar: u.Calendar, issue_day: i64, start: i64, end: i64, report: usize, errors: *std.ArrayList(g.Problem)) !Parts {
    var i: usize = 0;
    while (i < body.len and !indicator(body[i].text)) : (i += 1) {}
    const base = body[0..i];
    var changes: std.ArrayList(Change) = .empty;
    while (i < body.len) {
        const item = body[i];
        var kind: []const u8 = if (std.mem.startsWith(u8, item.text, "FM")) "FM" else item.text;
        i += 1;
        if ((g.eq(kind, "PROB30") or g.eq(kind, "PROB40")) and i < body.len and g.eq(body[i].text, "TEMPO")) {
            kind = try std.fmt.allocPrint(a, "{s} TEMPO", .{ kind });
            i += 1;
        }
        var stop = i;
        while (stop < body.len and !indicator(body[stop].text)) : (stop += 1) {}
        if (g.eq(kind, "FM")) {
            const time = calendar.change(item.text, issue_day);
            if (time == null or time.? < start or time.? >= end) try errors.append(a, .{.report = report, .position = item.position, .reason = "invalid period", .text = item.text }) else try changes.append(a, .{.kind = kind, .start = time.?, .end = time.?, .body = body[i..stop] });
        } else if (i == stop or body[i].text.len != 9 or body[i].text[4] != '/' or !g.digits(body[i].text[0..4], 4, 4) or !g.digits(body[i].text[5..9], 4, 4)) {
            try errors.append(a, .{.report = report, .position = item.position, .reason = "missing period", .text = kind });
        } else {
            const period = calendar.period(body[i].text, issue_day, 0);
            if (period == null or period.?.start < start or period.?.end > end) try errors.append(a, .{.report = report, .position = body[i].position, .reason = "invalid period", .text = body[i].text }) else try changes.append(a, .{.kind = kind, .start = period.?.start, .end = period.?.end, .body = body[i + 1..stop] });
        }
        i = stop;
    }
    return .{.base = base, .changes = changes.items };
}

pub fn overlay(base: g.Section, change: g.Section) g.Section {
    var result = base;
    for (slots) |k| {
        const i = @intFromEnum(k);
        if (change.one[i] != null) {
            result.one[i] = change.one[i];
            result.lists[i] = change.lists[i];
        }
    }
    return result;
}

pub fn expand(a: g.A, start: i64, end: i64, base: g.Section, changes: []const Change) ![]Hour {
    var hours: std.ArrayList(Hour) = .empty;
    var h = start;
    while (h < end) : (h += 60) {
        var state = base;
        for (changes) |c| {
            if (g.eq(c.kind, "FM") and c.start <= h) state = c.state;
            if (g.eq(c.kind, "BECMG") and c.end <= h) state = overlay(state, c.state);
        }
        var temp: std.ArrayList(Temporary) = .empty;
        for (changes) |c| {
            if (!g.eq(c.kind, "FM") and !g.eq(c.kind, "BECMG") and c.start <= h and h < c.end) try temp.append(a, .{.kind = c.kind, .state = overlay(state, c.state) });
        }
        try hours.append(a, .{.time = h, .prevailing = state, .temporary = temp.items });
    }
    return hours.items;
}
