fn cross(o: (i32, i32), a: (i32, i32), b: (i32, i32)) -> i32 {
    (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
}

fn main() {
    let mut points = [(3, 2), (-6, 1), (8, 4), (0, 0), (-3, 7), (4, -3), (1, -5), (-2, 1), (5, 6),
        (-6, -2), (2, -2), (7, -1), (-3, 4), (2, 8), (-6, 3)];
    points.sort();
    let mut lower = Vec::new();
    let mut upper = Vec::new();
    for &p in &points {
        while lower.len() >= 2 && cross(lower[lower.len() - 2], lower[lower.len() - 1], p) <= 0 {
            lower.pop();
        }
        lower.push(p);
    }
    for &p in points.iter().rev() {
        while upper.len() >= 2 && cross(upper[upper.len() - 2], upper[upper.len() - 1], p) <= 0 {
            upper.pop();
        }
        upper.push(p);
    }
    lower.pop();
    upper.pop();
    lower.extend(upper);
    let mut twice = 0;
    println!("hull: {} points", lower.len());
    for i in 0..lower.len() {
        let (x, y) = lower[i];
        let (nx, ny) = lower[(i + 1) % lower.len()];
        println!("({}, {})", x, y);
        twice += x * ny - nx * y;
    }
    println!("area: {}.{}", twice / 2, twice % 2 * 5);
}
