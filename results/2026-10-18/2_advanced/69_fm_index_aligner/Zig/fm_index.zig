const std = @import("std");
const d = @import("sequence_io.zig");
const suffix = @import("suffix_array.zig");
pub const Interval = struct {
    lower: usize,
    upper: usize,
    pub fn empty(self: Interval) bool {
        return self.lower >= self.upper;
    }
};
pub const Located = struct { position: usize, steps: usize };
pub const Index = struct {
    size: usize,
    interval: usize,
    bwt: []const u8,
    C: [6]usize = [_]usize{0} ** 6,
    checkpoints: []const [6]usize,
    samples: ?[]const ?usize = null,
    sample_count: usize = 0,
    pub fn init(text: []const u8, suffixes: []const usize, occurrence_interval: usize, sample_interval: ?usize) Index {
        const bwt = d.alloc(u8, text.len);
        const checkpoints = d.alloc([6]usize, text.len / occurrence_interval + 1);
        var out: Index = .{ .size = text.len, .interval = occurrence_interval, .bwt = bwt, .checkpoints = checkpoints };
        var frequencies = [_]usize{0} ** 6;
        for (text) |character| frequencies[suffix.symbolNumber(character)] += 1;
        var offset: usize = 0;
        for (frequencies, 0..) |count, i| {
            out.C[i] = offset;
            offset += count;
        }
        for (suffixes, bwt) |position, *character| character.* = text[if (position == 0) text.len - 1 else position - 1];
        if (sample_interval) |step| {
            const samples = d.alloc(?usize, text.len);
            @memset(samples, null);
            for (suffixes, 0..) |position, row| if (position % step == 0) {
                samples[row] = position;
                out.sample_count += 1;
            };
            out.samples = samples;
        }
        var counts = [_]usize{0} ** 6;
        checkpoints[0] = counts;
        var checkpoint: usize = 1;
        for (bwt, 1..) |character, i| {
            counts[suffix.symbolNumber(character)] += 1;
            if (i % occurrence_interval == 0) {
                checkpoints[checkpoint] = counts;
                checkpoint += 1;
            }
        }
        return out;
    }
    pub fn occurrence(self: Index, symbol: u8, position: usize) usize {
        const checkpoint = position / self.interval;
        var count = self.checkpoints[checkpoint][suffix.symbolNumber(symbol)];
        for (self.bwt[checkpoint * self.interval .. position]) |character| count += @intFromBool(character == symbol);
        return count;
    }
    pub fn lf(self: Index, row: usize) usize {
        const symbol = self.bwt[row];
        return self.C[suffix.symbolNumber(symbol)] + self.occurrence(symbol, row);
    }
    pub fn extend(self: Index, interval: Interval, base: u8) Interval {
        if (base == 'N') return .{ .lower = 0, .upper = 0 };
        const start = self.C[suffix.symbolNumber(base)];
        return .{ .lower = start + self.occurrence(base, interval.lower), .upper = start + self.occurrence(base,
             interval.upper) };
    }
    pub fn backwardSearch(self: Index, sequence: []const u8) Interval {
        var out: Interval = .{ .lower = 0, .upper = self.size };
        var i = sequence.len;
        while (i > 0) {
            i -= 1;
            out = self.extend(out, sequence[i]);
            if (out.empty()) break;
        }
        return out;
    }
    pub fn locate(self: Index, start: usize) Located {
        const samples = self.samples.?;
        var row = start;
        var steps: usize = 0;
        while (samples[row] == null) {
            row = self.lf(row);
            steps += 1;
        }
        return .{ .position = samples[row].? + steps, .steps = steps };
    }
    pub fn inverse(self: Index) []const u8 {
        const out = d.alloc(u8, self.size);
        out[self.size - 1] = '$';
        var row: usize = 0;
        var i = self.size - 1;
        while (i > 0) {
            i -= 1;
            out[i] = self.bwt[row];
            row = self.lf(row);
        }
        return out;
    }
};
