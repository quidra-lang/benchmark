const std = @import("std");
const e = @import("entities.zig");
const Minstd = @import("minstd.zig").Minstd;
const combat = @import("combat.zig");
const gen = @import("dungeon_gen.zig");
const fov = @import("fov.zig");

const Config = struct {
    generation_seed: i64, game_seed: i64, width: usize, height: usize,
    min_size: usize, max_split: usize, room_min: usize, room_max: usize, levels: usize,
    monster_base: usize, monster_step: usize, item_base: usize, item_step: usize,
    sleep_chance: i64, wake_chance: i64, radius: i64, max_hp: i64, regen: usize,
    hitdie: combat.Dice, food_start: i64, food_max: i64, food_hungry: i64, food_weak: i64,
    pack_limit: usize, start: e.Strings, xp: []i64, checkpoints: []usize,
};
const Command = struct { name: []const u8, argument: []const u8 };
const Player = struct {
    x: i64, y: i64, depth: usize = 1, hp: i64, max_hp: i64, level: usize = 1,
    xp: i64 = 0, gold: i64 = 0, satiation: i64, poison: i64 = 0,
    pack: std.ArrayList(*e.Item) = .empty, weapon: ?*e.Item = null, armor: ?*e.Item = null,
    fn defense(self: *const Player) i64 { return 10 + (if (self.armor) |item| item.kind.armor + item.bonus else 0); }
};
const AttackStats = struct {
    count: usize = 0, hits: usize = 0, criticals: usize = 0, damage: i64 = 0,
    fn record(self: *AttackStats, attack: combat.Attack) void {
        self.count += 1;
        if (attack.outcome != .miss) { self.hits += 1; self.damage += attack.damage; }
        if (attack.outcome == .critical) self.criticals += 1;
    }
    fn write(self: AttackStats, name: []const u8, lines: *e.Lines) void {
        lines.add("{s} {d} hits {d} criticals {d} damage {d} accuracy {s}", .{ name, self.count, self.hits, self.criticals, self.damage, dec1(100 * self.hits, self.count) });
    }
};
const Result = enum { won, died, alive };
const Game = struct {
    config: Config, monster_types: []e.MonsterType, item_types: []e.ItemType, commands: []Command,
    amulet: e.ItemType = .{ .category = .amulet, .name = "amulet" },
    generation_rng: Minstd, rng: Minstd, levels: []gen.Level, player: Player = undefined,
    turn: usize = 1, messages: e.Lines = .{}, maps: e.Lines = .{}, visible: []bool = &.{}, distance: []i64 = &.{},
    result: ?Result = null, cause: []const u8 = "", succeeded: usize = 0, failed: usize = 0, unused: usize = 0,
    moves: usize = 0, poison_damage: usize = 0, starvation_damage: usize = 0,
    usage: [6]usize = [_]usize{0} ** 6, kills: [20]usize = [_]usize{0} ** 20,
    player_attacks: AttackStats = .{}, monster_attacks: AttackStats = .{},

    fn currentLevel(self: *Game) *gen.Level { return &self.levels[self.player.depth - 1]; }
    fn say(self: *Game, comptime pattern: []const u8, arguments: anytype) void { self.messages.add("{d:0>4} {s}", .{ self.turn, e.fmt(pattern, arguments) }); }
    fn hunger(self: *const Game) []const u8 {
        if (self.player.satiation > self.config.food_hungry) return "normal";
        if (self.player.satiation > self.config.food_weak) return "hungry";
        return if (self.player.satiation > 0) "weak" else "starving";
    }
    fn die(self: *Game, cause: []const u8) void { self.say("You die.", .{}); self.result = .died; self.cause = cause; }

    fn buildLevels(self: *Game) void {
        const generator: gen.Generator = .{ .rng = &self.generation_rng, .min_size = self.config.min_size, .max_split = self.config.max_split, .room_min = self.config.room_min, .room_max = self.config.room_max };
        for (self.levels, 1..) |*level, depth| {
            level.* = generator.generate(depth, self.config.width, self.config.height);
            var items: std.ArrayList(*e.Item) = .empty;
            if (depth < self.config.levels) level.terrain[e.u(level.target.y) * level.width + e.u(level.target.x)] = '>' else {
                e.append(*e.Item, &items, newItem(&self.amulet, level.target.x, level.target.y, true));
                level.items = items.items;
            }
            var ids: [30]usize = undefined;
            var weights: [30]usize = undefined;
            var candidate_count: usize = 0;
            for (self.monster_types, 0..) |kind, i| {
                if (kind.min_depth <= depth and depth <= kind.max_depth) { ids[candidate_count] = i; weights[candidate_count] = kind.weight; candidate_count += 1; }
            }
            const monster_count = self.config.monster_base + self.config.monster_step * (depth - 1);
            level.monsters = e.alloc(e.Monster, monster_count);
            @memset(level.monsters, .{});
            for (level.monsters, 1..) |*monster, number| {
                const choice = self.generation_rng.select(weights[0..candidate_count]);
                const kind = &self.monster_types[ids[choice]];
                var cell: gen.RoomCell = undefined;
                while (true) {
                    cell = level.drawRoomCell(&self.generation_rng);
                    if (cell.room != level.arrival_room and level.terrain[e.u(cell.y) * level.width + e.u(cell.x)] == '.' and level.monsterAt(cell.x, cell.y) == null) break;
                }
                const hp = kind.hp.roll(&self.generation_rng);
                const asleep = @mod(self.generation_rng.draw(), 100) < self.config.sleep_chance;
                monster.* = .{ .number = number, .kind = kind, .x = cell.x, .y = cell.y, .hp = hp, .max_hp = hp, .asleep = asleep };
            }
            candidate_count = 0;
            for (self.item_types, 0..) |kind, i| {
                if (kind.min_depth <= depth and depth <= kind.max_depth) { ids[candidate_count] = i; weights[candidate_count] = kind.weight; candidate_count += 1; }
            }
            const item_count = self.config.item_base + self.config.item_step * (depth - 1);
            for (0..item_count) |_| {
                const choice = self.generation_rng.select(weights[0..candidate_count]);
                const kind = &self.item_types[ids[choice]];
                var cell: gen.RoomCell = undefined;
                while (true) {
                    cell = level.drawRoomCell(&self.generation_rng);
                    if (level.terrain[e.u(cell.y) * level.width + e.u(cell.x)] == '.' and level.itemAt(cell.x, cell.y) == null) break;
                }
                const item = newItem(kind, cell.x, cell.y, true);
                if (kind.category == .gold) item.amount = kind.dice.roll(&self.generation_rng);
                e.append(*e.Item, &items, item);
                level.items = items.items;
            }
            level.items_placed = level.items.len;
        }
    }

    fn initializePlayer(self: *Game) void {
        self.player = .{ .x = self.levels[0].arrival.x, .y = self.levels[0].arrival.y, .hp = self.config.max_hp, .max_hp = self.config.max_hp, .satiation = self.config.food_start };
        for (self.config.start) |name| {
            var kind: *const e.ItemType = undefined;
            for (self.item_types) |*candidate| if (e.eq(name, candidate.name)) { kind = candidate; break; };
            const item = newItem(kind, self.player.x, self.player.y, false);
            e.append(*e.Item, &self.player.pack, item);
            if (kind.category == .weapon and self.player.weapon == null) self.player.weapon = item;
            if (kind.category == .armor and self.player.armor == null) self.player.armor = item;
        }
    }

    fn updateView(self: *Game) void {
        const level = self.currentLevel();
        self.visible = fov.fieldOfView(level, self.player.x, self.player.y, self.config.radius);
        for (0..level.height) |y| {
            for (0..level.width) |x| {
                const cell = y * level.width + x;
                if (!self.visible[cell]) continue;
                level.memory[cell] = if (level.itemAt(e.n(x), e.n(y))) |item| item.symbol() else level.terrain[cell];
            }
        }
        for (level.monsters) |*monster| {
            if (monster.hp <= 0) continue;
            const seen = self.visible[e.u(monster.y) * level.width + e.u(monster.x)];
            if (seen and !monster.was_visible) self.say("You see the {s}.", .{monster.kind.name});
            monster.was_visible = seen;
        }
    }

    fn gainXp(self: *Game, amount: i64) void {
        self.player.xp += amount;
        while (self.player.level <= self.config.xp.len and self.player.xp >= self.config.xp[self.player.level - 1]) {
            self.player.level += 1;
            const gained = self.config.hitdie.roll(&self.rng);
            self.player.max_hp += gained;
            self.player.hp += gained;
            self.say("Welcome to level {d}.", .{self.player.level});
        }
    }

    fn playerAttack(self: *Game, monster: *e.Monster) void {
        monster.asleep = false;
        var to_hit = e.n(self.player.level);
        var bonus: i64 = 0;
        var dice: combat.Dice = .{ .count = 1, .sides = 2 };
        if (self.player.weapon) |weapon| { to_hit += weapon.kind.to_hit + weapon.bonus; bonus = weapon.bonus; dice = weapon.kind.dice; }
        if (self.player.satiation <= self.config.food_weak) to_hit -= 2;
        const attack = combat.resolveAttack(&self.rng, to_hit, monster.kind.defense, dice, bonus);
        self.player_attacks.record(attack);
        if (attack.outcome == .miss) { self.say("You miss the {s}.", .{monster.kind.name}); return; }
        self.say("You hit the {s}{s} for {d}.", .{ monster.kind.name, if (attack.outcome == .critical) " hard" else "", attack.damage });
        monster.hp -= attack.damage;
        if (monster.hp <= 0) {
            self.say("You kill the {s}.", .{monster.kind.name});
            self.currentLevel().kills += 1;
            for (self.monster_types, 0..) |*kind, i| if (kind == monster.kind) { self.kills[i] += 1; break; };
            self.gainXp(monster.kind.xp);
        }
    }

    fn monsterAttack(self: *Game, monster: *e.Monster) void {
        const kind = monster.kind;
        const attack = combat.resolveAttack(&self.rng, kind.to_hit, self.player.defense(), kind.damage, 0);
        self.monster_attacks.record(attack);
        if (attack.outcome == .miss) { self.say("The {s} misses you.", .{kind.name}); return; }
        self.say("The {s} hits you{s} for {d}.", .{ kind.name, if (attack.outcome == .critical) " hard" else "", attack.damage });
        self.player.hp -= attack.damage;
        if (self.player.hp <= 0) self.die(e.fmt("killed_by {s}", .{kind.name})) else if (kind.poisonous) { self.player.poison += 5; self.say("You are poisoned.", .{}); }
    }

    fn movePlayer(self: *Game, direction: e.Point) bool {
        const level = self.currentLevel();
        const x = self.player.x + direction.x;
        const y = self.player.y + direction.y;
        if (!fov.passable(level, x, y)) { self.say("You bump into a wall.", .{}); return false; }
        if (!fov.canMove(level, self.player.x, self.player.y, direction.x, direction.y)) { self.say("You cannot move diagonally through a door.", .{}); return false; }
        if (level.monsterAt(x, y)) |monster| { self.playerAttack(monster); return true; }
        self.player.x = x;
        self.player.y = y;
        self.moves += 1;
        if (level.itemAt(x, y)) |item| self.say("You see {s} here.", .{item.referenceName()}) else if (level.terrain[e.u(y) * level.width + e.u(x)] == '>') self.say("There is a staircase down here.", .{});
        return true;
    }

    fn pickup(self: *Game) bool {
        const level = self.currentLevel();
        const item = level.itemAt(self.player.x, self.player.y) orelse { self.say("There is nothing here.", .{}); return false; };
        switch (item.kind.category) {
            .gold => { self.player.gold += item.amount; self.say("You pick up {s}.", .{item.displayName()}); },
            .amulet => { self.say("You pick up the amulet.", .{}); self.say("You win!", .{}); self.result = .won; self.cause = "amulet"; },
            else => {
                if (self.player.pack.items.len == self.config.pack_limit) { self.say("Your pack is full.", .{}); return false; }
                e.append(*e.Item, &self.player.pack, item);
                self.say("You pick up the {s} ({d}).", .{ item.displayName(), self.player.pack.items.len });
            },
        }
        item.ground = false;
        level.picked += 1;
        self.usage[0] += 1;
        return true;
    }

    fn useItem(self: *Game, name: []const u8, number: usize) bool {
        const level = self.currentLevel();
        if (number > self.player.pack.items.len) { self.say("You do not have that item.", .{}); return false; }
        const item = self.player.pack.items[number - 1];
        const required: e.ItemClass = if (e.eq(name, "quaff")) .potion else if (e.eq(name, "read")) .scroll else if (e.eq(name, "wield")) .weapon else if (e.eq(name, "wear")) .armor else .food;
        if (item.kind.category != required) { self.say("You cannot {s} that.", .{name}); return false; }
        if (required == .weapon) {
            if (self.player.weapon == item) { self.say("You are already wielding that.", .{}); return false; }
            self.player.weapon = item;
            self.usage[4] += 1;
            self.say("You are now wielding the {s}.", .{item.displayName()});
            return true;
        }
        if (required == .armor) {
            if (self.player.armor == item) { self.say("You are already wearing that.", .{}); return false; }
            self.player.armor = item;
            self.usage[5] += 1;
            self.say("You are now wearing the {s}.", .{item.displayName()});
            return true;
        }
        _ = self.player.pack.orderedRemove(number - 1);
        if (required == .food) {
            self.usage[3] += 1;
            self.player.satiation = @min(self.player.satiation + item.kind.nutrition, self.config.food_max);
            self.say("You eat the {s}.", .{item.displayName()});
            return true;
        }
        const effect = item.kind.effect;
        if (required == .potion) {
            self.usage[1] += 1;
            self.say("You quaff the {s}.", .{item.displayName()});
            if (e.eq(effect, "heal")) {
                self.player.hp += item.kind.dice.roll(&self.rng);
                if (self.player.hp > self.player.max_hp) { self.player.max_hp += 1; self.player.hp = self.player.max_hp; }
                self.player.poison = 0;
                self.say("You feel better.", .{});
            } else if (e.eq(effect, "poison")) { self.player.poison += item.kind.poison_turns; self.say("You feel very sick.", .{}); } else {
                self.say("You feel more experienced.", .{});
                if (self.player.level <= self.config.xp.len) self.gainXp(self.config.xp[self.player.level - 1] - self.player.xp);
            }
        } else {
            self.usage[2] += 1;
            self.say("You read the {s}.", .{item.displayName()});
            if (e.eq(effect, "mapping")) {
                for (level.terrain, level.memory) |terrain, *memory| if (terrain != ' ' and memory.* == ' ') { memory.* = terrain; };
                self.say("A map forms in your mind.", .{});
            } else if (e.eq(effect, "teleport")) {
                var cell: gen.RoomCell = undefined;
                while (true) {
                    cell = level.drawRoomCell(&self.rng);
                    if ((cell.x != self.player.x or cell.y != self.player.y) and level.monsterAt(cell.x, cell.y) == null) break;
                }
                self.player.x = cell.x;
                self.player.y = cell.y;
                self.say("You are teleported.", .{});
            } else if (e.eq(effect, "enchant_weapon")) {
                if (self.player.weapon) |weapon| { self.say("Your {s} glows blue.", .{weapon.displayName()}); weapon.bonus += 1; } else self.say("Your hands twitch.", .{});
            } else {
                if (self.player.armor) |armor| { self.say("Your {s} glows silver.", .{armor.displayName()}); armor.bonus += 1; } else self.say("Your skin tingles.", .{});
            }
        }
        return true;
    }

    fn execute(self: *Game, command: Command) bool {
        if (e.eq(command.name, "move")) {
            for (fov.direction_names, fov.directions) |name, direction| if (e.eq(name, command.argument)) return self.movePlayer(direction);
        }
        if (e.eq(command.name, "wait")) return true;
        if (e.eq(command.name, "pickup")) return self.pickup();
        if (e.eq(command.name, "descend")) {
            const level = self.currentLevel();
            if (level.terrain[e.u(self.player.y) * level.width + e.u(self.player.x)] != '>') { self.say("There are no stairs here.", .{}); return false; }
            self.player.depth += 1;
            const destination = self.currentLevel().arrival;
            self.player.x = destination.x;
            self.player.y = destination.y;
            self.say("You descend to depth {d}.", .{self.player.depth});
            return true;
        }
        return self.useItem(command.name, e.integer(command.argument));
    }

    fn canAttack(self: *Game, monster: *const e.Monster) bool {
        const dx = self.player.x - monster.x;
        const dy = self.player.y - monster.y;
        if (@max(e.abs(dx), e.abs(dy)) != 1) return false;
        return fov.canMove(self.currentLevel(), monster.x, monster.y, dx, dy);
    }

    fn wander(self: *Game, monster: *e.Monster) void {
        const direction = fov.directions[self.rng.rnd(8)];
        const level = self.currentLevel();
        if (!fov.canMove(level, monster.x, monster.y, direction.x, direction.y)) return;
        const x = monster.x + direction.x;
        const y = monster.y + direction.y;
        if (x == self.player.x and y == self.player.y) self.monsterAttack(monster) else if (level.monsterAt(x, y) == null) { monster.x = x; monster.y = y; }
    }

    fn chase(self: *Game, monster: *e.Monster) void {
        if (self.canAttack(monster)) { self.monsterAttack(monster); return; }
        const level = self.currentLevel();
        const here = self.distance[e.u(monster.y) * level.width + e.u(monster.x)];
        var chosen: ?e.Point = null;
        var minimum: i64 = 0;
        for (fov.directions) |direction| {
            if (!fov.canMove(level, monster.x, monster.y, direction.x, direction.y)) continue;
            const x = monster.x + direction.x;
            const y = monster.y + direction.y;
            const distance = self.distance[e.u(y) * level.width + e.u(x)];
            if (distance < 0 or (here >= 0 and distance >= here)) continue;
            if (level.monsterAt(x, y) != null or (x == self.player.x and y == self.player.y)) continue;
            if (chosen == null or distance < minimum) { chosen = .{ .x = x, .y = y }; minimum = distance; }
        }
        if (chosen) |point| { monster.x = point.x; monster.y = point.y; }
    }

    fn monsterAction(self: *Game, monster: *e.Monster) void {
        const level = self.currentLevel();
        const sees = self.visible[e.u(monster.y) * level.width + e.u(monster.x)];
        if (monster.asleep) {
            if (sees and @mod(self.rng.draw(), 100) < self.config.wake_chance) { monster.asleep = false; self.say("The {s} wakes up.", .{monster.kind.name}); }
        } else if (monster.kind.stationary) {
            if (self.canAttack(monster)) self.monsterAttack(monster);
        } else if (monster.kind.erratic and @mod(self.rng.draw(), 2) == 0) self.wander(monster) else if (sees) self.chase(monster) else self.wander(monster);
    }

    fn monstersAct(self: *Game) void {
        const level = self.currentLevel();
        self.distance = fov.distances(level, self.player.x, self.player.y);
        for (level.monsters) |*monster| {
            if (monster.hp <= 0) continue;
            monster.energy += monster.kind.speed;
            while (monster.energy >= 2) {
                monster.energy -= 2;
                self.monsterAction(monster);
                if (self.result != null) return;
            }
        }
    }

    fn endTurn(self: *Game) void {
        for (self.currentLevel().monsters) |*monster| {
            if (monster.hp > 0 and monster.kind.regenerates and monster.hp < monster.max_hp) monster.hp += 1;
        }
        if (self.player.poison > 0) {
            self.player.hp -= 1;
            self.poison_damage += 1;
            if (self.player.hp <= 0) { self.die("poison"); return; }
            self.player.poison -= 1;
            if (self.player.poison == 0) self.say("You feel less sick.", .{});
        }
        if (self.player.satiation == 0) {
            self.player.hp -= 1;
            self.starvation_damage += 1;
            if (self.player.hp <= 0) { self.die("starvation"); return; }
        } else {
            const before = self.hunger();
            self.player.satiation -= 1;
            const after = self.hunger();
            if (!e.eq(before, after)) {
                if (e.eq(after, "hungry")) self.say("You are getting hungry.", .{}) else if (e.eq(after, "weak")) self.say("You feel weak from hunger.", .{}) else self.say("You are starving.", .{});
            }
        }
        if (self.turn % self.config.regen == 0 and self.player.poison == 0 and self.player.satiation > 0 and self.player.hp < self.player.max_hp) self.player.hp += 1;
    }

    fn statusLine(self: *const Game) []const u8 {
        const player = &self.player;
        return e.fmt("STATUS hp {d}/{d} level {d} xp {d} defense {d} gold {d} food {d} {s} poison {d}", .{ player.hp, player.max_hp, player.level, player.xp, player.defense(), player.gold, player.satiation, self.hunger(), player.poison });
    }

    fn mapRows(self: *const Game, level: *const gen.Level, current: bool, lines: *e.Lines) void {
        const border = e.alloc(u8, level.width + 2);
        @memset(border, '-');
        border[0] = '+';
        border[border.len - 1] = '+';
        lines.write(border);
        for (0..level.height) |y| {
            const row = e.alloc(u8, level.width + 2);
            row[0] = '|';
            row[row.len - 1] = '|';
            for (0..level.width) |x| {
                const cell = y * level.width + x;
                var value = level.memory[cell];
                if (current and self.visible[cell]) {
                    if (e.n(x) == self.player.x and e.n(y) == self.player.y) value = '@' else if (level.monsterAt(e.n(x), e.n(y))) |monster| value = monster.kind.symbol else if (level.itemAt(e.n(x), e.n(y))) |item| value = item.symbol() else value = level.terrain[cell];
                }
                row[x + 1] = value;
            }
            lines.write(row);
        }
        lines.write(border);
    }

    fn checkpoint(self: *Game) void {
        self.maps.add("CHECKPOINT turn {d} depth {d}", .{ self.turn, self.player.depth });
        self.mapRows(self.currentLevel(), true, &self.maps);
        self.maps.write(self.statusLine());
    }

    fn run(self: *Game) void {
        self.updateView();
        for (self.commands) |command| {
            if (self.result != null) { self.unused += 1; continue; }
            if (!self.execute(command)) { self.failed += 1; continue; }
            self.succeeded += 1;
            if (self.result != null) continue;
            self.updateView();
            self.monstersAct();
            if (self.result != null) continue;
            self.endTurn();
            if (self.result != null) continue;
            for (self.config.checkpoints) |turn| if (turn == self.turn) { self.checkpoint(); };
            self.turn += 1;
        }
        if (self.result == null) { self.result = .alive; self.cause = "commands_exhausted"; }
    }

    fn finalBlock(self: *Game) void {
        self.maps.add("FINAL turn {d} depth {d}", .{ self.succeeded, self.player.depth });
        for (self.levels[0..self.player.depth]) |*level| {
            const explored = exploration(level);
            self.maps.add("LEVEL {d} explored {d}/{d}", .{ level.depth, explored.seen, explored.total });
            self.mapRows(level, level.depth == self.player.depth, &self.maps);
        }
        self.maps.write(self.statusLine());
    }

    fn statsLines(self: *const Game) e.Lines {
        const player = &self.player;
        var lines: e.Lines = .{};
        lines.add("result {s}", .{@tagName(self.result.?)});
        lines.add("cause {s}", .{self.cause});
        lines.add("turns {d}", .{self.succeeded});
        lines.add("depth {d}", .{player.depth});
        lines.add("level {d}", .{player.level});
        lines.add("xp {d}", .{player.xp});
        lines.add("hp {d}/{d}", .{ player.hp, player.max_hp });
        lines.add("defense {d}", .{player.defense()});
        lines.add("gold {d}", .{player.gold});
        lines.add("food {d} {s}", .{ player.satiation, self.hunger() });
        lines.add("poison {d}", .{player.poison});
        lines.add("weapon {s}", .{if (player.weapon) |item| item.displayName() else "-"});
        lines.add("armor {s}", .{if (player.armor) |item| item.displayName() else "-"});
        lines.add("commands {d} executed {d} failed {d} unused {d}", .{ self.commands.len, self.succeeded, self.failed, self.unused });
        lines.add("moves {d}", .{self.moves});
        self.player_attacks.write("player_attacks", &lines);
        self.monster_attacks.write("monster_attacks", &lines);
        lines.add("poison_damage {d} starvation_damage {d}", .{ self.poison_damage, self.starvation_damage });
        lines.add("picked {d} quaffed {d} read {d} eaten {d} wielded {d} worn {d}", .{ self.usage[0], self.usage[1], self.usage[2], self.usage[3], self.usage[4], self.usage[5] });
        var kills: usize = 0;
        for (self.kills[0..self.monster_types.len]) |count| kills += count;
        lines.add("kills {d}", .{kills});
        for (self.monster_types, self.kills[0..self.monster_types.len]) |kind, count| if (count > 0) { lines.add("KILL {s} {d}", .{ kind.name, count }); };
        for (self.levels) |*level| {
            const explored = exploration(level);
            lines.add("LEVEL {d} rooms {d} explored {d}/{d} {s} monsters {d}/{d} items {d}/{d}", .{
                level.depth, level.rooms.len, explored.seen, explored.total, dec1(100 * explored.seen, explored.total), level.kills, level.monsters.len, level.picked, level.items_placed,
            });
        }
        for (player.pack.items, 1..) |item, number| lines.add("INVENTORY {d} {s}{s}", .{ number, item.displayName(), if (item == player.weapon) " (wielded)" else if (item == player.armor) " (worn)" else "" });
        return lines;
    }
};

