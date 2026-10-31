const d = @import("model_io.zig");
pub const Matrix = [][]f64;
pub fn zeros(size: usize) []f64 {
    const out = d.alloc(f64, size);
    @memset(out, 0);
    return out;
}
pub fn matrix(size: usize) Matrix {
    const out = d.alloc([]f64, size);
    for (out) |*row| row.* = zeros(size);
    return out;
}
pub const Geometry = struct { length: f64, cosine: f64, sine: f64, dofs: [4]usize };
pub const Properties = struct { area: f64, inertia: f64, young: f64, yield_stress: f64, density: f64,
     expansion: f64, stiffness: f64 };
pub fn memberGeometry(model: d.Model, dofs: []const [2]usize) []const Geometry {
    const out = d.alloc(Geometry, model.members.len);
    for (model.members, out) |member, *g| {
        const dx = model.nodes[member.end].x - model.nodes[member.start].x;
        const dy = model.nodes[member.end].y - model.nodes[member.start].y;
        const length = @sqrt(d.f(dx * dx + dy * dy));
        g.* = .{ .length = length, .cosine = d.f(dx) / length, .sine = d.f(dy) / length, .dofs = .{ dofs[member.start][0],
             dofs[member.start][1], dofs[member.end][0], dofs[member.end][1] } };
    }
    return out;
}
pub fn memberProperties(model: d.Model, choices: []const usize, geometry: []const Geometry) []const Properties {
    const out = d.alloc(Properties, model.members.len);
    for (model.members, choices, geometry, out) |member, choice, g, *p| {
        const material = model.materials[member.material];
        const section = model.sections[choice];
        p.* = .{ .area = section.area, .inertia = section.inertia, .young = material.young,
             .yield_stress = material.yield_stress, .density = material.density, .expansion = material.expansion,
             .stiffness = material.young * section.area / g.length };
    }
    return out;
}
pub fn memberWeight(p: Properties, g: Geometry) f64 {
    return p.density * 9.81 * p.area * g.length / 1000000000;
}
pub fn memberStiffness(p: Properties, g: Geometry) [4][4]f64 {
    const xx = p.stiffness * (g.cosine * g.cosine);
    const xy = p.stiffness * (g.cosine * g.sine);
    const yy = p.stiffness * (g.sine * g.sine);
    return .{ .{ xx, xy, -xx, -xy }, .{ xy, yy, -xy, -yy }, .{ -xx, -xy, xx, xy }, .{ -xy, -yy, xy, yy } };
}
pub fn assemble(geometry: []const Geometry, properties: []const Properties, degrees: usize, removed: ?usize) Matrix {
    const out = matrix(degrees);
    for (geometry, properties, 0..) |g, p, i| {
        if (removed == i) continue;
        const local = memberStiffness(p, g);
        for (0..4) |r| for (0..4) |c| {
            out[g.dofs[r]][g.dofs[c]] += local[r][c];
        };
    }
    return out;
}
pub const Loading = struct { external: []f64, total: []f64, temperature: []f64, settlement: bool = false };
pub fn loadVectors(load_case: d.LoadCase, geometry: []const Geometry, properties: []const Properties,
     dofs: []const [2]usize, degrees: usize, removed: ?usize) Loading {
    var out: Loading = .{ .external = zeros(degrees), .total = zeros(degrees), .temperature = zeros(geometry.len) };
    const thermal = zeros(degrees);
    for (load_case.lines) |line| switch (line.kind) {
        .force => {
            out.external[dofs[line.index][0]] += line.x * 1000;
            out.external[dofs[line.index][1]] += line.y * 1000;
        },
        .temperature => {
            const i = line.index;
            if (removed == i) continue;
            const p = properties[i];
            const g = geometry[i];
            const force = p.young * p.area * p.expansion * line.x;
            out.temperature[i] = force;
            const direction = [_]f64{ -g.cosine, -g.sine, g.cosine, g.sine };
            for (g.dofs, direction) |degree, value| thermal[degree] += force * value;
        },
        .selfweight => {
            for (geometry, properties, 0..) |g, p, i| {
                if (removed == i) continue;
                const weight = memberWeight(p, g);
                out.external[g.dofs[1]] -= weight / 2;
                out.external[g.dofs[3]] -= weight / 2;
            }
        },
        .settlement => {
            out.settlement = true;
        },
    };
    for (out.total, out.external, thermal) |*total, external, temperature| total.* = external + temperature;
    return out;
}
