const c = @import("scene.zig");
const f = @import("fixed_point.zig");
const v = @import("vector3.zig");
pub fn base(material: c.Material, point: c.Vec) c.Vec {
    if (material.checker_size == 0) return material.color;
    const cell = f.div(point[0], material.checker_size) + f.div(point[1], material.checker_size) + f.div(point[2],
         material.checker_size);
    return if (@mod(cell, 2) != 0) material.second else material.color;
}
pub fn phong(material: c.Material, normal: c.Vec, light: c.Vec, view: c.Vec, effective: i64) [2]i64 {
    const ndl = v.dot(normal, light);
    const diffuse = f.mul(f.mul(material.kd, ndl), effective);
    const rv = v.dot(v.sub(v.sc(normal, 2 * ndl), light), view);
    var specular: i64 = 0;
    if (rv > 0) {
        var power: i64 = f.scale;
        for (0..c.u(material.exponent)) |_| power = f.mul(power, rv);
        specular = f.mul(f.mul(material.ks, power), effective);
    }
    return .{ diffuse, specular };
}
pub fn reflected(direction: c.Vec, normal: c.Vec) c.Vec {
    return v.norm(v.sub(direction, v.sc(normal, 2 * v.dot(direction, normal))));
}
pub const Weights = struct { reflection: i64, refraction: i64, direction: ?c.Vec = null, total_internal: bool = false };
pub fn refracted(material: c.Material, direction: c.Vec, normal: c.Vec, front: bool) Weights {
    var out: Weights = .{ .reflection = material.kr, .refraction = material.kt };
    if (material.kt == 0) return out;
    const eta = if (front) f.div(f.scale * f.scale, material.ior) else material.ior;
    const cn = -v.dot(direction, normal);
    const disc = f.scale * f.scale - f.div(f.mul(eta, eta) * (f.scale * f.scale - cn * cn), f.scale);
    if (disc < 0) {
        out.reflection = material.kr + material.kt;
        out.refraction = 0;
        out.total_internal = true;
        return out;
    }
    out.direction = v.norm(v.add(v.sc(direction, eta), v.sc(normal, f.mul(eta, cn) - f.isqrt(disc))));
    const r0 = f.div((material.ior - f.scale) * f.scale, material.ior + f.scale);
    const base_term = f.mul(r0, r0);
    const x = f.scale - @min(cn, f.scale);
    var power: i64 = f.scale;
    for (0..5) |_| power = f.mul(power, x);
    const fresnel = base_term + f.mul(f.scale - base_term, power);
    const reflection = f.mul(material.kt, fresnel);
    out.reflection = material.kr + reflection;
    out.refraction = material.kt - reflection;
    return out;
}
pub fn mix(local: c.Vec, lw: i64, reflection: c.Vec, rw: i64, refraction: c.Vec, tw: i64) c.Vec {
    var out: c.Vec = undefined;
    for (0..3) |axis| out[axis] = f.div(local[axis] * lw, f.scale) + f.div(reflection[axis] * rw,
         f.scale) + f.div(refraction[axis] * tw, f.scale);
    return out;
}
