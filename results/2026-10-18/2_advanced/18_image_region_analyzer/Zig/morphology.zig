const p = @import("pgm_reader.zig");
const Point = p.Point;
const Mask = p.Mask;
const neighborhood = [_]Point{ .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = -1, .y = -1 } };
pub fn erode(mask: Mask, offsets: []const Point) Mask {
    const result = Mask.init(mask.width, mask.height);
    for (0..mask.height) |y| {
        for (0..mask.width) |x| {
            var value = true;
            for (offsets) |offset| if (!mask.get(p.n(x) + offset.x, p.n(y) + offset.y)) { value = false; break; };
            result.pixels[y * mask.width + x] = value;
        }
    }
    return result;
}
pub fn dilate(mask: Mask, offsets: []const Point) Mask {
    const result = Mask.init(mask.width, mask.height);
    for (0..mask.height) |y| {
        for (0..mask.width) |x| {
            var value = false;
            for (offsets) |offset| if (mask.get(p.n(x) - offset.x, p.n(y) - offset.y)) { value = true; break; };
            result.pixels[y * mask.width + x] = value;
        }
    }
    return result;
}
pub fn opening(mask: Mask, offsets: []const Point) Mask { return dilate(erode(mask, offsets), offsets); }
pub fn closing(mask: Mask, offsets: []const Point) Mask { return erode(dilate(mask, offsets), offsets); }
fn bitsAt(mask: Mask, x: i64, y: i64) [8]bool {
    var bits: [8]bool = undefined;
    for (neighborhood, &bits) |offset, *bit| bit.* = mask.get(x + offset.x, y + offset.y);
    return bits;
}
fn transitions(bits: [8]bool) usize {
    var result: usize = 0;
    for (0..8) |i| if (!bits[i] and bits[(i + 1) % 8]) { result += 1; };
    return result;
}
pub fn crossingNumber(mask: Mask, x: i64, y: i64) usize { return transitions(bitsAt(mask, x, y)); }
fn thinningStep(mask: Mask, first: bool) bool {
    var removed = [_]bool{false} ** 3072;
    var changed = false;
    for (mask.pixels, 0..) |value, index| {
        if (!value) continue;
        const bits = bitsAt(mask, p.n(index % mask.width), p.n(index / mask.width));
        var count: usize = 0;
        for (bits) |bit| count += @intFromBool(bit);
        if (count < 2 or count > 6 or transitions(bits) != 1) continue;
        const p2 = bits[0];
        const p4 = bits[2];
        const p6 = bits[4];
        const p8 = bits[6];
        const blocked = if (first) (p2 and p4 and p6) or (p4 and p6 and p8) else (p2 and p4 and p8) or (p2 and p6 and p8);
        if (!blocked) { removed[index] = true; changed = true; }
    }
    for (mask.pixels, 0..) |*value, index| if (removed[index]) { value.* = false; };
    return changed;
}
pub fn thin(mask: Mask) Mask {
    const result = Mask.init(mask.width, mask.height);
    @memcpy(result.pixels, mask.pixels);
    while (true) {
        const first = thinningStep(result, true);
        const second = thinningStep(result, false);
        if (!first and !second) return result;
    }
}
