const std = @import("std");
const d = @import("dataset.zig");
const grid_index = @import("grid_index.zig");
const dbscan = @import("dbscan.zig");
const optics_module = @import("optics.zig");
const r = @import("report.zig");
const Optics = optics_module.Optics;
fn number(value: i64) []const u8 {
    return if (value == d.INF) "-" else d.fmt("{d}", .{value});
}
fn character(label: i64) u8 {
    return if (label < 0) '.' else if (label < 26) 'A' + @as(u8, @intCast(label)) else if (label < 52) 'a' + @as(u8,
         @intCast(label - 26)) else '#';
}
fn clusterCount(labels: []const i64) usize {
    var count: i64 = 0;
    for (labels) |label| count = @max(count, label + 1);
    return d.u(count);
}
fn noiseCount(labels: []const i64) usize {
    var count: usize = 0;
    for (labels) |label| if (label < 0) {
        count += 1;
    };
    return count;
}
fn groups(labels: []const i64) [][]usize {
    const lists = d.alloc(std.ArrayList(usize), clusterCount(labels));
    @memset(lists, .empty);
    for (labels, 0..) |label, id| if (label >= 0) d.append(usize, &lists[d.u(label)], id);
    const result = d.alloc([]usize, lists.len);
    for (lists, result) |list, *target| target.* = list.items;
    return result;
}
fn extraction(optics: Optics, radius: i64) []i64 {
    const labels = d.alloc(i64, optics.order.len);
    var cluster: i64 = -1;
    const threshold = radius * radius;
    for (optics.order) |id| {
        if (optics.reach[id] > threshold) {
            if (optics.core[id] <= threshold) {
                cluster += 1;
                labels[id] = cluster;
            } else labels[id] = -1;
        } else labels[id] = cluster;
    }
    return labels;
}
fn integerLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
const KneeContext = struct { neighbors: d.Distances, k: usize };
fn kneeLess(context: KneeContext, a: usize, b: usize) bool {
    const first = context.neighbors[a][context.k - 1];
    const second = context.neighbors[b][context.k - 1];
    return if (first != second) first > second else a < b;
}
const Knee = struct { rank: usize, point: usize, radius: i64, distance: i64, cross: i64, order: []usize };
fn knee(neighbors: d.Distances, k: usize) Knee {
    const n = neighbors.len;
    const order = d.sequence(n);
    std.mem.sort(usize, order, KneeContext{ .neighbors = neighbors, .k = k }, kneeLess);
    const first = neighbors[order[0]][k - 1];
    const last = neighbors[order[n - 1]][k - 1];
    var best: usize = 0;
    var greatest: i64 = -1;
    for (order, 0..) |id, position| {
        const cross: i64 = @intCast(@abs(d.n(n - 1) * (neighbors[id][k - 1] - first) - (last - first) * d.n(position)));
        if (cross > greatest) {
            greatest = cross;
            best = position;
        }
    }
    const value = neighbors[order[best]][k - 1];
    var radius: i64 = 1;
    while (radius * radius < value) radius += 1;
    return .{ .rank = best + 1, .point = order[best], .radius = radius, .distance = value, .cross = greatest, .order = order };
}
const SteepArea = struct { down: bool, first: usize, last: usize };
const XiCluster = struct {
    first: usize,
    last: usize,
    label: ?i64 = null,
    parent: ?usize = null,
    fn size(self: XiCluster) usize {
        return self.last - self.first + 1;
    }
};
const XiResult = struct { labels: []i64, areas: []SteepArea, clusters: []XiCluster, reach: []i64 };
const SteepFlags = struct {
    steep_up: []bool,
    steep_down: []bool,
    up: []bool,
    down: []bool,
    n: usize,
    min_points: usize,
    fn extend(self: SteepFlags, first: usize, descending: bool) usize {
        var end = first;
        var count: usize = 0;
        for (first..self.n + 1) |i| {
            if (if (descending) self.steep_down[i] else self.steep_up[i]) {
                end = i;
                count = 0;
            } else if (if (descending) self.up[i] else self.down[i]) break else {
                count += 1;
                if (count > self.min_points) break;
            }
        }
        return end;
    }
};
fn xle(a: i64, b: i64, alpha: i64, beta: i64) bool {
    if (b == d.INF) return true;
    if (a == d.INF) return false;
    return beta * a <= alpha * b;
}
fn xiExtract(optics: Optics, params: d.Params) XiResult {
    const n = optics.order.len;
    const alpha = (params.xi_v - params.xi_u) * (params.xi_v - params.xi_u);
    const beta = params.xi_v * params.xi_v;
    const reach = d.alloc(i64, n + 2);
    @memset(reach, d.INF);
    for (optics.order, 1..) |id, position| reach[position] = optics.reach[id];
    const flags: SteepFlags = .{ .steep_up = d.alloc(bool, n + 1), .steep_down = d.alloc(bool, n + 1),
         .up = d.alloc(bool, n + 1), .down = d.alloc(bool, n + 1), .n = n, .min_points = params.min_points };
    @memset(flags.steep_up, false);
    @memset(flags.steep_down, false);
    @memset(flags.up, false);
    @memset(flags.down, false);
    for (1..n + 1) |i| {
        if (reach[i] == d.INF and reach[i + 1] == d.INF) continue;
        flags.steep_up[i] = xle(reach[i], reach[i + 1], alpha, beta);
        flags.steep_down[i] = xle(reach[i + 1], reach[i], alpha, beta);
        flags.up[i] = flags.steep_up[i] or reach[i] < reach[i + 1];
        flags.down[i] = flags.steep_down[i] or reach[i] > reach[i + 1];
    }
    const DownArea = struct { first: usize, last: usize, maximum: i64 };
    var down_areas: std.ArrayList(DownArea) = .empty;
    var areas: std.ArrayList(SteepArea) = .empty;
    var clusters: std.ArrayList(XiCluster) = .empty;
    var index: usize = 1;
    var mib: i64 = 0;
    for (1..n + 1) |s| {
        if (s < index or (!flags.steep_up[s] and !flags.steep_down[s])) continue;
        for (reach[index .. s + 1]) |value| mib = @max(mib, value);
        if (mib == d.INF) down_areas.items.len = 0 else {
            var kept: usize = 0;
            for (down_areas.items) |area| if (xle(mib, reach[area.first], alpha, beta)) {
                down_areas.items[kept] = .{ .first = area.first, .last = area.last, .maximum = @max(area.maximum, mib) };
                kept += 1;
            };
            down_areas.items.len = kept;
        }
        if (flags.steep_down[s]) {
            const end = flags.extend(s, true);
            d.append(DownArea, &down_areas, .{ .first = s, .last = end, .maximum = 0 });
            d.append(SteepArea, &areas, .{ .down = true, .first = s, .last = end });
            index = end + 1;
            mib = reach[index];
        } else {
            const end = flags.extend(s, false);
            d.append(SteepArea, &areas, .{ .down = false, .first = s, .last = end });
            index = end + 1;
            mib = reach[index];
            var candidates: std.ArrayList(XiCluster) = .empty;
            for (down_areas.items) |area| {
                var cs = area.first;
                var ce = end;
                if (!xle(area.maximum, reach[ce + 1], alpha, beta)) continue;
                const left = reach[area.first];
                if (xle(reach[ce + 1], left, alpha, beta)) {
                    while (cs < area.last and reach[cs + 1] > reach[ce + 1]) cs += 1;
                } else if (xle(left, reach[ce + 1], alpha, beta)) {
                    while (ce > s and reach[ce - 1] > left) ce -= 1;
                }
                if (ce - cs + 1 >= params.xi_size and cs <= area.last and ce >= s) d.append(XiCluster,
                     &candidates, .{ .first = cs, .last = ce });
            }
            var candidate = candidates.items.len;
            while (candidate > 0) {
                candidate -= 1;
                d.append(XiCluster, &clusters, candidates.items[candidate]);
            }
        }
    }
    const positions = d.alloc(i64, n + 1);
    @memset(positions, -2);
    var next: i64 = 0;
    for (clusters.items) |*cluster| {
        var unassigned = true;
        for (positions[cluster.first .. cluster.last + 1]) |value| if (value != -2) {
            unassigned = false;
        };
        if (unassigned) {
            cluster.label = next;
            @memset(positions[cluster.first .. cluster.last + 1], next);
            next += 1;
        }
    }
    const labels = d.alloc(i64, n);
    for (optics.order, 1..) |id, position| labels[id] = if (positions[position] < 0) -1 else positions[position];
    for (clusters.items, 0..) |*cluster, j| for (clusters.items, 0..) |candidate, i| {
        if (i == j or candidate.first > cluster.first or candidate.last < cluster.last or !(candidate.size() > cluster.size() or (candidate.size() == cluster.size() and i > j))) continue;
        if (cluster.parent == null or candidate.size() < clusters.items[cluster.parent.?].size() or (candidate.size() == clusters.items[cluster.parent.?].size() and i < cluster.parent.?)) cluster.parent = i;
    };
    return .{ .labels = labels, .areas = areas.items, .clusters = clusters.items, .reach = reach };
}
const Setting = struct { name: []const u8, radius: i64, labels: []i64, core: []bool, db: bool = false,
     extraction_: bool = false };
