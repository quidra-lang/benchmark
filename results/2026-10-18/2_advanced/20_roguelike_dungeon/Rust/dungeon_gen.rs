use crate::entities::{Item, Monster};
use crate::minstd::Minstd;

#[derive(Clone, Copy)]
pub struct Room { pub x: i32, pub y: i32, pub width: usize, pub height: usize }
impl Room { pub fn center(self) -> (i32, i32) { (self.x + (self.width / 2) as i32, self.y + (self.height / 2) as i32) } }
struct Region { rectangle: Room, first: Option<usize>, second: Option<usize>, leaf: Option<usize> }
pub struct Level {
    pub depth: usize,
    pub width: usize,
    pub height: usize,
    pub terrain: Vec<Vec<u8>>,
    pub memory: Vec<Vec<u8>>,
    pub rooms: Vec<Room>,
    pub arrival: (i32, i32),
    pub arrival_room: usize,
    pub target: (i32, i32),
    pub monsters: Vec<Monster>,
    pub items: Vec<Item>,
    pub monsters_created: usize,
    pub items_placed: usize,
    pub kills: usize,
    pub picked: usize,
}
impl Level {
    fn new(depth: usize, width: usize, height: usize) -> Self {
        Self { depth, width, height, terrain: vec![vec![b' '; width]; height], memory: vec![vec![b' '; width]; height], rooms: Vec::new(),
            arrival: (0, 0), arrival_room: 0, target: (0, 0), monsters: Vec::new(), items: Vec::new(), monsters_created: 0, items_placed: 0, kills: 0, picked: 0 }
    }
    pub fn monster_at(&self, x: i32, y: i32) -> Option<usize> { self.monsters.iter().position(|monster| monster.x == x && monster.y == y) }
    pub fn item_at(&self, x: i32, y: i32) -> Option<usize> { self.items.iter().position(|item| item.x == x && item.y == y) }
    pub fn draw_interior_cell(&self, generator: &mut Minstd, index: usize) -> (i32, i32) {
        let room = self.rooms[index];
        let x = room.x + 1 + generator.rnd(room.width - 2) as i32;
        let y = room.y + 1 + generator.rnd(room.height - 2) as i32;
        (x, y)
    }
    pub fn draw_room_cell(&self, generator: &mut Minstd) -> (usize, i32, i32) {
        let room = generator.rnd(self.rooms.len());
        let (x, y) = self.draw_interior_cell(generator, room);
        (room, x, y)
    }
}

pub struct LevelGenerator { pub minimum: usize, pub max_split: usize, pub room_min: usize, pub room_max: usize }
impl LevelGenerator {
    pub fn generate(&self, generator: &mut Minstd, depth: usize, width: usize, height: usize) -> Level {
        let mut level = Level::new(depth, width, height);
        let mut tree = vec![Region { rectangle: Room { x: 0, y: 0, width, height }, first: None, second: None, leaf: None }];
        let mut leaves = Vec::new();
        self.split(generator, &mut tree, 0, 0, &mut leaves);
        for leaf in leaves {
            let room = self.make_room(generator, &mut level, tree[leaf].rectangle);
            level.rooms.push(room);
        }
        Self::connect(generator, &mut level, &tree, 0);
        let (room, x, y) = level.draw_room_cell(generator);
        level.terrain[y as usize][x as usize] = b'<';
        level.arrival = (x, y);
        level.arrival_room = room;
        let mut other = generator.rnd(level.rooms.len() - 1);
        if other >= room { other += 1; }
        level.target = level.draw_interior_cell(generator, other);
        level
    }
    fn split(&self, generator: &mut Minstd, tree: &mut Vec<Region>, node: usize, depth: usize, leaves: &mut Vec<usize>) {
        let r = tree[node].rectangle;
        let (cv, ch) = (r.width >= 2 * self.minimum, r.height >= 2 * self.minimum);
        if depth == self.max_split || !(cv || ch) { tree[node].leaf = Some(leaves.len()); leaves.push(node); return; }
        let vertical = if cv && ch {
            if 4 * r.width >= 5 * r.height { true } else if 4 * r.height >= 5 * r.width { false } else { generator.draw() % 2 == 0 }
        } else { cv };
        let (a, b) = if vertical {
            let cut = self.minimum + generator.rnd(r.width - 2 * self.minimum + 1);
            (Room { width: cut, ..r }, Room { x: r.x + cut as i32, width: r.width - cut, ..r })
        } else {
            let cut = self.minimum + generator.rnd(r.height - 2 * self.minimum + 1);
            (Room { height: cut, ..r }, Room { y: r.y + cut as i32, height: r.height - cut, ..r })
        };
        let first = tree.len();
        tree.push(Region { rectangle: a, first: None, second: None, leaf: None });
        let second = tree.len();
        tree.push(Region { rectangle: b, first: None, second: None, leaf: None });
        tree[node].first = Some(first);
        tree[node].second = Some(second);
        self.split(generator, tree, first, depth + 1, leaves);
        self.split(generator, tree, second, depth + 1, leaves);
    }
    fn make_room(&self, generator: &mut Minstd, level: &mut Level, region: Room) -> Room {
        let width = self.room_min + generator.rnd(self.room_max.min(region.width - 1) - self.room_min + 1);
        let height = self.room_min + generator.rnd(self.room_max.min(region.height - 1) - self.room_min + 1);
        let x = region.x + generator.rnd(region.width - width) as i32;
        let y = region.y + generator.rnd(region.height - height) as i32;
        for row in y..y + height as i32 { for column in x..x + width as i32 {
            level.terrain[row as usize][column as usize] = if row == y || row == y + height as i32 - 1 { b'-' }
                else if column == x || column == x + width as i32 - 1 { b'|' } else { b'.' };
        } }
        Room { x, y, width, height }
    }
    fn connect(generator: &mut Minstd, level: &mut Level, tree: &[Region], node: usize) -> Vec<usize> {
        if let Some(leaf) = tree[node].leaf { return vec![leaf]; }
        let first = Self::connect(generator, level, tree, tree[node].first.unwrap());
        let second = Self::connect(generator, level, tree, tree[node].second.unwrap());
        let mut best = None;
        for &a in &first { for &b in &second {
            let (ax, ay) = level.rooms[a].center();
            let (bx, by) = level.rooms[b].center();
            let candidate = ((ax - bx).abs() + (ay - by).abs(), a, b);
            if best.is_none_or(|previous| candidate < previous) { best = Some(candidate); }
        } }
        let (_, a, b) = best.unwrap();
        let horizontal = generator.draw() % 2 == 0;
        let start = level.rooms[a].center();
        let end = level.rooms[b].center();
        Self::dig(level, start, end, horizontal);
        first.into_iter().chain(second).collect()
    }
    fn dig(level: &mut Level, (ax, ay): (i32, i32), (bx, by): (i32, i32), horizontal: bool) {
        let span = |start: i32, end: i32| {
            let step = if end >= start { 1 } else { -1 };
            (0..=(end - start).abs()).map(move |offset| start + offset * step)
        };
        let path: Vec<_> = if horizontal { span(ax, bx).map(|x| (x, ay)).chain(span(ay, by).map(|y| (bx, y))).collect() }
            else { span(ay, by).map(|y| (ax, y)).chain(span(ax, bx).map(|x| (x, by))).collect() };
        for (x, y) in path {
            let terrain = &mut level.terrain[y as usize][x as usize];
            if *terrain == b' ' { *terrain = b'#'; } else if *terrain == b'-' || *terrain == b'|' { *terrain = b'+'; }
        }
    }
}
