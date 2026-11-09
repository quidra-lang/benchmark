const c = @import("mesh.zig");
pub fn heatFlow(system: *const c.System, field: []const f64, point: usize, first: usize, last: usize) f64 {
    var out: f64 = 0;
    for (system.faces[point][first..last]) |face| {
        if (face.neighbor) |neighbor| out += face.g * (field[neighbor] - field[point]) else if (face.theta) |theta| out += face.g * (theta - field[point]);
    }
    return out;
}
pub fn thomas(lower: []const f64, diagonal: []const f64, upper: []const f64, rhs: []const f64, out: []f64) void {
    var u: [40]f64 = undefined;
    var r: [40]f64 = undefined;
    u[0] = upper[0] / diagonal[0];
    r[0] = rhs[0] / diagonal[0];
    for (1..rhs.len) |i| {
        const pivot = diagonal[i] - lower[i] * u[i - 1];
        u[i] = upper[i] / pivot;
        r[i] = (rhs[i] - lower[i] * r[i - 1]) / pivot;
    }
    out[rhs.len - 1] = r[rhs.len - 1];
    var i = rhs.len - 1;
    while (i > 0) {
        i -= 1;
        out[i] = r[i] - u[i] * out[i + 1];
    }
}
pub fn sweep(system: *const c.System, tau: f64, rhs: []const f64, horizontal: bool, out: []f64) void {
    const mesh = system.mesh;
    const count = if (horizontal) mesh.height else mesh.width;
    const length = if (horizontal) mesh.width else mesh.height;
    const first: usize = if (horizontal) 0 else 2;
    var lower: [40]f64 = undefined;
    var diagonal: [40]f64 = undefined;
    var upper: [40]f64 = undefined;
    var r: [40]f64 = undefined;
    var solved: [40]f64 = undefined;
    for (0..count) |line| {
        for (0..length) |i| {
            const point = if (horizontal) mesh.cell(line, i) else mesh.cell(i, line);
            const a = system.faces[point][first];
            const b = system.faces[point][first + 1];
            lower[i] = if (a.neighbor != null) -a.g else 0;
            diagonal[i] = system.capacity[point] / tau + a.g + b.g;
            upper[i] = if (b.neighbor != null) -b.g else 0;
            r[i] = rhs[point];
            if (a.theta) |theta| r[i] += a.g * theta;
            if (b.theta) |theta| r[i] += b.g * theta;
        }
        thomas(lower[0..length], diagonal[0..length], upper[0..length], r[0..length], solved[0..length]);
        for (0..length) |i| out[if (horizontal) mesh.cell(line, i) else mesh.cell(i, line)] = solved[i];
    }
}
pub fn advance(system: *const c.System, field: []const f64, source: []const f64, dt: f64, method: []const u8,
     out: []f64, intermediate: []f64) void {
    if (c.eq(method, "ftcs")) {
        for (out, 0..) |*value, point| value.* = field[point] + dt * (heatFlow(system, field,
             point, 0, 4) + source[point]) / system.capacity[point];
        return;
    }
    const backward = c.eq(method, "backward_euler");
    const tau = if (backward) dt else dt / 2;
    var vertical: [1000]f64 = undefined;
    var rhs: [1000]f64 = undefined;
    for (0..field.len) |point| {
        vertical[point] = heatFlow(system, field, point, 2, 4);
        rhs[point] = system.capacity[point] / tau * field[point] + vertical[point] + source[point];
    }
    sweep(system, tau, rhs[0..field.len], true, intermediate);
    for (0..field.len) |point| rhs[point] = if (backward) system.capacity[point] / tau * intermediate[point] - vertical[point] else system.capacity[point] / tau * intermediate[point] + heatFlow(system,
         intermediate, point, 0, 2) + source[point];
    sweep(system, tau, rhs[0..field.len], false, out);
}
