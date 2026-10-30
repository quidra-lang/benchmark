const c = @import("dataset.zig");
pub const State = struct {
    first: [1066]f64 = [_]f64{0} ** 1066,
    second: [1066]f64 = [_]f64{0} ** 1066,
    pi1: f64 = 1,
    pi2: f64 = 1,
    pub fn update(self: *State, weights: []f64, gradient: []const f64, run: c.Run, eta: f64) void {
        if (run.optimizer == .ADAM) {
            self.pi1 = self.pi1 * run.beta1;
            self.pi2 = self.pi2 * run.beta2;
        }
        for (weights, gradient, 0..) |*weight, g, p| switch (run.optimizer) {
            .SGD => weight.* = weight.* - eta * g,
            .MOMENTUM => {
                self.first[p] = run.mu * self.first[p] + g;
                weight.* = weight.* - eta * self.first[p];
            },
            .ADAM => {
                self.first[p] = run.beta1 * self.first[p] + (1 - run.beta1) * g;
                self.second[p] = run.beta2 * self.second[p] + (1 - run.beta2) * g * g;
                const m = self.first[p] / (1 - self.pi1);
                const v = self.second[p] / (1 - self.pi2);
                weight.* = weight.* - eta * m / (@sqrt(v) + run.epsilon);
            },
        };
    }
};
pub fn learningRate(run: c.Run, params: c.Params, epoch: usize) f64 {
    var out = run.eta;
    for (0..(epoch - 1) / params.lr_step) |_| out *= params.gamma;
    return out;
}
