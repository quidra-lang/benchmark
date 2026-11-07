import os

from combat import Projectile, advance, damage_dealt, squared_distance
from enemies import Enemy, parse_waves
from grid_map import EXIT, GROUND, ROCK, WATER, cell_center, read_map
from pathing import DistanceField
from towers import TARGET_MODES, Tower, can_aim, parse_tower_types


INPUT_DIR = "input"
OUTPUT_DIR = "output"
ARROWS = "^>v<"
INCOME_FIELDS = ("bounty", "reward", "interest", "early", "refund")
WAVE_COLUMNS = (
    "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"
)


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as file:
        return file.read().splitlines()


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as file:
        file.write("".join(line + "\n" for line in lines))


def one_decimal(numerator, denominator):
    if denominator == 0:
        return "-"
    rounded = (20 * numerator + denominator) // (2 * denominator)
    return f"{rounded // 10}.{rounded % 10}"


def digit(count):
    if count == 0:
        return "."
    if count <= 9:
        return str(count)
    return "*"


def ruled(rows):
    lines = ["  " + "".join(str(x % 10) for x in range(len(rows[0])))]
    for y, row in enumerate(rows):
        lines.append(f"{y % 10} " + "".join(row))
    return lines


class Params:
    def __init__(self, lines):
        fields = [line.split() for line in lines]
        self.gold = int(fields[0][1])
        self.lives = int(fields[1][1])
        self.interest_rate = int(fields[2][1])
        self.interest_cap = int(fields[2][2])
        self.sell_rate = int(fields[3][1])
        self.start = int(fields[4][1])
        self.interval = int(fields[4][2])
        self.early = int(fields[5][1])
        self.snapshots = {int(value) for value in fields[6][1:]}


class Action:
    def __init__(self, line):
        tick, command, *arguments = line.split()
        self.tick = int(tick)
        self.command = command
        self.arguments = arguments


class WaveRecord:
    def __init__(self, number, plan, start):
        self.number = number
        self.plan = plan
        self.start = start
        self.end = 0
        self.status = ""
        self.released = [0] * len(plan.groups)
        self.spawned = 0
        self.peak = 0
        self.kills = 0
        self.leaks = 0
        self.lives_lost = 0
        self.bounty = 0
        self.reward = 0
        self.interest = 0
        self.gold = 0
        self.lives = 0
        self.tower_damage = {}

    def all_released(self):
        return all(
            released == group.count
            for released, group in zip(self.released, self.plan.groups)
        )

    def close(self, status, tick, gold, lives):
        self.status = status
        self.end = tick
        self.gold = gold
        self.lives = lives

    def csv_row(self, tower_count):
        values = [
            self.number, self.start, self.end, self.status, self.spawned, self.peak,
            self.kills, self.leaks, self.lives_lost, self.bounty, self.reward,
            self.interest, self.gold, self.lives,
        ]
        values.extend(self.tower_damage.get(number, 0) for number in range(1, tower_count + 1))
        return ",".join(str(value) for value in values)


