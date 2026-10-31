const e = @import("environment.zig");
pub const Sample = struct { state: usize, action: usize, reward: i64 };
pub fn discounted(rewards: []const i64, gamma: i64) i64 {
    var value: i64 = 0;
    var i = rewards.len;
    while (i > 0) {
        i -= 1;
        value = 10000 * rewards[i] + @divFloor(gamma * value, 100);
    }
    return value;
}
pub fn update(steps: []const Sample, q: e.Table, sums: e.Table, counts: e.Table, gamma: i64) void {
    const first = e.alloc([4]?usize, q.len);
    @memset(first, @splat(null));
    for (steps, 0..) |sample, i| if (first[sample.state][sample.action] == null) {
        first[sample.state][sample.action] = i;
    };
    var value: i64 = 0;
    var i = steps.len;
    while (i > 0) {
        i -= 1;
        const sample = steps[i];
        value = 10000 * sample.reward + @divFloor(gamma * value, 100);
        if (first[sample.state][sample.action].? == i) {
            sums[sample.state][sample.action] += value;
            counts[sample.state][sample.action] += 1;
            q[sample.state][sample.action] = @divFloor(sums[sample.state][sample.action], counts[sample.state][sample.action]);
        }
    }
}
