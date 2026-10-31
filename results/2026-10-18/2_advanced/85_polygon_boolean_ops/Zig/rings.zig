const std = @import("std");
const r = @import("rational.zig");
const intersections = @import("intersections.zig");
pub const Ring = []const r.Point;
pub const Sequence = []const Ring;
pub const Polygons = []const Sequence;
pub fn inside(ring: Ring, point: r.Point) bool {
    var parity = false;
    for (ring, 0..) |first, index| {
        const second = ring[(index + 1) % ring.len];
        if (point.y.less(first.y) == point.y.less(second.y)) continue;
        const low = if (first.y.less(second.y)) first else second;
        const high = if (first.y.less(second.y)) second else first;
        if (r.cross(low, high, point).numerator > 0) parity = !parity;
    }
    return parity;
}
pub fn interior(sequence: Sequence, point: r.Point) bool {
    var parity = false;
    for (sequence) |ring| if (inside(ring, point)) {
        parity = !parity;
    };
    return parity;
}
pub fn boundary(ring: Ring, point: r.Point) bool {
    for (ring, 0..) |first, index| if (intersections.onSegment(point, first, ring[(index + 1) % ring.len])) return true;
    return false;
}
pub fn rotate(ring: Ring) Ring {
    var first: usize = 0;
    for (ring, 0..) |point, index| if (r.pointLess({}, point, ring[first])) {
        first = index;
    };
    const out = r.alloc(r.Point, ring.len);
    for (out, 0..) |*point, index| point.* = ring[(first + index) % ring.len];
    return out;
}
pub fn counterclockwise(ring: Ring) bool {
    return r.cross(ring[ring.len - 1], ring[0], ring[1]).numerator > 0;
}
pub fn reverse(ring: Ring) Ring {
    const out = r.alloc(r.Point, ring.len);
    out[0] = ring[0];
    for (1..ring.len) |index| out[index] = ring[ring.len - index];
    return out;
}
pub fn normalize(ring: Ring, outer: bool) Ring {
    const rotated = rotate(ring);
    return if (counterclockwise(rotated) == outer) rotated else reverse(rotated);
}
pub fn ringLess(_: void, first: Ring, second: Ring) bool {
    return r.pointLess({}, first[0], second[0]);
}
pub fn assemble(result_rings: Sequence) Polygons {
    const rotated = r.alloc(Ring, result_rings.len);
    for (result_rings, rotated) |ring, *out| out.* = rotate(ring);
    const depths = r.zero(usize, rotated.len, 0);
    for (rotated, 0..) |ring, index| for (rotated, 0..) |other, j| if (index != j and inside(other, ring[0])) {
        depths[index] += 1;
    };
    for (rotated, depths) |*ring, depth| if (counterclockwise(ring.*) != (depth % 2 == 0)) {
        ring.* = reverse(ring.*);
    };
    var outers: std.ArrayList(usize) = .empty;
    for (depths, 0..) |depth, index| if (depth % 2 == 0) r.append(usize, &outers, index);
    std.mem.sort(usize, outers.items, rotated, struct {
        fn less(sequence: []Ring, a: usize, b: usize) bool {
            return ringLess({}, sequence[a], sequence[b]);
        }
    }.less);
    var polygons: std.ArrayList(Sequence) = .empty;
    for (outers.items) |index| {
        var holes: std.ArrayList(Ring) = .empty;
        for (rotated, depths) |ring, depth| if (depth == depths[index] + 1 and inside(rotated[index],
             ring[0])) r.append(Ring, &holes, ring);
        std.mem.sort(Ring, holes.items, {}, ringLess);
        const sequence = r.alloc(Ring, holes.items.len + 1);
        sequence[0] = rotated[index];
        @memcpy(sequence[1..], holes.items);
        r.append(Sequence, &polygons, sequence);
    }
    return polygons.items;
}
pub fn area(ring: Ring) f64 {
    var total: f64 = 0;
    for (ring, 0..) |first, index| {
        const second = ring[(index + 1) % ring.len];
        total += first.x.real() * second.y.real() - second.x.real() * first.y.real();
    }
    return total / 2.0;
}
pub fn perimeter(ring: Ring) f64 {
    var total: f64 = 0;
    for (ring, 0..) |first, index| {
        const second = ring[(index + 1) % ring.len];
        const dx = second.x.real() - first.x.real();
        const dy = second.y.real() - first.y.real();
        total += @sqrt(dx * dx + dy * dy);
    }
    return total;
}
