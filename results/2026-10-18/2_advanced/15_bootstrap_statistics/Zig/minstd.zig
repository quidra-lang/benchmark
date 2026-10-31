const std = @import("std");
pub const Minstd = struct {
    state: i64,
    pub fn draw(self: *Minstd) i64 { self.state = @mod(48271 * self.state, 2147483647); return self.state; }
    pub fn below(self: *Minstd, limit: usize) usize { return @intCast(@mod(self.draw(), @as(i64, @intCast(limit)))); }
    pub fn shuffle(self: *Minstd, values: []usize) void {
        var i = values.len;
        while (i > 1) : (i -= 1) { const j = self.below(i); std.mem.swap(usize, &values[i - 1], &values[j]); }
    }
};
