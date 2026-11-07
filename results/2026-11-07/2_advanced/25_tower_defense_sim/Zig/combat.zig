const g = @import("grid_map.zig");
pub fn squaredDistance(first: g.Point, second: g.Point) i64 {
    const dx = first.x - second.x;
    const dy = first.y - second.y;
    return dx * dx + dy * dy;
}
pub fn isqrt(value: i64) i64 {
    var remainder = value;
    var root: i64 = 0;
    var bit: i64 = @as(i64, 1) << 30;
    while (bit > remainder) bit >>= 2;
    while (bit != 0) : (bit >>= 2) {
        if (remainder >= root + bit) {
            remainder -= root + bit;
            root = (root >> 1) + bit;
        } else root >>= 1;
    }
    return root;
}
pub const Advance = struct { point: g.Point, arrived: bool };
pub fn advance(point: g.Point, goal: g.Point, step: i64) Advance {
    const dx = goal.x - point.x;
    const dy = goal.y - point.y;
    const squared = dx * dx + dy * dy;
    if (squared <= step * step) return .{ .point = goal, .arrived = true };
    const length = isqrt(squared);
    return .{ .point = .{ .x = point.x + @divTrunc(dx * step, length), .y = point.y + @divTrunc(dy * step, length) }, .arrived = false };
}
pub fn damageDealt(hp: i64, power: i64, armor: i64) i64 { return @min(hp, @max(1, power - armor)); }
pub const Effect = struct {
    strength: i64 = 0,
    remaining: i64 = 0,
    source: ?usize = null,

    pub fn active(self: Effect) bool { return self.remaining > 0; }
    pub fn receive(self: *Effect, strength: i64, duration: i64, source: ?usize) void {
        if (strength > self.strength) {
            self.strength = strength;
            self.remaining = duration;
            self.source = source;
        } else if (strength == self.strength) self.remaining = @max(self.remaining, duration);
    }
    pub fn advanceTime(self: *Effect) void {
        self.remaining -= 1;
        if (self.remaining == 0) {
            self.strength = 0;
            self.source = null;
        }
    }
};
pub const Projectile = struct {
    number: usize,
    tower: usize,
    target: usize,
    position: g.Point,
    aim: g.Point,
    targets: g.Targets,
    power: i64,
    speed: i64,
    splash: i64,
    slow_rate: i64,
    slow_time: i64,
    burn_amount: i64,
    burn_time: i64,

    pub fn fly(self: *Projectile) bool {
        if (self.speed == 0) return true;
        const movement = advance(self.position, self.aim, self.speed);
        self.position = movement.point;
        return movement.arrived;
    }
};
