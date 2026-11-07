use std::collections::HashMap;
use crate::combat::{Effect, integer_sqrt, squared_distance};
use crate::grid_map::{Cell, Point, cell_center};
use crate::pathing::DistanceField;

#[derive(Clone, Copy, PartialEq)]
pub enum Movement { Ground, Air }
pub struct EnemyType {
    pub name: String, pub symbol: u8, pub movement: Movement, pub hp: i64, pub armor: i64,
    pub speed: i64, pub bounty: i64, pub lives: i64, pub regen: i64,
    pub split_into: Option<usize>, pub split_count: usize, pub spawned: i64, pub kills: i64, pub leaks: i64, pub damage: i64,
}
#[derive(Clone, Copy)]
pub struct Group { pub kind: usize, pub spawn: usize, pub count: usize, pub delay: i64, pub interval: i64, pub multiplier: i64 }
impl Group { pub fn spawn_tick(&self, start: i64, index: usize) -> i64 { start + self.delay + index as i64 * self.interval } }
pub struct Wave { pub reward: i64, pub groups: Vec<Group> }
impl Wave { pub fn enemy_count(&self) -> usize { self.groups.iter().map(|group| group.count).sum() } }
pub fn parse_waves(lines: &[String]) -> (Vec<EnemyType>, Vec<Wave>) {
    let mut types = Vec::new();
    let mut known = HashMap::new();
    let mut waves: Vec<Wave> = Vec::new();
    for line in lines {
        let fields: Vec<&str> = line.split(' ').collect();
        if fields[0] == "enemy" {
            let split_into = if fields[10] == "-" { None } else { Some(known[fields[10]]) };
            known.insert(fields[1].to_owned(), types.len());
            types.push(EnemyType { name: fields[1].to_owned(), symbol: fields[2].as_bytes()[0], movement: if fields[3] == "air" { Movement::Air } else { Movement::Ground },
                hp: fields[4].parse().unwrap(), armor: fields[5].parse().unwrap(), speed: fields[6].parse().unwrap(), bounty: fields[7].parse().unwrap(), lives: fields[8].parse().unwrap(), regen: fields[9].parse().unwrap(),
                split_into, split_count: fields[11].parse().unwrap(), spawned: 0, kills: 0, leaks: 0, damage: 0 });
        } else if fields[0] == "wave" { waves.push(Wave { reward: fields[1].parse().unwrap(), groups: Vec::new() }); }
        else { waves.last_mut().unwrap().groups.push(Group { kind: known[fields[1]], spawn: fields[2].parse::<usize>().unwrap() - 1, count: fields[3].parse().unwrap(), delay: fields[4].parse().unwrap(), interval: fields[5].parse().unwrap(), multiplier: fields[6].parse().unwrap() }); }
    }
    (types, waves)
}
#[derive(Clone, Copy)]
pub enum Position { Ground { cell: Cell, next: Cell, progress: i64 }, Air(Point) }
pub struct Enemy { pub number: usize, pub kind: usize, pub multiplier: i64, pub max_hp: i64, pub hp: i64, pub slow: Effect, pub burn: Effect, pub alive: bool, pub position: Position }
impl Enemy {
    pub fn new(number: usize, kind: usize, types: &[EnemyType], multiplier: i64, position: Position) -> Self {
        let hp = types[kind].hp * multiplier / 100;
        Self { number, kind, multiplier, max_hp: hp, hp, slow: Effect::default(), burn: Effect::default(), alive: true, position }
    }
    pub fn flying(&self) -> bool { matches!(self.position, Position::Air(_)) }
    pub fn point(&self) -> Point {
        match self.position { Position::Air(point) => point, Position::Ground { cell, next, progress } => (100 * cell.0 + (next.0 - cell.0) * progress, 100 * cell.1 + (next.1 - cell.1) * progress) }
    }
    pub fn occupied_cell(&self) -> Cell {
        match self.position { Position::Air(point) => ((point.0 + 50) / 100, (point.1 + 50) / 100), Position::Ground { cell, next, progress } => if progress < 50 { cell } else { next } }
    }
    pub fn remaining(&self, field: &DistanceField) -> i64 {
        match self.position { Position::Air(point) => integer_sqrt(squared_distance(point, cell_center(field.exit))), Position::Ground { next, progress, .. } => 100 * field.at(next).unwrap() + 100 - progress }
    }
    pub fn slowed_speed(&self, types: &[EnemyType]) -> i64 { let speed = types[self.kind].speed; if self.slow.active() { speed * (100 - self.slow.strength) / 100 } else { speed } }
    pub fn split(&self, number: usize, types: &[EnemyType]) -> Self { Self::new(number, types[self.kind].split_into.unwrap(), types, self.multiplier, self.position) }
}
