const std = @import("std");
const c = @import("pgm_io.zig");
const filters = @import("filters.zig");
const canny = @import("canny.zig");
const hough = @import("hough.zig");
const corners = @import("corners.zig");
const Circle = struct { peak: hough.CirclePeak, gap: i64 = 0, arcs: i64 = 0 };
const Segment = struct { start: c.Point, end: c.Point, length: i64, pixels: i64, theta: i64, line: usize };
const Line = struct { peak: hough.LinePeak, segments: []const usize };
const Junction = struct { a: usize, b: usize, point: c.Point, a_end: bool, b_end: bool };
const Polygon = struct { segments: [4]usize, count: usize, vertices: [4]c.Point = undefined, angles: [4]i64 = undefined,
     lengths: [4]i64 = undefined, support: [4]i64 = undefined, sigma: i64 = 0, vertex_corners: [4]?usize = .{ null,
     null, null, null }, kind: []const u8 = "" };
const Shape = struct { polygon: bool, index: usize, representatives: [4]c.Point = undefined, count: usize,
     pixels: i64 = 0, mean: i64 = 0, contrast: i64 = 0, parent: ?usize = null };
const Projected = struct { point: c.Point, position: i64 };
fn difference(a: c.Point, b: c.Point) c.Point {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}
fn cross(a: c.Point, b: c.Point) i64 {
    return a.x * b.y - a.y * b.x;
}
fn dot(a: c.Point, b: c.Point) i64 {
    return a.x * b.x + a.y * b.y;
}
fn chebyshev(a: c.Point, b: c.Point) i64 {
    return @max(filters.absolute(a.x - b.x), filters.absolute(a.y - b.y));
}
fn angle(a: i64, b: i64) i64 {
    const d = filters.absolute(a - b);
    return @min(d, 180 - d);
}
fn rounded(numerator: i64, denominator: i64) i64 {
    const n = if (denominator < 0) -numerator else numerator;
    const d = if (denominator < 0) -denominator else denominator;
    return @divFloor(2 * n + d, 2 * d);
}
const Bres = struct { data: [300]c.Point = undefined, count: usize = 0 };
fn bresenham(start: c.Point, end: c.Point) Bres {
    var out: Bres = .{};
    var x = start.x;
    var y = start.y;
    const dx = filters.absolute(end.x - x);
    const dy = -filters.absolute(end.y - y);
    const sx: i64 = if (x < end.x) 1 else -1;
    const sy: i64 = if (y < end.y) 1 else -1;
    var error_value = dx + dy;
    while (true) {
        out.data[out.count] = .{ .x = x, .y = y };
        out.count += 1;
        if (x == end.x and y == end.y) break;
        const twice = 2 * error_value;
        if (twice >= dy) {
            error_value += dy;
            x += sx;
        }
        if (twice <= dx) {
            error_value += dx;
            y += sy;
        }
    }
    return out;
}
fn circumference(point: c.Point, circle: Circle) bool {
    const delta = difference(point, circle.peak.center);
    const d2 = dot(delta, delta);
    const r = circle.peak.radius;
    return (r - 1) * (r - 1) <= d2 and d2 <= (r + 1) * (r + 1);
}
fn nearEdge(edges: c.Image, point: c.Point) bool {
    for (c.offsets) |dy| for (c.offsets) |dx| {
        const next: c.Point = .{ .x = point.x + dx, .y = point.y + dy };
        if (edges.inside(next) and edges.at(next) != 0) return true;
    };
    return false;
}
fn shapeName(index: ?usize, shapes: []const Shape) []const u8 {
    const id = index orelse return "none";
    const shape = shapes[id];
    return c.fmt("{s} {d}", .{ if (shape.polygon) "polygon" else "circle", shape.index + 1 });
}
fn inside(point: c.Point, shape: Shape, polygons: []const Polygon, circles: []const Circle) bool {
    if (!shape.polygon) {
        const circle = circles[shape.index].peak;
        const delta = difference(point, circle.center);
        return dot(delta, delta) <= circle.radius * circle.radius;
    }
    const polygon = polygons[shape.index];
    for (0..polygon.count) |i| {
        const a = polygon.vertices[i];
        const b = polygon.vertices[(i + 1) % polygon.count];
        const value = cross(difference(b, a), difference(point, a));
        if (value != 0 and ((value > 0) != (polygon.sigma > 0))) return false;
    }
    return true;
}
fn lookup(junctions: []const Junction, first: usize, second: usize) ?Junction {
    const a = @min(first, second);
    const b = @max(first, second);
    var low: usize = 0;
    var high = junctions.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const value = junctions[middle];
        if (value.a < a or (value.a == a and value.b < b)) low = middle + 1 else high = middle;
    }
    if (low < junctions.len and junctions[low].a == a and junctions[low].b == b) return junctions[low];
    return null;
}
fn junctionEnd(junction: Junction, id: usize, other: usize) bool {
    return if (id < other) junction.a_end else junction.b_end;
}
fn half(point: c.Point) usize {
    return if (point.y > 0 or (point.y == 0 and point.x > 0)) 0 else 1;
}
fn angularLess(_: void, a: c.Point, b: c.Point) bool {
    if (half(a) != half(b)) return half(a) < half(b);
    return cross(a, b) > 0;
}
fn projectedLess(_: void, a: Projected, b: Projected) bool {
    if (a.position != b.position) return a.position < b.position;
    if (a.point.x != b.point.x) return a.point.x < b.point.x;
    return a.point.y < b.point.y;
}
fn integerLess(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn allAngles(polygon: Polygon, target: i64, p: c.Params) bool {
    for (polygon.angles[0..polygon.count]) |value| if (filters.absolute(value - target) > p.angle_tolerance) return false;
    return true;
}
const Search = struct { size: usize, start: usize, path: [4]usize = undefined, segments: []const Segment,
     junctions: []const Junction, adjacency: []const std.ArrayList(usize), edges: c.Image, params: c.Params,
     polygons: *std.ArrayList(Polygon) };
fn visit(search: *Search, count: usize) void {
    const path = search.path;
    const size = search.size;
    const p = search.params;
    if (count == size) {
        if (path[1] >= path[size - 1] or lookup(search.junctions, path[size - 1], path[0]) == null) return;
        var polygon: Polygon = .{ .segments = path, .count = size };
        for (0..size) |i| {
            const previous = path[(i + size - 1) % size];
            const current = path[i];
            const next = path[(i + 1) % size];
            const left = lookup(search.junctions, previous, current).?;
            const right = lookup(search.junctions, current, next).?;
            if (junctionEnd(left, current, previous) == junctionEnd(right, current, next)) return;
            polygon.vertices[i] = left.point;
        }
        var sign: i64 = 0;
        for (0..size) |i| {
            const z = cross(difference(polygon.vertices[(i + 1) % size], polygon.vertices[i]), difference(polygon.vertices[(i + 2) % size],
                 polygon.vertices[(i + 1) % size]));
            if (z == 0 or (sign != 0 and ((z > 0) != (sign > 0)))) return;
            sign = z;
        }
        for (0..size) |i| {
            const a = polygon.vertices[i];
            const b = polygon.vertices[(i + 1) % size];
            const previous = polygon.vertices[(i + size - 1) % size];
            polygon.sigma += cross(a, b);
            const phi = angle(search.segments[path[(i + size - 1) % size]].theta, search.segments[path[i]].theta);
            polygon.angles[i] = if (dot(difference(previous, a), difference(b, a)) < 0) 180 - phi else phi;
            const side = difference(b, a);
            polygon.lengths[i] = dot(side, side);
            const points = bresenham(a, b);
            var supported: i64 = 0;
            for (points.data[0..points.count]) |point| supported += @intFromBool(nearEdge(search.edges, point));
            polygon.support[i] = @divFloor(100 * supported, c.n(points.count));
        }
        if (size == 3) {
            var right = false;
            for (polygon.angles[0..size]) |value| right = right or filters.absolute(value - 90) <= p.angle_tolerance;
            polygon.kind = if (allAngles(polygon, 60, p)) "equilateral_triangle" else if (right) "right_triangle" else "triangle";
        } else {
            const a = angle(search.segments[path[0]].theta, search.segments[path[2]].theta) <= p.angle_tolerance;
            const b = angle(search.segments[path[1]].theta, search.segments[path[3]].theta) <= p.angle_tolerance;
            var largest = polygon.lengths[0];
            var smallest = largest;
            for (polygon.lengths[0..size]) |value| {
                largest = @max(largest, value);
                smallest = @min(smallest, value);
            }
            polygon.kind = if (!a and !b) "quadrilateral" else if (a != b) "trapezoid" else if (!allAngles(polygon,
                 90, p)) "parallelogram" else if (100 * (largest - smallest) <= p.square_tolerance * largest) "square" else "rectangle";
        }
        c.append(Polygon, search.polygons, polygon);
        return;
    }
    for (search.adjacency[path[count - 1]].items) |next| {
        if (next <= search.start) continue;
        var seen = false;
        for (path[0..count]) |id| seen = seen or id == next;
        if (seen) continue;
        search.path[count] = next;
        visit(search, count + 1);
    }
}
fn paint(overlay: c.Image, point: c.Point) void {
    if (overlay.inside(point)) overlay.set(point, 255);
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
    const image = input.image;
    const p = input.params;
    const g = filters.gradient(filters.smooth(image, p));
    const edges = canny.detect(g, p);
    const circle_data = hough.circleVotes(edges.edges, p);
    const circles = c.alloc(Circle, @min(c.u(p.circle_count), circle_data.peaks.len));
    for (circles, 0..) |*circle, index| {
        circle.* = .{ .peak = circle_data.peaks[index] };
        const ordered = c.dupe(c.Point, circle_data.offsets[c.u(circle.peak.radius - p.r_min)]);
        std.mem.sort(c.Point, ordered, {}, angularLess);
        const hit = c.alloc(bool, ordered.len);
        var all = true;
        for (ordered, hit) |offset, *value| {
            const point: c.Point = .{ .x = circle.peak.center.x + offset.x, .y = circle.peak.center.y + offset.y };
            value.* = image.inside(point) and edges.edges.at(point) != 0;
            all = all and value.*;
        }
        const n = hit.len;
        if (all) circle.arcs = 1 else for (hit, 0..) |value, i| {
            circle.arcs += @intFromBool(value and !hit[(i + n - 1) % n]);
        };
        var run: i64 = 0;
        for (0..2 * n) |i| {
            if (hit[i % n]) run = 0 else run += 1;
            circle.gap = @max(circle.gap, @min(c.n(n), run));
        }
    }
    const line_edges: c.Image = .{ .width = image.width, .height = image.height, .data = c.dupe(i64, edges.edges.data) };
    var circle_edge_pixels: i64 = 0;
    for (0..image.height) |y| for (0..image.width) |x| {
        const point: c.Point = .{ .x = c.n(x), .y = c.n(y) };
        if (edges.edges.at(point) == 0) continue;
        for (circles) |circle| if (circumference(point, circle)) {
            line_edges.set(point, 0);
            circle_edge_pixels += 1;
            break;
        };
    };
    const line_data = hough.lineVotes(line_edges, &input.trig, p);
    var lines: std.ArrayList(Line) = .empty;
    var segments: std.ArrayList(Segment) = .empty;
    const claimed = c.Image.init(image.width, image.height);
    const selected = c.alloc(Projected, image.data.len);
    for (line_data.peaks) |peak| {
        if (lines.items.len >= c.u(p.line_count)) break;
        var count: usize = 0;
        for (0..image.height) |y| for (0..image.width) |x| {
            const point: c.Point = .{ .x = c.n(x), .y = c.n(y) };
            if (line_edges.at(point) != 0 and claimed.at(point) == 0 and filters.absolute(hough.rho(point,
                 peak.theta, input.trig, p) - peak.rho) <= p.tolerance) {
                selected[count] = .{ .point = point, .position = point.y * input.trig[c.u(peak.theta)][0] - point.x * input.trig[c.u(peak.theta)][1] };
                count += 1;
            }
        };
        std.mem.sort(Projected, selected[0..count], {}, projectedLess);
        var ids: std.ArrayList(usize) = .empty;
        var begin: usize = 0;
        while (begin < count) {
            var end = begin + 1;
            while (end < count and selected[end].position - selected[end - 1].position <= p.max_gap * 16384) end += 1;
            const start = selected[begin].point;
            const last = selected[end - 1].point;
            const length = chebyshev(start, last) + 1;
            if (length >= p.min_length) {
                c.append(usize, &ids, segments.items.len);
                c.append(Segment, &segments, .{ .start = start, .end = last, .length = length, .pixels = c.n(end - begin),
                     .theta = peak.theta, .line = lines.items.len });
                for (selected[begin..end]) |value| claimed.set(value.point, 1);
            }
            begin = end;
        }
        if (ids.items.len > 0) c.append(Line, &lines, .{ .peak = peak, .segments = ids.items });
    }
    var junctions: std.ArrayList(Junction) = .empty;
    const adjacency = c.alloc(std.ArrayList(usize), segments.items.len);
    @memset(adjacency, .empty);
    for (segments.items, 0..) |first, a| for (a + 1..segments.items.len) |b| {
        const second = segments.items[b];
        if (angle(first.theta, second.theta) < p.junction_angle) continue;
        const da = difference(first.end, first.start);
        const db = difference(second.end, second.start);
        const den = cross(da, db);
        if (den == 0) continue;
        const lambda = cross(difference(second.start, first.start), db);
        const point: c.Point = .{ .x = rounded(first.start.x * den + lambda * da.x, den), .y = rounded(first.start.y * den + lambda * da.y,
             den) };
        const a_start = chebyshev(first.start, point);
        const a_end = chebyshev(first.end, point);
        const b_start = chebyshev(second.start, point);
        const b_end = chebyshev(second.end, point);
        if (@min(a_start, a_end) > p.junction_distance or @min(b_start, b_end) > p.junction_distance) continue;
        c.append(Junction, &junctions, .{ .a = a, .b = b, .point = point, .a_end = a_start > a_end, .b_end = b_start > b_end });
        c.append(usize, &adjacency[a], b);
        c.append(usize, &adjacency[b], a);
    };
    for (adjacency) |list| std.mem.sort(usize, list.items, {}, integerLess);
    var polygon_list: std.ArrayList(Polygon) = .empty;
    for (3..5) |size| for (0..segments.items.len) |start| {
        var search: Search = .{ .size = size, .start = start, .segments = segments.items, .junctions = junctions.items,
             .adjacency = adjacency, .edges = edges.edges, .params = p, .polygons = &polygon_list };
        search.path[0] = start;
        visit(&search, 1);
    };
    const polygons = polygon_list.items;
    const shapes = c.alloc(Shape, polygons.len + circles.len);
    for (polygons, 0..) |polygon, i| shapes[i] = .{ .polygon = true, .index = i, .representatives = polygon.vertices,
         .count = polygon.count };
    for (circles, 0..) |circle, i| {
        const x = circle.peak.center.x;
        const y = circle.peak.center.y;
        const r = circle.peak.radius;
        shapes[polygons.len + i] = .{ .polygon = false, .index = i, .representatives = .{ .{ .x = x + r,
             .y = y }, .{ .x = x, .y = y + r }, .{ .x = x - r, .y = y }, .{ .x = x, .y = y - r } },
             .count = 4 };
    }
    for (shapes) |*shape| {
        var x0 = shape.representatives[0].x;
        var y0 = shape.representatives[0].y;
        var x1 = x0;
        var y1 = y0;
        for (shape.representatives[0..shape.count]) |point| {
            x0 = @min(x0, point.x);
            x1 = @max(x1, point.x);
            y0 = @min(y0, point.y);
            y1 = @max(y1, point.y);
        }
        x0 = @max(0, x0 - p.margin);
        y0 = @max(0, y0 - p.margin);
        x1 = @min(c.n(image.width) - 1, x1 + p.margin);
        y1 = @min(c.n(image.height) - 1, y1 + p.margin);
        var inner: i64 = 0;
        var outer: i64 = 0;
        var outer_count: i64 = 0;
        var y = y0;
        while (y <= y1) : (y += 1) {
            var x = x0;
            while (x <= x1) : (x += 1) {
                const point: c.Point = .{ .x = x, .y = y };
                if (inside(point, shape.*, polygons, circles)) {
                    shape.pixels += 1;
                    inner += image.at(point);
                } else {
                    outer_count += 1;
                    outer += image.at(point);
                }
            }
        }
        shape.mean = if (shape.pixels > 0) @divFloor(inner, shape.pixels) else 0;
        shape.contrast = shape.mean - (if (outer_count > 0) @divFloor(outer, outer_count) else 0);
    }
    for (shapes, 0..) |*shape, i| for (shapes, 0..) |other, j| {
        if (i == j or other.pixels <= shape.pixels) continue;
        var contains = true;
        for (shape.representatives[0..shape.count]) |point| contains = contains and inside(point, other, polygons, circles);
        if (contains and (shape.parent == null or other.pixels < shapes[shape.parent.?].pixels)) shape.parent = j;
    };
    const corner_data = corners.detect(g, p);
    const corner_matches = c.alloc([]const u8, corner_data.values.len);
    var corner_vertices: i64 = 0;
    var corner_segments: i64 = 0;
    var vertices_with_corner: i64 = 0;
    for (corner_data.values, corner_matches) |corner, *match| {
        var best = p.match_distance + 1;
        match.* = "none";
        for (polygons, 0..) |polygon, pi| for (polygon.vertices[0..polygon.count], 0..) |vertex, vi| {
            const d = chebyshev(corner.point, vertex);
            if (d <= p.match_distance and d < best) {
                best = d;
                match.* = c.fmt("polygon {d} vertex {d}", .{ pi + 1, vi + 1 });
            }
        };
        if (!c.eq(match.*, "none")) corner_vertices += 1 else {
            best = p.match_distance + 1;
            for (segments.items, 0..) |segment, id| for (0..2) |end| {
                const d = chebyshev(corner.point, if (end == 1) segment.end else segment.start);
                if (d <= p.match_distance and d < best) {
                    best = d;
                    match.* = c.fmt("segment {d} {s}", .{ id + 1, if (end == 1) "end" else "start" });
                }
            };
            if (!c.eq(match.*, "none")) corner_segments += 1;
        }
    }
    for (polygons) |*polygon| for (polygon.vertices[0..polygon.count], 0..) |vertex, vi| {
        var best = p.match_distance + 1;
        for (corner_data.values, 0..) |corner, id| {
            const d = chebyshev(vertex, corner.point);
            if (d <= p.match_distance and d < best) {
                best = d;
                polygon.vertex_corners[vi] = id;
            }
        }
        vertices_with_corner += @intFromBool(polygon.vertex_corners[vi] != null);
    };
    const component_shapes = c.alloc(?usize, edges.components.len);
    @memset(component_shapes, null);
    const explained_counts = c.alloc(i64, edges.components.len);
    @memset(explained_counts, 0);
    const explained = c.Image.init(image.width, image.height);
    for (shapes, 0..) |shape, si| {
        @memset(explained.data, 0);
        if (shape.polygon) {
            const polygon = polygons[shape.index];
            for (0..polygon.count) |i| {
                const points = bresenham(polygon.vertices[i], polygon.vertices[(i + 1) % polygon.count]);
                for (points.data[0..points.count]) |point| for (c.offsets) |dy| for (c.offsets) |dx| {
                    const next: c.Point = .{ .x = point.x + dx, .y = point.y + dy };
                    if (image.inside(next)) explained.set(next, 1);
                };
            }
        }
        for (edges.components, 0..) |component, index| {
            var count: i64 = 0;
            for (component) |point| count += if (shape.polygon) explained.at(point) else @intFromBool(circumference(point,
                 circles[shape.index]));
            if (count > explained_counts[index]) {
                explained_counts[index] = count;
                component_shapes[index] = si;
            }
        }
    }
    const overlay = c.Image.init(image.width, image.height);
    const edge_image = c.Image.init(image.width, image.height);
    const hough_image = c.Image.init(line_data.votes.width, line_data.votes.height);
    for (image.data, 0..) |value, i| {
        overlay.data[i] = @divFloor(value, p.overlay_divisor);
        edge_image.data[i] = 255 * edges.edges.data[i];
    }
    for (line_data.votes.data, 0..) |value, i| hough_image.data[i] = if (line_data.maximum > 0) @divFloor(255 * value,
         line_data.maximum) else 0;
    for (segments.items) |segment| {
        const points = bresenham(segment.start, segment.end);
        for (points.data[0..points.count]) |point| paint(overlay, point);
    }
    for (circles) |circle| for (circle_data.offsets[c.u(circle.peak.radius - p.r_min)]) |offset| {
        paint(overlay, .{ .x = circle.peak.center.x + offset.x, .y = circle.peak.center.y + offset.y });
    };
    for (corner_data.values) |corner| {
        var e: i64 = -2;
        while (e <= 2) : (e += 1) {
            paint(overlay, .{ .x = corner.point.x + e, .y = corner.point.y });
            paint(overlay, .{ .x = corner.point.x, .y = corner.point.y + e });
        }
    }
    try c.writePgm(init.io, "edges.pgm", edge_image);
    try c.writePgm(init.io, "hough.pgm", hough_image);
    try c.writePgm(init.io, "overlay.pgm", overlay);
    var line_file: c.Lines = .{};
    var circle_file: c.Lines = .{};
    var polygon_file: c.Lines = .{};
    var corner_file: c.Lines = .{};
    var component_file: c.Lines = .{};
    var report: c.Lines = .{};
    line_file.add("lines {d}", .{lines.items.len});
    for (lines.items, 1..) |line, number| {
        line_file.add("line {d} theta {d} rho {d} votes {d} segments {d}", .{ number, line.peak.theta,
             line.peak.rho, line.peak.votes, line.segments.len });
        for (line.segments) |id| {
            const segment = segments.items[id];
            line_file.add("segment {d} start {d} {d} end {d} {d} length {d} pixels {d}", .{ id + 1,
                 segment.start.x, segment.start.y, segment.end.x, segment.end.y, segment.length, segment.pixels });
        }
    }
    circle_file.add("circles {d}", .{circles.len});
    for (circles, 0..) |circle, i| {
        const shape = shapes[polygons.len + i];
        circle_file.add("circle {d} center {d} {d} radius {d} votes {d} points {d} gap {d} arcs {d} pixels {d} mean {d} contrast {d} inside {s}",
             .{ i + 1, circle.peak.center.x, circle.peak.center.y, circle.peak.radius, circle.peak.votes,
             circle.peak.points, circle.gap, circle.arcs, shape.pixels, shape.mean, shape.contrast,
             shapeName(shape.parent, shapes) });
    }
    polygon_file.add("polygons {d}", .{polygons.len});
    for (polygons, 0..) |polygon, i| {
        const shape = shapes[i];
        var line: c.Text = .{};
        line.add("polygon {d} {s} segments", .{ i + 1, polygon.kind });
        for (polygon.segments[0..polygon.count]) |id| line.add(" {d}", .{id + 1});
        const area = filters.absolute(polygon.sigma);
        line.add(" area {d}.{d} pixels {d} mean {d} contrast {d} inside {s}", .{ @divTrunc(area, 2),
             if (@mod(area, 2) == 1) @as(i64, 5) else @as(i64, 0), shape.pixels, shape.mean, shape.contrast,
             shapeName(shape.parent, shapes) });
        polygon_file.add("{s}", .{line.value()});
        for (polygon.vertices[0..polygon.count], 0..) |vertex, v| polygon_file.add("vertex {d} {d} {d} angle {d} corner {s}",
             .{ v + 1, vertex.x, vertex.y, polygon.angles[v], if (polygon.vertex_corners[v]) |id| c.fmt("{d}",
             .{id + 1}) else "none" });
        for (polygon.segments[0..polygon.count], 0..) |id, side| polygon_file.add("side {d} segment {d} length2 {d} support {d}",
             .{ side + 1, id + 1, polygon.lengths[side], polygon.support[side] });
    }
    corner_file.add("corners {d}", .{corner_data.values.len});
    for (corner_data.values, corner_matches, 1..) |corner, match, number| corner_file.add("corner {d} {d} {d} response {d} match {s}",
         .{ number, corner.point.x, corner.point.y, corner.response, match });
    component_file.add("components {d}", .{edges.components.len});
    for (edges.components, 0..) |component, i| {
        var x0 = c.n(image.width) - 1;
        var y0 = c.n(image.height) - 1;
        var x1: i64 = 0;
        var y1: i64 = 0;
        var ends: i64 = 0;
        var strength: i64 = 0;
        var directions = [_]i64{ 0, 0, 0, 0 };
        for (component) |point| {
            x0 = @min(x0, point.x);
            y0 = @min(y0, point.y);
            x1 = @max(x1, point.x);
            y1 = @max(y1, point.y);
            var neighbors: i64 = 0;
            for (c.offsets) |dy| for (c.offsets) |dx| {
                const next: c.Point = .{ .x = point.x + dx, .y = point.y + dy };
                if ((dx != 0 or dy != 0) and image.inside(next) and edges.edges.at(next) != 0) neighbors += 1;
            };
            ends += @intFromBool(neighbors == 1);
            strength += g.magnitude.at(point);
            directions[c.u(@divTrunc(edges.direction.at(point), 45))] += 1;
        }
        var direction: usize = 0;
        for (1..4) |j| if (directions[j] > directions[direction]) {
            direction = j;
        };
        component_file.add("component {d} pixels {d} box {d} {d} {d} {d} ends {d} strength {d} direction {d} shape {s} explained {d}",
             .{ i + 1, component.len, x0, y0, x1, y1, ends, @divFloor(strength, c.n(component.len)),
             45 * direction, shapeName(component_shapes[i], shapes), explained_counts[i] });
    }
    const names = [_][]const u8{ "gradient_nonzero", "gradient_max", "nms_kept", "strong", "weak",
         "edges", "weak_kept", "weak_dropped", "edge_components", "direction_0", "direction_45", "direction_90",
         "direction_135", "circle_candidates", "circle_peaks", "circles", "circle_edge_pixels", "line_edge_pixels",
         "hough_max_votes", "hough_peaks", "lines", "segments", "claimed_pixels", "junctions", "polygons",
         "equilateral_triangle", "right_triangle", "triangle", "square", "rectangle", "parallelogram",
         "trapezoid", "quadrilateral", "corner_candidates", "corners", "corners_on_vertices", "corners_on_segments",
         "corners_unmatched", "vertices_with_corner" };
    var counts = [_]i64{0} ** 39;
    for (image.data, 0..) |_, i| {
        counts[0] += @intFromBool(g.magnitude.data[i] > 0);
        counts[1] = @max(counts[1], g.magnitude.data[i]);
        counts[2] += @intFromBool(edges.nms.data[i] > 0);
        counts[5] += edges.edges.data[i];
        counts[6] += @intFromBool(edges.edges.data[i] != 0 and edges.nms.data[i] >= p.low and edges.nms.data[i] < p.high);
        counts[22] += claimed.data[i];
        if (edges.edges.data[i] != 0) counts[9 + c.u(@divTrunc(edges.direction.data[i], 45))] += 1;
    }
    counts[3] = edges.strong;
    counts[4] = edges.weak;
    counts[7] = edges.weak - counts[6];
    counts[8] = c.n(edges.components.len);
    counts[13] = circle_data.candidates;
    counts[14] = c.n(circle_data.peaks.len);
    counts[15] = c.n(circles.len);
    counts[16] = circle_edge_pixels;
    counts[17] = counts[5] - circle_edge_pixels;
    counts[18] = line_data.maximum;
    counts[19] = c.n(line_data.peaks.len);
    counts[20] = c.n(lines.items.len);
    counts[21] = c.n(segments.items.len);
    counts[23] = c.n(junctions.items.len);
    counts[24] = c.n(polygons.len);
    for (polygons) |polygon| for (25..33) |kind| {
        if (c.eq(polygon.kind, names[kind])) counts[kind] += 1;
    };
    counts[33] = c.n(corner_data.candidates);
    counts[34] = c.n(corner_data.values.len);
    counts[35] = corner_vertices;
    counts[36] = corner_segments;
    counts[37] = c.n(corner_data.values.len) - corner_vertices - corner_segments;
    counts[38] = vertices_with_corner;
    report.add("image {d} {d}", .{ image.width, image.height });
    for (names, counts) |name, count| report.add("{s} {d}", .{ name, count });
    try write(init.io, "lines.txt", line_file);
    try write(init.io, "circles.txt", circle_file);
    try write(init.io, "polygons.txt", polygon_file);
    try write(init.io, "corners.txt", corner_file);
    try write(init.io, "components.txt", component_file);
    try write(init.io, "report.txt", report);
}
