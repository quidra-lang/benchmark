const std = @import("std");
const c = @import("predicates.zig");
const triangulation_module = @import("triangulation.zig");
const voronoi = @import("voronoi.zig");
const proximity = @import("proximity.zig");
const plot = @import("plot.zig");
const section_names = [_][]const u8{ "input", "summary", "insertions", "triangles", "edges", "hull",
     "convex_layers", "quality", "vertices", "voronoi_edges", "cells", "nearest", "components", "mst",
     "proximity", "degrees", "empty_circle", "extent", "spanner", "alpha", "sites", "queries", "delaunay_plot",
     "voronoi_plot" };
fn real(value: f64) []const u8 {
    return c.fmt("{d:.3}", .{if (@abs(value) < 0.0005) @as(f64, 0) else value});
}
fn integerWord(word: []const u8) bool {
    const begin: usize = if (word[0] == '-') 1 else 0;
    if (begin == word.len) return false;
    for (word[begin..]) |character| if (character < '0' or character > '9') return false;
    return true;
}
fn ids(values: []const usize) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else " ", value + 1 });
    return out.value();
}
fn triangleText(triangle: c.Triangle) []const u8 {
    return c.fmt("{d} {d} {d}", .{ triangle[0] + 1, triangle[1] + 1, triangle[2] + 1 });
}
fn optionalId(value: ?usize) []const u8 {
    return if (value) |id| c.fmt("{d}", .{id + 1}) else "-";
}
fn siteLess(points: []const c.Point, a: usize, b: usize) bool {
    return if (points[a].x != points[b].x) points[a].x < points[b].x else points[a].y < points[b].y;
}
fn hullOf(points: []const c.Point, sites: []const usize) []const usize {
    if (sites.len < 3) return sites;
    const sorted = c.dupe(usize, sites);
    std.mem.sort(usize, sorted, points, siteLess);
    var lower: std.ArrayList(usize) = .empty;
    var upper: std.ArrayList(usize) = .empty;
    for (sorted) |site| {
        while (lower.items.len >= 2 and c.orient(points[lower.items[lower.items.len - 2]], points[lower.items[lower.items.len - 1]],
             points[site]) <= 0) _ = lower.pop();
        c.append(usize, &lower, site);
    }
    var remaining = sorted.len;
    while (remaining > 0) {
        remaining -= 1;
        const site = sorted[remaining];
        while (upper.items.len >= 2 and c.orient(points[upper.items[upper.items.len - 2]], points[upper.items[upper.items.len - 1]],
             points[site]) <= 0) _ = upper.pop();
        c.append(usize, &upper, site);
    }
    _ = lower.pop();
    _ = upper.pop();
    for (upper.items) |site| c.append(usize, &lower, site);
    var smallest: usize = 0;
    for (lower.items[1..], 1..) |site, i| if (site < lower.items[smallest]) {
        smallest = i;
    };
    const out = c.alloc(usize, lower.items.len);
    for (out, 0..) |*site, i| site.* = lower.items[(smallest + i) % lower.items.len];
    return out;
}
const Circle = struct { count: usize = 0, sites: [3]usize = .{ 0, 0, 0 } };
fn contains(circle: Circle, points: []const c.Point, site: usize) bool {
    if (circle.count == 0) return false;
    if (circle.count == 1) return points[site].x == points[circle.sites[0]].x and points[site].y == points[circle.sites[0]].y;
    if (circle.count == 2) return c.dot(points[site], points[circle.sites[0]], points[circle.sites[1]]) <= 0;
    return c.incircle(points[circle.sites[0]], points[circle.sites[1]], points[circle.sites[2]], points[site]) >= 0;
}
fn triple(points: []const c.Point, a: usize, b: usize, q: usize) Circle {
    return .{ .count = 3, .sites = if (c.orient(points[a], points[b], points[q]) > 0) .{ a, b, q } else .{ a, q, b } };
}
fn enclosing(points: []const c.Point, hull: []const usize) Circle {
    var out: Circle = .{};
    for (hull, 0..) |site, i| if (!contains(out, points, site)) {
        out = .{ .count = 1, .sites = .{ site, 0, 0 } };
        for (hull[0..i], 0..) |other, j| if (!contains(out, points, other)) {
            out = .{ .count = 2, .sites = .{ site, other, 0 } };
            for (hull[0..j]) |third| if (!contains(out, points, third)) {
                out = triple(points, site, other, third);
            };
        };
    };
    return out;
}
fn onCircle(circle: Circle, points: []const c.Point, site: usize) bool {
    if (circle.count == 2) return c.dot(points[site], points[circle.sites[0]], points[circle.sites[1]]) == 0;
    if (circle.count == 3) return c.incircle(points[circle.sites[0]], points[circle.sites[1]], points[circle.sites[2]],
         points[site]) == 0;
    return contains(circle, points, site);
}
fn routeLength(points: []const c.Point, route: []const usize) f64 {
    var out: f64 = 0;
    for (1..route.len) |i| out += @sqrt(c.f(c.d2(points[route[i - 1]], points[route[i]])));
    return out;
}
fn dual(edge: proximity.Edge, points: []const c.Point) []const u8 {
    if (edge.left != null and edge.right != null) return c.fmt("segment {d} {d}", .{ edge.left.? + 1, edge.right.? + 1 });
    const left = edge.left != null;
    const normal = c.outward(points[if (left) edge.a else edge.b], points[if (left) edge.b else edge.a]);
    return c.fmt("ray {d} {d} {d}", .{ (if (left) edge.left.? else edge.right.?) + 1, normal.x, normal.y });
}
fn optionalMatrix(size: usize) [][]?usize {
    const out = c.alloc([]?usize, size);
    for (out) |*row| {
        row.* = c.alloc(?usize, size);
        @memset(row.*, null);
    }
    return out;
}
fn lessIndex(_: void, a: usize, b: usize) bool {
    return a < b;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const point_lines = try c.readLines(init.io, "input/points.txt");
    var point_list: std.ArrayList(c.Point) = .empty;
    var rejected: c.Lines = .{};
    for (point_lines, 1..) |line, line_number| {
        if (line.len == 0 or line[0] == '#') continue;
        const fields = c.words(line);
        if (fields.len != 2 or !integerWord(fields[0]) or !integerWord(fields[1])) {
            rejected.add("reject {d} format", .{line_number});
            continue;
        }
        const x = c.number(fields[0]);
        const y = c.number(fields[1]);
        if (x < 0 or x > 1000 or y < 0 or y > 1000) {
            rejected.add("reject {d} range", .{line_number});
            continue;
        }
        var duplicate: ?usize = null;
        for (point_list.items, 0..) |point, i| if (point.x == x and point.y == y) {
            duplicate = i;
        };
        if (duplicate) |site| {
            rejected.add("reject {d} duplicate {d}", .{ line_number, site + 1 });
            continue;
        }
        c.append(c.Point, &point_list, .{ .x = x, .y = y });
    }
    const points: []const c.Point = point_list.items;
    const n = points.len;
    var width: usize = 61;
    var height: usize = 31;
    var layers: []const []const u8 = &.{ "edges", "hull", "sites" };
    var requested: []const []const u8 = &.{"summary"};
    var alphas: std.ArrayList(i64) = .empty;
    var queries: std.ArrayList([]const u8) = .empty;
    for (try c.readLines(init.io, "input/params.txt")) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const fields = c.words(line);
        if (c.eq(fields[0], "plot")) {
            width = c.u(c.number(fields[1]));
            height = c.u(c.number(fields[2]));
        } else if (c.eq(fields[0], "plot_layers")) layers = fields[1..] else if (c.eq(fields[0], "sections")) requested = fields[1..] else if (c.eq(fields[0],
             "alpha")) {
            for (fields[1..]) |field| c.append(i64, &alphas, c.number(field));
        } else c.append([]const u8, &queries, line[6..]);
    }
    var triangulation = triangulation_module.initialize(points);
    const initial = triangulation.triangles()[0];
    const insertions = c.alloc(triangulation_module.Insertion, n - 3);
    for (3..n) |site| insertions[site - 3] = triangulation.insert(points, site);
    const triangles = triangulation.triangles();
    const count = triangles.len;
    const triangle_id = optionalMatrix(n);
    const edge_id = optionalMatrix(n);
    for (triangles, 0..) |triangle, t| for (0..3) |k| {
        triangle_id[triangle[k]][triangle[(k + 1) % 3]] = t;
    };
    var edge_list: std.ArrayList(proximity.Edge) = .empty;
    const neighbor_lists = c.alloc(std.ArrayList(usize), n);
    @memset(neighbor_lists, .empty);
    for (0..n) |a| for (a + 1..n) |b| {
        if (triangulation.third(a, b) == null and triangulation.third(b, a) == null) continue;
        const index = edge_list.items.len;
        edge_id[a][b] = index;
        edge_id[b][a] = index;
        c.append(proximity.Edge, &edge_list, .{ .a = a, .b = b, .left = triangle_id[a][b], .right = triangle_id[b][a],
             .length2 = c.d2(points[a], points[b]) });
        c.append(usize, &neighbor_lists[a], b);
        c.append(usize, &neighbor_lists[b], a);
    };
    const edges = edge_list.items;
    const neighbors = c.alloc([]const usize, n);
    for (neighbor_lists, neighbors) |values, *list| {
        std.mem.sort(usize, values.items, {}, lessIndex);
        list.* = values.items;
    }
    const next = c.alloc(?usize, n);
    const previous = c.alloc(?usize, n);
    @memset(next, null);
    @memset(previous, null);
    for (triangulation.hullEdges()) |edge| {
        next[edge.a] = edge.b;
        previous[edge.b] = edge.a;
    }
    var start: usize = 0;
    while (next[start] == null) start += 1;
    var hull_list: std.ArrayList(usize) = .empty;
    var current = start;
    while (true) {
        c.append(usize, &hull_list, current);
        current = next[current].?;
        if (current == start) break;
    }
    const hull = hull_list.items;
    const ordered_neighbors = c.alloc([]const usize, n);
    for (0..n) |s| ordered_neighbors[s] = voronoi.neighborOrder(triangulation, s, neighbors[s], next[s]);
    const vertices = c.alloc(c.Center, count);
    const radii = c.vector(count);
    const minimum_angles = c.vector(count);
    const maximum_angles = c.vector(count);
    const positions = c.alloc([]const u8, count);
    const kinds = c.alloc([]const u8, count);
    const areas = c.alloc(i64, count);
    var acute: usize = 0;
    var right: usize = 0;
    var obtuse: usize = 0;
    var angle_bins = [_]usize{0} ** 6;
    for (triangles, 0..) |triangle, t| {
        const a = points[triangle[0]];
        const b = points[triangle[1]];
        const q = points[triangle[2]];
        areas[t] = c.orient(a, b, q);
        const products = [_]i64{ c.dot(a, b, q), c.dot(b, q, a), c.dot(q, a, b) };
        var zero = false;
        var negative = false;
        for (products) |value| {
            zero = zero or value == 0;
            negative = negative or value < 0;
        }
        kinds[t] = if (zero) "right" else if (negative) "obtuse" else "acute";
        acute += @intFromBool(c.eq(kinds[t], "acute"));
        right += @intFromBool(c.eq(kinds[t], "right"));
        obtuse += @intFromBool(c.eq(kinds[t], "obtuse"));
        minimum_angles[t] = std.math.inf(f64);
        maximum_angles[t] = 0;
        for (products) |value| {
            const angle = std.math.atan2(c.f(areas[t]), c.f(value)) * 180 / std.math.pi;
            minimum_angles[t] = @min(minimum_angles[t], angle);
            maximum_angles[t] = @max(maximum_angles[t], angle);
        }
        angle_bins[@as(usize, @intFromFloat(@floor(minimum_angles[t] / 10)))] += 1;
        vertices[t] = c.center(a, b, q);
        radii[t] = voronoi.radius2(a, b, q);
        positions[t] = voronoi.position(vertices[t], points, hull);
    }
    const cell_vertices = c.alloc([]const usize, n);
    const cell_areas = c.vector(n);
    const clips = c.vector(n);
    var total_area: f64 = 0;
    var clip_total: f64 = 0;
    var largest: ?usize = null;
    for (0..n) |s| {
        var sequence: std.ArrayList(usize) = .empty;
        for (ordered_neighbors[s]) |neighbor| if (triangle_id[s][neighbor]) |id| c.append(usize, &sequence, id);
        cell_vertices[s] = sequence.items;
        if (next[s] == null) {
            cell_areas[s] = voronoi.cellArea(points[s], vertices, sequence.items);
            total_area += cell_areas[s];
            if (largest == null or cell_areas[s] > cell_areas[largest.?]) largest = s;
        }
        clips[s] = voronoi.clippedArea(points, s, ordered_neighbors[s]);
        clip_total += clips[s];
    }
    const nn = proximity.nearest(points, neighbors);
    var nn_sets = proximity.Disjoint.init(n);
    var mutual: usize = 0;
    for (0..n) |s| {
        _ = nn_sets.join(s, nn[s]);
        mutual += @intFromBool(s < nn[s] and nn[nn[s]] == s);
    }
    const component_ids = c.alloc(?usize, n);
    @memset(component_ids, null);
    const component = c.alloc(usize, n);
    var component_lists: std.ArrayList(std.ArrayList(usize)) = .empty;
    for (0..n) |s| {
        const root = nn_sets.find(s);
        if (component_ids[root] == null) {
            component_ids[root] = component_lists.items.len;
            c.append(std.ArrayList(usize), &component_lists, .empty);
        }
        component[s] = component_ids[root].?;
        c.append(usize, &component_lists.items[component[s]], s);
    }
    const components = component_lists.items;
    const mst = proximity.kruskal(edges, n);
    var mst_length: f64 = 0;
    for (mst) |index| mst_length += @sqrt(c.f(edges[index].length2));
    var gg: usize = 0;
    var rng: usize = 0;
    const gg_degree = c.alloc(usize, n);
    const rng_degree = c.alloc(usize, n);
    const mst_degree = c.alloc(usize, n);
    @memset(gg_degree, 0);
    @memset(rng_degree, 0);
    @memset(mst_degree, 0);
    for (edges) |*edge| {
        edge.gabriel = proximity.gabriel(points, triangulation, edge.a, edge.b);
        edge.rng = proximity.relativeNeighborhood(points, edge.a, edge.b);
        gg += @intFromBool(edge.gabriel);
        rng += @intFromBool(edge.rng);
        for ([_]usize{ edge.a, edge.b }) |s| {
            gg_degree[s] += @intFromBool(edge.gabriel);
            rng_degree[s] += @intFromBool(edge.rng);
            mst_degree[s] += @intFromBool(edge.mst);
        }
    }
    var empty: ?usize = null;
    var candidates: usize = 0;
    for (positions, 0..) |value, t| if (c.eq(value, "inside")) {
        candidates += 1;
        if (empty == null or radii[t] > radii[empty.?]) empty = t;
    };
    var diameter: c.Pair = .{ .a = 0, .b = 1 };
    var diameter2 = c.d2(points[0], points[1]);
    for (0..n - 1) |a| for (a + 1..n) |b| {
        if (c.d2(points[a], points[b]) > diameter2) {
            diameter = .{ .a = a, .b = b };
            diameter2 = c.d2(points[a], points[b]);
        }
    };
    var width_value = std.math.inf(f64);
    var width_edge: usize = 0;
    for (hull, 0..) |site, k| {
        var maximum: i64 = 0;
        for (hull) |s| maximum = @max(maximum, c.orient(points[site], points[hull[(k + 1) % hull.len]], points[s]));
        const value = c.f(maximum) / @sqrt(c.f(c.d2(points[site], points[hull[(k + 1) % hull.len]])));
        if (value < width_value) {
            width_value = value;
            width_edge = k;
        }
    }
    const enclosing_circle = enclosing(points, hull);
    var enclosing_list: std.ArrayList(usize) = .empty;
    for (0..n) |s| if (onCircle(enclosing_circle, points, s)) c.append(usize, &enclosing_list, s);
    const enclosing_sites = enclosing_list.items;
    var diameter_support: ?c.Pair = null;
    for (0..enclosing_sites.len - 1) |a| for (a + 1..enclosing_sites.len) |b| {
        var all = true;
        for (enclosing_sites) |s| all = all and c.dot(points[s], points[enclosing_sites[a]], points[enclosing_sites[b]]) == 0;
        if (all and diameter_support == null) diameter_support = .{ .a = enclosing_sites[a], .b = enclosing_sites[b] };
    };
    var enclosing_center: c.Center = undefined;
    var enclosing_radius2: f64 = undefined;
    if (diameter_support) |support| {
        const a = points[support.a];
        const b = points[support.b];
        enclosing_center = .{ .x = a.x + b.x, .y = a.y + b.y, .d = 2 };
        enclosing_radius2 = c.f(c.d2(a, b)) / 4;
    } else {
        const support = triple(points, enclosing_sites[0], enclosing_sites[1], enclosing_sites[2]);
        const a = points[support.sites[0]];
        const b = points[support.sites[1]];
        const q = points[support.sites[2]];
        enclosing_center = c.center(a, b, q);
        enclosing_radius2 = voronoi.radius2(a, b, q);
    }
    var convex_layers: std.ArrayList([]const usize) = .empty;
    const all_sites = c.alloc(usize, n);
    for (all_sites, 0..) |*site, s| site.* = s;
    var remaining: []const usize = all_sites;
    const depth = c.alloc(usize, n);
    @memset(depth, 0);
    while (remaining.len > 0) {
        const layer = hullOf(points, remaining);
        c.append([]const usize, &convex_layers, layer);
        for (layer) |s| depth[s] = convex_layers.items.len;
        var rest: std.ArrayList(usize) = .empty;
        for (remaining) |s| if (depth[s] == 0) c.append(usize, &rest, s);
        remaining = rest.items;
    }
    const paths = c.alloc(proximity.Paths, n);
    for (0..n) |s| paths[s] = proximity.dijkstra(points, neighbors, s);
    var stretch_sum: f64 = 0;
    var max_stretch: f64 = -1;
    var stretch_pair: c.Pair = .{ .a = 0, .b = 1 };
    for (0..n - 1) |a| for (a + 1..n) |b| {
        const value = paths[a].distance[b] / @sqrt(c.f(c.d2(points[a], points[b])));
        stretch_sum += value;
        if (value > max_stretch) {
            max_stretch = value;
            stretch_pair = .{ .a = a, .b = b };
        }
    };
    const sections = c.alloc(c.Lines, 24);
    @memset(sections, .{});
    var out = &sections[0];
    out.add("lines {d}", .{point_lines.len});
    out.add("accepted {d}", .{n});
    out.add("rejected {d}", .{rejected.data.items.len});
    out.extend(rejected);
    out = &sections[1];
    var flips: usize = 0;
    var outside: usize = 0;
    var maximum_insertion: ?usize = null;
    for (insertions, 0..) |insertion, i| {
        flips += insertion.flips;
        outside += @intFromBool(!insertion.inside);
        if (maximum_insertion == null or insertion.flips > insertions[maximum_insertion.?].flips) maximum_insertion = i;
    }
    out.add("sites {d}", .{n});
    out.add("triangles {d}", .{count});
    out.add("edges {d}", .{edges.len});
    out.add("hull_vertices {d}", .{hull.len});
    out.add("interior_sites {d}", .{n - hull.len});
    out.add("euler {d}", .{c.n(n) - c.n(edges.len) + c.n(count)});
    out.add("flips {d}", .{flips});
    out.add("outside_insertions {d}", .{outside});
    if (maximum_insertion) |i| out.add("max_flips {d} {d}", .{ insertions[i].site + 1, insertions[i].flips }) else out.add("max_flips none",
         .{});
    out.add("acute {d}", .{acute});
    out.add("right {d}", .{right});
    out.add("obtuse {d}", .{obtuse});
    out = &sections[2];
    out.add("init {s}", .{triangleText(initial)});
    for (insertions) |insertion| {
        var line: c.Text = .{};
        line.add("insert {d} ", .{insertion.site + 1});
        if (insertion.inside) line.add("inside {s}", .{triangleText(insertion.containing)}) else line.add("outside {d}",
             .{insertion.visible});
        line.add(" flips {d} triangles {d} hull {d}", .{ insertion.flips, insertion.triangles, insertion.hull });
        out.add("{s}", .{line.value()});
    }
    out = &sections[3];
    for (triangles, 0..) |triangle, t| out.add("tri {d} {s} area2 {d} {s} adj {s} {s} {s}", .{ t + 1,
         triangleText(triangle), areas[t], kinds[t], optionalId(triangle_id[triangle[2]][triangle[1]]),
         optionalId(triangle_id[triangle[0]][triangle[2]]), optionalId(triangle_id[triangle[1]][triangle[0]]) });
    out = &sections[4];
    for (edges) |edge| out.add("edge {d} {d} {s} len2 {d} left {s} right {s}", .{ edge.a + 1, edge.b + 1,
         if (edge.left != null and edge.right != null) "inner" else "hull", edge.length2, optionalId(edge.left),
         optionalId(edge.right) });
    out = &sections[5];
    var perimeter: f64 = 0;
    var hull_area: i64 = 0;
    for (hull, 0..) |site, k| {
        const a = points[site];
        const b = points[hull[(k + 1) % hull.len]];
        perimeter += @sqrt(c.f(c.d2(a, b)));
        hull_area += a.x * b.y - b.x * a.y;
    }
    out.add("hull_vertices {d}", .{hull.len});
    out.add("order {s}", .{ids(hull)});
    out.add("perimeter {s}", .{real(perimeter)});
    out.add("area2 {d}", .{hull_area});
    out = &sections[6];
    out.add("layers {d}", .{convex_layers.items.len});
    for (convex_layers.items, 1..) |layer, k| out.add("layer {d} size {d} sites {s}", .{ k, layer.len, ids(layer) });
    out = &sections[7];
    var min_triangle: usize = 0;
    var max_triangle: usize = 0;
    var minimum_sum: f64 = 0;
    for (0..count) |t| {
        if (minimum_angles[t] < minimum_angles[min_triangle]) min_triangle = t;
        if (maximum_angles[t] > maximum_angles[max_triangle]) max_triangle = t;
        minimum_sum += minimum_angles[t];
    }
    out.add("min_angle {s} tri {d}", .{ real(minimum_angles[min_triangle]), min_triangle + 1 });
    out.add("max_angle {s} tri {d}", .{ real(maximum_angles[max_triangle]), max_triangle + 1 });
    out.add("mean_min_angle {s}", .{real(minimum_sum / c.f(count))});
    for (angle_bins, 0..) |value, bin| out.add("bin {d} {d} {d}", .{ bin * 10, (bin + 1) * 10, value });
    out = &sections[8];
    for ([_][]const u8{ "inside", "on", "outside" }) |kind| {
        var total: usize = 0;
        for (positions) |value| total += @intFromBool(c.eq(value, kind));
        out.add("{s} {d}", .{ kind, total });
    }
    for (vertices, 0..) |vertex, t| out.add("v {d} {s} {s} r {s} {s}", .{ t + 1, c.fraction(vertex.x,
         vertex.d), c.fraction(vertex.y, vertex.d), real(@sqrt(radii[t])), positions[t] });
    out = &sections[9];
    out.add("segments {d}", .{edges.len - hull.len});
    out.add("rays {d}", .{hull.len});
    for (edges) |edge| out.add("ve {d} {d} {s}", .{ edge.a + 1, edge.b + 1, dual(edge, points) });
    out = &sections[10];
    out.add("bounded {d}", .{n - hull.len});
    out.add("unbounded {d}", .{hull.len});
    out.add("total_area {s}", .{real(total_area)});
    out.add("clip_total {s}", .{real(clip_total)});
    if (largest) |s| out.add("largest {d} area {s}", .{ s + 1, real(cell_areas[s]) }) else out.add("largest none", .{});
    for (0..n) |s| {
        if (next[s]) |next_| {
            const incoming = c.outward(points[s], points[next_]);
            const outgoing = c.outward(points[previous[s].?], points[s]);
            out.add("cell {d} unbounded {d} clip {s} from {d} {d} vertices {s} to {d} {d}", .{ s + 1,
                 cell_vertices[s].len, real(clips[s]), incoming.x, incoming.y, ids(cell_vertices[s]),
                 outgoing.x, outgoing.y });
        } else out.add("cell {d} bounded {d} area {s} clip {s} vertices {s}", .{ s + 1, cell_vertices[s].len,
             real(cell_areas[s]), real(clips[s]), ids(cell_vertices[s]) });
    }
    out = &sections[11];
    var closest: usize = 0;
    for (edges[1..], 1..) |edge, i| if (edge.length2 < edges[closest].length2) {
        closest = i;
    };
    out.add("mutual_pairs {d}", .{mutual});
    out.add("closest_pair {d} {d} d2 {d}", .{ edges[closest].a + 1, edges[closest].b + 1, edges[closest].length2 });
    for (0..n) |s| out.add("nn {d} {d} d2 {d} {s}", .{ s + 1, nn[s] + 1, c.d2(points[s], points[nn[s]]),
         if (nn[nn[s]] == s) "mutual" else "-" });
    out = &sections[12];
    out.add("components {d}", .{components.len});
    for (components, 1..) |component_, i| {
        var pair: c.Pair = .{ .a = 0, .b = 0 };
        for (component_.items) |s| if (s < nn[s] and nn[nn[s]] == s) {
            pair = .{ .a = s, .b = nn[s] };
        };
        out.add("component {d} size {d} pair {d} {d} sites {s}", .{ i, component_.items.len, pair.a + 1,
             pair.b + 1, ids(component_.items) });
    }
    out = &sections[13];
    const longest = edges[mst[mst.len - 1]];
    out.add("edges {d}", .{mst.len});
    out.add("total_length {s}", .{real(mst_length)});
    out.add("longest {d} {d} len2 {d}", .{ longest.a + 1, longest.b + 1, longest.length2 });
    for (mst) |index| {
        const edge = edges[index];
        out.add("mst {d} {d} len2 {d}", .{ edge.a + 1, edge.b + 1, edge.length2 });
    }
    out = &sections[14];
    out.add("delaunay {d}", .{edges.len});
    out.add("gabriel {d}", .{gg});
    out.add("rng {d}", .{rng});
    out.add("mst {d}", .{mst.len});
    out.add("nn {d}", .{n - mutual});
    for (edges) |edge| if (edge.rng and !edge.mst) out.add("rng_extra {d} {d} len2 {d}", .{ edge.a + 1,
         edge.b + 1, edge.length2 });
    out = &sections[15];
    const degree_counts = c.alloc(usize, n);
    @memset(degree_counts, 0);
    var min_degree = neighbors[0].len;
    var max_degree = min_degree;
    for (neighbors) |values| {
        degree_counts[values.len] += 1;
        min_degree = @min(min_degree, values.len);
        max_degree = @max(max_degree, values.len);
    }
    out.add("min {d}", .{min_degree});
    out.add("max {d}", .{max_degree});
    for (min_degree..max_degree + 1) |degree| if (degree_counts[degree] > 0) out.add("degree {d} count {d}",
         .{ degree, degree_counts[degree] });
    out = &sections[16];
    out.add("candidates {d}", .{candidates});
    if (empty) |t| {
        out.add("vertex {d}", .{t + 1});
        out.add("center {s} {s}", .{ c.fraction(vertices[t].x, vertices[t].d), c.fraction(vertices[t].y, vertices[t].d) });
        out.add("radius {s}", .{real(@sqrt(radii[t]))});
        out.add("sites {s}", .{triangleText(triangles[t])});
    } else out.add("none", .{});
    out = &sections[17];
    out.add("diameter {d} {d} d2 {d}", .{ diameter.a + 1, diameter.b + 1, diameter2 });
    out.add("width {s} edge {d} {d}", .{ real(width_value), hull[width_edge] + 1, hull[(width_edge + 1) % hull.len] + 1 });
    out.add("enclosing_center {s} {s}", .{ c.fraction(enclosing_center.x, enclosing_center.d), c.fraction(enclosing_center.y,
         enclosing_center.d) });
    out.add("enclosing_radius {s}", .{real(@sqrt(enclosing_radius2))});
    out.add("enclosing_sites {s}", .{ids(enclosing_sites)});
    out = &sections[18];
    out.add("pairs {d}", .{n * (n - 1) / 2});
    out.add("max_stretch {s} pair {d} {d} length {s} distance {s}", .{ real(max_stretch), stretch_pair.a + 1,
         stretch_pair.b + 1, real(paths[stretch_pair.a].distance[stretch_pair.b]), real(@sqrt(c.f(c.d2(points[stretch_pair.a],
         points[stretch_pair.b])))) });
    out.add("mean_stretch {s}", .{real(stretch_sum / c.f(n * (n - 1) / 2))});
    out = &sections[19];
    for (alphas.items) |alpha| {
        const selected = c.alloc(bool, count);
        const active = c.alloc(bool, n);
        @memset(selected, false);
        @memset(active, false);
        var faces: usize = 0;
        var selected_edges: usize = 0;
        var boundary: usize = 0;
        var dangling: usize = 0;
        var components_count = n;
        var area: i64 = 0;
        for (radii, 0..) |radius, t| if (radius <= c.f(alpha)) {
            selected[t] = true;
            faces += 1;
            area += areas[t];
        };
        var sets = proximity.Disjoint.init(n);
        for (edges) |edge| {
            const adjacent = @as(usize, @intFromBool(if (edge.left) |t| selected[t] else false)) + @as(usize,
                 @intFromBool(if (edge.right) |t| selected[t] else false));
            if (adjacent == 0 and !(edge.gabriel and edge.length2 <= 4 * alpha)) continue;
            selected_edges += 1;
            boundary += @intFromBool(adjacent == 1);
            dangling += @intFromBool(adjacent == 0);
            active[edge.a] = true;
            active[edge.b] = true;
            components_count -= @intFromBool(sets.join(edge.a, edge.b));
        }
        var isolated: usize = 0;
        for (active) |value| isolated += @intFromBool(!value);
        out.add("alpha {d} triangles {d} edges {d} boundary {d} dangling {d} isolated {d} components {d} holes {d} area2 {d}",
             .{ alpha, faces, selected_edges, boundary, dangling, isolated, components_count, c.n(components_count) - (c.n(n) - c.n(selected_edges) + c.n(faces)),
             area });
    }
    out = &sections[20];
    for (points, 0..) |point, s| out.add("site {d} {d} {d} {s} dt {d} gg {d} rng {d} mst {d} nn {d} comp {d} depth {d}",
         .{ s + 1, point.x, point.y, if (next[s] != null) "hull" else "inner", neighbors[s].len, gg_degree[s],
         rng_degree[s], mst_degree[s], nn[s] + 1, component[s] + 1, depth[s] });
    out = &sections[21];
    for (queries.items) |query| {
        const fields = c.words(query);
        const kind = fields[0];
        var line: c.Text = .{};
        line.add("{s} ", .{query});
        if (c.eq(kind, "locate") or c.eq(kind, "walk") or c.eq(kind, "natural")) {
            const q: c.Point = .{ .x = c.number(fields[1]), .y = c.number(fields[2]) };
            if (c.eq(kind, "locate")) {
                var place: []const u8 = "outside";
                var found = false;
                for (points, 0..) |point, s| if (c.d2(point, q) == 0) {
                    place = c.fmt("vertex {d}", .{s + 1});
                    found = true;
                    break;
                };
                if (!found) for (edges) |edge| {
                    if (c.orient(points[edge.a], points[edge.b], q) == 0 and c.dot(q, points[edge.a], points[edge.b]) < 0) {
                        place = c.fmt("edge {d} {d}", .{ edge.a + 1, edge.b + 1 });
                        found = true;
                        break;
                    }
                };
                if (!found) for (triangles) |triangle| {
                    if (c.orient(points[triangle[0]], points[triangle[1]], q) > 0 and c.orient(points[triangle[1]],
                         points[triangle[2]], q) > 0 and c.orient(points[triangle[2]], points[triangle[0]],
                         q) > 0) {
                        place = c.fmt("triangle {s}", .{triangleText(triangle)});
                        break;
                    }
                };
                var nearest_: usize = 0;
                for (points[1..], 1..) |point, s| if (c.d2(point, q) < c.d2(points[nearest_], q)) {
                    nearest_ = s;
                };
                line.add("{s} nearest {d} d2 {d}", .{ place, nearest_ + 1, c.d2(points[nearest_], q) });
            } else if (c.eq(kind, "walk")) {
                const walk = triangulation.walk(points, q);
                line.add("steps {d} ", .{walk.path.len - 1});
                if (walk.outside) line.add("outside {d} {d}", .{ walk.edge.a + 1, walk.edge.b + 1 }) else line.add("triangle {d}",
                     .{walk.path[walk.path.len - 1] + 1});
                line.add(" path {s}", .{ids(walk.path)});
            } else {
                var triangle_count: usize = 0;
                const present = c.alloc(bool, n);
                @memset(present, false);
                for (triangles) |triangle| if (c.incircle(points[triangle[0]], points[triangle[1]], points[triangle[2]], q) > 0) {
                    triangle_count += 1;
                    for (triangle) |s| present[s] = true;
                };
                var sites: std.ArrayList(usize) = .empty;
                for (present, 0..) |value, s| if (value) c.append(usize, &sites, s);
                line.add("triangles {d} sites {s}", .{ triangle_count, if (sites.items.len == 0) "-" else ids(sites.items) });
            }
        } else {
            const a_ = c.number(fields[1]) - 1;
            const b_ = if (c.eq(kind, "neighbors")) a_ else c.number(fields[2]) - 1;
            if (a_ < 0 or a_ >= c.n(n) or b_ < 0 or b_ >= c.n(n)) line.add("error unknown_site", .{}) else {
                const a = c.u(a_);
                const b = c.u(b_);
                if (c.eq(kind, "neighbors")) line.add("degree {d} sites {s}", .{ neighbors[a].len,
                     ids(ordered_neighbors[a]) }) else if (c.eq(kind, "route")) {
                    const route = proximity.greedyRoute(points, neighbors, a, b);
                    line.add("hops {d} length {s} path {s}", .{ route.len - 1, real(routeLength(points, route)), ids(route) });
                } else if (c.eq(kind, "path")) {
                    var route: std.ArrayList(usize) = .empty;
                    var cursor: ?usize = b;
                    while (cursor) |site| {
                        c.append(usize, &route, site);
                        if (site == a) break;
                        cursor = paths[a].previous[site];
                    }
                    std.mem.reverse(usize, route.items);
                    line.add("length {s} stretch {s} hops {d} sites {s}", .{ real(paths[a].distance[b]),
                         if (a == b) "-" else real(paths[a].distance[b] / @sqrt(c.f(c.d2(points[a],
                         points[b])))), route.items.len - 1, ids(route.items) });
                } else if (a == b) line.add("error same_site", .{}) else if (edge_id[a][b]) |index| {
                    const edge = edges[index];
                    line.add("delaunay len2 {d} gabriel {s} rng {s} mst {s} dual {s}", .{ edge.length2,
                         if (edge.gabriel) "yes" else "no", if (edge.rng) "yes" else "no", if (edge.mst) "yes" else "no",
                         dual(edge, points) });
                } else {
                    var crossings: std.ArrayList(c.Pair) = .empty;
                    for (edges) |edge| if (c.orient(points[a], points[b], points[edge.a]) * c.orient(points[a],
                         points[b], points[edge.b]) < 0 and c.orient(points[edge.a], points[edge.b],
                         points[a]) * c.orient(points[edge.a], points[edge.b], points[b]) < 0) {
                        c.append(c.Pair, &crossings, .{ .a = edge.a, .b = edge.b });
                    };
                    line.add("missing crossings {d}", .{crossings.items.len});
                    for (crossings.items) |edge| line.add(" {d}-{d}", .{ edge.a + 1, edge.b + 1 });
                }
            }
        }
        out.add("{s}", .{line.value()});
    }
    const delaunay = plot.canvas(width, height);
    for (layers) |layer| {
        if (c.eq(layer, "edges")) {
            for (edges) |edge| plot.drawLine(delaunay, plot.mapPoint(points[edge.a], width, height),
                 plot.mapPoint(points[edge.b], width, height), '.');
        } else if (c.eq(layer, "mst")) {
            for (mst) |index| {
                const edge = edges[index];
                plot.drawLine(delaunay, plot.mapPoint(points[edge.a], width, height), plot.mapPoint(points[edge.b],
                     width, height), '*');
            }
        } else if (c.eq(layer, "hull")) {
            for (hull, 0..) |site, k| plot.drawLine(delaunay, plot.mapPoint(points[site], width, height),
                 plot.mapPoint(points[hull[(k + 1) % hull.len]], width, height), '#');
        } else if (c.eq(layer, "sites")) {
            for (points) |point| {
                const cell = plot.mapPoint(point, width, height);
                delaunay[cell.b][cell.a] = 'o';
            }
        } else if (c.eq(layer, "circle")) {
            if (empty) |t| {
                const cell = plot.mapCenter(vertices[t], width, height);
                delaunay[cell.b][cell.a] = '@';
            }
        }
    }
    sections[22] = plot.framed(delaunay);
    sections[23] = plot.framed(plot.voronoiPlot(points, width, height));
    var files = [_]c.Text{.{}} ** 4;
    for (requested) |name| {
        var section: usize = 0;
        for (section_names, 0..) |value, i| if (c.eq(value, name)) {
            section = i;
            break;
        };
        const target: usize = if (section <= 7) 0 else if (section <= 10) 1 else if (section >= 22) 3 else 2;
        files[target].add("[{s}]\n", .{name});
        for (sections[section].data.items) |value| files[target].add("{s}\n", .{value});
    }
    const paths_ = [_][]const u8{ "output/triangulation.txt", "output/voronoi.txt", "output/derived.txt", "output/plot.txt" };
    for (paths_, files) |path, text| try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = text.value() });
}
