use std::collections::BTreeMap;
use crate::grid::Grid;

fn starts_run(grid: &Grid, row: i32, column: i32, dr: i32, dc: i32) -> bool {
    grid.is_open(row, column) && !grid.is_open(row - dr, column - dc)
}
fn run_length(grid: &Grid, row: i32, column: i32, dr: i32, dc: i32) -> usize {
    let mut length = 0;
    while grid.is_open(row + length * dr, column + length * dc) { length += 1; }
    length as usize
}
pub fn find_short_run(grid: &Grid) -> Option<(usize, &'static str)> {
    for row in 0..grid.height { for column in 0..grid.width {
        for (dr, dc, direction) in [(0, 1, "across"), (1, 0, "down")] {
            if starts_run(grid, row as i32, column as i32, dr, dc) && run_length(grid, row as i32, column as i32, dr, dc) == 2 {
                return Some((grid.cell(row, column), direction));
            }
        }
    } }
    None
}

pub struct Slot {
    pub index: usize,
    pub number: usize,
    pub across: bool,
    pub cells: Vec<usize>,
    pub label: String,
    pub crossings: Vec<usize>,
}
impl Slot { pub fn length(&self) -> usize { self.cells.len() } }
pub struct Layout {
    pub grid: Grid,
    pub numbers: BTreeMap<usize, usize>,
    pub slots: Vec<Slot>,
    pub across_slot: Vec<Option<usize>>,
    pub down_slot: Vec<Option<usize>>,
}
impl Layout {
    pub fn new(grid: Grid) -> Self {
        let size = grid.cells.len();
        let mut result = Self { grid, numbers: BTreeMap::new(), slots: Vec::new(), across_slot: vec![None; size], down_slot: vec![None; size] };
        for row in 0..result.grid.height { for column in 0..result.grid.width {
            for (dr, dc, across) in [(0, 1, true), (1, 0, false)] {
                if !starts_run(&result.grid, row as i32, column as i32, dr, dc) { continue; }
                let length = run_length(&result.grid, row as i32, column as i32, dr, dc);
                if length < 3 { continue; }
                let start = result.grid.cell(row, column);
                let next_number = result.numbers.len() + 1;
                let number = *result.numbers.entry(start).or_insert(next_number);
                let cells: Vec<_> = (0..length).map(|position| result.grid.cell(row + position * dr as usize, column + position * dc as usize)).collect();
                let index = result.slots.len();
                let owners = if across { &mut result.across_slot } else { &mut result.down_slot };
                for &cell in &cells { owners[cell] = Some(index); }
                result.slots.push(Slot { index, number, across, cells, label: format!("{number}{}", if across { 'A' } else { 'D' }), crossings: Vec::new() });
            }
        } }
        for slot in &mut result.slots {
            let owners = if slot.across { &result.down_slot } else { &result.across_slot };
            slot.crossings = slot.cells.iter().filter_map(|&cell| owners[cell]).collect();
            slot.crossings.sort_unstable();
        }
        result
    }
    pub fn owner_count(&self, cell: usize) -> usize { self.across_slot[cell].is_some() as usize + self.down_slot[cell].is_some() as usize }
    pub fn orphan_cell(&self) -> Option<usize> { self.grid.white_cells().into_iter().find(|&cell| self.owner_count(cell) == 0) }
}
