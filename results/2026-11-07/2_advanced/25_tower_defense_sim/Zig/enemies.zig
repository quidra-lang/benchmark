const std = @import("std");
const g = @import("grid_map.zig");
const c = @import("combat.zig");
const p = @import("pathing.zig");

pub const EnemyType = struct {
    name: []const u8,
    symbol: u8,
    movement: g.Targets,
    hp: i64,
    armor: i64,
    speed: i64,
    bounty: i64,
    lives: i64,
    regen: i64,
    split_into: ?*EnemyType,
    split_count: usize,
    spawned: i64 = 0,
    kills: i64 = 0,
    leaks: i64 = 0,
    damage: i64 = 0,

    pub fn parse(fields: []const []const u8, known: []const *EnemyType) EnemyType {
        return .{
            .name = fields[1],
            .symbol = fields[2][0],
            .movement = g.parseTargets(fields[3]),
            .hp = g.number(fields[4]),
            .armor = g.number(fields[5]),
            .speed = g.number(fields[6]),
            .bounty = g.number(fields[7]),
            .lives = g.number(fields[8]),
            .regen = g.number(fields[9]),
            .split_into = if (g.eq(fields[10], "-")) null else findType(known, fields[10]).?,
            .split_count = g.u(g.number(fields[11])),
        };
    }
};
pub fn findType(types: []const *EnemyType, name: []const u8) ?*EnemyType {
    for (types) |kind| if (g.eq(kind.name, name)) return kind;
    return null;
}
pub const Group = struct {
    kind: *EnemyType,
    spawn: usize,
    count: usize,
    delay: i64,
    interval: i64,
    multiplier: i64,

    pub fn parse(fields: []const []const u8, known: []const *EnemyType) Group {
        return .{
            .kind = findType(known, fields[1]).?,
            .spawn = g.u(g.number(fields[2])),
            .count = g.u(g.number(fields[3])),
            .delay = g.number(fields[4]),
            .interval = g.number(fields[5]),
            .multiplier = g.number(fields[6]),
        };
    }
    pub fn spawnTick(self: Group, start: i64, index: usize) i64 { return start + self.delay + g.n(index) * self.interval; }
};
pub const Wave = struct {
    reward: i64,
    groups: std.ArrayList(Group) = .empty,
    pub fn enemyCount(self: Wave) usize {
        var count: usize = 0;
        for (self.groups.items) |group| count += group.count;
        return count;
    }
};
pub const WaveInput = struct { types: []*EnemyType, waves: []*Wave };
pub fn parseWaves(source: []const []const u8) WaveInput {
    var types: std.ArrayList(*EnemyType) = .empty;
    var waves: std.ArrayList(*Wave) = .empty;
    for (source) |line| {
        const fields = g.splitFields(line);
        if (g.eq(fields[0], "enemy")) {
            const kind = &g.alloc(EnemyType, 1)[0];
            kind.* = EnemyType.parse(fields, types.items);
            g.append(*EnemyType, &types, kind);
        } else if (g.eq(fields[0], "wave")) {
            const wave = &g.alloc(Wave, 1)[0];
            wave.* = .{ .reward = g.number(fields[1]) };
            g.append(*Wave, &waves, wave);
        } else g.append(Group, &waves.items[waves.items.len - 1].groups, Group.parse(fields, types.items));
    }
    return .{ .types = types.items, .waves = waves.items };
}
pub const Enemy = struct {
    number: usize,
    kind: *EnemyType,
    multiplier: i64,
    max_hp: i64,
    hp: i64,
    slow: c.Effect = .{},
    burn: c.Effect = .{},
    alive: bool = true,
    cell: g.Cell = .{},
    next_cell: g.Cell = .{},
    progress: i64 = 0,
    point: g.Point = .{},

    pub fn create(number: usize, kind: *EnemyType, multiplier: i64) *Enemy {
        const enemy = &g.alloc(Enemy, 1)[0];
        const hp = @divTrunc(kind.hp * multiplier, 100);
        enemy.* = .{ .number = number, .kind = kind, .multiplier = multiplier, .max_hp = hp, .hp = hp };
        return enemy;
    }
    pub fn flying(self: Enemy) bool { return self.kind.movement == .air; }
    pub fn position(self: Enemy) g.Point {
        if (self.flying()) return self.point;
        return .{ .x = 100 * self.cell.x + (self.next_cell.x - self.cell.x) * self.progress, .y = 100 * self.cell.y + (self.next_cell.y - self.cell.y) * self.progress };
    }
    pub fn occupiedCell(self: Enemy) g.Cell {
        if (self.flying()) return .{ .x = @divTrunc(self.point.x + 50, 100), .y = @divTrunc(self.point.y + 50, 100) };
        return if (self.progress < 50) self.cell else self.next_cell;
    }
    pub fn remaining(self: Enemy, field: *const p.DistanceField) i64 {
        if (self.flying()) return c.isqrt(c.squaredDistance(self.point, g.cellCenter(field.grid.exit)));
        return 100 * field.at(self.next_cell) + 100 - self.progress;
    }
    pub fn slowedSpeed(self: Enemy) i64 { return if (self.slow.active()) @divTrunc(self.kind.speed * (100 - self.slow.strength), 100) else self.kind.speed; }
    pub fn split(self: Enemy, number: usize) *Enemy {
        const child = Enemy.create(number, self.kind.split_into.?, self.multiplier);
        child.cell = self.cell;
        child.next_cell = self.next_cell;
        child.progress = self.progress;
        child.point = self.point;
        return child;
    }
};
