const d = @import("model_io.zig");
const a = @import("assembly.zig");
pub const Result = struct { name: []const u8, displacement: []const f64, forces: []const f64,
     reactions: []const f64, external: []const f64 };
pub fn axialForces(geometry: []const a.Geometry, properties: []const a.Properties, displacement: []const f64,
     temperature: []const f64, removed: ?usize) []f64 {
    const out = a.zeros(geometry.len);
    for (geometry, properties, 0..) |g, p, i| {
        if (removed == i) continue;
        const extension = (displacement[g.dofs[2]] - displacement[g.dofs[0]]) * g.cosine + (displacement[g.dofs[3]] - displacement[g.dofs[1]]) * g.sine;
        out[i] = p.stiffness * extension - temperature[i];
    }
    return out;
}
pub fn reactions(matrix: a.Matrix, displacement: []const f64, force: []const f64, restrained: []const usize) []f64 {
    const out = a.zeros(force.len);
    for (restrained) |r| {
        var value: f64 = 0;
        for (displacement, 0..) |entry, degree| value += matrix[r][degree] * entry;
        out[r] = value - force[r];
    }
    return out;
}
fn combinedVector(combination: d.Combination, cases: []const Result, comptime field: []const u8) []const f64 {
    const first = combination.terms[0];
    const out = d.dupe(f64, @field(cases[first.index], field));
    for (out) |*value| value.* = first.factor * value.*;
    for (combination.terms[1..]) |term| {
        const source = @field(cases[term.index], field);
        for (out, source) |*value, entry| value.* += term.factor * entry;
    }
    return out;
}
pub fn superpose(combination: d.Combination, cases: []const Result) Result {
    return .{ .name = combination.name, .displacement = combinedVector(combination, cases,
         "displacement"), .forces = combinedVector(combination, cases, "forces"), .reactions = combinedVector(combination,
         cases, "reactions"), .external = combinedVector(combination, cases, "external") };
}
pub fn equilibriumResidual(result: Result, geometry: []const a.Geometry) f64 {
    const residual = d.alloc(f64, result.external.len);
    for (residual, result.external, result.reactions) |*value, external, reaction| value.* = external + reaction;
    for (geometry, result.forces) |g, force| {
        const direction = [_]f64{ g.cosine, g.sine, -g.cosine, -g.sine };
        for (g.dofs, direction) |degree, entry| residual[degree] += force * entry;
    }
    var maximum: f64 = 0;
    for (residual) |value| maximum = @max(maximum, @abs(value));
    return maximum;
}
