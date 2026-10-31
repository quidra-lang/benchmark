const std = @import("std");
const u = @import("units.zig");
pub const A = std.mem.Allocator;
pub const Kind = enum(usize) {
    modifier,
    wind,
    variation,
    visibility,
    rvr,
    weather,
    cloud,
    temperature,
    pressure,
    no_trend
};

pub const Value = struct {
    raw: []const u8 = "",
    name: []const u8 = "",
    suffix: []const u8 = "",
    qualifier: []const u8 = "",
    qualifier2: []const u8 = "",
    unit: []const u8 = "",
    trend: []const u8 = "",
    intensity: []const u8 = "",
    descriptor: []const u8 = "",
    codes: []const []const u8 = &.{},
    direction: i64 = 0,
    speed: i64 = 0,
    gust: i64 = -1,
    direction_start: i64 = 0,
    direction_end: i64 = 0,
    whole_or_meters: i64 = 0,
    numerator: i64 = 0,
    denominator: i64 = 1,
    reading_first: i64 = 0,
    reading_second: i64 = 0,
    height: i64 = 0,
    temperature: i64 = 0,
    dew_point: i64 = 0,
    pressure: i64 = 0,
    inches: i64 = 0,
    hectopascals: i64 = 0,
    mixed: bool = false,
    fractional: bool = false,
};

pub const Section = struct {
    context: []const u8 = "",
    one: [10]?Value = .{ null } ** 10,
    lists: [10][]const Value = .{ &.{} } ** 10,
    pub fn get(s: Section, k: Kind) ?Value {
        return s.one[@intFromEnum(k)];
    }
    pub fn list(s: Section, k: Kind) []const Value {
        return s.lists[@intFromEnum(k)];
    }
};

pub const Runway = struct {
    name: []const u8,
    heading: i64
};

pub const Station = struct {
    code: []const u8,
    elevation: i64,
    runways: []const Runway,
    name: []const u8
};

pub const Group = struct {
    text: []const u8,
    position: usize
};

pub const Problem = struct {
    report: usize,
    position: usize,
    reason: []const u8,
    text: ?[]const u8 = null
};
pub const descriptors = [_][]const u8 { "MI", "BC", "PR", "DR", "BL", "SH", "TS", "FZ" };
pub const descriptor_words = [_][]const u8 { "shallow", "patches", "partial", "low drifting", "blowing", "showers", "thunderstorm", "freezing" };
pub const phenomena = [_][]const u8 { "DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP", "BR", "FG", "FU", "VA", "DU", "SA", "HZ", "PY", "PO", "SQ", "FC", "SS", "DS" };
pub const phenomenon_words = [_][]const u8 { "drizzle", "rain", "snow", "snow grains", "ice crystals", "ice pellets", "hail", "small hail", "unknown precipitation", "mist", "fog", "smoke", "volcanic ash", "dust", "sand", "haze", "spray", "dust whirls", "squalls", "funnel cloud", "sandstorm", "duststorm" };
pub const amounts = [_][]const u8 { "FEW", "SCT", "BKN", "OVC" };
pub const amount_words = [_][]const u8 { "few", "scattered", "broken", "overcast" };
pub const clear = [_][]const u8 { "SKC", "CLR", "NSC" };
pub const clear_words = [_][]const u8 { "sky clear", "clear below 12000 ft", "no significant cloud" };

pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn index(items: []const []const u8, text: []const u8) ?usize {
    for (items, 0..) |item, i| {
        if (eq(item, text)) return i;
    }
    return null;
}

pub fn digits(text: []const u8, lo: usize, hi: usize) bool {
    if (text.len < lo or text.len > hi) return false;
    for (text) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}

fn signed(text: []const u8) ?i64 {
    const neg = std.mem.startsWith(u8, text, "M");
    const body = if (neg) text[1..] else text;
    if (!digits(body, 2, 2)) return null;
    return number(body) *(if (neg) @as(i64, -1) else 1);
}

fn reading(text: []const u8, cursor: *usize, qualifier: *[]const u8) ?i64 {
    const start = cursor.*;
    qualifier.*= "";
    if (cursor.*< text.len and (text[cursor.*] == 'M' or text[cursor.*] == 'P')) {
        qualifier.*= text[cursor.*..cursor.*+ 1];
        cursor.*+= 1;
    }
    if (cursor.*+ 4 > text.len or !digits(text[cursor.*..cursor.*+ 4], 4, 4)) {
        cursor.*= start;
        return null;
    }
    const value = number(text[cursor.*..cursor.*+ 4]);
    cursor.*+= 4;
    return value;
}

