const f = @import("fixed_point.zig");
pub const Vec = [3]i64;
pub fn add(a: Vec, b: Vec) Vec {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn sub(a: Vec, b: Vec) Vec {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn neg(a: Vec) Vec {
    return .{ -a[0], -a[1], -a[2] };
}
pub fn dot(a: Vec, b: Vec) i64 {
    return f.div(a[0] * b[0] + a[1] * b[1] + a[2] * b[2], f.scale);
}
pub fn sc(a: Vec, k: i64) Vec {
    return .{ f.mul(a[0], k), f.mul(a[1], k), f.mul(a[2], k) };
}
pub fn len(a: Vec) i64 {
    return f.isqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
}
pub fn norm(a: Vec) Vec {
    const l = len(a);
    return .{ f.div(a[0] * f.scale, l), f.div(a[1] * f.scale, l), f.div(a[2] * f.scale, l) };
}
