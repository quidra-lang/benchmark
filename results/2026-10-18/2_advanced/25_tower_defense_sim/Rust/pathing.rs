use std::collections::{HashSet, VecDeque};
use crate::grid_map::{Cell, GridMap};

pub const DIRECTIONS: [Cell; 4] = [(0, -1), (1, 0), (0, 1), (-1, 0)];
pub fn neighbor(cell: Cell, direction: usize) -> Cell { (cell.0 + DIRECTIONS[direction].0, cell.1 + DIRECTIONS[direction].1) }
pub struct DistanceField { pub dist: Vec<Vec<Option<i64>>>, pub exit: Cell, width: usize, height: usize }
impl DistanceField {
    pub fn new(grid: &GridMap, towers: &HashSet<Cell>) -> Self {
        let mut result = Self { dist: vec![vec![None; grid.width]; grid.height], exit: grid.exit, width: grid.width, height: grid.height };
        result.dist[grid.exit.1 as usize][grid.exit.0 as usize] = Some(0);
        let mut queue = VecDeque::from([grid.exit]);
        while let Some(cell) = queue.pop_front() {
            for direction in 0..4 {
                let next = neighbor(cell, direction);
                if grid.inside(next) && !grid.is_rock(next) && !towers.contains(&next) && result.at(next).is_none() {
                    result.dist[next.1 as usize][next.0 as usize] = Some(result.at(cell).unwrap() + 1);
                    queue.push_back(next);
                }
            }
        }
        result
    }
    pub fn at(&self, cell: Cell) -> Option<i64> { self.dist[cell.1 as usize][cell.0 as usize] }
    pub fn direction(&self, cell: Cell) -> usize {
        let mut best: Option<(i64, usize)> = None;
        for direction in 0..4 {
            let next = neighbor(cell, direction);
            if next.0 < 0 || next.1 < 0 || next.0 >= self.width as i64 || next.1 >= self.height as i64 { continue; }
            if let Some(distance) = self.at(next) { if best.map(|value| distance < value.0).unwrap_or(true) { best = Some((distance, direction)); } }
        }
        best.unwrap().1
    }
    pub fn next_cell(&self, cell: Cell) -> Cell { neighbor(cell, self.direction(cell)) }
    pub fn path(&self, start: Cell) -> Vec<Cell> {
        let mut path = vec![start];
        while *path.last().unwrap() != self.exit { path.push(self.next_cell(*path.last().unwrap())); }
        path
    }
}
