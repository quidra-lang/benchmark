const std = @import("std");
const c = @import("mesh.zig");
pub fn load(io: std.Io) ![]const c.Material {
    var out: std.ArrayList(c.Material) = .empty;
    for (try c.readLines(io, "input/materials.txt")) |line| {
        const row = c.words(line);
        c.append(c.Material, &out, .{ .code = row[0][0], .name = row[1], .k = c.real(row[2]),
             .rho = c.real(row[3]), .cp = c.real(row[4]) });
    }
    return out.items;
}
pub fn capacity(material: c.Material, dx: f64, thickness: f64) f64 {
    return material.rho * material.cp * dx * dx * thickness;
}
pub fn interior(first: f64, second: f64, thickness: f64) f64 {
    return 2 * first * second / (first + second) * thickness;
}
pub fn fixed(conductivity: f64, thickness: f64) f64 {
    return 2 * conductivity * thickness;
}
pub fn convective(conductivity: f64, coefficient: f64, dx: f64, thickness: f64) f64 {
    return 1 / (1 / (coefficient * dx * thickness) + 1 / (2 * conductivity * thickness));
}
