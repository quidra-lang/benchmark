import os

from combat import CRITICAL, MISS, Dice, parse_dice, resolve_attack
from dungeon_gen import DOWN_STAIRS, FLOOR, ROCK, UNSEEN, LevelGenerator
from entities import Item, Monster, MonsterType, amulet_type, parse_item_type
from fov import DIRECTION_NAMES, DIRECTIONS, can_move, distances, field_of_view, passable
from minstd import Minstd


INPUT_DIR = "input"
OUTPUT_DIR = "output"
BASE_DEFENSE = 10
UNARMED_DAMAGE = Dice(1, 2)
HUNGER_PENALTY = 2
POISON_BITE_TURNS = 5
COMMAND_CLASSES = {
    "quaff": "potion",
    "read": "scroll",
    "wield": "weapon",
    "wear": "armor",
    "eat": "food",
}
HUNGER_MESSAGES = {
    "hungry": "You are getting hungry.",
    "weak": "You feel weak from hunger.",
    "starving": "You are starving.",
}
USAGE_FIELDS = ("picked", "quaffed", "read", "eaten", "wielded", "worn")


def read_rows(name):
    with open(os.path.join(INPUT_DIR, name)) as handle:
        return [line.split(" ") for line in handle.read().splitlines()]


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def integers(tokens):
    return [int(token) for token in tokens]


def dec_1(a, b):
    if b == 0:
        return "-"
    z = (20 * a + b) // (2 * b)
    return f"{z // 10}.{z % 10}"


def exploration(level):
    explored = 0
    total = 0
    for y in range(level.height):
        for x in range(level.width):
            if level.terrain[y][x] != ROCK:
                total += 1
                if level.memory[y][x] != UNSEEN:
                    explored += 1
    return explored, total


class Config:
    def __init__(self, rows):
        values = {tokens[0]: tokens[1:] for tokens in rows}
        self.generation_seed, self.game_seed = integers(values["seed"])
        self.width, self.height = integers(values["map"])
        self.min_size, self.max_split = integers(values["bsp"])
        self.room_min, self.room_max = integers(values["room"])
        self.levels = int(values["levels"][0])
        self.monster_base, self.monster_step = integers(values["monsters"])
        self.item_base, self.item_step = integers(values["items"])
        self.sleep_chance, self.wake_chance = integers(values["sleep"])
        self.fov_radius = int(values["fov"][0])
        self.max_hp, self.regen_interval = integers(values["player"])
        self.hit_die = parse_dice(values["hitdie"][0])
        self.food_start, self.food_max, self.food_hungry, self.food_weak = integers(values["food"])
        self.pack_limit = int(values["pack"][0])
        self.start_items = values["start"]
        self.xp_levels = integers(values["xp"])
        self.checkpoints = set(integers(values["checkpoints"]))


def expand_commands(rows):
    commands = []
    for tokens in rows:
        name = tokens[0]
        if name == "wait":
            argument = None
            count = int(tokens[1]) if len(tokens) == 2 else 1
        else:
            argument = tokens[1] if len(tokens) > 1 else None
            count = int(tokens[2]) if len(tokens) == 3 else 1
        commands.extend([(name, argument)] * count)
    return commands


class Player:
    def __init__(self, config, x, y):
        self.x = x
        self.y = y
        self.depth = 1
        self.hp = config.max_hp
        self.max_hp = config.max_hp
        self.level = 1
        self.xp = 0
        self.gold = 0
        self.satiation = config.food_start
        self.poison = 0
        self.pack = []
        self.weapon = None
        self.armor = None

    def defense(self):
        if self.armor is None:
            return BASE_DEFENSE
        return BASE_DEFENSE + self.armor.kind.armor + self.armor.bonus


class AttackStats:
    def __init__(self):
        self.count = 0
        self.hits = 0
        self.criticals = 0
        self.damage = 0

    def record(self, outcome, damage):
        self.count += 1
        if outcome != MISS:
            self.hits += 1
            self.damage += damage
        if outcome == CRITICAL:
            self.criticals += 1

    def line(self, label):
        accuracy = dec_1(100 * self.hits, self.count)
        return (
            f"{label} {self.count} hits {self.hits} criticals {self.criticals} "
            f"damage {self.damage} accuracy {accuracy}"
        )


