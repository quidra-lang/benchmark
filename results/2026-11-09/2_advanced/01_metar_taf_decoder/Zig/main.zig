const std = @import("std");
const g = @import("groups.zig");
const u = @import("units.zig");
const m = @import("metar.zig");
const t = @import("taf.zig");
const v = @import("verification.zig");
var arena: std.heap.ArenaAllocator = undefined;

fn alloc() g.A {
    return arena.allocator();
}

fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(alloc(), pattern, args) catch @panic("allocation failed");
}

fn append(comptime T: type, list: *std.ArrayList(T), item: T) void {
    list.append(alloc(), item) catch @panic("allocation failed");
}

const Text = struct {
    bytes: std.ArrayList(u8) = .empty,
    fn add(s: *Text, text: []const u8) void {
        s.bytes.appendSlice(alloc(), text) catch @panic("allocation failed");
    }
    fn line(s: *Text, text: []const u8) void {
        s.add(text);
        s.add("\n");
    }
    fn block(s: *Text, text: []const u8) void {
        if (s.bytes.items.len > 0) s.add("\n");
        s.add(text);
    }
    fn value(s: Text) []const u8 {
        return s.bytes.items;
    }
};

fn join(items: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(alloc(), separator, items) catch @panic("allocation failed");
}

fn words(text: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |s| append([]const u8, &out, s);
    return out.items;
}

fn lines(text: []const u8) []const []const u8 {
    const all = words(text, '\n');
    return all[0..all.len - 1];
}

fn repeatByte(byte: u8, count: usize) []const u8 {
    const result = alloc().alloc(u8, count) catch @panic("allocation failed");
    @memset(result, byte);
    return result;
}

fn pad(n: i64, width: usize) []const u8 {
    const text = fmt("{d}", .{ n });
    if (text.len >= width) return text;
    return fmt("{s}{s}", .{ repeatByte('0', width - text.len), text });
}

fn abs(n: i64) i64 {
    return if (n < 0) - n else n;
}

fn stamp(calendar: u.Calendar, time: i64) []const u8 {
    return calendar.stamp(alloc(), time) catch unreachable;
}

fn fraction(p: i64, q: i64) []const u8 {
    return u.fraction(alloc(), p, q) catch unreachable;
}

fn tenth(n: i64) []const u8 {
    return fmt("{s}{d}.{d}", .{ if (n < 0) @as([]const u8, "-") else "", @divFloor(abs(n), 10), @mod(abs(n), 10) });
}

fn ceiling(s: g.Section) ?i64 {
    for (s.list(.cloud)) |c| {
        if (g.index(&.{ "BKN", "OVC", "VV" }, c.name) != null) return c.height;
    }
    return null;
}

fn category(s: g.Section) usize {
    const c = ceiling(s) orelse 1000000;
    var p: i64 = 100000000;
    var q: i64 = 1;
    if (s.get(.visibility)) |vis| {
        const f = u.miles(vis.name, vis.whole_or_meters, vis.numerator, vis.denominator);
        p = f.p;
        q = f.q;
    }
    if (c < 500 or p < q) return 3;
    if (c < 1000 or p < 3 * q) return 2;
    if (c <= 3000 or p <= 5 * q) return 1;
    return 0;
}

fn windPhrase(w: g.Value) []const u8 {
    if (w.direction == 0) return "calm";
    const base = if (w.direction < 0) fmt("variable at {d} KT", .{ w.speed }) else fmt("{s} degrees at {d} KT", .{ pad(w.direction, 3), w.speed });
    return if (w.gust < 0) base else fmt("{s} gusting {d} KT", .{ base, w.gust });
}

fn windCode(w: g.Value) []const u8 {
    if (w.direction == 0) return "00000KT";
    return fmt("{s}{s}{s}KT", .{ if (w.direction < 0) @as([]const u8, "VRB") else pad(w.direction, 3), pad(w.speed, 2), if (w.gust < 0) @as([]const u8, "") else fmt("G{s}", .{ pad(w.gust, 2) }) });
}

fn mileNumber(w: g.Value) []const u8 {
    if (!w.fractional) return fmt("{d}", .{ w.whole_or_meters });
    const f = fmt("{d}/{d}", .{ w.numerator, w.denominator });
    return if (w.whole_or_meters == 0) f else fmt("{d} {s}", .{ w.whole_or_meters, f });
}

