const std = @import("std");
const e = @import("environment.zig");
const dp = @import("dynamic_programming.zig");
pub fn choose(q: []const [4]i64, state: usize, epsilon: i64, random: *e.Random) usize {
    return if (@mod(random.draw(), 1000) < epsilon) e.u(@mod(random.draw(), 4)) else dp.firstMaximum(q[state]);
}
pub fn nextValue(q: []const [4]i64, state: usize, epsilon: i64, expected: bool) i64 {
    const maximum = q[state][dp.firstMaximum(q[state])];
    if (!expected) return maximum;
    var sum: i64 = 0;
    for (q[state]) |value| sum += value;
    return @divFloor(epsilon * sum + 4 * (1000 - epsilon) * maximum, 4000);
}
pub fn update(model: e.Model, q: e.Table, state: usize, action: usize, next: usize, reward: i64, gamma: i64,
     alpha: i64, future: i64) void {
    const target = 10000 * reward + if (e.terminal(model.world, next)) @as(i64, 0) else @divFloor(gamma * future, 100);
    q[state][action] += @divFloor(alpha * (target - q[state][action]), 100);
}
const Pair = struct { state: usize, action: usize };
const Entry = struct { next: usize, reward: i64 };
pub const Dyna = struct {
    entries: [][4]?Entry,
    observed: std.ArrayList(Pair) = .empty,
    pub fn init(states: usize) Dyna {
        const entries = e.alloc([4]?Entry, states);
        @memset(entries, @splat(null));
        return .{ .entries = entries };
    }
    pub fn record(self: *Dyna, state: usize, action: usize, next: usize, reward: i64) void {
        if (self.entries[state][action] == null) e.append(Pair, &self.observed, .{ .state = state, .action = action });
        self.entries[state][action] = .{ .next = next, .reward = reward };
    }
    pub fn plan(self: Dyna, model: e.Model, q: e.Table, count: usize, gamma: i64, alpha: i64, random: *e.Random) void {
        for (0..count) |_| {
            const pair = self.observed.items[e.u(@mod(random.draw(), e.n(self.observed.items.len)))];
            const entry = self.entries[pair.state][pair.action].?;
            const future = if (model.world.index[entry.next]) |state| nextValue(q, state, 0, false) else 0;
            update(model, q, pair.state, pair.action, entry.next, entry.reward, gamma, alpha, future);
        }
    }
};