pub fn format(gpa: A, k: Kind, text: []const u8) !?Value {
    var v: Value = .{.raw = text };
    switch (k) {
        .modifier => {
            if (!eq(text, "AUTO") and !eq(text, "COR")) return null;
            v.name = text;
        },
        .wind => {
            var body = text;
            if (std.mem.endsWith(u8, body, "MPS")) {
                v.unit = "MPS";
                body = body[0..body.len - 3];
            } else if (std.mem.endsWith(u8, body, "KT")) {
                v.unit = "KT";
                body = body[0..body.len - 2];
            } else return null;
            if (body.len < 5 or (!eq(body[0..3], "VRB") and !digits(body[0..3], 3, 3))) return null;
            v.direction = if (eq(body[0..3], "VRB")) - 1 else number(body[0..3]);
            const tail = body[3..];
            const gust = std.mem.findScalar(u8, tail, 'G');
            const speed = if (gust) |p| tail[0..p] else tail;
            if (!digits(speed, 2, 3)) return null;
            v.speed = number(speed);
            if (gust) |p| {
                if (!digits(tail[p + 1..], 2, 3)) return null;
                v.gust = number(tail[p + 1..]);
            }
        },
        .variation => {
            if (text.len != 7 or text[3] != 'V' or !digits(text[0..3], 3, 3) or !digits(text[4..], 3, 3)) return null;
            v.direction_start = number(text[0..3]);
            v.direction_end = number(text[4..]);
        },
        .visibility => {
            if (eq(text, "CAVOK")) {
                v.name = "cavok";
                v.whole_or_meters = 10000;
                v.qualifier = "P";
            } else if (digits(text, 4, 4)) {
                v.name = "meter";
                v.whole_or_meters = number(text);
                if (v.whole_or_meters == 9999) {
                    v.whole_or_meters = 10000;
                    v.qualifier = "P";
                }
            } else {
                if (!std.mem.endsWith(u8, text, "SM")) return null;
                v.name = "mile";
                v.denominator = 1;
                var body = text[0..text.len - 2];
                if (body.len > 0 and (body[0] == 'M' or body[0] == 'P')) {
                    v.qualifier = body[0..1];
                    body = body[1..];
                }
                if (std.mem.findScalar(u8, body, ' ')) |p| {
                    if (p != 1 or !digits(body[0..p], 1, 1) or v.qualifier.len > 0) return null;
                    v.whole_or_meters = number(body[0..p]);
                    v.mixed = true;
                    body = body[p + 1..];
                }
                if (std.mem.findScalar(u8, body, '/')) |p| {
                    if (!digits(body[0..p], 1, 1) or !digits(body[p + 1..], 1, 2)) return null;
                    v.numerator = number(body[0..p]);
                    v.denominator = number(body[p + 1..]);
                    v.fractional = true;
                } else {
                    if (v.mixed or !digits(body, 1, 2)) return null;
                    v.whole_or_meters = number(body);
                }
            }
        },
        .rvr => {
            if (text.len < 8 or text[0] != 'R') return null;
            const slash = std.mem.findScalar(u8, text, '/') orelse return null;
            if ((slash != 3 and slash != 4) or !digits(text[1..3], 2, 2) or (slash == 4 and std.mem.findScalar(u8, "LCR", text[3]) == null)) return null;
            v.name = text[1..slash];
            var cursor = slash + 1;
            v.reading_first = reading(text, &cursor, &v.qualifier) orelse return null;
            if (cursor < text.len and text[cursor] == 'V') {
                cursor += 1;
                v.reading_second = reading(text, &cursor, &v.qualifier2) orelse return null;
                v.mixed = true;
            }
            v.unit = "m";
            if (std.mem.startsWith(u8, text[cursor..], "FT")) {
                v.unit = "ft";
                cursor += 2;
            }
            if (cursor < text.len and std.mem.findScalar(u8, "UDN", text[cursor]) != null) {
                v.trend = text[cursor..cursor + 1];
                cursor += 1;
            }
            if (cursor != text.len) return null;
        },
        .weather => {
            if (eq(text, "NSW")) {
                v.name = "NSW";
                return v;
            }
            var body = text;
            if (std.mem.startsWith(u8, body, "VC")) {
                v.intensity = "VC";
                body = body[2..];
            } else if (body.len > 0 and (body[0] == '-' or body[0] == '+')) {
                v.intensity = body[0..1];
                body = body[1..];
            }
            if (body.len == 0 or body.len % 2 != 0) return null;
            var codes: std.ArrayList([]const u8) = .empty;
            var p: usize = 0;
            while (p < body.len) : (p += 2) {
                const code = body[p..p + 2];
                if (index(&descriptors, code) == null and index(&phenomena, code) == null) return null;
                try codes.append(gpa, code);
            }
            v.codes = codes.items;
            if (index(&descriptors, codes.items[0]) != null) {
                v.descriptor = codes.items[0];
                v.codes = codes.items[1..];
            }
        },
        .cloud => {
            if (index(&clear, text) != null) {
                v.name = text;
                v.height = -1;
            } else if (text.len == 5 and std.mem.startsWith(u8, text, "VV") and digits(text[2..], 3, 3)) {
                v.name = "VV";
                v.height = number(text[2..]) * 100;
            } else {
                if (text.len < 6 or index(&amounts, text[0..3]) == null or !digits(text[3..6], 3, 3)) return null;
                v.name = text[0..3];
                v.height = number(text[3..6]) * 100;
                v.suffix = text[6..];
                if (v.suffix.len > 0 and !eq(v.suffix, "CB") and !eq(v.suffix, "TCU")) return null;
            }
        },
        .temperature => {
            const p = std.mem.findScalar(u8, text, '/') orelse return null;
            v.temperature = signed(text[0..p]) orelse return null;
            v.dew_point = signed(text[p + 1..]) orelse return null;
        },
        .pressure => {
            if (text.len != 5 or (text[0] != 'A' and text[0] != 'Q') or !digits(text[1..], 4, 4)) return null;
            v.unit = text[0..1];
            v.pressure = number(text[1..]);
        },
        .no_trend => {
            if (!eq(text, "NOSIG")) return null;
        },
    }
    return v;
}