class Game:
    def __init__(self, config, monster_types, item_types, commands):
        self.config = config
        self.monster_types = monster_types
        self.item_types = item_types
        self.commands = commands
        self.generation_rng = Minstd(config.generation_seed)
        self.rng = Minstd(config.game_seed)
        self.levels = []
        self.build_levels()
        start_x, start_y = self.levels[0].arrival
        self.player = Player(config, start_x, start_y)
        self.give_start_items()
        self.turn = 1
        self.messages = []
        self.map_lines = []
        self.visible = None
        self.distance = None
        self.result = None
        self.cause = None
        self.succeeded = 0
        self.failed = 0
        self.unused = 0
        self.moves = 0
        self.player_attacks = AttackStats()
        self.monster_attacks = AttackStats()
        self.poison_damage = 0
        self.starvation_damage = 0
        self.usage = dict.fromkeys(USAGE_FIELDS, 0)
        self.kills = {kind.name: 0 for kind in monster_types}

    def build_levels(self):
        config = self.config
        generator = LevelGenerator(
            self.generation_rng, config.min_size, config.max_split,
            config.room_min, config.room_max,
        )
        for depth in range(1, config.levels + 1):
            level = generator.generate(depth, config.width, config.height)
            target_x, target_y = level.target
            if depth < config.levels:
                level.terrain[target_y][target_x] = DOWN_STAIRS
            else:
                level.items.append(Item(amulet_type(), target_x, target_y))
            self.place_monsters(level)
            self.place_items(level)
            self.levels.append(level)

    def place_monsters(self, level):
        rng = self.generation_rng
        depth = level.depth
        count = self.config.monster_base + self.config.monster_step * (depth - 1)
        candidates = [
            kind for kind in self.monster_types
            if kind.min_depth <= depth <= kind.max_depth
        ]
        weights = [kind.weight for kind in candidates]
        for number in range(1, count + 1):
            kind = candidates[rng.select(weights)]
            while True:
                room, x, y = level.draw_room_cell(rng)
                if (room != level.arrival_room and level.terrain[y][x] == FLOOR
                        and level.monster_at(x, y) is None):
                    break
            hp = kind.hp.roll(rng)
            asleep = rng.draw() % 100 < self.config.sleep_chance
            level.monsters.append(Monster(number, kind, x, y, hp, asleep))
        level.monsters_created = count

    def place_items(self, level):
        rng = self.generation_rng
        depth = level.depth
        count = self.config.item_base + self.config.item_step * (depth - 1)
        candidates = [
            kind for kind in self.item_types
            if kind.min_depth <= depth <= kind.max_depth
        ]
        weights = [kind.weight for kind in candidates]
        for _ in range(count):
            kind = candidates[rng.select(weights)]
            while True:
                _, x, y = level.draw_room_cell(rng)
                if level.terrain[y][x] == FLOOR and level.item_at(x, y) is None:
                    break
            amount = kind.dice.roll(rng) if kind.category == "gold" else 0
            level.items.append(Item(kind, x, y, amount))
        level.items_placed = len(level.items)

    def give_start_items(self):
        types_by_name = {kind.name: kind for kind in self.item_types}
        player = self.player
        for name in self.config.start_items:
            item = Item(types_by_name[name], player.x, player.y)
            player.pack.append(item)
            if item.kind.category == "weapon" and player.weapon is None:
                player.weapon = item
            if item.kind.category == "armor" and player.armor is None:
                player.armor = item

    def current_level(self):
        return self.levels[self.player.depth - 1]

    def say(self, text):
        self.messages.append((self.turn, text))

    def hunger_state(self):
        satiation = self.player.satiation
        if satiation > self.config.food_hungry:
            return "normal"
        if satiation > self.config.food_weak:
            return "hungry"
        if satiation > 0:
            return "weak"
        return "starving"

    def finish(self, result, cause):
        self.result = result
        self.cause = cause

    def die(self, cause):
        self.say("You die.")
        self.finish("died", cause)

    def update_view(self):
        level = self.current_level()
        player = self.player
        self.visible = field_of_view(level, player.x, player.y, self.config.fov_radius)
        for y in range(level.height):
            for x in range(level.width):
                if self.visible[y][x]:
                    item = level.item_at(x, y)
                    level.memory[y][x] = level.terrain[y][x] if item is None else item.symbol()
        for monster in level.monsters:
            seen = self.visible[monster.y][monster.x]
            if seen and not monster.was_visible:
                self.say(f"You see the {monster.kind.name}.")
            monster.was_visible = seen

    def run(self):
        self.update_view()
        for command in self.commands:
            if self.result is not None:
                self.unused += 1
            elif not self.execute(command):
                self.failed += 1
            else:
                self.succeeded += 1
                if self.result is None:
                    self.advance_turn()
        if self.result is None:
            self.finish("alive", "commands_exhausted")

    def advance_turn(self):
        self.update_view()
        self.monsters_act()
        if self.result is not None:
            return
        self.end_turn()
        if self.result is not None:
            return
        if self.turn in self.config.checkpoints:
            self.write_checkpoint()
        self.turn += 1

    def execute(self, command):
        name, argument = command
        if name == "move":
            dx, dy = DIRECTIONS[DIRECTION_NAMES.index(argument)]
            return self.move(dx, dy)
        if name == "wait":
            return True
        if name == "pickup":
            return self.pickup()
        if name == "descend":
            return self.descend()
        return self.use_item(name, int(argument))

    def move(self, dx, dy):
        level = self.current_level()
        player = self.player
        x = player.x + dx
        y = player.y + dy
        if not passable(level, x, y):
            self.say("You bump into a wall.")
            return False
        if not can_move(level, player.x, player.y, dx, dy):
            self.say("You cannot move diagonally through a door.")
            return False
        monster = level.monster_at(x, y)
        if monster is not None:
            self.player_attack(level, monster)
            return True
        player.x = x
        player.y = y
        self.moves += 1
        item = level.item_at(x, y)
        if item is not None:
            self.say(f"You see {item.reference_name()} here.")
        elif level.terrain[y][x] == DOWN_STAIRS:
            self.say("There is a staircase down here.")
        return True

    def pickup(self):
        level = self.current_level()
        player = self.player
        item = level.item_at(player.x, player.y)
        if item is None:
            self.say("There is nothing here.")
            return False
        category = item.kind.category
        if category == "gold":
            player.gold += item.amount
            self.say(f"You pick up {item.display_name()}.")
        elif category == "amulet":
            self.say("You pick up the amulet.")
            self.say("You win!")
            self.finish("won", "amulet")
        elif len(player.pack) >= self.config.pack_limit:
            self.say("Your pack is full.")
            return False
        else:
            player.pack.append(item)
            self.say(f"You pick up the {item.display_name()} ({len(player.pack)}).")
        level.items.remove(item)
        level.picked += 1
        self.usage["picked"] += 1
        return True

    def descend(self):
        player = self.player
        if self.current_level().terrain[player.y][player.x] != DOWN_STAIRS:
            self.say("There are no stairs here.")
            return False
        player.depth += 1
        player.x, player.y = self.current_level().arrival
        self.say(f"You descend to depth {player.depth}.")
        return True

    def use_item(self, name, number):
        pack = self.player.pack
        if number > len(pack):
            self.say("You do not have that item.")
            return False
        item = pack[number - 1]
        if item.kind.category != COMMAND_CLASSES[name]:
            self.say(f"You cannot {name} that.")
            return False
        if name == "quaff":
            return self.quaff(item)
        if name == "read":
            return self.read(item)
        if name == "wield":
            return self.wield(item)
        if name == "wear":
            return self.wear(item)
        return self.eat(item)

    def quaff(self, item):
        player = self.player
        player.pack.remove(item)
        self.usage["quaffed"] += 1
        self.say(f"You quaff the {item.display_name()}.")
        effect = item.kind.effect
        if effect == "heal":
            player.hp += item.kind.dice.roll(self.rng)
            if player.hp > player.max_hp:
                player.max_hp += 1
                player.hp = player.max_hp
            player.poison = 0
            self.say("You feel better.")
        elif effect == "poison":
            player.poison += item.kind.poison_turns
            self.say("You feel very sick.")
        elif effect == "level":
            self.say("You feel more experienced.")
            thresholds = self.config.xp_levels
            if player.level <= len(thresholds):
                self.gain_xp(thresholds[player.level - 1] - player.xp)
        return True

    def read(self, item):
        level = self.current_level()
        player = self.player
        player.pack.remove(item)
        self.usage["read"] += 1
        self.say(f"You read the {item.display_name()}.")
        effect = item.kind.effect
        if effect == "mapping":
            for y in range(level.height):
                for x in range(level.width):
                    if level.terrain[y][x] != ROCK and level.memory[y][x] == UNSEEN:
                        level.memory[y][x] = level.terrain[y][x]
            self.say("A map forms in your mind.")
        elif effect == "teleport":
            while True:
                _, x, y = level.draw_room_cell(self.rng)
                if (x, y) != (player.x, player.y) and level.monster_at(x, y) is None:
                    break
            player.x = x
            player.y = y
            self.say("You are teleported.")
        elif effect == "enchant_weapon":
            if player.weapon is None:
                self.say("Your hands twitch.")
            else:
                self.say(f"Your {player.weapon.display_name()} glows blue.")
                player.weapon.bonus += 1
        elif effect == "enchant_armor":
            if player.armor is None:
                self.say("Your skin tingles.")
            else:
                self.say(f"Your {player.armor.display_name()} glows silver.")
                player.armor.bonus += 1
        return True

    def wield(self, item):
        if item is self.player.weapon:
            self.say("You are already wielding that.")
            return False
        self.player.weapon = item
        self.usage["wielded"] += 1
        self.say(f"You are now wielding the {item.display_name()}.")
        return True

    def wear(self, item):
        if item is self.player.armor:
            self.say("You are already wearing that.")
            return False
        self.player.armor = item
        self.usage["worn"] += 1
        self.say(f"You are now wearing the {item.display_name()}.")
        return True

    def eat(self, item):
        player = self.player
        player.pack.remove(item)
        self.usage["eaten"] += 1
        player.satiation = min(player.satiation + item.kind.nutrition, self.config.food_max)
        self.say(f"You eat the {item.display_name()}.")
        return True

    def player_attack(self, level, monster):
        player = self.player
        weapon = player.weapon
        monster.asleep = False
        if weapon is None:
            to_hit = player.level
            dice = UNARMED_DAMAGE
            bonus = 0
        else:
            to_hit = player.level + weapon.kind.to_hit + weapon.bonus
            dice = weapon.kind.dice
            bonus = weapon.bonus
        if self.hunger_state() in ("weak", "starving"):
            to_hit -= HUNGER_PENALTY
        name = monster.kind.name
        outcome, damage = resolve_attack(self.rng, to_hit, monster.kind.defense, dice, bonus)
        self.player_attacks.record(outcome, damage)
        if outcome == MISS:
            self.say(f"You miss the {name}.")
            return
        if outcome == CRITICAL:
            self.say(f"You hit the {name} hard for {damage}.")
        else:
            self.say(f"You hit the {name} for {damage}.")
        monster.hp -= damage
        if monster.hp <= 0:
            self.say(f"You kill the {name}.")
            level.monsters.remove(monster)
            level.kills += 1
            self.kills[name] += 1
            self.gain_xp(monster.kind.xp)

    def gain_xp(self, amount):
        player = self.player
        thresholds = self.config.xp_levels
        player.xp += amount
        while player.level <= len(thresholds) and player.xp >= thresholds[player.level - 1]:
            player.level += 1
            gained = self.config.hit_die.roll(self.rng)
            player.max_hp += gained
            player.hp += gained
            self.say(f"Welcome to level {player.level}.")

    def monster_attack(self, monster):
        player = self.player
        kind = monster.kind
        outcome, damage = resolve_attack(self.rng, kind.to_hit, player.defense(), kind.damage, 0)
        self.monster_attacks.record(outcome, damage)
        if outcome == MISS:
            self.say(f"The {kind.name} misses you.")
            return
        if outcome == CRITICAL:
            self.say(f"The {kind.name} hits you hard for {damage}.")
        else:
            self.say(f"The {kind.name} hits you for {damage}.")
        player.hp -= damage
        if player.hp <= 0:
            self.die("killed_by " + kind.name)
        elif kind.poisonous:
            player.poison += POISON_BITE_TURNS
            self.say("You are poisoned.")

    def monsters_act(self):
        level = self.current_level()
        self.distance = None
        for monster in level.monsters:
            monster.energy += monster.kind.speed
            while monster.energy >= 2:
                monster.energy -= 2
                self.monster_action(level, monster)
                if self.result is not None:
                    return

    def monster_action(self, level, monster):
        sees_player = self.visible[monster.y][monster.x]
        if monster.asleep:
            if sees_player and self.rng.draw() % 100 < self.config.wake_chance:
                monster.asleep = False
                self.say(f"The {monster.kind.name} wakes up.")
        elif monster.kind.stationary:
            if self.can_attack(level, monster):
                self.monster_attack(monster)
        elif monster.kind.erratic and self.rng.draw() % 2 == 0:
            self.wander(level, monster)
        elif sees_player:
            self.chase(level, monster)
        else:
            self.wander(level, monster)

    def can_attack(self, level, monster):
        dx = self.player.x - monster.x
        dy = self.player.y - monster.y
        if max(abs(dx), abs(dy)) != 1:
            return False
        return can_move(level, monster.x, monster.y, dx, dy)

    def wander(self, level, monster):
        dx, dy = DIRECTIONS[self.rng.draw() % 8]
        if not can_move(level, monster.x, monster.y, dx, dy):
            return
        x = monster.x + dx
        y = monster.y + dy
        if (x, y) == (self.player.x, self.player.y):
            self.monster_attack(monster)
        elif level.monster_at(x, y) is None:
            monster.x = x
            monster.y = y

    def chase(self, level, monster):
        if self.can_attack(level, monster):
            self.monster_attack(monster)
            return
        if self.distance is None:
            self.distance = distances(level, self.player.x, self.player.y)
        here = self.distance[monster.y][monster.x]
        best = None
        best_distance = 0
        for dx, dy in DIRECTIONS:
            if not can_move(level, monster.x, monster.y, dx, dy):
                continue
            x = monster.x + dx
            y = monster.y + dy
            distance = self.distance[y][x]
            if distance is None or (here is not None and distance >= here):
                continue
            if level.monster_at(x, y) is not None or (x, y) == (self.player.x, self.player.y):
                continue
            if best is None or distance < best_distance:
                best = x, y
                best_distance = distance
        if best is not None:
            monster.x, monster.y = best

    def end_turn(self):
        level = self.current_level()
        player = self.player
        for monster in level.monsters:
            if monster.kind.regenerates and monster.hp < monster.max_hp:
                monster.hp += 1
        if player.poison > 0:
            player.hp -= 1
            self.poison_damage += 1
            if player.hp <= 0:
                self.die("poison")
                return
            player.poison -= 1
            if player.poison == 0:
                self.say("You feel less sick.")
        if player.satiation == 0:
            player.hp -= 1
            self.starvation_damage += 1
            if player.hp <= 0:
                self.die("starvation")
                return
        else:
            before = self.hunger_state()
            player.satiation -= 1
            after = self.hunger_state()
            if after != before:
                self.say(HUNGER_MESSAGES[after])
        if (self.turn % self.config.regen_interval == 0 and player.poison == 0
                and player.satiation > 0 and player.hp < player.max_hp):
            player.hp += 1

    def view_symbol(self, level, x, y):
        if (x, y) == (self.player.x, self.player.y):
            return "@"
        monster = level.monster_at(x, y)
        if monster is not None:
            return monster.kind.symbol
        item = level.item_at(x, y)
        if item is not None:
            return item.symbol()
        return level.terrain[y][x]

    def map_rows(self, level, current):
        border = "+" + "-" * level.width + "+"
        rows = [border]
        for y in range(level.height):
            symbols = []
            for x in range(level.width):
                if current and self.visible[y][x]:
                    symbols.append(self.view_symbol(level, x, y))
                else:
                    symbols.append(level.memory[y][x])
            rows.append("|" + "".join(symbols) + "|")
        rows.append(border)
        return rows

    def status_line(self):
        player = self.player
        return (
            f"STATUS hp {player.hp}/{player.max_hp} level {player.level} xp {player.xp} "
            f"defense {player.defense()} gold {player.gold} "
            f"food {player.satiation} {self.hunger_state()} poison {player.poison}"
        )

    def write_checkpoint(self):
        self.map_lines.append(f"CHECKPOINT turn {self.turn} depth {self.player.depth}")
        self.map_lines.extend(self.map_rows(self.current_level(), True))
        self.map_lines.append(self.status_line())

    def final_block(self):
        depth = self.player.depth
        lines = [f"FINAL turn {self.succeeded} depth {depth}"]
        for level in self.levels[:depth]:
            explored, total = exploration(level)
            lines.append(f"LEVEL {level.depth} explored {explored}/{total}")
            lines.extend(self.map_rows(level, level.depth == depth))
        lines.append(self.status_line())
        return lines

    def item_label(self, item):
        return "-" if item is None else item.display_name()

    def stats_lines(self):
        player = self.player
        lines = [
            f"result {self.result}",
            f"cause {self.cause}",
            f"turns {self.succeeded}",
            f"depth {player.depth}",
            f"level {player.level}",
            f"xp {player.xp}",
            f"hp {player.hp}/{player.max_hp}",
            f"defense {player.defense()}",
            f"gold {player.gold}",
            f"food {player.satiation} {self.hunger_state()}",
            f"poison {player.poison}",
            f"weapon {self.item_label(player.weapon)}",
            f"armor {self.item_label(player.armor)}",
            f"commands {len(self.commands)} executed {self.succeeded} "
            f"failed {self.failed} unused {self.unused}",
            f"moves {self.moves}",
            self.player_attacks.line("player_attacks"),
            self.monster_attacks.line("monster_attacks"),
            f"poison_damage {self.poison_damage} starvation_damage {self.starvation_damage}",
            " ".join(f"{field} {self.usage[field]}" for field in USAGE_FIELDS),
            f"kills {sum(self.kills.values())}",
        ]
        for kind in self.monster_types:
            if self.kills[kind.name] > 0:
                lines.append(f"KILL {kind.name} {self.kills[kind.name]}")
        for level in self.levels:
            explored, total = exploration(level)
            lines.append(
                f"LEVEL {level.depth} rooms {len(level.rooms)} "
                f"explored {explored}/{total} {dec_1(100 * explored, total)} "
                f"monsters {level.kills}/{level.monsters_created} "
                f"items {level.picked}/{level.items_placed}"
            )
        for number, item in enumerate(player.pack, 1):
            line = f"INVENTORY {number} {item.display_name()}"
            if item is player.weapon:
                line += " (wielded)"
            elif item is player.armor:
                line += " (worn)"
            lines.append(line)
        return lines


def main():
    config = Config(read_rows("config.txt"))
    monster_types = [MonsterType(tokens) for tokens in read_rows("monsters.txt")]
    item_types = [parse_item_type(tokens) for tokens in read_rows("items.txt")]
    commands = expand_commands(read_rows("commands.txt"))
    game = Game(config, monster_types, item_types, commands)
    game.run()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("messages.txt", [f"{turn:04d} {text}" for turn, text in game.messages])
    write_lines("maps.txt", game.map_lines + game.final_block())
    write_lines("stats.txt", game.stats_lines())


if __name__ == "__main__":
    main()
