const std = @import("std");
const c = @import("dataset.zig");
const kdtree = @import("kdtree.zig");
const quadtree = @import("quadtree.zig");
const rtree_module = @import("rtree.zig");
const grid_module = @import("grid.zig");
const report = @import("report.zig");
const structures = [_][]const u8{ "kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect" };
const search_names = [_][]const u8{ "RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN" };
const quadrants = [_][]const u8{ "NW", "NE", "SW", "SE" };
const View = struct { region: c.Box, objects: std.ArrayList(c.Object) = .empty, children: std.ArrayList(*View) = .empty,
     count: usize = 0, depth: usize = 0, mark: []const u8 = "", kd: ?*const kdtree.Node = null, quad: ?*const quadtree.Node = null,
     rtree: ?*const rtree_module.Node = null };
fn childAdd(node: *View, child: *View) void {
    c.append(*View, &node.children, child);
    node.count += child.count;
}
fn kdView(node: *const kdtree.Node, region: c.Box, mark: []const u8) *View {
    const out = c.create(View, .{ .region = region, .depth = node.depth, .mark = mark, .kd = node, .count = 1 });
    c.append(c.Object, &out.objects, .{ .id = node.point.id, .box = node.point.box() });
    if (node.left) |left| {
        var box = region;
        if (node.depth % 2 == 0) box.x2 = node.point.x else box.y2 = node.point.y;
        childAdd(out, kdView(left, box, "L"));
    }
    if (node.right) |right| {
        var box = region;
        if (node.depth % 2 == 0) box.x1 = node.point.x else box.y1 = node.point.y;
        childAdd(out, kdView(right, box, "R"));
    }
    return out;
}
fn quadView(node: *const quadtree.Node, depth: usize, mark: []const u8) *View {
    const out = c.create(View, .{ .region = .{ .x1 = node.x, .y1 = node.y, .x2 = node.x + node.size - 1,
         .y2 = node.y + node.size - 1 }, .depth = depth, .mark = mark, .quad = node });
    if (node.leaf()) {
        for (node.points.items) |point| c.append(c.Object, &out.objects, .{ .id = point.id, .box = point.box() });
        out.count = out.objects.items.len;
    } else for (node.children, 0..) |child, i| {
        childAdd(out, quadView(child.?, depth + 1, quadrants[i]));
    };
    return out;
}
fn rView(node: *const rtree_module.Node, depth: usize) *View {
    const out = c.create(View, .{ .region = node.box(), .depth = depth, .rtree = node });
    if (node.level == 0) {
        for (node.entries.items) |entry| c.append(c.Object, &out.objects, .{ .id = entry.id, .box = entry.box });
        out.count = out.objects.items.len;
    } else for (node.entries.items) |entry| {
        childAdd(out, rView(entry.child.?, depth + 1));
    };
    return out;
}
fn gridView(grid: grid_module.Grid) *View {
    const out = c.create(View, .{ .region = .{ .x1 = 0, .y1 = 0, .x2 = c.n(grid.world) - 1, .y2 = c.n(grid.world) - 1 } });
    for (0..grid.dimension) |j| for (0..grid.dimension) |i| {
        const cell = c.create(View, .{ .region = .{ .x1 = c.n(i * grid.side), .y1 = c.n(j * grid.side),
             .x2 = c.n(i * grid.side + grid.side) - 1, .y2 = c.n(j * grid.side + grid.side) - 1 },
             .depth = 1 });
        for (grid.cells[j * grid.dimension + i].items) |point| c.append(c.Object, &cell.objects, .{ .id = point.id,
             .box = point.box() });
        cell.count = cell.objects.items.len;
        childAdd(out, cell);
    };
    return out;
}
const Trees = struct { kd: *const kdtree.Node, quad: *const quadtree.Node, rtree: *const rtree_module.Tree,
     str: *const rtree_module.Tree, grid: *const grid_module.Grid, rect: *const rtree_module.Tree,
     str_rect: *const rtree_module.Tree, world: usize };