class Game:
    def __init__(self, grid, tower_types, enemy_types, waves, params):
        self.grid = grid
        self.tower_types = {kind.name: kind for kind in tower_types}
        self.enemy_types = enemy_types
        self.waves = waves
        self.params = params
        self.exit_center = cell_center(grid.exit)
        self.tick = 0
        self.gold = params.gold
        self.lives = params.lives
        self.towers = []
        self.enemies = []
        self.all_enemies = []
        self.projectiles = []
        self.projectile_count = 0
        self.records = []
        self.active = None
        self.next_start = params.start
        self.outcome = None
        self.field = DistanceField(grid, set())
        self.kill_counts = [[0] * grid.width for _ in range(grid.height)]
        self.income = dict.fromkeys(INCOME_FIELDS, 0)
        self.spent = 0
        self.done = 0
        self.refused = 0
        self.events = []
        self.snapshots = []

    def record(self, *parts):
        self.events.append(" ".join(str(part) for part in (self.tick,) + parts))

    def run(self, actions):
        index = 0
        while True:
            self.tick += 1
            while index < len(actions) and actions[index].tick == self.tick:
                self.perform(actions[index])
                index += 1
            self.spawn_enemies()
            self.move_enemies()
            if self.outcome is not None:
                break
            self.fire_towers()
            self.move_projectiles()
            self.check_wave_end()
            if self.tick in self.params.snapshots:
                self.snapshots.extend(self.block("SNAPSHOT"))
            if self.outcome is not None:
                break
        self.snapshots.extend(self.final_block())

    def standing_towers(self):
        return [tower for tower in self.towers if tower.standing()]

    def tower_cells(self):
        return {tower.cell for tower in self.standing_towers()}

    def tower_at(self, cell):
        for tower in self.standing_towers():
            if tower.cell == cell:
                return tower
        return None

    def standing_tower(self, text):
        number = int(text)
        if 1 <= number <= len(self.towers) and self.towers[number - 1].standing():
            return self.towers[number - 1]
        return None

    def ground_enemies(self):
        return [enemy for enemy in self.enemies if not enemy.flying()]

    def perform(self, action):
        handlers = {
            "BUILD": self.build,
            "UPGRADE": self.upgrade,
            "SELL": self.sell,
            "TARGET": self.set_target,
            "CALL": self.call_wave,
        }
        if handlers[action.command](action.arguments):
            self.done += 1
        else:
            self.refused += 1

    def build_refusal(self, name, cell):
        if name not in self.tower_types:
            return "type"
        if not self.grid.inside(cell):
            return "bounds"
        if not self.grid.buildable(cell):
            return "terrain"
        if self.tower_at(cell) is not None:
            return "tower"
        if self.gold < self.tower_types[name].levels[0].cost:
            return "gold"
        walkers = self.ground_enemies()
        if any(enemy.cell == cell or enemy.next_cell == cell for enemy in walkers):
            return "enemy"
        trial = DistanceField(self.grid, self.tower_cells() | {cell})
        if any(trial.at(spawn) is None for spawn in self.grid.spawns):
            return "blocked"
        if any(trial.at(enemy.next_cell) is None for enemy in walkers):
            return "blocked"
        return None

    def build(self, arguments):
        name, x_text, y_text = arguments
        cell = (int(x_text), int(y_text))
        reason = self.build_refusal(name, cell)
        if reason is not None:
            self.record("BUILD_REFUSED", name, x_text, y_text, reason)
            return False
        kind = self.tower_types[name]
        cost = kind.levels[0].cost
        tower = Tower(len(self.towers) + 1, kind, cell, self.tick)
        self.towers.append(tower)
        self.gold -= cost
        self.spent += cost
        self.record("BUILD", f"T{tower.number}", name, *cell, "cost", cost, "gold", self.gold)
        self.update_field()
        return True

    def upgrade(self, arguments):
        tower = self.standing_tower(arguments[0])
        if tower is None:
            reason = "notower"
        elif tower.level == len(tower.kind.levels):
            reason = "maxlevel"
        elif self.gold < tower.kind.levels[tower.level].cost:
            reason = "gold"
        else:
            cost = tower.kind.levels[tower.level].cost
            self.gold -= cost
            self.spent += cost
            tower.level += 1
            tower.investment += cost
            self.record(
                "UPGRADE", f"T{tower.number}", "level", tower.level,
                "cost", cost, "gold", self.gold,
            )
            return True
        self.record("UPGRADE_REFUSED", "T" + arguments[0], reason)
        return False

    def sell(self, arguments):
        tower = self.standing_tower(arguments[0])
        if tower is None:
            self.record("SELL_REFUSED", "T" + arguments[0], "notower")
            return False
        rate = 100 if self.tick == tower.built else self.params.sell_rate
        refund = tower.investment * rate // 100
        tower.sold = self.tick
        self.gold += refund
        self.income["refund"] += refund
        self.record("SELL", f"T{tower.number}", "refund", refund, "gold", self.gold)
        self.update_field()
        return True

    def set_target(self, arguments):
        number_text, mode = arguments
        tower = self.standing_tower(number_text)
        if tower is None:
            reason = "notower"
        elif mode not in TARGET_MODES:
            reason = "mode"
        else:
            tower.mode = mode
            self.record("TARGET", f"T{tower.number}", mode)
            return True
        self.record("TARGET_REFUSED", "T" + number_text, reason)
        return False

    def call_wave(self, arguments):
        if self.active is not None:
            self.record("CALL_REFUSED", "active")
            return False
        bonus = (self.next_start - self.tick) * self.params.early
        self.gold += bonus
        self.income["early"] += bonus
        self.next_start = self.tick
        self.record("CALL", len(self.records) + 1, "bonus", bonus, "gold", self.gold)
        return True

    def update_field(self):
        before = self.field
        self.field = DistanceField(self.grid, self.tower_cells())
        for number, spawn in enumerate(self.grid.spawns, 1):
            old = before.at(spawn)
            new = self.field.at(spawn)
            if old != new:
                self.record("REPATH", number, old, new)

    def start_wave(self):
        plan = self.waves[len(self.records)]
        wave = WaveRecord(len(self.records) + 1, plan, self.tick)
        self.records.append(wave)
        self.active = wave
        self.next_start = None
        self.record("WAVE_START", wave.number, "enemies", plan.enemy_count())

    def add_enemy(self, enemy):
        self.enemies.append(enemy)
        self.all_enemies.append(enemy)
        self.active.spawned += 1
        enemy.kind.spawned += 1

    def remove_enemy(self, enemy):
        enemy.alive = False
        self.enemies.remove(enemy)

    def spawn_enemies(self):
        if self.tick == self.next_start:
            self.start_wave()
        wave = self.active
        if wave is None:
            return
        for index, group in enumerate(wave.plan.groups):
            released = wave.released[index]
            if released == group.count or group.spawn_tick(wave.start, released) != self.tick:
                continue
            wave.released[index] += 1
            spawn = self.grid.spawns[group.spawn - 1]
            enemy = Enemy(len(self.all_enemies) + 1, group.kind, group.multiplier)
            if enemy.flying():
                enemy.point = cell_center(spawn)
            else:
                enemy.cell = spawn
                enemy.next_cell = self.field.next_cell(spawn)
            self.add_enemy(enemy)
            self.record("SPAWN", f"E{enemy.number}", enemy.kind.name, group.spawn, "hp", enemy.hp)
        wave.peak = max(wave.peak, len(self.enemies))

    def move_enemies(self):
        for enemy in list(self.enemies):
            self.move_enemy(enemy)
            if self.outcome is not None:
                return

    def move_enemy(self, enemy):
        if enemy.burn.active():
            source = self.towers[enemy.burn.source - 1]
            damage = min(enemy.hp, enemy.burn.strength)
            enemy.hp -= damage
            self.credit(source, enemy, damage)
            enemy.burn.advance_time()
            if enemy.hp == 0:
                self.kill(enemy, source)
                return
        enemy.hp = min(enemy.hp + enemy.kind.regen, enemy.max_hp)
        speed = enemy.slowed_speed()
        if enemy.slow.active():
            enemy.slow.advance_time()
        if enemy.flying():
            enemy.point, arrived = advance(enemy.point, self.exit_center, speed)
        else:
            arrived = self.walk(enemy, speed)
        if arrived:
            self.leak(enemy)

    def walk(self, enemy, speed):
        if self.grid.is_water(enemy.occupied_cell()):
            speed //= 2
        while speed > 0:
            rest = 100 - enemy.progress
            if speed < rest:
                enemy.progress += speed
                speed = 0
            else:
                speed -= rest
                enemy.cell = enemy.next_cell
                enemy.progress = 0
                if enemy.cell == self.grid.exit:
                    return True
                enemy.next_cell = self.field.next_cell(enemy.cell)
        return False

    def leak(self, enemy):
        self.remove_enemy(enemy)
        lost = min(self.lives, enemy.kind.lives)
        self.lives -= lost
        wave = self.active
        wave.leaks += 1
        wave.lives_lost += lost
        enemy.kind.leaks += 1
        self.record("LEAK", f"E{enemy.number}", enemy.kind.name, "lives", self.lives)
        if self.lives == 0:
            self.record("DEFEAT")
            self.outcome = "defeat"
            wave.close("lost", self.tick, self.gold, self.lives)
            self.active = None

    def fire_towers(self):
        for tower in self.standing_towers():
            if self.tick < tower.ready:
                continue
            target = tower.select_target(self.enemies, self.field)
            if target is not None:
                self.fire(tower, target)

    def fire(self, tower, target):
        stats = tower.stats()
        self.projectile_count += 1
        self.projectiles.append(Projectile(
            self.projectile_count, tower.number, target.number, tower.center(), target.position(),
            tower.kind.targets, stats.power, stats.shot_speed, stats.splash,
            stats.slow_rate, stats.slow_time, stats.burn_amount, stats.burn_time,
        ))
        tower.shots += 1
        tower.ready = self.tick + stats.interval
        self.record("SHOT", f"T{tower.number}", f"E{target.number}")

    def move_projectiles(self):
        flying = []
        for projectile in self.projectiles:
            target = self.all_enemies[projectile.target - 1]
            if target.alive:
                projectile.aim = target.position()
            if projectile.fly():
                self.impact(projectile)
            else:
                flying.append(projectile)
        self.projectiles = flying

    def impact(self, projectile):
        tower = self.towers[projectile.tower - 1]
        target = self.all_enemies[projectile.target - 1]
        if projectile.splash == 0:
            victims = [target] if target.alive else []
        else:
            reach = projectile.splash * projectile.splash
            victims = [
                enemy for enemy in self.enemies
                if can_aim(projectile.targets, enemy)
                and squared_distance(enemy.position(), projectile.aim) <= reach
            ]
        if not victims:
            tower.fizzles += 1
        for enemy in victims:
            tower.hits += 1
            damage = damage_dealt(enemy.hp, projectile.power, enemy.kind.armor)
            enemy.hp -= damage
            self.credit(tower, enemy, damage)
            if enemy.hp == 0:
                self.kill(enemy, tower)
                continue
            if projectile.slow_rate > 0:
                enemy.slow.receive(projectile.slow_rate, projectile.slow_time)
            if projectile.burn_amount > 0:
                enemy.burn.receive(projectile.burn_amount, projectile.burn_time, tower.number)

    def credit(self, tower, enemy, damage):
        tower.damage += damage
        enemy.kind.damage += damage
        wave_damage = self.active.tower_damage
        wave_damage[tower.number] = wave_damage.get(tower.number, 0) + damage

    def kill(self, enemy, tower):
        self.remove_enemy(enemy)
        x, y = enemy.occupied_cell()
        self.kill_counts[y][x] += 1
        wave = self.active
        bounty = enemy.kind.bounty
        tower.kills += 1
        wave.kills += 1
        enemy.kind.kills += 1
        self.gold += bounty
        wave.bounty += bounty
        self.income["bounty"] += bounty
        self.record(
            "KILL", f"E{enemy.number}", enemy.kind.name, f"T{tower.number}",
            "bounty", bounty, "gold", self.gold,
        )
        for _ in range(enemy.kind.split_count):
            child = enemy.split(len(self.all_enemies) + 1)
            self.add_enemy(child)
            self.record(
                "SPAWN", f"E{child.number}", child.kind.name, f"E{enemy.number}", "hp", child.hp
            )

    def check_wave_end(self):
        wave = self.active
        if wave is None or self.enemies or not wave.all_released():
            return
        reward = wave.plan.reward
        self.gold += reward
        interest = min(self.params.interest_cap, self.gold * self.params.interest_rate // 100)
        self.gold += interest
        wave.reward = reward
        wave.interest = interest
        self.income["reward"] += reward
        self.income["interest"] += interest
        self.active = None
        self.record(
            "WAVE_END", wave.number, "reward", reward, "interest", interest, "gold", self.gold
        )
        if wave.number == len(self.waves):
            self.record("VICTORY")
            self.outcome = "victory"
        else:
            self.next_start = self.tick + self.params.interval
        wave.close("cleared", self.tick, self.gold, self.lives)

    def map_picture(self):
        rows = [list(row) for row in self.grid.rows]
        for spawn in self.grid.spawns:
            for x, y in self.field.path(spawn):
                if self.grid.terrain((x, y)) in (GROUND, WATER):
                    rows[y][x] = "+"
        for tower in self.standing_towers():
            x, y = tower.cell
            rows[y][x] = tower.kind.symbol
        occupants = {}
        for enemy in self.enemies:
            occupants.setdefault(enemy.occupied_cell(), []).append(enemy)
        for (x, y), group in occupants.items():
            rows[y][x] = group[0].kind.symbol if len(group) == 1 else "*"
        return rows

    def flow_picture(self):
        rows = []
        for y in range(self.grid.height):
            row = []
            for x in range(self.grid.width):
                cell = (x, y)
                terrain = self.grid.terrain(cell)
                tower = self.tower_at(cell)
                if terrain == ROCK or terrain == EXIT:
                    row.append(terrain)
                elif tower is not None:
                    row.append(tower.kind.symbol)
                elif self.field.at(cell) is None:
                    row.append("?")
                else:
                    row.append(ARROWS[self.field.direction(cell)])
            rows.append(row)
        return rows

    def coverage_picture(self):
        towers = self.standing_towers()
        rows = []
        for y in range(self.grid.height):
            row = []
            for x in range(self.grid.width):
                cell = (x, y)
                tower = self.tower_at(cell)
                if self.grid.is_rock(cell):
                    row.append(ROCK)
                elif tower is not None:
                    row.append(tower.kind.symbol)
                else:
                    center = cell_center(cell)
                    row.append(digit(sum(1 for other in towers if other.in_range(center))))
            rows.append(row)
        return rows

    def kills_picture(self):
        rows = []
        for y in range(self.grid.height):
            row = []
            for x in range(self.grid.width):
                count = self.kill_counts[y][x]
                if count > 0:
                    row.append(digit(count))
                elif self.grid.is_rock((x, y)):
                    row.append(ROCK)
                else:
                    row.append(".")
            rows.append(row)
        return rows

    def block(self, label):
        waiting = self.active is None and self.outcome is None
        next_text = self.next_start if waiting else "-"
        lines = [
            f"{label} {self.tick} wave {len(self.records)} next {next_text} "
            f"gold {self.gold} lives {self.lives}"
        ]
        lines.extend(ruled(self.map_picture()))
        for number, spawn in enumerate(self.grid.spawns, 1):
            lines.append(f"PATH {number} length {self.field.at(spawn)}")
        for tower in self.standing_towers():
            x, y = tower.cell
            lines.append(
                f"T{tower.number} {tower.kind.name} {x} {y} level {tower.level} "
                f"mode {tower.mode} ready {tower.ready}"
            )
        for enemy in self.enemies:
            x, y = enemy.position()
            lines.append(
                f"E{enemy.number} {enemy.kind.name} {x} {y} hp {enemy.hp}/{enemy.max_hp} "
                f"slow {enemy.slow.strength} {enemy.slow.remaining} "
                f"burn {enemy.burn.strength} {enemy.burn.remaining}"
            )
        for projectile in self.projectiles:
            x, y = projectile.position
            lines.append(f"P{projectile.number} T{projectile.tower} E{projectile.target} {x} {y}")
        return lines

    def final_block(self):
        lines = self.block("FINAL")
        lines.append("FLOW")
        lines.extend(ruled(self.flow_picture()))
        lines.append("COVERAGE")
        lines.extend(ruled(self.coverage_picture()))
        lines.append("KILLS")
        lines.extend(ruled(self.kills_picture()))
        return lines

    def wave_lines(self):
        header = WAVE_COLUMNS + "".join(f",T{tower.number}" for tower in self.towers)
        return [header] + [wave.csv_row(len(self.towers)) for wave in self.records]

    def mvp_line(self):
        best = None
        for tower in self.towers:
            if best is None or tower.damage > best.damage:
                best = tower
        if best is None:
            return "mvp -"
        return f"mvp T{best.number} damage {best.damage}"

    def tower_line(self, tower, total_damage):
        x, y = tower.cell
        state = "active" if tower.standing() else f"sold {tower.sold}"
        return (
            f"TOWER T{tower.number} {tower.kind.name} {x} {y} level {tower.level} "
            f"mode {tower.mode} {state} shots {tower.shots} hits {tower.hits} "
            f"fizzles {tower.fizzles} kills {tower.kills} damage {tower.damage} "
            f"per_shot {one_decimal(tower.damage, tower.shots)} "
            f"share {one_decimal(100 * tower.damage, total_damage)} invested {tower.investment}"
        )

    def summary_lines(self, action_count):
        cleared = [wave for wave in self.records if wave.status == "cleared"]
        perfect = sum(1 for wave in cleared if wave.leaks == 0)
        kinds = list(self.enemy_types.values())
        spawned = sum(kind.spawned for kind in kinds)
        killed = sum(kind.kills for kind in kinds)
        leaked = sum(kind.leaks for kind in kinds)
        total_damage = sum(tower.damage for tower in self.towers)
        unused = action_count - self.done - self.refused
        score = 10 * killed + 100 * self.lives + 50 * perfect + self.gold
        lines = [
            f"outcome {self.outcome}",
            f"ticks {self.tick}",
            f"waves {len(cleared)}/{len(self.waves)} perfect {perfect}",
            f"lives {self.lives}/{self.params.lives}",
            f"gold {self.gold}",
            f"enemies spawned {spawned} killed {killed} leaked {leaked}",
            "income " + " ".join(f"{field} {self.income[field]}" for field in INCOME_FIELDS),
            f"spent {self.spent}",
            f"damage {total_damage}",
            f"actions total {action_count} done {self.done} "
            f"refused {self.refused} unused {unused}",
            f"score {score}",
            self.mvp_line(),
        ]
        for kind in kinds:
            lines.append(
                f"ENEMY {kind.name} spawned {kind.spawned} killed {kind.kills} "
                f"leaked {kind.leaks} damage {kind.damage}"
            )
        for tower in self.towers:
            lines.append(self.tower_line(tower, total_damage))
        return lines


def main():
    grid = read_map(os.path.join(INPUT_DIR, "map.txt"))
    tower_types = parse_tower_types(read_lines("towers.txt"))
    enemy_types, waves = parse_waves(read_lines("waves.txt"))
    actions = [Action(line) for line in read_lines("actions.txt")]
    params = Params(read_lines("params.txt"))
    game = Game(grid, tower_types, enemy_types, waves, params)
    game.run(actions)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("events.txt", game.events)
    write_lines("waves.csv", game.wave_lines())
    write_lines("snapshots.txt", game.snapshots)
    write_lines("summary.txt", game.summary_lines(len(actions)))


if __name__ == "__main__":
    main()
