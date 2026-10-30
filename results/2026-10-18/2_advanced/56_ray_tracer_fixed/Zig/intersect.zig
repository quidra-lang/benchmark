const std = @import("std");
const c = @import("scene.zig");
const f = @import("fixed_point.zig");
const v = @import("vector3.zig");
pub const Candidate = struct { distance: i64, entering: bool = false, axis: usize = 0 };
pub const Slab = struct { near: i64 = std.math.minInt(i64), far: i64 = std.math.maxInt(i64), near_axis: usize = 0, far_axis: usize = 0 };
pub fn slab(box: c.Bounds, ray: c.Ray) ?Slab {
    var out: Slab = .{};
    for (0..3) |axis| {
        if (ray.direction[axis] == 0) {
            if (ray.origin[axis] < box.lo[axis] or ray.origin[axis] > box.hi[axis]) return null;
            continue;
        }
        const a = f.div((box.lo[axis] - ray.origin[axis]) * f.scale, ray.direction[axis]);
        const b = f.div((box.hi[axis] - ray.origin[axis]) * f.scale, ray.direction[axis]);
        if (@min(a, b) > out.near) {
            out.near = @min(a, b);
            out.near_axis = axis;
        }
        if (@max(a, b) < out.far) {
            out.far = @max(a, b);
            out.far_axis = axis;
        }
    }
    return if (out.near > out.far) null else out;
}
pub fn hit(object: c.Object, ray: c.Ray, epsilon: i64) ?Candidate {
    if (object.kind == .sphere) {
        const oc = v.sub(ray.origin, object.first);
        const b = v.dot(oc, ray.direction);
        const tc = f.div(-b * f.scale, v.dot(ray.direction, ray.direction));
        const h = v.add(oc, v.sc(ray.direction, tc));
        const q = f.div(object.radius * object.radius, f.scale) - v.dot(h, h);
        if (q < 0) return null;
        const width = f.div(f.isqrt(q * f.scale) * f.scale, v.len(ray.direction));
        if (tc - width > epsilon) return .{ .distance = tc - width };
        if (tc + width > epsilon) return .{ .distance = tc + width };
        return null;
    }
    if (object.kind == .plane) {
        const den = v.dot(ray.direction, object.second);
        if (den == 0) return null;
        const distance = f.div(v.dot(v.sub(object.first, ray.origin), object.second) * f.scale, den);
        return if (distance > epsilon) .{ .distance = distance } else null;
    }
    const box = slab(.{ .lo = object.first, .hi = object.second }, ray) orelse return null;
    if (box.near > epsilon) return .{ .distance = box.near, .entering = true, .axis = box.near_axis };
    if (box.far > epsilon) return .{ .distance = box.far, .axis = box.far_axis };
    return null;
}
pub fn outward(object: c.Object, ray: c.Ray, point: c.Vec, candidate: Candidate) c.Vec {
    if (object.kind == .sphere) return v.norm(v.sub(point, object.first));
    if (object.kind == .plane) return object.second;
    var out: c.Vec = .{ 0, 0, 0 };
    const positive = ray.direction[candidate.axis] > 0;
    out[candidate.axis] = if (positive == candidate.entering) -f.scale else f.scale;
    return out;
}
pub fn bounds(object: c.Object, pad: i64) c.Bounds {
    var out: c.Bounds = undefined;
    for (0..3) |axis| {
        out.lo[axis] = object.first[axis] - pad - (if (object.kind == .sphere) object.radius else @as(i64, 0));
        out.hi[axis] = (if (object.kind == .sphere) object.first[axis] + object.radius else object.second[axis]) + pad;
    }
    return out;
}
