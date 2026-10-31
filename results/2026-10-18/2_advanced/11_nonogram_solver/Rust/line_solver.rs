pub const UNKNOWN: u8 = b'?';
pub const FILLED: u8 = b'#';
pub const EMPTY: u8 = b'.';
pub type Grid = Vec<Vec<u8>>;
pub type Clues = Vec<Vec<usize>>;

#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Given { pub row: usize, pub column: usize, pub value: u8 }

fn fit_table(cells: &[u8], clue: &[usize]) -> Vec<Vec<bool>> {
    let n = cells.len();
    let mut empties = vec![0; n + 1];
    for i in 0..n { empties[i + 1] = empties[i] + usize::from(cells[i] == EMPTY); }
    let mut table = vec![vec![false; clue.len() + 1]; n + 1];
    table[0][0] = true;
    for end in 1..=n {
        for count in 0..=clue.len() {
            let mut fits = cells[end - 1] != FILLED && table[end - 1][count];
            if !fits && count > 0 && end >= clue[count - 1] {
                let start = end - clue[count - 1];
                if empties[end] == empties[start] {
                    fits = if start == 0 { count == 1 } else { cells[start - 1] != FILLED && table[start - 1][count - 1] };
                }
            }
            table[end][count] = fits;
        }
    }
    table
}

struct Placements<'a> {
    cells: &'a [u8], clue: &'a [usize], before: Vec<Vec<bool>>, after: Vec<Vec<bool>>,
}

impl<'a> Placements<'a> {
    fn new(cells: &'a [u8], clue: &'a [usize]) -> Self {
        let reverse_cells: Vec<_> = cells.iter().rev().copied().collect();
        let reverse_clue: Vec<_> = clue.iter().rev().copied().collect();
        Self { cells, clue, before: fit_table(cells, clue), after: fit_table(&reverse_cells, &reverse_clue) }
    }
    fn consistent(&self) -> bool { self.before[self.cells.len()][self.clue.len()] }
    fn starts(&self, block: usize) -> Vec<usize> {
        let n = self.cells.len();
        let length = self.clue[block];
        if length > n { return Vec::new(); }
        (0..=n - length).filter(|&start| {
            let end = start + length;
            let rest = self.clue.len() - block - 1;
            !self.cells[start..end].contains(&EMPTY)
                && (if start == 0 { block == 0 } else { self.cells[start - 1] != FILLED && self.before[start - 1][block] })
                && (if end == n { rest == 0 } else { self.cells[end] != FILLED && self.after[n - end - 1][rest] })
        }).collect()
    }
    fn can_be_empty(&self, index: usize) -> bool {
        self.cells[index] != FILLED && (0..=self.clue.len()).any(|k| self.before[index][k] && self.after[self.cells.len() - index - 1][self.clue.len() - k])
    }
}

pub fn has_placement(cells: &[u8], clue: &[usize]) -> bool { Placements::new(cells, clue).consistent() }

pub fn solve(cells: &[u8], clue: &[usize], precise: bool) -> Option<Vec<u8>> {
    let placements = Placements::new(cells, clue);
    if !placements.consistent() { return None; }
    let mut solved = cells.to_vec();
    let mut possible = vec![false; cells.len()];
    for (block, &length) in clue.iter().enumerate() {
        let starts = placements.starts(block);
        if precise { for start in starts { possible[start..start + length].fill(true); } }
        else {
            let low = starts[0];
            let high = *starts.last().unwrap();
            for index in high..low + length { if solved[index] == UNKNOWN { solved[index] = FILLED; } }
            possible[low..high + length].fill(true);
        }
    }
    for index in 0..cells.len() {
        if solved[index] == UNKNOWN {
            if !possible[index] { solved[index] = EMPTY; }
            else if precise && !placements.can_be_empty(index) { solved[index] = FILLED; }
        }
    }
    Some(solved)
}
