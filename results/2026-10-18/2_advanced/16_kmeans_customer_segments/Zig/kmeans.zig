const std = @import("std");
const D = @import("transactions.zig");
pub const Point = [6]f64;
pub const Points = struct { values: []const Point, dimensions: usize = 6 };
pub const Lloyd = struct { labels: [400]usize = undefined, centers: [10]Point = undefined, iterations: usize = 0, reseeds: usize = 0, converged: bool = false, sse: f64 = 0 };
pub fn squaredDistance(first: Point, second: Point, dimensions: usize) f64 {
    var total: f64 = 0;
    for (0..dimensions) |f| { const difference = first[f] - second[f]; total += difference * difference; }
    return total;
}
pub fn meanPoint(points: Points) Point {
    var result = [_]f64{0} ** 6;
    for (points.values) |point| { for (0..points.dimensions) |f| result[f] += point[f]; }
    for (0..points.dimensions) |f| result[f] /= D.real(points.values.len);
    return result;
}
pub fn assign(points: Points, centers: []const Point, labels: []usize, errors: []f64) void {
    for (points.values, 0..) |point, i| {
        var best: usize = 0;
        var distance = squaredDistance(point, centers[0], points.dimensions);
        for (centers[1..], 1..) |center, j| {
            const trial = squaredDistance(point, center, points.dimensions);
            if (trial < distance) { best = j; distance = trial; }
        }
        labels[i] = best;
        errors[i] = distance;
    }
}
pub fn clusterSizes(labels: []const usize, k: usize) [10]usize {
    var result = [_]usize{0} ** 10;
    for (labels) |label| result[label] += 1;
    _ = k;
    return result;
}
pub fn clusterCenter(points: Points, labels: []const usize, group: usize) Point {
    var result = [_]f64{0} ** 6;
    var count: usize = 0;
    for (points.values, labels) |point, label| {
        if (label != group) continue;
        count += 1;
        for (0..points.dimensions) |f| result[f] += point[f];
    }
    for (0..points.dimensions) |f| result[f] /= D.real(count);
    return result;
}
pub fn clusterCenters(points: Points, labels: []const usize, centers: []Point) void {
    for (centers, 0..) |*center, j| center.* = clusterCenter(points, labels, j);
}
pub fn refill(labels: []usize, errors: []f64, k: usize) usize {
    var sizes = clusterSizes(labels, k);
    var reseeds: usize = 0;
    for (0..k) |j| {
        if (sizes[j] > 0) continue;
        var chosen: ?usize = null;
        for (labels, 0..) |label, i| { if (sizes[label] >= 2 and (chosen == null or errors[i] > errors[chosen.?])) chosen = i; }
        sizes[labels[chosen.?]] -= 1;
        sizes[j] += 1;
        labels[chosen.?] = j;
        errors[chosen.?] = 0;
        reseeds += 1;
    }
    return reseeds;
}
pub fn sumSquared(points: Points, labels: []const usize, centers: []const Point) f64 {
    var total: f64 = 0;
    for (points.values, labels) |point, label| total += squaredDistance(point, centers[label], points.dimensions);
    return total;
}
pub fn lloyd(points: Points, initial: []const Point, limit: usize) Lloyd {
    var result: Lloyd = .{};
    const labels = result.labels[0..points.values.len];
    const centers = result.centers[0..initial.len];
    var error_storage: [400]f64 = undefined;
    const errors = error_storage[0..points.values.len];
    assign(points, initial, labels, errors);
    while (result.iterations < limit) {
        result.reseeds += refill(labels, errors, initial.len);
        clusterCenters(points, labels, centers);
        result.iterations += 1;
        var storage: [400]usize = undefined;
        const updated = storage[0..labels.len];
        assign(points, centers, updated, errors);
        result.converged = std.mem.eql(usize, labels, updated);
        @memcpy(labels, updated);
        if (result.converged) break;
    }
    result.reseeds += refill(labels, errors, initial.len);
    clusterCenters(points, labels, centers);
    result.sse = sumSquared(points, labels, centers);
    return result;
}
