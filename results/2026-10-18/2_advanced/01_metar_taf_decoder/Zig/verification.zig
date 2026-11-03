const t = @import("taf.zig");
pub const categories = [_][]const u8 { "VFR", "MVFR", "IFR", "LIFR" };

pub const Forecast = struct {
    station: usize,
    number: usize,
    issued: i64,
    start: i64,
    end: i64,
    hours: []const t.Hour
};

pub fn covers(f: Forecast, station: usize, time: i64) bool {
    const h = time - @mod(time, 60);
    return f.station == station and f.issued <= time and f.start <= h and h < f.end;
}

pub fn select(fs: []const Forecast, station: usize, time: i64) ?usize {
    var best: ?usize = null;
    for (fs, 0..) |f, i| {
        if (covers(f, station, time) and (best == null or f.issued > fs[best.?].issued or (f.issued == fs[best.?].issued and f.number > fs[best.?].number))) best = i;
    }
    return best;
}

pub const Stats = struct {
    table: [4][4]i64 = .{.{ 0 } ** 4 } ** 4,
    rows: [4]i64 = .{ 0 } ** 4,
    columns: [4]i64 = .{ 0 } ** 4,
    total: i64 = 0,
    hits: i64 = 0,
    temporary_hits: i64 = 0,
    no_forecast: i64 = 0,
    bucket_hits: [5]i64 = .{ 0 } ** 5,
    bucket_pairs: [5]i64 = .{ 0 } ** 5,
    pub fn add(s: *Stats, forecast: usize, observed: usize, temporary: bool) void {
        s.table[forecast][observed] += 1;
        s.rows[forecast] += 1;
        s.columns[observed] += 1;
        s.total += 1;
        if (forecast == observed) s.hits += 1;
        if (temporary) s.temporary_hits += 1;
    }
    pub fn skill(s: Stats) [2]i64 {
        var expected: i64 = 0;
        for (0..4) |i| expected += s.rows[i] *s.columns[i];
        return .{ s.total * s.hits - expected, s.total * s.total - expected };
    }
    pub fn pod(s: Stats, i: usize) [2]i64 {
        return .{ s.table[i][i], s.columns[i] };
    }
    pub fn far(s: Stats, i: usize) [2]i64 {
        return .{ s.rows[i] - s.table[i][i], s.rows[i] };
    }
};
