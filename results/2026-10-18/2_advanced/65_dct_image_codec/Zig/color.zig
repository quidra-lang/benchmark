const d = @import("image_io.zig");
pub fn clamp(value: i64) i64 {
    return @min(@max(value, 0), 255);
}
pub fn toYCbCr(pixel: d.Pixel) d.Pixel {
    const r = pixel[0];
    const g = pixel[1];
    const b = pixel[2];
    return .{ @divFloor(19595 * r + 38470 * g + 7471 * b + 32768, 65536), @divFloor(-11059 * r - 21709 * g + 32768 * b + 8421375,
         65536), @divFloor(32768 * r - 27439 * g - 5329 * b + 8421375, 65536) };
}
pub fn toRGB(pixel: d.Pixel) d.Pixel {
    const y = pixel[0];
    const cb = pixel[1];
    const cr = pixel[2];
    return .{ clamp(y + @divFloor(91881 * (cr - 128) + 32768, 65536)), clamp(y + @divFloor(-22554 * (cb - 128) - 46802 * (cr - 128) + 32768,
         65536)), clamp(y + @divFloor(116130 * (cb - 128) + 32768, 65536)) };
}
pub fn splitPlanes(image: d.Image) [3]d.Plane {
    var out: [3]d.Plane = undefined;
    for (&out) |*plane| plane.* = .{ .width = image.width, .height = image.height, .pixels = d.alloc(i64,
         image.pixels.len) };
    for (image.pixels, 0..) |pixel, i| {
        const converted = toYCbCr(pixel);
        for (0..3) |k| out[k].pixels[i] = converted[k];
    }
    return out;
}
pub fn componentPlanes(planes: [3]d.Plane, factors: [3]d.Factor, mx: usize, my: usize) [3]d.Plane {
    var hmax: usize = 1;
    var vmax: usize = 1;
    for (factors) |factor| {
        hmax = @max(hmax, factor.h);
        vmax = @max(vmax, factor.v);
    }
    var out: [3]d.Plane = undefined;
    for (planes, 0..) |original, k| {
        const width = 8 * factors[k].h * mx;
        const height = 8 * factors[k].v * my;
        out[k] = .{ .width = width, .height = height, .pixels = d.alloc(i64, width * height) };
        const fx = hmax / factors[k].h;
        const fy = vmax / factors[k].v;
        for (0..height) |y| for (0..width) |x| {
            var sum: i64 = 0;
            for (0..fy) |j| for (0..fx) |i| {
                sum += original.pixels[@min(fy * y + j, original.height - 1) * original.width + @min(fx * x + i,
                     original.width - 1)];
            };
            out[k].pixels[y * width + x] = @divTrunc(sum, d.n(fx * fy));
        };
    }
    return out;
}
pub fn upsample(planes: [3]d.Plane, factors: [3]d.Factor, width: usize, height: usize) [3]d.Plane {
    var hmax: usize = 1;
    var vmax: usize = 1;
    for (factors) |factor| {
        hmax = @max(hmax, factor.h);
        vmax = @max(vmax, factor.v);
    }
    var out: [3]d.Plane = undefined;
    for (planes, 0..) |plane, k| {
        out[k] = .{ .width = width, .height = height, .pixels = d.alloc(i64, width * height) };
        for (0..height) |y| for (0..width) |x| {
            out[k].pixels[y * width + x] = plane.pixels[(y * factors[k].v / vmax) * plane.width + x * factors[k].h / hmax];
        };
    }
    return out;
}
pub fn combineRGB(planes: [3]d.Plane) d.Image {
    const width = planes[0].width;
    const height = planes[0].height;
    const pixels = d.alloc(d.Pixel, width * height);
    for (pixels, 0..) |*pixel, i| pixel.* = toRGB(.{ planes[0].pixels[i], planes[1].pixels[i], planes[2].pixels[i] });
    return .{ .width = width, .height = height, .pixels = pixels };
}