fn qualifier(q: []const u8) []const u8 {
    return if (g.eq(q, "M")) "less than " else if (g.eq(q, "P")) "more than " else "";
}

fn visibilityPhrase(w: g.Value) []const u8 {
    if (g.eq(w.name, "cavok")) return "10 km or more (CAVOK)";
    if (g.eq(w.name, "meter")) return if (g.eq(w.qualifier, "P")) "10 km or more" else fmt("{d} m", .{ w.whole_or_meters });
    return fmt("{s}{s} SM", .{ qualifier(w.qualifier), mileNumber(w) });
}

fn visibilityCode(w: g.Value) []const u8 {
    if (g.eq(w.name, "cavok")) return "CAVOK";
    if (g.eq(w.name, "meter")) return w.raw;
    return fmt("{s}{s}SM", .{ w.qualifier, mileNumber(w) });
}

fn weatherPhrase(w: g.Value) []const u8 {
    if (g.eq(w.name, "NSW")) return "no significant weather";
    var parts: std.ArrayList([]const u8) = .empty;
    var phenomena: std.ArrayList([]const u8) = .empty;
    if (w.intensity.len > 0) append([]const u8, &parts, if (g.eq(w.intensity, "-")) "light" else if (g.eq(w.intensity, "+")) "heavy" else "nearby");
    if (g.index(&g.descriptors, w.descriptor)) |i| append([]const u8, &parts, g.descriptor_words[i]);
    for (w.codes) |code| append([]const u8, &phenomena, g.phenomenon_words[g.index(&g.phenomena, code).?]);
    if (phenomena.items.len > 0) append([]const u8, &parts, join(phenomena.items, " and "));
    return join(parts.items, " ");
}

fn cloudPhrase(c: g.Value) []const u8 {
    if (g.index(&g.clear, c.name)) |i| return g.clear_words[i];
    if (g.eq(c.name, "VV")) return fmt("vertical visibility {d} ft", .{ c.height });
    return fmt("{s} at {d} ft{s}", .{ g.amount_words[g.index(&g.amounts, c.name).?], c.height, if (g.eq(c.suffix, "CB")) @as([]const u8, " cumulonimbus") else if (g.eq(c.suffix, "TCU")) @as([]const u8, " towering cumulus") else "" });
}

fn summary(s: g.Section) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    if (s.get(.wind)) |w| append([]const u8, &parts, fmt("wind {s}", .{ windPhrase(w) }));
    if (s.get(.visibility)) |w| append([]const u8, &parts, fmt("visibility {s}", .{ visibilityPhrase(w) }));
    for ([_]g.Kind {
        .weather, .cloud
    }) |k| {
        var phrases: std.ArrayList([]const u8) = .empty;
        for (s.list(k)) |w| append([]const u8, &phrases, if (k == .weather) weatherPhrase(w) else cloudPhrase(w));
        if (phrases.items.len > 0) append([]const u8, &parts, fmt("{s} {s}", .{ if (k == .weather) @as([]const u8, "weather") else "cloud", join(phrases.items, ", ") }));
    }
    return if (parts.items.len == 0) "no conditions" else join(parts.items, "; ");
}

fn tokens(s: g.Section) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    if (s.get(.wind)) |w| append([]const u8, &parts, windCode(w));
    if (s.get(.visibility)) |w| append([]const u8, &parts, visibilityCode(w));
    for (s.list(.weather)) |w| {
        if (!g.eq(w.name, "NSW")) append([]const u8, &parts, w.raw);
    }
    for (s.list(.cloud)) |c| append([]const u8, &parts, c.raw);
    append([]const u8, &parts, v.categories[category(s)]);
    return join(parts.items, " ");
}

fn windChanges(before: ?g.Value, after: ?g.Value, alpha: i64) []const []const u8 {
    const a = before orelse return &.{};
    const b = after orelse return &.{};
    var reasons: std.ArrayList([]const u8) = .empty;
    if (a.direction > 0 and b.direction > 0 and @max(a.speed, b.speed) >= 10) {
        const d = @mod(abs(a.direction - b.direction), 360);
        if (@min(d, 360 - d) >= alpha) append([]const u8, &reasons, "wind shift");
    }
    if (abs(a.speed - b.speed) >= 10) append([]const u8, &reasons, "wind speed");
    return reasons.items;
}

