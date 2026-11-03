const d = @import("day_rules.zig");
const std = @import("std");
pub const Period = struct {
    start: i64,
    offset: i64,
    dst: bool,
    abbreviation: []const u8,
    pub fn sameState(first: Period, second: Period) bool { return first.offset == second.offset and first.dst == second.dst and std.mem.eql(u8, first.abbreviation, second.abbreviation); }
};
pub const Candidates = struct { indices: [2]usize = undefined, count: usize = 0 };
pub const Timeline = struct {
    periods: []const Period,
    pub fn indexAt(self: Timeline, time: i64) usize {
        var low: usize = 0;
        var high = self.periods.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.periods[middle].start <= time) low = middle + 1 else high = middle;
        }
        return low - 1;
    }
    pub fn endOf(self: Timeline, index: usize) i64 { return if (index + 1 < self.periods.len) self.periods[index + 1].start else d.pos_infinity; }
    pub fn candidates(self: Timeline, local: i64) Candidates {
        var result: Candidates = .{};
        const first = self.indexAt(local - 57600);
        const last = self.indexAt(local + 57600);
        for (first..last + 1) |i| {
            const time = local - self.periods[i].offset;
            if (self.periods[i].start <= time and time < self.endOf(i)) { result.indices[result.count] = i; result.count += 1; }
        }
        return result;
    }
    pub fn skippingTransition(self: Timeline, local: i64) usize {
        const first = self.indexAt(local - 57600);
        const last = self.indexAt(local + 57600);
        for (first..last + 1) |i| {
            if (i == 0) continue;
            const time = self.periods[i].start;
            if (time + self.periods[i - 1].offset <= local and local < time + self.periods[i].offset) return i;
        }
        unreachable;
    }
};
