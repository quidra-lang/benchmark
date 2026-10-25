pub const Minstd = struct {
    state: i64,
    pub fn draw(self: *Minstd) i64 { self.state = @mod(48271 * self.state, 2147483647); return self.state; }
};
pub fn select(weights: []const i64, value: i64) usize { var sum: i64 = 0; for (weights) |weight| sum += weight; const q = @mod(value, sum); var total: i64 = 0; for (weights, 0..) |weight, i| { total += weight; if (q < total) return i; } unreachable; }
