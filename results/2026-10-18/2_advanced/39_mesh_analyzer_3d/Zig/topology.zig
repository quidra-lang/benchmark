const std = @import("std");
const c = @import("obj_io.zig");
pub const Edge = struct { a: usize, b: usize, faces: std.ArrayList(usize) = .empty };
pub const Topology = struct { edges: []Edge, face_component: []usize, fans: []usize, component_faces: [][]const usize,
     component_vertices: [][]const usize, component_edges: [][]const usize, vertex_faces: [][]const usize,
     vertex_edges: [][]const usize, neighbors: [][]const usize, fan_components: [][]const usize, component_nonmanifold_vertices: [][]const usize };
pub const Loop = struct {
    component: usize,
    vertices: std.ArrayList(usize) = .empty,
    closed: bool = false,
    filled: bool = false,
    kind: []const u8 = "open",
    pub fn length(self: Loop) usize {
        return self.vertices.items.len - @as(usize, if (self.closed) 0 else 1);
    }
};
const Occurrence = struct { a: usize, b: usize, face: usize };
fn occurrenceLess(_: void, a: Occurrence, b: Occurrence) bool {
    return if (a.a != b.a) a.a < b.a else if (a.b != b.b) a.b < b.b else a.face < b.face;
}
fn lists(count: usize) []std.ArrayList(usize) {
    const out = c.alloc(std.ArrayList(usize), count);
    @memset(out, .empty);
    return out;
}
fn slices(values: []const std.ArrayList(usize)) [][]const usize {
    const out = c.alloc([]const usize, values.len);
    for (values, out) |value, *slice| slice.* = value.items;
    return out;
}
pub fn contains(values: []const usize, value: usize) bool {
    return std.mem.indexOfScalar(usize, values, value) != null;
}
pub fn edgeIndex(topology: Topology, a_: usize, b_: usize) ?usize {
    const a = @min(a_, b_);
    const b = @max(a_, b_);
    var low: usize = 0;
    var high = topology.edges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const edge = topology.edges[middle];
        if (edge.a < a or (edge.a == a and edge.b < b)) low = middle + 1 else high = middle;
    }
    return if (low < topology.edges.len and topology.edges[low].a == a and topology.edges[low].b == b) low else null;
}
pub fn analyze(faces: []const c.Face, vertices: usize) Topology {
    const vertex_faces = lists(vertices + 1);
    const vertex_edges = lists(vertices + 1);
    const neighbors = lists(vertices + 1);
    const fan_components = lists(vertices + 1);
    const fans = c.alloc(usize, vertices + 1);
    @memset(fans, 0);
    const face_component = c.alloc(usize, faces.len);
    @memset(face_component, std.math.maxInt(usize));
    var occurrences: std.ArrayList(Occurrence) = .empty;
    for (faces, 0..) |face, f| for (face.vertices, 0..) |a, i| {
        const b = face.vertices[(i + 1) % 3];
        c.append(usize, &vertex_faces[a], f);
        c.append(Occurrence, &occurrences, .{ .a = @min(a, b), .b = @max(a, b), .face = f });
    };
    std.mem.sort(Occurrence, occurrences.items, {}, occurrenceLess);
    var edges: std.ArrayList(Edge) = .empty;
    for (occurrences.items) |occurrence| {
        if (edges.items.len == 0 or edges.items[edges.items.len - 1].a != occurrence.a or edges.items[edges.items.len - 1].b != occurrence.b) {
            const e = edges.items.len;
            c.append(Edge, &edges, .{ .a = occurrence.a, .b = occurrence.b });
            c.append(usize, &vertex_edges[occurrence.a], e);
            c.append(usize, &vertex_edges[occurrence.b], e);
            c.append(usize, &neighbors[occurrence.a], occurrence.b);
            c.append(usize, &neighbors[occurrence.b], occurrence.a);
        }
        c.append(usize, &edges.items[edges.items.len - 1].faces, occurrence.face);
    }
    for (neighbors) |*values| std.mem.sort(usize, values.items, {}, std.sort.asc(usize));
    var out: Topology = .{ .edges = edges.items, .face_component = face_component, .fans = fans, .vertex_faces = slices(vertex_faces),
         .vertex_edges = slices(vertex_edges), .neighbors = slices(neighbors), .fan_components = undefined,
         .component_faces = undefined, .component_vertices = undefined, .component_edges = undefined,
         .component_nonmanifold_vertices = undefined };
    var components: std.ArrayList([]const usize) = .empty;
    for (faces, 0..) |_, first| if (face_component[first] == std.math.maxInt(usize)) {
        const component = components.items.len;
        var queue: std.ArrayList(usize) = .empty;
        c.append(usize, &queue, first);
        face_component[first] = component;
        var position: usize = 0;
        while (position < queue.items.len) : (position += 1) {
            const face = faces[queue.items[position]];
            for (face.vertices, 0..) |a, i| {
                const edge = edges.items[edgeIndex(out, a, face.vertices[(i + 1) % 3]).?];
                for (edge.faces.items) |next| if (face_component[next] == std.math.maxInt(usize)) {
                    face_component[next] = component;
                    c.append(usize, &queue, next);
                };
            }
        }
        std.mem.sort(usize, queue.items, {}, std.sort.asc(usize));
        c.append([]const usize, &components, queue.items);
    };
    out.component_faces = components.items;
    const component_vertices = lists(components.items.len);
    const component_edges = lists(components.items.len);
    const component_nonmanifold = lists(components.items.len);
    for (components.items, 0..) |component, index| {
        const used = c.alloc(bool, vertices + 1);
        @memset(used, false);
        for (component) |f| for (faces[f].vertices) |vertex| {
            used[vertex] = true;
        };
        for (1..vertices + 1) |vertex| if (used[vertex]) c.append(usize, &component_vertices[index], vertex);
    }
    for (edges.items, 0..) |edge, e| c.append(usize, &component_edges[face_component[edge.faces.items[0]]], e);
    for (1..vertices + 1) |vertex| {
        const visited = c.alloc(bool, faces.len);
        @memset(visited, false);
        const per_component = c.alloc(usize, components.items.len);
        @memset(per_component, 0);
        for (vertex_faces[vertex].items) |first| if (!visited[first]) {
            var queue: std.ArrayList(usize) = .empty;
            c.append(usize, &queue, first);
            visited[first] = true;
            var position: usize = 0;
            while (position < queue.items.len) : (position += 1) for (vertex_edges[vertex].items) |e| {
                const edge = edges.items[e];
                if (!contains(edge.faces.items, queue.items[position])) continue;
                for (edge.faces.items) |next| if (!visited[next]) {
                    visited[next] = true;
                    c.append(usize, &queue, next);
                };
            };
            fans[vertex] += 1;
            per_component[face_component[first]] += 1;
        };
        for (per_component, 0..) |count, index| {
            if (count > 0) c.append(usize, &fan_components[vertex], index);
            if (count >= 2) c.append(usize, &component_nonmanifold[index], vertex);
        }
    }
    out.component_vertices = slices(component_vertices);
    out.component_edges = slices(component_edges);
    out.component_nonmanifold_vertices = slices(component_nonmanifold);
    out.fan_components = slices(fan_components);
    return out;
}
pub fn traceLoops(topology: Topology) std.ArrayList(Loop) {
    var loops: std.ArrayList(Loop) = .empty;
    const used = c.alloc(bool, topology.edges.len);
    @memset(used, false);
    for (topology.component_edges, 0..) |component_edges, component| for (component_edges) |first| {
        const edge = topology.edges[first];
        if (edge.faces.items.len != 1 or used[first]) continue;
        used[first] = true;
        var loop: Loop = .{ .component = component };
        c.append(usize, &loop.vertices, edge.a);
        c.append(usize, &loop.vertices, edge.b);
        while (loop.vertices.items[loop.vertices.items.len - 1] != edge.a) {
            const x = loop.vertices.items[loop.vertices.items.len - 1];
            var selected: ?usize = null;
            var other: usize = 0;
            for (topology.vertex_edges[x]) |e| {
                const candidate = topology.edges[e];
                if (used[e] or candidate.faces.items.len != 1 or topology.face_component[candidate.faces.items[0]] != component) continue;
                const y = if (candidate.a == x) candidate.b else candidate.a;
                if (selected == null or y < other) {
                    selected = e;
                    other = y;
                }
            }
            if (selected == null) break;
            used[selected.?] = true;
            c.append(usize, &loop.vertices, other);
        }
        loop.closed = loop.vertices.items[loop.vertices.items.len - 1] == edge.a;
        if (loop.closed) _ = loop.vertices.pop();
        c.append(Loop, &loops, loop);
    };
    return loops;
}
