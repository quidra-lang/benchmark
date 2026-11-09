use crate::line_solver::{Clues, Grid, EMPTY, FILLED, UNKNOWN};
use crate::propagation;

pub fn guess_cell(grid: &Grid) -> (usize, usize) {
    let rows: Vec<_> = grid.iter().map(|row| row.iter().filter(|&&state| state == UNKNOWN).count()).collect();
    let mut columns = vec![0; grid[0].len()];
    for row in grid { for (c, &state) in row.iter().enumerate() { if state == UNKNOWN { columns[c] += 1; } } }
    let mut best = (0, 0);
    let mut score = usize::MAX;
    for (r, row) in grid.iter().enumerate() {
        for (c, &state) in row.iter().enumerate() {
            if state == UNKNOWN && rows[r] + columns[c] < score { score = rows[r] + columns[c]; best = (r, c); }
        }
    }
    best
}

pub struct Guess {
    pub number: usize, pub depth: usize, pub row: usize, pub column: usize, pub value: u8,
    pub solves: usize, pub known: usize, pub result: String,
}
#[derive(Default)]
pub struct Search { pub guesses: Vec<Guess>, pub solutions: Vec<Grid>, pub backtracks: usize, pub max_depth: usize, pub line_solves: usize }
impl Search {
    pub fn new(grid: &Grid, rows: &Clues, columns: &Clues) -> Self { let mut search = Self::default(); search.visit(grid, rows, columns, 1); search }
    fn visit(&mut self, parent: &Grid, rows: &Clues, columns: &Clues, depth: usize) -> bool {
        let (row, column) = guess_cell(parent);
        for value in [FILLED, EMPTY] {
            let mut child = parent.clone();
            child[row][column] = value;
            let mut row_marks = vec![false; rows.len()];
            let mut column_marks = vec![false; columns.len()];
            row_marks[row] = true; column_marks[column] = true;
            let propagation = propagation::run(&mut child, rows, columns, true, row_marks, column_marks);
            let known = propagation::determined(&child);
            let result = if let Some(step) = &propagation.conflict { self.backtracks += 1; format!("contradiction at={}", step.label()) }
                else if known == rows.len() * columns.len() { self.solutions.push(child.clone()); format!("solution{}", self.solutions.len()) }
                else { "open".into() };
            self.line_solves += propagation.steps.len(); self.max_depth = self.max_depth.max(depth);
            let open = result == "open";
            self.guesses.push(Guess { number: self.guesses.len() + 1, depth, row, column, value, solves: propagation.steps.len(), known, result });
            if open { if self.visit(&child, rows, columns, depth + 1) { return true; } }
            else if self.solutions.len() == 2 { return true; }
        }
        false
    }
}
