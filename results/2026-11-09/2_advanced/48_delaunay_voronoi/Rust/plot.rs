use crate::predicates::Point;

pub struct Canvas {
    pub cells: Vec<Vec<char>>,
}

impl Canvas {
    pub fn new(w: usize, h: usize) -> Self { Self { cells: vec![vec![' '; w]; h] } }

    pub fn position(&self, (x, y, d): (i64, i64, i64)) -> (i64, i64) {
        let h = self.cells.len() as i64;
        let w = self.cells[0].len() as i64;
        ((2 * x * (w - 1) + 1000 * d) / (2000 * d), h - 1 - (2 * y * (h - 1) + 1000 * d) / (2000 * d))
    }

    pub fn set(&mut self, point: (i64, i64), mark: char) {
        self.cells[point.1 as usize][point.0 as usize] = mark;
    }

    pub fn line(&mut self, from: Point, to: Point, mark: char) {
        let (mut x, mut y) = self.position((from.0, from.1, 1));
        let (x1, y1) = self.position((to.0, to.1, 1));
        let dx = (x1 - x).abs();
        let dy = -(y1 - y).abs();
        let sx = if x < x1 { 1 } else { -1 };
        let sy = if y < y1 { 1 } else { -1 };
        let mut error = dx + dy;
        loop {
            self.set((x, y), mark);
            if x == x1 && y == y1 { break; }
            let twice = 2 * error;
            if twice >= dy { error += dy; x += sx; }
            if twice <= dx { error += dx; y += sy; }
        }
    }

    pub fn voronoi(&mut self, points: &[Point]) {
        let h = self.cells.len();
        let w = self.cells[0].len();
        let owners: Vec<Vec<usize>> = (0..h).map(|r| (0..w).map(|c| {
            (0..points.len()).min_by_key(|&s| {
                let (x, y) = points[s];
                let a = (c as i64 * 1000 - x * (w - 1) as i64) * (h - 1) as i64;
                let b = ((h - 1 - r) as i64 * 1000 - y * (h - 1) as i64) * (w - 1) as i64;
                (a * a + b * b, s)
            }).unwrap()
        }).collect()).collect();
        for r in 0..h {
            for c in 0..w {
                if (c + 1 < w && owners[r][c] != owners[r][c + 1]) || (r + 1 < h && owners[r][c] != owners[r + 1][c]) {
                    self.cells[r][c] = '#';
                }
            }
        }
    }

    pub fn frame(&self) -> Vec<String> {
        let border = format!("+{}+", "-".repeat(self.cells[0].len()));
        let mut lines = vec![border.clone()];
        lines.extend(self.cells.iter().map(|r| format!("|{}|", r.iter().collect::<String>())));
        lines.push(border);
        lines
    }
}
