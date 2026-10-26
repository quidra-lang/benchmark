const std = @import("std");
const Minstd = @import("minstd.zig").Minstd;
pub const Dice = struct {
    count: usize, sides: usize,
    pub fn parse(token: []const u8) Dice {
        const marker = std.mem.indexOfScalar(u8, token, 'd').?;
        return .{ .count = std.fmt.parseInt(usize, token[0..marker], 10) catch unreachable, .sides = std.fmt.parseInt(usize, token[marker + 1 ..], 10) catch unreachable };
    }
    pub fn roll(self: Dice, rng: *Minstd) i64 { return rng.roll(self.count, self.sides); }
};
pub const Outcome = enum { miss, hit, critical };
pub const Attack = struct { outcome: Outcome, damage: i64 };
pub fn resolveAttack(rng: *Minstd, to_hit: i64, defense: i64, dice: Dice, bonus: i64) Attack {
    const rolled: i64 = 1 + @as(i64, @intCast(rng.rnd(20)));
    if (rolled == 1 or (rolled != 20 and rolled + to_hit < defense)) return .{ .outcome = .miss, .damage = 0 };
    var damage = dice.roll(rng);
    var outcome: Outcome = .hit;
    if (rolled == 20) { outcome = .critical; damage += dice.roll(rng); }
    damage += bonus;
    return .{ .outcome = outcome, .damage = @max(damage, 1) };
}
