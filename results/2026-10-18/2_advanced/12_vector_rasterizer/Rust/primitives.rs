use std::collections::HashSet;
use crate::canvas::round_ratio;

pub type Point = (i64, i64);
pub type Pixels = HashSet<Point>;

pub fn bresenham((mut x, mut y): Point, (ex, ey): Point) -> Vec<Point> {
    let (dx, dy) = ((ex - x).abs(), -(ey - y).abs());
    let (sx, sy) = (if x < ex { 1 } else { -1 }, if y < ey { 1 } else { -1 });
    let mut error = dx + dy;
    let mut points = Vec::new();
    loop {
        points.push((x, y)); if x == ex && y == ey { return points; }
        let doubled = 2 * error;
        if doubled >= dy { error += dy; x += sx; }
        if doubled <= dx { error += dx; y += sy; }
    }
}
pub fn expand_square((x, y): Point, width: i64) -> Vec<Point> {
    let low = -((width - 1) / 2);
    (low..low + width).flat_map(|j| (low..low + width).map(move |i| (x + i, y + j))).collect()
}
pub fn circle_points(radius: i64) -> Pixels {
    let (mut a, mut b, mut error) = (radius, 0, 1 - radius);
    let mut points = Pixels::new();
    while a >= b {
        points.extend([(a, b), (b, a), (-b, a), (-a, b), (-a, -b), (-b, -a), (b, -a), (a, -b)]);
        b += 1;
        if error < 0 { error += 2 * b + 1; } else { a -= 1; error += 2 * (b - a) + 1; }
    }
    points
}
fn add_quadrants(points: &mut Pixels, x: i64, y: i64) { points.extend([(x, y), (-x, y), (x, -y), (-x, -y)]); }
pub fn ellipse_points(rx: i64, ry: i64) -> Pixels {
    let (rx2, ry2) = (rx * rx, ry * ry);
    let (mut x, mut y) = (0, ry);
    let mut points = Pixels::from([(0, ry), (0, -ry)]);
    while ry2 * x < rx2 * y {
        let d = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2;
        x += 1; if d >= 0 { y -= 1; } add_quadrants(&mut points, x, y);
    }
    while y > 0 {
        let d = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2;
        y -= 1; if d <= 0 { x += 1; } add_quadrants(&mut points, x, y);
    }
    points
}
pub fn bezier_points(controls: &[Point], segments: i64) -> Vec<Point> {
    let degree = controls.len() - 1;
    let scale = segments.pow(degree as u32);
    (0..=segments).map(|i| {
        let r = segments - i;
        let weights = if degree == 2 { vec![r * r, 2 * i * r, i * i] } else { vec![r * r * r, 3 * i * r * r, 3 * i * i * r, i * i * i] };
        let x = weights.iter().zip(controls).map(|(w, p)| w * p.0).sum();
        let y = weights.iter().zip(controls).map(|(w, p)| w * p.1).sum();
        (round_ratio(x, scale), round_ratio(y, scale))
    }).collect()
}
