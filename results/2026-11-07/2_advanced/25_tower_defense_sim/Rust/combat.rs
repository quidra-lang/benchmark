use crate::grid_map::Point;
use crate::towers::{Level, Targets};

pub fn squared_distance(first: Point, second: Point) -> i64 { let dx = first.0 - second.0; let dy = first.1 - second.1; dx * dx + dy * dy }
pub fn integer_sqrt(value: i64) -> i64 {
    let (mut low, mut high) = (0, value + 1);
    while low + 1 < high { let middle = (low + high) / 2; if middle <= value / middle { low = middle; } else { high = middle; } }
    low
}
pub fn advance(point: Point, goal: Point, step: i64) -> (Point, bool) {
    let (dx, dy) = (goal.0 - point.0, goal.1 - point.1);
    let squared = dx * dx + dy * dy;
    if squared <= step * step { return (goal, true); }
    let length = integer_sqrt(squared);
    ((point.0 + dx * step / length, point.1 + dy * step / length), false)
}
pub fn damage_dealt(hp: i64, power: i64, armor: i64) -> i64 { hp.min((power - armor).max(1)) }
#[derive(Clone, Copy, Default)]
pub struct Effect { pub strength: i64, pub remaining: i64, pub source: Option<usize> }
impl Effect {
    pub fn active(&self) -> bool { self.remaining > 0 }
    pub fn receive(&mut self, strength: i64, duration: i64, source: Option<usize>) {
        if strength > self.strength { self.strength = strength; self.remaining = duration; self.source = source; }
        else if strength == self.strength { self.remaining = self.remaining.max(duration); }
    }
    pub fn advance_time(&mut self) { self.remaining -= 1; if self.remaining == 0 { self.strength = 0; self.source = None; } }
}
pub struct Projectile { pub number: usize, pub tower: usize, pub target: usize, pub position: Point, pub aim: Point, pub targets: Targets, pub stats: Level }
impl Projectile {
    pub fn fly(&mut self) -> bool {
        if self.stats.shot_speed == 0 { return true; }
        let (point, arrived) = advance(self.position, self.aim, self.stats.shot_speed);
        self.position = point;
        arrived
    }
}
