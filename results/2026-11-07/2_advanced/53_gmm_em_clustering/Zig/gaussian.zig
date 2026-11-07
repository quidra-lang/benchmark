const std = @import("std");
const c = @import("dataset.zig");
const pi: f64 = 3.141592653589793;
pub fn determinant(cov: c.Cov) f64 {
    return cov[0] * cov[2] - cov[1] * cov[1];
}
pub fn mahalanobis(point: c.Vec, mean: c.Vec, cov: c.Cov) f64 {
    const dx = point[0] - mean[0];
    const dy = point[1] - mean[1];
    return (cov[2] * dx * dx - 2 * cov[1] * dx * dy + cov[0] * dy * dy) / determinant(cov);
}
pub fn weightedLog(point: c.Vec, component: c.Component) f64 {
    return @log(component.weight) - @log(2 * pi) - @log(determinant(component.cov)) / 2 - mahalanobis(point,
         component.mean, component.cov) / 2;
}
pub const Eigen = struct { leading: f64, trailing: f64, direction: c.Vec, angle: f64, major: f64,
     minor: f64, area: f64, correlation: f64 };
pub fn eigen(cov: c.Cov) Eigen {
    const a = cov[0];
    const b = cov[1];
    const d = cov[2];
    const h = (a + d) / 2;
    const g = @sqrt(((a - d) / 2) * ((a - d) / 2) + b * b);
    const leading = h + g;
    const trailing = h - g;
    var direction: c.Vec = undefined;
    if (b == 0) direction = if (a >= d) c.Vec{ 1, 0 } else c.Vec{ 0, 1 } else {
        const vx = if (a >= d) leading - d else b;
        const vy = if (a >= d) b else leading - a;
        const length = @sqrt(vx * vx + vy * vy);
        direction = if (vx < 0) c.Vec{ -vx / length, -vy / length } else c.Vec{ vx / length, vy / length };
    }
    return .{ .leading = leading, .trailing = trailing, .direction = direction, .angle = std.math.atan2(direction[1],
         direction[0]) * 180 / pi, .major = @sqrt(leading), .minor = @sqrt(trailing), .area = pi * @sqrt(leading * trailing),
         .correlation = b / @sqrt(a * d) };
}
pub fn bhattacharyya(a: c.Component, b: c.Component) f64 {
    var average: c.Cov = undefined;
    for (0..3) |j| average[j] = (a.cov[j] + b.cov[j]) / 2;
    return mahalanobis(b.mean, a.mean, average) / 8 + @log(determinant(average) / @sqrt(determinant(a.cov) * determinant(b.cov))) / 2;
}
