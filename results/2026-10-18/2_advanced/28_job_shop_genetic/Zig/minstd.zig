const std = @import("std");
pub const Minstd = struct {
    state: i64,
    pub fn draw(self: *Minstd) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return self.state;
    }
    pub fn below(self: *Minstd, limit: usize) usize {
        return @intCast(@mod(self.draw(), @as(i64, @intCast(limit))));
    }
    pub fn chance(self: *Minstd, fraction: [2]i64) bool {
        return @mod(self.draw(), fraction[1]) < fraction[0];
    }
    pub fn shuffle(self: *Minstd, genes: []usize) void {
        var length = genes.len;
        while (length > 1) : (length -= 1) {
            const index = self.below(length);
            std.mem.swap(usize, &genes[length - 1], &genes[index]);
        }
    }
};