fn weatherFlag(s: g.Section, freezing: bool) bool {
    for (s.list(.weather)) |w| {
        if (!freezing and g.eq(w.descriptor, "TS")) return true;
        if (freezing and g.eq(w.descriptor, "FZ")) for (w.codes) |code| {
            if (g.eq(code, "RA") or g.eq(code, "DZ")) return true;
        };
    }
    return false;
}

const Report = struct {
    number: usize,
    kind: []const u8,
    modifier: []const u8 = "",
    station: usize,
    time: i64,
    start: i64 = 0,
    end: i64 = 0,
    body_start: usize = 0,
    state: g.Section = .{},
    trends: []m.Trend = &.{},
    remarks: m.Remarks = .{.pressures = &.{}, .temperatures = &.{} },
    changes: []t.Change = &.{},
    hours: []t.Hour = &.{},
    speci: []const u8 = ""
};

const Engine = struct {
    calendar: u.Calendar,
    stations: []const g.Station,
    crosswind: i64,
    tailwind: i64,
    errors: std.ArrayList(g.Problem) = .empty,
    fn problem(e: *Engine, report: usize, position: usize, reason: []const u8, text: ?[]const u8) void {
        append(g.Problem, &e.errors, .{.report = report, .position = position, .reason = reason, .text = text });
    }
    fn header(e: *Engine, number: usize, w: []const []const u8) ?Report {
        if (g.index(&.{ "METAR", "SPECI", "TAF" }, w[0]) == null) {
            e.problem(number, 1, "rejected report, invalid type", w[0]);
            return null;
        }
        var r: Report = .{.number = number, .kind = w[0], .station = 0, .time = 0 };
        var cursor: usize = 1;
        if (g.eq(r.kind, "TAF") and cursor < w.len and g.index(&.{ "AMD", "COR" }, w[cursor]) != null) {
            r.modifier = w[cursor];
            cursor += 1;
        }
        const items: []const []const u8 = if (g.eq(r.kind, "TAF")) &.{ "station", "time", "validity" } else &.{ "station", "time" };
        for (items, 0..) |item, j| {
            if (cursor == w.len) {
                e.problem(number, w.len + 1, fmt("rejected report, missing {s}", .{ item }), null);
                return null;
            }
            var valid = false;
            const word = w[cursor];
            if (j == 0) {
                for (e.stations, 0..) |s, i| {
                    if (g.eq(s.code, word)) {
                        r.station = i;
                        valid = true;
                        break;
                    }
                }
            } else if (j == 1) {
                if (e.calendar.observation(word)) |time| {
                    r.time = time;
                    valid = true;
                }
            } else {
                if (e.calendar.period(word, @divFloor(r.time, 1440) + 1, 1800)) |period| {
                    r.start = period.start;
                    r.end = period.end;
                    valid = true;
                }
            }
            if (!valid) {
                e.problem(number, cursor + 1, fmt("rejected report, invalid {s}", .{ item }), word);
                return null;
            }
            cursor += 1;
        }
        r.body_start = cursor;
        return r;
    }
    fn matchSection(e: *Engine, r: Report, body: []const g.Group, slots: []const g.Kind, context: []const u8) g.Section {
        var state: g.Section = .{.context = context };
        var current: usize = 0;
        for (body) |item| {
            var found = current;
            var value: ?g.Value = null;
            while (found < slots.len) : (found += 1) {
                value = m.test(alloc(), slots[found], item.text) catch unreachable;
                if (value != null) break;
            }
            if (found == slots.len) {
                var earlier = false;
                for (slots[0..current]) |k| {
                    if ((m.test(alloc(), k, item.text) catch unreachable) != null) earlier = true;
                }
                e.problem(r.number, item.position, if (earlier) "out of order group" else "unknown group", item.text);
                continue;
            }
            const k = slots[found];
            if (!g.valid(k, value.?, state, e.stations[r.station])) {
                e.problem(r.number, item.position, "invalid group", item.text);
                continue;
            }
            g.accept(alloc(), &state, k, value.?) catch unreachable;
            if (k == .visibility and g.eq(value.?.name, "cavok")) {
                for (slots, 0..) |slot, i| {
                    if (slot == .cloud) current = i + 1;
                }
            } else current = found + @as(usize, if (m.repeat(k)) 0 else 1);
        }
        return state;
    }
    fn decode(e: *Engine, r: *Report, w: []const []const u8, previous: []const Report) void {
        var body: std.ArrayList(g.Group) = .empty;
        var i = r.body_start;
        while (i < w.len) {
            const position = i + 1;
            var text = w[i];
            if (g.digits(text, 1, 1) and i + 1 < w.len) {
                const next = w[i + 1];
                if (next.len >= 5 and next.len <= 6 and next[1] == '/' and g.digits(next[0..1], 1, 1) and std.mem.endsWith(u8, next, "SM") and g.digits(next[2..next.len - 2], 1, 2)) {
                    text = fmt("{s} {s}", .{ text, next });
                    i += 1;
                }
            }
            append(g.Group, &body, .{.text = text, .position = position });
            i += 1;
        }
        if (g.eq(r.kind, "TAF")) {
            const parts = t.split(alloc(), body.items, e.calendar, @divFloor(r.time, 1440) + 1, r.start, r.end, r.number, &e.errors) catch unreachable;
            r.state = e.matchSection(r.*, parts.base, &t.slots, "base");
            r.changes = parts.changes;
            for (r.changes) |*change| change.state = e.matchSection(r.*, change.body, &t.slots, "change");
            r.hours = t.expand(alloc(), r.start, r.end, r.state, r.changes) catch unreachable;
        } else {
            const parts = m.split(body.items);
            r.state = e.matchSection(r.*, parts.main, &m.slots, "main");
            r.trends = m.trends(alloc(), parts.trends, r.number, &e.errors) catch unreachable;
            for (r.trends) |*trend| trend.state = e.matchSection(r.*, trend.body, &t.slots, "trend");
            r.remarks = m.remarks(alloc(), parts.remarks) catch unreachable;
            if (g.eq(r.kind, "SPECI")) {
                var before: ?g.Section = null;
                for (previous) |p| {
                    if (p.station == r.station and !g.eq(p.kind, "TAF")) before = p.state;
                }
                r.speci = speci(before, r.state);
            }
        }
    }
};

