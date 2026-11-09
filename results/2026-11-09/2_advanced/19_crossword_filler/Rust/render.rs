use crate::grid::Grid;
use crate::slots::{Layout, Slot};

pub fn decimal(numerator: i64, denominator: usize, places: u32) -> String {
    let scale = 10i64.pow(places);
    let denominator = denominator as i64;
    let rounded = (2 * numerator * scale + denominator) / (2 * denominator);
    format!("{}.{:0width$}", rounded / scale, rounded % scale, width = places as usize)
}
pub fn grid_lines(grid: &Grid, letters: &[u8]) -> Vec<String> {
    letters.chunks(grid.width).map(|row| String::from_utf8(row.to_vec()).unwrap()).collect()
}
pub fn number_lines(layout: &Layout) -> Vec<String> {
    let grid = &layout.grid;
    (0..grid.height).map(|row| (0..grid.width).map(|column| {
        let cell = grid.cell(row, column);
        if grid.cells[cell] == b'#' { "##".to_owned() }
        else if let Some(number) = layout.numbers.get(&cell) { format!("{number:>2}") }
        else { " .".to_owned() }
    }).collect::<Vec<_>>().join(" ")).collect()
}
pub fn list_line(slot: &Slot, clue: &str, entry: &str, score: &str, theme: bool) -> String {
    format!("{}. {clue} ({}) {entry} {score}{}", slot.number, slot.length(), if theme { " theme" } else { "" })
}
