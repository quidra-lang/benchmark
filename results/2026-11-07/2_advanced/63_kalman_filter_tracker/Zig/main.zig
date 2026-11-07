const std = @import("std");
const m = @import("matrix.zig");
const kalman = @import("kalman.zig");
const association = @import("association.zig");
const imm = @import("imm.zig");
const evaluation = @import("evaluation.zig");
const real = evaluation.real;
const f = m.f;
const Target = struct { number: i64, first: usize, last: usize, positions: [101]?m.Position = [_]?m.Position{null} ** 101 };
const Input = struct { params: kalman.Params = .{}, measurements: [101]std.ArrayList(m.Position) = [_]std.ArrayList(m.Position){.empty} ** 101,
     scans: usize = 0, times: [101]f64 = [_]f64{0} ** 101, targets: std.ArrayList(Target) = .empty };
fn readInputs(io: std.Io) !*Input {
    const out = m.create(Input, .{});
    const measurements = try m.readLines(io, "input/measurements.csv");
    for (measurements[1..]) |line| {
        const row = m.split(line, ',');
        const scan = m.u(m.number(row[0]));
        out.scans = scan;
        out.times[scan] = m.real(row[1]);
        m.append(m.Position, &out.measurements[scan], .{ m.real(row[2]), m.real(row[3]) });
    }
    const truth = try m.readLines(io, "input/truth.csv");
    for (truth[1..]) |line| {
        const row = m.split(line, ',');
        const number = m.number(row[0]);
        const scan = m.u(m.number(row[1]));
        if (out.targets.items.len == 0 or out.targets.items[out.targets.items.len - 1].number != number) m.append(Target,
             &out.targets, .{ .number = number, .first = scan, .last = scan });
        const target = &out.targets.items[out.targets.items.len - 1];
        target.last = scan;
        target.positions[scan] = .{ m.real(row[2]), m.real(row[3]) };
    }
    const p = &out.params;
    for (try m.readLines(io, "input/params.txt")) |line| {
        const row = m.words(line);
        const key = row[0];
        if (m.eq(key, "MODEL")) p.ca = m.eq(row[1], "CA") else if (m.eq(key, "Q_CV")) p.q_cv = m.real(row[1]) else if (m.eq(key,
             "Q_CA")) p.q_ca = m.real(row[1]) else if (m.eq(key, "SIGMA")) p.sigma = m.real(row[1]) else if (m.eq(key,
             "INIT_VELOCITY_VARIANCE")) p.velocity = m.real(row[1]) else if (m.eq(key, "INIT_ACCELERATION_VARIANCE")) p.acceleration = m.real(row[1]) else if (m.eq(key,
             "GATE")) p.gate = m.real(row[1]) else if (m.eq(key, "CONFIRM")) {
            p.confirm = m.u(m.number(row[1]));
            p.window = m.u(m.number(row[2]));
        } else if (m.eq(key, "DELETE")) p.deletion = m.u(m.number(row[1])) else if (m.eq(key, "ABG")) {
            for (0..3) |i| p.abg[i] = m.real(row[i + 1]);
        } else if (m.eq(key, "IMM_Q")) {
            for (0..2) |i| p.imm_q[i] = m.real(row[i + 1]);
        } else if (m.eq(key, "IMM_TRANSITION")) {
            for (0..2) |i| for (0..2) |j| {
                p.transition[i][j] = m.real(row[1 + 2 * i + j]);
            };
        } else if (m.eq(key, "IMM_INITIAL")) {
            for (0..2) |i| p.imm_initial[i] = m.real(row[i + 1]);
        } else if (m.eq(key, "MATCH_DISTANCE")) p.delta = m.real(row[1]) else if (m.eq(key,
             "OSPA_CUTOFF")) p.cutoff = m.real(row[1]) else if (m.eq(key, "CONSISTENCY_BOUND")) p.bound = m.real(row[1]) else if (m.eq(key,
             "NIS_EDGES")) {
            const values = m.alloc(f64, row.len - 1);
            for (row[1..], values) |value, *destination| destination.* = m.real(value);
            p.edges = values;
        } else if (m.eq(key, "PLOT_X")) {
            p.xmin = m.real(row[1]);
            p.xmax = m.real(row[2]);
        } else if (m.eq(key, "PLOT_Y")) {
            p.ymin = m.real(row[1]);
            p.ymax = m.real(row[2]);
        } else if (m.eq(key, "PLOT_SIZE")) {
            p.width = m.u(m.number(row[1]));
            p.height = m.u(m.number(row[2]));
        }
    }
    return out;
}
const TrackAnalysis = struct { estimates: [5][101]m.Vector = std.mem.zeroes([5][101]m.Vector),
     covariances: [101]m.Matrix = std.mem.zeroes([101]m.Matrix), high: [101]f64 = [_]f64{0} ** 101,
     logs: [2]f64 = .{ 0, 0 }, path: f64 = 0, mean_distance: f64 = 0, longest_gap: usize = 0,
     common: usize = 0, target: ?usize = null, primary_matches: [101]?usize = [_]?usize{null} ** 101 };
