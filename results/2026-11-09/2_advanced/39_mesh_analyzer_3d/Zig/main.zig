const std = @import("std");
const c = @import("obj_io.zig");
const topology_module = @import("topology.zig");
const orientation = @import("orientation.zig");
const m = @import("measure.zig");
const repair = @import("repair.zig");
fn yes(value: bool) []const u8 {
    return if (value) "yes" else "no";
}
fn addNumber(lines: *c.Lines, name: []const u8, value: anytype) void {
    lines.add("{s} {d}", .{ name, value });
}
fn addText(lines: *c.Lines, name: []const u8, value: []const u8) void {
    lines.add("{s} {s}", .{ name, value });
}
fn readOptions(io: std.Io) !c.Options {
    var out: c.Options = .{};
    for (try c.readLines(io, "input/params.txt")) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const tokens = c.words(line);
        const name = tokens[0];
        if (c.eq(name, "snap")) out.snap = c.number(tokens[1]) else if (c.eq(name, "fill_holes")) out.fill_holes = c.u(c.number(tokens[1])) else if (c.eq(name,
             "sections")) out.sections = tokens[1..] else if (c.eq(name, "query")) c.append([]const []const u8,
             &out.queries, tokens[1..]) else {
            inline for (.{ "merge", "degenerate", "duplicates", "orient", "outward", "keep_unused" }) |field| if (c.eq(name,
                 field)) {
                @field(out, field) = c.eq(tokens[1], "on");
            };
        }
    }
    return out;
}
const Properties = struct { boundary: usize = 0, nonmanifold: usize = 0, loops: usize = 0, inconsistent: usize = 0,
     closed: bool = false, manifold: bool = false, consistent: bool = false, solid: bool = false,
     orientable: bool = true, euler: i64 = 0, genus: i64 = 0, crosscaps: i64 = 0, volume6: i64 = 0,
     normal_sum: c.Point = .{ 0, 0, 0 }, minimum: c.Point = .{ 0, 0, 0 }, maximum: c.Point = .{ 0,
     0, 0 }, inside: std.ArrayList(usize) = .empty };
