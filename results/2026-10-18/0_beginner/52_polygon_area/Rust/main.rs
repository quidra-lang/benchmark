fn main() {
    let polygons: [&[(i32, i32)]; 3] = [
        &[(0, 0), (5, 0), (6, 4), (1, 3)],
        &[(2, 1), (0, 4), (3, 7), (7, 6), (8, 2)],
        &[(0, 0), (8, 0), (8, 6), (5, 6), (4, 3), (3, 6), (0, 6)],
    ];
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
        println!("polygon {}: area={:.1} perimeter={:.3}", k + 1, f64::from(twice.abs()) / 2.0, perimeter);
    }
}