fn views(trees: Trees) [7]*View {
    return .{ kdView(trees.kd, .{ .x1 = 0, .y1 = 0, .x2 = c.n(trees.world) - 1, .y2 = c.n(trees.world) - 1 },
         "root"), quadView(trees.quad, 0, "root"), rView(trees.rtree.root, 0), rView(trees.str.root,
         0), gridView(trees.grid.*), rView(trees.rect.root, 0), rView(trees.str_rect.root, 0) };
}
const Visit = struct { nodes: usize = 0, tests: usize = 0 };
const Pair = struct { id: i64, value: i64 };
const Answer = struct { values: std.ArrayList(Pair) = .empty, count: usize = 0 };
fn pairLess(_: void, a: Pair, b: Pair) bool {
    return if (a.id != b.id) a.id < b.id else a.value < b.value;
}
fn nearestLess(_: void, a: Pair, b: Pair) bool {
    return if (a.value != b.value) a.value < b.value else a.id < b.id;
}
fn answerEqual(a: Answer, b: Answer) bool {
    if (a.count != b.count or a.values.items.len != b.values.items.len) return false;
    for (a.values.items, b.values.items) |x, y| if (x.id != y.id or x.value != y.value) return false;
    return true;
}
fn commandBox(command: c.Command) c.Box {
    return .{ .x1 = command.values[0], .y1 = command.values[1], .x2 = command.values[2], .y2 = command.values[3] };
}
fn regionCondition(command: c.Command, region: c.Box) bool {
    if (c.eq(command.name, "RANGE") or c.eq(command.name, "WINDOWCOUNT")) return rtree_module.intersects(region,
         commandBox(command));
    if (c.eq(command.name, "CONTAINS")) return rtree_module.contains(region, .{ .x1 = command.values[0],
         .y1 = command.values[1], .x2 = command.values[0], .y2 = command.values[1] });
    return rtree_module.distance(command.values[0], command.values[1], region) <= command.values[2] * command.values[2];
}
fn objectCondition(command: c.Command, object: c.Object) bool {
    if (c.eq(command.name, "RANGE") or c.eq(command.name, "WINDOWCOUNT")) return rtree_module.contains(commandBox(command),
         object.box);
    if (c.eq(command.name, "CONTAINS")) return rtree_module.contains(object.box, .{ .x1 = command.values[0],
         .y1 = command.values[1], .x2 = command.values[0], .y2 = command.values[1] });
    return rtree_module.distance(command.values[0], command.values[1], object.box) <= command.values[2] * command.values[2];
}
fn conditionSearch(node: *const View, command: c.Command, visit: *Visit, answer: *Answer) void {
    visit.nodes += 1;
    if (c.eq(command.name, "WINDOWCOUNT") and rtree_module.contains(commandBox(command), node.region)) {
        answer.count += node.count;
        return;
    }
    visit.tests += node.objects.items.len;
    for (node.objects.items) |object| if (objectCondition(command, object)) {
        if (c.eq(command.name, "WINDOWCOUNT")) answer.count += 1 else c.append(Pair, &answer.values,
             .{ .id = object.id, .value = 0 });
    };
    for (node.children.items) |child| if (regionCondition(command, child.region)) conditionSearch(child, command, visit, answer);
}
const QueueElement = struct { distance: i64, tie: i64, kind: u8 = 0, node: ?*const View = null, object: c.Object = .{ .id = 0,
     .box = .{} } };
