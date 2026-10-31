const std = @import("std");
const E = @import("enrolment.zig");
pub const Order = struct { later: usize, earlier: usize };
pub const Graph = struct {
    shared: [100][100]i64 = [_][100]i64{[_]i64{0} ** 100} ** 100,
    degrees: [100]i64 = [_]i64{0} ** 100,
    vertices: E.Indices = .{},
    pub fn init(courses: []const E.Course, students: []const E.Student) Graph {
        var result: Graph = .{};
        for (courses, 0..) |course, c| { if (course.size() > 0) result.vertices.add(c); }
        for (students) |student| {
            for (student.courses.slice(), 0..) |a, i| {
                for (student.courses.slice()[i + 1 ..]) |b| {
                    result.shared[a][b] += 1;
                    result.shared[b][a] += 1;
                }
            }
        }
        for (result.vertices.slice()) |c| { for (result.shared[c]) |value| { if (value > 0) result.degrees[c] += 1; } }
        return result;
    }
    pub fn components(self: *const Graph) Components {
        var seen = [_]bool{false} ** 100;
        var result: Components = .{};
        for (self.vertices.slice()) |c| {
            if (seen[c]) continue;
            var component: E.Indices = .{};
            component.add(c);
            seen[c] = true;
            var i: usize = 0;
            while (i < component.len) : (i += 1) {
                for (self.vertices.slice()) |n| {
                    if (self.shared[component.values[i]][n] == 0 or seen[n]) continue;
                    seen[n] = true;
                    component.add(n);
                }
            }
            component.sort();
            result.values[result.len] = component;
            result.len += 1;
        }
        std.mem.sort(E.Indices, result.values[0..result.len], {}, componentLess);
        return result;
    }
    pub fn clique(self: *const Graph, initial: E.Indices) E.Indices {
        var candidates = initial;
        var result: E.Indices = .{};
        while (candidates.len > 0) {
            var chosen = candidates.values[0];
            for (candidates.slice()) |c| {
                if (self.degrees[c] > self.degrees[chosen] or (self.degrees[c] == self.degrees[chosen] and c < chosen)) chosen = c;
            }
            result.add(chosen);
            var next: E.Indices = .{};
            for (candidates.slice()) |c| { if (self.shared[chosen][c] > 0) next.add(c); }
            candidates = next;
        }
        return result;
    }
    pub fn kempeChain(self: *const Graph, assignment: []const usize, start: usize, home: usize, target: usize) E.Indices {
        var result: E.Indices = .{};
        var seen = [_]bool{false} ** 100;
        result.add(start);
        seen[start] = true;
        var i: usize = 0;
        while (i < result.len) : (i += 1) {
            for (self.vertices.slice()) |n| {
                if (seen[n] or self.shared[result.values[i]][n] == 0 or (assignment[n] != home and assignment[n] != target)) continue;
                seen[n] = true;
                result.add(n);
            }
        }
        result.sort();
        return result;
    }
};
pub const Components = struct { values: [100]E.Indices = undefined, len: usize = 0 };
fn componentLess(_: void, a: E.Indices, b: E.Indices) bool { return if (a.len == b.len) a.values[0] < b.values[0] else a.len > b.len; }
pub fn reachable(orders: []const Order, source: usize, target: usize) bool {
    var stack: E.Indices = .{};
    var seen = [_]bool{false} ** 100;
    stack.add(source);
    seen[source] = true;
    while (stack.len > 0) {
        stack.len -= 1;
        const current = stack.values[stack.len];
        if (current == target) return true;
        for (orders) |order| {
            if (order.later == current and !seen[order.earlier]) {
                seen[order.earlier] = true;
                stack.add(order.earlier);
            }
        }
    }
    return false;
}