fn properties(faces: []const c.Face, points: []const c.Point, topology: topology_module.Topology) []Properties {
    const out = c.alloc(Properties, topology.component_faces.len);
    @memset(out, .{});
    for (orientation.inconsistent(faces, topology)) |e| out[topology.face_component[topology.edges[e].faces.items[0]]].inconsistent += 1;
    for (topology_module.traceLoops(topology).items) |loop| out[loop.component].loops += 1;
    for (out, 0..) |*prop, component| {
        for (topology.component_edges[component]) |e| {
            const count = topology.edges[e].faces.items.len;
            if (count == 1) prop.boundary += 1 else if (count >= 3) prop.nonmanifold += 1;
        }
        prop.closed = prop.boundary == 0;
        prop.manifold = prop.nonmanifold == 0 and topology.component_nonmanifold_vertices[component].len == 0;
        prop.consistent = prop.inconsistent == 0;
        prop.solid = prop.closed and prop.manifold and prop.consistent;
        prop.euler = c.n(topology.component_vertices[component].len) - c.n(topology.component_edges[component].len) + c.n(topology.component_faces[component].len);
        prop.minimum = points[topology.component_vertices[component][0]];
        prop.maximum = prop.minimum;
        for (topology.component_vertices[component]) |vertex| for (0..3) |axis| {
            prop.minimum[axis] = @min(prop.minimum[axis], points[vertex][axis]);
            prop.maximum[axis] = @max(prop.maximum[axis], points[vertex][axis]);
        };
        for (topology.component_faces[component]) |f| {
            prop.volume6 += m.determinant(faces[f], points);
            const normal = m.normal(faces[f], points);
            for (0..3) |axis| prop.normal_sum[axis] += normal[axis];
        }
    }
    return out;
}
fn edgeShape(edge: topology_module.Edge, faces: []const c.Face, points: []const c.Point) []const u8 {
    if (edge.faces.items.len != 2) return "-";
    const f = faces[edge.faces.items[0]];
    const g = faces[edge.faces.items[1]];
    if (orientation.directed(f, edge.a, edge.b) == orientation.directed(g, edge.a, edge.b)) return "inconsistent";
    var vertex: usize = 0;
    for (g.vertices) |candidate| if (candidate != edge.a and candidate != edge.b) {
        vertex = candidate;
    };
    const side = m.dot(m.difference(points[vertex], points[f.vertices[0]]), m.normal(f, points));
    return if (side < 0) "convex" else if (side > 0) "concave" else "flat";
}
fn length2(edge: topology_module.Edge, points: []const c.Point) i64 {
    const difference = m.difference(points[edge.a], points[edge.b]);
    return m.dot(difference, difference);
}
fn boundaries(loops: []topology_module.Loop, topology: topology_module.Topology, faces: []const c.Face,
     options: c.Options) c.Lines {
    const inconsistent = orientation.inconsistent(faces, topology);
    const bad = c.alloc(bool, topology.component_faces.len);
    @memset(bad, false);
    for (topology.edges) |edge| if (edge.faces.items.len >= 3) {
        bad[topology.face_component[edge.faces.items[0]]] = true;
    };
    for (inconsistent) |e| bad[topology.face_component[topology.edges[e].faces.items[0]]] = true;
    for (loops) |*loop| {
        if (loop.closed) {
            var forwards: usize = 0;
            for (loop.vertices.items, 0..) |a, i| {
                const b = loop.vertices.items[(i + 1) % loop.vertices.items.len];
                const edge = topology.edges[topology_module.edgeIndex(topology, a, b).?];
                forwards += @intFromBool(orientation.directed(faces[edge.faces.items[0]], a, b));
            }
            if (forwards == 0 or forwards == loop.vertices.items.len) {
                loop.kind = "coherent";
                if (forwards == 0) std.mem.reverse(usize, loop.vertices.items[1..]);
            } else loop.kind = "mixed";
        }
        var distinct = true;
        for (loop.vertices.items, 0..) |vertex, i| if (topology_module.contains(loop.vertices.items[i + 1 ..], vertex)) {
            distinct = false;
        };
        loop.filled = c.eq(loop.kind, "coherent") and loop.length() >= 3 and loop.length() <= options.fill_holes and distinct and !bad[loop.component];
    }
    var lines: c.Lines = .{};
    addNumber(&lines, "loops", loops.len);
    for (loops, 1..) |loop, i| lines.add("loop {d} component {d} length {d} {s} {s} vertices {s}",
         .{ i, loop.component + 1, loop.length(), loop.kind, if (loop.filled) "filled" else "kept",
         c.list(loop.vertices.items, 0) });
    var nonmanifold: usize = 0;
    for (topology.edges) |edge| if (edge.faces.items.len >= 3) {
        nonmanifold += 1;
    };
    addNumber(&lines, "nonmanifold_edges", nonmanifold);
    for (topology.edges) |edge| if (edge.faces.items.len >= 3) lines.add("edge {d} {d} faces {s}",
         .{ edge.a, edge.b, c.list(edge.faces.items, 1) });
    var vertices: usize = 0;
    for (topology.fans) |fans| if (fans >= 2) {
        vertices += 1;
    };
    addNumber(&lines, "nonmanifold_vertices", vertices);
    for (topology.fans, 0..) |fans, vertex| if (fans >= 2) lines.add("vertex {d} fans {d} components {s}",
         .{ vertex, fans, c.list(topology.fan_components[vertex], 1) });
    addNumber(&lines, "inconsistent_edges", inconsistent.len);
    for (inconsistent) |e| {
        const edge = topology.edges[e];
        lines.add("edge {d} {d} faces {s}", .{ edge.a, edge.b, c.list(edge.faces.items, 1) });
    }
    return lines;
}
fn nonplanar(object: c.Object, clean: repair.Cleanup) []bool {
    const out = c.alloc(bool, object.polygons.items.len);
    @memset(out, false);
    for (object.polygons.items, 0..) |polygon, p| {
        var sum: c.Point = .{ 0, 0, 0 };
        const first = clean.snapped[polygon.vertices[0]];
        var i: usize = 1;
        while (i + 1 < polygon.vertices.len) : (i += 1) {
            const term = m.cross(m.difference(clean.snapped[polygon.vertices[i]], first), m.difference(clean.snapped[polygon.vertices[i + 1]],
                 first));
            for (0..3) |axis| sum[axis] += term[axis];
        }
        for (polygon.vertices) |vertex| if (m.dot(m.difference(clean.snapped[vertex], first), sum) != 0) {
            out[p] = true;
        };
    }
    return out;
}
fn groupNames(face_ids: []const usize, faces: []const c.Face, groups: []const []const u8) []const u8 {
    const used = c.alloc(bool, groups.len);
    @memset(used, false);
    for (face_ids) |index| used[faces[index].group] = true;
    var out: c.Text = .{};
    for (groups, used) |group, included| if (included) out.add("{s}{s}", .{ if (out.value().len == 0) "" else " ", group });
    return if (out.value().len == 0) "-" else out.value();
}
fn queryAnswer(query: []const []const u8, faces: []const c.Face, points: []const c.Point, topology: topology_module.Topology,
     props: []const Properties, groups: []const []const u8) []const u8 {
    const kind = query[0];
    var args: [3]i64 = .{ 0, 0, 0 };
    for (query[1..], 0..) |value, i| args[i] = c.number(value);
    if (c.eq(kind, "vertex")) {
        const v = args[0];
        if (v < 1 or v >= c.n(points.len)) return c.fmt("vertex {d} invalid", .{v});
        const vertex = c.u(v);
        var boundary = false;
        for (topology.vertex_edges[vertex]) |e| if (topology.edges[e].faces.items.len == 1) {
            boundary = true;
        };
        return c.fmt("vertex {d} at {s} faces {d} valence {d} fans {d} boundary {s} components {s}",
             .{ v, m.pointText(points[vertex]), topology.vertex_faces[vertex].len, topology.vertex_edges[vertex].len,
             topology.fans[vertex], yes(boundary), c.list(topology.fan_components[vertex], 1) });
    }
    if (c.eq(kind, "face")) {
        const f = args[0];
        if (f < 1 or f > c.n(faces.len)) return c.fmt("face {d} invalid", .{f});
        const index = c.u(f - 1);
        const face = faces[index];
        var neighbors: c.Text = .{};
        for (face.vertices, 0..) |a, i| {
            const edge = topology.edges[topology_module.edgeIndex(topology, a, face.vertices[(i + 1) % 3]).?];
            const other = if (edge.faces.items.len == 1) "-" else if (edge.faces.items.len >= 3) "*" else c.fmt("{d}",
                 .{(if (edge.faces.items[0] == index) edge.faces.items[1] else edge.faces.items[0]) + 1});
            neighbors.add("{s}{s}", .{ if (i == 0) "" else " ", other });
        }
        const normal = m.normal(face, points);
        return c.fmt("face {d} vertices {d} {d} {d} group {s} polygon {s} line {s} component {d} normal {s} area {s} neighbors {s}",
             .{ f, face.vertices[0], face.vertices[1], face.vertices[2], groups[face.group], if (face.polygon == 0) "-" else c.fmt("{d}",
             .{face.polygon}), if (face.line == 0) "-" else c.fmt("{d}", .{face.line}), topology.face_component[index] + 1,
             m.pointText(normal), m.real(@sqrt(@as(f64, @floatFromInt(m.dot(normal, normal)))) / 2),
             neighbors.value() });
    }
    if (c.eq(kind, "edge")) {
        const a = @min(args[0], args[1]);
        const b = @max(args[0], args[1]);
        const index = if (a < 0 or b < 0) null else topology_module.edgeIndex(topology, c.u(a), c.u(b));
        if (index == null) return c.fmt("edge {d} {d} none", .{ a, b });
        const edge = topology.edges[index.?];
        return c.fmt("edge {d} {d} faces {s} kind {s} shape {s} len2 {d}", .{ a, b, c.list(edge.faces.items,
             1), if (edge.faces.items.len == 1) "boundary" else if (edge.faces.items.len == 2) "manifold" else "nonmanifold",
             edgeShape(edge, faces, points), length2(edge, points) });
    }
    if (c.eq(kind, "point")) {
        const point: c.Point = args;
        var inside: std.ArrayList(usize) = .empty;
        var sum: i64 = 0;
        for (props, 0..) |prop, component| if (prop.solid) {
            const winding = m.winding(point, topology.component_faces[component], faces, points);
            if (winding != 0) {
                c.append(usize, &inside, component + 1);
                sum += winding;
            }
        };
        return c.fmt("point {s} inside {s} winding {d}", .{ m.pointText(point), c.list(inside.items, 0), sum });
    }
    if (c.eq(kind, "path")) {
        const u = args[0];
        const v = args[1];
        if (u < 1 or u >= c.n(points.len) or v < 1 or v >= c.n(points.len)) return c.fmt("path {d} {d} invalid", .{ u, v });
        const parents = c.alloc(?usize, points.len);
        @memset(parents, null);
        var queue: std.ArrayList(usize) = .empty;
        c.append(usize, &queue, c.u(u));
        parents[c.u(u)] = c.u(u);
        var position: usize = 0;
        while (position < queue.items.len) : (position += 1) {
            const at = queue.items[position];
            for (topology.neighbors[at]) |next| if (parents[next] == null) {
                parents[next] = at;
                c.append(usize, &queue, next);
            };
        }
        if (parents[c.u(v)] == null) return c.fmt("path {d} {d} none", .{ u, v });
        var path: std.ArrayList(usize) = .empty;
        var at = c.u(v);
        while (at != c.u(u)) {
            c.append(usize, &path, at);
            at = parents[at].?;
        }
        c.append(usize, &path, c.u(u));
        std.mem.reverse(usize, path.items);
        return c.fmt("path {d} {d} hops {d} vertices {s}", .{ u, v, path.items.len - 1, c.list(path.items, 0) });
    }
    const direction: c.Point = args;
    const signs = c.alloc(i64, faces.len);
    var front: usize = 0;
    var back: usize = 0;
    var side: usize = 0;
    var silhouette: usize = 0;
    for (faces, signs) |face, *sign| {
        sign.* = m.dot(m.normal(face, points), direction);
        front += @intFromBool(sign.* > 0);
        back += @intFromBool(sign.* < 0);
        side += @intFromBool(sign.* == 0);
    }
    for (topology.edges) |edge| if (edge.faces.items.len == 2) {
        const a = signs[edge.faces.items[0]];
        const b = signs[edge.faces.items[1]];
        if ((a > 0 and b < 0) or (a < 0 and b > 0)) silhouette += 1;
    };
    return c.fmt("view {s} front {d} back {d} side {d} silhouette {d}", .{ m.pointText(direction),
         front, back, side, silhouette });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const options = try readOptions(init.io);
    const object = try c.readObject(init.io);
    var clean = repair.cleanup(object, options);
    const initial = c.dupe(c.Face, clean.faces.items);
    const before = topology_module.analyze(clean.faces.items, clean.points.items.len - 1);
    const inconsistent_before = orientation.inconsistent(clean.faces.items, before).len;
    if (options.orient) orientation.orient(clean.faces.items, before);
    const loops = topology_module.traceLoops(before);
    try c.write(init.io, "boundaries.txt", boundaries(loops.items, before, clean.faces.items, options));
    var groups: std.ArrayList([]const u8) = .empty;
    for (object.groups.items) |group| c.append([]const u8, &groups, group);
    var holes: usize = 0;
    for (loops.items) |loop| if (loop.filled) {
        holes += 1;
        repair.fillFaces(&clean.faces, loop, object.groups.items.len);
    };
    if (holes > 0) c.append([]const u8, &groups, "fill");
    const fill_count = clean.faces.items.len - initial.len;
    const points = clean.points.items;
    const faces = clean.faces.items;
    const topology = topology_module.analyze(faces, points.len - 1);
    const props = properties(faces, points, topology);
    for (props, 0..) |*prop, component| if (prop.solid) {
        for (props, 0..) |other, other_index| if (component != other_index and other.solid) {
            var vertex: ?usize = null;
            for (topology.component_vertices[component]) |candidate| if (!topology_module.contains(topology.component_vertices[other_index],
                 candidate)) {
                vertex = candidate;
                break;
            };
            if (vertex != null and m.winding(points[vertex.?], topology.component_faces[other_index],
                 faces, points) != 0) c.append(usize, &prop.inside, other_index + 1);
        };
    };
    var outward: usize = 0;
    for (props, 0..) |*prop, component| if (options.outward and prop.solid and prop.volume6 != 0 and ((prop.inside.items.len % 2 == 0 and prop.volume6 < 0) or (prop.inside.items.len % 2 == 1 and prop.volume6 > 0))) {
        outward += 1;
        for (topology.component_faces[component]) |index| orientation.flip(&faces[index]);
        prop.volume6 = -prop.volume6;
        for (&prop.normal_sum) |*value| value.* = -value.*;
    };
    const copy = c.dupe(c.Face, faces);
    orientation.orient(copy, topology);
    for (orientation.inconsistent(copy, topology)) |e| props[topology.face_component[topology.edges[e].faces.items[0]]].orientable = false;
    for (props) |*prop| {
        prop.crosscaps = 2 - prop.euler - c.n(prop.loops);
        prop.genus = @divTrunc(prop.crosscaps, 2);
    }
    var flipped: usize = 0;
    for (initial, faces[0..initial.len]) |a, b| if (!std.mem.eql(usize, &a.vertices, &b.vertices)) {
        flipped += 1;
    };
    const nonplanar_polygons = nonplanar(object, clean);
    var nonplanar_count: usize = 0;
    for (nonplanar_polygons) |bad| nonplanar_count += @intFromBool(bad);
    const all_faces = c.alloc(usize, faces.len);
    for (all_faces, 0..) |*value, index| value.* = index;
    var total_volume: i64 = 0;
    var solids: usize = 0;
    for (props) |prop| if (prop.solid) {
        solids += 1;
        total_volume += prop.volume6;
    };
    var report: c.Lines = .{};
    for (options.sections) |section| {
        if (c.eq(section, "summary")) {
            report.add("[summary]", .{});
            addNumber(&report, "lines", object.lines);
            addNumber(&report, "vertices", object.vertices.items.len - 1);
            addNumber(&report, "polygons", object.polygons.items.len);
            addNumber(&report, "errors", object.errors.items.len);
            addNumber(&report, "ignored", object.ignored);
            addNumber(&report, "nonplanar_polygons", nonplanar_count);
            var sizes = std.mem.zeroes([201]usize);
            for (object.polygons.items) |polygon| sizes[polygon.vertices.len] += 1;
            for (sizes, 0..) |count, size| if (count > 0) report.add("polygon_size {d} {d}", .{ size, count });
            var removed = std.mem.zeroes([3]usize);
            for (clean.removed.items) |item| removed[
                if (c.eq(item.reason, "repeated")) 0 else if (c.eq(item.reason, "zero_area")) 1 else 2
            ] += 1;
            addNumber(&report, "triangles", clean.triangles);
            addNumber(&report, "snapped", clean.snapped_count);
            addNumber(&report, "merged", clean.merged_count);
            addNumber(&report, "removed_repeated", removed[0]);
            addNumber(&report, "removed_zero_area", removed[1]);
            addNumber(&report, "removed_duplicate", removed[2]);
            addNumber(&report, "faces", initial.len);
            addNumber(&report, "inconsistent_before", inconsistent_before);
            addNumber(&report, "flipped_faces", flipped);
            addNumber(&report, "outward_components", outward);
            addNumber(&report, "boundary_loops", loops.items.len);
            addNumber(&report, "holes_filled", holes);
            addNumber(&report, "fill_faces", fill_count);
            addNumber(&report, "final_vertices", points.len - 1);
            addNumber(&report, "final_faces", faces.len);
            addNumber(&report, "components", props.len);
            addNumber(&report, "solids", solids);
            addText(&report, "total_area", m.real(m.area(all_faces, faces, points)));
            addText(&report, "total_volume", m.fraction(total_volume, 6));
        } else if (c.eq(section, "warnings")) {
            report.add("[warnings]", .{});
            for (object.errors.items) |err| report.add("line {d} {s}", .{ err.line, err.kind });
        } else if (c.eq(section, "cleanup")) {
            report.add("[cleanup]", .{});
            addNumber(&report, "snapped", clean.snapped_count);
            for (1..object.vertices.items.len) |vertex| if (!std.mem.eql(i64, &object.vertices.items[vertex],
                 &clean.snapped[vertex])) report.add("snap {d} {s} to {s}", .{ vertex, m.pointText(object.vertices.items[vertex]),
                 m.pointText(clean.snapped[vertex]) });
            addNumber(&report, "merged", clean.merged_count);
            for (1..clean.representative.len) |representative| if (clean.representative[representative] == representative) {
                var members: std.ArrayList(usize) = .empty;
                for (1..clean.representative.len) |vertex| if (clean.representative[vertex] == representative) c.append(usize,
                     &members, vertex);
                if (members.items.len > 1) report.add("merge {s} {s}", .{ if (clean.new_number[representative] == 0) "-" else c.fmt("{d}",
                     .{clean.new_number[representative]}), c.list(members.items, 0) });
            };
            addNumber(&report, "removed", clean.removed.items.len);
            for (clean.removed.items) |removed| report.add("remove {d} polygon {d} line {d} {s}",
                 .{ removed.triangle, removed.polygon, removed.line, removed.reason });
        } else if (c.eq(section, "components")) {
            for (props, 0..) |prop, component| {
                report.add("[component {d}]", .{component + 1});
                addText(&report, "groups", groupNames(topology.component_faces[component], faces, groups.items));
                addNumber(&report, "faces", topology.component_faces[component].len);
                addNumber(&report, "vertices", topology.component_vertices[component].len);
                addNumber(&report, "edges", topology.component_edges[component].len);
                addNumber(&report, "boundary_edges", prop.boundary);
                addNumber(&report, "nonmanifold_edges", prop.nonmanifold);
                addNumber(&report, "nonmanifold_vertices", topology.component_nonmanifold_vertices[component].len);
                addNumber(&report, "boundary_loops", prop.loops);
                inline for (.{ "closed", "manifold", "orientable", "consistent", "solid" }) |name| addText(&report,
                     name, yes(@field(prop, name)));
                addNumber(&report, "euler", prop.euler);
                if (!prop.manifold) addText(&report, "genus", "-") else if (prop.orientable) addNumber(&report,
                     "genus", prop.genus) else addNumber(&report, "crosscaps", prop.crosscaps);
                addText(&report, "volume", if (prop.solid) m.fraction(prop.volume6, 6) else "-");
                addText(&report, "area", m.real(m.area(topology.component_faces[component], faces, points)));
                addText(&report, "normal_sum", m.pointText(prop.normal_sum));
                report.add("bbox {s} {s}", .{ m.pointText(prop.minimum), m.pointText(prop.maximum) });
                addText(&report, "inside", if (prop.solid) c.list(prop.inside.items, 0) else "-");
                addText(&report, "centroid", if (prop.solid and prop.volume6 != 0) m.centroid(topology.component_faces[component],
                     faces, points, prop.volume6) else "-");
                var shapes = std.mem.zeroes([3]usize);
                var angles = std.mem.zeroes([3]usize);
                var shortest: i64 = -1;
                var longest: i64 = 0;
                const degrees = c.alloc(usize, points.len);
                @memset(degrees, 0);
                for (topology.component_edges[component]) |e| {
                    const edge = topology.edges[e];
                    const shape = edgeShape(edge, faces, points);
                    for ([_][]const u8{ "convex", "concave", "flat" }, 0..) |name, i| if (c.eq(name, shape)) {
                        shapes[i] += 1;
                    };
                    const length = length2(edge, points);
                    if (shortest < 0 or length < shortest) shortest = length;
                    longest = @max(longest, length);
                    degrees[edge.a] += 1;
                    degrees[edge.b] += 1;
                }
                for (topology.component_faces[component]) |index| {
                    const angle = m.triangleAngle(faces[index], points);
                    angles[if (c.eq(angle, "acute")) 0 else if (c.eq(angle, "right")) 1 else 2] += 1;
                }
                for ([_][]const u8{ "convex", "concave", "flat" }, shapes) |name, count| addNumber(&report, name, count);
                for ([_][]const u8{ "acute", "right", "obtuse" }, angles) |name, count| addNumber(&report, name, count);
                report.add("edge_len2 {d} {d}", .{ shortest, longest });
                var low: usize = topology.edges.len;
                var high: usize = 0;
                for (topology.component_vertices[component]) |vertex| {
                    low = @min(low, degrees[vertex]);
                    high = @max(high, degrees[vertex]);
                }
                report.add("valence {d} {d}", .{ low, high });
            }
        } else if (c.eq(section, "groups")) {
            for (groups.items, 0..) |group, g| {
                var group_faces: std.ArrayList(usize) = .empty;
                var components: std.ArrayList(usize) = .empty;
                var polygons: usize = 0;
                var triangles: usize = 0;
                var nonplanar_group: usize = 0;
                for (object.polygons.items, 0..) |polygon, index| if (polygon.group == g) {
                    polygons += 1;
                    triangles += polygon.vertices.len - 2;
                    nonplanar_group += @intFromBool(nonplanar_polygons[index]);
                };
                for (faces, 0..) |face, index| if (face.group == g) {
                    c.append(usize, &group_faces, index);
                    const component = topology.face_component[index] + 1;
                    if (!topology_module.contains(components.items, component)) c.append(usize, &components, component);
                };
                std.mem.sort(usize, components.items, {}, std.sort.asc(usize));
                report.add("[group {s}]", .{group});
                addNumber(&report, "polygons", polygons);
                addNumber(&report, "triangles", triangles);
                addNumber(&report, "nonplanar", nonplanar_group);
                addNumber(&report, "faces", group_faces.items.len);
                addText(&report, "area", m.real(m.area(group_faces.items, faces, points)));
                addText(&report, "components", c.list(components.items, 0));
            }
        } else if (c.eq(section, "contacts")) {
            report.add("[contacts]", .{});
            for (props, 0..) |a, component| for (props[component + 1 ..], component + 1..) |b, other| {
                var intersects = true;
                for (0..3) |axis| if (a.minimum[axis] > b.maximum[axis] or b.minimum[axis] > a.maximum[axis]) {
                    intersects = false;
                };
                if (!intersects) continue;
                var shared: usize = 0;
                var gap: i64 = -1;
                for (topology.component_vertices[component]) |u| {
                    if (topology_module.contains(topology.component_vertices[other], u)) shared += 1;
                    for (topology.component_vertices[other]) |v| if (u != v) {
                        const difference = m.difference(points[u], points[v]);
                        const distance = m.dot(difference, difference);
                        if (gap < 0 or distance < gap) gap = distance;
                    };
                }
                report.add("contact {d} {d} shared {d} gap2 {d}", .{ component + 1, other + 1, shared, gap });
            };
        } else if (c.eq(section, "edges")) {
            report.add("[edges]", .{});
            var kinds = std.mem.zeroes([3]usize);
            var shapes = std.mem.zeroes([4]usize);
            var max_faces: usize = 0;
            var shortest: usize = 0;
            var longest: usize = 0;
            for (topology.edges, 0..) |edge, e| {
                kinds[if (edge.faces.items.len == 1) 0 else if (edge.faces.items.len == 2) 1 else 2] += 1;
                const shape = edgeShape(edge, faces, points);
                for ([_][]const u8{ "convex", "concave", "flat", "inconsistent" }, 0..) |name, i| if (c.eq(shape, name)) {
                    shapes[i] += 1;
                };
                max_faces = @max(max_faces, edge.faces.items.len);
                if (length2(edge, points) < length2(topology.edges[shortest], points)) shortest = e;
                if (length2(edge, points) > length2(topology.edges[longest], points)) longest = e;
            }
            addNumber(&report, "edges", topology.edges.len);
            for ([_][]const u8{ "boundary", "manifold", "nonmanifold" }, kinds) |name, count| addNumber(&report, name, count);
            addNumber(&report, "max_faces", max_faces);
            for ([_][]const u8{ "convex", "concave", "flat", "inconsistent" }, shapes) |name, count| addNumber(&report,
                 name, count);
            const small = topology.edges[shortest];
            const large = topology.edges[longest];
            report.add("shortest {d} {d} len2 {d}", .{ small.a, small.b, length2(small, points) });
            report.add("longest {d} {d} len2 {d}", .{ large.a, large.b, length2(large, points) });
        } else if (c.eq(section, "valence")) {
            report.add("[valence]", .{});
            var used: usize = 0;
            var low: usize = topology.edges.len;
            var high: usize = 0;
            var sum: i64 = 0;
            const degrees = c.alloc(usize, topology.edges.len + 1);
            @memset(degrees, 0);
            for (topology.vertex_edges[1..]) |edges| {
                const degree = edges.len;
                if (degree == 0) continue;
                used += 1;
                sum += c.n(degree);
                degrees[degree] += 1;
                low = @min(low, degree);
                high = @max(high, degree);
            }
            addNumber(&report, "used", used);
            addNumber(&report, "isolated", points.len - 1 - used);
            addNumber(&report, "min", low);
            addNumber(&report, "max", high);
            addText(&report, "mean", m.fraction(sum, c.n(used)));
            for (degrees, 0..) |count, degree| if (count > 0) report.add("degree {d} {d}", .{ degree, count });
        } else if (c.eq(section, "queries")) {
            report.add("[queries]", .{});
            for (options.queries.items) |query| report.add("{s}", .{queryAnswer(query, faces, points,
                 topology, props, groups.items)});
        }
    }
    try c.write(init.io, "report.txt", report);
    var csv: c.Lines = .{};
    csv.add("component,faces,vertices,closed,euler,genus,volume6,area", .{});
    for (props, 0..) |prop, component| csv.add("{d},{d},{d},{s},{d},{s},{s},{s}", .{ component + 1,
         topology.component_faces[component].len, topology.component_vertices[component].len, yes(prop.closed),
         prop.euler, if (prop.manifold and prop.orientable) c.fmt("{d}", .{prop.genus}) else "-",
         if (prop.solid) c.fmt("{d}", .{prop.volume6}) else "-", m.real(m.area(topology.component_faces[component],
         faces, points)) });
    try c.write(init.io, "components.csv", csv);
    try c.writeObject(init.io, points, faces, groups.items);
}