fn speci(previous: ?g.Section, state: g.Section) []const u8 {
    const p = previous orelse return "no previous report";
    var reasons: std.ArrayList([]const u8) = .empty;
    if (category(p) != category(state)) append([]const u8, &reasons, fmt("category {s} to {s}", .{ v.categories[category(p)], v.categories[category(state)] }));
    for (windChanges(p.get(.wind), state.get(.wind), 45)) |reason| append([]const u8, &reasons, reason);
    for ([_]bool {
        false, true
    }) |freezing| {
        if (weatherFlag(p, freezing) != weatherFlag(state, freezing)) append([]const u8, &reasons, fmt("{s} {s}", .{ if (freezing) @as([]const u8, "freezing precipitation") else "thunderstorm", if (weatherFlag(state, freezing)) @as([]const u8, "began") else "ended" }));
    }
    return if (reasons.items.len == 0) "no criteria met" else join(reasons.items, ", ");
}

fn component(direction: i64, heading: i64, speed: i64) [2]i64 {
    return .{ @divFloor(speed * u.cos(direction - heading), 1000), @divFloor(speed * u.sin(direction - heading), 1000) };
}

fn componentPhrase(c: [2]i64) []const u8 {
    return fmt("{s} {d} KT, crosswind {d} KT{s}", .{ if (c[0] < 0) @as([]const u8, "tailwind") else "headwind", abs(c[0]), abs(c[1]), if (c[1] > 0) @as([]const u8, " from right") else if (c[1] < 0) @as([]const u8, " from left") else "" });
}

fn rvrPhrase(w: g.Value) []const u8 {
    const a = fmt("{s}{d}", .{ qualifier(w.qualifier), w.reading_first });
    const b = fmt("{s}{d}", .{ qualifier(w.qualifier2), w.reading_second });
    return fmt("runway {s} {s} {s}{s}", .{ w.name, if (w.mixed) fmt("between {s} and {s}", .{ a, b }) else a, w.unit, if (g.eq(w.trend, "U")) @as([]const u8, ", rising") else if (g.eq(w.trend, "D")) @as([]const u8, ", falling") else if (g.eq(w.trend, "N")) @as([]const u8, ", no change") else "" });
}

fn indent(out: *Text, line: []const u8) void {
    out.add("  ");
    out.line(line);
}

