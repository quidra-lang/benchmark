use crate::song_parser::{Cell, Song};
use std::collections::BTreeSet;

pub fn samples_per_tick(rate: i64, tempo: i64) -> usize { (rate * 5 / (tempo * 2)) as usize }

pub fn next_row(song: &Song, position: usize, row: usize, cells: &[Cell; 4]) -> (Option<(usize, usize)>, bool) {
    let mut jump = None;
    let mut pattern_break = None;
    let mut stop = false;
    for cell in cells {
        if let Some(effect) = &cell.effect {
            match effect.command {
                b'F' if effect.argument == 0 => stop = true,
                b'B' => jump = Some(effect.argument as usize),
                b'D' => pattern_break = Some(if effect.argument >= 64 { 0 } else { effect.argument as usize }),
                _ => (),
            }
        }
    }
    if stop { return (None, true); }
    let next = if jump.is_some() || pattern_break.is_some() { (jump.unwrap_or(position + 1), pattern_break.unwrap_or(0)) }
        else if row < 63 { (position, row + 1) } else { (position + 1, 0) };
    (if next.0 < song.order.len() { Some(next) } else { None }, false)
}

pub fn reachable(song: &Song) -> BTreeSet<(usize, usize)> {
    let mut visited = BTreeSet::new();
    let mut current = Some((0, 0));
    while let Some((position, row)) = current {
        if !visited.insert((position, row)) { break; }
        current = next_row(song, position, row, &song.patterns[&song.order[position]][row]).0;
    }
    visited
}
