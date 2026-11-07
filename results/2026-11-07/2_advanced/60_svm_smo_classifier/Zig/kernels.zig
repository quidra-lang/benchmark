const c = @import("dataset.zig");
const e = @import("evaluation.zig");
pub fn value(kernel: c.Kernel, a: c.Point, b: c.Point) f64 {
    if (kernel.kind == .linear) return a[0] * b[0] + a[1] * b[1];
    if (kernel.kind == .poly) {
        const s = kernel.gamma * (a[0] * b[0] + a[1] * b[1]) + kernel.coef0;
        var out: f64 = 1;
        for (0..kernel.degree) |_| out *= s;
        return out;
    }
    const e1 = a[0] - b[0];
    const e2 = a[1] - b[1];
    return @exp(-kernel.gamma * (e1 * e1 + e2 * e2));
}
pub fn matrix(kernel: c.Kernel, data: []const c.Example) c.Matrix {
    const out = c.alloc([]f64, data.len);
    for (out, 0..) |*row, i| {
        row.* = c.alloc(f64, data.len);
        for (row.*, 0..) |*entry, j| entry.* = value(kernel, data[i].point, data[j].point);
    }
    return out;
}
pub fn description(kernel: c.Kernel) []const u8 {
    return switch (kernel.kind) {
        .linear => "linear",
        .rbf => c.fmt("rbf gamma {s}", .{e.real(kernel.gamma, 4)}),
        .poly => c.fmt("poly degree {d} gamma {s} coef0 {s}", .{ kernel.degree, e.real(kernel.gamma,
             4), e.real(kernel.coef0, 4) }),
    };
}
