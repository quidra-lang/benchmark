const std = @import("std");
const c = @import("dataset.zig");
const gaussian = @import("gaussian.zig");
pub const Record = struct { responsibility: [4]f64 = .{ 0, 0, 0, 0 }, scores: [4]f64 = .{ 0, 0, 0, 0 }, log_density: f64 = 0 };
pub const Expectation = struct { records: []Record, loglik: f64 = 0 };
pub const Fit = struct { model: c.Model, e: Expectation, trace: []const f64, settled: usize = 0, largest: usize = 1,
     violations: []const usize };
pub fn adjust(initial: c.Model, kind: c.Type) c.Model {
    const components = c.dupe(c.Component, initial.components);
    if (kind == .TIED) {
        var shared: c.Cov = .{ 0, 0, 0 };
        for (components) |component| for (0..3) |j| {
            shared[j] += component.weight * component.cov[j];
        };
        for (components) |*component| component.cov = shared;
    } else for (components) |*component| {
        if (kind == .DIAG) component.cov[1] = 0 else if (kind == .SPHERICAL) {
            const variance = (component.cov[0] + component.cov[2]) / 2;
            component.cov = .{ variance, 0, variance };
        }
    };
    return .{ .components = components, .kind = kind };
}
pub fn expectation(points: []const c.Point, model: c.Model) Expectation {
    var out: Expectation = .{ .records = c.alloc(Record, points.len) };
    for (points, out.records) |point, *record| {
        record.* = .{};
        var maximum = -std.math.inf(f64);
        for (model.components, 0..) |component, j| {
            record.scores[j] = gaussian.weightedLog(point.xy, component);
            maximum = @max(maximum, record.scores[j]);
        }
        var sum: f64 = 0;
        for (0..model.components.len) |j| {
            record.responsibility[j] = @exp(record.scores[j] - maximum);
            sum += record.responsibility[j];
        }
        for (0..model.components.len) |j| record.responsibility[j] /= sum;
        record.log_density = maximum + @log(sum);
        out.loglik += record.log_density;
    }
    return out;
}
fn update(points: []const c.Point, e: Expectation, k: usize, kind: c.Type, epsilon: f64) c.Model {
    const components = c.alloc(c.Component, k);
    var counts = [_]f64{0} ** 4;
    var scatter = [_][3]f64{.{ 0, 0, 0 }} ** 4;
    for (components, 0..) |*component, j| {
        component.* = .{ .weight = 0, .mean = .{ 0, 0 }, .cov = .{ 0, 0, 0 } };
        for (e.records) |record| counts[j] += record.responsibility[j];
        component.weight = counts[j] / c.f(points.len);
        for (0..2) |axis| {
            var sum: f64 = 0;
            for (points, e.records) |point, record| sum += record.responsibility[j] * point.xy[axis];
            component.mean[axis] = sum / counts[j];
        }
        for (points, e.records) |point, record| {
            const r = record.responsibility[j];
            const dx = point.xy[0] - component.mean[0];
            const dy = point.xy[1] - component.mean[1];
            scatter[j][0] += r * dx * dx;
            scatter[j][1] += r * dx * dy;
            scatter[j][2] += r * dy * dy;
        }
    }
    if (kind == .TIED) {
        var shared: c.Cov = .{ 0, 0, 0 };
        for (0..3) |axis| {
            for (0..k) |j| shared[axis] += scatter[j][axis];
            shared[axis] /= c.f(points.len);
            if (axis != 1) shared[axis] += epsilon;
        }
        for (components) |*component| component.cov = shared;
    } else for (components, 0..) |*component, j| {
        const a = scatter[j][0] / counts[j];
        const b = scatter[j][1] / counts[j];
        const d = scatter[j][2] / counts[j];
        const variance = (a + d) / 2 + epsilon;
        component.cov = if (kind == .SPHERICAL) c.Cov{ variance, 0, variance } else c.Cov{ a + epsilon,
             if (kind == .FULL) b else 0, d + epsilon };
    };
    return .{ .components = components, .kind = kind };
}
pub fn run(points: []const c.Point, initial: c.Model, kind: c.Type, p: c.Params) Fit {
    var model = adjust(initial, kind);
    var e = expectation(points, model);
    const trace = c.alloc(f64, p.iterations + 1);
    trace[0] = e.loglik;
    for (1..p.iterations + 1) |t| {
        model = update(points, e, initial.components.len, kind, p.epsilon);
        e = expectation(points, model);
        trace[t] = e.loglik;
    }
    var out: Fit = .{ .model = model, .e = e, .trace = trace, .violations = &.{} };
    for (0..trace.len) |t| {
        var settled = true;
        for (trace[t..]) |value| if (@abs(value - e.loglik) > p.tolerance) {
            settled = false;
        };
        if (settled) {
            out.settled = t;
            break;
        }
    }
    var violations: std.ArrayList(usize) = .empty;
    for (1..trace.len) |t| {
        if (trace[t] - trace[t - 1] > trace[out.largest] - trace[out.largest - 1]) out.largest = t;
        if (trace[t] < trace[t - 1] - 0.000001 * @abs(trace[t - 1])) c.append(usize, &violations, t);
    }
    out.violations = violations.items;
    return out;
}
