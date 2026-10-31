const std = @import("std");
const r = @import("rational.zig");
const i = @import("intersections.zig");
const rings = @import("rings.zig");
const gh = @import("greiner_hormann.zig");
const render = @import("render.zig");
const Ring = rings.Ring;
const Sequence = rings.Sequence;
const Polygons = rings.Polygons;
const Polygon = struct {
    name: []const u8,
    input_rings: Sequence,
    rings: Sequence,
    fn init(name: []const u8, input: Sequence) *Polygon {
        const canonical = r.alloc(Ring, input.len);
        for (input, canonical, 0..) |ring, *out, index| out.* = rings.normalize(ring, index == 0);
        std.mem.sort(Ring, canonical[1..], {}, rings.ringLess);
        return r.create(Polygon, .{ .name = name, .input_rings = input, .rings = canonical });
    }
};
const Region = struct { polygons: Polygons, operands: ?[2]*const Polygon = null };
const Record = struct { number: usize, line: []const u8 };
fn records(io: std.Io, name: []const u8) ![]const Record {
    var out: std.ArrayList(Record) = .empty;
    for (try r.readLines(io, r.fmt("input/{s}", .{name})), 1..) |line, number| if (line.len > 0 and line[0] != '#') r.append(Record,
         &out, .{ .number = number, .line = line });
    return out.items;
}
fn digits(word: []const u8) bool {
    if (word.len < 1 or word.len > 9) return false;
    for (word) |character| if (character < '0' or character > '9') return false;
    return true;
}
fn integerWord(word: []const u8) bool {
    return digits(if (word.len > 0 and word[0] == '-') word[1..] else word);
}
fn validName(word: []const u8) bool {
    if (word.len < 1 or word.len > 16) return false;
    for (word) |character| if (!((character >= 'a' and character <= 'z') or (character >= '0' and character <= '9') or character == '_')) return false;
    return true;
}
const Parsed = struct { sequence: Sequence = &.{}, error_line: ?usize = null };
fn parseRings(content: []const Record, end_line: usize) Parsed {
    var sequence: std.ArrayList(Ring) = .empty;
    var position: usize = 0;
    while (position < content.len) {
        const record = content[position];
        const words = r.words(record.line);
        if (words.len != 2 or (!r.eq(words[0], "OUTER") and !r.eq(words[0], "HOLE")) or !digits(words[1]) or r.number(words[1]) < 1) return .{ .error_line = record.number };
        if ((r.eq(words[0], "OUTER") and sequence.items.len > 0) or (r.eq(words[0], "HOLE") and sequence.items.len == 0)) return .{ .error_line = record.number };
        const count = r.u(r.number(words[1]));
        position += 1;
        var points: std.ArrayList(r.Point) = .empty;
        for (0..count) |_| {
            if (position == content.len) return .{ .error_line = end_line };
            const vertex = content[position];
            const coordinates = r.words(vertex.line);
            if (coordinates.len != 2 or !integerWord(coordinates[0]) or !integerWord(coordinates[1])) return .{ .error_line = vertex.number };
            r.append(r.Point, &points, r.Point.init(r.number(coordinates[0]), r.number(coordinates[1])));
            position += 1;
        }
        r.append(Ring, &sequence, points.items);
    }
    return if (sequence.items.len == 0) .{ .error_line = end_line } else .{ .sequence = sequence.items };
}
fn inRange(point: r.Point) bool {
    return point.x.numerator >= 0 and !r.Fraction.integer(1000).less(point.x) and point.y.numerator >= 0 and !r.Fraction.integer(1000).less(point.y);
}
fn checkRing(ring: Ring, number: usize) ?[]const u8 {
    if (ring.len < 3) return r.fmt("too_few_vertices ring {d}", .{number});
    for (ring) |point| if (!inRange(point)) return r.fmt("out_of_range ring {d} {s}", .{ number, point.text() });
    for (ring, 0..) |point, index| for (ring[0..index]) |earlier| if (point.same(earlier)) return r.fmt("duplicate_vertex ring {d} {s}",
         .{ number, point.text() });
    for (ring, 0..) |point, index| if (r.cross(ring[(index + ring.len - 1) % ring.len], point,
         ring[(index + 1) % ring.len]).numerator == 0) return r.fmt("collinear ring {d} {s}",
         .{ number, point.text() });
    for (ring, 0..) |first, a| for (a + 1..ring.len) |c| {
        if (c == a + 1 or (a == 0 and c == ring.len - 1)) continue;
        const second = ring[(a + 1) % ring.len];
        const third = ring[c];
        const fourth = ring[(c + 1) % ring.len];
        if (i.touch(first, second, third, fourth)) return r.fmt("self_intersection ring {d} {s} {s}",
             .{ number, r.segmentText(first, second), r.segmentText(third, fourth) });
    };
    return null;
}
fn checkPolygon(sequence: Sequence) ?[]const u8 {
    for (sequence, 1..) |ring, index| if (checkRing(ring, index)) |reason| return reason;
    for (sequence, 0..) |first, a| for (a + 1..sequence.len) |c| {
        const second = sequence[c];
        for (first, 0..) |p, edge| for (second, 0..) |q, other| {
            const p2 = first[(edge + 1) % first.len];
            const q2 = second[(other + 1) % second.len];
            if (i.touch(p, p2, q, q2)) return r.fmt("rings_touch rings {d} {d} {s} {s}", .{ a + 1,
                 c + 1, r.segmentText(p, p2), r.segmentText(q, q2) });
        };
    };
    for (sequence[1..], 2..) |hole, index| if (!rings.inside(sequence[0], hole[0])) return r.fmt("hole_outside ring {d} {s}",
         .{ index, hole[0].text() });
    for (1..sequence.len) |a| for (a + 1..sequence.len) |c| {
        const first = sequence[a];
        const second = sequence[c];
        const point: ?r.Point = if (rings.inside(first, second[0])) second[0] else if (rings.inside(second,
             first[0])) first[0] else null;
        if (point) |p| return r.fmt("hole_in_hole rings {d} {d} {s}", .{ a + 1, c + 1, p.text() });
    };
    return null;
}
const Resolved = struct { polygon: ?*const Polygon = null, error_message: ?[]const u8 = null };
const Registry = struct {
    polygons: std.StringHashMapUnmanaged(?*const Polygon) = .empty,
    invalid: r.Lines = .{},
    block_count: usize = 0,
    valid_blocks: usize = 0,
    fn read(io: std.Io) !Registry {
        var out: Registry = .{};
        const lines = try records(io, "polygons.txt");
        var position: usize = 0;
        while (position < lines.len) {
            const header = lines[position];
            const name = r.words(header.line)[1];
            position += 1;
            const start = position;
            while (!r.eq(lines[position].line, "END")) position += 1;
            const end_line = lines[position].number;
            const content = lines[start..position];
            position += 1;
            out.block_count += 1;
            if (out.polygons.contains(name)) {
                out.invalid.add("polygon {s} duplicate_name line {d}", .{ name, header.number });
                continue;
            }
            out.polygons.put(r.allocator, name, null) catch @panic("allocation failed");
            const parsed = parseRings(content, end_line);
            if (parsed.error_line) |number| {
                out.invalid.add("polygon {s} format line {d}", .{ name, number });
                continue;
            }
            if (checkPolygon(parsed.sequence)) |reason| {
                out.invalid.add("polygon {s} {s}", .{ name, reason });
                continue;
            }
            out.polygons.put(r.allocator, name, Polygon.init(name, parsed.sequence)) catch @panic("allocation failed");
            out.valid_blocks += 1;
        }
        return out;
    }
    fn resolve(self: *const Registry, name: []const u8) Resolved {
        if (self.polygons.get(name)) |entry| {
            if (entry) |polygon| return .{ .polygon = polygon };
            return .{ .error_message = r.fmt("invalid_polygon {s}", .{name}) };
        }
        return .{ .error_message = r.fmt("unknown_polygon {s}", .{name}) };
    }
};
fn copySequence(source: Sequence) Sequence {
    const out = r.alloc(Ring, source.len);
    for (source, out) |ring, *copy| copy.* = r.dupe(r.Point, ring);
    return out;
}
fn copyRegion(source: Region) Region {
    const polygons = r.alloc(Sequence, source.polygons.len);
    for (source.polygons, polygons) |polygon, *copy| copy.* = copySequence(polygon);
    return .{ .polygons = polygons, .operands = source.operands };
}
fn singleRegion(polygon: *const Polygon) Region {
    const list = r.alloc(Sequence, 1);
    list[0] = polygon.rings;
    return .{ .polygons = list };
}
const kinds = [_][]const u8{ "UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA",
     "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER" };