pub fn valid(k: Kind, v: Value, s: Section, station: Station) bool {
    switch (k) {
        .wind => {
            if (v.direction < 0) {
                if (v.speed < 1) return false;
            } else if (v.direction > 360 or @mod(v.direction, 10) != 0 or ((v.direction == 0) !=(v.speed == 0))) return false;
            return v.gust < 0 or (v.direction != 0 and v.gust > v.speed);
        },
        .variation => {
            const w = s.get(.wind) orelse return false;
            return v.direction_start >= 10 and v.direction_start <= 360 and @mod(v.direction_start, 10) == 0 and v.direction_end >= 10 and v.direction_end <= 360 and @mod(v.direction_end, 10) == 0 and v.direction_start != v.direction_end and w.direction > 0;
        },
        .visibility => {
            if (!eq(v.name, "mile")) return true;
            if (!v.fractional) return v.whole_or_meters >= 1;
            return (v.denominator == 2 or v.denominator == 4 or v.denominator == 8 or v.denominator == 16) and v.numerator >= 1 and v.numerator < v.denominator and (!v.mixed or v.whole_or_meters >= 1);
        },
        .rvr => {
            var found = false;
            for (station.runways) |r| {
                if (eq(r.name, v.name)) found = true;
            }
            return found and (!v.mixed or v.reading_first < v.reading_second);
        },
        .weather => {
            const previous = s.list(.weather);
            if (previous.len >= 3) return false;
            for (previous) |w| {
                if (eq(w.name, "NSW")) return false;
            }
            if (eq(v.name, "NSW")) return previous.len == 0 and (eq(s.context, "trend") or eq(s.context, "change"));
            var precip: usize = 0;
            for (v.codes, 0..) |code, i| {
                const p = index(&phenomena, code) orelse return false;
                if (p < 9) precip += 1;
                for (v.codes[0..i]) |old| {
                    if (eq(old, code)) return false;
                }
            }
            if (v.codes.len == 0 and !eq(v.descriptor, "TS") and !eq(v.descriptor, "SH")) return false;
            if ((eq(v.intensity, "-") or eq(v.intensity, "+")) and precip == 0) return false;
            return v.codes.len < 2 or precip == v.codes.len;
        },
        .cloud => {
            const previous = s.list(.cloud);
            if (previous.len == 0) return true;
            const old = previous[previous.len - 1];
            return index(&amounts, v.name) != null and index(&amounts, old.name) != null and v.height > old.height;
        },
        .temperature => return v.dew_point <= v.temperature,
        .pressure => return if (eq(v.unit, "A")) v.pressure >= 2500 and v.pressure <= 3150 else v.pressure >= 850 and v.pressure <= 1070, else => return true,
    }
}

pub fn accept(gpa: A, s: *Section, k: Kind, value: Value) !void {
    var v = value;
    if (k == .wind and eq(v.unit, "MPS")) {
        v.speed = u.knots(v.speed);
        if (v.gust >= 0) v.gust = u.knots(v.gust);
    }
    if (k == .pressure) {
        v.inches = if (eq(v.unit, "A")) v.pressure else u.inHg(v.pressure);
        v.hectopascals = if (eq(v.unit, "Q")) v.pressure else u.hPa(v.pressure);
    }
    const ix = @intFromEnum(k);
    s.one[ix] = v;
    if (k == .weather or k == .cloud or k == .rvr) {
        const old = s.lists[ix];
        const next = try gpa.alloc(Value, old.len + 1);
        @memcpy(next[0..old.len], old);
        next[old.len] = v;
        s.lists[ix] = next;
    }
    if (k == .visibility and eq(v.name, "cavok")) {
        s.one[@intFromEnum(Kind.weather)] = .{};
        s.one[@intFromEnum(Kind.cloud)] = .{};
        s.lists[@intFromEnum(Kind.weather)] = &.{};
        s.lists[@intFromEnum(Kind.cloud)] = &.{};
    }
}