fn decoded(e: Engine, r: Report) []const u8 {
    var out: Text = .{};
    const s = r.state;
    const station = e.stations[r.station];
    const cal = e.calendar;
    out.line(fmt("REPORT {d}: {s} {s} ({s})", .{ r.number, r.kind, station.code, station.name }));
    if (g.eq(r.kind, "TAF")) {
        indent(&out, fmt("issued: {s}", .{ stamp(cal, r.time) }));
        if (r.modifier.len > 0) indent(&out, fmt("modifier: {s}", .{ if (g.eq(r.modifier, "AMD")) @as([]const u8, "amended") else "corrected" }));
        indent(&out, fmt("valid: {s} to {s}", .{ stamp(cal, r.start), stamp(cal, r.end) }));
        indent(&out, fmt("base: {s}", .{ summary(s) }));
        for (r.changes) |c| indent(&out, fmt("{s} {s}: {s}", .{ c.kind, if (g.eq(c.kind, "FM")) stamp(cal, c.start) else fmt("{s} to {s}", .{ stamp(cal, c.start), stamp(cal, c.end) }), summary(c.state) }));
        return out.value();
    }
    indent(&out, fmt("time: {s}", .{ stamp(cal, r.time) }));
    if (s.get(.modifier)) |mod| indent(&out, fmt("modifier: {s}", .{ if (g.eq(mod.name, "AUTO")) @as([]const u8, "automated") else "corrected" }));
    var wind: []const u8 = if (s.get(.wind)) |w| windPhrase(w) else "not reported";
    if (s.get(.variation)) |w| wind = fmt("{s}, varying between {s} and {s} degrees", .{ wind, pad(w.direction_start, 3), pad(w.direction_end, 3) });
    indent(&out, fmt("wind: {s}", .{ wind }));
    indent(&out, fmt("visibility: {s}", .{ if (s.get(.visibility)) |w| visibilityPhrase(w) else "not reported" }));
    for (s.list(.rvr)) |w| indent(&out, fmt("runway visual range: {s}", .{ rvrPhrase(w) }));
    for (s.list(.weather)) |w| indent(&out, fmt("weather: {s}", .{ weatherPhrase(w) }));
    if (s.get(.visibility) != null and g.eq(s.get(.visibility).?.name, "cavok")) indent(&out, "cloud: no significant cloud") else if (s.get(.cloud) == null) indent(&out, "cloud: not reported") else for (s.list(.cloud)) |c| indent(&out, fmt("cloud: {s}", .{ cloudPhrase(c) }));
    if (s.get(.temperature)) |w| indent(&out, fmt("temperature: {d} C, dew point {d} C, spread {d} C", .{ w.temperature, w.dew_point, w.temperature - w.dew_point })) else indent(&out, "temperature: not reported");
    if (s.get(.pressure)) |p| {
        const inch = fmt("{d}.{s} inHg", .{ @divFloor(p.inches, 100), pad(@mod(p.inches, 100), 2) });
        const hpa = fmt("{d} hPa", .{ p.hectopascals });
        indent(&out, fmt("altimeter: {s} ({s})", .{ if (g.eq(p.unit, "A")) inch else hpa, if (g.eq(p.unit, "A")) hpa else inch }));
    } else indent(&out, "altimeter: not reported");
    if (s.get(.no_trend) != null) indent(&out, "trend: no significant change");
    for (r.trends) |trend| {
        var phrase: Text = .{};
        phrase.add(if (g.eq(trend.kind, "BECMG")) "becoming" else "temporarily");
        for (trend.times) |time| phrase.add(fmt(" {s} {s}:{s}Z", .{ if (g.eq(time.kind, "FM")) @as([]const u8, "from") else if (g.eq(time.kind, "TL")) @as([]const u8, "until") else "at", pad(time.hour, 2), pad(time.minute, 2) }));
        indent(&out, fmt("trend: {s}: {s}", .{ phrase.value(), summary(trend.state) }));
    }
    for (r.remarks.pressures) |p| indent(&out, fmt("sea level pressure: {s} hPa", .{ tenth(p) }));
    for (r.remarks.temperatures) |p| indent(&out, fmt("precise temperature: {s} C, dew point {s} C", .{ tenth(p[0]), tenth(p[1]) }));
    indent(&out, fmt("ceiling: {s}", .{ if (ceiling(s)) |h| fmt("{d} ft", .{ h }) else "none" }));
    indent(&out, fmt("flight category: {s}", .{ v.categories[category(s)] }));
    var pa: ?i64 = null;
    var da: ?i64 = null;
    if (s.get(.pressure)) |p| {
        pa = station.elevation +(2992 - p.inches) * 10;
        if (s.get(.temperature)) |temp| da = pa.? + @divFloor(120 *(1000 * temp.temperature - 15000 + 2 * pa.?), 1000);
    }
    indent(&out, fmt("pressure altitude: {s}", .{ if (pa) |a| fmt("{d} ft", .{ a }) else "not available" }));
    indent(&out, fmt("density altitude: {s}", .{ if (da) |a| fmt("{d} ft", .{ a }) else "not available" }));
    if (s.get(.wind) != null and s.get(.wind).?.direction > 0) {
        const w = s.get(.wind).?;
        var usable: std.ArrayList([]const u8) = .empty;
        var preferred: []const u8 = "none";
        var best: i64 = -1000000;
        for (station.runways) |runway| {
            const mean = component(w.direction, runway.heading, w.speed);
            const gust = if (w.gust >= 0) component(w.direction, runway.heading, w.gust) else mean;
            var phrase = componentPhrase(mean);
            if (w.gust >= 0) phrase = fmt("{s}; gusts {s}", .{ phrase, componentPhrase(gust) });
            indent(&out, fmt("runway {s}: {s}", .{ runway.name, phrase }));
            if (abs(gust[1]) <= e.crosswind and - gust[0] <= e.tailwind) {
                append([]const u8, &usable, runway.name);
                if (mean[0] > best) {
                    best = mean[0];
                    preferred = runway.name;
                }
            }
        }
        indent(&out, fmt("usable runways: {s}", .{ if (usable.items.len == 0) @as([]const u8, "none") else join(usable.items, " ") }));
        indent(&out, fmt("preferred runway: {s}", .{ preferred }));
    } else indent(&out, "runway wind: not computed");
    if (g.eq(r.kind, "SPECI")) indent(&out, fmt("speci check: {s}", .{ r.speci }));
    return out.value();
}

