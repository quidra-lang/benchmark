const E = @import("enrolment.zig");
const G = @import("conflict_graph.zig");
pub const Choice = struct { course: usize, slot: usize, saturation: usize };
pub const Attempt = struct {
    pending: E.Indices, limit: usize,
    dead_ends: usize = 0, dead_end_course: ?usize = null, aborted: bool = false,
    choices: [100]Choice = undefined, choice_count: usize = 0,
    fn saturation(graph: *const G.Graph, course: usize, assignment: []const usize) usize {
        var seen = [_]bool{false} ** 36;
        var count: usize = 0;
        for (graph.vertices.slice()) |other| {
            const slot = assignment[other];
            if (graph.shared[course][other] == 0 or slot == 0 or seen[slot]) continue;
            seen[slot] = true;
            count += 1;
        }
        return count;
    }
    pub fn search(self: *Attempt, scheduler: anytype) bool {
        var chosen: ?usize = null;
        var best: usize = 0;
        for (self.pending.slice()) |c| {
            if (scheduler.assignment[c] != 0) continue;
            const value = saturation(&scheduler.graph, c, &scheduler.assignment);
            if (chosen == null or value > best or (value == best and
                (scheduler.graph.degrees[c] > scheduler.graph.degrees[chosen.?] or
                 (scheduler.graph.degrees[c] == scheduler.graph.degrees[chosen.?] and c < chosen.?)))) {
                chosen = c;
                best = value;
            }
        }
        const c = chosen orelse return true;
        const depth = self.choice_count;
        self.choices[depth] = .{ .course = c, .slot = 0, .saturation = best };
        self.choice_count += 1;
        const candidates = scheduler.candidateSlots(c, &scheduler.assignment);
        for (candidates.slice()) |slot| {
            scheduler.assignment[c] = slot;
            self.choices[depth].slot = slot;
            if (self.search(scheduler)) return true;
            scheduler.assignment[c] = 0;
            if (self.aborted) return false;
        }
        self.choice_count -= 1;
        self.dead_ends += 1;
        self.dead_end_course = c;
        self.aborted = self.dead_ends > self.limit;
        return false;
    }
};
pub fn greedyNumbering(graph: *const G.Graph, order: E.Indices) usize {
    var numbers = [_]usize{0} ** 100;
    var maximum: usize = 0;
    for (order.slice()) |c| {
        var taken = [_]bool{false} ** 101;
        for (graph.vertices.slice()) |other| { if (graph.shared[c][other] > 0) taken[numbers[other]] = true; }
        var number: usize = 1;
        while (taken[number]) : (number += 1) {}
        numbers[c] = number;
        maximum = @max(maximum, number);
    }
    return maximum;
}
