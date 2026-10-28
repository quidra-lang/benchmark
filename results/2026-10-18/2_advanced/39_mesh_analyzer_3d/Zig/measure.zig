const std = @import("std");
const c = @import("obj_io.zig");
pub fn difference(a: c.Point, b: c.Point) c.Point {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn cross(a: c.Point, b: c.Point) c.Point {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
pub fn dot(a: c.Point, b: c.Point) i64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn normal(face: c.Face, points: []const c.Point) c.Point {
    return cross(difference(points[face.vertices[1]], points[face.vertices[0]]), difference(points[face.vertices[2]],
         points[face.vertices[0]]));
}
pub fn determinant(face: c.Face, points: []const c.Point) i64 {
    return dot(points[face.vertices[0]], cross(points[face.vertices[1]], points[face.vertices[2]]));
}
fn f(value: i64) f64 {
    return @floatFromInt(value);
}
pub fn area(face_ids: []const usize, faces: []const c.Face, points: []const c.Point) f64 {
    var total: f64 = 0;
    for (face_ids) |index| {
        const n = normal(faces[index], points);
        total += @sqrt(f(dot(n, n)));
    }
    return total / 2;
}
pub fn fraction(numerator_: i64, denominator_: i64) []const u8 {
    var numerator = numerator_;
    var denominator = denominator_;
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    const divisor = std.math.gcd(@abs(numerator), @as(u64, @intCast(denominator)));
    numerator = @divTrunc(numerator, @as(i64, @intCast(divisor)));
    denominator = @divTrunc(denominator, @as(i64, @intCast(divisor)));
    return if (denominator == 1) c.fmt("{d}", .{numerator}) else c.fmt("{d}/{d}", .{ numerator, denominator });
}
pub fn real(value: f64) []const u8 {
    return c.fmt("{d:.3}", .{value});
}
pub fn pointText(point: c.Point) []const u8 {
    return c.fmt("{d} {d} {d}", .{ point[0], point[1], point[2] });
}
pub fn centroid(face_ids: []const usize, faces: []const c.Face, points: []const c.Point, volume6: i64) []const u8 {
    var sum: c.Point = .{ 0, 0, 0 };
    for (face_ids) |index| {
        const face = faces[index];
        const d = determinant(face, points);
        for (0..3) |axis| sum[axis] += d * (points[face.vertices[0]][axis] + points[face.vertices[1]][axis] + points[face.vertices[2]][axis]);
    }
    return c.fmt("{s} {s} {s}", .{ fraction(sum[0], 4 * volume6), fraction(sum[1], 4 * volume6), fraction(sum[2], 4 * volume6) });
}
pub fn winding(point: c.Point, face_ids: []const usize, faces: []const c.Face, points: []const c.Point) i64 {
    var total: f64 = 0;
    for (face_ids) |index| {
        const face = faces[index];
        const a = difference(points[face.vertices[0]], point);
        const b = difference(points[face.vertices[1]], point);
        const d = difference(points[face.vertices[2]], point);
        const al = @sqrt(f(dot(a, a)));
        const bl = @sqrt(f(dot(b, b)));
        const dl = @sqrt(f(dot(d, d)));
        const denominator = al * bl * dl + f(dot(a, b)) * dl + f(dot(b, d)) * al + f(dot(d, a)) * bl;
        total += 2 * std.math.atan2(f(dot(a, cross(b, d))), denominator);
    }
    return @intFromFloat(@round(total / (4 * std.math.pi)));
}
pub fn triangleAngle(face: c.Face, points: []const c.Point) []const u8 {
    var smallest: i64 = std.math.maxInt(i64);
    for (face.vertices, 0..) |vertex, i| smallest = @min(smallest, dot(difference(points[face.vertices[(i + 1) % 3]],
         points[vertex]), difference(points[face.vertices[(i + 2) % 3]], points[vertex])));
    return if (smallest < 0) "obtuse" else if (smallest == 0) "right" else "acute";
}
