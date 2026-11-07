use std::{fs, io};

pub type Cell = (i64, i64);
pub type Point = (i64, i64);
pub fn cell_center(cell: Cell) -> Point { (100 * cell.0, 100 * cell.1) }
pub struct GridMap { pub width: usize, pub height: usize, pub rows: Vec<Vec<u8>>, pub exit: Cell, pub spawns: Vec<Cell> }
impl GridMap {
    pub fn read(path: &str) -> io::Result<Self> {
        let text = fs::read_to_string(path)?;
        let lines: Vec<&str> = text.lines().collect();
        let dimensions: Vec<usize> = lines[0].split(' ').map(|value| value.parse().unwrap()).collect();
        let (width, height) = (dimensions[0], dimensions[1]);
        let rows: Vec<Vec<u8>> = lines[1..=height].iter().map(|line| line.as_bytes().to_vec()).collect();
        let mut exit = (0, 0);
        let mut found = std::collections::BTreeMap::new();
        for (y, row) in rows.iter().enumerate() { for (x, &terrain) in row.iter().enumerate() {
            if terrain.is_ascii_digit() { found.insert(terrain - b'0', (x as i64, y as i64)); }
            else if terrain == b'E' { exit = (x as i64, y as i64); }
        } }
        Ok(Self { width, height, rows, exit, spawns: found.into_values().collect() })
    }
    pub fn inside(&self, cell: Cell) -> bool { cell.0 >= 0 && cell.1 >= 0 && cell.0 < self.width as i64 && cell.1 < self.height as i64 }
    pub fn terrain(&self, cell: Cell) -> u8 { self.rows[cell.1 as usize][cell.0 as usize] }
    pub fn is_rock(&self, cell: Cell) -> bool { self.terrain(cell) == b'#' }
    pub fn is_water(&self, cell: Cell) -> bool { self.terrain(cell) == b'~' }
    pub fn buildable(&self, cell: Cell) -> bool { self.terrain(cell) == b'.' }
}