fn counts(c: [4]i64) []const u8 {
    return fmt("VFR {d}, MVFR {d}, IFR {d}, LIFR {d}", .{ c[0], c[1], c[2], c[3] });
}

fn timeline(e: Engine, r: Report) []const u8 {
    var out: Text = .{};
    out.line(fmt("TAF {s} issued {s} valid {s} to {s}", .{ e.stations[r.station].code, stamp(e.calendar, r.time), stamp(e.calendar, r.start), stamp(e.calendar, r.end) }));
    var c = [_]i64 { 0 } ** 4;
    for (r.hours) |hour| {
        out.add(fmt("{s} {s}", .{ stamp(e.calendar, hour.time), tokens(hour.prevailing) }));
        for (hour.temporary) |temp| out.add(fmt(" | {s} {s}", .{ temp.kind, tokens(temp.state) }));
        out.add("\n");
        c[category(hour.prevailing)] += 1;
    }
    out.line(fmt("summary: {s}", .{ counts(c) }));
    return out.value();
}

fn tableRow(out: *Text, label: []const u8, values: []const []const u8) void {
    out.add(label);
    out.add(repeatByte(' ', 8 - label.len));
    for (values) |value| {
        if (value.len < 6) out.add(repeatByte(' ', 6 - value.len));
        out.add(value);
    }
    out.add("\n");
}

fn extremeValue(r: Report, kind: usize) ?i64 {
    return switch (kind) {
        0, 1 => if (r.state.get(.temperature)) |w| w.temperature else null, 2 => if (r.state.get(.wind)) |w| if (w.gust >= 0) w.gust else w.speed else null, 3 => ceiling(r.state), else => if (r.state.get(.visibility)) |_| 0 else null
    };
}

