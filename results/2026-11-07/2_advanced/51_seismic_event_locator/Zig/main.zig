const std = @import("std");
const c = @import("waveform_io.zig");
const picker = @import("picker.zig");
const associator = @import("associator.zig");
const locator = @import("locator.zig");
const magnitude = @import("magnitude.zig");
const Jack = struct { station: usize, dx: f64, dy: f64, dz: f64, shift: f64 };
const Event = struct { used: []const usize, first: locator.Run, final: locator.Run = undefined, observations: [12]locator.Observation = undefined,
     ellipse: locator.Ellipse = undefined, start_rms: f64 = 0, gap: f64 = 0, dmin: f64 = 0, dh: f64 = 0,
     dz: f64 = 0, quality: u8 = 'C', jack: [12]Jack = undefined, max_jack: usize = 0, cluster: usize = 0,
     magnitudes: [12]magnitude.PickMagnitude = undefined, ml: ?f64 = null, mlc: ?f64 = null, md: f64 = 0 };
fn decimal(value: f64, digits: usize) []const u8 {
    const amount = magnitude.scaled(value, digits);
    const absolute = if (amount < 0) -amount else amount;
    var factor: i64 = 1;
    for (0..digits) |_| factor *= 10;
    if (digits == 0) return c.fmt("{d}", .{amount});
    const tail = c.fmt("{d}", .{@mod(absolute, factor)});
    const zeroes = c.alloc(u8, digits - tail.len);
    @memset(zeroes, '0');
    return c.fmt("{s}{d}.{s}{s}", .{ if (amount < 0) "-" else "", @divTrunc(absolute, factor), zeroes, tail });
}
fn timeText(value: i64) []const u8 {
    return c.fmt("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
}
fn optionalDecimal(value: ?f64) []const u8 {
    return if (value) |number| decimal(number, 2) else "-";
}
fn observations(ids: []const usize, picks: []const c.Pick, stations: []const c.Station, corrected: bool) [12]locator.Observation {
    var out: [12]locator.Observation = undefined;
    for (ids, 0..) |id, i| {
        const pick = picks[id];
        out[i] = .{ .station = pick.station, .time = pick.time() - (if (corrected) stations[pick.station].correction else 0) };
    }
    return out;
}
fn solutionLine(out: *c.Lines, label: []const u8, q: locator.Solution, error_value: f64) void {
    out.add("{s} x={s} y={s} z={s} t0={s} rms={s}", .{ label, decimal(q[0], 1), decimal(q[1], 1),
         decimal(q[2], 1), decimal(q[3], 3), decimal(error_value, 4) });
}
fn traceLines(out: *c.Lines, run: locator.Run) void {
    for (run.trace, 1..) |step, i| solutionLine(out, c.fmt("ITER {d}", .{i}), step.solution, step.rms);
}
fn passLines(out: *c.Lines, pass: usize, ids: []const usize, run: locator.Run, picks: []const c.Pick,
     stations: []const c.Station, p: c.Params) void {
    var codes: c.Text = .{};
    for (ids, 0..) |id, i| codes.add("{s}{s}", .{ if (i == 0) "" else ",", stations[picks[id].station].code });
    out.add("PASS {d} stations={s}", .{ pass, codes.value() });
    solutionLine(out, "GRID", run.grid, run.grid_rms);
    var profile: c.Text = .{};
    profile.add("PROFILE", .{});
    for (run.profile) |value| profile.add(" {s}", .{decimal(value, 4)});
    out.add("{s}", .{profile.value()});
    traceLines(out, run);
    for (ids, 0..) |id, i| {
        const pick = picks[id];
        const station = stations[pick.station];
        const d = locator.distance(run.solution, station);
        out.add("RES {s} dist={s} tt={s} obs={s} res={s}", .{ station.code, decimal(d, 1), decimal(d / p.velocity,
             4), timeText(pick.sample), decimal(run.residual[i], 4) });
    }
}
const Position = struct { column: i64 = 0, row: i64 = 0, valid: bool = false };
const Grid = [][]u8;
fn positionText(position: Position) []const u8 {
    return if (position.valid) c.fmt("{d},{d}", .{ position.column, position.row }) else "outside";
}
fn mapPosition(x: i64, y: i64, p: c.Params) Position {
    if (x < 10 * p.area[0] or x >= 10 * p.area[1] or y < 10 * p.area[2] or y >= 10 * p.area[3]) return .{};
    return .{ .column = @divFloor((x - 10 * p.area[0]) * p.map_size[0], 10 * (p.area[1] - p.area[0])),
         .row = p.map_size[1] - 1 - @divFloor((y - 10 * p.area[2]) * p.map_size[1], 10 * (p.area[3] - p.area[2])),
         .valid = true };
}
fn sectionPosition(coordinate: i64, z: i64, low: i64, high: i64, p: c.Params) Position {
    if (coordinate < 10 * low or coordinate >= 10 * high or z >= 10 * p.section[0]) return .{};
    return .{ .column = @divFloor((coordinate - 10 * low) * p.map_size[0], 10 * (high - low)), .row = @divFloor(z * p.section[1],
         10 * p.section[0]), .valid = true };
}
fn symbol(event: Event) u8 {
    const h = magnitude.scaled(event.ml orelse return '?', 2);
    return if (h < 100) '.' else if (h < 200) 'o' else if (h < 300) 'O' else '@';
}
fn grid(width: i64, height: i64) Grid {
    const out = c.alloc([]u8, c.u(height));
    for (out) |*row| {
        row.* = c.alloc(u8, c.u(width));
        @memset(row.*, ' ');
    }
    return out;
}
fn place(chart: Grid, position: Position, value: u8) void {
    if (!position.valid) return;
    const priority = " ?.oO@^";
    const current = &chart[c.u(position.row)][c.u(position.column)];
    if (std.mem.indexOfScalar(u8, priority, value).? > std.mem.indexOfScalar(u8, priority, current.*).?) current.* = value;
}
fn draw(out: *c.Lines, chart: Grid) void {
    const frame = c.alloc(u8, chart[0].len);
    @memset(frame, '-');
    out.add("+{s}+", .{frame});
    for (chart) |row| out.add("|{s}|", .{row});
    out.add("+{s}+", .{frame});
}
fn pickLess(_: void, a: c.Pick, b: c.Pick) bool {
    return a.sample < b.sample or (a.sample == b.sample and a.station < b.station);
}
fn indexLess(picks: []const c.Pick, a: usize, b: usize) bool {
    return picks[a].station < picks[b].station;
}
fn floatLess(_: void, a: f64, b: f64) bool {
    return a < b;
}
fn integerLess(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn fits(event: Event, bounds: [3]f64) bool {
    return event.gap <= bounds[0] and event.final.rms <= bounds[1] and event.ellipse.smaj <= bounds[2];
}
fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var text: c.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.load(init.io);
    const p = input.params;
    const stations = input.stations;
    var pick_list: std.ArrayList(c.Pick) = .empty;
    for (stations, 0..) |*station, index| for (picker.detect(station, index, p)) |pick| c.append(c.Pick, &pick_list, pick);
    const picks = pick_list.items;
    std.mem.sort(c.Pick, picks, {}, pickLess);
    const candidates = associator.associate(picks, p);
    var event_list: std.ArrayList(Event) = .empty;
    var locations: c.Lines = .{};
    var rejected: usize = 0;
    for (candidates, 1..) |candidate, number| {
        std.mem.sort(usize, candidate.picks, @as([]const c.Pick, picks), indexLess);
        const initial_obs = observations(candidate.picks, picks, stations, false);
        const first = locator.locate(initial_obs[0..candidate.picks.len], stations, p);
        var retained: std.ArrayList(usize) = .empty;
        var dropped: std.ArrayList(usize) = .empty;
        var drop_residual: std.ArrayList(f64) = .empty;
        for (candidate.picks, 0..) |id, i| {
            if (@abs(first.residual[i]) > p.limit) {
                c.append(usize, &dropped, id);
                c.append(f64, &drop_residual, first.residual[i]);
            } else c.append(usize, &retained, id);
        }
        locations.add("CANDIDATE {d} picks={d} first={s}", .{ number, candidate.picks.len, timeText(picks[candidate.first].sample) });
        passLines(&locations, 1, candidate.picks, first, picks, stations, p);
        for (dropped.items, drop_residual.items) |id, value| locations.add("DROP {s} res={s}", .{ stations[picks[id].station].code,
             decimal(value, 4) });
        if (dropped.items.len > 0 and retained.items.len < c.u(p.minimum)) {
            rejected += 1;
            for (candidate.picks) |id| picks[id].state = .rejected;
            locations.add("RESULT REJECTED stations={d}", .{retained.items.len});
            continue;
        }
        var adopted = first;
        if (dropped.items.len > 0) {
            const remaining_obs = observations(retained.items, picks, stations, false);
            adopted = locator.locate(remaining_obs[0..retained.items.len], stations, p);
            passLines(&locations, 2, retained.items, adopted, picks, stations, p);
        }
        const event_number = event_list.items.len + 1;
        for (retained.items, 0..) |id, i| {
            const pick = &picks[id];
            pick.state = .used;
            pick.event = event_number;
            pick.first_residual = adopted.residual[i];
            const station = &stations[pick.station];
            station.used += 1;
            station.correction += pick.first_residual;
            station.first_square += pick.first_residual * pick.first_residual;
        }
        for (dropped.items) |id| {
            picks[id].state = .dropped;
            picks[id].event = event_number;
        }
        c.append(Event, &event_list, .{ .used = retained.items, .first = adopted });
        locations.add("RESULT EVENT {d}", .{event_number});
    }
    const events = event_list.items;
    locations.add("CORRECTIONS", .{});
    for (stations) |*station| {
        if (station.used > 0) station.correction /= c.f(station.used);
        locations.add("{s} n={d} correction={s}", .{ station.code, station.used, decimal(station.correction, 4) });
    }
    for (events, 1..) |*event, number| {
        event.observations = observations(event.used, picks, stations, true);
        const obs = event.observations[0..event.used.len];
        event.start_rms = locator.rms(event.first.solution, obs, stations, p.velocity);
        event.final = locator.geiger(event.first.solution, obs, stations, p.velocity);
        const q = event.final.solution;
        event.ellipse = locator.ellipse(q, obs, stations, p.velocity);
        var angles: [12]f64 = undefined;
        event.dmin = std.math.inf(f64);
        for (event.used, 0..) |id, i| {
            const pick = &picks[id];
            const station = &stations[pick.station];
            pick.residual = event.final.residual[i];
            station.final_square += pick.residual * pick.residual;
            var angle = std.math.atan2(c.f(station.x) - q[0], c.f(station.y) - q[1]) * 180 / 3.141592653589793;
            if (angle < 0) angle += 360;
            angles[i] = angle;
            const dx = c.f(station.x) - q[0];
            const dy = c.f(station.y) - q[1];
            event.dmin = @min(event.dmin, @sqrt(dx * dx + dy * dy));
        }
        const bearings = angles[0..event.used.len];
        std.mem.sort(f64, bearings, {}, floatLess);
        event.gap = bearings[0] + 360 - bearings[bearings.len - 1];
        for (1..bearings.len) |i| event.gap = @max(event.gap, bearings[i] - bearings[i - 1]);
        event.quality = if (fits(event.*, p.qa)) 'A' else if (fits(event.*, p.qb)) 'B' else 'C';
        const dx = q[0] - event.first.solution[0];
        const dy = q[1] - event.first.solution[1];
        event.dh = @sqrt(dx * dx + dy * dy);
        event.dz = q[2] - event.first.solution[2];
        for (event.used, 0..) |id, omitted| {
            var remaining: [12]locator.Observation = undefined;
            var count: usize = 0;
            for (obs, 0..) |observation, j| if (j != omitted) {
                remaining[count] = observation;
                count += 1;
            };
            const alternative = locator.geiger(q, remaining[0..count], stations, p.velocity).solution;
            const x = alternative[0] - q[0];
            const y = alternative[1] - q[1];
            const z = alternative[2] - q[2];
            event.jack[omitted] = .{ .station = picks[id].station, .dx = x, .dy = y, .dz = z, .shift = @sqrt(x * x + y * y) };
            if (event.jack[omitted].shift > event.jack[event.max_jack].shift) event.max_jack = omitted;
        }
        locations.add("EVENT {d}", .{number});
        solutionLine(&locations, "START", event.first.solution, event.start_rms);
        traceLines(&locations, event.final);
        for (event.used) |id| {
            const pick = picks[id];
            const station = stations[pick.station];
            const d = locator.distance(q, station);
            locations.add("RES {s} dist={s} tt={s} obs={s} corr={s} res={s}", .{ station.code, decimal(d,
                 1), decimal(d / p.velocity, 4), timeText(pick.sample), decimal(station.correction,
                 4), decimal(pick.residual, 4) });
        }
        const e = event.ellipse;
        locations.add("ELLIPSE smaj={s} smin={s} az={s} erz={s} ert={s}", .{ decimal(e.smaj, 1), decimal(e.smin,
             1), decimal(e.az, 1), decimal(e.erz, 1), decimal(e.ert, 4) });
        locations.add("SHIFT dh={s} dz={s}", .{ decimal(event.dh, 1), decimal(event.dz, 1) });
        locations.add("GAP {s} DMIN {s} QUALITY {c}", .{ decimal(event.gap, 1), decimal(event.dmin, 1), event.quality });
        for (event.jack[0..event.used.len]) |jack| locations.add("JACK {s} dx={s} dy={s} dz={s} shift={s}",
             .{ stations[jack.station].code, decimal(jack.dx, 1), decimal(jack.dy, 1), decimal(jack.dz,
             1), decimal(jack.shift, 1) });
        const maximum = event.jack[event.max_jack];
        locations.add("JACKKNIFE max={s} station={s}", .{ decimal(maximum.shift, 1), stations[maximum.station].code });
    }
    for (events) |*event| {
        var local: [12]f64 = undefined;
        var duration: [12]f64 = undefined;
        var count: usize = 0;
        for (event.used, 0..) |id, i| {
            const pick = picks[id];
            const value = magnitude.magnitude(pick, locator.distance(event.final.solution, stations[pick.station]) / 1000, p);
            event.magnitudes[i] = value;
            duration[i] = value.md;
            if (value.ml) |ml| {
                local[count] = ml;
                count += 1;
            }
        }
        if (count > 0) event.ml = magnitude.median(local[0..count]);
        event.md = magnitude.median(duration[0..event.used.len]);
        for (event.used, 0..) |id, i| if (event.magnitudes[i].ml) |ml| {
            const station = &stations[picks[id].station];
            station.mag_correction += ml - event.ml.?;
            station.mag_count += 1;
        };
    }
    for (stations) |*station| if (station.mag_count > 0) {
        station.mag_correction /= c.f(station.mag_count);
    };
    for (events) |*event| {
        var corrected: [12]f64 = undefined;
        var count: usize = 0;
        for (event.used, 0..) |id, i| if (event.magnitudes[i].ml) |ml| {
            corrected[count] = ml - stations[picks[id].station].mag_correction;
            count += 1;
        };
        if (count > 0) event.mlc = magnitude.median(corrected[0..count]);
    }
    var point_count: usize = 0;
    var sd: f64 = 0;
    var st: f64 = 0;
    var sdd: f64 = 0;
    var sdt: f64 = 0;
    for (events) |event| for (event.used) |id| {
        const pick = picks[id];
        const d = locator.distance(event.final.solution, stations[pick.station]) / 1000;
        const t = pick.time() - event.final.solution[3];
        point_count += 1;
        sd += d;
        st += t;
        sdd += d * d;
        sdt += d * t;
    };
    const n = c.f(point_count);
    const slope = (n * sdt - sd * st) / (n * sdd - sd * sd);
    const intercept = (st - slope * sd) / n;
    var ss: f64 = 0;
    for (events) |event| for (event.used) |id| {
        const pick = picks[id];
        const d = locator.distance(event.final.solution, stations[pick.station]) / 1000;
        const t = pick.time() - event.final.solution[3];
        const r = t - intercept - slope * d;
        ss += r * r;
    };
    locations.add("FIT n={d} velocity={s} intercept={s} rms={s}", .{ point_count, decimal(1000 / slope,
         1), decimal(intercept, 4), decimal(@sqrt(ss / n), 4) });
    var cluster_count: usize = 0;
    const members = c.alloc(usize, events.len);
    for (events, 0..) |*first, index| {
        if (first.cluster > 0) continue;
        cluster_count += 1;
        var member_count: usize = 1;
        members[0] = index;
        first.cluster = cluster_count;
        var head: usize = 0;
        while (head < member_count) : (head += 1) {
            const a = events[members[head]].final.solution;
            for (events, 0..) |*other, j| {
                if (other.cluster > 0) continue;
                const b = other.final.solution;
                var d2: f64 = 0;
                for (0..3) |axis| d2 += (a[axis] - b[axis]) * (a[axis] - b[axis]);
                if (@abs(a[3] - b[3]) <= p.cluster[1] and @sqrt(d2) <= p.cluster[0]) {
                    other.cluster = cluster_count;
                    members[member_count] = j;
                    member_count += 1;
                }
            }
        }
        std.mem.sort(usize, members[0..member_count], {}, integerLess);
        if (member_count > 1) {
            var center: locator.Solution = [_]f64{0} ** 4;
            var low = events[members[0]].final.solution[3];
            var high = low;
            var numbers: c.Text = .{};
            for (members[0..member_count], 0..) |member, i| {
                numbers.add("{s}{d}", .{ if (i == 0) "" else ",", member + 1 });
                const q = events[member].final.solution;
                for (0..3) |axis| center[axis] += q[axis];
                low = @min(low, q[3]);
                high = @max(high, q[3]);
            }
            locations.add("CLUSTER {d} events={s} x={s} y={s} z={s} span={s}", .{ cluster_count, numbers.value(),
                 decimal(center[0] / c.f(member_count), 1), decimal(center[1] / c.f(member_count),
                 1), decimal(center[2] / c.f(member_count), 1), decimal(high - low, 3) });
        }
    }
    const station_sets = c.alloc([12]bool, events.len);
    @memset(station_sets, [_]bool{false} ** 12);
    for (events, station_sets) |event, *set| for (event.used) |id| {
        set[picks[id].station] = true;
    };
    locations.add("ADDED", .{});
    for (picks) |*pick| {
        if (pick.state != .unassociated) continue;
        var selected: ?usize = null;
        var best = std.math.inf(f64);
        var residual: f64 = 0;
        for (events, 0..) |event, ei| {
            if (station_sets[ei][pick.station]) continue;
            const q = event.final.solution;
            const rho = pick.time() - q[3] - locator.distance(q, stations[pick.station]) / p.velocity - stations[pick.station].correction;
            if (@abs(rho) <= p.limit and @abs(rho) < best) {
                best = @abs(rho);
                selected = ei;
                residual = rho;
            }
        }
        if (selected) |ei| {
            pick.state = .added;
            pick.event = ei + 1;
            pick.residual = residual;
            station_sets[ei][pick.station] = true;
            locations.add("{s} sample={d} event={d} res={s}", .{ stations[pick.station].code, pick.sample,
                 pick.event, decimal(pick.residual, 4) });
        }
    }
    var unassociated: usize = 0;
    for (picks) |pick| unassociated += @intFromBool(pick.state == .unassociated);
    const depths = c.alloc(f64, events.len);
    var quality = [_]usize{ 0, 0, 0 };
    var total_rms: f64 = 0;
    var min_depth = std.math.inf(f64);
    var max_depth = -std.math.inf(f64);
    for (events, depths) |event, *depth| {
        depth.* = event.final.solution[2];
        min_depth = @min(min_depth, depth.*);
        max_depth = @max(max_depth, depth.*);
        quality[event.quality - 'A'] += 1;
        total_rms += event.final.rms;
    }
    locations.add("SUMMARY picks={d} candidates={d} events={d} rejected={d} unassociated={d}", .{ picks.len,
         candidates.len, events.len, rejected, unassociated });
    locations.add("DEPTH min={s} median={s} max={s}", .{ decimal(min_depth, 1), decimal(magnitude.median(depths),
         1), decimal(max_depth, 1) });
    locations.add("QUALITY A={d} B={d} C={d} mean_rms={s}", .{ quality[0], quality[1], quality[2],
         decimal(total_rms / c.f(events.len), 4) });
    var pick_file: c.Lines = .{};
    var catalog: c.Lines = .{};
    var mag: c.Lines = .{};
    var station_file: c.Lines = .{};
    var map_file: c.Lines = .{};
    pick_file.add("station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual", .{});
    for (picks) |pick| pick_file.add("{s},{d},{s},{d},{s},{d},{s},{d},{s},{s}", .{ stations[pick.station].code,
         pick.sample, timeText(pick.sample), pick.duration, decimal(pick.ratio, 2), pick.amplitude,
         if (pick.clipped) "yes" else "no", pick.event, @tagName(pick.state), if (pick.state == .used or pick.state == .added) decimal(pick.residual,
         4) else "-" });
    catalog.add("event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster", .{});
    var local: std.ArrayList(f64) = .empty;
    var duration: std.ArrayList(f64) = .empty;
    for (events, 1..) |event, number| {
        const q = event.final.solution;
        const e = event.ellipse;
        catalog.add("{d},{s},{s},{s},{s},{s},{d},{s},{s},{s},{s},{s},{s},{s},{s},{c},{d}", .{ number,
             decimal(q[3], 3), decimal(q[0], 1), decimal(q[1], 1), decimal(q[2], 1), decimal(event.final.rms,
             4), event.used.len, decimal(event.gap, 1), decimal(event.dmin, 1), decimal(e.smaj, 1),
             decimal(e.smin, 1), decimal(e.az, 1), decimal(e.erz, 1), optionalDecimal(event.ml), decimal(event.md,
             2), event.quality, event.cluster });
        var available: usize = 0;
        for (event.magnitudes[0..event.used.len]) |value| available += @intFromBool(value.ml != null);
        mag.add("EVENT {d} ML={s} n={d} MD={s}", .{ number, optionalDecimal(event.ml), available, decimal(event.md, 2) });
        for (event.used, 0..) |id, i| {
            const pick = picks[id];
            const value = event.magnitudes[i];
            if (value.ml) |ml| {
                mag.add("{s} r={s} amp={d} ml={s} res={s} dur={d} md={s}", .{ stations[pick.station].code,
                     decimal(value.radius, 3), pick.amplitude, decimal(ml, 2), decimal(ml - event.ml.?,
                     2), pick.duration, decimal(value.md, 2) });
            } else mag.add("{s} r={s} amp={d} clipped dur={d} md={s}", .{ stations[pick.station].code,
                 decimal(value.radius, 3), pick.amplitude, pick.duration, decimal(value.md, 2) });
        }
        if (event.ml) |ml| {
            c.append(f64, &local, ml);
            c.append(f64, &duration, event.md);
        }
    }
    mag.add("CORRECTED", .{});
    for (events, 1..) |event, number| mag.add("EVENT {d} MLC={s}", .{ number, optionalDecimal(event.mlc) });
    const frequency = magnitude.frequency(local.items, duration.items);
    mag.add("FMD", .{});
    var class = frequency.counts[0].value;
    while (class <= frequency.counts[frequency.counts.len - 1].value) : (class += 1) {
        var count: usize = 0;
        var cumulative: usize = 0;
        for (frequency.counts) |entry| {
            if (entry.value == class) count = entry.count;
            if (entry.value >= class) cumulative += entry.count;
        }
        mag.add("M={s} N={d} CUM={d}", .{ magnitude.classText(class), count, cumulative });
    }
    mag.add("MC {s}", .{magnitude.classText(frequency.completeness)});
    mag.add("BVALUE {s} SIGMA {s} N {d}", .{ decimal(frequency.b, 3), decimal(frequency.sigma, 3), frequency.nb });
    mag.add("AVALUE {s}", .{decimal(frequency.a, 3)});
    mag.add("MLMD n={d} slope={s} intercept={s} r={s} mean_diff={s}", .{ frequency.n, decimal(frequency.slope,
         3), decimal(frequency.intercept, 3), decimal(frequency.r, 3), decimal(frequency.mean_diff,
         3) });
    const t = p.timeline;
    const timeline = grid(t[1], t[4]);
    for (events) |event| {
        const ml = event.ml orelse continue;
        const time = magnitude.scaled(event.final.solution[3], 3);
        const h = magnitude.scaled(ml, 2);
        if (time < 0 or time >= 1000 * t[0] or h < 100 * t[2]) continue;
        const column = @divFloor(time * t[1], 1000 * t[0]);
        const level = @min(t[4] - 1, @divFloor((h - 100 * t[2]) * t[4], 100 * (t[3] - t[2])));
        var k: i64 = 0;
        while (k <= level) : (k += 1) {
            const cell = &timeline[c.u(t[4] - 1 - k)][c.u(column)];
            if (k == level) cell.* = 'o' else if (cell.* == ' ') cell.* = '|';
        }
    }
    mag.add("TIMELINE t=0..{d} ML={d}..{d}", .{ t[0], t[2], t[3] });
    draw(&mag, timeline);
    for (stations, 0..) |station, si| {
        var states = [_]usize{0} ** 5;
        var count: usize = 0;
        for (picks) |pick| if (pick.station == si) {
            states[@intFromEnum(pick.state)] += 1;
            count += 1;
        };
        station_file.add("STATION {s} x={d} y={d} elevation={d}", .{ station.code, station.x, station.y, station.elevation });
        station_file.add("SAMPLES start={d} count={d} mean={d} noise={s} peak={d} clipped={d}", .{ station.start,
             station.samples.len, station.mean, decimal(station.noise, 1), station.peak, station.clipped });
        station_file.add("TRIGGERS total={d} short={d} picks={d}", .{ station.triggers, station.short_triggers, count });
        station_file.add("PICKS used={d} dropped={d} added={d} rejected={d} unassociated={d}", .{ states[0],
             states[1], states[2], states[3], states[4] });
        station_file.add("RESIDUALS n={d} rms={s} correction={s} after={s}", .{ station.used, if (station.used > 0) decimal(@sqrt(station.first_square / c.f(station.used)),
             4) else "-", decimal(station.correction, 4), if (station.used > 0) decimal(@sqrt(station.final_square / c.f(station.used)),
             4) else "-" });
        station_file.add("MAGNITUDES n={d} correction={s}", .{ station.mag_count, decimal(station.mag_correction, 2) });
    }
    const map = grid(p.map_size[0], p.map_size[1]);
    const ew = grid(p.map_size[0], p.section[1]);
    const ns = grid(p.map_size[0], p.section[1]);
    const positions = c.alloc([3]Position, events.len);
    for (events, positions) |event, *points| {
        const x = magnitude.scaled(event.final.solution[0], 1);
        const y = magnitude.scaled(event.final.solution[1], 1);
        const z = magnitude.scaled(event.final.solution[2], 1);
        points.* = .{ mapPosition(x, y, p), sectionPosition(x, z, p.area[0], p.area[1], p), sectionPosition(y,
             z, p.area[2], p.area[3], p) };
        place(map, points[0], symbol(event));
        place(ew, points[1], symbol(event));
        place(ns, points[2], symbol(event));
    }
    const station_positions = c.alloc(Position, stations.len);
    for (stations, station_positions) |station, *position| {
        position.* = mapPosition(10 * station.x, 10 * station.y, p);
        place(map, position.*, '^');
    }
    map_file.add("MAP x={d}..{d} y={d}..{d}", .{ p.area[0], p.area[1], p.area[2], p.area[3] });
    draw(&map_file, map);
    map_file.add("SECTION EW x={d}..{d} z=0..{d}", .{ p.area[0], p.area[1], p.section[0] });
    draw(&map_file, ew);
    map_file.add("SECTION NS y={d}..{d} z=0..{d}", .{ p.area[2], p.area[3], p.section[0] });
    draw(&map_file, ns);
    map_file.add("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML", .{});
    for (stations, station_positions) |station, position| map_file.add("STATION {s} map={s}", .{ station.code,
         positionText(position) });
    for (events, positions, 1..) |event, points, number| map_file.add("EVENT {d} {c} map={s} ew={s} ns={s}",
         .{ number, symbol(event), positionText(points[0]), positionText(points[1]), positionText(points[2]) });
    try write(init.io, "picks.csv", pick_file);
    try write(init.io, "locations.txt", locations);
    try write(init.io, "catalog.csv", catalog);
    try write(init.io, "magnitudes.txt", mag);
    try write(init.io, "stations.txt", station_file);
    try write(init.io, "map.txt", map_file);
}
