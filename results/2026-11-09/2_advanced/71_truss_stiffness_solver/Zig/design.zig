const d = @import("model_io.zig");
const a = @import("assembly.zig");
const post = @import("postprocess.zig");
pub const pi = 3.141592653589793;
pub fn buckling(p: a.Properties, g: a.Geometry, inertia: f64) f64 {
    return pi * pi * p.young * inertia / (g.length * g.length);
}
pub fn utilization(force: f64, p: a.Properties, g: a.Geometry, section: ?d.Section) f64 {
    const area = if (section) |s| s.area else p.area;
    const inertia = if (section) |s| s.inertia else p.inertia;
    return @max(@abs(force / area) / p.yield_stress, @max(0, -force) / buckling(p, g, inertia));
}
pub fn slenderness(p: a.Properties, g: a.Geometry, section: ?d.Section) f64 {
    const area = if (section) |s| s.area else p.area;
    const inertia = if (section) |s| s.inertia else p.inertia;
    return g.length / @sqrt(inertia / area);
}
pub fn slendernessLimit(member: usize, combinations: []const post.Result, compression: f64, tension: f64) f64 {
    for (combinations) |result| if (result.forces[member] < 0) return compression;
    return tension;
}
pub fn selectSection(members: []const usize, sections: []const d.Section, properties: []const a.Properties,
     geometry: []const a.Geometry, combinations: []const post.Result, limits: []const f64) usize {
    for (sections, 0..) |section, index| {
        var acceptable = true;
        for (members) |member| {
            if (slenderness(properties[member], geometry[member], section) > limits[member]) {
                acceptable = false;
                break;
            }
            for (combinations) |result| if (utilization(result.forces[member], properties[member],
                 geometry[member], section) > 1) {
                acceptable = false;
                break;
            };
            if (!acceptable) break;
        }
        if (acceptable) return index;
    }
    return sections.len - 1;
}
