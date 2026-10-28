const std = @import("std");
const c = @import("obj_io.zig");
const m = @import("measure.zig");
const t = @import("topology.zig");
pub const Removed = struct { triangle: usize, polygon: usize, line: usize, reason: []const u8 };
pub const Cleanup = struct { snapped: []c.Point, points: std.ArrayList(c.Point) = .empty, representative: []usize,
     new_number: []usize, faces: c.Faces = .empty, removed: std.ArrayList(Removed) = .empty, triangles: usize = 0,
     snapped_count: usize = 0, merged_count: usize = 0 };
pub fn triangulate(object: c.Object) c.Faces {
    var out: c.Faces = .empty;
    for (object.polygons.items, 1..) |polygon, p| {
        var i: usize = 1;
        while (i + 1 < polygon.vertices.len) : (i += 1) c.append(c.Face, &out, .{ .vertices = .{ polygon.vertices[0],
             polygon.vertices[i], polygon.vertices[i + 1] }, .polygon = p, .line = polygon.line, .group = polygon.group,
             .triangle = out.items.len + 1 });
    }
    return out;
}
pub fn cleanup(object: c.Object, options: c.Options) Cleanup {
    var out: Cleanup = .{ .snapped = c.dupe(c.Point, object.vertices.items), .representative = c.alloc(usize,
         object.vertices.items.len), .new_number = c.alloc(usize, object.vertices.items.len) };
    @memset(out.new_number, 0);
    for (1..out.snapped.len) |vertex| {
        for (&out.snapped[vertex]) |*coordinate| coordinate.* = options.snap * @divFloor(2 * coordinate.* + options.snap,
             2 * options.snap);
        if (!std.mem.eql(i64, &out.snapped[vertex], &object.vertices.items[vertex])) out.snapped_count += 1;
        out.representative[vertex] = vertex;
        if (options.merge) for (1..vertex) |earlier| {
            if (std.mem.eql(i64, &out.snapped[earlier], &out.snapped[vertex])) {
                out.representative[vertex] = earlier;
                break;
            }
        };
        if (out.representative[vertex] != vertex) out.merged_count += 1;
    }
    const triangles = triangulate(object);
    out.triangles = triangles.items.len;
    const used = c.alloc(bool, object.vertices.items.len);
    @memset(used, false);
    for (triangles.items) |original| {
        var face = original;
        for (&face.vertices) |*vertex| vertex.* = out.representative[vertex.*];
        var reason: ?[]const u8 = null;
        if (face.vertices[0] == face.vertices[1] or face.vertices[1] == face.vertices[2] or face.vertices[2] == face.vertices[0]) reason = "repeated" else {
            const n = m.normal(face, out.snapped);
            if (options.degenerate and std.mem.eql(i64, &n, &.{ 0, 0, 0 })) reason = "zero_area" else if (options.duplicates) for (out.faces.items) |earlier| {
                var equal = true;
                for (face.vertices) |vertex| if (!t.contains(&earlier.vertices, vertex)) {
                    equal = false;
                };
                if (equal) {
                    reason = "duplicate";
                    break;
                }
            };
        }
        if (reason) |why| c.append(Removed, &out.removed, .{ .triangle = face.triangle, .polygon = face.polygon,
             .line = face.line, .reason = why }) else {
            for (face.vertices) |vertex| used[vertex] = true;
            c.append(c.Face, &out.faces, face);
        }
    }
    c.append(c.Point, &out.points, .{ 0, 0, 0 });
    for (1..out.snapped.len) |vertex| if ((options.keep_unused and out.representative[vertex] == vertex) or (!options.keep_unused and used[vertex])) {
        out.new_number[vertex] = out.points.items.len;
        c.append(c.Point, &out.points, out.snapped[vertex]);
    };
    for (out.faces.items) |*face| for (&face.vertices) |*vertex| {
        vertex.* = out.new_number[vertex.*];
    };
    return out;
}
pub fn fillFaces(faces: *c.Faces, loop: t.Loop, group: usize) void {
    var i: usize = 1;
    while (i + 1 < loop.vertices.items.len) : (i += 1) c.append(c.Face, faces, .{ .vertices = .{ loop.vertices.items[0],
         loop.vertices.items[i + 1], loop.vertices.items[i] }, .group = group });
}
