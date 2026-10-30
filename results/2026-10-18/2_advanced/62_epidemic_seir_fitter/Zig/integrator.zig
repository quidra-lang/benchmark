const d = @import("data_io.zig");
const m = @import("models.zig");
pub fn rk4(model: m.Model, state: m.State, multiplier: f64) m.State {
    const h: f64 = 0.25;
    const k1 = model.rates(state, multiplier);
    var point = state;
    for (0..state.count) |i| point.values[i] = state.values[i] + (h / 2) * k1.values[i];
    const k2 = model.rates(point, multiplier);
    for (0..state.count) |i| point.values[i] = state.values[i] + (h / 2) * k2.values[i];
    const k3 = model.rates(point, multiplier);
    for (0..state.count) |i| point.values[i] = state.values[i] + h * k3.values[i];
    const k4 = model.rates(point, multiplier);
    var out = state;
    for (0..state.count) |i| out.values[i] = state.values[i] + (h / 6) * (((k1.values[i] + 2 * k2.values[i]) + 2 * k3.values[i]) + k4.values[i]);
    return out;
}
pub fn simulate(model: m.Model, initial: m.State, multipliers: []const f64) []const m.State {
    const out = d.alloc(m.State, multipliers.len);
    var state = initial;
    for (multipliers, out) |multiplier, *destination| {
        model.reset(&state);
        for (0..4) |_| state = rk4(model, state, multiplier);
        destination.* = state;
    }
    return out;
}
pub fn trajectory(model: m.Model, multipliers: []const f64) []const m.State {
    return simulate(model, model.initial(), multipliers);
}
