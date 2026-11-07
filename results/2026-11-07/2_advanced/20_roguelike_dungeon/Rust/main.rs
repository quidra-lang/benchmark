mod minstd;
mod combat;
mod entities;
mod dungeon_gen;
mod fov;

use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use combat::{AttackOutcome, Dice, resolve_attack};
use dungeon_gen::{Level, LevelGenerator};
use entities::{Item, ItemClass, ItemType, Monster, MonsterType, PotionEffect, ScrollEffect};
use fov::{DIRECTION_NAMES, DIRECTIONS, can_move, distances, field_of_view, passable};
use minstd::Minstd;

struct Config {
    generation_seed: i64,
    game_seed: i64,
    width: usize,
    height: usize,
    min_size: usize,
    max_split: usize,
    room_min: usize,
    room_max: usize,
    levels: usize,
    monster_base: usize,
    monster_step: usize,
    item_base: usize,
    item_step: usize,
    sleep_chance: i64,
    wake_chance: i64,
    radius: i32,
    max_hp: i64,
    regen_interval: usize,
    hit_die: Dice,
    food_start: i64,
    food_max: i64,
    food_hungry: i64,
    food_weak: i64,
    pack_limit: usize,
    start_items: Vec<String>,
    xp_levels: Vec<i64>,
    checkpoints: BTreeSet<usize>,
}
fn read_rows(name: &str) -> io::Result<Vec<Vec<String>>> {
    Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(|line| line.split(' ').map(str::to_owned).collect()).collect())
}
impl Config {
    fn read(rows: &[Vec<String>]) -> Self {
        let entries: BTreeMap<_, _> = rows.iter().map(|row| (row[0].as_str(), &row[1..])).collect();
        let integer = |key: &str, position: usize| entries[key][position].parse::<usize>().unwrap();
        Self { generation_seed: integer("seed", 0) as i64, game_seed: integer("seed", 1) as i64,
            width: integer("map", 0), height: integer("map", 1), min_size: integer("bsp", 0), max_split: integer("bsp", 1),
            room_min: integer("room", 0), room_max: integer("room", 1), levels: integer("levels", 0),
            monster_base: integer("monsters", 0), monster_step: integer("monsters", 1), item_base: integer("items", 0), item_step: integer("items", 1),
            sleep_chance: integer("sleep", 0) as i64, wake_chance: integer("sleep", 1) as i64, radius: integer("fov", 0) as i32,
            max_hp: integer("player", 0) as i64, regen_interval: integer("player", 1), hit_die: Dice::parse(&entries["hitdie"][0]),
            food_start: integer("food", 0) as i64, food_max: integer("food", 1) as i64, food_hungry: integer("food", 2) as i64,
            food_weak: integer("food", 3) as i64, pack_limit: integer("pack", 0), start_items: entries["start"].to_vec(),
            xp_levels: entries["xp"].iter().map(|value| value.parse().unwrap()).collect(),
            checkpoints: entries["checkpoints"].iter().map(|value| value.parse().unwrap()).collect() }
    }
}
#[derive(Clone, Copy)]
enum UseAction { Quaff, Read, Wield, Wear, Eat }
impl UseAction {
    fn name(self) -> &'static str { match self { Self::Quaff => "quaff", Self::Read => "read", Self::Wield => "wield", Self::Wear => "wear", Self::Eat => "eat" } }
    fn accepts(self, class: ItemClass) -> bool {
        matches!((self, class), (Self::Quaff, ItemClass::Potion(_)) | (Self::Read, ItemClass::Scroll(_)) |
            (Self::Wield, ItemClass::Weapon { .. }) | (Self::Wear, ItemClass::Armor(_)) | (Self::Eat, ItemClass::Food(_)))
    }
}
#[derive(Clone, Copy)]
enum Command { Move(i32, i32), Wait, Pickup, Descend, Use(UseAction, usize) }
fn expand_commands(rows: &[Vec<String>]) -> Vec<Command> {
    let mut commands = Vec::new();
    for words in rows {
        let (command, count) = match words[0].as_str() {
            "move" => {
                let number = DIRECTION_NAMES.iter().position(|&name| name == words[1]).unwrap();
                let (dx, dy) = DIRECTIONS[number];
                (Command::Move(dx, dy), words.get(2).map_or(1, |value| value.parse().unwrap()))
            }
            "wait" => (Command::Wait, words.get(1).map_or(1, |value| value.parse().unwrap())),
            "pickup" => (Command::Pickup, 1), "descend" => (Command::Descend, 1),
            name => {
                let action = match name { "quaff" => UseAction::Quaff, "read" => UseAction::Read, "wield" => UseAction::Wield,
                    "wear" => UseAction::Wear, "eat" => UseAction::Eat, _ => unreachable!() };
                (Command::Use(action, words[1].parse().unwrap()), 1)
            }
        };
        commands.extend(std::iter::repeat_n(command, count));
    }
    commands
}
fn dec_1(numerator: i64, denominator: usize) -> String {
    if denominator == 0 { return "-".to_owned(); }
    let denominator = denominator as i64;
    let rounded = (20 * numerator + denominator) / (2 * denominator);
    format!("{}.{}", rounded / 10, rounded % 10)
}
fn exploration(level: &Level) -> (usize, usize) {
    let (mut explored, mut total) = (0, 0);
    for y in 0..level.height { for x in 0..level.width {
        if level.terrain[y][x] != b' ' { total += 1; if level.memory[y][x] != b' ' { explored += 1; } }
    } }
    (explored, total)
}
struct Player {
    x: i32,
    y: i32,
    depth: usize,
    hp: i64,
    max_hp: i64,
    level: usize,
    xp: i64,
    gold: i64,
    food: i64,
    poison: i64,
    pack: Vec<Item>,
    weapon: Option<usize>,
    armor: Option<usize>,
}
impl Player {
    fn defense(&self, types: &[ItemType]) -> i64 {
        match self.armor {
            Some(number) => match types[self.pack[number].kind].class { ItemClass::Armor(value) => 10 + value + self.pack[number].bonus, _ => unreachable!() },
            None => 10,
        }
    }
    fn remove_consumable(&mut self, number: usize) -> Item {
        if self.weapon.is_some_and(|index| index > number) { self.weapon = self.weapon.map(|index| index - 1); }
        if self.armor.is_some_and(|index| index > number) { self.armor = self.armor.map(|index| index - 1); }
        self.pack.remove(number)
    }
}
#[derive(Default)]
struct AttackStats { count: usize, hits: usize, criticals: usize, damage: i64 }
impl AttackStats {
    fn record(&mut self, outcome: AttackOutcome, damage: i64) {
        self.count += 1;
        if outcome != AttackOutcome::Miss { self.hits += 1; self.damage += damage; }
        if outcome == AttackOutcome::Critical { self.criticals += 1; }
    }
    fn line(&self, label: &str) -> String {
        format!("{label} {} hits {} criticals {} damage {} accuracy {}", self.count, self.hits, self.criticals, self.damage, dec_1(100 * self.hits as i64, self.count))
    }
}
struct Game {
    config: Config,
    monster_types: Vec<MonsterType>,
    item_types: Vec<ItemType>,
    commands: Vec<Command>,
    generator: Minstd,
    levels: Vec<Level>,
    player: Player,
    turn: usize,
    messages: Vec<String>,
    map_lines: Vec<String>,
    visible: Vec<Vec<bool>>,
    distance: Vec<Vec<Option<usize>>>,
    result: Option<&'static str>,
    cause: String,
    succeeded: usize,
    failed: usize,
    unused: usize,
    moves: usize,
    player_attacks: AttackStats,
    monster_attacks: AttackStats,
    poison_damage: usize,
    starvation_damage: usize,
    usage: [usize; 6],
    kills: Vec<usize>,
}
impl Game {
    fn new(config: Config, monster_types: Vec<MonsterType>, mut item_types: Vec<ItemType>, commands: Vec<Command>) -> Self {
        let original_names: BTreeMap<_, _> = item_types.iter().enumerate().map(|(number, kind)| (kind.name.clone(), number)).collect();
        let amulet = item_types.len();
        item_types.push(ItemType::amulet());
        let mut generation = Minstd { state: config.generation_seed };
        let builder = LevelGenerator { minimum: config.min_size, max_split: config.max_split, room_min: config.room_min, room_max: config.room_max };
        let mut levels = Vec::new();
        for depth in 1..=config.levels {
            let mut level = builder.generate(&mut generation, depth, config.width, config.height);
            let (x, y) = level.target;
            if depth < config.levels { level.terrain[y as usize][x as usize] = b'>'; }
            else { level.items.push(Item::new(amulet, x, y, 0)); }
            Self::place_monsters(&mut level, &monster_types, &config, &mut generation);
            Self::place_items(&mut level, &item_types, &config, &mut generation);
            levels.push(level);
        }
        let (x, y) = levels[0].arrival;
        let mut player = Player { x, y, depth: 1, hp: config.max_hp, max_hp: config.max_hp, level: 1, xp: 0, gold: 0,
            food: config.food_start, poison: 0, pack: Vec::new(), weapon: None, armor: None };
        for name in &config.start_items {
            let kind = original_names[name];
            let number = player.pack.len();
            player.pack.push(Item::new(kind, x, y, 0));
            if matches!(item_types[kind].class, ItemClass::Weapon { .. }) && player.weapon.is_none() { player.weapon = Some(number); }
            if matches!(item_types[kind].class, ItemClass::Armor(_)) && player.armor.is_none() { player.armor = Some(number); }
        }
        let generator = Minstd { state: config.game_seed };
        let kills = vec![0; monster_types.len()];
        let visible = vec![vec![false; config.width]; config.height];
        Self { config, monster_types, item_types, commands, generator, levels, player, turn: 1, messages: Vec::new(), map_lines: Vec::new(),
            visible, distance: Vec::new(), result: None, cause: String::new(), succeeded: 0, failed: 0, unused: 0, moves: 0,
            player_attacks: AttackStats::default(), monster_attacks: AttackStats::default(), poison_damage: 0, starvation_damage: 0, usage: [0; 6], kills }
    }
    fn place_monsters(level: &mut Level, types: &[MonsterType], config: &Config, generator: &mut Minstd) {
        let candidates: Vec<_> = types.iter().enumerate().filter(|(_, kind)| kind.min_depth <= level.depth && level.depth <= kind.max_depth).map(|(number, _)| number).collect();
        let weights: Vec<_> = candidates.iter().map(|&number| types[number].weight).collect();
        let count = config.monster_base + config.monster_step * (level.depth - 1);
        for number in 1..=count {
            let kind = candidates[generator.select(&weights)];
            let (x, y) = loop {
                let (room, x, y) = level.draw_room_cell(generator);
                if room != level.arrival_room && level.terrain[y as usize][x as usize] == b'.' && level.monster_at(x, y).is_none() { break (x, y); }
            };
            let hp = types[kind].hp.roll(generator);
            let asleep = generator.draw() % 100 < config.sleep_chance;
            level.monsters.push(Monster { number, kind, x, y, hp, max_hp: hp, asleep, energy: 0, was_visible: false });
        }
        level.monsters_created = count;
    }
    fn place_items(level: &mut Level, types: &[ItemType], config: &Config, generator: &mut Minstd) {
        let candidates: Vec<_> = types.iter().enumerate().filter(|(_, kind)| kind.min_depth <= level.depth && level.depth <= kind.max_depth).map(|(number, _)| number).collect();
        let weights: Vec<_> = candidates.iter().map(|&number| types[number].weight).collect();
        let count = config.item_base + config.item_step * (level.depth - 1);
        for _ in 0..count {
            let kind = candidates[generator.select(&weights)];
            let (x, y) = loop {
                let (_, x, y) = level.draw_room_cell(generator);
                if level.terrain[y as usize][x as usize] == b'.' && level.item_at(x, y).is_none() { break (x, y); }
            };
            let amount = match types[kind].class { ItemClass::Gold(dice) => dice.roll(generator), _ => 0 };
            level.items.push(Item::new(kind, x, y, amount));
        }
        level.items_placed = level.items.len();
    }
    fn say(&mut self, text: String) { self.messages.push(format!("{:04} {text}", self.turn)); }
    fn hunger_state(&self) -> &'static str {
        if self.player.food > self.config.food_hungry { "normal" } else if self.player.food > self.config.food_weak { "hungry" }
        else if self.player.food > 0 { "weak" } else { "starving" }
    }
    fn die(&mut self, cause: String) { self.say("You die.".to_owned()); self.result = Some("died"); self.cause = cause; }
    fn update_view(&mut self) {
        let depth = self.player.depth - 1;
        self.visible = field_of_view(&self.levels[depth], self.player.x, self.player.y, self.config.radius);
        for y in 0..self.config.height { for x in 0..self.config.width {
            if !self.visible[y][x] { continue; }
            let symbol = match self.levels[depth].item_at(x as i32, y as i32) {
                Some(number) => self.item_types[self.levels[depth].items[number].kind].symbol(), None => self.levels[depth].terrain[y][x],
            };
            self.levels[depth].memory[y][x] = symbol;
        } }
        for number in 0..self.levels[depth].monsters.len() {
            let (x, y, kind, was_visible) = {
                let monster = &self.levels[depth].monsters[number];
                (monster.x, monster.y, monster.kind, monster.was_visible)
            };
            let visible = self.visible[y as usize][x as usize];
            if visible && !was_visible { self.say(format!("You see the {}.", self.monster_types[kind].name)); }
            self.levels[depth].monsters[number].was_visible = visible;
        }
    }
    fn run(&mut self) {
        self.update_view();
        for number in 0..self.commands.len() {
            if self.result.is_some() { self.unused += 1; continue; }
            if !self.execute(self.commands[number]) { self.failed += 1; continue; }
            self.succeeded += 1;
            if self.result.is_none() { self.advance_turn(); }
        }
        if self.result.is_none() { self.result = Some("alive"); self.cause = "commands_exhausted".to_owned(); }
    }
    fn advance_turn(&mut self) {
        self.update_view();
        let depth = self.player.depth - 1;
        self.distance = distances(&self.levels[depth], self.player.x, self.player.y);
        for number in 0..self.levels[depth].monsters.len() {
            let kind = self.levels[depth].monsters[number].kind;
            self.levels[depth].monsters[number].energy += self.monster_types[kind].speed;
            while self.levels[depth].monsters[number].energy >= 2 {
                self.levels[depth].monsters[number].energy -= 2;
                self.monster_action(number);
                if self.result.is_some() { return; }
            }
        }
        self.end_turn();
        if self.result.is_some() { return; }
        if self.config.checkpoints.contains(&self.turn) {
            self.map_lines.push(format!("CHECKPOINT turn {} depth {}", self.turn, self.player.depth));
            let rows = self.map_rows(depth, true);
            self.map_lines.extend(rows);
            let status = self.status_line();
            self.map_lines.push(status);
        }
        self.turn += 1;
    }
    fn execute(&mut self, command: Command) -> bool {
        match command { Command::Move(dx, dy) => self.move_player(dx, dy), Command::Wait => true, Command::Pickup => self.pickup(),
            Command::Descend => self.descend(), Command::Use(action, number) => self.use_item(action, number) }
    }
    fn move_player(&mut self, dx: i32, dy: i32) -> bool {
        let depth = self.player.depth - 1;
        let (x, y) = (self.player.x + dx, self.player.y + dy);
        if !passable(&self.levels[depth], x, y) { self.say("You bump into a wall.".to_owned()); return false; }
        if !can_move(&self.levels[depth], self.player.x, self.player.y, dx, dy) { self.say("You cannot move diagonally through a door.".to_owned()); return false; }
        if let Some(number) = self.levels[depth].monster_at(x, y) { self.player_attack(number); return true; }
        self.player.x = x;
        self.player.y = y;
        self.moves += 1;
        if let Some(number) = self.levels[depth].item_at(x, y) {
            self.say(format!("You see {} here.", self.levels[depth].items[number].reference_name(&self.item_types)));
        } else if self.levels[depth].terrain[y as usize][x as usize] == b'>' { self.say("There is a staircase down here.".to_owned()); }
        true
    }
    fn pickup(&mut self) -> bool {
        let depth = self.player.depth - 1;
        let Some(number) = self.levels[depth].item_at(self.player.x, self.player.y) else { self.say("There is nothing here.".to_owned()); return false; };
        let item = self.levels[depth].items[number].clone();
        let name = item.display_name(&self.item_types);
        match self.item_types[item.kind].class {
            ItemClass::Gold(_) => { self.player.gold += item.amount; self.say(format!("You pick up {name}.")); }
            ItemClass::Amulet => {
                self.say("You pick up the amulet.".to_owned()); self.say("You win!".to_owned()); self.result = Some("won"); self.cause = "amulet".to_owned();
            }
            _ => {
                if self.player.pack.len() >= self.config.pack_limit { self.say("Your pack is full.".to_owned()); return false; }
                self.player.pack.push(item);
                self.say(format!("You pick up the {name} ({}).", self.player.pack.len()));
            }
        }
        self.levels[depth].items.remove(number);
        self.levels[depth].picked += 1;
        self.usage[0] += 1;
        true
    }
    fn descend(&mut self) -> bool {
        let depth = self.player.depth - 1;
        if self.levels[depth].terrain[self.player.y as usize][self.player.x as usize] != b'>' { self.say("There are no stairs here.".to_owned()); return false; }
        self.player.depth += 1;
        (self.player.x, self.player.y) = self.levels[self.player.depth - 1].arrival;
        self.say(format!("You descend to depth {}.", self.player.depth));
        true
    }
    fn use_item(&mut self, action: UseAction, number: usize) -> bool {
        if number > self.player.pack.len() { self.say("You do not have that item.".to_owned()); return false; }
        let number = number - 1;
        let class = self.item_types[self.player.pack[number].kind].class;
        if !action.accepts(class) { self.say(format!("You cannot {} that.", action.name())); return false; }
        match action {
            UseAction::Wield => {
                if self.player.weapon == Some(number) { self.say("You are already wielding that.".to_owned()); return false; }
                self.player.weapon = Some(number); self.usage[4] += 1;
                self.say(format!("You are now wielding the {}.", self.player.pack[number].display_name(&self.item_types)));
            }
            UseAction::Wear => {
                if self.player.armor == Some(number) { self.say("You are already wearing that.".to_owned()); return false; }
                self.player.armor = Some(number); self.usage[5] += 1;
                self.say(format!("You are now wearing the {}.", self.player.pack[number].display_name(&self.item_types)));
            }
            UseAction::Quaff => {
                let item = self.player.remove_consumable(number);
                self.usage[1] += 1;
                self.say(format!("You quaff the {}.", item.display_name(&self.item_types)));
                match class {
                    ItemClass::Potion(PotionEffect::Heal(dice)) => {
                        self.player.hp += dice.roll(&mut self.generator);
                        if self.player.hp > self.player.max_hp { self.player.max_hp += 1; self.player.hp = self.player.max_hp; }
                        self.player.poison = 0; self.say("You feel better.".to_owned());
                    }
                    ItemClass::Potion(PotionEffect::Poison(turns)) => { self.player.poison += turns; self.say("You feel very sick.".to_owned()); }
                    ItemClass::Potion(PotionEffect::Level) => {
                        self.say("You feel more experienced.".to_owned());
                        if self.player.level <= self.config.xp_levels.len() { self.gain_xp(self.config.xp_levels[self.player.level - 1] - self.player.xp); }
                    }
                    _ => unreachable!(),
                }
            }
            UseAction::Read => {
                let item = self.player.remove_consumable(number);
                self.usage[2] += 1;
                self.say(format!("You read the {}.", item.display_name(&self.item_types)));
                let ItemClass::Scroll(effect) = class else { unreachable!(); };
                self.read_scroll(effect);
            }
            UseAction::Eat => {
                let item = self.player.remove_consumable(number);
                self.usage[3] += 1;
                let ItemClass::Food(nutrition) = class else { unreachable!(); };
                self.player.food = (self.player.food + nutrition).min(self.config.food_max);
                self.say(format!("You eat the {}.", item.display_name(&self.item_types)));
            }
        }
        true
    }
    fn read_scroll(&mut self, effect: ScrollEffect) {
        let depth = self.player.depth - 1;
        match effect {
            ScrollEffect::Mapping => {
                for y in 0..self.config.height { for x in 0..self.config.width {
                    if self.levels[depth].terrain[y][x] != b' ' && self.levels[depth].memory[y][x] == b' ' { self.levels[depth].memory[y][x] = self.levels[depth].terrain[y][x]; }
                } }
                self.say("A map forms in your mind.".to_owned());
            }
            ScrollEffect::Teleport => {
                let (x, y) = loop {
                    let (_, x, y) = self.levels[depth].draw_room_cell(&mut self.generator);
                    if (x, y) != (self.player.x, self.player.y) && self.levels[depth].monster_at(x, y).is_none() { break (x, y); }
                };
                self.player.x = x; self.player.y = y;
                self.say("You are teleported.".to_owned());
            }
            ScrollEffect::EnchantWeapon => {
                if let Some(number) = self.player.weapon {
                    self.say(format!("Your {} glows blue.", self.player.pack[number].display_name(&self.item_types)));
                    self.player.pack[number].bonus += 1;
                } else { self.say("Your hands twitch.".to_owned()); }
            }
            ScrollEffect::EnchantArmor => {
                if let Some(number) = self.player.armor {
                    self.say(format!("Your {} glows silver.", self.player.pack[number].display_name(&self.item_types)));
                    self.player.pack[number].bonus += 1;
                } else { self.say("Your skin tingles.".to_owned()); }
            }
        }
    }
    fn player_attack(&mut self, number: usize) {
        let depth = self.player.depth - 1;
        self.levels[depth].monsters[number].asleep = false;
        let kind = self.levels[depth].monsters[number].kind;
        let (mut to_hit, dice, bonus) = match self.player.weapon {
            Some(index) => {
                let item = &self.player.pack[index];
                let ItemClass::Weapon { damage, to_hit } = self.item_types[item.kind].class else { unreachable!(); };
                (self.player.level as i64 + to_hit + item.bonus, damage, item.bonus)
            }
            None => (self.player.level as i64, Dice { count: 1, sides: 2 }, 0),
        };
        if self.hunger_state() == "weak" || self.hunger_state() == "starving" { to_hit -= 2; }
        let (outcome, damage) = resolve_attack(&mut self.generator, to_hit, self.monster_types[kind].defense, dice, bonus);
        self.player_attacks.record(outcome, damage);
        let name = self.monster_types[kind].name.clone();
        if outcome == AttackOutcome::Miss { self.say(format!("You miss the {name}.")); return; }
        self.say(format!("You hit the {name}{} for {damage}.", if outcome == AttackOutcome::Critical { " hard" } else { "" }));
        self.levels[depth].monsters[number].hp -= damage;
        if self.levels[depth].monsters[number].hp <= 0 {
            self.say(format!("You kill the {name}."));
            self.levels[depth].monsters.remove(number);
            self.levels[depth].kills += 1; self.kills[kind] += 1;
            self.gain_xp(self.monster_types[kind].xp);
        }
    }
    fn gain_xp(&mut self, amount: i64) {
        self.player.xp += amount;
        while self.player.level <= self.config.xp_levels.len() && self.player.xp >= self.config.xp_levels[self.player.level - 1] {
            self.player.level += 1;
            let gained = self.config.hit_die.roll(&mut self.generator);
            self.player.max_hp += gained; self.player.hp += gained;
            self.say(format!("Welcome to level {}.", self.player.level));
        }
    }
    fn monster_attack(&mut self, number: usize) {
        let depth = self.player.depth - 1;
        let kind = self.levels[depth].monsters[number].kind;
        let attack = &self.monster_types[kind];
        let (outcome, damage) = resolve_attack(&mut self.generator, attack.to_hit, self.player.defense(&self.item_types), attack.damage, 0);
        self.monster_attacks.record(outcome, damage);
        let name = attack.name.clone();
        let poisonous = attack.poisonous;
        if outcome == AttackOutcome::Miss { self.say(format!("The {name} misses you.")); return; }
        self.say(format!("The {name} hits you{} for {damage}.", if outcome == AttackOutcome::Critical { " hard" } else { "" }));
        self.player.hp -= damage;
        if self.player.hp <= 0 { self.die(format!("killed_by {name}")); }
        else if poisonous { self.player.poison += 5; self.say("You are poisoned.".to_owned()); }
    }
    fn can_attack(&self, number: usize) -> bool {
        let level = &self.levels[self.player.depth - 1];
        let monster = &level.monsters[number];
        let (dx, dy) = (self.player.x - monster.x, self.player.y - monster.y);
        dx.abs().max(dy.abs()) == 1 && can_move(level, monster.x, monster.y, dx, dy)
    }
    fn monster_action(&mut self, number: usize) {
        let depth = self.player.depth - 1;
        let monster = self.levels[depth].monsters[number].clone();
        let kind = monster.kind;
        let sees = self.visible[monster.y as usize][monster.x as usize];
        if monster.asleep {
            if sees && self.generator.draw() % 100 < self.config.wake_chance {
                self.levels[depth].monsters[number].asleep = false;
                self.say(format!("The {} wakes up.", self.monster_types[kind].name));
            }
        } else if self.monster_types[kind].stationary {
            if self.can_attack(number) { self.monster_attack(number); }
        } else if self.monster_types[kind].erratic && self.generator.draw() % 2 == 0 { self.wander(number); }
        else if sees { self.chase(number); }
        else { self.wander(number); }
    }
    fn wander(&mut self, number: usize) {
        let depth = self.player.depth - 1;
        let (dx, dy) = DIRECTIONS[self.generator.rnd(8)];
        let (mx, my) = (self.levels[depth].monsters[number].x, self.levels[depth].monsters[number].y);
        if !can_move(&self.levels[depth], mx, my, dx, dy) { return; }
        let (x, y) = (mx + dx, my + dy);
        if (x, y) == (self.player.x, self.player.y) { self.monster_attack(number); }
        else if self.levels[depth].monster_at(x, y).is_none() {
            self.levels[depth].monsters[number].x = x;
            self.levels[depth].monsters[number].y = y;
        }
    }
    fn chase(&mut self, number: usize) {
        if self.can_attack(number) { self.monster_attack(number); return; }
        let depth = self.player.depth - 1;
        let monster = &self.levels[depth].monsters[number];
        let (mx, my) = (monster.x, monster.y);
        let here = self.distance[my as usize][mx as usize];
        let mut best: Option<(usize, i32, i32)> = None;
        for (dx, dy) in DIRECTIONS {
            if !can_move(&self.levels[depth], mx, my, dx, dy) { continue; }
            let (x, y) = (mx + dx, my + dy);
            let Some(distance) = self.distance[y as usize][x as usize] else { continue; };
            if here.is_some_and(|here| distance >= here) || self.levels[depth].monster_at(x, y).is_some() || (x, y) == (self.player.x, self.player.y) { continue; }
            if best.is_none_or(|(previous, _, _)| distance < previous) { best = Some((distance, x, y)); }
        }
        if let Some((_, x, y)) = best {
            self.levels[depth].monsters[number].x = x;
            self.levels[depth].monsters[number].y = y;
        }
    }
    fn end_turn(&mut self) {
        let depth = self.player.depth - 1;
        for monster in &mut self.levels[depth].monsters {
            if self.monster_types[monster.kind].regenerates && monster.hp < monster.max_hp { monster.hp += 1; }
        }
        if self.player.poison > 0 {
            self.player.hp -= 1; self.poison_damage += 1;
            if self.player.hp <= 0 { self.die("poison".to_owned()); return; }
            self.player.poison -= 1;
            if self.player.poison == 0 { self.say("You feel less sick.".to_owned()); }
        }
        if self.player.food == 0 {
            self.player.hp -= 1; self.starvation_damage += 1;
            if self.player.hp <= 0 { self.die("starvation".to_owned()); return; }
        } else {
            let before = self.hunger_state();
            self.player.food -= 1;
            let after = self.hunger_state();
            if before != after {
                self.say(match after { "hungry" => "You are getting hungry.", "weak" => "You feel weak from hunger.",
                    "starving" => "You are starving.", _ => unreachable!() }.to_owned());
            }
        }
        if self.turn % self.config.regen_interval == 0 && self.player.poison == 0 && self.player.food > 0 && self.player.hp < self.player.max_hp { self.player.hp += 1; }
    }
    fn map_rows(&self, depth: usize, current: bool) -> Vec<String> {
        let level = &self.levels[depth];
        let border = format!("+{}+", "-".repeat(level.width));
        let mut rows = vec![border.clone()];
        for y in 0..level.height {
            let mut row = vec![b'|'];
            for x in 0..level.width {
                let symbol = if !current || !self.visible[y][x] { level.memory[y][x] }
                else if (x as i32, y as i32) == (self.player.x, self.player.y) { b'@' }
                else if let Some(number) = level.monster_at(x as i32, y as i32) { self.monster_types[level.monsters[number].kind].symbol }
                else if let Some(number) = level.item_at(x as i32, y as i32) { self.item_types[level.items[number].kind].symbol() }
                else { level.terrain[y][x] };
                row.push(symbol);
            }
            row.push(b'|');
            rows.push(String::from_utf8(row).unwrap());
        }
        rows.push(border);
        rows
    }
    fn status_line(&self) -> String {
        let p = &self.player;
        format!("STATUS hp {}/{} level {} xp {} defense {} gold {} food {} {} poison {}", p.hp, p.max_hp, p.level, p.xp,
            p.defense(&self.item_types), p.gold, p.food, self.hunger_state(), p.poison)
    }
    fn final_block(&self) -> Vec<String> {
        let mut lines = vec![format!("FINAL turn {} depth {}", self.succeeded, self.player.depth)];
        for depth in 0..self.player.depth {
            let level = &self.levels[depth];
            let (explored, total) = exploration(level);
            lines.push(format!("LEVEL {} explored {explored}/{total}", level.depth));
            lines.extend(self.map_rows(depth, depth + 1 == self.player.depth));
        }
        lines.push(self.status_line());
        lines
    }
    fn item_label(&self, number: Option<usize>) -> String {
        number.map(|number| self.player.pack[number].display_name(&self.item_types)).unwrap_or_else(|| "-".to_owned())
    }
    fn stats_lines(&self) -> Vec<String> {
        let p = &self.player;
        let mut lines = vec![format!("result {}", self.result.unwrap()), format!("cause {}", self.cause),
            format!("turns {}", self.succeeded), format!("depth {}", p.depth), format!("level {}", p.level), format!("xp {}", p.xp),
            format!("hp {}/{}", p.hp, p.max_hp), format!("defense {}", p.defense(&self.item_types)), format!("gold {}", p.gold),
            format!("food {} {}", p.food, self.hunger_state()), format!("poison {}", p.poison), format!("weapon {}", self.item_label(p.weapon)),
            format!("armor {}", self.item_label(p.armor)), format!("commands {} executed {} failed {} unused {}", self.commands.len(), self.succeeded, self.failed, self.unused),
            format!("moves {}", self.moves), self.player_attacks.line("player_attacks"), self.monster_attacks.line("monster_attacks"),
            format!("poison_damage {} starvation_damage {}", self.poison_damage, self.starvation_damage),
            format!("picked {} quaffed {} read {} eaten {} wielded {} worn {}", self.usage[0], self.usage[1], self.usage[2], self.usage[3], self.usage[4], self.usage[5]),
            format!("kills {}", self.kills.iter().sum::<usize>())];
        for (kind, &count) in self.monster_types.iter().zip(&self.kills) {
            if count > 0 { lines.push(format!("KILL {} {count}", kind.name)); }
        }
        for level in &self.levels {
            let (explored, total) = exploration(level);
            lines.push(format!("LEVEL {} rooms {} explored {explored}/{total} {} monsters {}/{} items {}/{}", level.depth, level.rooms.len(),
                dec_1(100 * explored as i64, total), level.kills, level.monsters_created, level.picked, level.items_placed));
        }
        for (number, item) in p.pack.iter().enumerate() {
            let marker = if p.weapon == Some(number) { " (wielded)" } else if p.armor == Some(number) { " (worn)" } else { "" };
            lines.push(format!("INVENTORY {} {}{marker}", number + 1, item.display_name(&self.item_types)));
        }
        lines
    }
}

fn main() -> io::Result<()> {
    let config = Config::read(&read_rows("config.txt")?);
    let monster_types = read_rows("monsters.txt")?.iter().map(|words| MonsterType::parse(&words.iter().map(String::as_str).collect::<Vec<_>>())).collect();
    let item_types = read_rows("items.txt")?.iter().map(|words| ItemType::parse(&words.iter().map(String::as_str).collect::<Vec<_>>())).collect();
    let commands = expand_commands(&read_rows("commands.txt")?);
    let mut game = Game::new(config, monster_types, item_types, commands);
    game.run();
    let mut maps = game.map_lines.clone();
    maps.extend(game.final_block());
    fs::create_dir_all("output")?;
    for (name, lines) in [("messages.txt", game.messages.clone()), ("maps.txt", maps), ("stats.txt", game.stats_lines())] {
        let text = if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" };
        fs::write(format!("output/{name}"), text)?;
    }
    Ok(())
}
