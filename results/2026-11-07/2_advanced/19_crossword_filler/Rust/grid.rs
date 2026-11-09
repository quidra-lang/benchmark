#[derive(Clone)]
pub struct Grid {
    pub width: usize,
    pub height: usize,
    pub cells: Vec<u8>,
}
impl Grid {
    pub fn new(rows: &[String]) -> Self {
        Self { width: rows[0].len(), height: rows.len(), cells: rows.iter().flat_map(|row| row.bytes()).collect() }
    }
    pub fn cell(&self, row: usize, column: usize) -> usize { row * self.width + column }
    pub fn location(&self, cell: usize) -> String { format!("{},{}", cell / self.width + 1, cell % self.width + 1) }
    pub fn is_open(&self, row: i32, column: i32) -> bool {
        row >= 0 && row < self.height as i32 && column >= 0 && column < self.width as i32
            && self.cells[self.cell(row as usize, column as usize)] != b'#'
    }
    pub fn white_cells(&self) -> Vec<usize> { (0..self.cells.len()).filter(|&cell| self.cells[cell] != b'#').collect() }
    pub fn asymmetric_cell(&self, symmetry: &str) -> Option<usize> {
        for row in 0..self.height { for column in 0..self.width {
            let other_row = if symmetry == "rot180" { self.height - 1 - row } else { row };
            let other_column = self.width - 1 - column;
            if self.is_open(row as i32, column as i32) != self.is_open(other_row as i32, other_column as i32) { return Some(self.cell(row, column)); }
        } }
        None
    }
    pub fn component_count(&self) -> usize {
        let mut seen = vec![false; self.cells.len()];
        let mut count = 0;
        for start in self.white_cells() {
            if seen[start] { continue; }
            count += 1;
            seen[start] = true;
            let mut stack = vec![start];
            while let Some(cell) = stack.pop() {
                let (row, column) = ((cell / self.width) as i32, (cell % self.width) as i32);
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let (r, c) = (row + dr, column + dc);
                    if self.is_open(r, c) {
                        let neighbor = self.cell(r as usize, c as usize);
                        if !seen[neighbor] { seen[neighbor] = true; stack.push(neighbor); }
                    }
                }
            }
        }
        count
    }
}
