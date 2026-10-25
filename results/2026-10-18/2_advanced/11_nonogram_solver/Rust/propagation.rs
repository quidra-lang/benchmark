use crate::line_solver::{self, Clues, Grid, UNKNOWN};

pub fn label(row: bool, index: usize) -> String { format!("{}{}", if row { 'R' } else { 'C' }, index + 1) }
pub fn cells(grid: &Grid, row: bool, index: usize) -> Vec<u8> { if row { grid[index].clone() } else { grid.iter().map(|r| r[index]).collect() } }
pub fn determined(grid: &Grid) -> usize { grid.iter().flatten().filter(|&&state| state != UNKNOWN).count() }

#[derive(Clone)]
pub struct Step { pub row: bool, pub index: usize, pub gain: usize, pub contradiction: bool }
impl Step {
    pub fn label(&self) -> String { label(self.row, self.index) }
    fn text(&self) -> String { format!("{}{}", self.label(), if self.contradiction { "!".into() } else { format!("+{}", self.gain) }) }
}
pub struct Propagation { pub steps: Vec<Step>, pub conflict: Option<Step> }
impl Propagation { pub fn record(&self) -> String { self.steps.iter().map(Step::text).collect::<Vec<_>>().join(" ") } }

pub fn run(grid: &mut Grid, rows: &Clues, columns: &Clues, precise: bool, mut row_marks: Vec<bool>, mut column_marks: Vec<bool>) -> Propagation {
    let mut result = Propagation { steps: Vec::new(), conflict: None };
    loop {
        let (row, index) = if let Some(index) = row_marks.iter().position(|&mark| mark) { row_marks[index] = false; (true, index) }
            else if let Some(index) = column_marks.iter().position(|&mark| mark) { column_marks[index] = false; (false, index) }
            else { return result; };
        let current = cells(grid, row, index);
        let Some(solved) = line_solver::solve(&current, if row { &rows[index] } else { &columns[index] }, precise) else {
            let step = Step { row, index, gain: 0, contradiction: true };
            result.conflict = Some(step.clone()); result.steps.push(step); return result;
        };
        let mut gain = 0;
        for (position, &state) in solved.iter().enumerate() {
            if current[position] != UNKNOWN || state == UNKNOWN { continue; }
            gain += 1;
            if row { grid[index][position] = state; column_marks[position] = true; }
            else { grid[position][index] = state; row_marks[position] = true; }
        }
        result.steps.push(Step { row, index, gain, contradiction: false });
    }
}
