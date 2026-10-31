const std = @import("std");
const c = @import("dataset.zig");
const kernels = @import("kernels.zig");
pub const Pass = struct { full: bool, examined: usize, changed: usize, alpha: []const f64 = &.{} };
pub const Model = struct {
    data: []const c.Example,
    kernel: c.Kernel,
    matrix: c.Matrix,
    c: f64,
    b: f64 = 0,
    alpha: []f64,
    full: usize = 0,
    nonbound: usize = 0,
    examined: usize = 0,
    steps: usize = 0,
    choices: [3]usize = .{ 0, 0, 0 },
    clipping: [3]usize = .{ 0, 0, 0 },
    converged: bool = false,
    passes: std.ArrayList(Pass) = .empty,
    pub fn decision(self: Model, point: c.Point) f64 {
        var out: f64 = 0;
        for (self.alpha, self.data) |alpha, example| if (alpha > 0) {
            out += alpha * c.f(example.label) * kernels.value(self.kernel, example.point, point);
        };
        return out - self.b;
    }
    pub fn trainingDecisions(self: Model) []f64 {
        const out = c.alloc(f64, self.data.len);
        for (out, 0..) |*entry, i| {
            var sum: f64 = 0;
            for (self.alpha, self.data, 0..) |alpha, example, j| if (alpha > 0) {
                sum += alpha * c.f(example.label) * self.matrix[i][j];
            };
            entry.* = sum - self.b;
        }
        return out;
    }
};
const Trainer = struct {
    model: Model,
    params: c.Params,
    errors: []f64,
    fn nonbound(self: *const Trainer, index: usize) bool {
        return self.model.alpha[index] > 0 and self.model.alpha[index] < self.model.c;
    }
    fn snap(self: *const Trainer, value: f64) f64 {
        return if (value < 0.00000001) 0 else if (value > self.model.c - 0.00000001) self.model.c else value;
    }
    fn take(self: *Trainer, i1: usize, i2: usize) bool {
        if (i1 == i2) return false;
        const model = &self.model;
        const alpha1 = model.alpha[i1];
        const alpha2 = model.alpha[i2];
        const y1 = c.f(model.data[i1].label);
        const y2 = c.f(model.data[i2].label);
        const e1 = self.errors[i1];
        const e2 = self.errors[i2];
        const lo = if (y1 != y2) @max(0, alpha2 - alpha1) else @max(0, alpha2 + alpha1 - model.c);
        const hi = if (y1 != y2) @min(model.c, model.c + alpha2 - alpha1) else @min(model.c, alpha2 + alpha1);
        if (lo == hi) return false;
        const k11 = model.matrix[i1][i1];
        const k12 = model.matrix[i1][i2];
        const k22 = model.matrix[i2][i2];
        const eta = k11 + k22 - 2 * k12;
        if (eta <= 0) return false;
        var a2 = alpha2 + y2 * (e1 - e2) / eta;
        var clipping: usize = 0;
        if (a2 < lo) {
            a2 = lo;
            clipping = 1;
        } else if (a2 > hi) {
            a2 = hi;
            clipping = 2;
        }
        a2 = self.snap(a2);
        if (@abs(a2 - alpha2) < self.params.epsilon * (a2 + alpha2 + self.params.epsilon)) return false;
        const a1 = self.snap(alpha1 + y1 * y2 * (alpha2 - a2));
        const t1 = y1 * (a1 - alpha1);
        const t2 = y2 * (a2 - alpha2);
        const b1 = e1 + t1 * k11 + t2 * k12 + model.b;
        const b2 = e2 + t1 * k12 + t2 * k22 + model.b;
        const threshold = if (a1 > 0 and a1 < model.c) b1 else if (a2 > 0 and a2 < model.c) b2 else (b1 + b2) / 2;
        const delta = threshold - model.b;
        for (self.errors, 0..) |*cached_error, i| cached_error.* = cached_error.* + (t1 * model.matrix[i1][i] + t2 * model.matrix[i2][i] - delta);
        if (a1 > 0 and a1 < model.c) self.errors[i1] = 0;
        if (a2 > 0 and a2 < model.c) self.errors[i2] = 0;
        model.alpha[i1] = a1;
        model.alpha[i2] = a2;
        model.b = threshold;
        model.steps += 1;
        model.clipping[clipping] += 1;
        return true;
    }
    fn examine(self: *Trainer, i2: usize) usize {
        self.model.examined += 1;
        const r2 = self.errors[i2] * c.f(self.model.data[i2].label);
        if (!((r2 < -self.params.tolerance and self.model.alpha[i2] < self.model.c) or (r2 > self.params.tolerance and self.model.alpha[i2] > 0))) return 0;
        var best: ?usize = null;
        var distance: f64 = -1;
        for (self.errors, 0..) |cached_error, i| if (i != i2 and self.nonbound(i)) {
            const next = @abs(cached_error - self.errors[i2]);
            if (next > distance) {
                best = i;
                distance = next;
            }
        };
        if (best) |i| if (self.take(i, i2)) {
            self.model.choices[0] += 1;
            return 1;
        };
        for (0..self.errors.len) |i| if (self.nonbound(i) and self.take(i, i2)) {
            self.model.choices[1] += 1;
            return 1;
        };
        for (0..self.errors.len) |i| if (self.take(i, i2)) {
            self.model.choices[2] += 1;
            return 1;
        };
        return 0;
    }
    fn run(self: *Trainer) Model {
        var all = true;
        while (true) {
            const before = self.model.examined;
            var changed: usize = 0;
            for (0..self.errors.len) |i| if (all or self.nonbound(i)) {
                changed += self.examine(i);
            };
            if (all) self.model.full += 1 else self.model.nonbound += 1;
            c.append(Pass, &self.model.passes, .{ .full = all, .examined = self.model.examined - before,
                 .changed = changed, .alpha = if (all) c.dupe(f64, self.model.alpha) else &.{} });
            if (all and changed == 0) {
                self.model.converged = true;
                break;
            }
            if (self.model.passes.items.len == self.params.max_passes) break;
            if (all) all = false else if (changed == 0) all = true;
        }
        return self.model;
    }
};
pub fn train(data: []const c.Example, kernel: c.Kernel, matrix: c.Matrix, coefficient: f64, params: c.Params) Model {
    const alpha = c.alloc(f64, data.len);
    @memset(alpha, 0);
    var errors: [200]f64 = undefined;
    for (data, 0..) |example, i| errors[i] = -c.f(example.label);
    var trainer: Trainer = .{ .model = .{ .data = data, .kernel = kernel, .matrix = matrix,
         .c = coefficient, .alpha = alpha }, .params = params, .errors = errors[0..data.len] };
    return trainer.run();
}
