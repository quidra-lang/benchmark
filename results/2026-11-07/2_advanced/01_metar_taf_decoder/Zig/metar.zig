const std = @import("std");
const g = @import("groups.zig");
pub const slots = [_]g.Kind {.modifier, .wind, .variation, .visibility, .rvr, .weather, .cloud, .temperature, .pressure, .no_trend };

pub fn repeat(k: g.Kind) bool {
    return k == .rvr or k == .weather or k == .cloud;
}

pub fn test(a: g.A, k: g.Kind, text: []const u8) !?g.Value {
    return g.format(a, k, text);
}

pub fn isTrend(text: []const u8) bool {
    return g.eq(text, "BECMG") or g.eq(text, "TEMPO");
}

pub const Parts = struct {
    main: []const g.Group,
    trends: []const g.Group,
    remarks: []const g.Group
};

pub fn split(body: []const g.Group) Parts {
    var r = body.len;
    for (body, 0..) |v, i| {
        if (g.eq(v.text, "RMK")) {
            r = i;
            break;
        }
    }
    var t = r;
    for (body[0..r], 0..) |v, i| {
        if (isTrend(v.text)) {
            t = i;
            break;
        }
    }
    return .{.main = body[0..t], .trends = body[t..r], .remarks = if (r < body.len) body[r + 1..] else &.{} };
}

pub const Time = struct {
    kind: []const u8,
    hour: i64,
    minute: i64
};

pub const Trend = struct {
    kind: []const u8,
    times: []const Time,
    body: []const g.Group,
    state: g.Section = .{}
};

pub fn trends(a: g.A, body: []const g.Group, report: usize, errors: *std.ArrayList(g.Problem)) ![]Trend {
    var result: std.ArrayList(Trend) = .empty;
    var i: usize = 0;
    while (i < body.len) {
        var end = i + 1;
        while (end < body.len and !isTrend(body[end].text)) : (end += 1) {}
        var cursor = i + 1;
        var times: std.ArrayList(Time) = .empty;
        var bad = false;
        while (cursor < end) {
            const text = body[cursor].text;
            if (text.len != 6 or g.index(&.{ "FM", "TL", "AT" }, text[0..2]) == null or !g.digits(text[2..], 4, 4)) break;
            if (times.items.len > 0 and !(times.items.len == 1 and g.eq(times.items[0].kind, "FM") and g.eq(text[0..2], "TL"))) break;
            const h = g.number(text[2..4]);
            const m = g.number(text[4..6]);
            if (h > 23 or m > 59) {
                try errors.append(a, .{.report = report, .position = body[cursor].position, .reason = "invalid period", .text = text });
                bad = true;
                break;
            }
            try times.append(a, .{.kind = text[0..2], .hour = h, .minute = m });
            cursor += 1;
        }
        if (!bad) try result.append(a, .{.kind = body[i].text, .times = times.items, .body = body[cursor..end] });
        i = end;
    }
    return result.toOwnedSlice(a);
}

pub const Remarks = struct {
    pressures: []const i64,
    temperatures: []const[2]i64
};

pub fn remarks(a: g.A, body: []const g.Group) !Remarks {
    var p: std.ArrayList(i64) = .empty;
    var t: std.ArrayList([2]i64) = .empty;
    for (body) |item| {
        const text = item.text;
        if (text.len == 6 and std.mem.startsWith(u8, text, "SLP") and g.digits(text[3..], 3, 3)) {
            const v = g.number(text[3..]);
            try p.append(a,(if (v >= 500) @as(i64, 9000) else 10000) + v);
        }
        if (text.len == 9 and text[0] == 'T' and (text[1] == '0' or text[1] == '1') and (text[5] == '0' or text[5] == '1') and g.digits(text[2..5], 3, 3) and g.digits(text[6..9], 3, 3)) try t.append(a, .{ g.number(text[2..5]) *(if (text[1] == '1') @as(i64, -1) else 1), g.number(text[6..9]) *(if (text[5] == '1') @as(i64, -1) else 1) });
    }
    return .{.pressures = p.items, .temperatures = t.items };
}