fn verification(e: Engine, station: usize, reports: []const Report, forecasts: []const v.Forecast) []const u8 {
    var out: Text = .{};
    const s = e.stations[station];
    out.line(fmt("station {s} ({s})", .{ s.code, s.name }));
    var metars: i64 = 0;
    var specis: i64 = 0;
    var observed = [_]i64 { 0 } ** 4;
    var observations: std.ArrayList(Report) = .empty;
    for (reports) |r| {
        if (r.station == station and !g.eq(r.kind, "TAF")) {
            append(Report, &observations, r);
            if (g.eq(r.kind, "METAR")) metars += 1 else specis += 1;
            observed[category(r.state)] += 1;
        }
    }
    out.line(fmt("reports: METAR {d}, SPECI {d}", .{ metars, specis }));
    out.line(fmt("observed categories: {s}", .{ counts(observed) }));
    const labels = [_][]const u8 { "lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility" };
    for (labels, 0..) |label, k| {
        var best: ?Report = null;
        var value: i64 = 0;
        for (observations.items) |r| {
            const a = extremeValue(r, k) orelse continue;
            var better = best == null;
            if (best) |b| {
                if (k == 4) {
                    const x = r.state.get(.visibility).?;
                    const y = b.state.get(.visibility).?;
                    const p = u.miles(x.name, x.whole_or_meters, x.numerator, x.denominator);
                    const q = u.miles(y.name, y.whole_or_meters, y.numerator, y.denominator);
                    better = p.p * q.q < q.p * p.q;
                } else better = if (k == 1 or k == 2) a > value else a < value;
            }
            if (better) {
                best = r;
                value = a;
            }
        }
        if (best) |r| {
            const phrase = if (k < 2) fmt("{d} C", .{ value }) else if (k == 2) windPhrase(r.state.get(.wind).?) else if (k == 3) fmt("{d} ft", .{ value }) else visibilityPhrase(r.state.get(.visibility).?);
            out.line(fmt("{s}: {s} at {s}", .{ label, phrase, stamp(e.calendar, r.time) }));
        } else out.line(fmt("{s}: not available", .{ label }));
    }
    var stats: v.Stats = .{};
    var amendments: Text = .{};
    for (observations.items) |r| {
        const h = r.time - @mod(r.time, 60);
        const actual = category(r.state);
        for (forecasts) |f| {
            if (v.covers(f, station, r.time)) {
                const ix: usize = @intCast(@divFloor(h - f.start, 60));
                const bucket = ix / 6;
                stats.bucket_pairs[bucket] += 1;
                if (category(f.hours[ix].prevailing) == actual) stats.bucket_hits[bucket] += 1;
            }
        }
        const ix = v.select(forecasts, station, r.time) orelse {
            stats.no_forecast += 1;
            continue;
        };
        const f = forecasts[ix];
        const hour = f.hours[@intCast(@divFloor(h - f.start, 60))];
        const forecast = category(hour.prevailing);
        var temporary_hit = actual == forecast;
        for (hour.temporary) |temp| {
            if (category(temp.state) == actual) temporary_hit = true;
        }
        stats.add(forecast, actual, temporary_hit);
        var reasons: std.ArrayList([]const u8) = .empty;
        if (!temporary_hit) append([]const u8, &reasons, fmt("category {s}, forecast {s}", .{ v.categories[actual], v.categories[forecast] }));
        if (windChanges(hour.prevailing.get(.wind), r.state.get(.wind), 60).len > 0) append([]const u8, &reasons, fmt("wind {s}, forecast {s}", .{ windCode(r.state.get(.wind).?), windCode(hour.prevailing.get(.wind).?) }));
        if (reasons.items.len > 0) amendments.line(fmt("amendment {s}: {s}", .{ stamp(e.calendar, r.time), join(reasons.items, "; ") }));
    }
    out.line(fmt("verified: {d}", .{ stats.total }));
    out.line(fmt("no forecast: {d}", .{ stats.no_forecast }));
    tableRow(&out, "forecast", &.{ "VFR", "MVFR", "IFR", "LIFR", "total" });
    for (v.categories, 0..) |cat, i| {
        var cells: [5][]const u8 = undefined;
        for (0..4) |j| cells[j] = fmt("{d}", .{ stats.table[i][j] });
        cells[4] = fmt("{d}", .{ stats.rows[i] });
        tableRow(&out, cat, &cells);
    }
    var total: [5][]const u8 = undefined;
    for (0..4) |i| total[i] = fmt("{d}", .{ stats.columns[i] });
    total[4] = fmt("{d}", .{ stats.total });
    tableRow(&out, "total", &total);
    out.line(fmt("hit rate: {s}", .{ fraction(stats.hits, stats.total) }));
    out.line(fmt("hit rate with temporary groups: {s}", .{ fraction(stats.temporary_hits, stats.total) }));
    const skill = stats.skill();
    out.line(fmt("heidke skill score: {s}", .{ fraction(skill[0], skill[1]) }));
    for (v.categories, 0..) |cat, i| {
        const pod = stats.pod(i);
        const far = stats.far(i);
        out.line(fmt("{s}: pod {s}, far {s}", .{ cat, fraction(pod[0], pod[1]), fraction(far[0], far[1]) }));
    }
    for (0..5) |i| out.line(fmt("hours {d}-{d}: {s}", .{ i * 6, i * 6 + 5, fraction(stats.bucket_hits[i], stats.bucket_pairs[i]) }));
    out.add(amendments.value());
    return out.value();
}

