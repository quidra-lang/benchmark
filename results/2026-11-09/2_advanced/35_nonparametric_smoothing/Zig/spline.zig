const d = @import("dataset.zig");
pub const Values = struct { fitted: []f64, gamma: []f64 };
pub const Spline = struct {
    positions: []const i64,
    x: []f64,
    h: []f64,
    diagonal: []f64,
    l1: []f64,
    l2: []f64,
    penalty: f64,
    basis: []Values = &.{},
    pub fn init(positions: []const i64, penalty: f64) *Spline {
        const storage = d.alloc(Spline, 1);
        const self = &storage[0];
        const n = positions.len;
        const m = n - 2;
        self.* = .{ .positions = positions, .x = d.alloc(f64, n), .h = d.alloc(f64, n - 1), .diagonal = d.zero(f64,
             m), .l1 = d.zero(f64, m), .l2 = d.zero(f64, m), .penalty = penalty };
        for (positions, self.x) |position, *x| x.* = d.f(position) / 100;
        for (self.h, 0..) |*h, i| h.* = self.x[i + 1] - self.x[i];
        const a = d.alloc(f64, m);
        const b = d.alloc(f64, m);
        const c = d.alloc(f64, m);
        const diagonal = d.alloc(f64, m);
        const first = d.zero(f64, m);
        const second = d.zero(f64, m);
        for (0..m) |j| {
            a[j] = 1 / self.h[j];
            c[j] = 1 / self.h[j + 1];
            b[j] = -(a[j] + c[j]);
            diagonal[j] = (self.h[j] + self.h[j + 1]) / 3 + penalty * (a[j] * a[j] + b[j] * b[j] + c[j] * c[j]);
        }
        for (0..m - 1) |j| first[j] = self.h[j + 1] / 6 + penalty * c[j] * (b[j] + b[j + 1]);
        if (m >= 2) for (0..m - 2) |j| {
            second[j] = penalty * c[j] * c[j + 1];
        };
        for (0..m) |j| {
            if (j >= 2) self.l2[j] = second[j - 2] / self.diagonal[j - 2];
            if (j >= 1) self.l1[j] = (first[j - 1] - if (j >= 2) self.l2[j] * self.diagonal[j - 2] * self.l1[j - 1] else @as(f64,
                 0)) / self.diagonal[j - 1];
            var value = diagonal[j];
            if (j >= 1) value -= self.l1[j] * self.l1[j] * self.diagonal[j - 1];
            if (j >= 2) value -= self.l2[j] * self.l2[j] * self.diagonal[j - 2];
            self.diagonal[j] = value;
        }
        return self;
    }
    pub fn fit(self: Spline, values: []const f64) Values {
        const n = values.len;
        const m = n - 2;
        const z = d.zero(f64, m);
        const gamma = d.zero(f64, n);
        const fitted = d.alloc(f64, n);
        for (0..m) |j| {
            var value = (values[j + 2] - values[j + 1]) / self.h[j + 1] - (values[j + 1] - values[j]) / self.h[j];
            if (j >= 1) value -= self.l1[j] * z[j - 1];
            if (j >= 2) value -= self.l2[j] * z[j - 2];
            z[j] = value;
        }
        var j = m;
        while (j > 0) {
            j -= 1;
            var value = z[j] / self.diagonal[j];
            if (j + 1 < m) value -= self.l1[j + 1] * gamma[j + 2];
            if (j + 2 < m) value -= self.l2[j + 2] * gamma[j + 3];
            gamma[j + 1] = value;
        }
        for (fitted, values, 0..) |*value, observed, i| {
            const omega = if (i == 0) (gamma[1] - gamma[0]) / self.h[0] else if (i + 1 == n) 0 - (gamma[n - 1] - gamma[n - 2]) / self.h[n - 2] else (gamma[i + 1] - gamma[i]) / self.h[i] - (gamma[i] - gamma[i - 1]) / self.h[i - 1];
            value.* = observed - self.penalty * omega;
        }
        return .{ .fitted = fitted, .gamma = gamma };
    }
    pub fn evaluate(self: Spline, fit_: Values, position: i64) f64 {
        const n = self.x.len;
        var index: usize = 0;
        while (index < n and self.positions[index] < position) index += 1;
        const g = fit_.fitted;
        const gamma = fit_.gamma;
        const x0 = d.f(position) / 100;
        if (index < n and self.positions[index] == position) return g[index];
        if (index == 0) {
            const tau = (g[1] - g[0]) / self.h[0] - self.h[0] * gamma[1] / 6;
            return g[0] - (self.x[0] - x0) * tau;
        }
        if (index == n) {
            const tau = (g[n - 1] - g[n - 2]) / self.h[n - 2] + self.h[n - 2] * gamma[n - 2] / 6;
            return g[n - 1] + (x0 - self.x[n - 1]) * tau;
        }
        const i = index - 1;
        const pl = x0 - self.x[i];
        const pr = self.x[i + 1] - x0;
        return (pl * g[i + 1] + pr * g[i]) / self.h[i] - pl * pr * ((1 + pl / self.h[i]) * gamma[i + 1] + (1 + pr / self.h[i]) * gamma[i]) / 6;
    }
    pub fn prepare(self: *Spline) void {
        if (self.basis.len > 0) return;
        self.basis = d.alloc(Values, self.x.len);
        for (self.basis, 0..) |*value, i| {
            const unit = d.zero(f64, self.x.len);
            unit[i] = 1;
            value.* = self.fit(unit);
        }
    }
    pub fn leverage(self: *Spline) []f64 {
        self.prepare();
        const result = d.alloc(f64, self.x.len);
        for (self.basis, result, 0..) |value, *leverage_, i| leverage_.* = value.fitted[i];
        return result;
    }
    pub fn weights(self: Spline, position: i64) []f64 {
        const result = d.alloc(f64, self.basis.len);
        for (self.basis, result) |value, *weight| weight.* = self.evaluate(value, position);
        return result;
    }
};
