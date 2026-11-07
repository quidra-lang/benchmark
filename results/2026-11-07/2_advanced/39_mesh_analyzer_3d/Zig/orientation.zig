const c = @import("obj_io.zig");
const t = @import("topology.zig");
const std = @import("std");
pub fn directed(face: c.Face, a: usize, b: usize) bool {
    for (face.vertices, 0..) |vertex, i| if (vertex == a and face.vertices[(i + 1) % 3] == b) return true;
    return false;
}
pub fn flip(face: *c.Face) void {
    std.mem.swap(usize, &face.vertices[1], &face.vertices[2]);
}
pub fn orient(faces: []c.Face, topology: t.Topology) void {
    const visited = c.alloc(bool, faces.len);
    @memset(visited, false);
    for (faces, 0..) |_, first| if (!visited[first]) {
        var queue: std.ArrayList(usize) = .empty;
        c.append(usize, &queue, first);
        visited[first] = true;
        var position: usize = 0;
        while (position < queue.items.len) : (position += 1) {
            const f = queue.items[position];
            const vertices = faces[f].vertices;
            for (vertices, 0..) |a, i| {
                const b = vertices[(i + 1) % 3];
                const edge = topology.edges[t.edgeIndex(topology, a, b).?];
                if (edge.faces.items.len != 2) continue;
                const other = if (edge.faces.items[0] == f) edge.faces.items[1] else edge.faces.items[0];
                if (visited[other]) continue;
                if (directed(faces[other], a, b)) flip(&faces[other]);
                visited[other] = true;
                c.append(usize, &queue, other);
            }
        }
    };
}
pub fn inconsistent(faces: []const c.Face, topology: t.Topology) []const usize {
    var out: std.ArrayList(usize) = .empty;
    for (topology.edges, 0..) |edge, e| if (edge.faces.items.len == 2 and directed(faces[edge.faces.items[0]],
         edge.a, edge.b) == directed(faces[edge.faces.items[1]], edge.a, edge.b)) c.append(usize,
         &out, e);
    return out.items;
}
