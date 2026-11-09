use crate::combat::squared_distance;
use crate::enemies::{Enemy, EnemyType, Movement};
use crate::grid_map::{Cell, Point, cell_center};
use crate::pathing::DistanceField;

#[derive(Clone, Copy)]
pub enum Targets { Ground, Air, Both }
impl Targets {
    pub fn parse(text: &str) -> Self { match text { "ground" => Self::Ground, "air" => Self::Air, _ => Self::Both } }
    pub fn can_aim(self, movement: Movement) -> bool { match self { Self::Ground => movement == Movement::Ground, Self::Air => movement == Movement::Air, Self::Both => true } }
}
#[derive(Clone, Copy)]
pub struct Level { pub cost: i64, pub range: i64, pub power: i64, pub interval: i64, pub shot_speed: i64, pub splash: i64, pub slow_rate: i64, pub slow_time: i64, pub burn_amount: i64, pub burn_time: i64 }
pub struct TowerType { pub name: String, pub symbol: u8, pub targets: Targets, pub levels: Vec<Level> }
pub fn parse_tower_types(lines: &[String]) -> Vec<TowerType> {
    let mut types = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        let fields: Vec<&str> = lines[index].split(' ').collect();
        let count: usize = fields[4].parse().unwrap();
        let mut levels = Vec::new();
        for line in &lines[index + 1..index + 1 + count] {
            let values: Vec<i64> = line.split(' ').skip(1).map(|value| value.parse().unwrap()).collect();
            levels.push(Level { cost: values[0], range: values[1], power: values[2], interval: values[3], shot_speed: values[4], splash: values[5], slow_rate: values[6], slow_time: values[7], burn_amount: values[8], burn_time: values[9] });
        }
        types.push(TowerType { name: fields[1].to_owned(), symbol: fields[2].as_bytes()[0], targets: Targets::parse(fields[3]), levels });
        index += count + 1;
    }
    types
}
#[derive(Clone, Copy)]
pub enum TargetMode { First, Last, Strongest, Weakest, Closest }
impl TargetMode {
    pub fn parse(text: &str) -> Option<Self> { match text { "FIRST" => Some(Self::First), "LAST" => Some(Self::Last), "STRONGEST" => Some(Self::Strongest), "WEAKEST" => Some(Self::Weakest), "CLOSEST" => Some(Self::Closest), _ => None } }
    pub fn text(self) -> &'static str { match self { Self::First => "FIRST", Self::Last => "LAST", Self::Strongest => "STRONGEST", Self::Weakest => "WEAKEST", Self::Closest => "CLOSEST" } }
}
pub struct Tower {
    pub number: usize, pub kind: usize, pub cell: Cell, pub level: usize, pub mode: TargetMode,
    pub ready: i64, pub investment: i64, pub built: i64, pub sold: Option<i64>,
    pub shots: i64, pub hits: i64, pub fizzles: i64, pub kills: i64, pub damage: i64,
}
impl Tower {
    pub fn new(number: usize, kind: usize, types: &[TowerType], cell: Cell, tick: i64) -> Self { Self { number, kind, cell, level: 0, mode: TargetMode::First, ready: tick, investment: types[kind].levels[0].cost, built: tick, sold: None, shots: 0, hits: 0, fizzles: 0, kills: 0, damage: 0 } }
    pub fn standing(&self) -> bool { self.sold.is_none() }
    pub fn center(&self) -> Point { cell_center(self.cell) }
    pub fn stats(&self, types: &[TowerType]) -> Level { types[self.kind].levels[self.level] }
    pub fn in_range(&self, point: Point, types: &[TowerType]) -> bool { let reach = self.stats(types).range; squared_distance(self.center(), point) <= reach * reach }
    pub fn select_target(&self, enemies: &[Enemy], types: &[EnemyType], tower_types: &[TowerType], field: &DistanceField) -> Option<usize> {
        let mut best: Option<(i64, usize)> = None;
        for (index, enemy) in enemies.iter().enumerate() {
            if !enemy.alive || !tower_types[self.kind].targets.can_aim(types[enemy.kind].movement) || !self.in_range(enemy.point(), tower_types) { continue; }
            let key = match self.mode { TargetMode::First => enemy.remaining(field), TargetMode::Last => -enemy.remaining(field), TargetMode::Strongest => -enemy.hp, TargetMode::Weakest => enemy.hp, TargetMode::Closest => squared_distance(self.center(), enemy.point()) };
            if best.map(|value| key < value.0).unwrap_or(true) { best = Some((key, index)); }
        }
        best.map(|value| value.1)
    }
}
