const std = @import("std");
const g = @import("grid_map.zig");
const p = @import("pathing.zig");
const t = @import("towers.zig");
const e = @import("enemies.zig");
const c = @import("combat.zig");

fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 {
    return std.fmt.allocPrint(g.allocator, pattern, arguments) catch @panic("allocation failed");
}
const Text = struct {
    data: std.ArrayList(u8) = .empty,
    fn write(self: *Text, text: []const u8) void { self.data.appendSlice(g.allocator, text) catch @panic("allocation failed"); }
    fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    fn value(self: Text) []const u8 { return self.data.items; }
};
const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    fn write(self: *Lines, text: []const u8) void { g.append([]const u8, &self.data, text); }
    fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(g.allocator, other.data.items) catch @panic("allocation failed"); }
};
fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    return g.lines(try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), g.allocator, .unlimited));
}
fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
fn oneDecimal(numerator: i64, denominator: i64) []const u8 {
    if (denominator == 0) return "-";
    const rounded = @divTrunc(20 * numerator + denominator, 2 * denominator);
    return fmt("{d}.{d}", .{ @divTrunc(rounded, 10), @mod(rounded, 10) });
}
fn digit(count: i64) u8 { return if (count == 0) '.' else if (count <= 9) '0' + @as(u8, @intCast(count)) else '*'; }
const Params = struct {
    gold: i64,
    lives: i64,
    interest_rate: i64,
    interest_cap: i64,
    sell_rate: i64,
    start: i64,
    interval: i64,
    early: i64,
    snapshots: []i64,

    fn parse(source: []const []const u8) Params {
        var fields: [7][]const []const u8 = undefined;
        for (source, &fields) |line, *row| row.* = g.splitFields(line);
        const snapshots = g.alloc(i64, fields[6].len - 1);
        for (fields[6][1..], snapshots) |word, *tick| tick.* = g.number(word);
        return .{
            .gold = g.number(fields[0][1]), .lives = g.number(fields[1][1]),
            .interest_rate = g.number(fields[2][1]), .interest_cap = g.number(fields[2][2]),
            .sell_rate = g.number(fields[3][1]), .start = g.number(fields[4][1]),
            .interval = g.number(fields[4][2]), .early = g.number(fields[5][1]), .snapshots = snapshots,
        };
    }
    fn snapshotAt(self: Params, tick: i64) bool {
        for (self.snapshots) |wanted| if (wanted == tick) return true;
        return false;
    }
};
const Action = struct {
    tick: i64,
    command: []const u8,
    arguments: []const []const u8,
    fn parse(line: []const u8) Action {
        const fields = g.splitFields(line);
        return .{ .tick = g.number(fields[0]), .command = fields[1], .arguments = fields[2..] };
    }
};
const WaveRecord = struct {
    number: usize,
    plan: *e.Wave,
    start: i64,
    end: i64 = 0,
    status: []const u8 = "",
    released: [20]usize = @splat(0),
    spawned: i64 = 0,
    peak: i64 = 0,
    kills: i64 = 0,
    leaks: i64 = 0,
    lives_lost: i64 = 0,
    bounty: i64 = 0,
    reward: i64 = 0,
    interest: i64 = 0,
    gold: i64 = 0,
    lives: i64 = 0,
    tower_damage: [2000]i64 = @splat(0),

    fn allReleased(self: *const WaveRecord) bool {
        for (self.plan.groups.items, self.released[0..self.plan.groups.items.len]) |group, released| if (released != group.count) return false;
        return true;
    }
    fn close(self: *WaveRecord, status: []const u8, tick: i64, gold: i64, lives: i64) void {
        self.status = status;
        self.end = tick;
        self.gold = gold;
        self.lives = lives;
    }
    fn csvRow(self: *const WaveRecord, tower_count: usize) []const u8 {
        var text: Text = .{};
        text.add("{d},{d},{d},{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}", .{ self.number, self.start, self.end, self.status, self.spawned, self.peak, self.kills, self.leaks, self.lives_lost, self.bounty, self.reward, self.interest, self.gold, self.lives });
        for (self.tower_damage[0..tower_count]) |damage| text.add(",{d}", .{damage});
        return text.value();
    }
};
const Income = struct { bounty: i64 = 0, reward: i64 = 0, interest: i64 = 0, early: i64 = 0, refund: i64 = 0 };
const Game = struct {
    backing: std.mem.Allocator,
    grid: *const g.GridMap,
    tower_types: []*t.TowerType,
    enemy_types: []*e.EnemyType,
    waves: []*e.Wave,
    params: *const Params,
    tick: i64 = 0,
    gold: i64,
    lives: i64,
    towers: std.ArrayList(*t.Tower) = .empty,
    all_enemies: std.ArrayList(*e.Enemy) = .empty,
    living: std.ArrayList(*e.Enemy) = .empty,
    living_count: i64 = 0,
    projectiles: std.ArrayList(c.Projectile) = .empty,
    projectile_count: usize = 0,
    records: std.ArrayList(*WaveRecord) = .empty,
    active: ?*WaveRecord = null,
    next_start: ?i64,
    outcome: ?[]const u8 = null,
    field: p.DistanceField,
    blocked: [1200]bool = @splat(false),
    occupied: [1200]?*t.Tower = @splat(null),
    kill_counts: [1200]i64 = @splat(0),
    income: Income = .{},
    spent: i64 = 0,
    done: usize = 0,
    refused: usize = 0,
    events: Lines = .{},
    snapshots: Lines = .{},

    fn create(backing: std.mem.Allocator, grid: *const g.GridMap, tower_types: []*t.TowerType, wave_input: e.WaveInput, params: *const Params) *Game {
        const game = &g.alloc(Game, 1)[0];
        game.* = .{
            .backing = backing,
            .grid = grid,
            .tower_types = tower_types,
            .enemy_types = wave_input.types,
            .waves = wave_input.waves,
            .params = params,
            .gold = params.gold,
            .lives = params.lives,
            .next_start = params.start,
            .field = .{ .grid = grid },
        };
        game.field = p.DistanceField.compute(grid, &game.blocked);
        return game;
    }
    fn deinit(self: *Game) void {
        self.living.deinit(self.backing);
        self.projectiles.deinit(self.backing);
    }
    fn record(self: *Game, comptime pattern: []const u8, arguments: anytype) void {
        self.events.add("{d} {s}", .{ self.tick, fmt(pattern, arguments) });
    }
    fn towerAt(self: *const Game, cell: g.Cell) ?*t.Tower { return self.occupied[self.grid.index(cell)]; }
    fn standingTower(self: *const Game, text: []const u8) ?*t.Tower {
        const number = g.u(g.number(text));
        if (number == 0 or number > self.towers.items.len) return null;
        const tower = self.towers.items[number - 1];
        return if (tower.standing()) tower else null;
    }
    fn perform(self: *Game, action: Action) void {
        const success = if (g.eq(action.command, "BUILD")) self.build(action.arguments)
            else if (g.eq(action.command, "UPGRADE")) self.upgrade(action.arguments)
            else if (g.eq(action.command, "SELL")) self.sell(action.arguments)
            else if (g.eq(action.command, "TARGET")) self.setTarget(action.arguments)
            else self.callWave();
        if (success) self.done += 1 else self.refused += 1;
    }
    fn buildRefusal(self: *Game, name: []const u8, cell: g.Cell) ?[]const u8 {
        const kind = t.findType(self.tower_types, name) orelse return "type";
        if (!self.grid.inside(cell)) return "bounds";
        if (!self.grid.buildable(cell)) return "terrain";
        if (self.towerAt(cell) != null) return "tower";
        if (self.gold < kind.levels[0].cost) return "gold";
        for (self.living.items) |enemy| {
            if (enemy.alive and !enemy.flying() and (enemy.cell.same(cell) or enemy.next_cell.same(cell))) return "enemy";
        }
        const index = self.grid.index(cell);
        self.blocked[index] = true;
        const trial = p.DistanceField.compute(self.grid, &self.blocked);
        self.blocked[index] = false;
        for (self.grid.spawns) |spawn| if (trial.at(spawn) < 0) return "blocked";
        for (self.living.items) |enemy| {
            if (enemy.alive and !enemy.flying() and trial.at(enemy.next_cell) < 0) return "blocked";
        }
        return null;
    }
    fn build(self: *Game, arguments: []const []const u8) bool {
        const name = arguments[0];
        const cell: g.Cell = .{ .x = g.number(arguments[1]), .y = g.number(arguments[2]) };
        if (self.buildRefusal(name, cell)) |reason| {
            self.record("BUILD_REFUSED {s} {s} {s} {s}", .{ name, arguments[1], arguments[2], reason });
            return false;
        }
        const kind = t.findType(self.tower_types, name).?;
        const cost = kind.levels[0].cost;
        const tower = t.Tower.create(self.towers.items.len + 1, kind, cell, self.tick);
        g.append(*t.Tower, &self.towers, tower);
        const index = self.grid.index(cell);
        self.occupied[index] = tower;
        self.blocked[index] = true;
        self.gold -= cost;
        self.spent += cost;
        self.record("BUILD T{d} {s} {d} {d} cost {d} gold {d}", .{ tower.number, name, cell.x, cell.y, cost, self.gold });
        self.updateField();
        return true;
    }
    fn upgrade(self: *Game, arguments: []const []const u8) bool {
        const tower = self.standingTower(arguments[0]);
        const reason: ?[]const u8 = if (tower == null) "notower" else if (tower.?.level == tower.?.kind.levels.len) "maxlevel" else if (self.gold < tower.?.kind.levels[tower.?.level].cost) "gold" else null;
        if (reason) |error_text| {
            self.record("UPGRADE_REFUSED T{s} {s}", .{ arguments[0], error_text });
            return false;
        }
        const current = tower.?;
        const cost = current.kind.levels[current.level].cost;
        self.gold -= cost;
        self.spent += cost;
        current.level += 1;
        current.investment += cost;
        self.record("UPGRADE T{d} level {d} cost {d} gold {d}", .{ current.number, current.level, cost, self.gold });
        return true;
    }
    fn sell(self: *Game, arguments: []const []const u8) bool {
        const tower = self.standingTower(arguments[0]) orelse {
            self.record("SELL_REFUSED T{s} notower", .{arguments[0]});
            return false;
        };
        const rate = if (self.tick == tower.built) 100 else self.params.sell_rate;
        const refund = @divTrunc(tower.investment * rate, 100);
        tower.sold = self.tick;
        const index = self.grid.index(tower.cell);
        self.occupied[index] = null;
        self.blocked[index] = false;
        self.gold += refund;
        self.income.refund += refund;
        self.record("SELL T{d} refund {d} gold {d}", .{ tower.number, refund, self.gold });
        self.updateField();
        return true;
    }
    fn setTarget(self: *Game, arguments: []const []const u8) bool {
        const tower = self.standingTower(arguments[0]) orelse {
            self.record("TARGET_REFUSED T{s} notower", .{arguments[0]});
            return false;
        };
        const mode = t.parseMode(arguments[1]) orelse {
            self.record("TARGET_REFUSED T{s} mode", .{arguments[0]});
            return false;
        };
        tower.mode = mode;
        self.record("TARGET T{d} {s}", .{ tower.number, t.modeText(mode) });
        return true;
    }
    fn callWave(self: *Game) bool {
        if (self.active != null) {
            self.record("CALL_REFUSED active", .{});
            return false;
        }
        const bonus = (self.next_start.? - self.tick) * self.params.early;
        self.gold += bonus;
        self.income.early += bonus;
        self.next_start = self.tick;
        self.record("CALL {d} bonus {d} gold {d}", .{ self.records.items.len + 1, bonus, self.gold });
        return true;
    }
    fn updateField(self: *Game) void {
        var before: [9]i64 = undefined;
        for (self.grid.spawns, 0..) |spawn, index| before[index] = self.field.at(spawn);
        self.field = p.DistanceField.compute(self.grid, &self.blocked);
        for (self.grid.spawns, 0..) |spawn, index| {
            const after = self.field.at(spawn);
            if (before[index] != after) self.record("REPATH {d} {d} {d}", .{ index + 1, before[index], after });
        }
    }
    fn run(self: *Game, actions: []const Action) void {
        var action_index: usize = 0;
        while (true) {
            self.tick += 1;
            while (action_index < actions.len and actions[action_index].tick == self.tick) : (action_index += 1) self.perform(actions[action_index]);
            self.spawnEnemies();
            self.moveEnemies();
            if (self.outcome != null) break;
            self.fireTowers();
            self.moveProjectiles();
            self.checkWaveEnd();
            if (self.params.snapshotAt(self.tick)) self.snapshots.extend(self.block("SNAPSHOT"));
            if (self.outcome != null) break;
        }
        self.snapshots.extend(self.finalBlock());
    }
    fn startWave(self: *Game) void {
        const plan = self.waves[self.records.items.len];
        const wave = &g.alloc(WaveRecord, 1)[0];
        wave.* = .{ .number = self.records.items.len + 1, .plan = plan, .start = self.tick };
        g.append(*WaveRecord, &self.records, wave);
        self.active = wave;
        self.next_start = null;
        self.record("WAVE_START {d} enemies {d}", .{ wave.number, plan.enemyCount() });
    }
    fn addEnemy(self: *Game, enemy: *e.Enemy) void {
        self.living.append(self.backing, enemy) catch @panic("allocation failed");
        g.append(*e.Enemy, &self.all_enemies, enemy);
        self.living_count += 1;
        self.active.?.spawned += 1;
        enemy.kind.spawned += 1;
    }
    fn removeEnemy(self: *Game, enemy: *e.Enemy) void {
        enemy.alive = false;
        self.living_count -= 1;
    }
    fn compactLiving(self: *Game) void {
        var count: usize = 0;
        for (self.living.items) |enemy| {
            if (!enemy.alive) continue;
            self.living.items[count] = enemy;
            count += 1;
        }
        self.living.items.len = count;
    }
    fn spawnEnemies(self: *Game) void {
        if (self.next_start) |start| if (start == self.tick) { self.startWave(); };
        const wave = self.active orelse return;
        for (wave.plan.groups.items, 0..) |group, index| {
            const released = wave.released[index];
            if (released == group.count or group.spawnTick(wave.start, released) != self.tick) continue;
            wave.released[index] += 1;
            const spawn = self.grid.spawns[group.spawn - 1];
            const enemy = e.Enemy.create(self.all_enemies.items.len + 1, group.kind, group.multiplier);
            if (enemy.flying()) enemy.point = g.cellCenter(spawn) else {
                enemy.cell = spawn;
                enemy.next_cell = self.field.nextCell(spawn);
            }
            self.addEnemy(enemy);
            self.record("SPAWN E{d} {s} {d} hp {d}", .{ enemy.number, enemy.kind.name, group.spawn, enemy.hp });
        }
        wave.peak = @max(wave.peak, self.living_count);
    }
    fn moveEnemies(self: *Game) void {
        const initial_count = self.living.items.len;
        var index: usize = 0;
        while (index < initial_count) : (index += 1) {
            const enemy = self.living.items[index];
            if (!enemy.alive) continue;
            self.moveEnemy(enemy);
            if (self.outcome != null) return;
        }
        self.compactLiving();
    }
    fn moveEnemy(self: *Game, enemy: *e.Enemy) void {
        if (enemy.burn.active()) {
            const tower = self.towers.items[enemy.burn.source.? - 1];
            const damage = @min(enemy.hp, enemy.burn.strength);
            enemy.hp -= damage;
            self.credit(tower, enemy, damage);
            enemy.burn.advanceTime();
            if (enemy.hp == 0) {
                self.kill(enemy, tower);
                return;
            }
        }
        enemy.hp = @min(enemy.hp + enemy.kind.regen, enemy.max_hp);
        const speed = enemy.slowedSpeed();
        if (enemy.slow.active()) enemy.slow.advanceTime();
        var arrived: bool = undefined;
        if (enemy.flying()) {
            const movement = c.advance(enemy.point, g.cellCenter(self.grid.exit), speed);
            enemy.point = movement.point;
            arrived = movement.arrived;
        } else arrived = self.walk(enemy, speed);
        if (arrived) self.leak(enemy);
    }
    fn walk(self: *const Game, enemy: *e.Enemy, initial_speed: i64) bool {
        var speed = initial_speed;
        if (self.grid.water(enemy.occupiedCell())) speed = @divTrunc(speed, 2);
        while (speed > 0) {
            const rest = 100 - enemy.progress;
            if (speed < rest) {
                enemy.progress += speed;
                speed = 0;
            } else {
                speed -= rest;
                enemy.cell = enemy.next_cell;
                enemy.progress = 0;
                if (enemy.cell.same(self.grid.exit)) return true;
                enemy.next_cell = self.field.nextCell(enemy.cell);
            }
        }
        return false;
    }
    fn leak(self: *Game, enemy: *e.Enemy) void {
        self.removeEnemy(enemy);
        const lost = @min(self.lives, enemy.kind.lives);
        self.lives -= lost;
        const wave = self.active.?;
        wave.leaks += 1;
        wave.lives_lost += lost;
        enemy.kind.leaks += 1;
        self.record("LEAK E{d} {s} lives {d}", .{ enemy.number, enemy.kind.name, self.lives });
        if (self.lives == 0) {
            self.record("DEFEAT", .{});
            self.outcome = "defeat";
            wave.close("lost", self.tick, self.gold, self.lives);
            self.active = null;
        }
    }
    fn fireTowers(self: *Game) void {
        for (self.towers.items) |tower| {
            if (!tower.standing() or self.tick < tower.ready) continue;
            if (tower.selectTarget(self.living.items, &self.field)) |target| self.fire(tower, target);
        }
    }
    fn fire(self: *Game, tower: *t.Tower, target: *e.Enemy) void {
        const stats = tower.stats();
        self.projectile_count += 1;
        self.projectiles.append(self.backing, .{
            .number = self.projectile_count, .tower = tower.number, .target = target.number,
            .position = tower.center(), .aim = target.position(), .targets = tower.kind.targets,
            .power = stats.power, .speed = stats.shot_speed, .splash = stats.splash,
            .slow_rate = stats.slow_rate, .slow_time = stats.slow_time,
            .burn_amount = stats.burn_amount, .burn_time = stats.burn_time,
        }) catch @panic("allocation failed");
        tower.shots += 1;
        tower.ready = self.tick + stats.interval;
        self.record("SHOT T{d} E{d}", .{ tower.number, target.number });
    }
    fn moveProjectiles(self: *Game) void {
        var count: usize = 0;
        for (self.projectiles.items) |value| {
            var projectile = value;
            const target = self.all_enemies.items[projectile.target - 1];
            if (target.alive) projectile.aim = target.position();
            if (projectile.fly()) self.impact(projectile) else {
                self.projectiles.items[count] = projectile;
                count += 1;
            }
        }
        self.projectiles.items.len = count;
        self.compactLiving();
    }
    fn impact(self: *Game, projectile: c.Projectile) void {
        const tower = self.towers.items[projectile.tower - 1];
        const target = self.all_enemies.items[projectile.target - 1];
        var victims: std.ArrayList(*e.Enemy) = .empty;
        defer victims.deinit(self.backing);
        if (projectile.splash == 0) {
            if (target.alive) victims.append(self.backing, target) catch @panic("allocation failed");
        } else {
            const reach = projectile.splash * projectile.splash;
            for (self.living.items) |enemy| {
                if (enemy.alive and t.canAim(projectile.targets, enemy) and c.squaredDistance(enemy.position(), projectile.aim) <= reach) victims.append(self.backing, enemy) catch @panic("allocation failed");
            }
        }
        if (victims.items.len == 0) tower.fizzles += 1;
        for (victims.items) |enemy| {
            tower.hits += 1;
            const damage = c.damageDealt(enemy.hp, projectile.power, enemy.kind.armor);
            enemy.hp -= damage;
            self.credit(tower, enemy, damage);
            if (enemy.hp == 0) {
                self.kill(enemy, tower);
                continue;
            }
            if (projectile.slow_rate > 0) enemy.slow.receive(projectile.slow_rate, projectile.slow_time, null);
            if (projectile.burn_amount > 0) enemy.burn.receive(projectile.burn_amount, projectile.burn_time, tower.number);
        }
    }
    fn credit(self: *Game, tower: *t.Tower, enemy: *e.Enemy, damage: i64) void {
        tower.damage += damage;
        enemy.kind.damage += damage;
        self.active.?.tower_damage[tower.number - 1] += damage;
    }
    fn kill(self: *Game, enemy: *e.Enemy, tower: *t.Tower) void {
        self.removeEnemy(enemy);
        self.kill_counts[self.grid.index(enemy.occupiedCell())] += 1;
        const wave = self.active.?;
        const bounty = enemy.kind.bounty;
        tower.kills += 1;
        wave.kills += 1;
        enemy.kind.kills += 1;
        self.gold += bounty;
        wave.bounty += bounty;
        self.income.bounty += bounty;
        self.record("KILL E{d} {s} T{d} bounty {d} gold {d}", .{ enemy.number, enemy.kind.name, tower.number, bounty, self.gold });
        for (0..enemy.kind.split_count) |_| {
            const child = enemy.split(self.all_enemies.items.len + 1);
            self.addEnemy(child);
            self.record("SPAWN E{d} {s} E{d} hp {d}", .{ child.number, child.kind.name, enemy.number, child.hp });
        }
    }
    fn checkWaveEnd(self: *Game) void {
        const wave = self.active orelse return;
        if (self.living_count > 0 or !wave.allReleased()) return;
        const reward = wave.plan.reward;
        self.gold += reward;
        const interest = @min(self.params.interest_cap, @divTrunc(self.gold * self.params.interest_rate, 100));
        self.gold += interest;
        wave.reward = reward;
        wave.interest = interest;
        self.income.reward += reward;
        self.income.interest += interest;
        self.active = null;
        self.record("WAVE_END {d} reward {d} interest {d} gold {d}", .{ wave.number, reward, interest, self.gold });
        if (wave.number == self.waves.len) {
            self.record("VICTORY", .{});
            self.outcome = "victory";
        } else self.next_start = self.tick + self.params.interval;
        wave.close("cleared", self.tick, self.gold, self.lives);
    }
    fn ruled(self: *const Game, picture: []const u8) Lines {
        var lines: Lines = .{};
        var ruler: Text = .{};
        ruler.write("  ");
        for (0..self.grid.width) |x| ruler.add("{d}", .{x % 10});
        lines.write(ruler.value());
        for (0..self.grid.height) |y| lines.add("{d} {s}", .{ y % 10, picture[y * self.grid.width .. (y + 1) * self.grid.width] });
        return lines;
    }
    fn mapPicture(self: *const Game) []u8 {
        const picture = g.alloc(u8, self.grid.width * self.grid.height);
        for (self.grid.rows, 0..) |row, y| @memcpy(picture[y * self.grid.width .. (y + 1) * self.grid.width], row);
        for (self.grid.spawns) |spawn| {
            for (self.field.path(spawn)) |cell| {
                const terrain = self.grid.terrain(cell);
                if (terrain == '.' or terrain == '~') picture[self.grid.index(cell)] = '+';
            }
        }
        for (self.towers.items) |tower| if (tower.standing()) { picture[self.grid.index(tower.cell)] = tower.kind.symbol; };
        var occupants: [1200]i64 = @splat(0);
        for (self.living.items) |enemy| {
            if (!enemy.alive) continue;
            const index = self.grid.index(enemy.occupiedCell());
            occupants[index] += 1;
            picture[index] = if (occupants[index] == 1) enemy.kind.symbol else '*';
        }
        return picture;
    }
    fn flowPicture(self: *const Game) []u8 {
        const picture = g.alloc(u8, self.grid.width * self.grid.height);
        for (0..self.grid.height) |y| {
            for (0..self.grid.width) |x| {
                const cell: g.Cell = .{ .x = g.n(x), .y = g.n(y) };
                const index = self.grid.index(cell);
                const terrain = self.grid.terrain(cell);
                if (terrain == '#' or terrain == 'E') {
                    picture[index] = terrain;
                } else if (self.towerAt(cell)) |tower| {
                    picture[index] = tower.kind.symbol;
                } else if (self.field.at(cell) < 0) {
                    picture[index] = '?';
                } else picture[index] = "^>v<"[self.field.direction(cell)];
            }
        }
        return picture;
    }
    fn coveragePicture(self: *const Game) []u8 {
        const picture = g.alloc(u8, self.grid.width * self.grid.height);
        for (0..self.grid.height) |y| {
            for (0..self.grid.width) |x| {
                const cell: g.Cell = .{ .x = g.n(x), .y = g.n(y) };
                const index = self.grid.index(cell);
                if (self.grid.rock(cell)) {
                    picture[index] = '#';
                } else if (self.towerAt(cell)) |tower| {
                    picture[index] = tower.kind.symbol;
                } else {
                    var count: i64 = 0;
                    for (self.towers.items) |tower| if (tower.standing() and tower.inRange(g.cellCenter(cell))) { count += 1; };
                    picture[index] = digit(count);
                }
            }
        }
        return picture;
    }
    fn killsPicture(self: *const Game) []u8 {
        const picture = g.alloc(u8, self.grid.width * self.grid.height);
        for (0..self.grid.height) |y| {
            for (0..self.grid.width) |x| {
                const cell: g.Cell = .{ .x = g.n(x), .y = g.n(y) };
                const index = self.grid.index(cell);
                const count = self.kill_counts[index];
                picture[index] = if (count > 0) digit(count) else if (self.grid.rock(cell)) '#' else '.';
            }
        }
        return picture;
    }
    fn block(self: *const Game, label: []const u8) Lines {
        const waiting = self.active == null and self.outcome == null;
        const next = if (waiting) fmt("{d}", .{self.next_start.?}) else "-";
        var lines: Lines = .{};
        lines.add("{s} {d} wave {d} next {s} gold {d} lives {d}", .{ label, self.tick, self.records.items.len, next, self.gold, self.lives });
        lines.extend(self.ruled(self.mapPicture()));
        for (self.grid.spawns, 1..) |spawn, number| lines.add("PATH {d} length {d}", .{ number, self.field.at(spawn) });
        for (self.towers.items) |tower| {
            if (!tower.standing()) continue;
            lines.add("T{d} {s} {d} {d} level {d} mode {s} ready {d}", .{ tower.number, tower.kind.name, tower.cell.x, tower.cell.y, tower.level, t.modeText(tower.mode), tower.ready });
        }
        for (self.living.items) |enemy| {
            if (!enemy.alive) continue;
            const position = enemy.position();
            lines.add("E{d} {s} {d} {d} hp {d}/{d} slow {d} {d} burn {d} {d}", .{ enemy.number, enemy.kind.name, position.x, position.y, enemy.hp, enemy.max_hp, enemy.slow.strength, enemy.slow.remaining, enemy.burn.strength, enemy.burn.remaining });
        }
        for (self.projectiles.items) |projectile| lines.add("P{d} T{d} E{d} {d} {d}", .{ projectile.number, projectile.tower, projectile.target, projectile.position.x, projectile.position.y });
        return lines;
    }
    fn finalBlock(self: *const Game) Lines {
        var lines = self.block("FINAL");
        lines.write("FLOW");
        lines.extend(self.ruled(self.flowPicture()));
        lines.write("COVERAGE");
        lines.extend(self.ruled(self.coveragePicture()));
        lines.write("KILLS");
        lines.extend(self.ruled(self.killsPicture()));
        return lines;
    }
    fn waveLines(self: *const Game) Lines {
        var header: Text = .{};
        header.write("wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives");
        for (self.towers.items) |tower| header.add(",T{d}", .{tower.number});
        var lines: Lines = .{};
        lines.write(header.value());
        for (self.records.items) |wave| lines.write(wave.csvRow(self.towers.items.len));
        return lines;
    }
    fn mvpLine(self: *const Game) []const u8 {
        var best: ?*t.Tower = null;
        for (self.towers.items) |tower| if (best == null or tower.damage > best.?.damage) { best = tower; };
        return if (best) |tower| fmt("mvp T{d} damage {d}", .{ tower.number, tower.damage }) else "mvp -";
    }
    fn towerLine(tower: *const t.Tower, total_damage: i64) []const u8 {
        const state = if (tower.sold) |sold| fmt("sold {d}", .{sold}) else "active";
        return fmt("TOWER T{d} {s} {d} {d} level {d} mode {s} {s} shots {d} hits {d} fizzles {d} kills {d} damage {d} per_shot {s} share {s} invested {d}", .{ tower.number, tower.kind.name, tower.cell.x, tower.cell.y, tower.level, t.modeText(tower.mode), state, tower.shots, tower.hits, tower.fizzles, tower.kills, tower.damage, oneDecimal(tower.damage, tower.shots), oneDecimal(100 * tower.damage, total_damage), tower.investment });
    }
    fn summaryLines(self: *const Game, action_count: usize) Lines {
        var cleared: usize = 0;
        var perfect: usize = 0;
        for (self.records.items) |wave| {
            if (!g.eq(wave.status, "cleared")) continue;
            cleared += 1;
            if (wave.leaks == 0) perfect += 1;
        }
        var spawned: i64 = 0;
        var killed: i64 = 0;
        var leaked: i64 = 0;
        for (self.enemy_types) |kind| {
            spawned += kind.spawned;
            killed += kind.kills;
            leaked += kind.leaks;
        }
        var total_damage: i64 = 0;
        for (self.towers.items) |tower| total_damage += tower.damage;
        const unused = action_count - self.done - self.refused;
        const score = 10 * killed + 100 * self.lives + 50 * g.n(perfect) + self.gold;
        var lines: Lines = .{};
        lines.add("outcome {s}", .{self.outcome.?});
        lines.add("ticks {d}", .{self.tick});
        lines.add("waves {d}/{d} perfect {d}", .{ cleared, self.waves.len, perfect });
        lines.add("lives {d}/{d}", .{ self.lives, self.params.lives });
        lines.add("gold {d}", .{self.gold});
        lines.add("enemies spawned {d} killed {d} leaked {d}", .{ spawned, killed, leaked });
        lines.add("income bounty {d} reward {d} interest {d} early {d} refund {d}", .{ self.income.bounty, self.income.reward, self.income.interest, self.income.early, self.income.refund });
        lines.add("spent {d}", .{self.spent});
        lines.add("damage {d}", .{total_damage});
        lines.add("actions total {d} done {d} refused {d} unused {d}", .{ action_count, self.done, self.refused, unused });
        lines.add("score {d}", .{score});
        lines.write(self.mvpLine());
        for (self.enemy_types) |kind| lines.add("ENEMY {s} spawned {d} killed {d} leaked {d} damage {d}", .{ kind.name, kind.spawned, kind.kills, kind.leaks, kind.damage });
        for (self.towers.items) |tower| lines.write(towerLine(tower, total_damage));
        return lines;
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    g.allocator = arena.allocator();
    const grid = &g.alloc(g.GridMap, 1)[0];
    grid.* = try g.GridMap.read(init.io);
    const tower_types = t.parseTowerTypes(try readLines(init.io, "towers.txt"));
    const wave_input = e.parseWaves(try readLines(init.io, "waves.txt"));
    const action_source = try readLines(init.io, "actions.txt");
    const actions = g.alloc(Action, action_source.len);
    for (action_source, actions) |line, *action| action.* = Action.parse(line);
    const params = &g.alloc(Params, 1)[0];
    params.* = Params.parse(try readLines(init.io, "params.txt"));
    const game = Game.create(init.gpa, grid, tower_types, wave_input, params);
    defer game.deinit();
    game.run(actions);
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try writeLines(init.io, "events.txt", game.events);
    try writeLines(init.io, "waves.csv", game.waveLines());
    try writeLines(init.io, "snapshots.txt", game.snapshots);
    try writeLines(init.io, "summary.txt", game.summaryLines(actions.len));
}
