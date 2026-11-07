const std = @import("std");
const c = @import("dataset.zig");
pub fn riskSize(subjects: c.Subjects, time: i64) i64 {
    var count: i64 = 0;
    for (subjects) |subject| count += @intFromBool(subject.time >= time);
    return count;
}
pub fn eventCount(subjects: c.Subjects, time: i64) i64 {
    var count: i64 = 0;
    for (subjects) |subject| count += @intFromBool(subject.time == time and subject.event == 1);
    return count;
}
pub fn eventTimes(subjects: c.Subjects) []const i64 {
    var out: std.ArrayList(i64) = .empty;
    for (subjects) |subject| if (subject.event == 1) c.append(i64, &out, subject.time);
    std.mem.sort(i64, out.items, {}, std.sort.asc(i64));
    var count: usize = 0;
    for (out.items) |value| if (count == 0 or value != out.items[count - 1]) {
        out.items[count] = value;
        count += 1;
    };
    return out.items[0..count];
}
pub const KMRow = struct { time: i64 = 0, risk: i64 = 0, events: i64 = 0, censored: i64 = 0, survival: f64 = 1,
     std_err: ?f64 = 0, lower: ?f64 = null, upper: ?f64 = null, hazard: f64 = 0, hazard_se: f64 = 0 };
pub fn kaplanMeier(subjects: c.Subjects) []const KMRow {
    const times = eventTimes(subjects);
    var out: std.ArrayList(KMRow) = .empty;
    var survival: f64 = 1;
    var greenwood: f64 = 0;
    var hazard: f64 = 0;
    var variance: f64 = 0;
    var defined = true;
    for (times, 0..) |time, i| {
        var row: KMRow = .{ .time = time, .risk = riskSize(subjects, time), .events = eventCount(subjects, time) };
        for (subjects) |subject| if (subject.event == 0 and subject.time >= time and (i + 1 == times.len or subject.time < times[i + 1])) {
            row.censored += 1;
        };
        survival = survival * (c.f(row.risk - row.events) / c.f(row.risk));
        row.survival = survival;
        if (row.risk == row.events) defined = false;
        if (defined) {
            greenwood += c.f(row.events) / c.f(row.risk * (row.risk - row.events));
            row.std_err = survival * @sqrt(greenwood);
            const logarithm = @log(survival);
            const omega = c.normal_z * @sqrt(greenwood) / (-logarithm);
            row.lower = @exp(logarithm * @exp(omega));
            row.upper = @exp(logarithm * @exp(-omega));
        } else row.std_err = null;
        hazard += c.f(row.events) / c.f(row.risk);
        variance += c.f(row.events) / c.f(row.risk * row.risk);
        row.hazard = hazard;
        row.hazard_se = @sqrt(variance);
        c.append(KMRow, &out, row);
    }
    return out.items;
}
pub fn rowAt(rows: []const KMRow, time: i64) KMRow {
    var out: KMRow = .{};
    for (rows) |row| {
        if (row.time > time) break;
        out = row;
    }
    return out;
}
pub const LifeRow = struct { a: i64, b: i64, risk: i64, events: i64 = 0, withdrawn: i64 = 0, exposure2: i64 = 0,
     probability: f64 = 0, survival: f64 = 0, std_err: f64 = 0, hazard: f64 = 0 };
pub fn lifeTable(subjects: c.Subjects, width: i64, intervals: usize) []const LifeRow {
    var out: std.ArrayList(LifeRow) = .empty;
    var survival: f64 = 1;
    var greenwood: f64 = 0;
    for (0..intervals) |i| {
        var row: LifeRow = .{ .a = c.n(i) * width, .b = c.n(i + 1) * width, .risk = riskSize(subjects, c.n(i) * width) };
        for (subjects) |subject| if (subject.time >= row.a and subject.time < row.b) {
            if (subject.event == 1) row.events += 1 else row.withdrawn += 1;
        };
        row.exposure2 = 2 * row.risk - row.withdrawn;
        const exposure = row.exposure2;
        const d = row.events;
        row.probability = c.f(2 * d) / c.f(exposure);
        survival = survival * (c.f(exposure - 2 * d) / c.f(exposure));
        row.survival = survival;
        greenwood += c.f(4 * d) / c.f(exposure * (exposure - 2 * d));
        row.std_err = survival * @sqrt(greenwood);
        row.hazard = c.f(2000 * d) / c.f(width * (exposure - d));
        c.append(LifeRow, &out, row);
    }
    return out.items;
}
