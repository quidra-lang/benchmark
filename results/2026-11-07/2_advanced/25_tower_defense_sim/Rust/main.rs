mod grid_map;
mod pathing;
mod towers;
mod enemies;
mod combat;

use std::collections::{HashMap, HashSet};
use std::{fs, io};
use combat::{Projectile, advance, damage_dealt, squared_distance};
use enemies::{Enemy, EnemyType, Movement, Position, Wave, parse_waves};
use grid_map::{Cell, GridMap, cell_center};
use pathing::DistanceField;
use towers::{TargetMode, Tower, TowerType, parse_tower_types};

const WAVE_COLUMNS: &str = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives";
fn read_lines(name: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect()) }
fn write_lines(name: &str, lines: &[String]) -> io::Result<()> { fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }) }
fn one_decimal(numerator: i64, denominator: i64) -> String { if denominator == 0 { "-".to_owned() } else { let rounded = (20 * numerator + denominator) / (2 * denominator); format!("{}.{}", rounded / 10, rounded % 10) } }
fn digit(count: i64) -> u8 { if count == 0 { b'.' } else if count <= 9 { b'0' + count as u8 } else { b'*' } }
fn ruled(rows: &[Vec<u8>]) -> Vec<String> {
    let mut lines = vec![format!("  {}", (0..rows[0].len()).map(|x| (b'0' + (x % 10) as u8) as char).collect::<String>())];
    for (y, row) in rows.iter().enumerate() { lines.push(format!("{} {}", y % 10, String::from_utf8(row.clone()).unwrap())); }
    lines
}
struct Params { gold: i64, lives: i64, interest_rate: i64, interest_cap: i64, sell_rate: i64, start: i64, interval: i64, early: i64, snapshots: HashSet<i64> }
impl Params {
    fn new(lines: &[String]) -> Self {
        let values: Vec<Vec<i64>> = lines.iter().map(|line| line.split(' ').skip(1).map(|value| value.parse().unwrap()).collect()).collect();
        Self { gold: values[0][0], lives: values[1][0], interest_rate: values[2][0], interest_cap: values[2][1], sell_rate: values[3][0], start: values[4][0], interval: values[4][1], early: values[5][0], snapshots: values[6].iter().copied().collect() }
    }
}
enum Command { Build(String, Cell), Upgrade(usize), Sell(usize), Target(usize, String), Call }
struct Action { tick: i64, command: Command }
impl Action {
    fn parse(line: &str) -> Self {
        let fields: Vec<&str> = line.split(' ').collect();
        let command = match fields[1] {
            "BUILD" => Command::Build(fields[2].to_owned(), (fields[3].parse().unwrap(), fields[4].parse().unwrap())),
            "UPGRADE" => Command::Upgrade(fields[2].parse().unwrap()), "SELL" => Command::Sell(fields[2].parse().unwrap()),
            "TARGET" => Command::Target(fields[2].parse().unwrap(), fields[3].to_owned()), _ => Command::Call,
        };
        Self { tick: fields[0].parse().unwrap(), command }
    }
}
#[derive(Clone, Copy, PartialEq)]
enum WaveStatus { Active, Cleared, Lost }
impl WaveStatus { fn text(self) -> &'static str { match self { Self::Active => "active", Self::Cleared => "cleared", Self::Lost => "lost" } } }
struct WaveRecord {
    number: usize, start: i64, end: i64, status: WaveStatus, released: Vec<usize>, spawned: i64, peak: usize,
    kills: i64, leaks: i64, lives_lost: i64, bounty: i64, reward: i64, interest: i64, gold: i64, lives: i64, tower_damage: HashMap<usize, i64>,
}
impl WaveRecord {
    fn new(number: usize, start: i64, group_count: usize) -> Self { Self { number, start, end: 0, status: WaveStatus::Active, released: vec![0; group_count], spawned: 0, peak: 0, kills: 0, leaks: 0, lives_lost: 0, bounty: 0, reward: 0, interest: 0, gold: 0, lives: 0, tower_damage: HashMap::new() } }
    fn close(&mut self, status: WaveStatus, tick: i64, gold: i64, lives: i64) { self.status = status; self.end = tick; self.gold = gold; self.lives = lives; }
    fn csv_row(&self, tower_count: usize) -> String {
        let mut fields = vec![self.number.to_string(), self.start.to_string(), self.end.to_string(), self.status.text().to_owned(), self.spawned.to_string(), self.peak.to_string(), self.kills.to_string(), self.leaks.to_string(), self.lives_lost.to_string(), self.bounty.to_string(), self.reward.to_string(), self.interest.to_string(), self.gold.to_string(), self.lives.to_string()];
        fields.extend((0..tower_count).map(|tower| self.tower_damage.get(&tower).copied().unwrap_or(0).to_string()));
        fields.join(",")
    }
}
#[derive(Clone, Copy)]
enum Outcome { Victory, Defeat }
impl Outcome { fn text(self) -> &'static str { match self { Self::Victory => "victory", Self::Defeat => "defeat" } } }
#[derive(Default)]
struct Income { bounty: i64, reward: i64, interest: i64, early: i64, refund: i64 }
struct Game {
    grid: GridMap, tower_types: Vec<TowerType>, enemy_types: Vec<EnemyType>, waves: Vec<Wave>, params: Params,
    tick: i64, gold: i64, lives: i64, towers: Vec<Tower>, enemies: Vec<Enemy>, projectiles: Vec<Projectile>, projectile_count: usize,
    records: Vec<WaveRecord>, active: Option<usize>, next_start: Option<i64>, outcome: Option<Outcome>, field: DistanceField,
    kill_counts: Vec<Vec<i64>>, income: Income, spent: i64, done: usize, refused: usize, events: Vec<String>, snapshots: Vec<String>,
}
impl Game {
    fn new(grid: GridMap, tower_types: Vec<TowerType>, enemy_types: Vec<EnemyType>, waves: Vec<Wave>, params: Params) -> Self {
        let field = DistanceField::new(&grid, &HashSet::new());
        let kill_counts = vec![vec![0; grid.width]; grid.height];
        let (gold, lives, next_start) = (params.gold, params.lives, Some(params.start));
        Self { grid, tower_types, enemy_types, waves, params, tick: 0, gold, lives, towers: Vec::new(), enemies: Vec::new(), projectiles: Vec::new(), projectile_count: 0,
            records: Vec::new(), active: None, next_start, outcome: None, field, kill_counts, income: Income::default(), spent: 0, done: 0, refused: 0, events: Vec::new(), snapshots: Vec::new() }
    }
    fn record(&mut self, body: String) { self.events.push(format!("{} {body}", self.tick)); }
    fn run(&mut self, actions: &[Action]) {
        let mut index = 0;
        loop {
            self.tick += 1;
            while index < actions.len() && actions[index].tick == self.tick { self.perform(&actions[index].command); index += 1; }
            self.spawn_enemies(); self.move_enemies();
            if self.outcome.is_some() { break; }
            self.fire_towers(); self.move_projectiles(); self.check_wave_end();
            if self.params.snapshots.contains(&self.tick) { let block = self.block("SNAPSHOT"); self.snapshots.extend(block); }
            if self.outcome.is_some() { break; }
        }
        let final_block = self.final_block();
        self.snapshots.extend(final_block);
    }
    fn tower_cells(&self) -> HashSet<Cell> { self.towers.iter().filter(|tower| tower.standing()).map(|tower| tower.cell).collect() }
    fn tower_at(&self, cell: Cell) -> Option<usize> { self.towers.iter().position(|tower| tower.standing() && tower.cell == cell) }
    fn standing_tower(&self, number: usize) -> Option<usize> { self.towers.get(number - 1).filter(|tower| tower.standing()).map(|_| number - 1) }
    fn perform(&mut self, command: &Command) {
        let success = match command { Command::Build(name, cell) => self.build(name, *cell), Command::Upgrade(number) => self.upgrade(*number), Command::Sell(number) => self.sell(*number), Command::Target(number, mode) => self.set_target(*number, mode), Command::Call => self.call_wave() };
        if success { self.done += 1; } else { self.refused += 1; }
    }
    fn build_refusal(&self, name: &str, cell: Cell) -> Option<&'static str> {
        let Some(kind) = self.tower_types.iter().position(|kind| kind.name == name) else { return Some("type"); };
        if !self.grid.inside(cell) { return Some("bounds"); }
        if !self.grid.buildable(cell) { return Some("terrain"); }
        if self.tower_at(cell).is_some() { return Some("tower"); }
        if self.gold < self.tower_types[kind].levels[0].cost { return Some("gold"); }
        for enemy in &self.enemies { if enemy.alive { if let Position::Ground { cell: current, next, .. } = enemy.position { if current == cell || next == cell { return Some("enemy"); } } } }
        let mut cells = self.tower_cells(); cells.insert(cell);
        let trial = DistanceField::new(&self.grid, &cells);
        if self.grid.spawns.iter().any(|&spawn| trial.at(spawn).is_none()) { return Some("blocked"); }
        for enemy in &self.enemies { if enemy.alive { if let Position::Ground { next, .. } = enemy.position { if trial.at(next).is_none() { return Some("blocked"); } } } }
        None
    }
    fn build(&mut self, name: &str, cell: Cell) -> bool {
        if let Some(reason) = self.build_refusal(name, cell) { self.record(format!("BUILD_REFUSED {name} {} {} {reason}", cell.0, cell.1)); return false; }
        let kind = self.tower_types.iter().position(|kind| kind.name == name).unwrap(); let cost = self.tower_types[kind].levels[0].cost;
        let tower = Tower::new(self.towers.len() + 1, kind, &self.tower_types, cell, self.tick); let number = tower.number;
        self.towers.push(tower); self.gold -= cost; self.spent += cost;
        self.record(format!("BUILD T{number} {name} {} {} cost {cost} gold {}", cell.0, cell.1, self.gold));
        self.update_field(); true
    }
    fn upgrade(&mut self, number: usize) -> bool {
        let Some(index) = self.standing_tower(number) else { self.record(format!("UPGRADE_REFUSED T{number} notower")); return false; };
        let tower = &self.towers[index];
        if tower.level + 1 == self.tower_types[tower.kind].levels.len() { self.record(format!("UPGRADE_REFUSED T{number} maxlevel")); return false; }
        let cost = self.tower_types[tower.kind].levels[tower.level + 1].cost;
        if self.gold < cost { self.record(format!("UPGRADE_REFUSED T{number} gold")); return false; }
        self.gold -= cost; self.spent += cost; self.towers[index].level += 1; self.towers[index].investment += cost;
        self.record(format!("UPGRADE T{number} level {} cost {cost} gold {}", self.towers[index].level + 1, self.gold)); true
    }
    fn sell(&mut self, number: usize) -> bool {
        let Some(index) = self.standing_tower(number) else { self.record(format!("SELL_REFUSED T{number} notower")); return false; };
        let tower = &self.towers[index]; let rate = if self.tick == tower.built { 100 } else { self.params.sell_rate }; let refund = tower.investment * rate / 100;
        self.towers[index].sold = Some(self.tick); self.gold += refund; self.income.refund += refund;
        self.record(format!("SELL T{number} refund {refund} gold {}", self.gold)); self.update_field(); true
    }
    fn set_target(&mut self, number: usize, mode: &str) -> bool {
        let Some(index) = self.standing_tower(number) else { self.record(format!("TARGET_REFUSED T{number} notower")); return false; };
        let Some(value) = TargetMode::parse(mode) else { self.record(format!("TARGET_REFUSED T{number} mode")); return false; };
        self.towers[index].mode = value; self.record(format!("TARGET T{number} {mode}")); true
    }
    fn call_wave(&mut self) -> bool {
        if self.active.is_some() { self.record("CALL_REFUSED active".to_owned()); return false; }
        let bonus = (self.next_start.unwrap() - self.tick) * self.params.early;
        self.gold += bonus; self.income.early += bonus; self.next_start = Some(self.tick);
        self.record(format!("CALL {} bonus {bonus} gold {}", self.records.len() + 1, self.gold)); true
    }
    fn update_field(&mut self) {
        let updated = DistanceField::new(&self.grid, &self.tower_cells());
        let mut changed = Vec::new();
        for (number, &spawn) in self.grid.spawns.iter().enumerate() { let old = self.field.at(spawn).unwrap(); let new = updated.at(spawn).unwrap(); if old != new { changed.push(format!("REPATH {} {old} {new}", number + 1)); } }
        self.field = updated;
        for body in changed { self.record(body); }
    }
    fn start_wave(&mut self) {
        let index = self.records.len(); let count = self.waves[index].enemy_count();
        self.records.push(WaveRecord::new(index + 1, self.tick, self.waves[index].groups.len())); self.active = Some(index); self.next_start = None;
        self.record(format!("WAVE_START {} enemies {count}", index + 1));
    }
    fn add_enemy(&mut self, enemy: Enemy) {
        self.records[self.active.unwrap()].spawned += 1; self.enemy_types[enemy.kind].spawned += 1; self.enemies.push(enemy);
    }
    fn spawn_enemies(&mut self) {
        if self.next_start == Some(self.tick) { self.start_wave(); }
        let Some(wave) = self.active else { return; };
        for group_index in 0..self.waves[wave].groups.len() {
            let group = self.waves[wave].groups[group_index]; let released = self.records[wave].released[group_index];
            if released == group.count || group.spawn_tick(self.records[wave].start, released) != self.tick { continue; }
            self.records[wave].released[group_index] += 1;
            let spawn = self.grid.spawns[group.spawn];
            let position = if self.enemy_types[group.kind].movement == Movement::Air { Position::Air(cell_center(spawn)) } else { Position::Ground { cell: spawn, next: self.field.next_cell(spawn), progress: 0 } };
            let enemy = Enemy::new(self.enemies.len() + 1, group.kind, &self.enemy_types, group.multiplier, position); let number = enemy.number; let hp = enemy.hp;
            self.add_enemy(enemy);
            self.record(format!("SPAWN E{number} {} {} hp {hp}", self.enemy_types[group.kind].name, group.spawn + 1));
        }
        self.records[wave].peak = self.records[wave].peak.max(self.enemies.iter().filter(|enemy| enemy.alive).count());
    }
    fn move_enemies(&mut self) {
        let order: Vec<usize> = self.enemies.iter().enumerate().filter(|(_, enemy)| enemy.alive).map(|(index, _)| index).collect();
        for index in order { self.move_enemy(index); if self.outcome.is_some() { return; } }
    }
    fn move_enemy(&mut self, index: usize) {
        if self.enemies[index].burn.active() {
            let source = self.enemies[index].burn.source.unwrap(); let damage = self.enemies[index].hp.min(self.enemies[index].burn.strength);
            self.enemies[index].hp -= damage; self.credit(source, index, damage); self.enemies[index].burn.advance_time();
            if self.enemies[index].hp == 0 { self.kill(index, source); return; }
        }
        let regen = self.enemy_types[self.enemies[index].kind].regen;
        self.enemies[index].hp = (self.enemies[index].hp + regen).min(self.enemies[index].max_hp);
        let speed = self.enemies[index].slowed_speed(&self.enemy_types);
        if self.enemies[index].slow.active() { self.enemies[index].slow.advance_time(); }
        let arrived = match self.enemies[index].position {
            Position::Air(point) => { let (point, arrived) = advance(point, cell_center(self.grid.exit), speed); self.enemies[index].position = Position::Air(point); arrived }
            Position::Ground { .. } => self.walk(index, speed),
        };
        if arrived { self.leak(index); }
    }
    fn walk(&mut self, index: usize, mut speed: i64) -> bool {
        if self.grid.is_water(self.enemies[index].occupied_cell()) { speed /= 2; }
        let Position::Ground { mut cell, mut next, mut progress } = self.enemies[index].position else { unreachable!() };
        let mut arrived = false;
        while speed > 0 {
            let rest = 100 - progress;
            if speed < rest { progress += speed; speed = 0; }
            else { speed -= rest; cell = next; progress = 0; if cell == self.grid.exit { arrived = true; break; } next = self.field.next_cell(cell); }
        }
        self.enemies[index].position = Position::Ground { cell, next, progress };
        arrived
    }
    fn leak(&mut self, index: usize) {
        self.enemies[index].alive = false; let kind = self.enemies[index].kind; let lost = self.lives.min(self.enemy_types[kind].lives); self.lives -= lost;
        let wave = self.active.unwrap(); self.records[wave].leaks += 1; self.records[wave].lives_lost += lost; self.enemy_types[kind].leaks += 1;
        self.record(format!("LEAK E{} {} lives {}", self.enemies[index].number, self.enemy_types[kind].name, self.lives));
        if self.lives == 0 { self.record("DEFEAT".to_owned()); self.outcome = Some(Outcome::Defeat); self.records[wave].close(WaveStatus::Lost, self.tick, self.gold, self.lives); self.active = None; }
    }
    fn fire_towers(&mut self) {
        for index in 0..self.towers.len() {
            if !self.towers[index].standing() || self.tick < self.towers[index].ready { continue; }
            if let Some(target) = self.towers[index].select_target(&self.enemies, &self.enemy_types, &self.tower_types, &self.field) {
                let tower = &self.towers[index]; let stats = tower.stats(&self.tower_types);
                self.projectile_count += 1;
                self.projectiles.push(Projectile { number: self.projectile_count, tower: index, target, position: tower.center(), aim: self.enemies[target].point(), targets: self.tower_types[tower.kind].targets, stats });
                self.towers[index].shots += 1; self.towers[index].ready = self.tick + stats.interval;
                self.record(format!("SHOT T{} E{}", self.towers[index].number, self.enemies[target].number));
            }
        }
    }
    fn move_projectiles(&mut self) {
        let projectiles = std::mem::take(&mut self.projectiles);
        for mut projectile in projectiles {
            if self.enemies[projectile.target].alive { projectile.aim = self.enemies[projectile.target].point(); }
            if projectile.fly() { self.impact(&projectile); } else { self.projectiles.push(projectile); }
        }
    }
    fn impact(&mut self, projectile: &Projectile) {
        let victims: Vec<usize> = if projectile.stats.splash == 0 {
            if self.enemies[projectile.target].alive { vec![projectile.target] } else { Vec::new() }
        } else {
            let radius = projectile.stats.splash * projectile.stats.splash;
            self.enemies.iter().enumerate().filter(|(_, enemy)| enemy.alive && projectile.targets.can_aim(self.enemy_types[enemy.kind].movement) && squared_distance(enemy.point(), projectile.aim) <= radius).map(|(index, _)| index).collect()
        };
        if victims.is_empty() { self.towers[projectile.tower].fizzles += 1; }
        for index in victims {
            self.towers[projectile.tower].hits += 1;
            let damage = damage_dealt(self.enemies[index].hp, projectile.stats.power, self.enemy_types[self.enemies[index].kind].armor);
            self.enemies[index].hp -= damage; self.credit(projectile.tower, index, damage);
            if self.enemies[index].hp == 0 { self.kill(index, projectile.tower); continue; }
            if projectile.stats.slow_rate > 0 { self.enemies[index].slow.receive(projectile.stats.slow_rate, projectile.stats.slow_time, None); }
            if projectile.stats.burn_amount > 0 { self.enemies[index].burn.receive(projectile.stats.burn_amount, projectile.stats.burn_time, Some(projectile.tower)); }
        }
    }
    fn credit(&mut self, tower: usize, enemy: usize, damage: i64) {
        self.towers[tower].damage += damage; self.enemy_types[self.enemies[enemy].kind].damage += damage;
        *self.records[self.active.unwrap()].tower_damage.entry(tower).or_default() += damage;
    }
    fn kill(&mut self, index: usize, tower: usize) {
        self.enemies[index].alive = false; let cell = self.enemies[index].occupied_cell(); self.kill_counts[cell.1 as usize][cell.0 as usize] += 1;
        let kind = self.enemies[index].kind; let wave = self.active.unwrap(); let bounty = self.enemy_types[kind].bounty;
        self.towers[tower].kills += 1; self.records[wave].kills += 1; self.enemy_types[kind].kills += 1;
        self.gold += bounty; self.records[wave].bounty += bounty; self.income.bounty += bounty;
        let parent_number = self.enemies[index].number;
        self.record(format!("KILL E{parent_number} {} T{} bounty {bounty} gold {}", self.enemy_types[kind].name, self.towers[tower].number, self.gold));
        for _ in 0..self.enemy_types[kind].split_count {
            let child = self.enemies[index].split(self.enemies.len() + 1, &self.enemy_types); let child_kind = child.kind; let number = child.number; let hp = child.hp;
            self.add_enemy(child); self.record(format!("SPAWN E{number} {} E{parent_number} hp {hp}", self.enemy_types[child_kind].name));
        }
    }
    fn check_wave_end(&mut self) {
        let Some(wave) = self.active else { return; };
        if self.enemies.iter().any(|enemy| enemy.alive) || self.records[wave].released.iter().zip(&self.waves[wave].groups).any(|(&released, group)| released != group.count) { return; }
        let reward = self.waves[wave].reward; self.gold += reward;
        let interest = self.params.interest_cap.min(self.gold * self.params.interest_rate / 100); self.gold += interest;
        self.records[wave].reward = reward; self.records[wave].interest = interest; self.income.reward += reward; self.income.interest += interest; self.active = None;
        self.record(format!("WAVE_END {} reward {reward} interest {interest} gold {}", wave + 1, self.gold));
        if wave + 1 == self.waves.len() { self.record("VICTORY".to_owned()); self.outcome = Some(Outcome::Victory); }
        else { self.next_start = Some(self.tick + self.params.interval); }
        self.records[wave].close(WaveStatus::Cleared, self.tick, self.gold, self.lives);
    }
    fn map_picture(&self) -> Vec<Vec<u8>> {
        let mut rows = self.grid.rows.clone();
        for &spawn in &self.grid.spawns { for cell in self.field.path(spawn) { if matches!(self.grid.terrain(cell), b'.' | b'~') { rows[cell.1 as usize][cell.0 as usize] = b'+'; } } }
        for tower in &self.towers { if tower.standing() { rows[tower.cell.1 as usize][tower.cell.0 as usize] = self.tower_types[tower.kind].symbol; } }
        let mut occupants = HashMap::<Cell, (usize, u8)>::new();
        for enemy in &self.enemies { if enemy.alive { let entry = occupants.entry(enemy.occupied_cell()).or_insert((0, self.enemy_types[enemy.kind].symbol)); entry.0 += 1; } }
        for (cell, (count, symbol)) in occupants { rows[cell.1 as usize][cell.0 as usize] = if count == 1 { symbol } else { b'*' }; }
        rows
    }
    fn flow_picture(&self) -> Vec<Vec<u8>> {
        (0..self.grid.height).map(|y| (0..self.grid.width).map(|x| {
            let cell = (x as i64, y as i64); let terrain = self.grid.terrain(cell);
            if matches!(terrain, b'#' | b'E') { terrain }
            else if let Some(tower) = self.tower_at(cell) { self.tower_types[self.towers[tower].kind].symbol }
            else if self.field.at(cell).is_none() { b'?' } else { b"^>v<"[self.field.direction(cell)] }
        }).collect()).collect()
    }
    fn coverage_picture(&self) -> Vec<Vec<u8>> {
        (0..self.grid.height).map(|y| (0..self.grid.width).map(|x| {
            let cell = (x as i64, y as i64);
            if self.grid.is_rock(cell) { b'#' }
            else if let Some(tower) = self.tower_at(cell) { self.tower_types[self.towers[tower].kind].symbol }
            else { digit(self.towers.iter().filter(|tower| tower.standing() && tower.in_range(cell_center(cell), &self.tower_types)).count() as i64) }
        }).collect()).collect()
    }
    fn kills_picture(&self) -> Vec<Vec<u8>> {
        (0..self.grid.height).map(|y| (0..self.grid.width).map(|x| {
            let count = self.kill_counts[y][x]; if count > 0 { digit(count) } else if self.grid.is_rock((x as i64, y as i64)) { b'#' } else { b'.' }
        }).collect()).collect()
    }
    fn block(&self, label: &str) -> Vec<String> {
        let next = if self.active.is_none() && self.outcome.is_none() { self.next_start.unwrap().to_string() } else { "-".to_owned() };
        let mut lines = vec![format!("{label} {} wave {} next {next} gold {} lives {}", self.tick, self.records.len(), self.gold, self.lives)];
        lines.extend(ruled(&self.map_picture()));
        for (number, &spawn) in self.grid.spawns.iter().enumerate() { lines.push(format!("PATH {} length {}", number + 1, self.field.at(spawn).unwrap())); }
        for tower in &self.towers { if tower.standing() { lines.push(format!("T{} {} {} {} level {} mode {} ready {}", tower.number, self.tower_types[tower.kind].name, tower.cell.0, tower.cell.1, tower.level + 1, tower.mode.text(), tower.ready)); } }
        for enemy in &self.enemies { if enemy.alive { let point = enemy.point(); lines.push(format!("E{} {} {} {} hp {}/{} slow {} {} burn {} {}", enemy.number, self.enemy_types[enemy.kind].name, point.0, point.1, enemy.hp, enemy.max_hp, enemy.slow.strength, enemy.slow.remaining, enemy.burn.strength, enemy.burn.remaining)); } }
        for projectile in &self.projectiles { lines.push(format!("P{} T{} E{} {} {}", projectile.number, self.towers[projectile.tower].number, self.enemies[projectile.target].number, projectile.position.0, projectile.position.1)); }
        lines
    }
    fn final_block(&self) -> Vec<String> {
        let mut lines = self.block("FINAL");
        lines.push("FLOW".to_owned()); lines.extend(ruled(&self.flow_picture()));
        lines.push("COVERAGE".to_owned()); lines.extend(ruled(&self.coverage_picture()));
        lines.push("KILLS".to_owned()); lines.extend(ruled(&self.kills_picture()));
        lines
    }
    fn wave_lines(&self) -> Vec<String> {
        let mut header = WAVE_COLUMNS.to_owned(); for tower in &self.towers { header += &format!(",T{}", tower.number); }
        let mut lines = vec![header]; lines.extend(self.records.iter().map(|wave| wave.csv_row(self.towers.len()))); lines
    }
    fn summary_lines(&self, action_count: usize) -> Vec<String> {
        let cleared = self.records.iter().filter(|wave| wave.status == WaveStatus::Cleared).count(); let perfect = self.records.iter().filter(|wave| wave.status == WaveStatus::Cleared && wave.leaks == 0).count();
        let spawned: i64 = self.enemy_types.iter().map(|kind| kind.spawned).sum(); let killed: i64 = self.enemy_types.iter().map(|kind| kind.kills).sum(); let leaked: i64 = self.enemy_types.iter().map(|kind| kind.leaks).sum();
        let total_damage: i64 = self.towers.iter().map(|tower| tower.damage).sum(); let score = 10 * killed + 100 * self.lives + 50 * perfect as i64 + self.gold;
        let mut lines = vec![format!("outcome {}", self.outcome.unwrap().text()), format!("ticks {}", self.tick), format!("waves {cleared}/{} perfect {perfect}", self.waves.len()), format!("lives {}/{}", self.lives, self.params.lives), format!("gold {}", self.gold),
            format!("enemies spawned {spawned} killed {killed} leaked {leaked}"), format!("income bounty {} reward {} interest {} early {} refund {}", self.income.bounty, self.income.reward, self.income.interest, self.income.early, self.income.refund),
            format!("spent {}", self.spent), format!("damage {total_damage}"), format!("actions total {action_count} done {} refused {} unused {}", self.done, self.refused, action_count - self.done - self.refused), format!("score {score}")];
        let mut best: Option<usize> = None;
        for (index, tower) in self.towers.iter().enumerate() { if best.map(|before| tower.damage > self.towers[before].damage).unwrap_or(true) { best = Some(index); } }
        lines.push(if let Some(index) = best { format!("mvp T{} damage {}", self.towers[index].number, self.towers[index].damage) } else { "mvp -".to_owned() });
        for kind in &self.enemy_types { lines.push(format!("ENEMY {} spawned {} killed {} leaked {} damage {}", kind.name, kind.spawned, kind.kills, kind.leaks, kind.damage)); }
        for tower in &self.towers {
            let state = tower.sold.map(|tick| format!("sold {tick}")).unwrap_or_else(|| "active".to_owned());
            lines.push(format!("TOWER T{} {} {} {} level {} mode {} {state} shots {} hits {} fizzles {} kills {} damage {} per_shot {} share {} invested {}", tower.number, self.tower_types[tower.kind].name, tower.cell.0, tower.cell.1, tower.level + 1, tower.mode.text(), tower.shots, tower.hits, tower.fizzles, tower.kills, tower.damage, one_decimal(tower.damage, tower.shots), one_decimal(100 * tower.damage, total_damage), tower.investment));
        }
        lines
    }
}
fn main() -> io::Result<()> {
    let grid = GridMap::read("input/map.txt")?; let tower_types = parse_tower_types(&read_lines("towers.txt")?);
    let (enemy_types, waves) = parse_waves(&read_lines("waves.txt")?); let actions: Vec<Action> = read_lines("actions.txt")?.iter().map(|line| Action::parse(line)).collect();
    let params = Params::new(&read_lines("params.txt")?); let mut game = Game::new(grid, tower_types, enemy_types, waves, params); game.run(&actions);
    fs::create_dir_all("output")?;
    write_lines("events.txt", &game.events)?; write_lines("waves.csv", &game.wave_lines())?;
    write_lines("snapshots.txt", &game.snapshots)?; write_lines("summary.txt", &game.summary_lines(actions.len()))
}