const Track = struct { number: usize, birth: usize, last_hit: usize, confirmed: ?usize = null,
     deleted: ?usize = null, hits: usize = 1, misses: usize = 0, status: enum { tentative,
     confirmed, deleted } = .tentative, filter: kalman.Kalman, observations: [101]?m.Position = [_]?m.Position{null} ** 101,
     nis: [101]?f64 = [_]?f64{null} ** 101, analysis: *TrackAnalysis = undefined };
const Result = struct { track: ?usize = null, common: usize = 0, velocity_count: usize = 0,
     inside: usize = 0, position: [5]f64 = [_]f64{0} ** 5, velocity: [5]f64 = [_]f64{0} ** 5,
     nees: f64 = 0 };
fn position(vector: m.Vector) m.Position {
    return .{ vector.values[0], vector.values[1] };
}
fn optional(value: ?usize) []const u8 {
    return if (value) |number| m.fmt("{d}", .{number}) else "-";
}
const filters = [5][]const u8{ "cv", "ca", "abg", "imm", "rts" };
fn listed(key: []const u8, values: m.Lines) []const u8 {
    var out: m.Text = .{};
    out.add("{s}", .{key});
    for (values.data.items) |value| out.add(" {s}", .{value});
    if (values.data.items.len == 0) out.add(" none", .{});
    return out.value();
}
fn scores(values: [5]f64) []const u8 {
    var out: m.Text = .{};
    var best: usize = 0;
    for (values, 0..) |value, i| {
        out.add("{s}{s} {s}", .{ if (i > 0) " " else "", filters[i], real(value) });
        if (m.real(real(value)) < m.real(real(values[best]))) best = i;
    }
    out.add(" best {s}", .{filters[best]});
    return out.value();
}
fn frame(out: *m.Lines, grid: []const []u8) void {
    const border = m.alloc(u8, grid[0].len + 2);
    @memset(border, '-');
    border[0] = '+';
    border[border.len - 1] = '+';
    out.add("{s}", .{border});
    for (grid) |row| out.add("|{s}|", .{row});
    out.add("{s}", .{border});
}
const Candidate = struct { row: usize, column: usize, cost: f64 };
fn candidateLess(_: void, a: Candidate, b: Candidate) bool {
    if (a.cost != b.cost) return a.cost < b.cost;
    if (a.row != b.row) return a.row < b.row;
    return a.column < b.column;
}
fn pairLess(_: void, a: association.Pair, b: association.Pair) bool {
    return if (a.row != b.row) a.row < b.row else a.column < b.column;
}
const Analysis = struct {
    input: *const Input,
    primary: usize,
    tracks: []Track,
    track_count: usize = 0,
    evaluated: std.ArrayList(usize) = .empty,
    track_rows: m.Lines = .{},
    log: m.Lines = .{},
    conflict_m: usize = 0,
    conflict_t: usize = 0,
    greedy_differences: usize = 0,
    labels: [5][10][101]i64 = std.mem.zeroes([5][10][101]i64),
    sizes: [100][2]usize = std.mem.zeroes([100][2]usize),
    matched_tracks: [10]?usize = [_]?usize{null} ** 10,
    ospa_values: [5][100]f64 = std.mem.zeroes([5][100]f64),
    overall_position: [5]f64 = [_]f64{0} ** 5,
    overall_velocity: [5]f64 = [_]f64{0} ** 5,
    continuities: [5][10]evaluation.Continuity = undefined,
    results: [10]Result = [_]Result{.{}} ** 10,
    fn tracking(self: *Analysis) void {
        const input = self.input;
        const p = input.params;
        self.track_rows.add("track,scan,x,y,vx,vy,status", .{});
        for (1..input.scans + 1) |scan| {
            var live: std.ArrayList(usize) = .empty;
            for (self.tracks[0..self.track_count], 0..) |track, i| {
                if (track.status != .deleted) m.append(usize, &live, i);
            }
            const measurements = input.measurements[scan].items;
            const rows = live.items.len;
            const columns = measurements.len;
            if (scan > 1) {
                for (live.items) |index| self.tracks[index].filter.predict(input.times[scan] - input.times[scan - 1]);
            }
            const costs = m.alloc(f64, rows * columns);
            @memset(costs, 0);
            const usable = m.alloc(bool, costs.len);
            @memset(usable, false);
            const row_gates = m.alloc(usize, rows);
            @memset(row_gates, 0);
            var column_gates: [20]usize = [_]usize{0} ** 20;
            var candidates: std.ArrayList(Candidate) = .empty;
            var gates: m.Lines = .{};
            for (live.items, 0..) |index, i| for (measurements, 0..) |point, j| {
                const observation = self.tracks[index].filter.innovation(point);
                if (observation.distance <= p.gate) {
                    const offset = i * columns + j;
                    costs[offset] = observation.distance;
                    usable[offset] = true;
                    row_gates[i] += 1;
                    column_gates[j] += 1;
                    m.append(Candidate, &candidates, .{ .row = i, .column = j, .cost = observation.distance });
                    gates.add("{d}:{d}={s}", .{ self.tracks[index].number, j + 1, real(observation.distance) });
                }
            };
            const assigned = association.optimalAssignment(costs, usable, rows, columns);
            std.mem.sort(Candidate, candidates.items, {}, candidateLess);
            const used_rows = m.alloc(bool, rows);
            @memset(used_rows, false);
            var used_columns: [20]bool = [_]bool{false} ** 20;
            var greedy: std.ArrayList(association.Pair) = .empty;
            for (candidates.items) |candidate| {
                if (!used_rows[candidate.row] and !used_columns[candidate.column]) {
                    m.append(association.Pair, &greedy, .{ .row = candidate.row, .column = candidate.column });
                    used_rows[candidate.row] = true;
                    used_columns[candidate.column] = true;
                }
            }
            std.mem.sort(association.Pair, greedy.items, {}, pairLess);
            var different = assigned.len != greedy.items.len;
            if (!different) {
                for (assigned, greedy.items) |a, b| {
                    if (a.row != b.row or a.column != b.column) different = true;
                }
            }
            self.greedy_differences += @intFromBool(different);
            const matches = m.alloc(?usize, rows);
            @memset(matches, null);
            @memset(&used_columns, false);
            var assignment_items: m.Lines = .{};
            var greedy_items: m.Lines = .{};
            var missed: m.Lines = .{};
            var confirmed: m.Lines = .{};
            var deleted: m.Lines = .{};
            var new_items: m.Lines = .{};
            for (assigned) |pair| {
                matches[pair.row] = pair.column;
                used_columns[pair.column] = true;
                assignment_items.add("{d}:{d}", .{ self.tracks[live.items[pair.row]].number, pair.column + 1 });
            }
            for (greedy.items) |pair| greedy_items.add("{d}:{d}", .{ self.tracks[live.items[pair.row]].number,
                 pair.column + 1 });
            for (live.items, 0..) |index, row| {
                const track = &self.tracks[index];
                if (matches[row]) |column| {
                    _ = track.filter.update(track.filter.innovation(measurements[column]));
                    track.observations[scan] = measurements[column];
                    track.nis[scan] = costs[row * columns + column];
                    track.last_hit = scan;
                    track.hits += 1;
                    track.misses = 0;
                } else {
                    track.misses += 1;
                    missed.add("{d}", .{track.number});
                }
                if (track.status == .confirmed) {
                    if (track.misses >= p.deletion) {
                        track.status = .deleted;
                        track.deleted = scan;
                        deleted.add("{d}", .{track.number});
                    }
                } else if (track.hits >= p.confirm) {
                    track.status = .confirmed;
                    track.confirmed = scan;
                    confirmed.add("{d}", .{track.number});
                } else if (scan - track.birth + 1 >= p.window) {
                    track.status = .deleted;
                    track.deleted = scan;
                    deleted.add("{d}", .{track.number});
                }
            }
            var processed: std.ArrayList(usize) = .empty;
            for (live.items) |index| m.append(usize, &processed, index);
            for (measurements, 0..) |point, j| {
                if (used_columns[j]) continue;
                const index = self.track_count;
                self.track_count += 1;
                const track = &self.tracks[index];
                track.* = .{ .number = index + 1, .birth = scan, .last_hit = scan, .filter = kalman.Kalman.init(p.ca,
                     if (p.ca) p.q_ca else p.q_cv, p, point) };
                track.observations[scan] = point;
                m.append(usize, &processed, index);
                new_items.add("{d}:{d}", .{ index + 1, j + 1 });
            }
            var cm: usize = 0;
            var ct: usize = 0;
            var tentative: usize = 0;
            var confirmed_count: usize = 0;
            for (column_gates[0..columns]) |value| cm += @intFromBool(value >= 2);
            for (row_gates) |value| ct += @intFromBool(value >= 2);
            self.conflict_m += cm;
            self.conflict_t += ct;
            for (self.tracks[0..self.track_count]) |track| {
                tentative += @intFromBool(track.status == .tentative);
                confirmed_count += @intFromBool(track.status == .confirmed);
            }
            self.log.add("scan {d} tracks {d} measurements {d}", .{ scan, rows, columns });
            self.log.add("{s}", .{listed("gate", gates)});
            self.log.add("{s}", .{listed("assign", assignment_items)});
            self.log.add("{s}", .{listed("greedy", greedy_items)});
            self.log.add("{s}", .{listed("missed", missed)});
            self.log.add("{s}", .{listed("new", new_items)});
            self.log.add("{s}", .{listed("confirmed", confirmed)});
            self.log.add("{s}", .{listed("deleted", deleted)});
            self.log.add("status tentative {d} confirmed {d}", .{ tentative, confirmed_count });
            self.log.add("conflicts measurements {d} tracks {d}", .{ cm, ct });
            for (processed.items) |index| {
                const track = self.tracks[index];
                self.track_rows.add("{d},{d},{s},{s},{s},{s},{s}", .{ track.number, scan, real(track.filter.x.values[0]),
                     real(track.filter.x.values[1]), real(track.filter.x.values[2]), real(track.filter.x.values[3]),
                     @tagName(track.status) });
            }
        }
        for (self.tracks[0..self.track_count], 0..) |track, i| {
            if (track.confirmed != null) m.append(usize, &self.evaluated, i);
        }
    }
    fn comparedFilters(self: *Analysis) void {
        const input = self.input;
        const p = input.params;
        for (self.evaluated.items) |index| {
            const track = &self.tracks[index];
            const analysis = m.create(TrackAnalysis, .{});
            track.analysis = analysis;
            const history = m.alloc(kalman.History, track.last_hit - track.birth + 1);
            for (0..2) |kind| {
                var filter = kalman.Kalman.init(kind == 1, if (kind == 1) p.q_ca else p.q_cv,
                     p, track.observations[track.birth].?);
                for (track.birth..track.last_hit + 1) |scan| {
                    if (scan > track.birth) {
                        filter.predict(input.times[scan] - input.times[scan - 1]);
                        if (track.observations[scan]) |point| analysis.logs[kind] += filter.update(filter.innovation(point));
                    }
                    analysis.estimates[kind][scan] = filter.x;
                    if (kind == self.primary) {
                        history[scan - track.birth] = .{ .x = filter.x, .xp = filter.xp, .P = filter.P,
                             .Pp = filter.Pp, .F = filter.F };
                        analysis.covariances[scan] = filter.P;
                    }
                }
            }
            const smoothed = kalman.smooth(history);
            for (track.birth..track.last_hit + 1) |scan| analysis.estimates[4][scan] = smoothed[scan - track.birth];
            const initial = track.observations[track.birth].?;
            var abg: m.Vector = .{ .count = 6, .values = .{ initial[0], initial[1], 0, 0, 0, 0 } };
            var mixed = imm.IMM.init(p, initial);
            var gap: usize = 0;
            for (track.birth..track.last_hit + 1) |scan| {
                if (scan > track.birth) {
                    const t = input.times[scan] - input.times[scan - 1];
                    for (0..2) |axis| {
                        var location = abg.values[axis];
                        var velocity = abg.values[axis + 2];
                        var acceleration = abg.values[axis + 4];
                        location = location + t * velocity + t * t * acceleration / 2;
                        velocity = velocity + t * acceleration;
                        if (track.observations[scan]) |point| {
                            const residual = point[axis] - location;
                            location = location + p.abg[0] * residual;
                            velocity = velocity + p.abg[1] * residual / t;
                            acceleration = acceleration + 2 * p.abg[2] * residual / (t * t);
                        }
                        abg.values[axis] = location;
                        abg.values[axis + 2] = velocity;
                        abg.values[axis + 4] = acceleration;
                    }
                    mixed.step(t, track.observations[scan]);
                }
                analysis.estimates[2][scan] = abg;
                analysis.estimates[3][scan] = mixed.estimate();
                analysis.high[scan] = mixed.probabilities[1];
                gap = if (track.observations[scan] == null) gap + 1 else 0;
                analysis.longest_gap = @max(analysis.longest_gap, gap);
                if (scan > track.birth) analysis.path += evaluation.distance(position(analysis.estimates[4][scan - 1]),
                     position(analysis.estimates[4][scan]));
            }
        }
    }
    fn scanEvaluation(self: *Analysis) void {
        const input = self.input;
        const p = input.params;
        for (&self.labels) |*by_target| for (by_target) |*sequence| {
            @memset(sequence, -1);
        };
        for (1..input.scans + 1) |scan| {
            var active: std.ArrayList(usize) = .empty;
            var targets: std.ArrayList(usize) = .empty;
            var truth: std.ArrayList(m.Position) = .empty;
            for (self.evaluated.items) |index| {
                const track = self.tracks[index];
                if (track.birth <= scan and scan <= track.last_hit) m.append(usize, &active, index);
            }
            for (input.targets.items, 0..) |target, b| {
                if (target.positions[scan]) |point| {
                    m.append(usize, &targets, b);
                    m.append(m.Position, &truth, point);
                }
            }
            const rows = active.items.len;
            const columns = targets.items.len;
            self.sizes[scan - 1] = .{ columns, rows };
            for (0..5) |kind| {
                const costs = m.alloc(f64, rows * columns);
                @memset(costs, 0);
                const usable = m.alloc(bool, costs.len);
                @memset(usable, false);
                const estimates = m.alloc(m.Position, rows);
                for (active.items, 0..) |index, i| {
                    estimates[i] = position(self.tracks[index].analysis.estimates[kind][scan]);
                    for (truth.items, 0..) |point, j| {
                        const value = evaluation.distance(estimates[i], point);
                        if (value <= p.delta) {
                            costs[i * columns + j] = value;
                            usable[i * columns + j] = true;
                        }
                    }
                }
                for (association.optimalAssignment(costs, usable, rows, columns)) |pair| {
                    const index = active.items[pair.row];
                    const target = targets.items[pair.column];
                    self.labels[kind][target][scan] = m.n(self.tracks[index].number);
                    if (kind == self.primary) self.tracks[index].analysis.primary_matches[scan] = target;
                }
                self.ospa_values[kind][scan - 1] = evaluation.ospa(estimates, truth.items, p.cutoff);
            }
        }
        for (0..5) |kind| for (input.targets.items, 0..) |target, b| {
            self.continuities[kind][b] = evaluation.continuity(self.labels[kind][b][target.first .. target.last + 1]);
        };
    }
    fn matchTracks(self: *Analysis) void {
        const input = self.input;
        const rows = self.evaluated.items.len;
        const columns = input.targets.items.len;
        const costs = m.alloc(f64, rows * columns);
        @memset(costs, 0);
        const usable = m.alloc(bool, costs.len);
        @memset(usable, false);
        for (self.evaluated.items, 0..) |index, i| {
            const track = self.tracks[index];
            for (input.targets.items, 0..) |target, b| {
                var sum: f64 = 0;
                var count: usize = 0;
                var close = false;
                for (1..input.scans + 1) |scan| {
                    const in_track = track.birth <= scan and scan <= track.last_hit;
                    const point = target.positions[scan];
                    if (!in_track and point == null) continue;
                    count += 1;
                    if (in_track and point != null) {
                        const value = evaluation.distance(position(track.analysis.estimates[self.primary][scan]),
                             point.?);
                        sum += @min(input.params.cutoff, value);
                        close = close or value < input.params.cutoff;
                    } else sum += input.params.cutoff;
                }
                if (close) {
                    usable[i * columns + b] = true;
                    costs[i * columns + b] = sum / f(count);
                }
            }
        }
        for (association.optimalAssignment(costs, usable, rows, columns)) |pair| {
            const index = self.evaluated.items[pair.row];
            const track = &self.tracks[index];
            track.analysis.target = pair.column;
            track.analysis.mean_distance = costs[pair.row * columns + pair.column];
            self.matched_tracks[pair.column] = index;
            for (track.birth..track.last_hit + 1) |scan| track.analysis.common += @intFromBool(input.targets.items[pair.column].positions[scan] != null);
        }
    }
    fn evaluateErrors(self: *Analysis) void {
        const input = self.input;
        var position_sum: [5]f64 = [_]f64{0} ** 5;
        var velocity_sum: [5]f64 = [_]f64{0} ** 5;
        var position_count: usize = 0;
        var velocity_count: usize = 0;
        for (input.targets.items, 0..) |target, b| {
            const index = self.matched_tracks[b] orelse continue;
            const track = self.tracks[index];
            const result = &self.results[b];
            result.track = index;
            var ps: [5]f64 = [_]f64{0} ** 5;
            var vs: [5]f64 = [_]f64{0} ** 5;
            var nees_sum: f64 = 0;
            for (target.first..target.last + 1) |scan| {
                if (scan < track.birth or scan > track.last_hit) continue;
                result.common += 1;
                position_count += 1;
                var velocity: ?m.Position = null;
                if (scan > target.first and scan < target.last) {
                    const interval = input.times[scan + 1] - input.times[scan - 1];
                    const following = target.positions[scan + 1].?;
                    const previous = target.positions[scan - 1].?;
                    velocity = .{ (following[0] - previous[0]) / interval, (following[1] - previous[1]) / interval };
                    result.velocity_count += 1;
                    velocity_count += 1;
                }
                const truth = target.positions[scan].?;
                for (0..5) |kind| {
                    const x = track.analysis.estimates[kind][scan];
                    const pe = evaluation.squaredDistance(position(x), truth);
                    ps[kind] += pe;
                    position_sum[kind] += pe;
                    if (velocity) |v| {
                        const ve = evaluation.squaredDistance(.{ x.values[2], x.values[3] }, v);
                        vs[kind] += ve;
                        velocity_sum[kind] += ve;
                    }
                }
                const x = track.analysis.estimates[self.primary][scan];
                var covariance = m.zeros(2, 2);
                for (0..2) |i| for (0..2) |j| {
                    covariance.values[i][j] = track.analysis.covariances[scan].values[i][j];
                };
                const nees = m.quadratic2(.{ x.values[0] - truth[0], x.values[1] - truth[1] }, m.inverse(covariance));
                nees_sum += nees;
                result.inside += @intFromBool(nees <= input.params.bound);
            }
            for (0..5) |kind| {
                result.position[kind] = @sqrt(ps[kind] / f(result.common));
                result.velocity[kind] = @sqrt(vs[kind] / f(result.velocity_count));
            }
            result.nees = nees_sum / f(result.common);
        }
        for (0..5) |kind| {
            self.overall_position[kind] = @sqrt(position_sum[kind] / f(position_count));
            self.overall_velocity[kind] = @sqrt(velocity_sum[kind] / f(velocity_count));
        }
    }
    fn evaluationReport(self: *const Analysis) m.Lines {
        const input = self.input;
        const p = input.params;
        var out: m.Lines = .{};
        var measurements: usize = 0;
        var false_tracks: usize = 0;
        var used: usize = 0;
        var lost: usize = 0;
        for (input.measurements[1 .. input.scans + 1]) |list| measurements += list.items.len;
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            var matched = false;
            for (track.analysis.primary_matches[track.birth .. track.last_hit + 1]) |target| matched = matched or target != null;
            false_tracks += @intFromBool(!matched);
            used += track.hits;
        }
        for (self.matched_tracks[0..input.targets.items.len]) |value| lost += @intFromBool(value == null);
        out.add("summary", .{});
        out.add("scans {d}", .{input.scans});
        out.add("measurements {d}", .{measurements});
        out.add("targets {d}", .{input.targets.items.len});
        out.add("tracks_created {d}", .{self.track_count});
        out.add("tracks_confirmed {d}", .{self.evaluated.items.len});
        out.add("false_tracks {d}", .{false_tracks});
        out.add("missed_targets {d}", .{lost});
        out.add("measurements_used {d}", .{used});
        out.add("conflict_measurements {d}", .{self.conflict_m});
        out.add("conflict_tracks {d}", .{self.conflict_t});
        out.add("greedy_differences {d}", .{self.greedy_differences});
        out.add("", .{});
        out.add("targets", .{});
        for (input.targets.items) |target| {
            var path: f64 = 0;
            for (target.first + 1..target.last + 1) |scan| path += evaluation.distance(target.positions[scan - 1].?,
                 target.positions[scan].?);
            out.add("target {d} first {d} last {d} scans {d} path {s} mean_speed {s}", .{ target.number,
                 target.first, target.last, target.last - target.first + 1, real(path), real(path / (input.times[target.last] - input.times[target.first])) });
        }
        out.add("", .{});
        out.add("tracks", .{});
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            var sum: f64 = 0;
            var inside: usize = 0;
            var count: usize = 0;
            for (track.nis[track.birth .. track.last_hit + 1]) |value| {
                if (value) |nis| {
                    sum += nis;
                    inside += @intFromBool(nis <= p.bound);
                    count += 1;
                }
            }
            out.add("track {d} birth {d} confirmed {d} end {d} deleted {s} hits {d} misses {d} longest_gap {d} path {s} nis {s} nis_inside {d}/{d}",
                 .{ track.number, track.birth, track.confirmed.?, track.last_hit, optional(track.deleted),
                 track.hits, track.last_hit - track.birth + 1 - track.hits, track.analysis.longest_gap,
                 real(track.analysis.path), real(sum / f(count)), inside, count });
        }
        out.add("", .{});
        out.add("matching", .{});
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            const analysis = track.analysis;
            var row: m.Text = .{};
            row.add("track {d} target {s}", .{ track.number, if (analysis.target) |target| m.fmt("{d}",
                 .{input.targets.items[target].number}) else "-" });
            if (analysis.target != null) row.add(" common {d} mean_distance {s}", .{ analysis.common,
                 real(analysis.mean_distance) });
            var count: usize = 0;
            var segments: m.Lines = .{};
            var scan = track.birth;
            while (scan <= track.last_hit) : (scan += 1) {
                const target = analysis.primary_matches[scan] orelse continue;
                const first = scan;
                while (scan < track.last_hit and analysis.primary_matches[scan + 1] == target) scan += 1;
                count += scan - first + 1;
                segments.add("{d}-{d}:{d}", .{ first, scan, input.targets.items[target].number });
            }
            out.add("{s} matched_scans {d} {s}", .{ row.value(), count, listed("segments", segments) });
        }
        out.add("", .{});
        out.add("rmse", .{});
        for (input.targets.items, 0..) |target, b| {
            const result = self.results[b];
            const index = result.track orelse {
                out.add("target {d} track -", .{target.number});
                continue;
            };
            out.add("target {d} track {d} common {d} {s}", .{ target.number, self.tracks[index].number,
                 result.common, scores(result.position) });
            out.add("target {d} velocity {d} {s}", .{ target.number, result.velocity_count, scores(result.velocity) });
        }
        out.add("overall position {s}", .{scores(self.overall_position)});
        out.add("overall velocity {s}", .{scores(self.overall_velocity)});
        out.add("", .{});
        out.add("consistency", .{});
        for (input.targets.items, 0..) |target, b| {
            const result = self.results[b];
            if (result.track) |index| out.add("target {d} track {d} nees {s} inside {d}/{d}",
                 .{ target.number, self.tracks[index].number, real(result.nees), result.inside,
                 result.common }) else out.add("target {d} track -", .{target.number});
        }
        const observed = m.alloc(usize, p.edges.len + 1);
        @memset(observed, 0);
        var nis_count: usize = 0;
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            for (track.nis[track.birth .. track.last_hit + 1]) |value| {
                if (value) |nis| {
                    nis_count += 1;
                    var bin: usize = 0;
                    while (bin < p.edges.len and p.edges[bin] <= nis) bin += 1;
                    observed[bin] += 1;
                }
            }
        }
        var histogram: m.Text = .{};
        histogram.add("nis_histogram total {d} observed", .{nis_count});
        for (observed) |value| histogram.add(" {d}", .{value});
        histogram.add(" expected", .{});
        var lower: f64 = 0;
        for (0..observed.len) |bin| {
            const upper_probability = if (bin == p.edges.len) @as(f64, 0) else @exp(-p.edges[bin] / 2);
            histogram.add(" {s}", .{real(f(nis_count) * (@exp(-lower / 2) - upper_probability))});
            if (bin < p.edges.len) lower = p.edges[bin];
        }
        out.add("{s}", .{histogram.value()});
        out.add("", .{});
        out.add("models", .{});
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            out.add("track {d} updates {d} cv {s} ca {s} better {s}", .{ track.number, track.hits - 1,
                 real(track.analysis.logs[0]), real(track.analysis.logs[1]), if (track.analysis.logs[0] >= track.analysis.logs[1]) "cv" else "ca" });
        }
        out.add("", .{});
        out.add("ospa cutoff {s} order 2", .{real(p.cutoff)});
        out.add("scan targets tracks cv ca abg imm rts", .{});
        for (1..input.scans + 1) |scan| {
            var row: m.Text = .{};
            row.add("{d} {d} {d}", .{ scan, self.sizes[scan - 1][0], self.sizes[scan - 1][1] });
            for (0..5) |kind| row.add(" {s}", .{real(self.ospa_values[kind][scan - 1])});
            out.add("{s}", .{row.value()});
        }
        var means: m.Text = .{};
        means.add("mean", .{});
        for (0..5) |kind| {
            var sum: f64 = 0;
            for (self.ospa_values[kind][0..input.scans]) |value| sum += value;
            means.add(" {s}", .{real(sum / f(input.scans))});
        }
        out.add("{s}", .{means.value()});
        out.add("", .{});
        out.add("continuity", .{});
        for (0..5) |kind| {
            var covered: usize = 0;
            var breaks: usize = 0;
            var swaps: usize = 0;
            for (self.continuities[kind][0..input.targets.items.len]) |value| {
                covered += value.covered;
                breaks += value.breaks;
                swaps += value.swaps;
            }
            out.add("{s} covered {d} breaks {d} swaps {d}", .{ filters[kind], covered, breaks, swaps });
            for (input.targets.items, 0..) |target, b| {
                const value = self.continuities[kind][b];
                out.add("  target {d} scans {d} covered {d} breaks {d} swaps {d} delay {s}",
                     .{ target.number, target.last - target.first + 1, value.covered, value.breaks,
                     value.swaps, optional(value.delay) });
            }
        }
        out.add("", .{});
        out.add("imm", .{});
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            const analysis = track.analysis;
            var sum: f64 = 0;
            var maximum = track.birth;
            var count: usize = 0;
            for (track.birth..track.last_hit + 1) |scan| {
                sum += analysis.high[scan];
                if (analysis.high[scan] > analysis.high[maximum]) maximum = scan;
                count += @intFromBool(analysis.high[scan] > 0.5);
            }
            var segments: m.Lines = .{};
            var scan = track.birth;
            while (scan <= track.last_hit) : (scan += 1) {
                if (analysis.high[scan] <= 0.5) continue;
                const first = scan;
                while (scan < track.last_hit and analysis.high[scan + 1] > 0.5) scan += 1;
                segments.add("{d}-{d}", .{ first, scan });
            }
            out.add("track {d} mean_high {s} max_high {s} at {d} high_scans {d} {s}", .{ track.number,
                 real(sum / f(track.last_hit - track.birth + 1)), real(analysis.high[maximum]),
                 maximum, count, listed("segments", segments) });
        }
        return out;
    }
    fn cell(self: *const Analysis, point: m.Position) ?association.Pair {
        const p = self.input.params;
        const dx = (p.xmax - p.xmin) / f(p.width);
        const dy = (p.ymax - p.ymin) / f(p.height);
        const column: i64 = @intFromFloat(@floor((point[0] - p.xmin) / dx));
        const row: i64 = @intFromFloat(@floor((p.ymax - point[1]) / dy));
        if (column < 0 or column >= m.n(p.width) or row < 0 or row >= m.n(p.height)) return null;
        return .{ .row = m.u(row), .column = m.u(column) };
    }
    fn plots(self: *const Analysis) m.Lines {
        const input = self.input;
        const p = input.params;
        var out: m.Lines = .{};
        out.add("tracks x {s} {s} y {s} {s} size {d} {d}", .{ real(p.xmin), real(p.xmax), real(p.ymin),
             real(p.ymax), p.width, p.height });
        const grid = blankGrid(p.width, p.height);
        for (input.targets.items) |target| {
            for (target.first..target.last + 1) |scan| {
                if (self.cell(target.positions[scan].?)) |location| grid[location.row][location.column] = '.';
            }
        }
        for (self.evaluated.items, 0..) |index, i| {
            const track = self.tracks[index];
            for (track.birth..track.last_hit + 1) |scan| {
                if (self.cell(position(track.analysis.estimates[4][scan]))) |location| grid[location.row][location.column] = character(i);
            }
        }
        frame(&out, grid);
        for (self.evaluated.items, 0..) |index, i| {
            const track = self.tracks[index];
            out.add("{c} track {d} target {s}", .{ character(i), track.number, if (track.analysis.target) |target| m.fmt("{d}",
                 .{input.targets.items[target].number}) else "-" });
        }
        out.add("", .{});
        out.add("measurements", .{});
        const counts = m.alloc(usize, p.height * p.width);
        @memset(counts, 0);
        for (input.measurements[1 .. input.scans + 1]) |list| for (list.items) |point| {
            if (self.cell(point)) |location| counts[location.row * p.width + location.column] += 1;
        };
        for (0..p.height) |row| for (0..p.width) |column| {
            const count = counts[row * p.width + column];
            grid[row][column] = if (count == 0) ' ' else if (count >= 10) '#' else @as(u8, @intCast('0' + count));
        };
        frame(&out, grid);
        out.add("", .{});
        out.add("timeline", .{});
        var characters: [1001]u8 = [_]u8{0} ** 1001;
        for (self.evaluated.items, 0..) |index, i| characters[self.tracks[index].number] = character(i);
        for (input.targets.items, 0..) |target, b| {
            const timeline = m.alloc(u8, input.scans);
            @memset(timeline, ' ');
            for (target.first..target.last + 1) |scan| {
                const label = self.labels[self.primary][b][scan];
                timeline[scan - 1] = if (label < 0) '.' else characters[m.u(label)];
            }
            out.add("{d} |{s}|", .{ target.number, timeline });
        }
        out.add("", .{});
        out.add("ospa {s}", .{filters[self.primary]});
        const ospa_grid = blankGrid(input.scans, 10);
        for (0..input.scans) |scan| {
            const height: usize = @intFromFloat(@floor(10 * self.ospa_values[self.primary][scan] / p.cutoff));
            for (0..10) |row| {
                if (height >= 10 - row) ospa_grid[row][scan] = '#';
            }
        }
        frame(&out, ospa_grid);
        return out;
    }
    fn run(self: *Analysis, io: std.Io) !void {
        self.tracking();
        self.comparedFilters();
        self.scanEvaluation();
        self.matchTracks();
        self.evaluateErrors();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try save(io, "tracks.csv", self.track_rows);
        try save(io, "association_log.txt", self.log);
        var smoothed: m.Lines = .{};
        smoothed.add("track,scan,x,y,vx,vy", .{});
        for (self.evaluated.items) |index| {
            const track = self.tracks[index];
            for (track.birth..track.last_hit + 1) |scan| {
                const x = track.analysis.estimates[4][scan];
                smoothed.add("{d},{d},{s},{s},{s},{s}", .{ track.number, scan, real(x.values[0]),
                     real(x.values[1]), real(x.values[2]), real(x.values[3]) });
            }
        }
        try save(io, "smoothed.csv", smoothed);
        try save(io, "evaluation.txt", self.evaluationReport());
        try save(io, "track_plot.txt", self.plots());
    }
};
fn character(index: usize) u8 {
    return @intCast(if (index < 26) 'A' + index else 'a' + index - 26);
}
fn blankGrid(width: usize, height: usize) [][]u8 {
    const out = m.alloc([]u8, height);
    for (out) |*row| {
        row.* = m.alloc(u8, width);
        @memset(row.*, ' ');
    }
    return out;
}
fn save(io: std.Io, name: []const u8, lines: m.Lines) !void {
    var text: m.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = m.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    m.allocator = arena.allocator();
    const input = try readInputs(init.io);
    const analysis = m.create(Analysis, .{ .input = input, .primary = if (input.params.ca) 1 else 0,
         .tracks = m.alloc(Track, 1000) });
    try analysis.run(init.io);
}