fn kindIndex(name: []const u8) ?usize {
    for (kinds, 0..) |kind, index| if (r.eq(kind, name)) return index;
    return null;
}
fn definition(kind: usize) bool {
    return kind >= 6 and kind <= 9;
}
fn argumentsValid(kind: usize, words: r.Names) bool {
    const counts = [12]usize{ 3, 3, 3, 3, 3, 2, 5, 6, 5, 3, 4, 8 };
    if (words.len != counts[kind]) return false;
    if (kind <= 5) return true;
    if (kind == 9) return validName(words[2]);
    if (kind == 8) return validName(words[4]) and (r.eq(words[2], "x") or r.eq(words[2], "y")) and integerWord(words[3]) and r.number(words[3]) >= 0 and r.number(words[3]) <= 1000;
    if (kind == 6 or kind == 7) {
        if (!validName(words[words.len - 1])) return false;
        for (words[2 .. words.len - 1]) |word| if (!integerWord(word)) return false;
        if (kind == 6) return r.number(words[2]) >= -1000 and r.number(words[2]) <= 1000 and r.number(words[3]) >= -1000 and r.number(words[3]) <= 1000;
        return r.number(words[2]) >= 0 and r.number(words[2]) <= 1000 and r.number(words[3]) >= 0 and r.number(words[3]) <= 1000 and r.number(words[4]) >= 1 and r.number(words[4]) <= 3;
    }
    for (words[2..]) |word| if (!integerWord(word)) return false;
    if (kind == 10) return r.number(words[2]) >= 0 and r.number(words[2]) <= 1000 and r.number(words[3]) >= 0 and r.number(words[3]) <= 1000;
    const x = r.number(words[2]);
    const y = r.number(words[3]);
    const width = r.number(words[4]);
    const height = r.number(words[5]);
    const columns = r.number(words[6]);
    const rows = r.number(words[7]);
    return x >= 0 and y >= 0 and width >= 1 and width <= 100 and height >= 1 and height <= 100 and columns >= 1 and columns <= 100 and rows >= 1 and rows <= 60 and x + width * columns <= 1000 and y + height * rows <= 1000;
}
fn generalPosition(first: *const Polygon, second: *const Polygon) ?[]const u8 {
    var vertices: std.AutoHashMapUnmanaged(r.Point, void) = .empty;
    for (second.rings) |ring| for (ring) |point| vertices.put(r.allocator, point, {}) catch @panic("allocation failed");
    for (first.rings) |ring| for (ring) |point| if (vertices.contains(point)) return r.fmt("shared_vertex {s}",
         .{point.text()});
    for (first.rings) |ring| for (ring, 0..) |a, index| for (second.rings) |other| for (other, 0..) |c, j| {
        const b = ring[(index + 1) % ring.len];
        const d = other[(j + 1) % other.len];
        if (i.overlap(a, b, c, d)) return r.fmt("overlapping_edges {s} {s}", .{ r.segmentText(a,
             b), r.segmentText(c, d) });
    };
    const sources = [2]*const Polygon{ first, second };
    for (sources, 0..) |source, side| {
        const other = sources[1 - side];
        for (source.rings) |ring| for (ring) |point| for (other.rings) |other_ring| for (other_ring, 0..) |a, index| {
            const b = other_ring[(index + 1) % other_ring.len];
            if (i.onSegment(point, a, b)) return r.fmt("vertex_on_edge {s} {s} {s} {s}", .{ source.name,
                 point.text(), other.name, r.segmentText(a, b) });
        };
    }
    return null;
}
fn transformedRings(polygon: *const Polygon, kind: usize, words: r.Names) Sequence {
    const sequence = r.alloc(Ring, polygon.input_rings.len);
    for (polygon.input_rings, sequence) |ring, *result| {
        const points = r.alloc(r.Point, ring.len);
        for (ring, points) |point, *out| {
            var x = point.x.numerator;
            var y = point.y.numerator;
            if (kind == 6) {
                x += r.number(words[2]);
                y += r.number(words[3]);
            } else if (kind == 7) {
                const cx: r.Integer = r.number(words[2]);
                const cy: r.Integer = r.number(words[3]);
                for (0..r.u(r.number(words[4]))) |_| {
                    const next_x = cx - (y - cy);
                    y = cy + (x - cx);
                    x = next_x;
                }
            } else if (r.eq(words[2], "x")) x = 2 * @as(r.Integer, r.number(words[3])) - x else y = 2 * @as(r.Integer,
                 r.number(words[3])) - y;
            out.* = r.Point.init(x, y);
        }
        result.* = points;
    }
    return sequence;
}
fn roundedRings(source: Sequence) Sequence {
    const out = r.alloc(Ring, source.len);
    for (source, out) |ring, *result| {
        const points = r.alloc(r.Point, ring.len);
        for (ring, points) |point, *copy| copy.* = r.Point.init(point.x.rounded(), point.y.rounded());
        result.* = points;
    }
    return out;
}
const Checked = struct { error_message: ?[]const u8 = null, kind: usize = 0, first: ?*const Polygon = null,
     second: ?*const Polygon = null, target: ?Region = null, defined: ?*const Polygon = null };
