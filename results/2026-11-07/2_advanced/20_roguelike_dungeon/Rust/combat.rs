use crate::minstd::Minstd;

#[derive(Clone, Copy)]
pub struct Dice { pub count: usize, pub sides: usize }
impl Dice {
    pub fn parse(text: &str) -> Self {
        let (count, sides) = text.split_once('d').unwrap();
        Self { count: count.parse().unwrap(), sides: sides.parse().unwrap() }
    }
    pub fn roll(self, generator: &mut Minstd) -> i64 { generator.roll(self.count, self.sides) }
}
#[derive(Clone, Copy, PartialEq)]
pub enum AttackOutcome { Miss, Hit, Critical }
pub fn resolve_attack(generator: &mut Minstd, to_hit: i64, defense: i64, dice: Dice, bonus: i64) -> (AttackOutcome, i64) {
    let roll = 1 + generator.rnd(20) as i64;
    if roll == 1 { return (AttackOutcome::Miss, 0); }
    if roll == 20 { return (AttackOutcome::Critical, (dice.roll(generator) + dice.roll(generator) + bonus).max(1)); }
    if roll + to_hit >= defense { (AttackOutcome::Hit, (dice.roll(generator) + bonus).max(1)) }
    else { (AttackOutcome::Miss, 0) }
}
