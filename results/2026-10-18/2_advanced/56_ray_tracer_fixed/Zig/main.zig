const std = @import("std");
const c = @import("scene.zig");
const f = @import("fixed_point.zig");
const v = @import("vector3.zig");
const inter = @import("intersect.zig");
const shade = @import("shading.zig");
const Vec = c.Vec;
const Ray = c.Ray;
const zero: Vec = .{ 0, 0, 0 };
const ray_names = [_][]const u8{ "primary", "reflection", "refraction", "shadow" };
const Settings = struct { width: usize, height: usize, contrast: i64, depth: usize, far: i64, epsilon: i64, pad: i64 };
const Node = struct { box: c.Bounds, objects: []const usize = &.{}, left: ?*Node = null, right: ?*Node = null, depth: usize, visits: i64 = 0 };
const Tests = struct { nodes: i64 = 0, objects: i64 = 0 };
const ObjectCounts = struct { primary: i64 = 0, secondary: i64 = 0, shadow: i64 = 0 };
const LightCounts = struct { shadow: i64 = 0, blocked: i64 = 0, attenuated: i64 = 0, backfacing: i64 = 0, outside: i64 = 0 };
const Statistics = struct {
    rays: [4]i64 = .{ 0, 0, 0, 0 },
    misses: [3]i64 = .{ 0, 0, 0 },
    tests: [4]Tests = .{ .{}, .{}, .{}, .{} },
    depths: [4]i64 = .{ 0, 0, 0, 0 },
    objects: [26]ObjectCounts = [_]ObjectCounts{.{}} ** 26,
    lights: [9]LightCounts = [_]LightCounts{.{}} ** 9,
    total_internal: i64 = 0,
    saturated: i64 = 0,
};
const Hit = struct { object: usize, candidate: inter.Candidate };
const Info = struct { hit: Hit, point: Vec, normal: Vec, base: Vec, front: bool };
const LightResult = struct { lit: i64 = 0, diffuse: i64 = 0, specular: i64 = 0 };
const Result = struct { color: Vec = zero, info: ?Info = null, lights: [9]LightResult = [_]LightResult{.{}} ** 9, illumination: i64 = 0 };
const Pixel = struct { center: Vec = zero, color: Vec = zero, info: ?Info = null, lit: [9]bool = [_]bool{false} ** 9, rays: i64 = 0, depth: usize = 0, subsampled: bool = false };
const Sample = struct { direction: Vec, distance: i64, intensity: i64 };
const Samples = struct { data: [16]Sample = undefined, count: usize = 0 };
const Ids = struct { data: [26]usize = undefined, count: usize = 0 };
fn triple(value: Vec) []const u8 {
    return c.fmt("{d} {d} {d}", .{ value[0], value[1], value[2] });
}
fn settings(io: std.Io) !Settings {
    const rows = try c.readLines(io, "input/render.txt");
    const size = c.words(rows[0]);
    return .{ .width = c.u(c.number(size[1])), .height = c.u(c.number(size[2])), .contrast = c.number(c.words(rows[1])[1]), .depth = c.u(c.number(c.words(rows[2])[1])), .far = c.number(c.words(rows[3])[1]), .epsilon = c.number(c.words(rows[4])[1]), .pad = c.number(c.words(rows[5])[1]) };
}
const Tracer = struct {
    scene: c.Scene,
    render: Settings,
    boxes: []c.Bounds,
    root: ?*Node = null,
    stats: Statistics = .{},
    fn init(scene: c.Scene, render: Settings) Tracer {
        var out: Tracer = .{ .scene = scene, .render = render, .boxes = c.alloc(c.Bounds, scene.objects.items.len) };
        var bounded: std.ArrayList(usize) = .empty;
        for (scene.objects.items, 0..) |object, id| {
            if (object.kind == .plane) continue;
            out.boxes[id] = inter.bounds(object, render.pad);
            c.append(usize, &bounded, id);
        }
        if (bounded.items.len > 0) out.root = out.build(bounded.items, 0);
        return out;
    }
    fn unionBox(self: *const Tracer, objects: []const usize) c.Bounds {
        var box = self.boxes[objects[0]];
        for (objects) |id| for (0..3) |axis| {
            box.lo[axis] = @min(box.lo[axis], self.boxes[id].lo[axis]);
            box.hi[axis] = @max(box.hi[axis], self.boxes[id].hi[axis]);
        };
        return box;
    }
    fn area(self: *const Tracer, objects: []const usize) i64 {
        const box = self.unionBox(objects);
        const d = v.sub(box.hi, box.lo);
        return d[0] * d[1] + d[1] * d[2] + d[2] * d[0];
    }
    fn build(self: *Tracer, objects: []const usize, depth: usize) *Node {
        const node = c.create(Node, .{ .box = self.unionBox(objects), .depth = depth });
        if (objects.len <= 2) {
            const ordered = c.dupe(usize, objects);
            std.mem.sort(usize, ordered, {}, std.sort.asc(usize));
            node.objects = ordered;
            return node;
        }
        var best: i64 = std.math.maxInt(i64);
        var left: []const usize = &.{};
        var right: []const usize = &.{};
        for (0..3) |axis| {
            const ordered = c.dupe(usize, objects);
            const Context = struct {
                boxes: []const c.Bounds,
                axis: usize,
                fn less(ctx: @This(), a: usize, b: usize) bool {
                    const x = f.div(ctx.boxes[a].lo[ctx.axis] + ctx.boxes[a].hi[ctx.axis], 2);
                    const y = f.div(ctx.boxes[b].lo[ctx.axis] + ctx.boxes[b].hi[ctx.axis], 2);
                    return if (x != y) x < y else a < b;
                }
            };
            std.mem.sort(usize, ordered, Context{ .boxes = self.boxes, .axis = axis }, Context.less);
            for (1..ordered.len) |i| {
                const cost = self.area(ordered[0..i]) * c.n(i) + self.area(ordered[i..]) * c.n(ordered.len - i);
                if (cost < best) {
                    best = cost;
                    left = ordered[0..i];
                    right = ordered[i..];
                }
            }
        }
        node.left = self.build(left, depth + 1);
        node.right = self.build(right, depth + 1);
        return node;
    }
    fn camera(self: *const Tracer, qx: i64, qy: i64) Ray {
        const u = f.div((qx - 2 * c.n(self.render.width)) * self.scene.half_width, 2 * c.n(self.render.width));
        const y = f.div((2 * c.n(self.render.height) - qy) * self.scene.half_height, 2 * c.n(self.render.height));
        return .{ .origin = self.scene.eye, .direction = v.norm(v.add(v.add(self.scene.forward, v.sc(self.scene.right, u)), v.sc(self.scene.up, y))) };
    }
    fn nearestObject(self: *Tracer, id: usize, ray: Ray, kind: usize, counted: bool, found: *?Hit) void {
        if (counted) self.stats.tests[kind].objects += 1;
        const candidate = inter.hit(self.scene.objects.items[id], ray, self.render.epsilon) orelse return;
        if (candidate.distance > self.render.far) return;
        if (found.*) |old| {
            if (candidate.distance > old.candidate.distance or (candidate.distance == old.candidate.distance and id >= old.object)) return;
        }
        found.* = .{ .object = id, .candidate = candidate };
    }
    fn nearestNode(self: *Tracer, node: *Node, ray: Ray, kind: usize, counted: bool, found: *?Hit) void {
        if (counted) {
            self.stats.tests[kind].nodes += 1;
            node.visits += 1;
        }
        const box = inter.slab(node.box, ray) orelse return;
        if (box.far <= self.render.epsilon or box.near > self.render.far) return;
        if (found.*) |old| if (box.near > old.candidate.distance) return;
        if (node.objects.len > 0) {
            for (node.objects) |id| self.nearestObject(id, ray, kind, counted, found);
        } else {
            self.nearestNode(node.left.?, ray, kind, counted, found);
            self.nearestNode(node.right.?, ray, kind, counted, found);
        }
    }
    fn nearest(self: *Tracer, ray: Ray, kind: usize, counted: bool) ?Hit {
        var found: ?Hit = null;
        for (self.scene.objects.items, 0..) |object, id| if (object.kind == .plane) self.nearestObject(id, ray, kind, counted, &found);
        if (self.root) |root| self.nearestNode(root, ray, kind, counted, &found);
        return found;
    }
    fn occludeObject(self: *Tracer, id: usize, ray: Ray, distance: i64, counted: bool, found: *Ids) void {
        if (counted) self.stats.tests[3].objects += 1;
        const candidate = inter.hit(self.scene.objects.items[id], ray, self.render.epsilon) orelse return;
        if (candidate.distance < distance) {
            found.data[found.count] = id;
            found.count += 1;
        }
    }
    fn occludeNode(self: *Tracer, node: *Node, ray: Ray, distance: i64, counted: bool, found: *Ids) void {
        if (counted) {
            self.stats.tests[3].nodes += 1;
            node.visits += 1;
        }
        const box = inter.slab(node.box, ray) orelse return;
        if (box.far <= self.render.epsilon or box.near >= distance) return;
        if (node.objects.len > 0) {
            for (node.objects) |id| self.occludeObject(id, ray, distance, counted, found);
        } else {
            self.occludeNode(node.left.?, ray, distance, counted, found);
            self.occludeNode(node.right.?, ray, distance, counted, found);
        }
    }
    fn occluders(self: *Tracer, ray: Ray, distance: i64, counted: bool) Ids {
        var found: Ids = .{};
        for (self.scene.objects.items, 0..) |object, id| if (object.kind == .plane) self.occludeObject(id, ray, distance, counted, &found);
        if (self.root) |root| self.occludeNode(root, ray, distance, counted, &found);
        std.mem.sort(usize, found.data[0..found.count], {}, std.sort.asc(usize));
        if (counted) for (found.data[0..found.count]) |id| {
            self.stats.objects[id].shadow += 1;
        };
        return found;
    }
    fn samples(self: *const Tracer, light: c.Light, point: Vec) Samples {
        var out: Samples = .{};
        if (light.kind == .sun) {
            out.data[0] = .{ .direction = light.direction, .distance = self.render.far, .intensity = light.intensity };
            out.count = 1;
            return out;
        }
        const count = if (light.kind == .area) light.divisions else 1;
        for (0..count) |j| for (0..count) |i| {
            var position = light.position;
            if (light.kind == .area) for (0..3) |axis| {
                position[axis] += f.div(c.n(2 * i + 1) * light.u[axis], c.n(2 * count)) + f.div(c.n(2 * j + 1) * light.v[axis], c.n(2 * count));
            };
            const rel = v.sub(position, point);
            out.data[out.count] = .{ .direction = v.norm(rel), .distance = v.len(rel), .intensity = f.div(light.intensity, c.n(count * count)) };
            out.count += 1;
        };
        return out;
    }
    fn cone(light: c.Light, direction: Vec) i64 {
        if (light.kind != .spot) return f.scale;
        const cosine = -v.dot(direction, light.direction);
        if (cosine <= light.outer) return 0;
        if (cosine >= light.inner) return f.scale;
        return f.div((cosine - light.outer) * f.scale, light.inner - light.outer);
    }
    fn trace(self: *Tracer, ray: Ray, kind: usize, depth: usize, counted: bool, pixel: ?*Pixel, record: ?*c.Lines) Result {
        if (counted) {
            self.stats.rays[kind] += 1;
            self.stats.depths[depth] += 1;
            pixel.?.rays += 1;
            pixel.?.depth = @max(pixel.?.depth, depth);
        }
        if (record) |lines| lines.add("ray {s} {d} origin {s} direction {s}", .{ ray_names[kind], depth, triple(ray.origin), triple(ray.direction) });
        var out: Result = .{};
        const hit = self.nearest(ray, kind, counted) orelse {
            out.color = self.scene.background;
            if (counted) self.stats.misses[kind] += 1;
            if (record) |lines| {
                lines.add("miss", .{});
                lines.add("color {s}", .{triple(out.color)});
            }
            return out;
        };
        const object = self.scene.objects.items[hit.object];
        const material = self.scene.materials.items[object.material];
        const point = v.add(ray.origin, v.sc(ray.direction, hit.candidate.distance));
        const normal0 = inter.outward(object, ray, point, hit.candidate);
        const front = v.dot(normal0, ray.direction) <= 0;
        const normal = if (front) normal0 else v.neg(normal0);
        const base = shade.base(material, point);
        out.info = .{ .hit = hit, .point = point, .normal = normal, .base = base, .front = front };
        if (counted) {
            if (kind == 0) self.stats.objects[hit.object].primary += 1 else self.stats.objects[hit.object].secondary += 1;
        }
        if (record) |lines| lines.add("hit {c} t {d} point {s} normal {s} base {s}", .{ object.label, hit.candidate.distance, triple(point), triple(normal), triple(base) });
        var diffuse: i64 = 0;
        var specular: i64 = 0;
        for (self.scene.lights.items, 0..) |light, index| {
            const result = &out.lights[index];
            const light_samples = self.samples(light, point);
            for (light_samples.data[0..light_samples.count]) |sample| {
                if (v.dot(normal, sample.direction) <= 0) {
                    if (counted) self.stats.lights[index].backfacing += 1;
                    continue;
                }
                var factor = cone(light, sample.direction);
                if (factor == 0) {
                    if (counted) self.stats.lights[index].outside += 1;
                    continue;
                }
                if (counted) {
                    self.stats.rays[3] += 1;
                    self.stats.lights[index].shadow += 1;
                    pixel.?.rays += 1;
                }
                const blockers = self.occluders(.{ .origin = point, .direction = sample.direction }, sample.distance, counted);
                for (blockers.data[0..blockers.count]) |id| factor = f.mul(factor, self.scene.materials.items[self.scene.objects.items[id].material].kt);
                if (factor == 0) {
                    if (counted) self.stats.lights[index].blocked += 1;
                    continue;
                }
                if (counted and blockers.count > 0) self.stats.lights[index].attenuated += 1;
                result.lit += 1;
                const terms = shade.phong(material, normal, sample.direction, v.neg(ray.direction), f.mul(sample.intensity, factor));
                result.diffuse += terms[0];
                result.specular += terms[1];
            }
            diffuse += result.diffuse;
            specular += result.specular;
            if (result.lit > 0) out.illumination += 1;
            if (record) |lines| lines.add("light {d} lit {d} of {d} diffuse {d} specular {d}", .{ index + 1, result.lit, light_samples.count, result.diffuse, result.specular });
        }
        var local: Vec = undefined;
        for (0..3) |axis| {
            const raw = f.div(base[axis] * (self.scene.ambient + diffuse), f.scale) + f.div(255 * specular, f.scale);
            local[axis] = @min(raw, 255);
            if (counted and raw > 255) self.stats.saturated += 1;
        }
        if (record) |lines| lines.add("local {s}", .{triple(local)});
        var color = local;
        if (depth < self.render.depth and (material.kr > 0 or material.kt > 0)) {
            const weights = shade.refracted(material, ray.direction, normal, front);
            if (weights.total_internal) {
                if (counted) self.stats.total_internal += 1;
                if (record) |lines| lines.add("total_internal_reflection", .{});
            }
            if (record) |lines| lines.add("weights {d} {d} {d}", .{ f.scale - material.kr - material.kt, weights.reflection, weights.refraction });
            var reflected = zero;
            var refracted = zero;
            if (weights.reflection > 0) reflected = self.trace(.{ .origin = point, .direction = shade.reflected(ray.direction, normal) }, 1, depth + 1, counted, pixel, record).color;
            if (weights.refraction > 0) refracted = self.trace(.{ .origin = point, .direction = weights.direction.? }, 2, depth + 1, counted, pixel, record).color;
            color = shade.mix(local, f.scale - material.kr - material.kt, reflected, weights.reflection, refracted, weights.refraction);
        }
        if (self.scene.fog) {
            const distance = hit.candidate.distance;
            const factor = if (distance <= self.scene.fog_start) 0 else if (distance >= self.scene.fog_end) f.scale else f.div((distance - self.scene.fog_start) * f.scale, self.scene.fog_end - self.scene.fog_start);
            color = shade.mix(color, f.scale - factor, self.scene.fog_color, factor, zero, 0);
        }
        out.color = color;
        if (record) |lines| lines.add("color {s}", .{triple(color)});
        return out;
    }
    fn label(self: *const Tracer, pixel: Pixel) u8 {
        return if (pixel.info) |info| self.scene.objects.items[info.hit.object].label else '.';
    }
};
fn leafDepth(node: *const Node, object: usize) ?usize {
    if (node.objects.len > 0) {
        for (node.objects) |id| if (id == object) return node.depth;
        return null;
    }
    if (leafDepth(node.left.?, object)) |depth| return depth;
    return leafDepth(node.right.?, object);
}
fn reportNode(tracer: *const Tracer, node: *const Node, lines: *c.Lines) void {
    if (node.objects.len > 0) {
        var labels: c.Text = .{};
        for (node.objects) |id| labels.add("{c}", .{tracer.scene.objects.items[id].label});
        lines.add("node {d} leaf {s} box {s} {s} visits {d}", .{ node.depth, labels.value(), triple(node.box.lo), triple(node.box.hi), node.visits });
    } else {
        lines.add("node {d} inner box {s} {s} visits {d}", .{ node.depth, triple(node.box.lo), triple(node.box.hi), node.visits });
        reportNode(tracer, node.left.?, lines);
        reportNode(tracer, node.right.?, lines);
    }
}
fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
fn image(io: std.Io, name: []const u8, comptime T: type, values: []const T, width: usize, height: usize) !void {
    var lines: c.Lines = .{};
    lines.add("{s}", .{if (T == Vec) "P3" else "P2"});
    lines.add("{d} {d}", .{ width, height });
    lines.add("255", .{});
    for (0..height) |y| {
        var row: c.Text = .{};
        for (0..width) |x| {
            if (x > 0) row.add(" ", .{});
            if (T == Vec) row.add("{s}", .{triple(values[y * width + x])}) else row.add("{d}", .{values[y * width + x]});
        }
        lines.add("{s}", .{row.value()});
    }
    try save(io, name, lines);
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    const io = init.io;
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var tracer = Tracer.init(try c.load(io), try settings(io));
    const render = tracer.render;
    const width = render.width;
    const height = render.height;
    const count = width * height;
    const pixels = c.alloc(Pixel, count);
    @memset(pixels, .{});
    for (0..height) |y| for (0..width) |x| {
        const pixel = &pixels[y * width + x];
        const result = tracer.trace(tracer.camera(4 * c.n(x) + 2, 4 * c.n(y) + 2), 0, 0, true, pixel, null);
        pixel.center = result.color;
        pixel.color = result.color;
        pixel.info = result.info;
        for (0..tracer.scene.lights.items.len) |id| pixel.lit[id] = result.lights[id].lit > 0;
    };
    var supersampled: i64 = 0;
    const neighbors = [_][2]i64{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };
    const offsets = [_][2]i64{ .{ 1, 1 }, .{ 3, 1 }, .{ 1, 3 }, .{ 3, 3 } };
    for (0..height) |y| for (0..width) |x| {
        const pixel = &pixels[y * width + x];
        for (neighbors) |offset| {
            const xx = c.n(x) + offset[0];
            const yy = c.n(y) + offset[1];
            if (xx < 0 or yy < 0 or xx >= c.n(width) or yy >= c.n(height)) continue;
            const other = pixels[c.u(yy) * width + c.u(xx)];
            var difference: i64 = 0;
            for (0..3) |axis| difference = @max(difference, @as(i64, @intCast(@abs(pixel.center[axis] - other.center[axis]))));
            if (tracer.label(pixel.*) != tracer.label(other) or difference > render.contrast) pixel.subsampled = true;
        }
        if (pixel.subsampled) {
            supersampled += 1;
            var sum = zero;
            for (offsets) |offset| {
                const color = tracer.trace(tracer.camera(4 * c.n(x) + offset[0], 4 * c.n(y) + offset[1]), 0, 0, true, pixel, null).color;
                sum = v.add(sum, color);
            }
            for (0..3) |axis| pixel.color[axis] = f.div(sum[axis], 4);
        }
    };
    var minimum: ?i64 = null;
    var maximum: i64 = 0;
    var cost_max: i64 = 0;
    var total_color = zero;
    var histogram = [_]i64{0} ** 8;
    const colors = c.alloc(Vec, count);
    const normal = c.alloc(Vec, count);
    @memset(normal, zero);
    const albedo = c.alloc(Vec, count);
    @memset(albedo, zero);
    const depth = c.alloc(i64, count);
    @memset(depth, 0);
    const cost = c.alloc(i64, count);
    var object_map: c.Lines = .{};
    var light_map: c.Lines = .{};
    var ray_depth: c.Lines = .{};
    for (0..height) |y| {
        var objects: c.Text = .{};
        var lights: c.Text = .{};
        var depths: c.Text = .{};
        for (0..width) |x| {
            const index = y * width + x;
            const pixel = pixels[index];
            colors[index] = pixel.color;
            objects.add("{c}", .{tracer.label(pixel)});
            var lit: usize = 0;
            for (pixel.lit) |value| {
                if (value) lit += 1;
            }
            lights.add("{c}", .{if (pixel.info != null) @as(u8, @intCast('0' + lit)) else @as(u8, '.')});
            depths.add("{d}", .{pixel.depth});
            cost_max = @max(cost_max, pixel.rays);
            total_color = v.add(total_color, pixel.color);
            histogram[c.u(f.div(f.div(299 * pixel.color[0] + 587 * pixel.color[1] + 114 * pixel.color[2], 1000), 32))] += 1;
            if (pixel.info) |info| {
                const distance = info.hit.candidate.distance;
                minimum = if (minimum) |old| @min(old, distance) else distance;
                maximum = @max(maximum, distance);
                albedo[index] = info.base;
                for (0..3) |axis| normal[index][axis] = @max(0, @min(255, f.div((info.normal[axis] + f.scale) * 255, 2 * f.scale)));
            }
        }
        object_map.add("{s}", .{objects.value()});
        light_map.add("{s}", .{lights.value()});
        ray_depth.add("{s}", .{depths.value()});
    }
    for (pixels, 0..) |pixel, index| {
        cost[index] = f.div(255 * pixel.rays, cost_max);
        if (pixel.info) |info| depth[index] = if (maximum == minimum.?) 255 else 255 - f.div(235 * (info.hit.candidate.distance - minimum.?), maximum - minimum.?);
    }
    try image(io, "image.ppm", Vec, colors, width, height);
    try image(io, "depth.pgm", i64, depth, width, height);
    try image(io, "normal.ppm", Vec, normal, width, height);
    try image(io, "albedo.ppm", Vec, albedo, width, height);
    try image(io, "cost.pgm", i64, cost, width, height);
    try save(io, "object_map.txt", object_map);
    try save(io, "light_map.txt", light_map);
    try save(io, "ray_depth.txt", ray_depth);
    var stats: c.Lines = .{};
    const counts = tracer.stats;
    stats.add("image {d} {d}", .{ width, height });
    stats.add("supersampled {d}", .{supersampled});
    stats.add("rays primary {d} reflection {d} refraction {d} shadow {d} total {d}", .{ counts.rays[0], counts.rays[1], counts.rays[2], counts.rays[3], counts.rays[0] + counts.rays[1] + counts.rays[2] + counts.rays[3] });
    stats.add("misses primary {d} reflection {d} refraction {d}", .{ counts.misses[0], counts.misses[1], counts.misses[2] });
    var depth_counts: c.Text = .{};
    depth_counts.add("depth", .{});
    for (counts.depths[0 .. render.depth + 1]) |value| depth_counts.add(" {d}", .{value});
    stats.add("{s}", .{depth_counts.value()});
    for (ray_names, 0..) |name, kind| stats.add("tests {s} nodes {d} objects {d}", .{ name, counts.tests[kind].nodes, counts.tests[kind].objects });
    stats.add("total_internal_reflection {d}", .{counts.total_internal});
    stats.add("clamped {d}", .{counts.saturated});
    if (minimum) |value| stats.add("distance {d} {d}", .{ value, maximum }) else stats.add("distance none", .{});
    stats.add("max_pixel_rays {d}", .{cost_max});
    for (&total_color) |*value| value.* = f.div(value.*, c.n(count));
    stats.add("mean {s}", .{triple(total_color)});
    var hist: c.Text = .{};
    hist.add("histogram", .{});
    for (histogram) |value| hist.add(" {d}", .{value});
    stats.add("{s}", .{hist.value()});
    if (tracer.root) |root| reportNode(&tracer, root, &stats);
    for (tracer.scene.objects.items, 0..) |object, id| {
        var pixel_count: i64 = 0;
        var x0 = width;
        var y0 = height;
        var x1: usize = 0;
        var y1: usize = 0;
        var sum = zero;
        for (pixels, 0..) |pixel, index| {
            const info = pixel.info orelse continue;
            if (info.hit.object != id) continue;
            const x = index % width;
            const y = index / width;
            pixel_count += 1;
            x0 = @min(x0, x);
            y0 = @min(y0, y);
            x1 = @max(x1, x);
            y1 = @max(y1, y);
            sum = v.add(sum, pixel.color);
        }
        var tail: []const u8 = "none color none";
        if (pixel_count > 0) {
            for (&sum) |*value| value.* = f.div(value.*, pixel_count);
            tail = c.fmt("{d} {d} {d} {d} color {s}", .{ x0, y0, x1, y1, triple(sum) });
        }
        stats.add("object {c} {s} primary {d} secondary {d} shadow {d} pixels {d} box {s}", .{ object.label, @tagName(object.kind), counts.objects[id].primary, counts.objects[id].secondary, counts.objects[id].shadow, pixel_count, tail });
    }
    for (tracer.scene.lights.items, 0..) |light, id| {
        var lit: i64 = 0;
        for (pixels) |pixel| {
            if (pixel.lit[id]) lit += 1;
        }
        const value = counts.lights[id];
        const samples = if (light.kind == .area) light.divisions * light.divisions else 1;
        stats.add("light {d} {s} samples {d} pixels {d} shadow_rays {d} blocked {d} attenuated {d} backfacing {d} outside {d}", .{ id + 1, @tagName(light.kind), samples, lit, value.shadow, value.blocked, value.attenuated, value.backfacing, value.outside });
    }
    try save(io, "stats.txt", stats);
    var answers: c.Lines = .{};
    for (try c.readLines(io, "input/queries.txt"), 0..) |line, index| {
        answers.add("query {d} {s}", .{ index + 1, line });
        const row = c.words(line);
        const kind = row[0];
        if (c.eq(kind, "pixel")) {
            const pixel = pixels[c.u(c.number(row[2])) * width + c.u(c.number(row[1]))];
            const distance = if (pixel.info) |info| c.fmt("{d}", .{info.hit.candidate.distance}) else "none";
            answers.add("label {c} distance {s} color {s} samples {d} rays {d}", .{ tracer.label(pixel), distance, triple(pixel.color), @as(usize, if (pixel.subsampled) 4 else 1), pixel.rays });
        } else if (c.eq(kind, "trace")) {
            _ = tracer.trace(tracer.camera(4 * c.number(row[1]) + 2, 4 * c.number(row[2]) + 2), 0, 0, false, null, &answers);
        } else if (c.eq(kind, "ray")) {
            _ = tracer.trace(.{ .origin = c.vector(row, 1), .direction = v.norm(c.vector(row, 4)) }, 0, 0, false, null, &answers);
        } else if (c.eq(kind, "object")) {
            var id: usize = 0;
            while (tracer.scene.objects.items[id].label != row[1][0]) : (id += 1) {}
            const object = tracer.scene.objects.items[id];
            const material = tracer.scene.materials.items[object.material];
            if (object.kind == .plane) answers.add("plane material {s} bounds none leaf none", .{material.name}) else answers.add("{s} material {s} bounds {s} {s} leaf {d}", .{ @tagName(object.kind), material.name, triple(tracer.boxes[id].lo), triple(tracer.boxes[id].hi), leafDepth(tracer.root.?, id).? });
        } else if (c.eq(kind, "visible")) {
            const rel = v.sub(c.vector(row, 1), tracer.scene.eye);
            const ray: Ray = .{ .origin = tracer.scene.eye, .direction = v.norm(rel) };
            const blockers = tracer.occluders(ray, v.len(rel) - render.epsilon, false);
            const first = tracer.nearest(ray, 0, false);
            const visible = if (blockers.count == 0) "yes" else "no";
            if (first) |hit| answers.add("{s} first {c} t {d}", .{ visible, tracer.scene.objects.items[hit.object].label, hit.candidate.distance }) else answers.add("{s} first none", .{visible});
        } else if (c.eq(kind, "shadow")) {
            const point = c.vector(row, 1);
            for (tracer.scene.lights.items, 0..) |light, id| {
                var seen = [_]bool{false} ** 26;
                var transmittance: i64 = 0;
                const samples = tracer.samples(light, point);
                for (samples.data[0..samples.count]) |sample| {
                    var factor = Tracer.cone(light, sample.direction);
                    const blockers = tracer.occluders(.{ .origin = point, .direction = sample.direction }, sample.distance, false);
                    for (blockers.data[0..blockers.count]) |object| {
                        seen[object] = true;
                        factor = f.mul(factor, tracer.scene.materials.items[tracer.scene.objects.items[object].material].kt);
                    }
                    transmittance += factor;
                }
                var labels: c.Text = .{};
                for (tracer.scene.objects.items, 0..) |object, j| if (seen[j]) labels.add("{c}", .{object.label});
                answers.add("light {d} factor {d} occluders {s}", .{ id + 1, transmittance, if (labels.value().len == 0) "none" else labels.value() });
            }
        } else {
            const x0 = c.u(c.number(row[1]));
            const y0 = c.u(c.number(row[2]));
            const x1 = c.u(c.number(row[3]));
            const y1 = c.u(c.number(row[4]));
            var total = zero;
            var labels = [_]i64{0} ** 27;
            const region_count = c.n((x1 - x0 + 1) * (y1 - y0 + 1));
            for (y0..y1 + 1) |y| for (x0..x1 + 1) |x| {
                const pixel = pixels[y * width + x];
                total = v.add(total, pixel.color);
                labels[if (pixel.info) |info| info.hit.object else tracer.scene.objects.items.len] += 1;
            };
            for (&total) |*value| value.* = f.div(value.*, region_count);
            answers.add("pixels {d} mean {s}", .{ region_count, triple(total) });
            for (labels[0 .. tracer.scene.objects.items.len + 1], 0..) |amount, object| if (amount > 0) answers.add("label {c} {d}", .{ if (object < tracer.scene.objects.items.len) tracer.scene.objects.items[object].label else @as(u8, '.'), amount });
        }
    }
    try save(io, "queries.txt", answers);
}
