const d = @import("data_io.zig");
pub const Kind = enum { seird, sir, age, generation };
pub const State = struct { values: [36]f64 = [_]f64{0} ** 36, count: usize = 0 };
pub const Model = struct {
    kind: Kind,
    beta: f64,
    gamma: f64,
    sigma: f64,
    population: f64,
    fatality: f64,
    e0: f64,
    i0: f64,
    groups: []const d.Group,
    contacts: [6][6]f64,
    pub fn initial(self: Model) State {
        var out: State = .{};
        switch (self.kind) {
            .generation => {
                out.count = 3;
                out.values[0] = 1;
            },
            .sir => {
                out.count = 4;
                out.values[0] = self.population - self.e0 - self.i0;
                out.values[1] = self.e0 + self.i0;
            },
            .seird => {
                out.count = 6;
                out.values[0] = self.population - self.e0 - self.i0;
                out.values[1] = self.e0;
                out.values[2] = self.i0;
            },
            .age => {
                out.count = 6 * self.groups.len;
                for (self.groups, 0..) |group, g| {
                    const e = self.e0 * d.f(group.population) / self.population;
                    const i = self.i0 * d.f(group.population) / self.population;
                    out.values[6 * g] = d.f(group.population) - e - i;
                    out.values[6 * g + 1] = e;
                    out.values[6 * g + 2] = i;
                }
            },
        }
        return out;
    }
    pub fn rates(self: Model, state: State, multiplier: f64) State {
        var out: State = .{ .count = state.count };
        const y = &state.values;
        const r = &out.values;
        const beta = self.beta;
        const gamma = self.gamma;
        const sigma = self.sigma;
        switch (self.kind) {
            .generation => {
                r[0] = -sigma * y[0];
                r[1] = sigma * y[0] - gamma * y[1];
                r[2] = gamma * y[1];
            },
            .sir => {
                const flow = beta * multiplier * y[0] * y[1] / self.population;
                r[0] = -flow;
                r[1] = flow - gamma * y[1];
                r[2] = gamma * y[1];
                r[3] = flow;
            },
            .seird => {
                const flow = beta * multiplier * y[0] * y[2] / self.population;
                r[0] = -flow;
                r[1] = flow - sigma * y[1];
                r[2] = sigma * y[1] - gamma * y[2];
                r[3] = (1 - self.fatality) * gamma * y[2];
                r[4] = self.fatality * gamma * y[2];
                r[5] = sigma * y[1];
            },
            .age => {
                for (self.groups, 0..) |group, g| {
                    var sum: f64 = 0;
                    for (self.groups, 0..) |other, h| sum += self.contacts[g][h] * y[6 * h + 2] / d.f(other.population);
                    const lambda = beta * multiplier * sum;
                    const flow = lambda * y[6 * g];
                    const e = y[6 * g + 1];
                    const i = y[6 * g + 2];
                    r[6 * g] = -flow;
                    r[6 * g + 1] = flow - sigma * e;
                    r[6 * g + 2] = sigma * e - gamma * i;
                    r[6 * g + 3] = (1 - group.fatality) * gamma * i;
                    r[6 * g + 4] = group.fatality * gamma * i;
                    r[6 * g + 5] = sigma * e;
                }
            },
        }
        return out;
    }
    pub fn reset(self: Model, state: *State) void {
        switch (self.kind) {
            .generation => state.values[2] = 0,
            .sir => state.values[3] = 0,
            .seird => state.values[5] = 0,
            .age => {
                for (0..self.groups.len) |g| state.values[6 * g + 5] = 0;
            },
        }
    }
};
