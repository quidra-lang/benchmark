const std = @import("std");
const m = @import("matrix.zig");
pub const Params = struct { ca: bool = false, q_cv: f64 = 0, q_ca: f64 = 0, sigma: f64 = 0,
     velocity: f64 = 0, acceleration: f64 = 0, gate: f64 = 0, delta: f64 = 0, cutoff: f64 = 0,
     bound: f64 = 0, xmin: f64 = 0, xmax: f64 = 0, ymin: f64 = 0, ymax: f64 = 0, confirm: usize = 0,
     window: usize = 0, deletion: usize = 0, width: usize = 0, height: usize = 0, abg: [3]f64 = .{ 0,
     0, 0 }, imm_q: [2]f64 = .{ 0, 0 }, imm_initial: [2]f64 = .{ 0, 0 }, transition: [2][2]f64 = .{ .{ 0,
     0 }, .{ 0, 0 } }, edges: []const f64 = &.{} };
pub fn transition(ca: bool, t: f64) m.Matrix {
    var out = m.identity(if (ca) 6 else 4);
    out.values[0][2] = t;
    out.values[1][3] = t;
    if (ca) {
        out.values[0][4] = t * t / 2;
        out.values[1][5] = t * t / 2;
        out.values[2][4] = t;
        out.values[3][5] = t;
    }
    return out;
}
fn entry(a: *m.Matrix, axis: usize, i: usize, j: usize, value: f64) void {
    a.values[i + axis][j + axis] = value;
    a.values[j + axis][i + axis] = value;
}
pub fn processNoise(ca: bool, t: f64, q: f64) m.Matrix {
    const size: usize = if (ca) 6 else 4;
    var out = m.zeros(size, size);
    for (0..2) |axis| {
        if (ca) {
            entry(&out, axis, 0, 0, q * t * t * t * t * t / 20);
            entry(&out, axis, 0, 2, q * t * t * t * t / 8);
            entry(&out, axis, 0, 4, q * t * t * t / 6);
            entry(&out, axis, 2, 2, q * t * t * t / 3);
            entry(&out, axis, 2, 4, q * t * t / 2);
            entry(&out, axis, 4, 4, q * t);
        } else {
            entry(&out, axis, 0, 0, q * t * t * t / 3);
            entry(&out, axis, 0, 2, q * t * t / 2);
            entry(&out, axis, 2, 2, q * t);
        }
    }
    return out;
}
pub const Innovation = struct { residual: m.Position, covariance: m.Matrix, precision: m.Matrix, distance: f64 };
pub const Kalman = struct {
    ca: bool,
    q: f64,
    x: m.Vector,
    xp: m.Vector = .{},
    P: m.Matrix,
    Pp: m.Matrix = .{},
    F: m.Matrix = .{},
    H: m.Matrix,
    R: m.Matrix,
    pub fn init(ca: bool, q: f64, p: Params, measurement: m.Position) Kalman {
        const size: usize = if (ca) 6 else 4;
        const x: m.Vector = .{ .count = size, .values = .{ measurement[0], measurement[1], 0, 0, 0, 0 } };
        const variances: m.Vector = .{ .count = size, .values = .{ p.sigma * p.sigma, p.sigma * p.sigma,
             p.velocity, p.velocity, p.acceleration, p.acceleration } };
        var h = m.zeros(2, size);
        h.values[0][0] = 1;
        h.values[1][1] = 1;
        const noise: m.Vector = .{ .count = 2, .values = .{ p.sigma * p.sigma, p.sigma * p.sigma, 0, 0, 0, 0 } };
        return .{ .ca = ca, .q = q, .x = x, .P = m.diagonal(variances), .H = h, .R = m.diagonal(noise) };
    }
    pub fn predict(self: *Kalman, interval: f64) void {
        self.F = transition(self.ca, interval);
        self.x = m.matrixVector(self.F, self.x);
        self.P = m.add(m.product(m.product(self.F, self.P), m.transpose(self.F)), processNoise(self.ca,
             interval, self.q));
        self.xp = self.x;
        self.Pp = self.P;
    }
    pub fn innovation(self: Kalman, measurement: m.Position) Innovation {
        const expected = m.matrixVector(self.H, self.x);
        const residual = m.Position{ measurement[0] - expected.values[0], measurement[1] - expected.values[1] };
        const covariance = m.add(m.product(m.product(self.H, self.P), m.transpose(self.H)), self.R);
        const precision = m.inverse(covariance);
        return .{ .residual = residual, .covariance = covariance, .precision = precision, .distance = m.quadratic2(residual,
             precision) };
    }
    pub fn update(self: *Kalman, observation: Innovation) f64 {
        const gain = m.product(m.product(self.P, m.transpose(self.H)), observation.precision);
        const correction = m.subtract(m.identity(self.x.count), m.product(gain, self.H));
        const residual: m.Vector = .{ .count = 2, .values = .{ observation.residual[0], observation.residual[1],
             0, 0, 0, 0 } };
        self.x = m.vectorAdd(self.x, m.matrixVector(gain, residual));
        self.P = m.add(m.product(m.product(correction, self.P), m.transpose(correction)), m.product(m.product(gain,
             self.R), m.transpose(gain)));
        return -@log(2 * std.math.pi) - @log(m.determinant2(observation.covariance)) / 2 - observation.distance / 2;
    }
};
pub const History = struct { x: m.Vector, xp: m.Vector, P: m.Matrix, Pp: m.Matrix, F: m.Matrix };
pub fn smooth(history: []const History) []const m.Vector {
    const out = m.alloc(m.Vector, history.len);
    out[out.len - 1] = history[history.len - 1].x;
    var i = history.len - 1;
    while (i > 0) {
        i -= 1;
        const gain = m.product(m.product(history[i].P, m.transpose(history[i + 1].F)), m.inverse(history[i + 1].Pp));
        out[i] = m.vectorAdd(history[i].x, m.matrixVector(gain, m.vectorSubtract(out[i + 1], history[i + 1].xp)));
    }
    return out;
}
