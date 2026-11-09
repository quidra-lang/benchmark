const std = @import("std");
const D = @import("dataset.zig");
const Minstd = @import("minstd.zig").Minstd;
pub fn sum(values: []const i64) i64 { var result: i64 = 0; for (values) |value| result += value; return result; }
pub fn sequentialSum(values: []const f64) f64 { var result: f64 = 0; for (values) |value| result += value; return result; }
pub fn mean(values: []const i64) f64 { return D.real(sum(values)) / D.real(100 * D.n(values.len)); }
pub fn doubledMedian(values: []const i64) i64 {
    var storage: [6400]i64 = undefined;
    const ordered = storage[0..values.len];
    @memcpy(ordered, values);
    std.mem.sort(i64, ordered, {}, std.sort.asc(i64));
    return ordered[(values.len - 1) / 2] + ordered[values.len / 2];
}
pub fn median(values: []const i64) f64 { return D.real(doubledMedian(values)) / 200; }
pub fn trimmedMean(values: []const i64) f64 {
    var storage: [80]i64 = undefined;
    const ordered = storage[0..values.len];
    @memcpy(ordered, values);
    std.mem.sort(i64, ordered, {}, std.sort.asc(i64));
    const trim = values.len / 10;
    return D.real(sum(ordered[trim .. values.len - trim])) / D.real(100 * D.n(values.len - 2 * trim));
}
pub const Moments = struct { sd: f64, second: f64, third: f64, fourth: f64 };
pub fn moments(values: []const i64) Moments {
    const center = mean(values);
    var second: f64 = 0;
    var third: f64 = 0;
    var fourth: f64 = 0;
    for (values) |value| {
        const difference = D.real(value) / 100 - center;
        second += difference * difference;
        third += difference * difference * difference;
        fourth += difference * difference * difference * difference;
    }
    return .{ .sd = @sqrt(second / D.real(values.len - 1)), .second = second / D.real(values.len), .third = third / D.real(values.len), .fourth = fourth / D.real(values.len) };
}
pub fn sd(values: []const i64) f64 { return moments(values).sd; }
pub fn mad(values: []const i64) f64 {
    const center = doubledMedian(values);
    var storage: [80]i64 = undefined;
    for (values, 0..) |value, i| storage[i] = D.abs(2 * value - center);
    return D.real(doubledMedian(storage[0..values.len])) / 400;
}
pub fn quantileNumerator(values: []const i64, percent: usize) i64 {
    var storage: [80]i64 = undefined;
    const ordered = storage[0..values.len];
    @memcpy(ordered, values);
    std.mem.sort(i64, ordered, {}, std.sort.asc(i64));
    const position = (values.len - 1) * percent;
    const index = position / 100;
    const fraction = D.n(position % 100);
    return 100 * ordered[index] + (if (fraction != 0) fraction * (ordered[index + 1] - ordered[index]) else 0);
}
pub fn winsorized(values: []const i64, storage: []i64) []const i64 {
    var ordered_storage: [80]i64 = undefined;
    const ordered = ordered_storage[0..values.len];
    @memcpy(ordered, values);
    std.mem.sort(i64, ordered, {}, std.sort.asc(i64));
    const trim = values.len / 10;
    for (values, 0..) |value, i| storage[i] = @min(@max(value, ordered[trim]), ordered[values.len - trim - 1]);
    return storage[0..values.len];
}
pub fn meanDifference(first: []const i64, second: []const i64) f64 {
    const numerator = D.n(second.len) * sum(first) - D.n(first.len) * sum(second);
    return D.real(numerator) / D.real(100 * D.n(first.len) * D.n(second.len));
}
pub fn medianRatio(first: []const i64, second: []const i64) f64 { return D.real(doubledMedian(first)) / D.real(doubledMedian(second)); }
pub fn hodgesLehmann(first: []const i64, second: []const i64) f64 {
    var storage: [6400]i64 = undefined;
    var count: usize = 0;
    for (first) |x| { for (second) |y| { storage[count] = x - y; count += 1; } }
    return D.real(doubledMedian(storage[0..count])) / 200;
}
pub fn pooledSd(first: []const i64, second: []const i64) f64 {
    const x = sd(first);
    const y = sd(second);
    return @sqrt((D.real(first.len - 1) * x * x + D.real(second.len - 1) * y * y) / D.real(first.len + second.len - 2));
}
pub fn cohenD(first: []const i64, second: []const i64) f64 { return meanDifference(first, second) / pooledSd(first, second); }
pub fn correlation(first: []const i64, second: []const i64) f64 {
    const x = mean(first);
    const y = mean(second);
    var cross: f64 = 0;
    var squares_x: f64 = 0;
    var squares_y: f64 = 0;
    for (first, second) |a, b| {
        const e = D.real(a) / 100 - x;
        const f = D.real(b) / 100 - y;
        cross += e * f;
        squares_x += e * e;
        squares_y += f * f;
    }
    return cross / @sqrt(squares_x * squares_y);
}
pub fn groupStatistics(values: []const i64) [4]f64 { return .{ mean(values), median(values), trimmedMean(values), sd(values) }; }
pub fn pairStatistics(first: []const i64, second: []const i64) [4]f64 { return .{ meanDifference(first, second), medianRatio(first, second), hodgesLehmann(first, second), cohenD(first, second) }; }
pub fn resampleIndices(generator: *Minstd, size: usize, result: []usize) void { for (result) |*index| index.* = generator.below(size); }
pub fn ordinaryIndices(generator: *Minstd, size: usize, count: usize) []usize {
    const result = D.alloc(usize, size * count);
    for (0..count) |r| resampleIndices(generator, size, result[r * size .. (r + 1) * size]);
    return result;
}
pub fn balancedIndices(generator: *Minstd, size: usize, count: usize) []usize {
    const result = D.alloc(usize, size * count);
    for (result, 0..) |*index, i| index.* = i % size;
    generator.shuffle(result);
    return result;
}
pub fn without(values: []const i64, index: usize, storage: []i64) []const i64 {
    @memcpy(storage[0..index], values[0..index]);
    @memcpy(storage[index .. values.len - 1], values[index + 1 ..]);
    return storage[0 .. values.len - 1];
}
pub fn chosen(values: []const i64, indices: []const usize, storage: []i64) []const i64 {
    for (indices, 0..) |index, i| storage[i] = values[index];
    return storage[0..indices.len];
}
pub const Spread = struct { average: f64, se: f64 };
pub fn meanAndSe(values: []const f64) Spread {
    const average = sequentialSum(values) / D.real(values.len);
    var squares: f64 = 0;
    for (values) |value| { const difference = value - average; squares += difference * difference; }
    return .{ .average = average, .se = @sqrt(squares / D.real(values.len - 1)) };
}
pub fn phi(value: f64) f64 {
    if (value < 0) return 1 - phi(-value);
    const eta = 1 / (1 + 0.2316419 * value);
    const psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))));
    return 1 - 0.3989422804014327 * @exp(-(value * value) / 2) * psi;
}
pub fn phiInverse(probability: f64) f64 {
    if (probability > 0.5) return -phiInverse(1 - probability);
    const eta = @sqrt(-2 * @log(probability));
    const numerator = 2.515517 + eta * (0.802853 + eta * 0.010328);
    const denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308));
    return -(eta - numerator / denominator);
}
