pub const Minstd = struct {
    state: i64,
    pub fn draw(self: *Minstd) i64 { self.state = @mod(48271 * self.state, 2147483647); return self.state; }
    pub fn rnd(self: *Minstd, limit: usize) usize { return @intCast(@mod(self.draw(), @as(i64, @intCast(limit)))); }
    pub fn roll(self: *Minstd, count: usize, sides: usize) i64 {
        var total: i64 = 0;
        for (0..count) |_| total += 1 + @as(i64, @intCast(self.rnd(sides)));
        return total;
    }
    pub fn select(self: *Minstd, weights: []const usize) usize {
        var total: usize = 0;
        for (weights) |weight| total += weight;
        const value = self.rnd(total);
        var cumulative: usize = 0;
        for (weights, 0..) |weight, i| { cumulative += weight; if (value < cumulative) return i; }
        unreachable;
    }
};