fn earlier(a: QueueElement, b: QueueElement) bool {
    return a.distance < b.distance or (a.distance == b.distance and (a.kind < b.kind or (a.kind == b.kind and a.tie < b.tie)));
}
const Queue = struct {
    values: std.ArrayList(QueueElement) = .empty,
    fn push(self: *Queue, value: QueueElement) void {
        c.append(QueueElement, &self.values, value);
        var i = self.values.items.len - 1;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (!earlier(value, self.values.items[parent])) break;
            self.values.items[i] = self.values.items[parent];
            i = parent;
        }
        self.values.items[i] = value;
    }
    fn pop(self: *Queue) QueueElement {
        const out = self.values.items[0];
        const value = self.values.pop().?;
        if (self.values.items.len == 0) return out;
        var i: usize = 0;
        while (2 * i + 1 < self.values.items.len) {
            var child = 2 * i + 1;
            if (child + 1 < self.values.items.len and earlier(self.values.items[child + 1], self.values.items[child])) child += 1;
            if (!earlier(self.values.items[child], value)) break;
            self.values.items[i] = self.values.items[child];
            i = child;
        }
        self.values.items[i] = value;
        return out;
    }
};
fn bestFirst(root: *const View, command: c.Command, visit: *Visit) Answer {
    var out: Answer = .{};
    var queue: Queue = .{};
    var serial: i64 = 0;
    const x = command.values[0];
    const y = command.values[1];
    const k = c.u(command.values[2]);
    queue.push(.{ .distance = rtree_module.distance(x, y, root.region), .tie = serial, .node = root });
    serial += 1;
    while (queue.values.items.len > 0) {
        const element = queue.pop();
        if (element.kind == 1) {
            c.append(Pair, &out.values, .{ .id = element.object.id, .value = element.distance });
            if (out.values.items.len == k) break;
        } else {
            const node = element.node.?;
            visit.nodes += 1;
            visit.tests += node.objects.items.len;
            for (node.objects.items) |object| queue.push(.{ .distance = rtree_module.distance(x, y,
                 object.box), .kind = 1, .tie = object.id, .object = object });
            for (node.children.items) |child| {
                queue.push(.{ .distance = rtree_module.distance(x, y, child.region), .tie = serial, .node = child });
                serial += 1;
            }
        }
    }
    out.count = out.values.items.len;
    return out;
}
fn search(root: *const View, command: c.Command, visit: *Visit) Answer {
    if (c.eq(command.name, "KNN") or c.eq(command.name, "NEAREST")) return bestFirst(root, command, visit);
    var out: Answer = .{};
    conditionSearch(root, command, visit, &out);
    if (!c.eq(command.name, "WINDOWCOUNT")) {
        std.mem.sort(Pair, out.values.items, {}, pairLess);
        out.count = out.values.items.len;
    }
    return out;
}
fn spatialJoin(a: *const View, b: *const View, visit: *Visit, answer: *Answer) void {
    visit.nodes += 1;
    const al = a.children.items.len == 0;
    const bl = b.children.items.len == 0;
    if (al and bl) {
        visit.tests += a.objects.items.len * b.objects.items.len;
        for (a.objects.items) |point| for (b.objects.items) |rect| {
            if (rtree_module.contains(rect.box, point.box)) c.append(Pair, &answer.values, .{ .id = rect.id, .value = point.id });
        };
    } else if (al) {
        for (b.children.items) |child| if (rtree_module.intersects(a.region, child.region)) {
            spatialJoin(a, child, visit, answer);
        };
    } else if (bl) {
        for (a.children.items) |child| if (rtree_module.intersects(child.region, b.region)) {
            spatialJoin(child, b, visit, answer);
        };
    } else for (a.children.items) |left| for (b.children.items) |right| {
        if (rtree_module.intersects(left.region, right.region)) spatialJoin(left, right, visit, answer);
    };
}
fn brute(command: c.Command, points: []const c.Point, rectangles: []const c.Object) Answer {
    var out: Answer = .{};
    if (c.eq(command.name, "JOIN")) {
        for (rectangles) |rect| for (points) |point| {
            if (rtree_module.contains(rect.box, point.box())) c.append(Pair, &out.values, .{ .id = rect.id, .value = point.id });
        };
        std.mem.sort(Pair, out.values.items, {}, pairLess);
        out.count = out.values.items.len;
        return out;
    }
    var objects: std.ArrayList(c.Object) = .empty;
    if (c.eq(command.name, "CONTAINS") or c.eq(command.name, "NEAREST")) {
        for (rectangles) |object| c.append(c.Object, &objects, object);
    } else for (points) |point| {
        c.append(c.Object, &objects, .{ .id = point.id, .box = point.box() });
    };
    const nearest = c.eq(command.name, "KNN") or c.eq(command.name, "NEAREST");
    if (nearest) {
        for (objects.items) |object| c.append(Pair, &out.values, .{ .id = object.id, .value = rtree_module.distance(command.values[0],
             command.values[1], object.box) });
        std.mem.sort(Pair, out.values.items, {}, nearestLess);
        out.values.items = out.values.items[0..c.u(command.values[2])];
    } else for (objects.items) |object| if (objectCondition(command, object)) {
        if (c.eq(command.name, "WINDOWCOUNT")) out.count += 1 else c.append(Pair, &out.values, .{ .id = object.id, .value = 0 });
    };
    if (!c.eq(command.name, "WINDOWCOUNT")) {
        if (!nearest) std.mem.sort(Pair, out.values.items, {}, pairLess);
        out.count = out.values.items.len;
    }
    return out;
}
fn boxText(box: c.Box) []const u8 {
    return c.fmt("{d} {d} {d} {d}", .{ box.x1, box.y1, box.x2, box.y2 });
}
fn indent(depth: usize) []const u8 {
    const out = c.alloc(u8, 2 * (depth + 1));
    @memset(out, ' ');
    return out;
}
fn dump(out: *c.Lines, node: *const View) void {
    var line: c.Text = .{};
    line.add("{s}", .{indent(node.depth)});
    if (node.kd) |kd| {
        line.add("{s} {s} {d} {d} {d} box {s}", .{ node.mark, if (node.depth % 2 == 0) "x" else "y",
             kd.point.id, kd.point.x, kd.point.y, boxText(node.region) });
    } else if (node.quad) |quad| {
        line.add("{s} {d} {d} {d}", .{ node.mark, quad.x, quad.y, quad.size });
        if (quad.leaf()) {
            const values = c.alloc(i64, node.objects.items.len);
            for (node.objects.items, values) |object, *value| value.* = object.id;
            line.add(" leaf {s}", .{report.ids(values)});
        } else line.add(" node count {d}", .{node.count});
    } else if (node.rtree) |rtree| {
        if (rtree.level == 0) {
            const values = c.alloc(i64, node.objects.items.len);
            for (node.objects.items, values) |object, *value| value.* = object.id;
            line.add("leaf {s} ids {s}", .{ boxText(node.region), report.ids(values) });
        } else line.add("node {d} {s} entries {d}", .{ rtree.level, boxText(node.region), rtree.entries.items.len });
    }
    out.add("{s}", .{line.value()});
    for (node.children.items) |child| dump(out, child);
}
fn flatten(node: *const View, out: *std.ArrayList(*const View)) void {
    c.append(*const View, out, node);
    for (node.children.items) |child| flatten(child, out);
}
fn kdStats(out: *c.Lines, root: *const View) void {
    var nodes: std.ArrayList(*const View) = .empty;
    flatten(root, &nodes);
    var height: usize = 0;
    var leaves: usize = 0;
    var one: usize = 0;
    var depth_sum: usize = 0;
    for (nodes.items) |node| {
        height = @max(height, node.depth + 1);
        leaves += @intFromBool(node.children.items.len == 0);
        one += @intFromBool(node.children.items.len == 1);
        depth_sum += node.depth;
    }
    const levels = c.alloc([3]usize, height);
    @memset(levels, .{ 0, 0, 0 });
    for (nodes.items) |node| {
        levels[node.depth][0] += 1;
        levels[node.depth][1] += @intFromBool(node.children.items.len == 0);
        levels[node.depth][2] += @intFromBool(node.children.items.len == 1);
    }
    var ideal: usize = 0;
    var capacity: usize = 0;
    while (capacity < nodes.items.len) {
        capacity = 2 * capacity + 1;
        ideal += 1;
    }
    out.add("kdtree height {d} ideal {d} nodes {d} leaves {d} one_child {d} depth_sum {d} avg_depth {s}",
         .{ height, ideal, nodes.items.len, leaves, one, depth_sum, report.fraction(depth_sum, nodes.items.len) });
    for (levels, 0..) |value, depth| out.add("  depth {d} nodes {d} leaves {d} one_child {d}", .{ depth,
         value[0], value[1], value[2] });
}
fn quadStats(out: *c.Lines, root: *const View, bucket: usize) void {
    var nodes: std.ArrayList(*const View) = .empty;
    flatten(root, &nodes);
    var height: usize = 0;
    for (nodes.items) |node| height = @max(height, node.depth + 1);
    const levels = c.alloc([3]usize, height);
    @memset(levels, .{ 0, 0, 0 });
    var internal: usize = 0;
    var leaves: usize = 0;
    var empty: usize = 0;
    var maximum: usize = 0;
    for (nodes.items) |node| {
        if (node.children.items.len == 0) {
            leaves += 1;
            empty += @intFromBool(node.objects.items.len == 0);
            maximum = @max(maximum, node.objects.items.len);
            levels[node.depth][1] += 1;
            levels[node.depth][2] += node.objects.items.len;
        } else {
            internal += 1;
            levels[node.depth][0] += 1;
        }
    }
    out.add("quadtree height {d} internal {d} leaves {d} empty {d} max_leaf {d} fill {s}", .{ height,
         internal, leaves, empty, maximum, report.fraction(root.count, leaves * bucket) });
    for (levels, 0..) |value, depth| out.add("  depth {d} internal {d} leaves {d} points {d}", .{ depth,
         value[0], value[1], value[2] });
}
fn rStats(out: *c.Lines, root: *const View, name: []const u8, maximum: usize, minimum: usize) void {
    var nodes: std.ArrayList(*const View) = .empty;
    flatten(root, &nodes);
    var leaves: usize = 0;
    var entries: usize = 0;
    for (nodes.items) |node| {
        leaves += @intFromBool(node.rtree.?.level == 0);
        entries += node.rtree.?.entries.items.len;
    }
    out.add("{s} height {d} nodes {d} leaves {d} entries {d} fill {s}", .{ name, root.rtree.?.level + 1,
         nodes.items.len, leaves, entries, report.fraction(entries, nodes.items.len * maximum) });
    var remaining = root.rtree.?.level + 1;
    while (remaining > 0) {
        remaining -= 1;
        const level = remaining;
        var count: usize = 0;
        var low: usize = 65;
        var high: usize = 0;
        var under: usize = 0;
        var total_area: i64 = 0;
        var total_overlap: i64 = 0;
        var nlevel: usize = 0;
        for (nodes.items, 0..) |node, i| {
            if (node.rtree.?.level != level) continue;
            nlevel += 1;
            const n = node.rtree.?.entries.items.len;
            count += n;
            low = @min(low, n);
            high = @max(high, n);
            under += @intFromBool(n < minimum);
            total_area += rtree_module.area(node.region);
            for (nodes.items[i + 1 ..]) |other| if (other.rtree.?.level == level) {
                total_overlap += rtree_module.overlap(node.region, other.region);
            };
        }
        out.add("  level {d} nodes {d} entries {d} min {d} max {d} under {d} area {d} overlap {d}",
             .{ level, nlevel, count, low, high, under, total_area, total_overlap });
    }
}
fn gridStats(out: *c.Lines, grid: grid_module.Grid) void {
    var used: usize = 0;
    var maximum: usize = 0;
    for (grid.cells) |cell| {
        used += @intFromBool(cell.items.len > 0);
        maximum = @max(maximum, cell.items.len);
    }
    const counts = c.alloc(usize, maximum + 1);
    @memset(counts, 0);
    for (grid.cells) |cell| counts[cell.items.len] += 1;
    out.add("grid cells {d} used {d} max {d}", .{ grid.cells.len, used, maximum });
    var line: c.Text = .{};
    line.add("  occupancy", .{});
    for (counts, 0..) |count, k| if (count > 0) line.add(" {d}:{d}", .{ k, count });
    out.add("{s}", .{line.value()});
}
fn pathText(values: []const usize) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else "/", value });
    return out.value();
}
fn rLocation(node: *const rtree_module.Node, point: c.Point, path: *std.ArrayList(usize)) bool {
    for (node.entries.items, 0..) |entry, i| {
        if (node.level == 0) {
            if (entry.id == point.id) {
                c.append(usize, path, i + 1);
                return true;
            }
        } else if (rtree_module.contains(entry.box, point.box())) {
            c.append(usize, path, i + 1);
            if (rLocation(entry.child.?, point, path)) return true;
            _ = path.pop();
        }
    }
    return false;
}
fn copyLines(out: *c.Lines, source: c.Lines) void {
    for (source.data.items) |line| out.add("{s}", .{line});
}
fn recordSnapshot(gpa: std.mem.Allocator, snapshot: usize, query: usize, points: []const c.Point,
     rectangles: []const c.Object, p: c.Params, trees: Trees, structures_file: *c.Lines, stats: *c.Lines) void {
    const saved = c.allocator;
    var temporary = std.heap.ArenaAllocator.init(gpa);
    defer temporary.deinit();
    c.allocator = temporary.allocator();
    defer c.allocator = saved;
    var structure_lines: c.Lines = .{};
    var stat_lines: c.Lines = .{};
    if (snapshot > 0) {
        structure_lines.add("", .{});
        stat_lines.add("", .{});
    }
    const heading = c.fmt("snapshot {d} query {d} points {d} rects {d}", .{ snapshot, query, points.len, rectangles.len });
    structure_lines.add("{s}", .{heading});
    stat_lines.add("{s}", .{heading});
    const roots = views(trees);
    for ([_]usize{ 0, 1, 2, 3, 5, 6 }) |structure| {
        structure_lines.add("{s}", .{structures[structure]});
        dump(&structure_lines, roots[structure]);
    }
    kdStats(&stat_lines, roots[0]);
    quadStats(&stat_lines, roots[1], p.bucket);
    for ([_]usize{ 2, 3, 5, 6 }) |structure| rStats(&stat_lines, roots[structure], structures[structure], p.maximum, p.minimum);
    gridStats(&stat_lines, trees.grid.*);
    c.allocator = saved;
    copyLines(structures_file, structure_lines);
    copyLines(stats, stat_lines);
}
const Aggregate = struct { queries: usize = 0, nodes: usize = 0, tests: usize = 0, maximum: usize = 0 };
fn processSearch(gpa: std.mem.Allocator, query: usize, command: c.Command, points: []const c.Point,
     rectangles: []const c.Object, trees: Trees, aggregates: *[7][7]Aggregate, answers: *c.Lines,
     visits: *c.Lines, join_file: *c.Lines) void {
    const saved = c.allocator;
    var temporary = std.heap.ArenaAllocator.init(gpa);
    defer temporary.deinit();
    c.allocator = temporary.allocator();
    defer c.allocator = saved;
    var type_: usize = 0;
    for (search_names, 0..) |name, i| if (c.eq(name, command.name)) {
        type_ = i;
        break;
    };
    const roots = views(trees);
    const expected = brute(command, points, rectangles);
    const selected: []const usize = if (c.eq(command.name, "CONTAINS") or c.eq(command.name, "NEAREST")) &.{ 5,
         6 } else if (c.eq(command.name, "JOIN")) &.{ 2, 3 } else &.{ 0, 1, 2, 3, 4 };
    var mismatches: std.ArrayList(usize) = .empty;
    var visit_lines: c.Lines = .{};
    var join_lines: c.Lines = .{};
    for (selected) |structure| {
        var visit: Visit = .{};
        var actual: Answer = .{};
        if (c.eq(command.name, "JOIN")) {
            spatialJoin(roots[structure], roots[if (structure == 2) 5 else 6], &visit, &actual);
            std.mem.sort(Pair, actual.values.items, {}, pairLess);
            actual.count = actual.values.items.len;
        } else actual = search(roots[structure], command, &visit);
        if (!answerEqual(actual, expected)) c.append(usize, &mismatches, structure);
        visit_lines.add("{d},{s},{s},{d},{d}", .{ query, command.name, structures[structure], visit.nodes, visit.tests });
        const aggregate = &aggregates[type_][structure];
        aggregate.queries += 1;
        aggregate.nodes += visit.nodes;
        aggregate.tests += visit.tests;
        aggregate.maximum = @max(aggregate.maximum, visit.nodes);
    }
    var line: c.Text = .{};
    line.add("{d} {s} count {d}", .{ query, command.name, expected.count });
    if (c.eq(command.name, "RANGE") or c.eq(command.name, "RADIUS") or c.eq(command.name, "CONTAINS")) {
        const values = c.alloc(i64, expected.values.items.len);
        for (expected.values.items, values) |entry, *value| value.* = entry.id;
        line.add(" ids {s}", .{report.ids(values)});
    } else if (c.eq(command.name, "KNN") or c.eq(command.name, "NEAREST")) {
        line.add(" ids", .{});
        for (expected.values.items) |entry| line.add(" {d}:{d}", .{ entry.id, entry.value });
    } else if (c.eq(command.name, "JOIN")) {
        for (expected.values.items) |entry| join_lines.add("{d},{d},{d}", .{ query, entry.id, entry.value });
    }
    line.add(" check {s}", .{if (mismatches.items.len == 0) "ok" else "mismatch"});
    for (mismatches.items) |structure| line.add(" {s}", .{structures[structure]});
    const result = line.value();
    c.allocator = saved;
    answers.add("{s}", .{result});
    copyLines(visits, visit_lines);
    copyLines(join_file, join_lines);
}
fn aggregateLess(values: []const Aggregate, a: usize, b: usize) bool {
    return if (values[a].nodes != values[b].nodes) values[a].nodes < values[b].nodes else if (values[a].tests != values[b].tests) values[a].tests < values[b].tests else a < b;
}
fn pointIndex(points: []const c.Point, id: i64) ?usize {
    for (points, 0..) |point, i| if (point.id == id) return i;
    return null;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.readInput(init.io);
    const p = input.params;
    var points: std.ArrayList(c.Point) = .empty;
    for (input.points) |point| c.pointInsert(&points, point);
    var kd = kdtree.build(input.points, 0);
    const quad = c.create(quadtree.Node, .{ .size = c.n(p.world) });
    var grid = grid_module.Grid.init(p.world, p.grid);
    var rtree = rtree_module.Tree.init(p.maximum, p.minimum);
    var str = rtree_module.Tree.init(p.maximum, p.minimum);
    var rect = rtree_module.Tree.init(p.maximum, p.minimum);
    var str_rect = rtree_module.Tree.init(p.maximum, p.minimum);
    const point_entries = c.alloc(rtree_module.Entry, input.points.len);
    const rect_entries = c.alloc(rtree_module.Entry, input.rectangles.len);
    for (input.points, point_entries) |point, *entry| {
        quadtree.insert(quad, point, p.bucket);
        grid.insert(point);
        entry.* = .{ .box = point.box(), .id = point.id, .number = point.id };
        rtree.insert(entry.*, 0);
    }
    for (input.rectangles, rect_entries) |object, *entry| {
        entry.* = .{ .box = object.box, .id = object.id, .number = object.id };
        rect.insert(entry.*, 0);
    }
    str.bulk(point_entries);
    str_rect.bulk(rect_entries);
    var answers: c.Lines = .{};
    var visits: c.Lines = .{};
    var join_file: c.Lines = .{};
    var structures_file: c.Lines = .{};
    var stats: c.Lines = .{};
    visits.add("query,command,structure,nodes,tests", .{});
    join_file.add("query,rect,point", .{});
    var aggregates = std.mem.zeroes([7][7]Aggregate);
    var snapshot: usize = 0;
    var trees: Trees = .{ .kd = kd.?, .quad = quad, .rtree = &rtree, .str = &str, .grid = &grid, .rect = &rect,
         .str_rect = &str_rect, .world = p.world };
    recordSnapshot(init.gpa, 0, 0, points.items, input.rectangles, p, trees, &structures_file, &stats);
    for (input.commands, 1..) |command, query| {
        const name = command.name;
        if (c.eq(name, "INSERT")) {
            const point: c.Point = .{ .id = command.values[0], .x = command.values[1], .y = command.values[2] };
            c.pointInsert(&points, point);
            kd = kdtree.insert(kd, point, 0);
            quadtree.insert(quad, point, p.bucket);
            grid.insert(point);
            const entry: rtree_module.Entry = .{ .box = point.box(), .id = point.id, .number = point.id };
            rtree.insert(entry, 0);
            str.insert(entry, 0);
            answers.add("{d} INSERT {d} inserted points {d}", .{ query, point.id, points.items.len });
        } else if (c.eq(name, "DELETE")) {
            const id = command.values[0];
            if (pointIndex(points.items, id)) |index| {
                const point = points.items[index];
                kd = kdtree.delete(kd, point);
                quadtree.delete(quad, point, p.bucket);
                rtree.delete(point);
                str.delete(point);
                grid.delete(point);
                c.pointRemove(&points, id);
                answers.add("{d} DELETE {d} deleted points {d}", .{ query, id, points.items.len });
            } else answers.add("{d} DELETE {d} missing points {d}", .{ query, id, points.items.len });
        } else if (c.eq(name, "DUMP")) {
            snapshot += 1;
            trees.kd = kd.?;
            recordSnapshot(init.gpa, snapshot, query, points.items, input.rectangles, p, trees, &structures_file, &stats);
            answers.add("{d} DUMP snapshot {d}", .{ query, snapshot });
        } else if (c.eq(name, "LOCATE")) {
            const id = command.values[0];
            if (pointIndex(points.items, id)) |index| {
                const point = points.items[index];
                var kd_path: c.Text = .{};
                var node = kd.?;
                while (node.point.id != id) {
                    const left = kdtree.keyLess(point, node.point, node.depth % 2);
                    kd_path.add("{c}", .{if (left) @as(u8, 'L') else @as(u8, 'R')});
                    node = if (left) node.left.? else node.right.?;
                }
                var quad_path: c.Text = .{};
                var q = quad;
                while (!q.leaf()) {
                    const child = quadtree.destination(q.*, point);
                    quad_path.add("{s}{s}", .{ if (quad_path.value().len == 0) "" else "/", quadrants[child] });
                    q = q.children[child].?;
                }
                var a: std.ArrayList(usize) = .empty;
                var b: std.ArrayList(usize) = .empty;
                _ = rLocation(rtree.root, point, &a);
                _ = rLocation(str.root, point, &b);
                answers.add("{d} LOCATE {d} kdtree {s} quadtree {s} rtree {s} str {s} grid {d} {d}",
                     .{ query, id, if (kd_path.value().len == 0) "-" else kd_path.value(), if (quad_path.value().len == 0) "-" else quad_path.value(),
                     pathText(a.items), pathText(b.items), c.u(point.x) / p.grid, c.u(point.y) / p.grid });
            } else answers.add("{d} LOCATE {d} missing", .{ query, id });
        } else {
            trees.kd = kd.?;
            processSearch(init.gpa, query, command, points.items, input.rectangles, trees, &aggregates,
                 &answers, &visits, &join_file);
        }
    }
    stats.add("", .{});
    stats.add("visits", .{});
    for (search_names, 0..) |name, type_| {
        var selected: std.ArrayList(usize) = .empty;
        for (aggregates[type_], 0..) |value, structure| if (value.queries > 0) {
            c.append(usize, &selected, structure);
            stats.add("{s} {s} queries {d} nodes {d} tests {d} max_nodes {d} mean_nodes {s}", .{ name,
                 structures[structure], value.queries, value.nodes, value.tests, value.maximum, report.fraction(value.nodes,
                 value.queries) });
        };
        if (selected.items.len == 0) continue;
        std.mem.sort(usize, selected.items, @as([]const Aggregate, aggregates[type_][0..]), aggregateLess);
        var line: c.Text = .{};
        line.add("rank {s}", .{name});
        for (selected.items) |structure| line.add(" {s}", .{structures[structure]});
        stats.add("{s}", .{line.value()});
    }
    try report.write(init.io, "answers.txt", answers);
    try report.write(init.io, "visits.csv", visits);
    try report.write(init.io, "join.csv", join_file);
    try report.write(init.io, "structures.txt", structures_file);
    try report.write(init.io, "stats.txt", stats);
}