fn newItem(kind: *const e.ItemType, x: i64, y: i64, ground: bool) *e.Item {
    const item = &e.alloc(e.Item, 1)[0];
    item.* = .{ .kind = kind, .x = x, .y = y, .ground = ground };
    return item;
}
fn dec1(numerator: usize, denominator: usize) []const u8 {
    if (denominator == 0) return "-";
    const rounded = (20 * numerator + denominator) / (2 * denominator);
    return e.fmt("{d}.{d}", .{ rounded / 10, rounded % 10 });
}
const Exploration = struct { seen: usize, total: usize };
fn exploration(level: *const gen.Level) Exploration {
    var result: Exploration = .{ .seen = 0, .total = 0 };
    for (level.terrain, level.memory) |terrain, memory| {
        if (terrain == ' ') continue;
        result.total += 1;
        result.seen += @intFromBool(memory != ' ');
    }
    return result;
}
fn readRows(io: std.Io, name: []const u8) ![]e.Strings {
    const source = e.lines(try std.Io.Dir.cwd().readFileAlloc(io, e.fmt("input/{s}", .{name}), e.allocator, .unlimited));
    const rows = e.alloc(e.Strings, source.len);
    for (source, rows) |line, *row| row.* = e.split(line, ' ');
    return rows;
}
fn readConfig(io: std.Io) !Config {
    const rows = try readRows(io, "config.txt");
    const xp = e.alloc(i64, rows[14].len - 1);
    for (rows[14][1..], xp) |token, *value| value.* = e.number(token);
    const checkpoints = e.alloc(usize, rows[15].len - 1);
    for (rows[15][1..], checkpoints) |token, *value| value.* = e.integer(token);
    return .{
        .generation_seed = e.number(rows[0][1]), .game_seed = e.number(rows[0][2]), .width = e.integer(rows[1][1]), .height = e.integer(rows[1][2]),
        .min_size = e.integer(rows[2][1]), .max_split = e.integer(rows[2][2]), .room_min = e.integer(rows[3][1]), .room_max = e.integer(rows[3][2]), .levels = e.integer(rows[4][1]),
        .monster_base = e.integer(rows[5][1]), .monster_step = e.integer(rows[5][2]), .item_base = e.integer(rows[6][1]), .item_step = e.integer(rows[6][2]),
        .sleep_chance = e.number(rows[7][1]), .wake_chance = e.number(rows[7][2]), .radius = e.number(rows[8][1]), .max_hp = e.number(rows[9][1]), .regen = e.integer(rows[9][2]),
        .hitdie = combat.Dice.parse(rows[10][1]), .food_start = e.number(rows[11][1]), .food_max = e.number(rows[11][2]), .food_hungry = e.number(rows[11][3]), .food_weak = e.number(rows[11][4]),
        .pack_limit = e.integer(rows[12][1]), .start = rows[13][1..], .xp = xp, .checkpoints = checkpoints,
    };
}
fn readGame(io: std.Io) !*Game {
    const config = try readConfig(io);
    const monster_rows = try readRows(io, "monsters.txt");
    const monster_types = e.alloc(e.MonsterType, monster_rows.len);
    for (monster_rows, monster_types) |row, *kind| kind.* = e.MonsterType.parse(row);
    const item_rows = try readRows(io, "items.txt");
    const item_types = e.alloc(e.ItemType, item_rows.len);
    for (item_rows, item_types) |row, *kind| kind.* = e.ItemType.parse(row);
    var commands: std.ArrayList(Command) = .empty;
    for (try readRows(io, "commands.txt")) |row| {
        const wait = e.eq(row[0], "wait");
        const count = if (wait) (if (row.len == 2) e.integer(row[1]) else 1) else (if (row.len == 3) e.integer(row[2]) else 1);
        const argument = if (!wait and row.len > 1) row[1] else "";
        for (0..count) |_| e.append(Command, &commands, .{ .name = row[0], .argument = argument });
    }
    const game = &e.alloc(Game, 1)[0];
    game.* = .{ .config = config, .monster_types = monster_types, .item_types = item_types, .commands = commands.items, .generation_rng = .{ .state = config.generation_seed }, .rng = .{ .state = config.game_seed }, .levels = e.alloc(gen.Level, config.levels) };
    game.buildLevels();
    game.initializePlayer();
    return game;
}
fn writeLines(io: std.Io, name: []const u8, source: e.Lines) !void {
    var text: e.Text = .{};
    for (source.data.items) |line| { text.write(line); text.write("\n"); }
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = e.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    e.allocator = arena.allocator();
    const game = try readGame(init.io);
    game.run();
    game.finalBlock();
    try writeLines(init.io, "messages.txt", game.messages);
    try writeLines(init.io, "maps.txt", game.maps);
    try writeLines(init.io, "stats.txt", game.statsLines());
}
