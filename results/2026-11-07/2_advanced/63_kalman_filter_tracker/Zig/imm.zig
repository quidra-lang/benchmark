const std = @import("std");
const m = @import("matrix.zig");
const k = @import("kalman.zig");
pub const IMM = struct {
    models: [2]k.Kalman,
    probabilities: [2]f64,
    transition: [2][2]f64,
    pub fn init(p: k.Params, measurement: m.Position) IMM {
        return .{ .models = .{ k.Kalman.init(false, p.imm_q[0], p, measurement), k.Kalman.init(false,
             p.imm_q[1], p, measurement) }, .probabilities = p.imm_initial, .transition = p.transition };
    }
    pub fn step(self: *IMM, interval: f64, measurement: ?m.Position) void {
        var predicted: [2]f64 = undefined;
        var likelihood: [2]f64 = .{ 1, 1 };
        const old_x = [2]m.Vector{ self.models[0].x, self.models[1].x };
        const old_p = [2]m.Matrix{ self.models[0].P, self.models[1].P };
        for (0..2) |j| predicted[j] = self.transition[0][j] * self.probabilities[0] + self.transition[1][j] * self.probabilities[1];
        for (0..2) |j| {
            const w0 = self.transition[0][j] * self.probabilities[0] / predicted[j];
            const w1 = self.transition[1][j] * self.probabilities[1] / predicted[j];
            var mixed: m.Vector = .{ .count = 4 };
            for (0..4) |r| mixed.values[r] = w0 * old_x[0].values[r] + w1 * old_x[1].values[r];
            var covariance = m.zeros(4, 4);
            for (0..4) |r| for (0..4) |s| {
                covariance.values[r][s] = w0 * (old_p[0].values[r][s] + (old_x[0].values[r] - mixed.values[r]) * (old_x[0].values[s] - mixed.values[s])) + w1 * (old_p[1].values[r][s] + (old_x[1].values[r] - mixed.values[r]) * (old_x[1].values[s] - mixed.values[s]));
            };
            self.models[j].x = mixed;
            self.models[j].P = covariance;
            self.models[j].predict(interval);
            if (measurement) |point| {
                const observation = self.models[j].innovation(point);
                _ = self.models[j].update(observation);
                likelihood[j] = @exp(-observation.distance / 2) / (2 * std.math.pi * @sqrt(m.determinant2(observation.covariance)));
            }
        }
        const denominator = likelihood[0] * predicted[0] + likelihood[1] * predicted[1];
        for (0..2) |j| self.probabilities[j] = likelihood[j] * predicted[j] / denominator;
    }
    pub fn estimate(self: IMM) m.Vector {
        var out: m.Vector = .{ .count = 4 };
        for (0..4) |r| out.values[r] = self.probabilities[0] * self.models[0].x.values[r] + self.probabilities[1] * self.models[1].x.values[r];
        return out;
    }
};
