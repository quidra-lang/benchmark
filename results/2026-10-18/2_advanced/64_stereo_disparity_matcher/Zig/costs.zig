const d = @import("pgm_io.zig");
pub fn clamped(image: []const i64, width: usize, height: usize, x: i64, y: i64) i64 {
    const xx = d.u(@min(@max(x, 0), d.n(width) - 1));
    const yy = d.u(@min(@max(y, 0), d.n(height) - 1));
    return image[yy * width + xx];
}
pub fn boxSum(image: []const i64, width: usize, height: usize, window: usize) []const i64 {
    const radius = window / 2;
    const pw = width + 2 * radius;
    const ph = height + 2 * radius;
    const integral = d.alloc(i64, (pw + 1) * (ph + 1));
    @memset(integral, 0);
    const out = d.alloc(i64, width * height);
    for (0..ph) |y| {
        var sum: i64 = 0;
        for (0..pw) |x| {
            sum += clamped(image, width, height, d.n(x) - d.n(radius), d.n(y) - d.n(radius));
            integral[(y + 1) * (pw + 1) + x + 1] = integral[y * (pw + 1) + x + 1] + sum;
        }
    }
    for (0..height) |y| for (0..width) |x| {
        out[y * width + x] = integral[(y + window) * (pw + 1) + x + window] - integral[y * (pw + 1) + x + window] - integral[(y + window) * (pw + 1) + x] + integral[y * (pw + 1) + x];
    };
    return out;
}
pub fn census(image: []const i64, width: usize, height: usize) []const i64 {
    const out = d.alloc(i64, width * height);
    for (0..height) |y| for (0..width) |x| {
        var code: i64 = 0;
        var dy: i64 = -2;
        while (dy <= 2) : (dy += 1) {
            var dx: i64 = -2;
            while (dx <= 2) : (dx += 1) {
                if (dx == 0 and dy == 0) continue;
                code = (code << 1) | @as(i64, @intFromBool(clamped(image, width, height, d.n(x) + dx,
                     d.n(y) + dy) < image[y * width + x]));
            }
        }
        out[y * width + x] = code;
    };
    return out;
}
pub fn texture(image: []const i64, width: usize, height: usize, window: usize) []const i64 {
    const gradient = d.alloc(i64, width * height);
    for (0..height) |y| for (0..width) |x| {
        gradient[y * width + x] = @intCast(@abs(clamped(image, width, height, d.n(x) + 1, d.n(y)) - clamped(image,
             width, height, d.n(x) - 1, d.n(y))));
    };
    return boxSum(gradient, width, height, window);
}
pub fn costVolume(left: d.PGM, right: d.PGM, cl: []const i64, cr: []const i64, kind: usize,
     window: usize, p: d.Params) d.Volume {
    const width = left.width;
    const height = left.height;
    const count = p.maximum - p.minimum + 1;
    const out: d.Volume = .{ .values = d.alloc(i64, width * height * count), .pixels = width * height,
         .disparities = count };
    for (p.minimum..p.maximum + 1) |disparity| {
        const pixels = d.alloc(i64, width * height);
        for (0..height) |y| for (0..width) |x| {
            const index = y * width + x;
            const other = y * width + (if (x > disparity) x - disparity else 0);
            if (kind == 2) pixels[index] = @intCast(@popCount(@as(u64, @intCast(cl[index] ^ cr[other])))) else {
                const difference = left.pixels[index] - right.pixels[other];
                pixels[index] = if (kind == 0) @intCast(@abs(difference)) else difference * difference;
            }
        };
        const totals = boxSum(pixels, width, height, window);
        for (totals, 0..) |value, index| out.values[index * count + disparity - p.minimum] = value;
    }
    return out;
}
