const std = @import("std");
const d = @import("model_io.zig");
const a = @import("assembly.zig");
const solver = @import("solver.zig");
const post = @import("postprocess.zig");
const design = @import("design.zig");
const f = d.f;
const n = d.n;
const u = d.u;
fn realDigits(value: f64, comptime digits: usize) []const u8 {
    const text = if (digits == 6) d.fmt("{d:.6}", .{value}) else if (digits == 1) d.fmt("{d:.1}",
         .{value}) else d.fmt("{d:.4}", .{value});
    return if (text[0] == '-' and d.decimal(text) == 0) text[1..] else text;
}
fn real(value: f64) []const u8 {
    return realDigits(value, 4);
}
fn rounded(value: f64) f64 {
    return d.decimal(real(value));
}
fn extreme(values: []const f64, minimum: bool) usize {
    var chosen: usize = 0;
    var best = rounded(values[0]);
    for (values[1..], 1..) |entry, i| {
        const value = rounded(entry);
        if (if (minimum) value < best else value > best) {
            chosen = i;
            best = value;
        }
    }
    return chosen;
}
fn save(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
const System = struct { properties: []const a.Properties, matrix: a.Matrix, free_matrix: a.Matrix,
     lower: a.Matrix, unstable: ?usize, removed: ?usize };
const Group = struct { name: []const u8, members: std.ArrayList(usize) = .empty };
const Point = struct { column: i64, row: i64 };
const Canvas = struct {
    x0: i64,
    y1: i64,
    horizontal: i64,
    vertical: i64,
    width: usize,
    height: usize,
    grid: [][]u8,
    fn init(nodes: []const d.Node, wc: i64, hc: i64) Canvas {
        var x0 = nodes[0].x;
        var x1 = x0;
        var y0 = nodes[0].y;
        var y1 = y0;
        for (nodes) |node| {
            x0 = @min(x0, node.x);
            x1 = @max(x1, node.x);
            y0 = @min(y0, node.y);
            y1 = @max(y1, node.y);
        }
        const width = u(@as(i64, @intFromFloat(@floor(f(x1 - x0) / f(wc) + 0.5))) + 5);
        const height = u(@as(i64, @intFromFloat(@floor(f(y1 - y0) / f(hc) + 0.5))) + 5);
        const grid = d.alloc([]u8, height);
        for (grid) |*row| {
            row.* = d.alloc(u8, width);
            @memset(row.*, ' ');
        }
        return .{ .x0 = x0, .y1 = y1, .horizontal = wc, .vertical = hc, .width = width, .height = height,
             .grid = grid };
    }
    fn position(self: Canvas, x: f64, y: f64) Point {
        return .{ .column = @as(i64, @intFromFloat(@floor((x - f(self.x0)) / f(self.horizontal) + 0.5))) + 2,
             .row = @as(i64, @intFromFloat(@floor((f(self.y1) - y) / f(self.vertical) + 0.5))) + 2 };
    }
    fn put(self: *Canvas, point: Point, character: u8) void {
        if (point.column >= 0 and point.column < n(self.width) and point.row >= 0 and point.row < n(self.height)) self.grid[u(point.row)][u(point.column)] = character;
    }
    fn segment(self: *Canvas, first: Point, last: Point, character: u8) void {
        var c = first.column;
        var r = first.row;
        const dc = n(@abs(last.column - c));
        const dr = -n(@abs(last.row - r));
        const sc: i64 = if (c < last.column) 1 else -1;
        const sr: i64 = if (r < last.row) 1 else -1;
        var line_error = dc + dr;
        while (true) {
            self.put(.{ .column = c, .row = r }, character);
            if (c == last.column and r == last.row) break;
            const twice = 2 * line_error;
            if (twice >= dr) {
                line_error += dr;
                c += sc;
            }
            if (twice <= dc) {
                line_error += dc;
                r += sr;
            }
        }
    }
    fn appendFrame(self: Canvas, out: *d.Lines) void {
        const middle = d.alloc(u8, self.width);
        @memset(middle, '-');
        out.add("+{s}+", .{middle});
        for (self.grid) |row| out.add("|{s}|", .{row});
        out.add("+{s}+", .{middle});
    }
};
const Truss = struct {
    model: d.Model,
    degrees: usize,
    order: []usize,
    numbers: []usize,
    node_dofs: [][2]usize,
    owners: [][2]usize,
    adjacent: [40][40]bool = [_][40]bool{[_]bool{false} ** 40} ** 40,
    degree: [40]usize = [_]usize{0} ** 40,
    free: []const usize = &.{},
    restrained: []const usize = &.{},
    support_directions: std.ArrayList([3]usize) = .empty,
    prescribed: []f64,
    choices: []usize,
    groups: std.ArrayList(Group) = .empty,
    geometry: []const a.Geometry = &.{},
    final_system: System = undefined,
    results: []const post.Result = &.{},
    combinations: []const post.Result = &.{},
    units: []?post.Result,
    limits: []f64,
    uses: [][]f64,
    governing: []f64,
    governing_cases: []usize,
    weight: f64 = 0,
    history: d.Lines = .{},
    fn nodeBefore(self: *const Truss, left: usize, right: usize) bool {
        return self.degree[left] < self.degree[right] or (self.degree[left] == self.degree[right] and self.model.nodes[left].id < self.model.nodes[right].id);
    }
    fn init(model: d.Model) Truss {
        const nodes = model.nodes.len;
        const members = model.members.len;
        var self: Truss = .{ .model = model, .degrees = 2 * nodes, .order = d.alloc(usize,
             nodes), .numbers = d.alloc(usize, nodes), .node_dofs = d.alloc([2]usize, nodes),
             .owners = d.alloc([2]usize, 2 * nodes), .prescribed = a.zeros(2 * nodes), .choices = d.alloc(usize,
             members), .units = d.alloc(?post.Result, nodes), .limits = d.alloc(f64, members),
             .uses = d.alloc([]f64, members), .governing = d.alloc(f64, members), .governing_cases = d.alloc(usize,
             members) };
        @memset(self.units, null);
        for (model.members, 0..) |member, i| {
            self.adjacent[member.start][member.end] = true;
            self.adjacent[member.end][member.start] = true;
            self.choices[i] = member.section;
            var group: usize = 0;
            while (group < self.groups.items.len and !d.eq(self.groups.items[group].name, member.group)) : (group += 1) {}
            if (group == self.groups.items.len) d.append(Group, &self.groups, .{ .name = member.group });
            d.append(usize, &self.groups.items[group].members, i);
        }
        for (0..nodes) |i| for (0..nodes) |j| {
            if (self.adjacent[i][j]) self.degree[i] += 1;
        };
        var first: usize = 0;
        for (1..nodes) |node| if (self.nodeBefore(node, first)) {
            first = node;
        };
        self.order[0] = first;
        var count: usize = 1;
        var visited = [_]bool{false} ** 40;
        visited[first] = true;
        var position_index: usize = 0;
        while (position_index < count) : (position_index += 1) {
            var following: std.ArrayList(usize) = .empty;
            for (0..nodes) |node| if (self.adjacent[self.order[position_index]][node] and !visited[node]) d.append(usize,
                 &following, node);
            const Context = struct {
                fn less(context: *const Truss, left: usize, right: usize) bool {
                    return context.nodeBefore(left, right);
                }
            };
            std.mem.sort(usize, following.items, @as(*const Truss, &self), Context.less);
            for (following.items) |node| {
                visited[node] = true;
                self.order[count] = node;
                count += 1;
            }
        }
        std.mem.reverse(usize, self.order);
        for (self.order, 0..) |node, i| self.numbers[node] = i;
        for (0..nodes) |node| for (0..2) |axis| {
            const degree = 2 * self.numbers[node] + axis;
            self.node_dofs[node][axis] = degree;
            self.owners[degree] = .{ node, axis };
        };
        var fixed = [_]bool{false} ** 80;
        for (model.supports) |support| for (0..2) |axis| {
            if (support.fixed[axis]) {
                const degree = self.node_dofs[support.node][axis];
                self.prescribed[degree] = support.prescribed[axis];
                fixed[degree] = true;
                d.append([3]usize, &self.support_directions, .{ support.node, axis, degree });
            }
        };
        var free: std.ArrayList(usize) = .empty;
        var restrained: std.ArrayList(usize) = .empty;
        for (0..self.degrees) |degree| {
            if (fixed[degree]) d.append(usize, &restrained, degree) else d.append(usize, &free, degree);
        }
        self.free = free.items;
        self.restrained = restrained.items;
        self.geometry = a.memberGeometry(model, self.node_dofs);
        return self;
    }
    fn system(self: *const Truss, removed: ?usize) System {
        const properties = a.memberProperties(self.model, self.choices, self.geometry);
        const matrix = a.assemble(self.geometry, properties, self.degrees, removed);
        const free_matrix = a.matrix(self.free.len);
        for (self.free, 0..) |row, i| for (self.free, 0..) |column, j| {
            free_matrix[i][j] = matrix[row][column];
        };
        const factorization = solver.cholesky(free_matrix, self.free);
        return .{ .properties = properties, .matrix = matrix, .free_matrix = free_matrix, .lower = factorization.lower,
             .unstable = factorization.unstable, .removed = removed };
    }
    fn displacement(self: *const Truss, structure: System, force: []const f64, settlement: bool) []f64 {
        const out = a.zeros(self.degrees);
        const right = d.alloc(f64, self.free.len);
        for (self.restrained) |degree| out[degree] = if (settlement) self.prescribed[degree] else 0;
        for (self.free, right) |degree, *entry| {
            var value = force[degree];
            for (self.restrained) |fixed| value -= structure.matrix[degree][fixed] * out[fixed];
            entry.* = value;
        }
        const solution = solver.solve(structure.lower, right);
        for (self.free, solution) |degree, value| out[degree] = value;
        return out;
    }
    fn caseResult(self: *const Truss, structure: System, load_case: d.LoadCase) post.Result {
        const loading = a.loadVectors(load_case, self.geometry, structure.properties, self.node_dofs,
             self.degrees, structure.removed);
        const motion = self.displacement(structure, loading.total, loading.settlement);
        return .{ .name = load_case.name, .displacement = motion, .forces = post.axialForces(self.geometry,
             structure.properties, motion, loading.temperature, structure.removed), .reactions = post.reactions(structure.matrix,
             motion, loading.total, self.restrained), .external = loading.external };
    }
    fn analyze(self: *const Truss, structure: System) []const post.Result {
        const out = d.alloc(post.Result, self.model.cases.len + self.model.combinations.len);
        for (self.model.cases, 0..) |load_case, i| out[i] = self.caseResult(structure, load_case);
        for (self.model.combinations, 0..) |combination, i| out[self.model.cases.len + i] = post.superpose(combination,
             out);
        return out;
    }
    fn removalResult(self: *const Truss, structure: System, combination: d.Combination) post.Result {
        const cases = d.alloc(post.Result, self.model.cases.len);
        const needed = d.alloc(bool, self.model.cases.len);
        @memset(needed, false);
        for (combination.terms) |term| needed[term.index] = true;
        for (self.model.cases, 0..) |load_case, i| if (needed[i]) {
            cases[i] = self.caseResult(structure, load_case);
        };
        return post.superpose(combination, cases);
    }
    fn result(self: *const Truss, name: []const u8) post.Result {
        for (self.results) |item| if (d.eq(item.name, name)) return item;
        unreachable;
    }
    fn unitResult(self: *Truss, node: usize) post.Result {
        if (self.units[node]) |item| return item;
        const force = a.zeros(self.degrees);
        force[self.node_dofs[node][1]] = -1000;
        const motion = self.displacement(self.final_system, force, false);
        const item: post.Result = .{ .name = "unit", .displacement = motion, .forces = post.axialForces(self.geometry,
             self.final_system.properties, motion, a.zeros(self.model.members.len), null),
             .reactions = post.reactions(self.final_system.matrix, motion, force, self.restrained),
             .external = force };
        self.units[node] = item;
        return item;
    }
    fn magnitudes(self: *const Truss, item: post.Result) []f64 {
        const out = d.alloc(f64, self.model.nodes.len);
        for (self.node_dofs, out) |dofs, *value| {
            const x = item.displacement[dofs[0]];
            const y = item.displacement[dofs[1]];
            value.* = @sqrt(x * x + y * y);
        }
        return out;
    }
    fn metrics(self: *const Truss, mapping: []const usize) [2]i64 {
        var bandwidth: i64 = 0;
        var profile: i64 = 0;
        for (self.model.members) |member| bandwidth = @max(bandwidth, n(@abs(n(mapping[member.start]) - n(mapping[member.end]))));
        for (0..self.model.nodes.len) |node| {
            var low = mapping[node];
            for (0..self.model.nodes.len) |adjacent| if (self.adjacent[node][adjacent]) {
                low = @min(low, mapping[adjacent]);
            };
            profile += n(mapping[node]) - n(low);
        }
        return .{ bandwidth, profile };
    }
    fn designSections(self: *Truss) void {
        var last_round: usize = 0;
        var converged = false;
        for (1..11) |round| {
            last_round = round;
            self.final_system = self.system(null);
            self.results = self.analyze(self.final_system);
            self.combinations = self.results[self.model.cases.len..];
            var all_uses: std.ArrayList(f64) = .empty;
            self.weight = 0;
            for (0..self.model.members.len) |member| {
                self.limits[member] = design.slendernessLimit(member, self.combinations, self.model.settings.compression_limit,
                     self.model.settings.tension_limit);
                self.uses[member] = d.alloc(f64, self.combinations.len);
                for (self.combinations, self.uses[member]) |combination, *value| {
                    value.* = design.utilization(combination.forces[member], self.final_system.properties[member],
                         self.geometry[member], null);
                    d.append(f64, &all_uses, value.*);
                }
                self.weight += a.memberWeight(self.final_system.properties[member], self.geometry[member]);
            }
            const next = d.alloc(usize, self.groups.items.len);
            var changes: std.ArrayList(usize) = .empty;
            for (self.groups.items, next, 0..) |group, *selected, i| {
                selected.* = design.selectSection(group.members.items, self.model.sections,
                     self.final_system.properties, self.geometry, self.combinations, self.limits);
                if (selected.* != self.choices[group.members.items[0]]) d.append(usize, &changes, i);
            }
            const maximum = extreme(all_uses.items, false);
            const member = maximum / self.combinations.len;
            const combination = maximum % self.combinations.len;
            self.history.add("round {d} weight {s} max_utilization {s} at {d} {s} changes {d}",
                 .{ round, real(self.weight / 1000), real(all_uses.items[maximum]), self.model.members[member].id,
                 self.combinations[combination].name, changes.items.len });
            for (changes.items) |group_index| {
                const group = self.groups.items[group_index];
                var values: std.ArrayList(f64) = .empty;
                for (group.members.items) |m| for (self.uses[m]) |value| d.append(f64, &values, value);
                self.history.add("change {s} {s} {s} utilization {s}", .{ group.name, self.model.sections[self.choices[group.members.items[0]]].name,
                     self.model.sections[next[group_index]].name, real(values.items[extreme(values.items,
                     false)]) });
            }
            if (changes.items.len == 0) {
                converged = true;
                break;
            }
            if (round == 10) break;
            for (self.groups.items, next) |group, selected| for (group.members.items) |m| {
                self.choices[m] = selected;
            };
        }
        self.history.add("result {s} rounds {d}", .{ if (converged) "converged" else "not_converged", last_round });
        for (self.uses, self.governing, self.governing_cases) |values, *value, *chosen| {
            chosen.* = extreme(values, false);
            value.* = values[chosen.*];
        }
    }
    fn designReport(self: *const Truss) d.Lines {
        var out: d.Lines = .{};
        out.extend(self.history);
        for (self.groups.items) |group| {
            const values = d.alloc(f64, group.members.items.len);
            for (group.members.items, values) |member, *value| value.* = self.governing[member];
            const member = group.members.items[extreme(values, false)];
            out.add("group {s} section {s} members {d} utilization {s} at {d}", .{ group.name,
                 self.model.sections[self.choices[member]].name, group.members.items.len, real(self.governing[member]),
                 self.model.members[member].id });
        }
        for (self.model.members, 0..) |member, i| {
            const ratio = design.slenderness(self.final_system.properties[i], self.geometry[i], null);
            out.add("member {d} group {s} section {s} utilization {s} governing {s} slenderness {s} limit {s} {s}",
                 .{ member.id, member.group, self.model.sections[self.choices[i]].name, real(self.governing[i]),
                 self.combinations[self.governing_cases[i]].name, real(ratio), real(self.limits[i]),
                 if (self.governing[i] <= 1 and ratio <= self.limits[i]) "ok" else "over" });
        }
        const rank = d.alloc(usize, self.model.members.len);
        for (rank, 0..) |*member, i| member.* = i;
        const Context = struct {
            fn less(context: *const Truss, left: usize, right: usize) bool {
                const x = rounded(context.governing[left]);
                const y = rounded(context.governing[right]);
                return x > y or (x == y and left < right);
            }
        };
        std.mem.sort(usize, rank, self, Context.less);
        for (rank[0..@min(5, rank.len)], 1..) |member, i| out.add("rank {d} member {d} utilization {s}",
             .{ i, self.model.members[member].id, real(self.governing[member]) });
        for (self.model.members, 0..) |member, i| {
            const values = d.alloc(f64, self.combinations.len);
            for (self.combinations, values) |combination, *value| value.* = combination.forces[i] / 1000;
            const high = extreme(values, false);
            const low = extreme(values, true);
            out.add("envelope {d} max {s} {s} min {s} {s}", .{ member.id, real(values[high]),
                 self.combinations[high].name, real(values[low]), self.combinations[low].name });
        }
        for (self.model.sections, 0..) |section, i| {
            var count: usize = 0;
            var length: f64 = 0;
            for (self.choices, self.geometry) |choice, g| if (choice == i) {
                count += 1;
                length += g.length;
            };
            if (count > 0) out.add("section {s} members {d} length {s}", .{ section.name, count, real(length) });
        }
        out.add("weight {s}", .{real(self.weight / 1000)});
        return out;
    }
    fn analysisReport(self: *Truss) d.Lines {
        var out: d.Lines = .{};
        out.add("model nodes {d} members {d} supports {d} free_dofs {d} restrained_dofs {d} indeterminacy {d}",
             .{ self.model.nodes.len, self.model.members.len, self.model.supports.len, self.free.len,
             self.restrained.len, n(self.model.members.len) + n(self.restrained.len) - n(self.degrees) });
        var sequence: d.Text = .{};
        sequence.add("renumbering", .{});
        for (self.order) |node| sequence.add(" {d}", .{self.model.nodes[node].id});
        out.add("{s}", .{sequence.value()});
        const original = d.alloc(usize, self.model.nodes.len);
        for (original, 0..) |*value, i| value.* = i;
        const before = self.metrics(original);
        const after = self.metrics(self.numbers);
        out.add("bandwidth before {d} after {d}", .{ before[0], after[0] });
        out.add("profile before {d} after {d}", .{ before[1], after[1] });
        for (self.model.members, self.geometry) |member, g| out.add("member {d} nodes {d} {d} length {s} cos {s} sin {s}",
             .{ member.id, self.model.nodes[member.start].id, self.model.nodes[member.end].id,
             real(g.length), realDigits(g.cosine, 6), realDigits(g.sine, 6) });
        for (self.results, 0..) |item, index| {
            const moves = self.magnitudes(item);
            const chosen = extreme(moves, false);
            var energy: f64 = 0;
            var scale: f64 = 1;
            var reaction = [_]f64{ 0, 0 };
            var external = [_]f64{ 0, 0 };
            for (item.forces, self.geometry, self.final_system.properties) |force, g, p| energy += force * force * g.length / (2 * p.young * p.area);
            for (self.node_dofs) |dofs| for (0..2) |axis| {
                const degree = dofs[axis];
                reaction[axis] += item.reactions[degree];
                external[axis] += item.external[degree];
                scale = @max(scale, @abs(item.reactions[degree]));
                scale = @max(scale, @abs(item.external[degree]));
            };
            out.add("{s} {s} equilibrium {s} max_displacement {s} at {d} energy {s} reactions {s} {s} loads {s} {s}",
                 .{ if (index < self.model.cases.len) "case" else "combination", item.name,
                 if (post.equilibriumResidual(item, self.geometry) <= 0.000001 * scale) "ok" else "failed",
                 real(moves[chosen]), self.model.nodes[chosen].id, real(energy / 1000), real(reaction[0] / 1000),
                 real(reaction[1] / 1000), real(external[0] / 1000), real(external[1] / 1000) });
        }
        for (self.support_directions.items) |direction| {
            const values = d.alloc(f64, self.combinations.len);
            var uplift = false;
            for (self.combinations, values) |combination, *value| {
                value.* = combination.reactions[direction[2]] / 1000;
                if (combination.reactions[direction[2]] < 0) uplift = true;
            }
            const high = extreme(values, false);
            const low = extreme(values, true);
            var text: d.Text = .{};
            text.add("reaction_envelope {d} {c} max {s} {s} min {s} {s}", .{ self.model.nodes[direction[0]].id,
                 "xy"[direction[1]], real(values[high]), self.combinations[high].name, real(values[low]),
                 self.combinations[low].name });
            if (direction[1] == 1) text.add(" uplift {s}", .{if (uplift) "yes" else "no"});
            out.add("{s}", .{text.value()});
        }
        for (self.model.nodes, 0..) |node, i| {
            const values = d.alloc(f64, self.combinations.len);
            for (self.combinations, values) |combination, *value| value.* = self.magnitudes(combination)[i];
            const chosen = extreme(values, false);
            out.add("displacement_envelope {d} max {s} {s}", .{ node.id, real(values[chosen]),
                 self.combinations[chosen].name });
        }
        const deflection = self.result(self.model.settings.deflection);
        const deck = self.model.settings.deck;
        var anchors: std.ArrayList(usize) = .empty;
        for (deck, 0..) |node, i| for (self.support_directions.items) |direction| {
            if (direction[0] == node and direction[1] == 1) d.append(usize, &anchors, i);
        };
        for (1..anchors.items.len) |span| {
            const ai = anchors.items[span - 1];
            const bi = anchors.items[span];
            const na = deck[ai];
            const nb = deck[bi];
            const va = deflection.displacement[self.node_dofs[na][1]];
            const vb = deflection.displacement[self.node_dofs[nb][1]];
            const values = d.alloc(f64, bi - ai - 1);
            for (ai + 1..bi, values) |k, *value| {
                const node = deck[k];
                value.* = @abs(deflection.displacement[self.node_dofs[node][1]] - (va + (vb - va) * f(self.model.nodes[node].x - self.model.nodes[na].x) / f(self.model.nodes[nb].x - self.model.nodes[na].x)));
            }
            const chosen = extreme(values, false);
            const nt = deck[ai + 1 + chosen];
            const limit = f(self.model.nodes[nb].x - self.model.nodes[na].x) / f(self.model.settings.deflection_ratio);
            out.add("deflection {s} span {d} {d} max {s} at {d} limit {s} {s}", .{ deflection.name,
                 self.model.nodes[na].id, self.model.nodes[nb].id, real(values[chosen]), self.model.nodes[nt].id,
                 real(limit), if (values[chosen] <= limit) "ok" else "exceeded" });
            const unit = self.unitResult(nt);
            var work: f64 = 0;
            for (deflection.forces, unit.forces, self.geometry, self.final_system.properties) |force,
                 unit_force, g, p| work += force * (unit_force / 1000) * g.length / (p.young * p.area);
            const stiffness = -deflection.displacement[self.node_dofs[nt][1]];
            out.add("virtual_work {s} node {d} stiffness {s} virtual {s} {s}", .{ deflection.name,
                 self.model.nodes[nt].id, real(stiffness), real(work), if (@abs(work - stiffness) <= 0.000001 * @max(1,
                 @abs(stiffness))) "ok" else "failed" });
        }
        var definition: d.Combination = undefined;
        for (self.model.combinations) |combination| if (d.eq(combination.name, self.model.settings.removal)) {
            definition = combination;
        };
        for (self.model.members, 0..) |removed_member, removed| {
            const structure = self.system(removed);
            if (structure.unstable) |degree| {
                const owner = self.owners[degree];
                out.add("removal {d} unstable at {d} {c}", .{ removed_member.id, self.model.nodes[owner[0]].id,
                     "xy"[owner[1]] });
            } else {
                const item = self.removalResult(structure, definition);
                var values: std.ArrayList(f64) = .empty;
                var members: std.ArrayList(usize) = .empty;
                for (self.model.members, 0..) |_, i| {
                    if (i == removed) continue;
                    d.append(usize, &members, i);
                    d.append(f64, &values, design.utilization(item.forces[i], structure.properties[i],
                         self.geometry[i], null));
                }
                const chosen = extreme(values.items, false);
                const moves = self.magnitudes(item);
                const node = extreme(moves, false);
                out.add("removal {d} stable max_utilization {s} at {d} max_displacement {s} at {d}",
                     .{ removed_member.id, real(values.items[chosen]), self.model.members[members.items[chosen]].id,
                     real(moves[node]), self.model.nodes[node].id });
            }
        }
        return out;
    }
    fn ordinate(self: *const Truss, values: []const f64, x: i64) f64 {
        const deck = self.model.settings.deck;
        if (x < self.model.nodes[deck[0]].x or x > self.model.nodes[deck[deck.len - 1]].x) return 0;
        if (x == self.model.nodes[deck[deck.len - 1]].x) return values[values.len - 1];
        var k: usize = 0;
        while (self.model.nodes[deck[k + 1]].x <= x) : (k += 1) {}
        return values[k] + (values[k + 1] - values[k]) * f(x - self.model.nodes[deck[k]].x) / f(self.model.nodes[deck[k + 1]].x - self.model.nodes[deck[k]].x);
    }
    fn vehicle(self: *const Truss, values: []const f64, positions: []const i64) []const f64 {
        const out = d.alloc(f64, positions.len);
        for (positions, out) |position_value, *value| {
            value.* = 0;
            for (self.model.settings.axles) |axle| value.* += axle.load * self.ordinate(values,
                 position_value - axle.offset);
        }
        return out;
    }
    fn influenceReport(self: *Truss) d.Lines {
        var out: d.Lines = .{};
        const settings = self.model.settings;
        const deck = settings.deck;
        const member_lines = d.alloc([]f64, self.model.members.len);
        const reaction_lines = d.alloc([]f64, self.degrees);
        for (member_lines) |*values| values.* = d.alloc(f64, deck.len);
        for (reaction_lines) |*values| values.* = d.alloc(f64, deck.len);
        for (deck, 0..) |node, k| {
            const unit = self.unitResult(node);
            for (member_lines, unit.forces) |values, force| values[k] = force / 1000;
            for (self.restrained) |degree| reaction_lines[degree][k] = unit.reactions[degree] / 1000;
        }
        for (settings.influence) |member| {
            const values = member_lines[member];
            out.add("influence {d}", .{self.model.members[member].id});
            var positive: f64 = 0;
            var negative: f64 = 0;
            for (deck, values) |node, value| {
                out.add("node {d} {s}", .{ self.model.nodes[node].id, real(value) });
                if (value > 0) positive += value else if (value < 0) negative += value;
            }
            const high = extreme(values, false);
            const low = extreme(values, true);
            out.add("max {s} at {d} min {s} at {d} positive {s} negative {s}", .{ real(values[high]),
                 self.model.nodes[deck[high]].id, real(values[low]), self.model.nodes[deck[low]].id,
                 real(positive), real(negative) });
            var crossings: std.ArrayList(f64) = .empty;
            for (0..deck.len - 1) |k| if ((values[k] > 0 and values[k + 1] < 0) or (values[k] < 0 and values[k + 1] > 0)) d.append(f64,
                 &crossings, f(self.model.nodes[deck[k]].x) + f(self.model.nodes[deck[k + 1]].x - self.model.nodes[deck[k]].x) * values[k] / (values[k] - values[k + 1]));
            var text: d.Text = .{};
            text.add("crossings {d}", .{crossings.items.len});
            for (crossings.items) |value| text.add(" {s}", .{realDigits(value, 1)});
            out.add("{s}", .{text.value()});
        }
        var positions: std.ArrayList(i64) = .empty;
        var position_value = self.model.nodes[deck[0]].x;
        while (position_value <= self.model.nodes[deck[deck.len - 1]].x + settings.axles[settings.axles.len - 1].offset) : (position_value += settings.vehicle_step) d.append(i64,
             &positions, position_value);
        out.add("vehicle axles {d} positions {d}", .{ settings.axles.len, positions.items.len });
        const tension = d.alloc(f64, self.model.members.len);
        const compression = d.alloc(f64, self.model.members.len);
        for (self.model.members, 0..) |member, i| {
            const effects = self.vehicle(member_lines[i], positions.items);
            const high = extreme(effects, false);
            const low = extreme(effects, true);
            tension[i] = effects[high];
            compression[i] = effects[low];
            out.add("vehicle_member {d} max {s} at {d} min {s} at {d}", .{ member.id, real(effects[high]),
                 positions.items[high], real(effects[low]), positions.items[low] });
        }
        for (self.support_directions.items) |direction| {
            const effects = self.vehicle(reaction_lines[direction[2]], positions.items);
            const high = extreme(effects, false);
            const low = extreme(effects, true);
            out.add("vehicle_reaction {d} {c} max {s} at {d} min {s} at {d}", .{ self.model.nodes[direction[0]].id,
                 "xy"[direction[1]], real(effects[high]), positions.items[high], real(effects[low]),
                 positions.items[low] });
        }
        const dead = self.result(settings.rating);
        var ratings: std.ArrayList(f64) = .empty;
        var rating_owners: std.ArrayList([2]usize) = .empty;
        for (self.model.members, self.final_system.properties, 0..) |member, p, i| {
            const nd = dead.forces[i] / 1000;
            const pt = p.area * p.yield_stress / 1000;
            const pc = @min(p.area * p.yield_stress, design.buckling(p, self.geometry[i], p.inertia)) / 1000;
            var tension_text: []const u8 = "none";
            var compression_text: []const u8 = "none";
            if (rounded(tension[i]) > 0) {
                const value = (pt - settings.dead_factor * nd) / (settings.vehicle_factor * tension[i]);
                tension_text = real(value);
                d.append(f64, &ratings, value);
                d.append([2]usize, &rating_owners, .{ i, 0 });
            }
            if (rounded(compression[i]) < 0) {
                const value = (pc + settings.dead_factor * nd) / (settings.vehicle_factor * (-compression[i]));
                compression_text = real(value);
                d.append(f64, &ratings, value);
                d.append([2]usize, &rating_owners, .{ i, 1 });
            }
            out.add("rating {d} tension {s} compression {s}", .{ member.id, tension_text, compression_text });
        }
        const low = extreme(ratings.items, true);
        const owner = rating_owners.items[low];
        out.add("rating_min {s} at {d} {s}", .{ real(ratings.items[low]), self.model.members[owner[0]].id,
             if (owner[1] == 0) "tension" else "compression" });
        return out;
    }
    fn vibrationReport(self: *const Truss) d.Lines {
        var out: d.Lines = .{};
        const settings = self.model.settings;
        const loading = self.result(settings.vibration);
        const masses = d.alloc(f64, self.model.nodes.len);
        var total_mass: f64 = 0;
        for (self.node_dofs, masses) |dofs, *mass| {
            mass.* = -loading.external[dofs[1]] / 9.81;
            total_mass += mass.*;
        }
        const free_masses = d.alloc(f64, self.free.len);
        for (self.free, free_masses) |degree, *mass| mass.* = masses[self.owners[degree][0]];
        out.add("vibration {s} mass {s} iterations {d}", .{ loading.name, real(total_mass), settings.iterations });
        var modes: std.ArrayList([]const f64) = .empty;
        for (1..settings.modes + 1) |mode| {
            const x = d.alloc(f64, self.free.len);
            @memset(x, 1);
            for (0..settings.iterations) |_| {
                for (modes.items) |phi| {
                    var beta: f64 = 0;
                    for (phi, free_masses, x) |entry, mass, value| beta += entry * mass * value;
                    for (x, phi) |*value, entry| value.* = value.* - beta * entry;
                }
                const right = d.alloc(f64, self.free.len);
                for (right, free_masses, x) |*value, mass, entry| value.* = mass * entry;
                const y = solver.solve(self.final_system.lower, right);
                var norm: f64 = 0;
                for (free_masses, y) |mass, value| norm += mass * value * value;
                norm = @sqrt(norm);
                for (x, y) |*value, entry| value.* = entry / norm;
            }
            d.append([]const f64, &modes, x);
            var numerator: f64 = 0;
            var denominator: f64 = 0;
            for (0..self.free.len) |i| {
                var kx: f64 = 0;
                for (x, 0..) |value, j| kx += self.final_system.free_matrix[i][j] * value;
                numerator += x[i] * kx;
                denominator += free_masses[i] * x[i] * x[i];
            }
            const frequency = @sqrt(1000 * (numerator / denominator)) / (2 * design.pi);
            out.add("mode {d} frequency {s} period {s}", .{ mode, real(frequency), real(1 / frequency) });
            var peak: usize = 0;
            for (1..x.len) |i| if (@abs(x[i]) > @abs(x[peak])) {
                peak = i;
            };
            const normalized = a.zeros(self.degrees);
            for (self.free, x) |degree, value| normalized[degree] = value / x[peak];
            for (self.model.nodes, self.node_dofs) |node, dofs| out.add("node {d} {s} {s}",
                 .{ node.id, real(normalized[dofs[0]]), real(normalized[dofs[1]]) });
        }
        return out;
    }
    fn drawingReport(self: *const Truss) d.Lines {
        var out: d.Lines = .{};
        for (self.model.settings.drawings) |drawing| {
            var canvas = Canvas.init(self.model.nodes, drawing.horizontal, drawing.vertical);
            const item = self.result(drawing.name);
            const original = d.alloc(Point, self.model.nodes.len);
            const deformed = d.alloc(Point, self.model.nodes.len);
            for (self.model.nodes, self.node_dofs, original, deformed) |node, dofs, *point, *moved| {
                point.* = canvas.position(f(node.x), f(node.y));
                moved.* = canvas.position(f(node.x) + f(drawing.magnification) * item.displacement[dofs[0]],
                     f(node.y) + f(drawing.magnification) * item.displacement[dofs[1]]);
            }
            for (self.model.members) |member| canvas.segment(original[member.start], original[member.end], '.');
            for (original) |point| canvas.put(point, '+');
            for (self.model.members) |member| canvas.segment(deformed[member.start], deformed[member.end], '*');
            for (deformed) |point| canvas.put(point, 'o');
            out.add("drawing {s} magnification {d} columns {d} rows {d}", .{ drawing.name,
                 drawing.magnification, canvas.width, canvas.height });
            canvas.appendFrame(&out);
        }
        var canvas = Canvas.init(self.model.nodes, self.model.settings.map_horizontal, self.model.settings.map_vertical);
        const points = d.alloc(Point, self.model.nodes.len);
        for (self.model.nodes, points) |node, *point| point.* = canvas.position(f(node.x), f(node.y));
        for (self.model.members, self.governing) |member, value| {
            const character: u8 = if (value >= 1) '#' else '0' + @as(u8, @intFromFloat(@floor(10 * value)));
            canvas.segment(points[member.start], points[member.end], character);
        }
        for (points) |point| canvas.put(point, 'o');
        out.add("utilization_map columns {d} rows {d}", .{ canvas.width, canvas.height });
        canvas.appendFrame(&out);
        return out;
    }
    fn run(self: *Truss, io: std.Io) !void {
        self.designSections();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try save(io, "analysis.txt", self.analysisReport());
        try save(io, "design.txt", self.designReport());
        try save(io, "influence.txt", self.influenceReport());
        try save(io, "vibration.txt", self.vibrationReport());
        try save(io, "drawing.txt", self.drawingReport());
        var displacements: d.Lines = .{};
        var forces: d.Lines = .{};
        var reactions: d.Lines = .{};
        displacements.add("case,node,dx,dy", .{});
        forces.add("case,member,force,stress,utilization", .{});
        reactions.add("case,node,rx,ry", .{});
        for (self.results) |item| {
            for (self.model.nodes, self.node_dofs) |node, dofs| displacements.add("{s},{d},{s},{s}",
                 .{ item.name, node.id, real(item.displacement[dofs[0]]), real(item.displacement[dofs[1]]) });
            for (self.model.members, self.final_system.properties, self.geometry, 0..) |member,
                 p, g, i| forces.add("{s},{d},{s},{s},{s}", .{ item.name, member.id, real(item.forces[i] / 1000),
                 real(item.forces[i] / p.area), real(design.utilization(item.forces[i], p,
                 g, null)) });
            for (self.model.supports) |support| {
                const dofs = self.node_dofs[support.node];
                reactions.add("{s},{d},{s},{s}", .{ item.name, self.model.nodes[support.node].id,
                     real(item.reactions[dofs[0]] / 1000), real(item.reactions[dofs[1]] / 1000) });
            }
        }
        try save(io, "displacements.csv", displacements);
        try save(io, "member_forces.csv", forces);
        try save(io, "reactions.csv", reactions);
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    var truss = Truss.init(try d.readModel(init.io));
    try truss.run(init.io);
}
