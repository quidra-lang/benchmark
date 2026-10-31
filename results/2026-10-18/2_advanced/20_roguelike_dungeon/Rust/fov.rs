use std::collections::VecDeque;
use crate::dungeon_gen::Level;

pub const DIRECTION_NAMES: [&str; 8] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
pub const DIRECTIONS: [(i32, i32); 8] = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)];
pub fn passable(level: &Level, x: i32, y: i32) -> bool {
    x >= 0 && x < level.width as i32 && y >= 0 && y < level.height as i32 && matches!(level.terrain[y as usize][x as usize], b'.' | b'#' | b'+' | b'<' | b'>')
}
pub fn can_move(level: &Level, x: i32, y: i32, dx: i32, dy: i32) -> bool {
    passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || (level.terrain[y as usize][x as usize] != b'+' && level.terrain[(y + dy) as usize][(x + dx) as usize] != b'+'))
}
pub fn line(x0: i32, y0: i32, x1: i32, y1: i32) -> Vec<(i32, i32)> {
    let (dx, dy) = ((x1 - x0).abs(), (y1 - y0).abs());
    let sx = if x1 > x0 { 1 } else { -1 };
    let sy = if y1 > y0 { 1 } else { -1 };
    let (mut error, mut x, mut y) = (dx - dy, x0, y0);
    let mut cells = Vec::new();
    while (x, y) != (x1, y1) {
        let twice = 2 * error;
        if twice > -dy { error -= dy; x += sx; }
        if twice < dx { error += dx; y += sy; }
        cells.push((x, y));
    }
    cells
}
pub fn field_of_view(level: &Level, px: i32, py: i32, radius: i32) -> Vec<Vec<bool>> {
    let mut visible = vec![vec![false; level.width]; level.height];
    for y in 0.max(py - radius)..(level.height as i32).min(py + radius + 1) {
        for x in 0.max(px - radius)..(level.width as i32).min(px + radius + 1) {
            if (x - px) * (x - px) + (y - py) * (y - py) > radius * radius { continue; }
            let cells = line(px, py, x, y);
            if cells.iter().take(cells.len().saturating_sub(1)).all(|&(cx, cy)| passable(level, cx, cy)) { visible[y as usize][x as usize] = true; }
        }
    }
    visible
}
pub fn distances(level: &Level, px: i32, py: i32) -> Vec<Vec<Option<usize>>> {
    let mut distance = vec![vec![None; level.width]; level.height];
    distance[py as usize][px as usize] = Some(0);
    let mut queue = VecDeque::from([(px, py)]);
    while let Some((x, y)) = queue.pop_front() {
        for (dx, dy) in DIRECTIONS {
            if can_move(level, x, y, dx, dy) && distance[(y + dy) as usize][(x + dx) as usize].is_none() {
                distance[(y + dy) as usize][(x + dx) as usize] = Some(distance[y as usize][x as usize].unwrap() + 1);
                queue.push_back((x + dx, y + dy));
            }
        }
    }
    distance
}
