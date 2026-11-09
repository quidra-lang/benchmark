const std = @import("std");
const g = @import("grid_map.zig");
const c = @import("combat.zig");
const e = @import("enemies.zig");
const p = @import("pathing.zig");

pub const Level = struct {
    cost: i64,
    range: i64,
    power: i64,
    interval: i64,
    shot_speed: i64,
    splash: i64,
    slow_rate: i64,
    slow_time: i64,
    burn_amount: i64,
    burn_time: i64,
    pub fn parse(fields: []const []const u8) Level {
        return .{
            .cost = g.number(fields[1]),
            .range = g.number(fields[2]),
            .power = g.number(fields[3]),
            .interval = g.number(fields[4]),
            .shot_speed = g.number(fields[5]),
            .splash = g.number(fields[6]),
            .slow_rate = g.number(fields[7]),
            .slow_time = g.number(fields[8]),
            .burn_amount = g.number(fields[9]),
            .burn_time = g.number(fields[10]),
        };
    }
};
pub const TowerType = struct { name: []const u8, symbol: u8, targets: g.Targets, levels: []Level };
pub fn parseTowerTypes(source: []const []const u8) []*TowerType {
    var types: std.ArrayList(*TowerType) = .empty;
    var index: usize = 0;
    while (index < source.len) {
        const header = g.splitFields(source[index]);
        const count = g.u(g.number(header[4]));
        const levels = g.alloc(Level, count);
        for (levels, 1..) |*level, offset| level.* = Level.parse(g.splitFields(source[index + offset]));
        const kind = &g.alloc(TowerType, 1)[0];
        kind.* = .{ .name = header[1], .symbol = header[2][0], .targets = g.parseTargets(header[3]), .levels = levels };
        g.append(*TowerType, &types, kind);
        index += count + 1;
    }
    return types.items;
}
pub fn findType(types: []const *TowerType, name: []const u8) ?*TowerType {
    for (types) |kind| if (g.eq(kind.name, name)) return kind;
    return null;
}
pub fn canAim(targets: g.Targets, enemy: *const e.Enemy) bool { return targets == .both or targets == enemy.kind.movement; }
pub const Mode = enum { first, last, strongest, weakest, closest };
const mode_names = [_][]const u8{ "FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST" };
pub fn parseMode(text: []const u8) ?Mode {
    for (mode_names, 0..) |name, index| if (g.eq(name, text)) return @enumFromInt(index);
    return null;
}
pub fn modeText(mode: Mode) []const u8 { return mode_names[@intFromEnum(mode)]; }
pub const Tower = struct {
    number: usize,
    kind: *TowerType,
    cell: g.Cell,
    level: usize = 1,
    mode: Mode = .first,
    ready: i64,
    investment: i64,
    built: i64,
    sold: ?i64 = null,
    shots: i64 = 0,
    hits: i64 = 0,
    fizzles: i64 = 0,
    kills: i64 = 0,
    damage: i64 = 0,

    pub fn create(number: usize, kind: *TowerType, cell: g.Cell, tick: i64) *Tower {
        const tower = &g.alloc(Tower, 1)[0];
        tower.* = .{ .number = number, .kind = kind, .cell = cell, .ready = tick, .investment = kind.levels[0].cost, .built = tick };
        return tower;
    }
    pub fn stats(self: Tower) Level { return self.kind.levels[self.level - 1]; }
    pub fn center(self: Tower) g.Point { return g.cellCenter(self.cell); }
    pub fn standing(self: Tower) bool { return self.sold == null; }
    pub fn inRange(self: Tower, point: g.Point) bool {
        const reach = self.stats().range;
        return c.squaredDistance(self.center(), point) <= reach * reach;
    }
    pub fn targetKey(self: Tower, enemy: *const e.Enemy, field: *const p.DistanceField) i64 {
        return switch (self.mode) {
            .first => enemy.remaining(field),
            .last => -enemy.remaining(field),
            .strongest => -enemy.hp,
            .weakest => enemy.hp,
            .closest => c.squaredDistance(self.center(), enemy.position()),
        };
    }
    pub fn selectTarget(self: Tower, enemies: []const *e.Enemy, field: *const p.DistanceField) ?*e.Enemy {
        var best: ?*e.Enemy = null;
        var best_key: i64 = 0;
        for (enemies) |enemy| {
            if (!enemy.alive or !canAim(self.kind.targets, enemy) or !self.inRange(enemy.position())) continue;
            const key = self.targetKey(enemy, field);
            if (best == null or key < best_key or (key == best_key and enemy.number < best.?.number)) {
                best = enemy;
                best_key = key;
            }
        }
        return best;
    }
};
