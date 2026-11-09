const std = @import("std");
const c = @import("waveform_io.zig");
pub const Solution = [4]f64;
const Matrix = [4][4]f64;
pub const Observation = struct { station: usize, time: f64 };
pub const Iteration = struct { solution: Solution, rms: f64 };
pub const Run = struct { solution: Solution, grid: Solution = [_]f64{0} ** 4, rms: f64, grid_rms: f64 = 0,
     profile: []const f64 = &.{}, residual: [12]f64 = [_]f64{0} ** 12, trace: [8]Iteration };
pub const Ellipse = struct { smaj: f64, smin: f64, az: f64, erz: f64, ert: f64 };
pub fn distance(q: Solution, s: c.Station) f64 {
    const x = q[0] - c.f(s.x);
    const y = q[1] - c.f(s.y);
    const z = q[2] + c.f(s.elevation);
    return @sqrt(x * x + y * y + z * z);
}
pub fn residual(q: Solution, observation: Observation, stations: []const c.Station, velocity: f64) f64 {
    return observation.time - q[3] - distance(q, stations[observation.station]) / velocity;
}
pub fn rms(q: Solution, observations: []const Observation, stations: []const c.Station, velocity: f64) f64 {
    var sum: f64 = 0;
    for (observations) |observation| {
        const r = residual(q, observation, stations, velocity);
        sum += r * r;
    }
    return @sqrt(sum / c.f(observations.len));
}
fn cholesky(matrix: Matrix) Matrix {
    var lower: Matrix = [_][4]f64{[_]f64{0} ** 4} ** 4;
    for (0..4) |a| for (0..a + 1) |b| {
        var sum: f64 = 0;
        for (0..b) |j| sum += lower[a][j] * lower[b][j];
        lower[a][b] = if (a == b) @sqrt(matrix[a][a] - sum) else (matrix[a][b] - sum) / lower[b][b];
    };
    return lower;
}
fn solve(lower: Matrix, right: Solution) Solution {
    var forward: Solution = [_]f64{0} ** 4;
    var solution: Solution = [_]f64{0} ** 4;
    for (0..4) |a| {
        var sum: f64 = 0;
        for (0..a) |j| sum += lower[a][j] * forward[j];
        forward[a] = (right[a] - sum) / lower[a][a];
    }
    var remaining: usize = 4;
    while (remaining > 0) {
        remaining -= 1;
        const a = remaining;
        var sum: f64 = 0;
        for (a + 1..4) |j| sum += lower[j][a] * solution[j];
        solution[a] = (forward[a] - sum) / lower[a][a];
    }
    return solution;
}
const Normal = struct { matrix: Matrix, right: Solution };
fn normals(q: Solution, observations: []const Observation, stations: []const c.Station, velocity: f64) Normal {
    var out: Normal = .{ .matrix = [_][4]f64{[_]f64{0} ** 4} ** 4, .right = [_]f64{0} ** 4 };
    for (observations) |observation| {
        const s = stations[observation.station];
        const d = distance(q, s);
        const r = observation.time - q[3] - d / velocity;
        const g: Solution = .{ (q[0] - c.f(s.x)) / (velocity * d), (q[1] - c.f(s.y)) / (velocity * d),
             (q[2] + c.f(s.elevation)) / (velocity * d), 1 };
        for (0..4) |a| {
            out.right[a] += g[a] * r;
            for (0..4) |b| out.matrix[a][b] += g[a] * g[b];
        }
    }
    return out;
}
pub fn geiger(initial: Solution, observations: []const Observation, stations: []const c.Station, velocity: f64) Run {
    var q = initial;
    var out: Run = undefined;
    out.grid = [_]f64{0} ** 4;
    out.grid_rms = 0;
    out.profile = &.{};
    out.residual = [_]f64{0} ** 12;
    for (0..8) |iteration| {
        const normal = normals(q, observations, stations, velocity);
        const delta = solve(cholesky(normal.matrix), normal.right);
        for (0..4) |a| q[a] += delta[a];
        q[2] = @max(0, q[2]);
        out.trace[iteration] = .{ .solution = q, .rms = rms(q, observations, stations, velocity) };
    }
    out.solution = q;
    out.rms = rms(q, observations, stations, velocity);
    for (observations, 0..) |observation, j| out.residual[j] = residual(q, observation, stations, velocity);
    return out;
}
pub fn locate(observations: []const Observation, stations: []const c.Station, p: c.Params) Run {
    var best = std.math.inf(f64);
    var initial: Solution = [_]f64{0} ** 4;
    const profile = c.alloc(f64, c.u(@divExact(p.gz[1] - p.gz[0], p.gz[2]) + 1));
    @memset(profile, best);
    var x = p.gx[0];
    while (x <= p.gx[1]) : (x += p.gx[2]) {
        var y = p.gy[0];
        while (y <= p.gy[1]) : (y += p.gy[2]) {
            var z = p.gz[0];
            while (z <= p.gz[1]) : (z += p.gz[2]) {
                var q: Solution = .{ c.f(x), c.f(y), c.f(z), 0 };
                var delta: [12]f64 = undefined;
                var total: f64 = 0;
                for (observations, 0..) |observation, j| {
                    delta[j] = observation.time - distance(q, stations[observation.station]) / p.velocity;
                    total += delta[j];
                }
                q[3] = total / c.f(observations.len);
                var error_sum: f64 = 0;
                for (delta[0..observations.len]) |value| error_sum += (value - q[3]) * (value - q[3]);
                if (error_sum < best) {
                    best = error_sum;
                    initial = q;
                }
                const index = c.u(@divExact(z - p.gz[0], p.gz[2]));
                profile[index] = @min(profile[index], error_sum);
            }
        }
    }
    var out = geiger(initial, observations, stations, p.velocity);
    out.grid = initial;
    out.grid_rms = @sqrt(best / c.f(observations.len));
    for (profile) |*value| value.* = @sqrt(value.* / c.f(observations.len));
    out.profile = profile;
    return out;
}
pub fn ellipse(q: Solution, observations: []const Observation, stations: []const c.Station, velocity: f64) Ellipse {
    const lower = cholesky(normals(q, observations, stations, velocity).matrix);
    var sum: f64 = 0;
    for (observations) |observation| {
        const r = residual(q, observation, stations, velocity);
        sum += r * r;
    }
    const variance = sum / c.f(observations.len - 4);
    var covariance: Matrix = undefined;
    for (0..4) |column| {
        var unit: Solution = [_]f64{0} ** 4;
        unit[column] = 1;
        const values = solve(lower, unit);
        for (0..4) |row| covariance[row][column] = variance * values[row];
    }
    const xx = covariance[0][0];
    const yy = covariance[1][1];
    const xy = covariance[0][1];
    const mu = (xx + yy) / 2;
    const rho = @sqrt((xx - yy) * (xx - yy) / 4 + xy * xy);
    var az = 90 - std.math.atan2(2 * xy, xx - yy) / 2 * 180 / 3.141592653589793;
    if (az >= 180) az -= 180;
    if (az < 0) az += 180;
    return .{ .smaj = @sqrt(mu + rho), .smin = @sqrt(mu - rho), .az = az, .erz = @sqrt(covariance[2][2]),
         .ert = @sqrt(covariance[3][3]) };
}
