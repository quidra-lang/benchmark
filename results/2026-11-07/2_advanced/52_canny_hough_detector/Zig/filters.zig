const c = @import("pgm_io.zig");
pub fn absolute(value: i64) i64 {
    return if (value < 0) -value else value;
}
pub fn clamped(image: c.Image, x: i64, y: i64) i64 {
    return image.at(.{ .x = @max(0, @min(c.n(image.width) - 1, x)), .y = @max(0, @min(c.n(image.height) - 1, y)) });
}
pub fn smooth(image: c.Image, p: c.Params) c.Image {
    const out = c.Image.init(image.width, image.height);
    const half = @divTrunc(p.ks - 1, 2);
    for (0..image.height) |yy| for (0..image.width) |xx| {
        const x = c.n(xx);
        const y = c.n(yy);
        var sum: i64 = 0;
        for (0..c.u(p.ks)) |j| for (0..c.u(p.ks)) |i| {
            sum += p.kernel[j * c.u(p.ks) + i] * clamped(image, x + c.n(i) - half, y + c.n(j) - half);
        };
        out.set(.{ .x = x, .y = y }, @divFloor(sum, p.divisor));
    };
    return out;
}
pub const Gradient = struct { gx: c.Image, gy: c.Image, magnitude: c.Image };
pub fn gradient(image: c.Image) Gradient {
    const out: Gradient = .{ .gx = c.Image.init(image.width, image.height), .gy = c.Image.init(image.width,
         image.height), .magnitude = c.Image.init(image.width, image.height) };
    for (0..image.height) |yy| for (0..image.width) |xx| {
        const x = c.n(xx);
        const y = c.n(yy);
        var q: [9]i64 = undefined;
        for (c.offsets, 0..) |dy, j| for (c.offsets, 0..) |dx, i| {
            q[j * 3 + i] = clamped(image, x + dx, y + dy);
        };
        const gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
        const gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
        const point: c.Point = .{ .x = x, .y = y };
        out.gx.set(point, gx);
        out.gy.set(point, gy);
        out.magnitude.set(point, absolute(gx) + absolute(gy));
    };
    return out;
}