fn checkOperation(registry: *const Registry, regions: []const ?Region, words: r.Names) Checked {
    const kind = kindIndex(words[0]) orelse return .{ .error_message = r.fmt("unknown_operation {s}", .{words[0]}) };
    if (!argumentsValid(kind, words)) return .{ .error_message = "bad_arguments" };
    var out: Checked = .{ .kind = kind };
    if (kind <= 8) {
        const first = registry.resolve(words[1]);
        if (first.error_message) |message| return .{ .error_message = message };
        out.first = first.polygon;
        if (kind < 5) {
            const second = registry.resolve(words[2]);
            if (second.error_message) |message| return .{ .error_message = message };
            out.second = second.polygon;
        }
    } else {
        const target = words[1];
        if (target.len > 0 and target[0] == '@') {
            if (!digits(target[1..])) return .{ .error_message = r.fmt("bad_target {s}", .{target}) };
            const number = r.u(r.number(target[1..]));
            if (number >= regions.len or regions[number] == null) return .{ .error_message = r.fmt("bad_target {s}",
                 .{target}) };
            out.target = regions[number].?;
        } else {
            const resolved = registry.resolve(target);
            if (resolved.error_message) |message| return .{ .error_message = message };
            out.target = singleRegion(resolved.polygon.?);
        }
    }
    if (definition(kind) and registry.polygons.contains(words[words.len - 1])) return .{ .error_message = r.fmt("duplicate_name {s}",
         .{words[words.len - 1]}) };
    if (kind == 9 and out.target.?.polygons.len != 1) return .{ .error_message = r.fmt("not_single {s}", .{words[1]}) };
    if (kind == 4) {
        const window = out.second.?.rings;
        var convex = window.len == 1;
        if (convex) for (window[0], 0..) |point, index| {
            if (r.cross(window[0][(index + window[0].len - 1) % window[0].len], point, window[0][(index + 1) % window[0].len]).numerator <= 0) convex = false;
        };
        if (!convex) return .{ .error_message = r.fmt("not_convex {s}", .{words[2]}) };
    }
    if (kind < 5) {
        if (generalPosition(out.first.?, out.second.?)) |message| return .{ .error_message = message };
    }
    if (kind >= 6 and kind <= 8) {
        const sequence = transformedRings(out.first.?, kind, words);
        for (sequence) |ring| for (ring) |point| if (!inRange(point)) return .{ .error_message = r.fmt("out_of_range {s}",
             .{words[words.len - 1]}) };
        out.defined = Polygon.init(words[words.len - 1], sequence);
    } else if (kind == 9) {
        const sequence = roundedRings(out.target.?.polygons[0]);
        if (checkPolygon(sequence)) |message| return .{ .error_message = r.fmt("invalid_result {s}", .{message}) };
        out.defined = Polygon.init(words[2], sequence);
    }
    return out;
}

