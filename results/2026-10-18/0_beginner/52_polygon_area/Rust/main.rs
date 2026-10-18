fn main() {
    let polygons: Vec<Vec<(i32, i32)>>= vec![vec![(0, 0), (5, 0), (6, 4), (1, 3)], vec![(2, 1), (0,
        4), (3, 7), (7, 6), (8, 2)], vec![(0, 0), (8, 0), (8, 6), (5, 6), (4, 3), (3, 6), (0, 6)]];
    for (k, p) in polygons.iter().enumerate() {
        let mut twice = 0_i32;
        let mut perimeter = 0.0;
        for i in 0..p.len() {
            let (x, y) = p[i];
            let (nx, ny) = p[(i + 1) % p.len()];
            let (dx, dy) = (x - nx, y - ny);
            twice += x * ny - nx * y;
            perimeter += f64::from(dx * dx + dy * dy).sqrt();
        }
        let a = twice.abs();
        let q = (perimeter * 1000.0 + 0.5) as i32;
        println!("polygon {}: area={}.{} perimeter={}.{:03}", k + 1, a / 2, a % 2 * 5, q / 1000, q % 1000);
    }
}
