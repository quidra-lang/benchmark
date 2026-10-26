use crate::combat::Dice;

pub struct MonsterType {
    pub name: String,
    pub symbol: u8,
    pub min_depth: usize,
    pub max_depth: usize,
    pub weight: usize,
    pub hp: Dice,
    pub to_hit: i64,
    pub defense: i64,
    pub damage: Dice,
    pub speed: i64,
    pub xp: i64,
    pub erratic: bool,
    pub stationary: bool,
    pub regenerates: bool,
    pub poisonous: bool,
}
impl MonsterType {
    pub fn parse(words: &[&str]) -> Self {
        Self { name: words[0].to_owned(), symbol: words[1].as_bytes()[0], min_depth: words[2].parse().unwrap(),
            max_depth: words[3].parse().unwrap(), weight: words[4].parse().unwrap(), hp: Dice::parse(words[5]),
            to_hit: words[6].parse().unwrap(), defense: words[7].parse().unwrap(), damage: Dice::parse(words[8]),
            speed: words[9].parse().unwrap(), xp: words[10].parse().unwrap(), erratic: words[11].contains('E'),
            stationary: words[11].contains('S'), regenerates: words[11].contains('R'), poisonous: words[11].contains('P') }
    }
}
#[derive(Clone, Copy)]
pub enum PotionEffect { Heal(Dice), Poison(i64), Level }
#[derive(Clone, Copy)]
pub enum ScrollEffect { Mapping, Teleport, EnchantWeapon, EnchantArmor }
#[derive(Clone, Copy)]
pub enum ItemClass {
    Weapon { damage: Dice, to_hit: i64 }, Armor(i64), Potion(PotionEffect), Scroll(ScrollEffect), Food(i64), Gold(Dice), Amulet,
}
pub struct ItemType {
    pub name: String,
    pub min_depth: usize,
    pub max_depth: usize,
    pub weight: usize,
    pub class: ItemClass,
}
impl ItemType {
    pub fn parse(words: &[&str]) -> Self {
        let class = match words[0] {
            "weapon" => ItemClass::Weapon { damage: Dice::parse(words[5]), to_hit: words[6].parse().unwrap() },
            "armor" => ItemClass::Armor(words[5].parse().unwrap()),
            "potion" => ItemClass::Potion(match words[5] {
                "heal" => PotionEffect::Heal(Dice::parse(words[6])), "poison" => PotionEffect::Poison(words[6].parse().unwrap()),
                "level" => PotionEffect::Level, _ => unreachable!(),
            }),
            "scroll" => ItemClass::Scroll(match words[5] {
                "mapping" => ScrollEffect::Mapping, "teleport" => ScrollEffect::Teleport,
                "enchant_weapon" => ScrollEffect::EnchantWeapon, "enchant_armor" => ScrollEffect::EnchantArmor, _ => unreachable!(),
            }),
            "food" => ItemClass::Food(words[5].parse().unwrap()), "gold" => ItemClass::Gold(Dice::parse(words[5])), _ => unreachable!(),
        };
        Self { name: words[1].to_owned(), min_depth: words[2].parse().unwrap(), max_depth: words[3].parse().unwrap(), weight: words[4].parse().unwrap(), class }
    }
    pub fn amulet() -> Self { Self { name: "amulet".to_owned(), min_depth: 0, max_depth: 0, weight: 0, class: ItemClass::Amulet } }
    pub fn symbol(&self) -> u8 {
        match self.class { ItemClass::Weapon { .. } => b')', ItemClass::Armor(_) => b'[', ItemClass::Potion(_) => b'!',
            ItemClass::Scroll(_) => b'?', ItemClass::Food(_) => b'%', ItemClass::Gold(_) => b'$', ItemClass::Amulet => b'"' }
    }
}
#[derive(Clone)]
pub struct Monster {
    pub number: usize,
    pub kind: usize,
    pub x: i32,
    pub y: i32,
    pub hp: i64,
    pub max_hp: i64,
    pub asleep: bool,
    pub energy: i64,
    pub was_visible: bool,
}
#[derive(Clone)]
pub struct Item { pub kind: usize, pub x: i32, pub y: i32, pub bonus: i64, pub amount: i64 }
impl Item {
    pub fn new(kind: usize, x: i32, y: i32, amount: i64) -> Self { Self { kind, x, y, bonus: 0, amount } }
    pub fn display_name(&self, kinds: &[ItemType]) -> String {
        let kind = &kinds[self.kind];
        let name = kind.name.replace('_', " ");
        match kind.class { ItemClass::Weapon { .. } | ItemClass::Armor(_) => format!("+{} {name}", self.bonus),
            ItemClass::Gold(_) => format!("{} gold", self.amount), _ => name }
    }
    pub fn reference_name(&self, kinds: &[ItemType]) -> String {
        let name = self.display_name(kinds);
        if matches!(kinds[self.kind].class, ItemClass::Gold(_)) { name } else { format!("the {name}") }
    }
}