fn totalArea(polygons: Polygons) f64 {
    var area: f64 = 0;
    for (polygons) |polygon| for (polygon) |ring| {
        area += rings.area(ring);
    };
    return area;
}
const BinaryResult = struct { region: Region, graph: gh.Graph, relation: []const u8, iou: f64 };
fn binaryResult(kind: usize, first: *const Polygon, second: *const Polygon) BinaryResult {
    const graph = gh.Graph.init(first.rings, second.rings);
    const intersection = rings.assemble(graph.traverse(false, false));
    const union_result = rings.assemble(graph.traverse(true, true));
    var polygons: Polygons = undefined;
    if (kind == 0) polygons = union_result else if (kind == 1 or kind == 4) polygons = intersection else {
        const difference = rings.assemble(graph.traverse(true, false));
        if (kind == 3) {
            const reverse_graph = gh.Graph.init(second.rings, first.rings);
            const reverse_difference = rings.assemble(reverse_graph.traverse(true, false));
            const combined = r.alloc(Sequence, difference.len + reverse_difference.len);
            @memcpy(combined[0..difference.len], difference);
            @memcpy(combined[difference.len..], reverse_difference);
            std.mem.sort(Sequence, combined, {}, struct {
                fn less(_: void, a: Sequence, b: Sequence) bool {
                    return r.pointLess({}, a[0][0], b[0][0]);
                }
            }.less);
            polygons = combined;
        } else polygons = difference;
    }
    const relation = if (graph.crossings.len > 0) "overlap" else if (graph.n_a == first.rings.len and graph.n_b == 0) "within" else if (graph.n_b == second.rings.len and graph.n_a == 0) "contains" else if (graph.n_a == 0 and graph.n_b == 0) "disjoint" else "overlap";
    return .{ .region = .{ .polygons = polygons, .operands = .{ first, second } }, .graph = graph,
         .relation = relation, .iou = totalArea(intersection) / totalArea(union_result) };
}
fn cyclicEqual(first: Ring, second: Ring) bool {
    if (first.len != second.len) return false;
    for (second, 0..) |point, start| {
        if (!point.same(first[0])) continue;
        var equal = true;
        for (first, 0..) |p, index| equal = equal and p.same(second[(start + index) % second.len]);
        if (equal) return true;
    }
    return false;
}
const Crosscheck = struct { matches: bool, count: usize, vertices: usize };
fn crosscheckClip(first: *const Polygon, window: *const Polygon, polygons: Polygons) Crosscheck {
    var clipped: std.ArrayList(Ring) = .empty;
    for (first.rings) |ring| {
        var points = ring;
        for (window.rings[0], 0..) |edge_start, edge| {
            const edge_end = window.rings[0][(edge + 1) % window.rings[0].len];
            var replacement: std.ArrayList(r.Point) = .empty;
            for (points, 0..) |current, index| {
                const previous = points[(index + points.len - 1) % points.len];
                const a = r.cross(edge_start, edge_end, previous);
                const b = r.cross(edge_start, edge_end, current);
                if ((a.numerator > 0) != (b.numerator > 0)) r.append(r.Point, &replacement,
                     i.clippingPoint(previous, current, a, b));
                if (b.numerator > 0) r.append(r.Point, &replacement, current);
            }
            points = replacement.items;
        }
        var deduplicated: std.ArrayList(r.Point) = .empty;
        for (points, 0..) |point, index| if (!point.same(points[(index + points.len - 1) % points.len])) r.append(r.Point,
             &deduplicated, point);
        if (deduplicated.items.len >= 3) r.append(Ring, &clipped, deduplicated.items);
    }
    var result_count: usize = 0;
    var matches = true;
    for (polygons) |polygon| for (polygon) |ring| {
        result_count += 1;
        var found = false;
        for (clipped.items) |other| found = found or cyclicEqual(ring, other);
        matches = matches and found;
    };
    var vertices: usize = 0;
    for (clipped.items) |ring| vertices += ring.len;
    return .{ .matches = matches and result_count == clipped.items.len, .count = clipped.items.len,
         .vertices = vertices };
}
const RingItem = struct { polygon: usize, hole: usize, ring: Ring, area: f64 };
const Values = struct {
    polygon_count: usize,
    items: []const RingItem,
    ring_count: usize,
    hole_count: usize,
    vertex_count: usize,
    area: f64,
    perimeter: f64,
    origins: [3]usize,
    low: ?r.Point,
    high: ?r.Point,
    centroid: ?[2]f64,
    fn init(polygons: Polygons, first: *const Polygon, second: ?*const Polygon) Values {
        var first_vertices: std.AutoHashMapUnmanaged(r.Point, void) = .empty;
        var second_vertices: std.AutoHashMapUnmanaged(r.Point, void) = .empty;
        for (first.rings) |ring| for (ring) |point| first_vertices.put(r.allocator, point,
             {}) catch @panic("allocation failed");
        if (second) |other| for (other.rings) |ring| for (ring) |point| second_vertices.put(r.allocator,
             point, {}) catch @panic("allocation failed");
        var items: std.ArrayList(RingItem) = .empty;
        var area: f64 = 0;
        var perimeter: f64 = 0;
        var origins: [3]usize = @splat(0);
        var vertex_count: usize = 0;
        var low: ?r.Point = null;
        var high: ?r.Point = null;
        var sx: f64 = 0;
        var sy: f64 = 0;
        for (polygons, 1..) |polygon, number| for (polygon, 0..) |ring, hole| {
            const ring_area = rings.area(ring);
            area += ring_area;
            perimeter += rings.perimeter(ring);
            r.append(RingItem, &items, .{ .polygon = number, .hole = hole, .ring = ring, .area = ring_area });
            vertex_count += ring.len;
            for (ring, 0..) |point, index| {
                const next = ring[(index + 1) % ring.len];
                origins[if (first_vertices.contains(point)) @as(usize, 0) else if (second_vertices.contains(point)) 1 else 2] += 1;
                const x1 = point.x.real();
                const y1 = point.y.real();
                const x2 = next.x.real();
                const y2 = next.y.real();
                const cross = x1 * y2 - x2 * y1;
                sx += (x1 + x2) * cross;
                sy += (y1 + y2) * cross;
                if (low == null) {
                    low = point;
                    high = point;
                } else {
                    if (point.x.less(low.?.x)) low.?.x = point.x;
                    if (point.y.less(low.?.y)) low.?.y = point.y;
                    if (high.?.x.less(point.x)) high.?.x = point.x;
                    if (high.?.y.less(point.y)) high.?.y = point.y;
                }
            }
        };
        return .{ .polygon_count = polygons.len, .items = items.items, .ring_count = items.items.len,
             .hole_count = items.items.len - polygons.len, .vertex_count = vertex_count, .area = area,
             .perimeter = perimeter, .origins = origins, .low = low, .high = high, .centroid = if (vertex_count > 0) .{ sx / (6.0 * area),
             sy / (6.0 * area) } else null };
    }
    fn lines(self: Values) r.Lines {
        var out: r.Lines = .{};
        out.add("polygons {d} rings {d} holes {d} vertices {d} area {d:.3}", .{ self.polygon_count,
             self.ring_count, self.hole_count, self.vertex_count, self.area });
        for (self.items) |item| {
            var line: r.Text = .{};
            if (item.hole == 0) line.add("outer {d}", .{item.polygon}) else line.add("hole {d} {d}",
                 .{ item.polygon, item.hole });
            line.add(" {d} {d:.3}", .{ item.ring.len, item.area });
            for (item.ring) |point| line.add(" {s}", .{point.text()});
            out.add("{s}", .{line.value()});
        }
        if (self.low) |low| {
            out.add("bbox {s} {s}", .{ low.text(), self.high.?.text() });
            out.add("centroid ({d:.3},{d:.3})", .{ self.centroid.?[0], self.centroid.?[1] });
        } else {
            out.add("bbox none", .{});
            out.add("centroid none", .{});
        }
        out.add("perimeter {d:.3}", .{self.perimeter});
        out.add("origins a {d} b {d} crossing {d}", .{ self.origins[0], self.origins[1], self.origins[2] });
        return out;
    }
};
fn exactDoubleArea(ring: Ring) r.Integer {
    var area: r.Integer = 0;
    for (ring, 0..) |first, index| {
        const second = ring[(index + 1) % ring.len];
        area += first.x.numerator * second.y.numerator - second.x.numerator * first.y.numerator;
    }
    return area;
}
fn convexHull(outer: Ring) Ring {
    const ordered = r.dupe(r.Point, outer);
    std.mem.sort(r.Point, ordered, {}, struct {
        fn less(_: void, a: r.Point, b: r.Point) bool {
            return if (a.x.same(b.x)) a.y.less(b.y) else a.x.less(b.x);
        }
    }.less);
    var chains: [2]std.ArrayList(r.Point) = @splat(.empty);
    for (0..2) |side| for (0..ordered.len) |index| {
        const point = ordered[if (side == 0) index else ordered.len - 1 - index];
        const chain = &chains[side];
        while (chain.items.len >= 2 and r.cross(chain.items[chain.items.len - 2], chain.items[chain.items.len - 1],
             point).numerator <= 0) _ = chain.pop();
        r.append(r.Point, chain, point);
    };
    const out = r.alloc(r.Point, chains[0].items.len + chains[1].items.len - 2);
    @memcpy(out[0 .. chains[0].items.len - 1], chains[0].items[0 .. chains[0].items.len - 1]);
    @memcpy(out[chains[0].items.len - 1 ..], chains[1].items[0 .. chains[1].items.len - 1]);
    return out;
}
fn propertyLines(polygon: *const Polygon, area: f64) r.Lines {
    var out: r.Lines = .{};
    var input: r.Text = .{};
    input.add("input", .{});
    for (polygon.input_rings) |ring| input.add(" {s}", .{if (exactDoubleArea(ring) > 0) "ccw" else "cw"});
    out.add("{s}", .{input.value()});
    var reflex: usize = 0;
    for (polygon.rings) |ring| for (ring, 0..) |point, index| if (r.cross(ring[(index + ring.len - 1) % ring.len],
         point, ring[(index + 1) % ring.len]).numerator < 0) {
        reflex += 1;
    };
    const hull = convexHull(polygon.rings[0]);
    const hull_area = r.Fraction.init(exactDoubleArea(hull), 2).real();
    out.add("reflex {d}", .{reflex});
    out.add("hull {d} {d:.3} solidity {d:.6}", .{ hull.len, hull_area, area / hull_area });
    return out;
}
fn locate(polygons: Polygons, point: r.Point) []const u8 {
    for (polygons, 1..) |polygon, number| {
        if (rings.boundary(polygon[0], point)) return r.fmt("boundary outer {d}", .{number});
        for (polygon[1..], 1..) |hole, index| if (rings.boundary(hole, point)) return r.fmt("boundary hole {d} {d}",
             .{ number, index });
    }
    for (polygons, 1..) |polygon, number| {
        if (!rings.inside(polygon[0], point)) continue;
        var in_hole = false;
        for (polygon[1..]) |hole| in_hole = in_hole or rings.inside(hole, point);
        if (!in_hole) return r.fmt("inside polygon {d}", .{number});
    }
    return "outside";
}
fn operandLocation(polygon: *const Polygon, point: r.Point) []const u8 {
    for (polygon.rings) |ring| if (rings.boundary(ring, point)) return "boundary";
    return if (rings.interior(polygon.rings, point)) "inside" else "outside";
}
fn write(io: std.Io, name: []const u8, lines: r.Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: r.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = r.fmt("output/{s}", .{name}), .data = out.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    r.allocator = arena.allocator();
    var registry = try Registry.read(init.io);
    const operations = try records(init.io, "operations.txt");
    const regions = r.zero(?Region, operations.len + 1, null);
    var results: r.Lines = .{};
    var areas: r.Lines = .{};
    areas.add("operation,rings,holes,vertices,area", .{});
    var drawings: r.Lines = .{};
    var rejected: r.Lines = .{};
    var totals: [12]usize = @splat(0);
    var succeeded_kinds: [12]usize = @splat(0);
    var succeeded: usize = 0;
    var defined: usize = 0;
    var crossings: usize = 0;
    for (operations, 1..) |record, number| {
        const persistent = r.allocator;
        var work: std.heap.ArenaAllocator = .init(init.gpa);
        defer work.deinit();
        r.allocator = work.allocator();
        const words = r.words(record.line);
        if (kindIndex(words[0])) |kind| totals[kind] += 1;
        const checked = checkOperation(&registry, regions, words);
        if (checked.error_message) |message| {
            r.allocator = persistent;
            rejected.add("op {d} {s}", .{ number, message });
            continue;
        }
        const kind = checked.kind;
        succeeded += 1;
        succeeded_kinds[kind] += 1;
        var local_results: r.Lines = .{};
        var local_areas: r.Lines = .{};
        var local_drawings: r.Lines = .{};
        var output_region: ?Region = null;
        if (kind == 11) {
            const target = checked.target.?;
            const operands: ?[2]Sequence = if (target.operands) |pair| .{ pair[0].rings, pair[1].rings } else null;
            const drawing = render.grid(target.polygons, operands, r.number(words[2]), r.number(words[3]),
                 r.number(words[4]), r.number(words[5]), r.u(r.number(words[6])), r.u(r.number(words[7])));
            local_drawings.add("render {d} {s} cols {d} rows {d} result {d} a {d} b {d} both {d}",
                 .{ number, words[1], r.number(words[6]), r.number(words[7]), drawing.counts[0],
                 drawing.counts[1], drawing.counts[2], drawing.counts[3] });
            local_drawings.extend(drawing.lines);
        } else if (kind == 10) {
            const target = checked.target.?;
            const point = r.Point.init(r.number(words[2]), r.number(words[3]));
            local_results.add("op {d} {s}", .{ number, record.line });
            local_results.add("location {s}", .{locate(target.polygons, point)});
            if (target.operands) |pair| local_results.add("operands a {s} b {s}", .{ operandLocation(pair[0],
                 point), operandLocation(pair[1], point) });
        } else {
            local_results.add("op {d} {s}", .{ number, record.line });
            var first: *const Polygon = undefined;
            var second: ?*const Polygon = null;
            var region: Region = undefined;
            if (kind < 5) {
                first = checked.first.?;
                second = checked.second.?;
                const binary = binaryResult(kind, first, second.?);
                region = binary.region;
                local_results.add("relation {s} iou {d:.6}", .{ binary.relation, binary.iou });
                local_results.add("crossings {d}", .{binary.graph.crossings.len});
                crossings += binary.graph.crossings.len;
                for (binary.graph.crossings) |crossing| local_results.add("crossing {s} {s}",
                     .{ crossing.point.text(), if (crossing.first.entering) "in" else "out" });
            } else {
                first = if (definition(kind)) checked.defined.? else checked.first.?;
                region = singleRegion(first);
            }
            const values = Values.init(region.polygons, first, second);
            local_results.extend(values.lines());
            if (kind >= 5) local_results.extend(propertyLines(first, values.area));
            if (kind == 4) {
                const crosscheck = crosscheckClip(first, second.?, region.polygons);
                local_results.add("crosscheck {s} rings {d} vertices {d}", .{ if (crosscheck.matches) "match" else "mismatch",
                     crosscheck.count, crosscheck.vertices });
            }
            local_areas.add("{d}:{s},{d},{d},{d},{d:.3}", .{ number, r.join(words, ":"), values.ring_count,
                 values.hole_count, values.vertex_count, values.area });
            output_region = region;
        }
        r.allocator = persistent;
        results.extend(local_results);
        areas.extend(local_areas);
        drawings.extend(local_drawings);
        if (output_region) |region| regions[number] = copyRegion(region);
        if (checked.defined) |polygon| {
            const copy = Polygon.init(polygon.name, copySequence(polygon.input_rings));
            registry.polygons.put(r.allocator, copy.name, copy) catch @panic("allocation failed");
            defined += 1;
        }
    }
    results.add("summary polygons {d} valid {d} invalid {d} defined {d}", .{ registry.block_count,
         registry.valid_blocks, registry.invalid.data.items.len, defined });
    results.add("summary operations {d} succeeded {d} rejected {d}", .{ operations.len, succeeded,
         rejected.data.items.len });
    results.add("summary crossings {d}", .{crossings});
    for (kinds, totals, succeeded_kinds) |kind, total, accepted| results.add("kind {s} {d} {d}",
         .{ kind, total, accepted });
    var rejections: r.Lines = .{};
    rejections.add("rejections {d}", .{registry.invalid.data.items.len + rejected.data.items.len});
    rejections.extend(registry.invalid);
    rejections.extend(rejected);
    try write(init.io, "results.txt", results);
    try write(init.io, "areas.csv", areas);
    try write(init.io, "render.txt", drawings);
    try write(init.io, "rejections.txt", rejections);
}
