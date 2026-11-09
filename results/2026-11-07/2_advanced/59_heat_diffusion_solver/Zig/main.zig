const std = @import("std");
const c = @import("mesh.zig");
const material = @import("materials.zig");
const transient = @import("transient.zig");
const steady_solver = @import("steady.zig");
const r = @import("report.zig");
const Probe = struct { name: []const u8, point: usize };
const Run = struct { name: []const u8, method: []const u8, step: i64 };
const Params = struct {
    initial: f64 = 0,
    tolerance: f64 = 0,
    omega: f64 = 0,
    alarm: f64 = 0,
    limit: f64 = 0,
    end: i64 = 0,
    probe_every: i64 = 0,
    max_iterations: usize = 0,
    snapshots: []const i64 = &.{},
    probes: std.ArrayList(Probe) = .empty,
    runs: std.ArrayList(Run) = .empty,
    reference: []const u8 = "",
    bands: []const f64 = &.{},
};
const Boundary = struct { segments: []const c.Segment, sources: []const c.Source };
fn boundary(io: std.Io, mesh: c.Mesh) !Boundary {
    var segments: std.ArrayList(c.Segment) = .empty;
    var sources: std.ArrayList(c.Source) = .empty;
    for (try c.readLines(io, "input/boundary.txt")) |line| {
        const row = c.words(line);
        if (c.eq(row[0], "segment")) {
            c.append(c.Segment, &segments, .{ .name = row[1], .edge = row[2], .kind = row[5],
                 .faces = mesh.segmentFaces(row[2], c.u(c.number(row[3])), c.u(c.number(row[4]))),
                 .coefficient = if (c.eq(row[5], "convective")) c.real(row[6]) else 0, .theta = if (c.eq(row[5],
                 "insulated")) 0 else c.real(row[row.len - 1]) });
        } else {
            var intervals: std.ArrayList(c.Interval) = .empty;
            var i: usize = 7;
            while (i < row.len) : (i += 2) c.append(c.Interval, &intervals, .{ .on = c.number(row[i]),
                 .off = c.number(row[i + 1]) });
            c.append(c.Source, &sources, .{ .name = row[1], .cells = mesh.sourceCells(c.u(c.number(row[2])),
                 c.u(c.number(row[3])), c.u(c.number(row[4])), c.u(c.number(row[5]))), .power = c.real(row[6]),
                 .intervals = intervals.items });
        }
    }
    return .{ .segments = segments.items, .sources = sources.items };
}
fn parameters(io: std.Io, mesh: c.Mesh) !Params {
    var out: Params = .{};
    for (try c.readLines(io, "input/params.txt")) |line| {
        const row = c.words(line);
        const key = row[0];
        if (c.eq(key, "initial")) out.initial = c.real(row[1]) else if (c.eq(key, "end_time")) out.end = c.number(row[1]) else if (c.eq(key,
             "probe_every")) out.probe_every = c.number(row[1]) else if (c.eq(key, "tolerance")) out.tolerance = c.real(row[1]) else if (c.eq(key,
             "max_iterations")) out.max_iterations = c.u(c.number(row[1])) else if (c.eq(key,
             "omega")) out.omega = c.real(row[1]) else if (c.eq(key, "alarm")) out.alarm = c.real(row[1]) else if (c.eq(key,
             "limit")) out.limit = c.real(row[1]) else if (c.eq(key, "reference")) out.reference = row[1] else if (c.eq(key,
             "snapshots")) {
            const values = c.alloc(i64, row.len - 1);
            for (row[1..], values) |field, *value| value.* = c.number(field);
            out.snapshots = values;
        } else if (c.eq(key, "bands")) {
            const values = c.alloc(f64, row.len - 1);
            for (row[1..], values) |field, *value| value.* = c.real(field);
            out.bands = values;
        } else if (c.eq(key, "probe")) c.append(Probe, &out.probes, .{ .name = row[1], .point = mesh.cell(c.u(c.number(row[2])),
             c.u(c.number(row[3]))) }) else if (c.eq(key, "run")) c.append(Run, &out.runs,
             .{ .name = row[1], .method = row[2], .step = c.number(row[3]) });
    }
    return out;
}
fn operating(source: c.Source, time: i64) bool {
    for (source.intervals) |interval| if (interval.on <= time and time < interval.off) return true;
    return false;
}
fn duty(source: c.Source, end: i64) f64 {
    var duration: i64 = 0;
    for (source.intervals) |interval| duration += @min(interval.off, end) - @min(interval.on, end);
    return c.f(duration) / c.f(end);
}
fn sourceTerms(system: *const c.System, time: ?i64, field: []f64) f64 {
    @memset(field, 0);
    var power: f64 = 0;
    for (system.sources) |source| {
        if (time) |value| if (!operating(source, value)) continue;
        power += source.power;
        const weight = source.power / c.f(source.cells.len);
        for (source.cells) |point| field[point] += weight;
    }
    return power;
}
fn loadSystem(io: std.Io) !c.System {
    const mesh = try c.load(io);
    const materials = try material.load(io);
    const borders = try boundary(io, mesh);
    var out: c.System = .{ .mesh = mesh, .materials = materials, .segments = borders.segments,
         .sources = borders.sources, .faces = c.alloc([4]c.Face, mesh.count), .cell_material = c.alloc(usize,
         mesh.count), .material_cells = c.alloc(std.ArrayList(usize), materials.len), .capacity = c.alloc(f64,
         mesh.count), .diagonal = c.alloc(f64, mesh.count), .beta = c.alloc(f64, mesh.count),
         .source_all = c.alloc(f64, mesh.count), .dt_max = std.math.inf(f64) };
    @memset(out.material_cells, .empty);
    @memset(out.diagonal, 0);
    @memset(out.beta, 0);
    for (mesh.codes, 0..) |code, point| {
        var index: usize = 0;
        while (materials[index].code != code) : (index += 1) {}
        out.cell_material[point] = index;
        c.append(usize, &out.material_cells[index], point);
        out.capacity[point] = material.capacity(materials[index], mesh.dx, mesh.thickness);
    }
    for (out.faces, 0..) |*faces, point| for (0..4) |direction| {
        const neighbor = mesh.neighbors[point][direction];
        faces[direction] = .{ .neighbor = neighbor, .g = if (neighbor) |q| material.interior(materials[out.cell_material[point]].k,
             materials[out.cell_material[q]].k, mesh.thickness) else 0 };
    };
    for (out.segments) |segment| for (segment.faces) |item| {
        const face = &out.faces[item.point][item.direction];
        const conductivity = materials[out.cell_material[item.point]].k;
        if (c.eq(segment.kind, "fixed")) {
            face.g = material.fixed(conductivity, mesh.thickness);
            face.theta = segment.theta;
        } else if (c.eq(segment.kind, "convective")) {
            face.g = material.convective(conductivity, segment.coefficient, mesh.dx, mesh.thickness);
            face.theta = segment.theta;
        }
    };
    for (out.faces, 0..) |faces, point| {
        for (faces) |face| {
            out.diagonal[point] += face.g;
            if (face.theta) |theta| out.beta[point] += face.g * theta;
        }
        out.dt_max = @min(out.dt_max, out.capacity[point] / out.diagonal[point]);
    }
    out.total_power = sourceTerms(&out, null, out.source_all);
    return out;
}
fn status(system: *const c.System, params: Params, run: Run) []const u8 {
    if (@mod(params.end, run.step) != 0 or @mod(params.probe_every, run.step) != 0) return "step";
    for (params.snapshots) |time| if (@mod(time, run.step) != 0) return "step";
    for (system.sources) |source| for (source.intervals) |interval| if (@mod(interval.on, run.step) != 0 or @mod(interval.off,
         run.step) != 0) return "step";
    return if (c.eq(run.method, "ftcs") and c.f(run.step) / 1000 > system.dt_max) "unstable" else "accepted";
}
fn stored(system: *const c.System, field: []const f64, initial: f64, cells: ?[]const usize) f64 {
    var out: f64 = 0;
    if (cells) |points| {
        for (points) |point| out += system.capacity[point] * (field[point] - initial);
    } else {
        for (field, 0..) |value, point| out += system.capacity[point] * (value - initial);
    }
    return out;
}
fn segmentFlow(system: *const c.System, segment: c.Segment, field: []const f64) f64 {
    var out: f64 = 0;
    if (c.eq(segment.kind, "insulated")) return out;
    for (segment.faces) |item| {
        const face = system.faces[item.point][item.direction];
        out += face.g * (face.theta.? - field[item.point]);
    }
    return out;
}
fn maximumDifference(first: []const f64, second: []const f64) f64 {
    var out: f64 = 0;
    for (first, second) |a, b| out = @max(out, @abs(a - b));
    return out;
}
fn balanceVerdict(u: f64, b: f64, q: f64) []const u8 {
    return if (@abs(u - b - q) <= 0.000001 * (@abs(u) + @abs(b) + @abs(q))) "ok" else "failed";
}
const Snapshot = struct { time: i64, field: []const f64, u: f64, b: f64, q: f64 };
const ProbeRow = struct { time: i64, values: []const f64 };
const Result = struct {
    run: Run,
    status: []const u8,
    field: []f64 = &.{},
    boundaries: []f64 = &.{},
    source_energy: f64 = 0,
    stored_heat: f64 = 0,
    boundary_energy: f64 = 0,
    peak: f64 = 0,
    peak_time: i64 = 0,
    peak_cell: usize = 0,
    above: i64 = 0,
    alarm: ?struct { time: i64, cell: usize } = null,
    snapshots: std.ArrayList(Snapshot) = .empty,
    probes: std.ArrayList(ProbeRow) = .empty,
};
fn observe(system: *const c.System, params: Params, out: *Result, time: i64) void {
    const hot = r.hottest(out.field);
    const maximum = out.field[hot];
    if (maximum > out.peak) {
        out.peak = maximum;
        out.peak_time = time;
        out.peak_cell = hot;
    }
    if (maximum >= params.alarm) {
        if (out.alarm == null) out.alarm = .{ .time = time, .cell = hot };
        if (time > 0) out.above += out.run.step;
    }
    if (@mod(time, params.probe_every) == 0) {
        const values = c.alloc(f64, params.probes.items.len);
        for (params.probes.items, values) |probe, *value| value.* = out.field[probe.point];
        c.append(ProbeRow, &out.probes, .{ .time = time, .values = values });
    }
    for (params.snapshots) |stamp| if (stamp == time) {
        var b: f64 = 0;
        for (out.boundaries) |value| b += value;
        c.append(Snapshot, &out.snapshots, .{ .time = time, .field = c.dupe(f64, out.field),
             .u = stored(system, out.field, params.initial, null), .b = b, .q = out.source_energy });
    };
}
fn transientRun(system: *const c.System, params: Params, definition: Run) Result {
    var out: Result = .{ .run = definition, .status = status(system, params, definition) };
    if (!c.eq(out.status, "accepted")) return out;
    const n = system.mesh.count;
    out.field = c.alloc(f64, n);
    @memset(out.field, params.initial);
    out.boundaries = c.alloc(f64, system.segments.len);
    @memset(out.boundaries, 0);
    out.peak = params.initial;
    var updated: [1000]f64 = undefined;
    var intermediate: [1000]f64 = undefined;
    var source: [1000]f64 = undefined;
    var average: [1000]f64 = undefined;
    const dt = c.f(definition.step) / 1000;
    observe(system, params, &out, 0);
    var time: i64 = 0;
    while (time < params.end) : (time += definition.step) {
        const power = sourceTerms(system, time, source[0..n]);
        transient.advance(system, out.field, source[0..n], dt, definition.method, updated[0..n], intermediate[0..n]);
        const crank = c.eq(definition.method, "crank_nicolson");
        if (crank) for (0..n) |point| {
            average[point] = (out.field[point] + updated[point]) / 2;
        };
        for (system.segments, 0..) |segment, j| {
            const horizontal = c.eq(segment.edge, "left") or c.eq(segment.edge, "right");
            const field = if (c.eq(definition.method, "ftcs")) out.field else if (horizontal) intermediate[0..n] else if (crank) average[0..n] else updated[0..n];
            out.boundaries[j] += dt * segmentFlow(system, segment, field);
        }
        out.source_energy += dt * power;
        @memcpy(out.field, updated[0..n]);
        observe(system, params, &out, time + definition.step);
    }
    out.stored_heat = stored(system, out.field, params.initial, null);
    for (out.boundaries) |value| out.boundary_energy += value;
    return out;
}
fn rate(solver: steady_solver.Iteration) f64 {
    return @sqrt(solver.changes[solver.changes.len - 1] / solver.changes[solver.changes.len - 3]);
}
fn milestones(solver: steady_solver.Iteration, tolerance: f64) []const u8 {
    var out: c.Text = .{};
    for ([_]f64{ 1000, 100, 10, 1 }) |factor| {
        var found: ?usize = null;
        for (solver.changes, 0..) |value, i| if (value < tolerance * factor) {
            found = i + 1;
            break;
        };
        out.add(" {s}", .{if (found) |value| c.fmt("{d}", .{value}) else "never"});
    }
    return out.value();
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    const io = init.io;
    const system = try loadSystem(io);
    const mesh = system.mesh;
    const params = try parameters(io, mesh);
    const n = mesh.count;
    const rhs = c.alloc([]const f64, system.sources.len + 2);
    const full = c.alloc(f64, n);
    for (full, 0..) |*value, point| value.* = system.beta[point] + system.source_all[point];
    rhs[0] = full;
    rhs[1] = system.beta;
    for (system.sources, 0..) |source, j| {
        const unit = c.alloc(f64, n);
        @memset(unit, 0);
        for (source.cells) |point| unit[point] = 1 / c.f(source.cells.len);
        rhs[j + 2] = unit;
    }
    const solutions = steady_solver.direct(&system, rhs);
    const steady = solutions[0];
    const base = solutions[1];
    var solvers: [4]steady_solver.Iteration = undefined;
    solvers[0] = steady_solver.iterate(&system, params.initial, params.tolerance, params.max_iterations, "jacobi", 1);
    const rho = rate(solvers[0]);
    const omega_opt = 2 / (1 + @sqrt(1 - rho * rho));
    solvers[1] = steady_solver.iterate(&system, params.initial, params.tolerance, params.max_iterations,
         "gauss_seidel", 1);
    solvers[2] = steady_solver.iterate(&system, params.initial, params.tolerance, params.max_iterations,
         "sor", params.omega);
    solvers[3] = steady_solver.iterate(&system, params.initial, params.tolerance, params.max_iterations,
         "sor_estimated", omega_opt);
    const results = c.alloc(Result, params.runs.items.len);
    var reference: usize = 0;
    for (params.runs.items, 0..) |run, i| {
        if (c.eq(run.name, params.reference)) reference = i;
        results[i] = transientRun(&system, params, run);
    }
    var snapshots: c.Lines = .{};
    var probes: c.Lines = .{};
    var comparison: c.Lines = .{};
    probes.add("run,time,probe,temperature", .{});
    comparison.add("ftcs_max_dt {s}", .{r.real(system.dt_max, 4)});
    for (results, 0..) |result, index| {
        const run = result.run;
        const prefix = c.fmt("run {s} {s} dt {s}", .{ run.name, run.method, r.time(run.step) });
        if (!c.eq(result.status, "accepted")) {
            snapshots.add("{s} rejected {s}{s}", .{ prefix, result.status, if (c.eq(result.status,
                 "unstable")) c.fmt(" max_dt {s}", .{r.real(system.dt_max, 4)}) else "" });
            comparison.add("{s} rejected {s}", .{ prefix, result.status });
            continue;
        }
        for (result.snapshots.items) |snapshot| {
            snapshots.add("{s}", .{r.summary(c.fmt("{s} time {s}", .{ prefix, r.time(snapshot.time) }),
                 mesh, snapshot.field)});
            r.fieldLines(&snapshots, mesh, snapshot.field);
        }
        for (result.probes.items) |row| for (params.probes.items, row.values) |probe, value| probes.add("{s},{s},{s},{s}",
             .{ run.name, r.time(row.time), probe.name, r.real(value, 3) });
        const alarm = if (result.alarm) |value| c.fmt("{s} at {s}", .{ r.time(value.time),
             mesh.coordinates(value.cell) }) else "never";
        comparison.add("{s} steps {d} peak {s} time {s} at {s} alarm {s} above {s}", .{ prefix,
             @divTrunc(params.end, run.step), r.real(result.peak, 2), r.time(result.peak_time),
             mesh.coordinates(result.peak_cell), alarm, r.time(result.above) });
        comparison.add("energy {s} stored {s} boundary {s} source {s} balance {s}", .{ run.name,
             r.real(result.stored_heat, 2), r.real(result.boundary_energy, 2), r.real(result.source_energy,
             2), balanceVerdict(result.stored_heat, result.boundary_energy, result.source_energy) });
        for (result.snapshots.items) |snapshot| comparison.add("energy_at {s} time {s} stored {s} boundary {s} source {s}",
             .{ run.name, r.time(snapshot.time), r.real(snapshot.u, 2), r.real(snapshot.b,
             2), r.real(snapshot.q, 2) });
        for (system.materials, system.material_cells) |value, cells| comparison.add("energy_material {s} {c} {s}",
             .{ run.name, value.code, r.real(stored(&system, result.field, params.initial,
             cells.items), 2) });
        for (system.segments, result.boundaries) |segment, value| comparison.add("energy_segment {s} {s} {s}",
             .{ run.name, segment.name, r.real(value, 2) });
        for (params.probes.items, 0..) |probe, j| {
            var maximum = result.probes.items[0].values[j];
            var minimum = maximum;
            var max_time: i64 = 0;
            var min_time: i64 = 0;
            for (result.probes.items) |row| {
                if (row.values[j] > maximum) {
                    maximum = row.values[j];
                    max_time = row.time;
                }
                if (row.values[j] < minimum) {
                    minimum = row.values[j];
                    min_time = row.time;
                }
            }
            comparison.add("probe_summary {s} {s} max {s} time {s} min {s} time {s}", .{ run.name,
                 probe.name, r.real(maximum, 3), r.time(max_time), r.real(minimum, 3), r.time(min_time) });
        }
        if (index != reference) for (result.snapshots.items, results[reference].snapshots.items) |snapshot, other| {
            var squared: f64 = 0;
            for (snapshot.field, other.field) |a, b| {
                const difference = @abs(a - b);
                squared += difference * difference;
            }
            comparison.add("compare {s} {s} time {s} max_diff {s} rms_diff {s}", .{ run.name,
                 params.reference, r.time(snapshot.time), r.real(maximumDifference(snapshot.field,
                 other.field), 6), r.real(@sqrt(squared / c.f(n)), 6) });
        };
        comparison.add("final {s} steady_max_diff {s}", .{ run.name, r.real(maximumDifference(result.field,
             steady), 6) });
    }
    comparison.add("steady direct max_residual {s}", .{r.real(steady_solver.residual(&system, steady, full), 6)});
    for (solvers) |solver| comparison.add("steady {s} iterations {d} max_diff {s} max_residual {s}",
         .{ solver.method, solver.changes.len, r.real(maximumDifference(solver.field, steady),
         6), r.real(steady_solver.residual(&system, solver.field, full), 6) });
    comparison.add("jacobi_spectral_radius {s} squared {s}", .{ r.real(rho, 6), r.real(rho * rho, 6) });
    comparison.add("omega_estimated {s}", .{r.real(omega_opt, 4)});
    var report: c.Lines = .{};
    report.add("{s}", .{r.summary("steady", mesh, steady)});
    r.fieldLines(&report, mesh, steady);
    for (system.materials, system.material_cells) |value, cells| {
        var minimum = steady[cells.items[0]];
        var maximum = minimum;
        var total: f64 = 0;
        for (cells.items) |point| {
            minimum = @min(minimum, steady[point]);
            maximum = @max(maximum, steady[point]);
            total += steady[point];
        }
        report.add("material {c} {s} cells {d} min {s} max {s} mean {s}", .{ value.code, value.name,
             cells.items.len, r.real(minimum, 2), r.real(maximum, 2), r.real(total / c.f(cells.items.len),
             2) });
    }
    for (system.sources) |source| {
        var total: f64 = 0;
        var maximum = steady[source.cells[0]];
        for (source.cells) |point| {
            total += steady[point];
            maximum = @max(maximum, steady[point]);
        }
        report.add("source {s} power {s} duty {s} mean {s} max {s}", .{ source.name, r.real(source.power,
             4), r.real(duty(source, params.end), 4), r.real(total / c.f(source.cells.len),
             2), r.real(maximum, 2) });
    }
    for (system.sources) |source| for (system.sources, 0..) |other, j| {
        var total: f64 = 0;
        for (source.cells) |point| total += solutions[j + 2][point];
        report.add("influence {s} {s} {s}", .{ source.name, other.name, r.real(total / c.f(source.cells.len), 4) });
    };
    const superposition = c.dupe(f64, base);
    const duty_field = c.dupe(f64, base);
    for (0..n) |point| for (system.sources, 0..) |source, j| {
        superposition[point] += source.power * solutions[j + 2][point];
        duty_field[point] += (duty(source, params.end) * source.power) * solutions[j + 2][point];
    };
    report.add("superposition {s}", .{if (maximumDifference(superposition, steady) <= 0.000001) "ok" else "failed"});
    for (system.sources, 0..) |source, j| for (system.segments) |segment| {
        var value: f64 = 0;
        if (!c.eq(segment.kind, "insulated")) for (segment.faces) |item| {
            value += system.faces[item.point][item.direction].g * solutions[j + 2][item.point];
        };
        report.add("path {s} {s} {s}", .{ source.name, segment.name, r.real(value, 4) });
    };
    report.add("{s}", .{r.summary("duty_steady", mesh, duty_field)});
    for (system.sources, 0..) |source, j| {
        var minimum = std.math.inf(f64);
        var cell: usize = 0;
        for (0..n) |point| {
            const value = (params.limit - (steady[point] - source.power * solutions[j + 2][point])) / solutions[j + 2][point];
            if (value < minimum) {
                minimum = value;
                cell = point;
            }
        }
        report.add("headroom {s} max_power {s} at {s}", .{ source.name, r.real(minimum, 4), mesh.coordinates(cell) });
    }
    const Interface = struct { faces: usize = 0, forward: f64 = 0, backward: f64 = 0 };
    const interfaces = c.alloc(Interface, system.materials.len * system.materials.len);
    @memset(interfaces, .{});
    var gradient: f64 = -1;
    var gradient_first: usize = 0;
    var gradient_second: usize = 0;
    for (system.faces, 0..) |faces, point| for ([_]usize{ 1, 3 }) |direction| {
        const face = faces[direction];
        const neighbor = face.neighbor orelse continue;
        const value = @abs(steady[point] - steady[neighbor]) / mesh.dx;
        if (value > gradient) {
            gradient = value;
            gradient_first = point;
            gradient_second = neighbor;
        }
        const a = system.cell_material[point];
        const b = system.cell_material[neighbor];
        if (a == b) continue;
        const flow = face.g * (steady[point] - steady[neighbor]);
        const oriented = if (a < b) flow else -flow;
        const entry = &interfaces[@min(a, b) * system.materials.len + @max(a, b)];
        entry.faces += 1;
        if (oriented > 0) entry.forward += oriented else if (oriented < 0) entry.backward += -oriented;
    };
    for (system.materials, 0..) |a, i| for (system.materials[i + 1 ..], i + 1..) |b, j| {
        const entry = interfaces[i * system.materials.len + j];
        if (entry.faces > 0) report.add("interface {c} {c} faces {d} forward {s} backward {s}",
             .{ a.code, b.code, entry.faces, r.real(entry.forward, 4), r.real(entry.backward,
             4) });
    };
    var total_flow: f64 = 0;
    var absolute_flow: f64 = 0;
    for (system.segments) |segment| {
        const flow = segmentFlow(&system, segment, steady);
        total_flow += flow;
        absolute_flow += @abs(flow);
        report.add("segment {s} {s} {s} flow {s}", .{ segment.name, segment.edge, segment.kind, r.real(flow, 4) });
    }
    report.add("sources {s}", .{r.real(system.total_power, 4)});
    report.add("balance {s}", .{if (@abs(total_flow + system.total_power) <= 0.000001 * (absolute_flow + system.total_power)) "ok" else "failed"});
    report.add("max_gradient {s} between {s} and {s}", .{ r.real(gradient, 2), mesh.coordinates(gradient_first),
         mesh.coordinates(gradient_second) });
    for (solvers, 0..) |solver, i| report.add("solver {s}{s} iterations {d} converged {s} rate {s} milestones{s}",
         .{ solver.method, if (i >= 2) c.fmt(" omega {s}", .{r.real(solver.omega, 4)}) else "",
         solver.changes.len, if (solver.converged) "yes" else "no", r.real(rate(solver), 6),
         milestones(solver, params.tolerance) });
    var maps: c.Lines = .{};
    r.isotherms(&maps, "isotherms steady", mesh, steady, params.bands);
    for (results[reference].snapshots.items) |snapshot| r.isotherms(&maps, c.fmt("isotherms {s} time {s}",
         .{ params.reference, r.time(snapshot.time) }), mesh, snapshot.field, params.bands);
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try r.save(io, "snapshots.txt", snapshots);
    try r.save(io, "probes.csv", probes);
    try r.save(io, "steady_state.txt", report);
    try r.save(io, "solver_comparison.txt", comparison);
    try r.save(io, "isotherms.txt", maps);
}
