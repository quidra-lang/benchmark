const io = @import("series_io.zig");
const d = @import("decomposition.zig");
pub const Parameters = struct { alpha: f64 = 0, beta: f64 = 0, gamma: f64 = 0, phi: f64 = 1 };
pub const State = struct { level: f64 = 0, slope: f64 = 0, seasonal: []f64 = &.{} };
pub const Smoothed = struct { residuals: []f64 = &.{}, states: []State = &.{} };
pub fn smooth(method: usize, values: []const f64, season: usize, p: Parameters) Smoothed {
    const winters = method == 6 or method == 7;
    var state: State = .{ .level = values[0] };
    if (winters) {
        state.level = d.total(values[0..season]) / io.f(season);
        state.slope = (d.total(values[season .. 2 * season]) / io.f(season) - state.level) / io.f(season);
        state.seasonal = io.alloc(f64, season);
        for (state.seasonal, 0..) |*component, j| component.* = if (method == 6) values[j] - state.level else values[j] / state.level;
    } else if (method != 3) state.slope = (values[season] - values[0]) / io.f(season);
    const result: Smoothed = .{ .residuals = io.alloc(f64, values.len), .states = io.alloc(State, values.len + 1) };
    for (values, 0..) |observed, t| {
        result.states[t] = .{ .level = state.level, .slope = state.slope, .seasonal = io.dupe(f64, state.seasonal) };
        var predicted: f64 = undefined;
        var next_level: f64 = undefined;
        var next_slope: f64 = undefined;
        if (method == 3) {
            predicted = state.level;
            next_level = p.alpha * observed + (1 - p.alpha) * state.level;
            next_slope = state.slope;
        } else if (winters) {
            const position = t % season;
            const previous = state.seasonal[position];
            const base = state.level + state.slope;
            if (method == 6) {
                predicted = base + previous;
                next_level = p.alpha * (observed - previous) + (1 - p.alpha) * base;
                state.seasonal[position] = p.gamma * (observed - base) + (1 - p.gamma) * previous;
            } else {
                predicted = base * previous;
                next_level = p.alpha * (observed / previous) + (1 - p.alpha) * base;
                state.seasonal[position] = p.gamma * (observed / base) + (1 - p.gamma) * previous;
            }
            next_slope = p.beta * (next_level - state.level) + (1 - p.beta) * state.slope;
        } else {
            predicted = state.level + p.phi * state.slope;
            next_level = p.alpha * observed + (1 - p.alpha) * predicted;
            next_slope = p.beta * (next_level - state.level) + (1 - p.beta) * p.phi * state.slope;
        }
        result.residuals[t] = observed - predicted;
        state.level = next_level;
        state.slope = next_slope;
    }
    result.states[values.len] = state;
    return result;
}
pub fn forecast(method: usize, state: State, p: Parameters, origin: usize, steps: usize, season: usize) []f64 {
    const result = io.alloc(f64, steps);
    var power = p.phi;
    var accumulated: f64 = 0;
    for (result, 1..) |*value, k| {
        if (method == 3) value.* = state.level else if (method == 4 or method == 5) {
            accumulated += power;
            value.* = state.level + accumulated * state.slope;
            power *= p.phi;
        } else {
            const component = state.seasonal[(origin + k - 1) % season];
            const base = state.level + io.f(k) * state.slope;
            value.* = if (method == 6) base + component else base * component;
        }
    }
    return result;
}
