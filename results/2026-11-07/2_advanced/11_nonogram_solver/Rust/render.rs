use crate::clues;
use crate::line_solver::{Clues, Grid};

pub fn state_string(cells: &[u8]) -> String { String::from_utf8(cells.to_vec()).unwrap() }
pub fn grid_display(grids: &[(&str, &Grid)]) -> Vec<String> {
    if grids.is_empty() { return Vec::new(); }
    let mut lines = vec![format!("grid {}", grids.iter().map(|(name, _)| *name).collect::<Vec<_>>().join(" "))];
    for row in 0..grids[0].1.len() { lines.push(grids.iter().map(|(_, grid)| state_string(&grid[row])).collect::<Vec<_>>().join(" | ")); }
    lines
}
pub fn answer_sheet(rows: &Clues, columns: &Clues, grid: &Grid) -> Vec<String> {
    let tokens: Vec<Vec<String>> = columns.iter().map(|clue| clues::text(clue, " ").split(' ').map(str::to_owned).collect()).collect();
    let width = tokens.iter().flatten().map(String::len).max().unwrap() + 1;
    let depth = tokens.iter().map(Vec::len).max().unwrap();
    let margin = rows.iter().map(|clue| clues::text(clue, " ").len()).max().unwrap();
    let mut lines = Vec::new();
    for line in 0..depth {
        let mut text = " ".repeat(margin);
        for column in &tokens {
            let skip = depth - column.len();
            let token = if line < skip { "" } else { &column[line - skip] };
            text.push_str(&format!("{token:>width$}"));
        }
        lines.push(text.trim_end().to_owned());
    }
    for (r, row) in grid.iter().enumerate() {
        let clue = clues::text(&rows[r], " ");
        let mut text = format!("{clue:>margin$}");
        for &state in row { text.push_str(&" ".repeat(width - 1)); text.push(state as char); }
        lines.push(text);
    }
    lines
}