fn turn(o: d.Point, a: d.Point, b: d.Point) i64 {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}
fn pointLess(points: []const d.Point, a: usize, b: usize) bool {
    return if (points[a].x != points[b].x) points[a].x < points[b].x else points[a].y < points[b].y;
}
fn hull(points: []const d.Point, members: []const usize) []usize {
    const ids = d.dupe(usize, members);
    std.mem.sort(usize, ids, points, pointLess);
    if (ids.len <= 2) return ids;
    var lower: std.ArrayList(usize) = .empty;
    var upper: std.ArrayList(usize) = .empty;
    for (ids) |id| {
        while (lower.items.len >= 2 and turn(points[lower.items[lower.items.len - 2]], points[lower.items[lower.items.len - 1]],
             points[id]) <= 0) lower.items.len -= 1;
        d.append(usize, &lower, id);
    }
    var i = ids.len;
    while (i > 0) {
        i -= 1;
        const id = ids[i];
        while (upper.items.len >= 2 and turn(points[upper.items[upper.items.len - 2]], points[upper.items[upper.items.len - 1]],
             points[id]) <= 0) upper.items.len -= 1;
        d.append(usize, &upper, id);
    }
    lower.items.len -= 1;
    for (upper.items[0 .. upper.items.len - 1]) |id| d.append(usize, &lower, id);
    return lower.items;
}
fn c2(value: i64) i64 {
    return @divTrunc(value * (value - 1), 2);
}
fn ari(first: []const i64, second: []const i64) [2]i64 {
    var cells = std.AutoHashMap([2]i64, i64).init(d.allocator);
    const rows = d.alloc(i64, clusterCount(first) + 1);
    const columns = d.alloc(i64, clusterCount(second) + 1);
    @memset(rows, 0);
    @memset(columns, 0);
    for (first, second) |a, b| {
        const key = [2]i64{ a, b };
        cells.put(key, (cells.get(key) orelse 0) + 1) catch @panic("allocation failed");
        rows[d.u(a + 1)] += 1;
        columns[d.u(b + 1)] += 1;
    }
    var s: i64 = 0;
    var a: i64 = 0;
    var b: i64 = 0;
    var iterator = cells.valueIterator();
    while (iterator.next()) |value| s += c2(value.*);
    for (rows) |value| a += c2(value);
    for (columns) |value| b += c2(value);
    const z = c2(d.n(first.len));
    const numerator = 2 * (z * s - a * b);
    const denominator = z * (a + b) - 2 * a * b;
    return if (denominator == 0) .{ 1, 1 } else .{ numerator, denominator };
}
fn findGrid(grids: []const grid_index.Grid, radius: i64) *const grid_index.Grid {
    for (grids) |*grid| if (grid.radius == radius) return grid;
    unreachable;
}
fn settingReport(out: *r.Lines, setting: Setting, points: []const d.Point, distances: d.Distances,
     grids: []const grid_index.Grid) void {
    const members = groups(setting.labels);
    var core_count: usize = 0;
    var border_count: usize = 0;
    for (setting.labels, setting.core) |label, core| if (label >= 0) {
        if (core) core_count += 1 else border_count += 1;
    };
    out.add("setting {s} eps {d} clusters {d} noise {d} core {d} border {d}", .{ setting.name, setting.radius,
         members.len, noiseCount(setting.labels), core_count, border_count });
    for (members, 0..) |ids, label| {
        var sx: i64 = 0;
        var sy: i64 = 0;
        var core: usize = 0;
        var xmin: i64 = 10001;
        var ymin: i64 = 10001;
        var xmax: i64 = 0;
        var ymax: i64 = 0;
        for (ids) |id| {
            sx += points[id].x;
            sy += points[id].y;
            if (setting.core[id]) core += 1;
            xmin = @min(xmin, points[id].x);
            ymin = @min(ymin, points[id].y);
            xmax = @max(xmax, points[id].x);
            ymax = @max(ymax, points[id].y);
        }
        var medoid = ids[0];
        var best = d.INF;
        for (ids) |id| {
            const x = d.n(ids.len) * points[id].x - sx;
            const y = d.n(ids.len) * points[id].y - sy;
            const value = x * x + y * y;
            if (value < best) {
                best = value;
                medoid = id;
            }
        }
        const vertices = hull(points, ids);
        var area2: i64 = 0;
        var diameter: i64 = 0;
        for (vertices, 0..) |id, index| {
            const a = points[id];
            const b = points[vertices[(index + 1) % vertices.len]];
            area2 += a.x * b.y - b.x * a.y;
            for (vertices) |q| diameter = @max(diameter, distances[id][q]);
        }
        area2 = @intCast(@abs(area2));
        const area = (xmax - xmin + 1) * (ymax - ymin + 1);
        out.add("cluster {d} {c} size {d} core {d} border {d} centroid {s} {s} medoid {d}", .{ label,
             character(d.n(label)), ids.len, core, ids.len - core, r.fraction(sx, d.n(ids.len)), r.fraction(sy,
             d.n(ids.len)), points[medoid].id });
        out.add("  bbox {d} {d} {d} {d} area {d} density {s}", .{ xmin, ymin, xmax, ymax, area, r.fraction(d.n(ids.len), area) });
        out.add("  hull {d} hull_area {d}.{d} diameter_sq {d} diameter {s}", .{ vertices.len, @divTrunc(area2,
             2), if (@mod(area2, 2) == 0) @as(usize, 0) else 5, diameter, r.root(diameter) });
    }
    if (!setting.db) return;
    const grid = findGrid(grids, setting.radius);
    var a = true;
    var b = true;
    var c = true;
    var isolated: usize = 0;
    var ambiguous: usize = 0;
    var details: r.Lines = .{};
    for (setting.labels, setting.core, 0..) |label, core, id| {
        if (core) {
            for (grid.neighbors[id]) |q| if (setting.core[q] and label != setting.labels[q]) {
                a = false;
            };
        } else if (label >= 0) {
            var found = false;
            const others = d.alloc(bool, members.len);
            @memset(others, false);
            for (grid.neighbors[id]) |q| if (setting.core[q]) {
                if (setting.labels[q] == label) found = true else others[d.u(setting.labels[q])] = true;
            };
            if (!found) b = false;
            var text: r.Text = .{};
            for (others, 0..) |other, cluster| if (other) text.add(" {d}", .{cluster});
            if (text.value().len > 0) {
                ambiguous += 1;
                details.add("  {d} cluster {d} also{s}", .{ points[id].id, label, text.value() });
            }
        } else {
            if (grid.neighbors[id].len == 1) isolated += 1;
            for (grid.neighbors[id]) |q| if (setting.core[q]) {
                c = false;
            };
        }
    }
    out.add("check {s} {s} {s}", .{ if (a) "ok" else "fail", if (b) "ok" else "fail", if (c) "ok" else "fail" });
    out.add("isolated {d}", .{isolated});
    out.add("ambiguous {d}", .{ambiguous});
    out.extend(details);
}
fn clusterMap(setting: Setting, points: []const d.Point, params: d.Params, kinds: bool) []const []const u8 {
    var x0: i64 = 10001;
    var y0: i64 = 10001;
    var x1: i64 = 0;
    var y1: i64 = 0;
    for (points) |point| {
        x0 = @min(x0, point.x);
        y0 = @min(y0, point.y);
        x1 = @max(x1, point.x);
        y1 = @max(y1, point.y);
    }
    const count = params.width * params.height;
    const occupied = d.alloc(bool, count);
    const multiple = d.alloc(bool, count);
    const labels = d.alloc(i64, count);
    const priority = d.alloc(u8, count);
    @memset(occupied, false);
    @memset(multiple, false);
    @memset(labels, -1);
    @memset(priority, 0);
    for (points, setting.labels, setting.core) |point, label, core| {
        const column = d.u(@divTrunc((point.x - x0) * d.n(params.width), x1 - x0 + 1));
        const row = d.u(@divTrunc((y1 - point.y) * d.n(params.height), y1 - y0 + 1));
        const cell = row * params.width + column;
        occupied[cell] = true;
        if (core) priority[cell] = 2 else if (label >= 0) priority[cell] = @max(priority[cell], 1);
        if (label >= 0) {
            if (labels[cell] < 0) labels[cell] = label else if (labels[cell] != label) multiple[cell] = true;
        }
    }
    const rows = d.alloc([]const u8, params.height);
    for (rows, 0..) |*row, row_index| {
        const text = d.alloc(u8, params.width);
        for (text, 0..) |*mark, column| {
            const cell = row_index * params.width + column;
            mark.* = if (!occupied[cell]) ' ' else if (kinds) (if (priority[cell] == 2) '#' else if (priority[cell] == 1) '+' else '.') else if (multiple[cell]) '*' else character(labels[cell]);
        }
        row.* = text;
    }
    return rows;
}
const Outlier = struct { point: usize, nearest: usize, distance: i64 };
fn outlierLess(_: void, a: Outlier, b: Outlier) bool {
    return if (a.distance != b.distance) a.distance > b.distance else a.point < b.point;
}
fn radiusLess(settings: []const Setting, a: usize, b: usize) bool {
    return if (settings[a].radius != settings[b].radius) settings[a].radius < settings[b].radius else a < b;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const input = try d.readInput(init.io);
    const points = input.points;
    const params = input.params;
    const n = points.len;
    const k = params.min_points - 1;
    const distances = d.alloc([]i64, n);
    const neighbors = d.alloc([]i64, n);
    for (0..n) |i| {
        distances[i] = d.alloc(i64, n);
        neighbors[i] = d.alloc(i64, n - 1);
        var next: usize = 0;
        for (0..n) |j| {
            distances[i][j] = d.distance(points[i], points[j]);
            if (i != j) {
                neighbors[i][next] = distances[i][j];
                next += 1;
            }
        }
        std.mem.sort(i64, neighbors[i], {}, integerLess);
    }
    const main_knee = knee(neighbors, k);
    var radii: std.ArrayList(i64) = .empty;
    for (params.eps) |radius| d.append(i64, &radii, radius);
    d.append(i64, &radii, main_knee.radius);
    d.append(i64, &radii, params.max_eps);
    std.mem.sort(i64, radii.items, {}, integerLess);
    var grids_list: std.ArrayList(grid_index.Grid) = .empty;
    for (radii.items) |radius| {
        if (grids_list.items.len > 0 and grids_list.items[grids_list.items.len - 1].radius == radius) continue;
        d.append(grid_index.Grid, &grids_list, grid_index.build(points, distances, radius));
    }
    const grids = grids_list.items;
    const optics = optics_module.run(findGrid(grids, params.max_eps), distances, params.min_points);
    const xi = xiExtract(optics, params);
    var setting_list: std.ArrayList(Setting) = .empty;
    for (0..params.eps.len + 1) |index| {
        const radius = if (index == params.eps.len) main_knee.radius else params.eps[index];
        const grid = findGrid(grids, radius);
        const core = d.alloc(bool, n);
        for (grid.neighbors, core) |row, *value| value.* = row.len >= params.min_points;
        d.append(Setting, &setting_list, .{ .name = d.fmt("{s}{d}", .{ if (index == params.eps.len) "knee" else "db",
             radius }), .radius = radius, .labels = dbscan.run(grid, params.min_points), .core = core,
             .db = true });
    }
    const db_count = setting_list.items.len;
    const knee_index = db_count - 1;
    for (params.extract) |radius| {
        const core = d.alloc(bool, n);
        for (optics.core, core) |distance_, *value| value.* = distance_ <= radius * radius;
        d.append(Setting, &setting_list, .{ .name = d.fmt("op{d}", .{radius}), .radius = radius, .labels = extraction(optics,
             radius), .core = core, .extraction_ = true });
    }
    const xi_core = d.alloc(bool, n);
    for (optics.core, xi_core) |value, *core| core.* = value != d.INF;
    d.append(Setting, &setting_list, .{ .name = "xi", .radius = params.max_eps, .labels = xi.labels, .core = xi_core });
    const settings = setting_list.items;
    const knee_setting = settings[knee_index];
    const xi_setting = settings[settings.len - 1];
    var labels_file: r.Lines = .{};
    var header: r.Text = .{};
    header.add("id", .{});
    for (settings) |setting| header.add(",{s}", .{setting.name});
    labels_file.add("{s}", .{header.value()});
    for (points, 0..) |point, id| {
        var line: r.Text = .{};
        line.add("{d}", .{point.id});
        for (settings) |setting| line.add(",{d}", .{setting.labels[id]});
        labels_file.add("{s}", .{line.value()});
    }
    var order_file: r.Lines = .{};
    order_file.add("order,id,core_sq,reach_sq,reach,predecessor", .{});
    for (optics.order, 1..) |id, position| order_file.add("{d},{d},{s},{s},{s},{s}", .{ position,
         points[id].id, number(optics.core[id]), number(optics.reach[id]), r.root(optics.reach[id]),
         if (optics.predecessor[id]) |previous| d.fmt("{d}", .{points[previous].id}) else "-" });
    var kdist: r.Lines = .{};
    kdist.add("k_distance k {d} points {d}", .{ k, n });
    kdist.add("rank id kdist_sq kdist", .{});
    for (main_knee.order, 1..) |id, position| kdist.add("{d} {d} {d} {s}", .{ position, points[id].id,
         neighbors[id][k - 1], r.root(neighbors[id][k - 1]) });
    kdist.blank();
    kdist.add("knee rank {d} id {d} kdist_sq {d} kdist {s} cross {d}", .{ main_knee.rank, points[main_knee.point].id,
         main_knee.distance, r.root(main_knee.distance), main_knee.cross });
    kdist.add("suggested_eps {d}", .{main_knee.radius});
    kdist.blank();
    kdist.add("knee_table", .{});
    for (1..2 * params.min_points + 1) |neighbor| {
        const curve = knee(neighbors, neighbor);
        kdist.add("k {d} rank {d} id {d} kdist_sq {d} eps {d}", .{ neighbor, curve.rank, points[curve.point].id,
             curve.distance, curve.radius });
    }
    kdist.blank();
    kdist.add("core_check", .{});
    for (settings[0..db_count]) |setting| {
        var core: usize = 0;
        var grid_core: usize = 0;
        for (neighbors, setting.core) |row, value| {
            if (row[k - 1] <= setting.radius * setting.radius) core += 1;
            if (value) grid_core += 1;
        }
        kdist.add("eps {d} core {d} non_core {d} grid_core {d} {s}", .{ setting.radius, core, n - core,
             grid_core, if (core == grid_core) "ok" else "mismatch" });
    }
    var core_ok = true;
    var optics_core: usize = 0;
    for (optics.core, neighbors) |core, row| if (core != d.INF) {
        optics_core += 1;
        if (core != row[k - 1]) core_ok = false;
    };
    kdist.add("optics max_eps {d} core {d} {s}", .{ params.max_eps, optics_core, if (core_ok) "ok" else "mismatch" });
    var out: r.Lines = .{};
    out.add("points {d} min_pts {d}", .{ n, params.min_points });
    var setting_names: r.Text = .{};
    setting_names.add("settings", .{});
    for (settings) |setting| setting_names.add(" {s}", .{setting.name});
    out.add("{s}", .{setting_names.value()});
    out.blank();
    out.add("grid", .{});
    for (grids) |grid| {
        out.add("eps {d} cells {d} busiest {d} {d} {d} candidates {d} pairs {d} brute_pairs {d} {s}",
             .{ grid.radius, grid.cells.count(), grid.busiest_x, grid.busiest_y, grid.busiest_count,
             grid.total_candidates, grid.pairs, grid.brute_pairs, if (grid.correct) "ok" else "mismatch" });
        var occupancy: r.Text = .{};
        occupancy.add("  occupancy", .{});
        for (grid.occupancy, 0..) |count, c| if (count > 0) occupancy.add(" {d}:{d}", .{ c, count });
        out.add("{s}", .{occupancy.value()});
    }
    for (settings) |setting| {
        out.blank();
        settingReport(&out, setting, points, distances, grids);
    }
    out.blank();
    out.add("hierarchy", .{});
    const hierarchy = d.sequence(db_count);
    std.mem.sort(usize, hierarchy, @as([]const Setting, settings), radiusLess);
    for (1..db_count) |index| {
        const a = settings[hierarchy[index - 1]];
        const b = settings[hierarchy[index]];
        out.add("{s} -> {s}", .{ a.name, b.name });
        const destinations = d.alloc(std.ArrayList(usize), clusterCount(b.labels));
        @memset(destinations, .empty);
        for (groups(a.labels), 0..) |group, label| for (group) |id| if (a.core[id]) {
            d.append(usize, &destinations[d.u(b.labels[id])], label);
            break;
        };
        for (destinations, 0..) |list, label| {
            var text: r.Text = .{};
            if (list.items.len == 0) text.add(" -", .{}) else for (list.items) |source| text.add(" {d}", .{source});
            out.add("  {d} <-{s}", .{ label, text.value() });
        }
    }
    out.blank();
    out.add("optics_vs_dbscan", .{});
    for (settings[db_count .. settings.len - 1]) |a| {
        var match: ?Setting = null;
        for (settings[0..db_count]) |b| if (b.radius == a.radius) {
            match = b;
            break;
        };
        const b = match orelse continue;
        const forward = d.alloc(i64, clusterCount(a.labels));
        const reverse = d.alloc(i64, clusterCount(b.labels));
        @memset(forward, -2);
        @memset(reverse, -2);
        var same = true;
        var border_noise: usize = 0;
        for (a.labels, b.labels, a.core) |x, y, core| {
            if (core) {
                if (forward[d.u(x)] != -2 and forward[d.u(x)] != y) same = false;
                if (reverse[d.u(y)] != -2 and reverse[d.u(y)] != x) same = false;
                forward[d.u(x)] = y;
                reverse[d.u(y)] = x;
            }
            if (x < 0 and y >= 0) border_noise += 1;
        }
        for (forward) |value| if (value == -2) {
            same = false;
        };
        for (reverse) |value| if (value == -2) {
            same = false;
        };
        var moved: usize = 0;
        if (same) for (a.labels, b.labels) |x, y| if (x >= 0 and forward[d.u(x)] != y) {
            moved += 1;
        };
        out.add("{s} {s} core_partition {s} border_as_noise {d} moved {s}", .{ a.name, b.name, if (same) "same" else "different",
             border_noise, if (same) d.fmt("{d}", .{moved}) else "-" });
    }
    var components: usize = 0;
    var singletons: usize = 0;
    var largest: usize = 0;
    var current: usize = 0;
    for (optics.order) |id| {
        if (optics.reach[id] == d.INF) {
            if (current > 0) {
                if (current == 1) singletons += 1;
                largest = @max(largest, current);
            }
            components += 1;
            current = 0;
        }
        current += 1;
    }
    if (current > 0) {
        if (current == 1) singletons += 1;
        largest = @max(largest, current);
    }
    out.blank();
    out.add("optics max_eps {d} core {d} components {d} singletons {d} largest {d}", .{ params.max_eps,
         optics_core, components, singletons, largest });
    out.blank();
    out.add("sweep max_eps {d}", .{params.max_eps});
    out.add("eps clusters noise largest", .{});
    const sweep = d.alloc(usize, d.u(params.max_eps) + 1);
    for (1..sweep.len) |radius| {
        const labels = extraction(optics, d.n(radius));
        const members = groups(labels);
        var largest_: usize = 0;
        for (members) |group| largest_ = @max(largest_, group.len);
        sweep[radius] = members.len;
        out.add("{d} {d} {d} {d}", .{ radius, members.len, noiseCount(labels), largest_ });
    }
    var stable_first: usize = 0;
    var stable_last: usize = 0;
    var first: usize = 1;
    while (first < sweep.len) {
        var last = first;
        while (last + 1 < sweep.len and sweep[last + 1] == sweep[first]) last += 1;
        if (sweep[first] >= 2 and (stable_first == 0 or last - first > stable_last - stable_first)) {
            stable_first = first;
            stable_last = last;
        }
        first = last + 1;
    }
    if (stable_first == 0) out.add("stable -", .{}) else out.add("stable clusters {d} eps {d} {d} length {d}",
         .{ sweep[stable_first], stable_first, stable_last, stable_last - stable_first + 1 });
    out.blank();
    out.add("xi {d}/{d} min_size {d} steep_areas {d}", .{ params.xi_u, params.xi_v, params.xi_size, xi.areas.len });
    for (xi.areas) |area| out.add("{s} {d} {d}", .{ if (area.down) "down" else "up", area.first, area.last });
    out.add("xi_clusters {d}", .{xi.clusters.len});
    for (xi.clusters, 0..) |cluster, index| {
        var valley = d.INF;
        for (xi.reach[cluster.first + 1 .. cluster.last + 1]) |value| valley = @min(valley, value);
        out.add("{d} start {d} end {d} size {d} label {s} parent {s} walls {s} {s} valley {s}", .{ index,
             cluster.first, cluster.last, cluster.size(), if (cluster.label) |label| d.fmt("{d}",
             .{label}) else "-", if (cluster.parent) |parent| d.fmt("{d}", .{parent}) else "-", r.root(xi.reach[cluster.first]),
             r.root(xi.reach[cluster.last + 1]), r.root(valley) });
    }
    var outliers: std.ArrayList(Outlier) = .empty;
    for (knee_setting.labels, 0..) |label, id| if (label < 0) {
        var nearest: usize = 0;
        var best = d.INF;
        for (knee_setting.core, 0..) |core, q| if (core and distances[id][q] < best) {
            nearest = q;
            best = distances[id][q];
        };
        d.append(Outlier, &outliers, .{ .point = id, .nearest = nearest, .distance = best });
    };
    std.mem.sort(Outlier, outliers.items, {}, outlierLess);
    out.blank();
    out.add("outliers {s} count {d}", .{ knee_setting.name, outliers.items.len });
    for (outliers.items) |item| out.add("{d} nearest_core {d} cluster {d} dist_sq {d} dist {s}", .{ points[item.point].id,
         points[item.nearest].id, knee_setting.labels[item.nearest], item.distance, r.root(item.distance) });
    const knee_members = groups(knee_setting.labels);
    const xi_members = groups(xi_setting.labels);
    out.blank();
    out.add("gaps {s}", .{knee_setting.name});
    for (knee_members, 0..) |a, label_a| for (label_a + 1..knee_members.len) |label_b| {
        const b = knee_members[label_b];
        var best = d.INF;
        var first_point: usize = 0;
        var second_point: usize = 0;
        for (a) |x| for (b) |y| if (distances[x][y] < best) {
            best = distances[x][y];
            first_point = x;
            second_point = y;
        };
        out.add("{d} {d} dist_sq {d} dist {s} between {d} {d}", .{ label_a, label_b, best, r.root(best),
             points[first_point].id, points[second_point].id });
    };
    const table = d.alloc([]usize, knee_members.len + 1);
    for (table) |*row| {
        row.* = d.alloc(usize, xi_members.len + 1);
        @memset(row.*, 0);
    }
    for (knee_setting.labels, xi_setting.labels) |a, b| table[d.u(a + 1)][d.u(b + 1)] += 1;
    out.blank();
    out.add("contingency {s} xi", .{knee_setting.name});
    var columns: r.Text = .{};
    columns.add("columns", .{});
    for (0..xi_members.len + 1) |c| columns.add(" {d}", .{d.n(c) - 1});
    out.add("{s}", .{columns.value()});
    for (table, 0..) |row, index| {
        var line: r.Text = .{};
        line.add("{d}", .{d.n(index) - 1});
        for (row) |value| line.add(" {d}", .{value});
        out.add("{s}", .{line.value()});
    }
    for (xi_members, 0..) |members, c| {
        var match: usize = 0;
        for (1..knee_members.len) |row| if (table[row + 1][c + 1] > table[match + 1][c + 1]) {
            match = row;
        };
        const shared = table[match + 1][c + 1];
        out.add("match {d} {d} shared {d} jaccard {s}", .{ c, match, shared, r.fraction(d.n(shared),
             d.n(knee_members[match].len + members.len - shared)) });
    }
    out.blank();
    out.add("ari", .{});
    for (settings, 0..) |a, index| for (settings[index + 1 ..]) |b| {
        const value = ari(a.labels, b.labels);
        out.add("{s} {s} {s} {s}", .{ a.name, b.name, r.fraction(value[0], value[1]), r.ariValue(value[0], value[1]) });
    };
    var maps: r.Lines = .{};
    for (settings) |setting| {
        const members = groups(setting.labels);
        maps.add("map {s} clusters {d} noise {d}", .{ setting.name, members.len, noiseCount(setting.labels) });
        maps.extend(r.framed(clusterMap(setting, points, params, false)));
        var legend: r.Text = .{};
        legend.add("legend", .{});
        if (members.len == 0) legend.add(" -", .{}) else for (members, 0..) |group, label| legend.add(" {c}={d}",
             .{ character(d.n(label)), group.len });
        maps.add("{s}", .{legend.value()});
        maps.blank();
    }
    maps.add("kinds {s}", .{knee_setting.name});
    maps.extend(r.framed(clusterMap(knee_setting, points, params, true)));
    maps.blank();
    const maximum = neighbors[main_knee.order[0]][k - 1];
    const heights = d.alloc(usize, params.kwidth);
    @memset(heights, 0);
    var knee_column: usize = 0;
    for (heights, 0..) |*height, c| {
        const start = c * n / params.kwidth;
        const end = (c + 1) * n / params.kwidth;
        const value = neighbors[main_knee.order[start]][k - 1];
        while (d.n(height.* + 1) * d.n(height.* + 1) * maximum <= d.n(params.kheight) * d.n(params.kheight) * value) height.* += 1;
        if (start < main_knee.rank and main_knee.rank <= end) knee_column = c;
    }
    const curve = d.alloc([]const u8, params.kheight);
    for (curve, 0..) |*row, index| {
        const cells = d.alloc(u8, params.kwidth);
        for (cells, heights, 0..) |*cell, height, c| cell.* = if (params.kheight - index <= height) '#' else if (c == knee_column) ':' else ' ';
        row.* = cells;
    }
    maps.add("kdist_plot k {d} max {s} knee_column {d}", .{ k, r.root(maximum), knee_column + 1 });
    maps.extend(r.framed(curve));
    var reach_top: i64 = 0;
    for (optics.reach) |value| if (value != d.INF) {
        reach_top = @max(reach_top, value);
    };
    maps.blank();
    var reach_header: r.Text = .{};
    reach_header.add("reachability width {d} max_reach {s} columns", .{ params.rwidth, r.root(reach_top) });
    for (settings[db_count..]) |setting| reach_header.add(" {s}", .{setting.name});
    maps.add("{s}", .{reach_header.value()});
    for (optics.order, 1..) |id, position| {
        var marks: r.Text = .{};
        for (settings[db_count..]) |setting| marks.add("{c}", .{character(setting.labels[id])});
        var length = params.rwidth;
        var mark: u8 = '-';
        if (optics.reach[id] != d.INF) {
            length = 0;
            mark = '#';
            while (d.n(length + 1) * d.n(length + 1) * reach_top <= d.n(params.rwidth) * d.n(params.rwidth) * optics.reach[id]) length += 1;
        }
        const bar = d.alloc(u8, length);
        @memset(bar, mark);
        maps.add("{d: >4} {d: >5} {s: >7} {s} |{s}", .{ position, points[id].id, r.root(optics.reach[id]), marks.value(), bar });
    }
    try r.writeLines(init.io, "labels.csv", labels_file);
    try r.writeLines(init.io, "optics_order.csv", order_file);
    try r.writeLines(init.io, "kdist.txt", kdist);
    try r.writeLines(init.io, "clusters.txt", out);
    try r.writeLines(init.io, "maps.txt", maps);
}
