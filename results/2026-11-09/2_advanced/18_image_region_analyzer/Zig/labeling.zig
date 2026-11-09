const p = @import("pgm_reader.zig");
const Point = p.Point;
const Mask = p.Mask;
pub const Labeling = struct { pixels: []usize, count: usize, provisional: usize };
fn root(parents: []usize, initial: usize) usize {
    var value = initial;
    while (parents[value] != value) {
        parents[value] = parents[parents[value]];
        value = parents[value];
    }
    return value;
}
pub fn labelComponents(mask: Mask, connectivity: usize) Labeling {
    const previous4 = [_]Point{ .{ .x = -1, .y = 0 }, .{ .x = 0, .y = -1 } };
    const previous8 = [_]Point{ .{ .x = -1, .y = 0 }, .{ .x = -1, .y = -1 }, .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 } };
    const previous: []const Point = if (connectivity == 4) &previous4 else &previous8;
    var parents = [_]usize{0} ** 3073;
    var numbers = [_]usize{0} ** 3073;
    var result: Labeling = .{ .pixels = p.alloc(usize, mask.pixels.len), .count = 0, .provisional = 0 };
    @memset(result.pixels, 0);
    for (0..mask.height) |y| {
        for (0..mask.width) |x| {
            const index = y * mask.width + x;
            if (!mask.pixels[index]) continue;
            var label: usize = 0;
            for (previous) |offset| {
                const nx = p.n(x) + offset.x;
                const ny = p.n(y) + offset.y;
                if (!mask.get(nx, ny)) continue;
                const other = result.pixels[p.u(ny) * mask.width + p.u(nx)];
                if (label == 0) label = other else {
                    const first = root(&parents, label);
                    const second = root(&parents, other);
                    parents[@max(first, second)] = @min(first, second);
                }
            }
            if (label == 0) {
                result.provisional += 1;
                label = result.provisional;
                parents[label] = label;
            }
            result.pixels[index] = label;
        }
    }
    for (result.pixels) |*label| {
        if (label.* == 0) continue;
        const representative = root(&parents, label.*);
        if (numbers[representative] == 0) { result.count += 1; numbers[representative] = result.count; }
        label.* = numbers[representative];
    }
    return result;
}
pub fn bitQuadEuler(mask: Mask, connectivity: usize) i64 {
    var singles: i64 = 0;
    var triples: i64 = 0;
    var diagonals: i64 = 0;
    var y: i64 = -1;
    while (y < p.n(mask.height)) : (y += 1) {
        var x: i64 = -1;
        while (x < p.n(mask.width)) : (x += 1) {
            const a = mask.get(x, y);
            const b = mask.get(x + 1, y);
            const c = mask.get(x, y + 1);
            const d = mask.get(x + 1, y + 1);
            const count = @as(usize, @intFromBool(a)) + @intFromBool(b) + @intFromBool(c) + @intFromBool(d);
            if (count == 1) singles += 1 else if (count == 3) triples += 1 else if (count == 2 and ((a and d) or (b and c))) diagonals += 1;
        }
    }
    return @divExact(singles - triples + (if (connectivity == 8) @as(i64, -2) else 2) * diagonals, 4);
}
