use std::collections::BTreeSet;

pub type Point = (i64, i64);
pub type Mask = Vec<Vec<bool>>;
pub const NEIGHBORHOOD: [Point; 8] = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)];

pub fn occupied(mask: &[Vec<bool>], x: i64, y: i64) -> bool {
    y >= 0 && y < mask.len() as i64 && x >= 0 && x < mask[0].len() as i64 && mask[y as usize][x as usize]
}

pub fn erode(mask: &[Vec<bool>], offsets: &[Point]) -> Mask {
    mask.iter().enumerate().map(|(y, row)| (0..row.len()).map(|x|
        offsets.iter().all(|&(dx, dy)| occupied(mask, x as i64 + dx, y as i64 + dy))).collect()).collect()
}

pub fn dilate(mask: &[Vec<bool>], offsets: &[Point]) -> Mask {
    mask.iter().enumerate().map(|(y, row)| (0..row.len()).map(|x|
        offsets.iter().any(|&(dx, dy)| occupied(mask, x as i64 - dx, y as i64 - dy))).collect()).collect()
}

pub fn opening(mask: &[Vec<bool>], offsets: &[Point]) -> Mask { dilate(&erode(mask, offsets), offsets) }
pub fn closing(mask: &[Vec<bool>], offsets: &[Point]) -> Mask { erode(&dilate(mask, offsets), offsets) }

fn neighbor_bits(pixels: &BTreeSet<Point>, point: Point) -> [bool; 8] {
    NEIGHBORHOOD.map(|(dx, dy)| pixels.contains(&(point.0 + dx, point.1 + dy)))
}

fn transitions(bits: &[bool; 8]) -> usize {
    (0..8).filter(|&index| !bits[index] && bits[(index + 1) % 8]).count()
}

pub fn crossing_number(pixels: &BTreeSet<Point>, point: Point) -> usize { transitions(&neighbor_bits(pixels, point)) }

fn removable(bits: &[bool; 8], first: bool) -> bool {
    let count = bits.iter().filter(|&&bit| bit).count();
    if !(2..=6).contains(&count) || transitions(bits) != 1 { return false; }
    let (p2, p4, p6, p8) = (bits[0], bits[2], bits[4], bits[6]);
    if first { !(p2 && p4 && p6) && !(p4 && p6 && p8) }
    else { !(p2 && p4 && p8) && !(p2 && p6 && p8) }
}

fn thinning_step(pixels: &mut BTreeSet<Point>, first: bool) -> bool {
    let removed: Vec<_> = pixels.iter().copied().filter(|&point| removable(&neighbor_bits(pixels, point), first)).collect();
    for point in &removed { pixels.remove(point); }
    !removed.is_empty()
}

pub fn thin(pixels: &[Point]) -> BTreeSet<Point> {
    let mut skeleton = pixels.iter().copied().collect();
    loop {
        let first = thinning_step(&mut skeleton, true);
        let second = thinning_step(&mut skeleton, false);
        if !first && !second { return skeleton; }
    }
}
