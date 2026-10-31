const std = @import("std");
const p = @import("pgm_reader.zig");
pub const Histogram = struct {
    pixels: i64, maxval: usize,
    counts: [256]i64 = [_]i64{0} ** 256,
    below: [256]i64 = [_]i64{0} ** 256,
    sums: [256]i64 = [_]i64{0} ** 256,
    minimum: usize = 0, maximum: usize = 0, median: usize = 0, mode: usize = 0, levels: usize = 0,
    total: i64 = 0, bin_width: usize = 0, bins: [8]i64 = [_]i64{0} ** 8, bin_count: usize = 0,
    pub fn init(image: p.Image) Histogram {
        var result: Histogram = .{ .pixels = p.n(image.pixels.len), .maxval = image.maxval, .minimum = image.maxval };
        for (image.pixels) |value| result.counts[p.u(value)] += 1;
        var count: i64 = 0;
        var sum: i64 = 0;
        var median_found = false;
        for (0..image.maxval + 1) |value| {
            count += result.counts[value];
            sum += p.n(value) * result.counts[value];
            result.below[value] = count;
            result.sums[value] = sum;
            if (result.counts[value] > 0) {
                result.minimum = @min(result.minimum, value);
                result.maximum = value;
                result.levels += 1;
            }
            if (!median_found and 2 * count >= result.pixels) { result.median = value; median_found = true; }
            if (result.counts[value] > result.counts[result.mode]) result.mode = value;
        }
        result.total = sum;
        result.bin_width = (image.maxval + 8) / 8;
        var start: usize = 0;
        while (start <= image.maxval) : (start += result.bin_width) {
            for (start..@min(start + result.bin_width, image.maxval + 1)) |value| result.bins[result.bin_count] += result.counts[value];
            result.bin_count += 1;
        }
        return result;
    }
    pub fn split(self: *const Histogram, cutoff: usize) Candidate {
        const below = self.below[cutoff];
        const sum_below = self.sums[cutoff];
        const above = self.pixels - below;
        const sum_above = self.total - sum_below;
        return .{ .cutoff = cutoff, .below = below, .above = above, .sum_below = sum_below, .sum_above = sum_above,
            .numerator = sum_below * sum_below * above + sum_above * sum_above * below, .denominator = below * above };
    }
};
pub const Candidate = struct { cutoff: usize, below: i64, above: i64, sum_below: i64, sum_above: i64, numerator: i64, denominator: i64 };
pub const Otsu = struct { cutoff: usize, upper: usize, candidates: []Candidate };
fn ranked(_: void, first: Candidate, second: Candidate) bool {
    const first_q = @divFloor(first.numerator, first.denominator);
    const second_q = @divFloor(second.numerator, second.denominator);
    if (first_q != second_q) return first_q > second_q;
    const left = @mod(first.numerator, first.denominator) * second.denominator;
    const right = @mod(second.numerator, second.denominator) * first.denominator;
    return if (left != right) left > right else first.cutoff < second.cutoff;
}
pub fn otsu(hist: *const Histogram) Otsu {
    var candidates: std.ArrayList(Candidate) = .empty;
    for (0..hist.maxval) |cutoff| if (hist.counts[cutoff] > 0 and hist.below[cutoff] < hist.pixels) { p.append(Candidate, &candidates, hist.split(cutoff)); };
    std.mem.sort(Candidate, candidates.items, {}, ranked);
    const cutoff = if (candidates.items.len > 0) candidates.items[0].cutoff else hist.minimum;
    var upper = cutoff;
    if (candidates.items.len > 0) {
        var following = cutoff + 1;
        while (hist.counts[following] == 0) : (following += 1) {}
        upper = following - 1;
    }
    return .{ .cutoff = cutoff, .upper = upper, .candidates = candidates.items };
}
pub const Isodata = struct { cutoff: usize, iterations: usize };
pub fn isodata(hist: *const Histogram) Isodata {
    var cutoff = p.u(@divFloor(hist.total, hist.pixels));
    var iterations: usize = 0;
    while (true) {
        const values = hist.split(cutoff);
        if (values.below == 0 or values.above == 0) break;
        const following = p.u(@divFloor(values.sum_below * values.above + values.sum_above * values.below, 2 * values.below * values.above));
        iterations += 1;
        if (following == cutoff) break;
        cutoff = following;
        if (iterations == 100) break;
    }
    return .{ .cutoff = cutoff, .iterations = iterations };
}
