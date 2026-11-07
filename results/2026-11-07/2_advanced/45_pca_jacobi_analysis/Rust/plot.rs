pub type Grid = Vec<Vec<char>>;

pub fn grid(width: usize, height: usize) -> Grid {
    vec![vec![' '; width]; height]
}

pub fn frame(grid: &Grid) -> Vec<String> {
    let edge = format!("+{}+", "-".repeat(grid[0].len()));
    let mut lines = vec![edge.clone()];
    lines.extend(grid.iter().map(|r| format!("|{}|", r.iter().collect::<String>())));
    lines.push(edge);
    lines
}

pub fn axes(grid: &mut Grid, (row, column): (usize, usize)) {
    for cell in &mut grid[row] {
        *cell = '-';
    }
    for line in grid.iter_mut() {
        line[column] = '|';
    }
    grid[row][column] = '+';
}

pub fn cell(x: f64, y: f64, m1: f64, m2: f64, w: usize, h: usize) -> (usize, usize) {
    let column = (((x + m1) / (2.0 * m1) * w as f64).floor() as usize).min(w - 1);
    let row = (((m2 - y) / (2.0 * m2) * h as f64).floor() as usize).min(h - 1);
    (row, column)
}

pub fn diagnostic(t2: f64, spe: f64, x: f64, y: f64, w: usize, h: usize) -> (usize, usize) {
    let column = ((t2 / x * w as f64).floor() as usize).min(w - 1);
    let row = h - 1 - ((spe / y * h as f64).floor() as usize).min(h - 1);
    (row, column)
}

pub fn shaft(origin: (usize, usize), tip: (usize, usize)) -> Vec<(usize, usize, char)> {
    let dc = tip.1 as i64 - origin.1 as i64;
    let dr = tip.0 as i64 - origin.0 as i64;
    let steps = dc.abs().max(dr.abs());
    let mark = if 2 * dr.abs() <= dc.abs() { '-' }
        else if 2 * dc.abs() <= dr.abs() { '|' }
        else if dc * dr < 0 { '/' } else { '\\' };
    let mut cells = Vec::new();
    for s in 1..steps {
        let c = origin.1 as i64 + dc.signum() * ((2 * s * dc.abs() + steps) / (2 * steps));
        let r = origin.0 as i64 + dr.signum() * ((2 * s * dr.abs() + steps) / (2 * steps));
        cells.push((r as usize, c as usize, mark));
    }
    cells
}

pub fn density(grid: &mut Grid, positions: &[(usize, usize)]) {
    let mut counts = vec![vec![0; grid[0].len()]; grid.len()];
    for &(r, c) in positions {
        counts[r][c] += 1;
    }
    for r in 0..grid.len() {
        for c in 0..grid[r].len() {
            if counts[r][c] > 0 {
                grid[r][c] = match counts[r][c] { 1 => '.', 2 | 3 => 'o', _ => '@' };
            }
        }
    }
}

pub fn scree(width: usize, length: usize, broken: usize, kaiser: usize) -> String {
    (1..=width).map(|p| {
        if p == broken { 'o' } else if p == kaiser { ':' } else if p <= length { '#' } else { ' ' }
    }).collect()
}
