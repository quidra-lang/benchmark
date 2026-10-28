use crate::matrix::Grid;
pub fn symbol(grid: &Grid) -> Vec<String> {
    grid.iter().map(|row| row.iter().map(|&v| if v == 1 {
        '#'
    } else {
        '.'
    }).collect()).collect()
}
pub fn pbm(grid: &Grid, quiet: usize, scale: usize) -> Vec<String> {
    let n = grid.len();
    let width = (n+2*quiet)*scale;
    let mut lines = vec!["P1".to_owned(),format!("{} {}",width,width)];
    for py in 0..width {
        let y = py/scale;
        let row: String = (0..width).map(|px| {
            let x = px/scale;
            if x >= quiet && x < n+quiet && y >= quiet && y < n+quiet && grid[y-quiet][x-quiet] == 1 {
                '1'
            } else {
                '0'
            }
        }).collect();
        lines.push(row);
    }
    lines
}
