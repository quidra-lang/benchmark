const c = @import("dataset.zig");
pub fn distance2(a: c.Vec, b: c.Vec) f64 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    return x * x + y * y;
}
pub fn distance(a: c.Vec, b: c.Vec) f64 {
    return @sqrt(distance2(a, b));
}
pub const Result = struct { centers: []c.Vec, assignment: []usize, sizes: []usize, iterations: usize = 0, inertia: f64 = 0 };
fn assign(points: []const c.Point, centers: []const c.Vec) []usize {
    const out = c.alloc(usize, points.len);
    for (points, out) |point, *label| {
        label.* = 0;
        var best = distance2(point.xy, centers[0]);
        for (centers[1..], 1..) |center, j| {
            const d = distance2(point.xy, center);
            if (d < best) {
                best = d;
                label.* = j;
            }
        }
    }
    return out;
}
pub fn run(points: []const c.Point, initial: c.Model, maximum: usize) Result {
    const centers = c.alloc(c.Vec, initial.components.len);
    for (initial.components, centers) |component, *center| center.* = component.mean;
    var out: Result = .{ .centers = centers, .assignment = assign(points, centers), .sizes = c.alloc(usize, centers.len) };
    @memset(out.sizes, 0);
    for (1..maximum + 1) |t| {
        for (centers, 0..) |*center, j| {
            var total: c.Vec = .{ 0, 0 };
            var count: usize = 0;
            for (points, out.assignment) |point, label| if (label == j) {
                count += 1;
                total[0] += point.xy[0];
                total[1] += point.xy[1];
            };
            if (count > 0) center.* = .{ total[0] / c.f(count), total[1] / c.f(count) };
        }
        const labels = assign(points, centers);
        var same = true;
        for (labels, out.assignment) |a, b| same = same and a == b;
        out.assignment = labels;
        out.iterations = t;
        if (same) break;
    }
    for (points, out.assignment) |point, label| {
        out.inertia += distance2(point.xy, centers[label]);
        out.sizes[label] += 1;
    }
    return out;
}
