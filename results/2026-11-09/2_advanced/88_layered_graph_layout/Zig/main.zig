const std = @import("std");
const g = @import("graph_io.zig");
const a = @import("acyclic_layering.zig");
const c = @import("crossing.zig");
const coordinates = @import("coordinates.zig");
const drawing = @import("canvas.zig");
fn visit(graph: *const g.Graph, v: usize, seen: []bool, orders: []std.ArrayList(usize)) void {
    if (seen[v]) return; seen[v] = true; g.append(usize, &orders[graph.vertices.items[v].layer], v);
    for (graph.segments.items) |s| if (s.upper == v) visit(graph, s.lower, seen, orders);
}
fn initialOrders(graph: *g.Graph) c.Orders {
    const n = graph.nodes;
    for (graph.edges.items, 0..) |*e, ei| {
        if (e.transitive) continue; var chain: std.ArrayList(usize) = .empty; g.append(usize, &chain, e.a);
        for (graph.vertices.items[e.a].layer + 1 .. graph.vertices.items[e.b].layer) |layer| { const v = graph.vertices.items.len; g.append(g.Vertex, &graph.vertices, .{ .name = g.fmt("d{d}", .{v - n + 1}), .label = "", .layer = layer, .dummy = true }); g.append(usize, &chain, v); }
        g.append(usize, &chain, e.b); e.chain = chain.items; for (1..chain.items.len) |i| g.append(g.Segment, &graph.segments, .{ .upper = chain.items[i - 1], .lower = chain.items[i], .edge = ei });
    }
    var count: usize = 0; for (graph.vertices.items) |v| count = @max(count, v.layer + 1); const lists = g.alloc(std.ArrayList(usize), count); @memset(lists, .empty); const seen = g.zero(bool, graph.vertices.items.len, false);
    for (0..n) |v| visit(graph, v, seen, lists); const orders = g.alloc([]usize, count); for (lists, orders) |list, *row| row.* = list.items; return orders;
}
fn reorder(graph: *const g.Graph, orders: c.Orders, layer: usize, upper: bool) void {
    const pos = c.positions(orders, graph.vertices.items.len); const Key = struct { vertex: usize, previous: usize, numerator: i64, denominator: i64 }; var movable: std.ArrayList(Key) = .empty; var positions: std.ArrayList(usize) = .empty;
    for (orders[layer], 0..) |v, old| {
        const refs = c.neighbors(graph, v, upper); if (refs.len == 0) continue; const values = g.alloc(usize, refs.len); for (refs, values) |u, *p| p.* = pos[u]; var sum: i64 = 0; for (values) |p| sum += @intCast(p); var denominator: i64 = @intCast(values.len);
        if (g.eq(graph.settings.heuristic, "median")) { std.mem.sort(usize, values, {}, std.sort.asc(usize)); sum = @intCast(values[(values.len - 1) / 2] + values[values.len / 2]); denominator = 1; }
        g.append(Key, &movable, .{ .vertex = v, .previous = old, .numerator = sum, .denominator = denominator }); g.append(usize, &positions, old);
    }
    std.mem.sort(Key, movable.items, {}, struct { fn less(_: void, x: Key, y: Key) bool { const left = x.numerator * y.denominator; const right = y.numerator * x.denominator; return left < right or (left == right and x.previous < y.previous); } }.less);
    for (positions.items, movable.items) |p, key| orders[layer][p] = key.vertex;
}
fn exchanges(graph: *const g.Graph, orders: c.Orders) usize {
    var total: usize = 0;
    while (true) { var changed = false; for (orders) |row| { if (row.len < 2) continue; for (0..row.len - 1) |j| { const pos = c.positions(orders, graph.vertices.items.len); const v = row[j]; const w = row[j + 1]; if (c.cost(graph, v, w, pos) > c.cost(graph, w, v, pos)) { std.mem.swap(usize, &row[j], &row[j + 1]); total += 1; changed = true; } } } if (!changed) break; }
    return total;
}
const Reduction = struct { orders: c.Orders, initial: usize, swept: usize, run: usize, sweep: usize };
fn reduceCrossings(graph: *const g.Graph, initial: c.Orders, layout: *g.Text, csv: *g.Text) Reduction {
    var result = Reduction{ .orders = c.clone(initial), .initial = c.total(graph, initial), .swept = std.math.maxInt(usize), .run = 0, .sweep = 0 }; var random = graph.settings.seed;
    for (0..graph.settings.restarts + 1) |run| {
        const orders = c.clone(initial);
        if (run > 0) for (orders) |row| { var j = row.len; while (j > 1) { j -= 1; random = @mod(48271 * random, 2147483647); const k: usize = @intCast(@mod(random, @as(i64, @intCast(j + 1)))); std.mem.swap(usize, &row[j], &row[k]); } };
        var history: std.ArrayList(c.Orders) = .empty; g.append(c.Orders, &history, c.clone(orders)); var count = c.total(graph, orders); var best = count; var best_sweep: usize = 0; var best_order = c.clone(orders);
        layout.line("sweep {d} 0 initial crossings {d}", .{run, count}); csv.line("{s},{d},0,{d}", .{graph.name, run, count});
        var sweep: usize = 1;
        while (count != 0 and sweep <= graph.settings.sweeps) : (sweep += 1) {
            if (sweep >= 3 and c.same(history.items[sweep - 1], history.items[sweep - 3])) break;
            const old = c.positions(orders, graph.vertices.items.len); const downward = sweep % 2 == 1;
            for (1..orders.len) |step| reorder(graph, orders, if (downward) step else orders.len - 1 - step, downward);
            const pos = c.positions(orders, graph.vertices.items.len); var moved: usize = 0; for (old, pos) |before, after| moved += @intFromBool(before != after); const swaps = exchanges(graph, orders); count = c.total(graph, orders);
            layout.line("sweep {d} {d} {s} moved {d} swaps {d} crossings {d}", .{run, sweep, if (downward) "down" else "up", moved, swaps, count}); csv.line("{s},{d},{d},{d}", .{graph.name, run, sweep, count}); g.append(c.Orders, &history, c.clone(orders));
            if (count < best) { best = count; best_sweep = sweep; best_order = c.clone(orders); }
        }
        if (best < result.swept) { result.orders = best_order; result.swept = best; result.run = run; result.sweep = best_sweep; }
    }
    layout.line("best run {d} sweep {d} crossings {d}", .{result.run, result.sweep, result.swept});
    if (graph.settings.sifting) {
        var round: usize = 0; while (true) { round += 1; var moves: usize = 0;
            for (graph.vertices.items, 0..) |vertex, v| {
                const row = result.orders[vertex.layer]; var old: usize = 0; for (row, 0..) |u, j| if (u == v) { old = j; break; };
                const others = g.alloc(usize, row.len - 1); var j: usize = 0; for (row) |u| if (u != v) { others[j] = u; j += 1; };
                const costs = g.alloc(usize, row.len); var minimum = std.math.maxInt(usize);
                for (0..row.len) |p| { @memcpy(row[0..p], others[0..p]); row[p] = v; @memcpy(row[p + 1 ..], others[p..]); costs[p] = c.total(graph, result.orders); minimum = @min(minimum, costs[p]); }
                var chosen = old; if (costs[old] != minimum) for (costs, 0..) |cost, p| if (cost == minimum) { chosen = p; break; };
                @memcpy(row[0..chosen], others[0..chosen]); row[chosen] = v; @memcpy(row[chosen + 1 ..], others[chosen..]); moves += @intFromBool(chosen != old);
            }
            layout.line("sift {d} moves {d} crossings {d}", .{round, moves, c.total(graph, result.orders)}); if (moves == 0) break;
        }
    }
    return result;
}
fn analysis(graph: *const g.Graph, stats: *g.Text) void {
    const n = graph.nodes; const reach = g.zero(bool, n * n, false); const weak = g.zero(bool, n * n, false); const incoming = g.zero(usize, n, 0); const outgoing = g.zero(usize, n, 0);
    for (0..n) |v| { reach[v * n + v] = true; weak[v * n + v] = true; } for (graph.edges.items) |e| { reach[e.from * n + e.to] = true; weak[e.from * n + e.to] = true; weak[e.to * n + e.from] = true; incoming[e.to] += 1; outgoing[e.from] += 1; }
    for (0..n) |k| for (0..n) |i| for (0..n) |j| { reach[i * n + j] = reach[i * n + j] or (reach[i * n + k] and reach[k * n + j]); weak[i * n + j] = weak[i * n + j] or (weak[i * n + k] and weak[k * n + j]); };
    var sources: usize = 0; var sinks: usize = 0; var isolated: usize = 0; var components: usize = 0;
    for (0..n) |v| { sources += @intFromBool(incoming[v] == 0 and outgoing[v] > 0); sinks += @intFromBool(outgoing[v] == 0 and incoming[v] > 0); isolated += @intFromBool(incoming[v] == 0 and outgoing[v] == 0); var first = true; for (0..v) |u| if (weak[v * n + u]) { first = false; break; }; components += @intFromBool(first); }
    stats.line("nodes {d} edges {d} self_loops {d} duplicates {d}", .{n, graph.edges.items.len, graph.loops, graph.duplicates}); stats.line("sources {d} sinks {d} isolated {d} components {d}", .{sources, sinks, isolated, components});
    const reported = g.zero(bool, n, false); for (0..n) |v| { if (reported[v]) continue; var members: std.ArrayList(usize) = .empty; for (0..n) |u| if (reach[v * n + u] and reach[u * n + v]) { reported[u] = true; g.append(usize, &members, u); }; if (members.items.len > 1) { stats.put("scc", .{}); for (members.items) |u| stats.put(" {s}", .{graph.vertices.items[u].name}); stats.put("\n", .{}); } }
}
const Bus = struct { upper: bool, vertex: usize, lo: i64, hi: i64, segments: std.ArrayList(usize) = .empty };
const Geometry = struct { starts: []i64, thickness: []i64, gaps: []i64, tracks: []usize, main_size: i64, secondary_size: i64 };
fn geometry(graph: *g.Graph, orders: c.Orders, x: []const i64) Geometry {
    const layers = orders.len; const starts = g.zero(i64, layers, 0); const thickness = g.zero(i64, layers, 1); const gaps = g.zero(i64, layers - 1, 0); const tracks = g.zero(usize, layers - 1, 0);
    for (0..layers - 1) |layer| {
        const upper_count = g.zero(usize, x.len, 0); for (graph.segments.items) |s| if (graph.vertices.items[s.upper].layer == layer and x[s.upper] != x[s.lower]) { upper_count[s.upper] += 1; };
        var buses: std.ArrayList(Bus) = .empty;
        for (graph.segments.items, 0..) |s, si| {
            if (graph.vertices.items[s.upper].layer != layer or x[s.upper] == x[s.lower]) continue; const upper = upper_count[s.upper] >= 2; const vertex = if (upper) s.upper else s.lower; var existing: ?usize = null;
            for (buses.items, 0..) |bus, j| if (bus.upper == upper and bus.vertex == vertex) { existing = j; break; };
            const j = existing orelse blk: { g.append(Bus, &buses, .{ .upper = upper, .vertex = vertex, .lo = @min(x[s.upper], x[s.lower]), .hi = @max(x[s.upper], x[s.lower]) }); break :blk buses.items.len - 1; };
            const bus = &buses.items[j]; bus.lo = @min(bus.lo, @min(x[s.upper], x[s.lower])); bus.hi = @max(bus.hi, @max(x[s.upper], x[s.lower])); g.append(usize, &bus.segments, si);
        }
        std.mem.sort(Bus, buses.items, x, struct { fn less(coords: []const i64, first: Bus, second: Bus) bool { if (first.lo != second.lo) return first.lo < second.lo; if (first.hi != second.hi) return first.hi < second.hi; if (first.upper != second.upper) return first.upper; return coords[first.vertex] < coords[second.vertex]; } }.less);
        var ends: std.ArrayList(i64) = .empty;
        for (buses.items) |bus| { var choice: ?usize = null; for (ends.items, 0..) |end, j| if (end + 1 < bus.lo) { choice = j; break; }; const track = choice orelse blk: { g.append(i64, &ends, bus.hi); break :blk ends.items.len - 1; }; ends.items[track] = bus.hi; for (bus.segments.items) |si| graph.segments.items[si].track = @intCast(track + 1); }
        tracks[layer] = ends.items.len; gaps[layer] = @max(graph.settings.layer_gap, @as(i64, @intCast(ends.items.len)) + 2); const offset = @divFloor(gaps[layer] - 2 - @as(i64, @intCast(ends.items.len)), 2);
        for (graph.segments.items) |*s| if (graph.vertices.items[s.upper].layer == layer and s.track > 0) { s.track += offset; };
    }
    if (!graph.settings.vertical()) for (orders, 0..) |row, i| for (row) |v| { thickness[i] = @max(thickness[i], graph.vertices.items[v].width); };
    for (1..layers) |i| starts[i] = starts[i - 1] + thickness[i - 1] + gaps[i - 1]; var secondary: i64 = 0; for (graph.vertices.items, x) |v, coord| secondary = @max(secondary, coord + v.right + 1);
    return .{ .starts = starts, .thickness = thickness, .gaps = gaps, .tracks = tracks, .main_size = starts[layers - 1] + thickness[layers - 1], .secondary_size = secondary };
}
fn shortest(graph: *const g.Graph) []const usize {
    const path = graph.path orelse return &.{}; const parent = g.zero(?usize, graph.nodes, null); parent[path[0]] = path[0]; var queue: std.ArrayList(usize) = .empty; g.append(usize, &queue, path[0]); var at: usize = 0;
    while (at < queue.items.len) : (at += 1) { const v = queue.items[at]; for (0..graph.nodes) |u| { if (parent[u] != null) continue; var adjacent = false; for (graph.edges.items) |e| if (!e.transitive and e.from == v and e.to == u) { adjacent = true; break; }; if (adjacent) { parent[u] = v; g.append(usize, &queue, u); } } }
    if (parent[path[1]] == null) return &.{}; var result: std.ArrayList(usize) = .empty; var v = path[1]; while (true) { g.append(usize, &result, v); if (v == path[0]) break; v = parent[v].?; } std.mem.reverse(usize, result.items); return result.items;
}
fn paint(graph: *g.Graph, geometry_data: Geometry, x: []const i64, path: []const usize) drawing.Canvas {
    const geo = geometry_data; var canvas = drawing.Canvas.init(graph.settings, geo.main_size, geo.secondary_size);
    for (graph.vertices.items, 0..) |v, id| { const band = geo.starts[v.layer]; if (v.dummy) { var j: i64 = 0; while (j < geo.thickness[v.layer]) : (j += 1) canvas.line(band + j, x[id], true); } else if (!graph.settings.vertical() and c.neighbors(graph, id, false).len > 0) { var j = v.width; while (j < geo.thickness[v.layer]) : (j += 1) canvas.line(band + j, x[id], true); } }
    for (graph.segments.items) |s| {
        const layer = graph.vertices.items[s.upper].layer; const start = geo.starts[layer] + geo.thickness[layer]; const gap = geo.gaps[layer]; var j: i64 = 0;
        if (x[s.upper] == x[s.lower]) { while (j < gap) : (j += 1) canvas.line(start + j, x[s.upper], true); }
        else { while (j < s.track) : (j += 1) canvas.line(start + j, x[s.upper], true); canvas.corner(start + s.track, x[s.upper]); canvas.corner(start + s.track, x[s.lower]); var coord = @min(x[s.upper], x[s.lower]) + 1; while (coord < @max(x[s.upper], x[s.lower])) : (coord += 1) canvas.line(start + s.track, coord, false); j = s.track + 1; while (j < gap) : (j += 1) canvas.line(start + j, x[s.lower], true); }
    }
    for (graph.edges.items, 0..) |*edge, ei| {
        if (edge.transitive) continue; var route: std.ArrayList(g.Point) = .empty; const va = graph.vertices.items[edge.a]; const vb = graph.vertices.items[edge.b]; const size: i64 = if (graph.settings.vertical()) 1 else va.width;
        g.append(g.Point, &route, canvas.map(geo.starts[va.layer] + size, x[edge.a]));
        for (graph.segments.items) |s| if (s.edge == ei and x[s.upper] != x[s.lower]) { const layer = graph.vertices.items[s.upper].layer; const main_coord = geo.starts[layer] + geo.thickness[layer] + s.track; g.append(g.Point, &route, canvas.map(main_coord, x[s.upper])); g.append(g.Point, &route, canvas.map(main_coord, x[s.lower])); edge.bends += 2; };
        g.append(g.Point, &route, canvas.map(geo.starts[vb.layer] - 1, x[edge.b])); canvas.arrow(if (edge.reversed) route.items[0] else route.items[route.items.len - 1], edge.reversed);
        if (edge.reversed) std.mem.reverse(g.Point, route.items); edge.route = route.items; edge.length = 1; for (1..route.items.len) |i| edge.length += @intCast(@abs(route.items[i].row - route.items[i - 1].row) + @abs(route.items[i].column - route.items[i - 1].column));
        var highlighted = false; if (path.len > 1) for (1..path.len) |i| if (path[i - 1] == edge.from and path[i] == edge.to) { highlighted = true; break; };
        if (highlighted) for (1..route.items.len) |i| canvas.highlight(route.items[i - 1], route.items[i]);
    }
    for (graph.vertices.items[0..graph.nodes], 0..) |v, id| { var highlighted = false; for (path) |u| if (id == u) { highlighted = true; break; }; const point = if (graph.settings.vertical()) canvas.map(geo.starts[v.layer], x[id] - v.left) else g.Point{ .row = x[id], .column = if (g.eq(graph.settings.direction, "LR")) geo.starts[v.layer] else geo.main_size - geo.starts[v.layer] - v.width }; canvas.box(point, v.label, highlighted); }
    return canvas;
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa); defer arena.deinit(); g.allocator = arena.allocator();
    const graphs = g.parse(try g.read(init.io, "input/params.txt"), try g.read(init.io, "input/graphs.txt")); var layout: g.Text = .{}; var stats: g.Text = .{}; var csv: g.Text = .{}; var drawings: g.Text = .{}; csv.line("graph,run,sweep,crossings", .{});
    var valid: usize = 0; var nodes_total: usize = 0; var edges_total: usize = 0; var dummy_total: usize = 0; var initial_total: usize = 0; var final_total: usize = 0;
    for (graphs, 0..) |*graph, gi| {
        if (gi > 0) drawings.line("", .{}); layout.line("graph {s}", .{graph.name}); stats.line("graph {s}", .{graph.name});
        if (graph.error_kind) |error_kind| { layout.line("error {s} line {d}", .{error_kind, graph.error_line}); layout.line("end", .{}); stats.line("error {s} line {d}", .{error_kind, graph.error_line}); stats.line("end", .{}); drawings.line("graph {s} error {s}", .{graph.name, error_kind}); continue; }
        valid += 1; graph.settings.display(&layout); analysis(graph, &stats); const acyclic = a.acyclic(graph); layout.put("acyclic", .{}); for (acyclic) |v| layout.put(" {s}", .{graph.vertices.items[v].name}); layout.put("\n", .{});
        const layering = a.layers(graph, acyclic); if (g.eq(graph.settings.layering, "coffman")) { layout.put("labels", .{}); for (layering.labels, graph.vertices.items) |label, v| layout.put(" {s}:{d}", .{v.name, label}); layout.put("\n", .{}); } for (layering.promotions) |promotion| layout.line("promote {d} {s} {d}", .{promotion.round, graph.vertices.items[promotion.vertex].name, promotion.difference});
        for ([_]bool{true, false}) |reversed| { var count: usize = 0; for (graph.edges.items) |edge| count += @intFromBool(if (reversed) edge.reversed else edge.transitive); stats.put("{s} {d}", .{if (reversed) "reversed" else "transitive", count}); for (graph.edges.items) |edge| if (if (reversed) edge.reversed else edge.transitive) stats.put(" {s}->{s}", .{graph.vertices.items[edge.from].name, graph.vertices.items[edge.to].name}); stats.put("\n", .{}); }
        const initial = initialOrders(graph); const reduction = reduceCrossings(graph, initial, &layout, &csv); const orders = reduction.orders; const position = c.positions(orders, graph.vertices.items.len); const final_crossings = c.total(graph, orders);
        for (graph.segments.items, 0..) |first, i| for (graph.segments.items[i + 1 ..]) |second| { if (graph.vertices.items[first.upper].layer == graph.vertices.items[second.upper].layer and c.crosses(first, second, position)) { graph.edges.items[first.edge].crossings += 1; graph.edges.items[second.edge].crossings += 1; } };
        const coords = coordinates.assign(graph, orders); const x = coords.x; const geo = geometry(graph, orders, x); const path = shortest(graph); const canvas = paint(graph, geo, x, path); canvas.display(graph.name, &drawings);
        var max_nodes: usize = 0; var max_vertices: usize = 0;
        for (orders, 0..) |row, layer| { var node_count: usize = 0; var low: i64 = std.math.maxInt(i64); var high: i64 = std.math.minInt(i64); for (row) |v| { node_count += @intFromBool(v < graph.nodes); low = @min(low, x[v] - graph.vertices.items[v].left); high = @max(high, x[v] + graph.vertices.items[v].right); } max_nodes = @max(max_nodes, node_count); max_vertices = @max(max_vertices, row.len); var begin = geo.starts[layer]; var end = begin + geo.thickness[layer] - 1; if (g.eq(graph.settings.direction, "BT") or g.eq(graph.settings.direction, "RL")) { const old = begin; begin = geo.main_size - 1 - end; end = geo.main_size - 1 - old; } layout.put("layer {d} band {d} {d} extent {d} {d} :", .{layer, begin, end, low, high}); for (row) |v| layout.put(" {s}@{d}", .{graph.vertices.items[v].name, x[v]}); layout.put("\n", .{}); }
        for (0..orders.len - 1) |layer| { var segments: usize = 0; for (graph.segments.items) |s| segments += @intFromBool(graph.vertices.items[s.upper].layer == layer); layout.line("between {d} {d} segments {d} crossings {d} tracks {d} gap {d}", .{layer, layer + 1, segments, c.gap(graph, orders, layer), geo.tracks[layer], geo.gaps[layer]}); }
        const variants = [_][]const u8{"ul", "ur", "dl", "dr"}; layout.line("bk conflicts {d} ul={d}/{d} ur={d}/{d} dl={d}/{d} dr={d}/{d} smallest {s}", .{coords.conflicts, coords.blocks[0], coords.widths[0], coords.blocks[1], coords.widths[1], coords.blocks[2], coords.widths[2], coords.blocks[3], coords.widths[3], variants[coords.smallest]});
        for (orders, 0..) |row, layer| for (row, 0..) |v, pos| layout.line("vertex {s} layer {d} pos {d} ul {d} ur {d} dl {d} dr {d} x {d}", .{graph.vertices.items[v].name, layer, pos, coords.aligned[0][v], coords.aligned[1][v], coords.aligned[2][v], coords.aligned[3][v], x[v]});
        const spans = g.zero(usize, orders.len, 0); var span_total: usize = 0; var span_max: usize = 0; var long: usize = 0; var vertical: usize = 0; var routes_length: usize = 0; var bends: usize = 0; var longest: ?usize = null;
        for (graph.edges.items, 0..) |edge, ei| {
            layout.put("edge {s} {s}", .{graph.vertices.items[edge.from].name, graph.vertices.items[edge.to].name}); if (edge.transitive) { layout.line(" transitive", .{}); continue; }
            const span = edge.chain.len - 1; spans[span] += 1; span_total += span; span_max = @max(span_max, span); routes_length += edge.length; bends += edge.bends; if (longest == null or edge.length > graph.edges.items[longest.?].length) longest = ei;
            if (span >= 2) { long += 1; var same = true; for (edge.chain[1 .. edge.chain.len - 1]) |v| if (x[v] != x[edge.chain[1]]) { same = false; break; }; vertical += @intFromBool(same); }
            layout.put("{s} span {d} crossings {d} bends {d} path", .{if (edge.reversed) " reversed" else "", span, edge.crossings, edge.bends}); for (0..edge.chain.len) |i| { const v = edge.chain[if (edge.reversed) edge.chain.len - 1 - i else i]; layout.put(" {d}", .{x[v]}); } layout.put(" route", .{}); for (edge.route) |point| layout.put(" {d},{d}", .{point.row, point.column}); layout.put("\n", .{});
        }
        layout.line("end", .{}); stats.line("layers {d} max_nodes {d} max_vertices {d}", .{orders.len, max_nodes, max_vertices}); if (graph.settings.promotion) stats.line("promotion rounds {d} accepted {d} dummies_before {d}", .{layering.rounds, layering.promotions.len, layering.dummies_before}) else stats.line("promotion off", .{});
        stats.line("dummies {d} span_total {d} span_max {d}", .{graph.vertices.items.len - graph.nodes, span_total, span_max}); if (longest == null) stats.line("spans none", .{}) else { stats.put("spans", .{}); for (spans, 0..) |count, span| if (count > 0) stats.put(" {d}:{d}", .{span, count}); stats.put("\n", .{}); }
        stats.line("long_edges {d} vertical {d}", .{long, vertical}); stats.line("crossings initial {d} swept {d} best_run {d} best_sweep {d} final {d} brute {d}", .{reduction.initial, reduction.swept, reduction.run, reduction.sweep, final_crossings, c.brute(graph, orders)});
        var straight: usize = 0; var offset: u64 = 0; for (graph.segments.items) |s| { straight += @intFromBool(x[s.upper] == x[s.lower]); offset += @abs(x[s.upper] - x[s.lower]); } stats.line("segments {d} straight {d} bent {d} offset {d}", .{graph.segments.items.len, straight, graph.segments.items.len - straight, offset}); stats.put("routes length {d} bends {d}", .{routes_length, bends}); if (longest) |ei| { const edge = graph.edges.items[ei]; stats.put(" longest {s}->{s} {d}", .{graph.vertices.items[edge.from].name, graph.vertices.items[edge.to].name, edge.length}); } stats.put("\n", .{}); stats.line("canvas width {d} height {d} crossing_cells {d}", .{canvas.columns, canvas.rows, canvas.crossings()});
        if (graph.path) |ends| { stats.put("path {s} {s}", .{graph.vertices.items[ends[0]].name, graph.vertices.items[ends[1]].name}); if (path.len == 0) stats.line(" none", .{}) else { stats.put(" hops {d} :", .{path.len - 1}); for (path) |v| stats.put(" {s}", .{graph.vertices.items[v].name}); stats.put("\n", .{}); } } stats.line("end", .{});
        nodes_total += graph.nodes; edges_total += graph.edges.items.len; dummy_total += graph.vertices.items.len - graph.nodes; initial_total += reduction.initial; final_total += final_crossings;
    }
    stats.line("summary graphs {d} laid_out {d} errors {d} nodes {d} edges {d} dummies {d} crossings_initial {d} crossings_final {d}", .{graphs.len, valid, graphs.len - valid, nodes_total, edges_total, dummy_total, initial_total, final_total});
    try g.write(init.io, "layout.txt", layout); try g.write(init.io, "stats.txt", stats); try g.write(init.io, "crossings.csv", csv); try g.write(init.io, "drawings.txt", drawings);
}
