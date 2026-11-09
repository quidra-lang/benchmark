const std = @import("std");
const g = @import("grid_map.zig");
pub const Budget = struct { limit: ?i64 = null, searches: i64 = 0, expansions: i64 = 0 };
pub fn stateKey(cell: usize, time: usize) u64 {
    return @as(u64, time) * 1024 + cell;
}
pub fn moveKey(source: usize, destination: usize, time: usize) u64 {
    return (@as(u64, time) * 1024 + source) * 1024 + destination;
}
pub const Prohibitions = struct {
    states: std.AutoHashMapUnmanaged(u64, void) = .empty,
    moves: std.AutoHashMapUnmanaged(u64, void) = .empty,
    permanent: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    pub fn clone(self: Prohibitions) Prohibitions {
        return .{ .states = self.states.clone(g.allocator) catch @panic("allocation failed"),
             .moves = self.moves.clone(g.allocator) catch @panic("allocation failed"), .permanent = self.permanent.clone(g.allocator) catch @panic("allocation failed") };
    }
    pub fn forbidState(self: *Prohibitions, cell: usize, time: usize) void {
        self.states.put(g.allocator, stateKey(cell, time), {}) catch @panic("allocation failed");
    }
    pub fn forbidMove(self: *Prohibitions, source: usize, destination: usize, time: usize) void {
        self.moves.put(g.allocator, moveKey(source, destination, time), {}) catch @panic("allocation failed");
    }
    pub fn stateAllowed(self: *const Prohibitions, cell: usize, time: usize) bool {
        return !self.states.contains(stateKey(cell, time)) and (if (self.permanent.get(cell)) |start| time < start else true);
    }
    pub fn actionAllowed(self: *const Prohibitions, source: usize, destination: usize, time: usize) bool {
        return self.stateAllowed(destination, time) and (source == destination or !self.moves.contains(moveKey(source,
             destination, time)));
    }
    pub fn arrivalAllowed(self: *const Prohibitions, goal: usize) usize {
        var result: usize = 0;
        var keys = self.states.keyIterator();
        while (keys.next()) |key| if (key.* % 1024 == goal) {
            result = @max(result, @as(usize, @intCast(key.* / 1024)) + 1);
        };
        return result;
    }
    pub fn reserve(self: *Prohibitions, path: g.Path, start: usize, permanent: bool) void {
        for (path, 0..) |cell, time| {
            self.forbidState(cell, start + time);
            if (time > 0 and cell != path[time - 1]) self.forbidMove(cell, path[time - 1], start + time);
        }
        if (permanent) {
            const cell = path[path.len - 1];
            const time = start + path.len - 1;
            self.permanent.put(g.allocator, cell, if (self.permanent.get(cell)) |old| @min(old,
                 time) else time) catch @panic("allocation failed");
        }
    }
};
const State = struct { cell: usize, time: usize, f: i64, steps: usize, insertion: usize };
fn less(a: State, b: State) bool {
    if (a.f != b.f) return a.f < b.f;
    if (a.steps != b.steps) return a.steps > b.steps;
    return a.insertion < b.insertion;
}
const Heap = struct {
    items: std.ArrayList(State) = .empty,
    allocator: std.mem.Allocator,
    fn push(self: *Heap, state: State) void {
        self.items.append(self.allocator, state) catch @panic("allocation failed");
        var index = self.items.items.len - 1;
        while (index > 0) {
            const parent = (index - 1) / 2;
            if (!less(self.items.items[index], self.items.items[parent])) break;
            std.mem.swap(State, &self.items.items[index], &self.items.items[parent]);
            index = parent;
        }
    }
    fn pop(self: *Heap) State {
        const value = self.items.items[0];
        const last = self.items.pop().?;
        if (self.items.items.len == 0) return value;
        self.items.items[0] = last;
        var index: usize = 0;
        while (2 * index + 1 < self.items.items.len) {
            var child = 2 * index + 1;
            if (child + 1 < self.items.items.len and less(self.items.items[child + 1], self.items.items[child])) child += 1;
            if (!less(self.items.items[child], self.items.items[index])) break;
            std.mem.swap(State, &self.items.items[index], &self.items.items[child]);
            index = child;
        }
        return value;
    }
};
pub const Result = struct { status: enum { success, no_path, aborted }, path: g.Path = &.{}, expansions: i64 };
pub fn search(grid: g.Grid, agent: g.Agent, distance: []const i64, start: usize, t0: usize,
     prohibitions: *const Prohibitions, tmax: usize, budget: *Budget, window: bool, work_allocator: std.mem.Allocator) Result {
    budget.searches += 1;
    const beginning = budget.expansions;
    const arrival = prohibitions.arrivalAllowed(agent.goal);
    const cells = grid.size();
    const parents = work_allocator.alloc(i32, (tmax - t0 + 1) * cells) catch @panic("allocation failed");
    defer work_allocator.free(parents);
    @memset(parents, -2);
    parents[start] = -1;
    var heap: Heap = .{ .allocator = work_allocator };
    defer heap.items.deinit(work_allocator);
    heap.push(.{ .cell = start, .time = t0, .f = distance[start], .steps = 0, .insertion = 0 });
    var insertion: usize = 0;
    while (heap.items.items.len > 0) {
        const state = heap.pop();
        budget.expansions += 1;
        if (budget.limit) |limit| if (budget.expansions > limit) return .{ .status = .aborted,
             .expansions = budget.expansions - beginning };
        if ((state.cell == agent.goal and state.time >= arrival) or (window and state.time == tmax)) {
            const path = g.alloc(usize, state.steps + 1);
            var current = (state.time - t0) * cells + state.cell;
            var position = path.len;
            while (true) {
                position -= 1;
                path[position] = current % cells;
                const parent = parents[current];
                if (parent < 0) break;
                current = @intCast(parent);
            }
            return .{ .status = .success, .path = path, .expansions = budget.expansions - beginning };
        }
        if (state.time == tmax) continue;
        const destinations = grid.destinations(state.cell);
        for (destinations.cells[0..destinations.count]) |destination| {
            const time = state.time + 1;
            const index = (time - t0) * cells + destination;
            if (distance[destination] < 0 or parents[index] != -2 or !prohibitions.actionAllowed(state.cell,
                 destination, time)) continue;
            insertion += 1;
            parents[index] = @intCast((state.time - t0) * cells + state.cell);
            const steps = time - t0;
            heap.push(.{ .cell = destination, .time = time, .f = g.n(steps) + distance[destination],
                 .steps = steps, .insertion = insertion });
        }
    }
    return .{ .status = .no_path, .expansions = budget.expansions - beginning };
}