fn problemLess(_: void, a: g.Problem, b: g.Problem) bool {
    return a.report < b.report or (a.report == b.report and a.position < b.position);
}

pub fn main(init: std.process.Init) !void {
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const cwd = std.Io.Dir.cwd();
    const station_text = try cwd.readFileAlloc(init.io, "input/stations.txt", alloc(), .unlimited);
    const params_text = try cwd.readFileAlloc(init.io, "input/params.txt", alloc(), .unlimited);
    const report_text = try cwd.readFileAlloc(init.io, "input/reports.txt", alloc(), .unlimited);
    var stations: std.ArrayList(g.Station) = .empty;
    for (lines(station_text)) |line| {
        const w = words(line, ' ');
        var runways: std.ArrayList(g.Runway) = .empty;
        for (words(w[2], ',')) |entry| {
            const rw = words(entry, '/');
            append(g.Runway, &runways, .{.name = rw[0], .heading = g.number(rw[1]) });
        }
        append(g.Station, &stations, .{.code = w[0], .elevation = g.number(w[1]), .runways = runways.items, .name = join(w[3..], " ") });
    }
    const p = lines(params_text);
    var engine: Engine = .{.calendar = .{.year = g.number(words(p[0], ' ') [1]), .month = g.number(words(p[1], ' ') [1]) }, .stations = stations.items, .crosswind = g.number(words(p[2], ' ') [1]), .tailwind = g.number(words(p[3], ' ') [1]) };
    var raw: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    for (lines(report_text)) |line| {
        if (line[0] != ' ') append(std.ArrayList([]const u8), &raw, .empty);
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        while (it.next()) |word| append([]const u8, &raw.items[raw.items.len - 1], word);
    }
    var reports: std.ArrayList(Report) = .empty;
    var forecasts: std.ArrayList(v.Forecast) = .empty;
    var decoded_out: Text = .{};
    var categories_out: Text = .{};
    var timeline_out: Text = .{};
    var verification_out: Text = .{};
    var errors_out: Text = .{};
    categories_out.line("station,time,ceiling,visibility,category");
    for (raw.items, 0..) |item, i| {
        var report = engine.header(i + 1, item.items) orelse continue;
        engine.decode(&report, item.items, reports.items);
        append(Report, &reports, report);
        decoded_out.block(decoded(engine, report));
        if (g.eq(report.kind, "TAF")) {
            append(v.Forecast, &forecasts, .{.station = report.station, .number = report.number, .issued = report.time, .start = report.start, .end = report.end, .hours = report.hours });
            timeline_out.block(timeline(engine, report));
        } else {
            const state = report.state;
            const visibility = if (state.get(.visibility)) |w| fmt("{s}{d}", .{ w.qualifier, u.meters(w.name, w.whole_or_meters, w.numerator, w.denominator) }) else "NONE";
            categories_out.line(fmt("{s},{s},{s},{s},{s}", .{ engine.stations[report.station].code, stamp(engine.calendar, report.time), if (ceiling(state)) |h| fmt("{d}", .{ h }) else "NONE", visibility, v.categories[category(state)] }));
        }
    }
    for (words(p[4], ' ') [1..]) |code| {
        for (engine.stations, 0..) |station, i| {
            if (g.eq(station.code, code)) verification_out.block(verification(engine, i, reports.items, forecasts.items));
        }
    }
    std.mem.sort(g.Problem, engine.errors.items, {}, problemLess);
    for (engine.errors.items) |problem| errors_out.line(fmt("report {d} word {d}: {s}{s}", .{ problem.report, problem.position, problem.reason, if (problem.text) |text| fmt(" \"{s}\"", .{ text }) else "" }));
    try cwd.createDirPath(init.io, "output");
    const names = [_][]const u8 { "decoded.txt", "categories.csv", "taf_timeline.txt", "verification.txt", "errors.txt" };
    const outputs = [_]Text { decoded_out, categories_out, timeline_out, verification_out, errors_out };
    for (names, outputs) |name, output| {
        try cwd.writeFile(init.io, .{.sub_path = fmt("output/{s}", .{ name }), .data = output.value() });
    }
}
