fn main() {
    let polygon = [
        [1, 1],
        [11, 2],
        [13, 9],
        [9, 7],
        [7, 12],
        [5, 6],
        [2, 10],
        [3, 5],
    ];
    for [px, py] in [[4, 8], [6, 4], [10, 8], [7, 11], [14, 3], [12, 8]] {
        let mut inside = false;
        for i in 0..8 {
            let [x1, y1] = polygon[i];
            let [x2, y2] = polygon[(i + 1) % 8];
            if (y1 > py) != (y2 > py) {
                let intersection =
                    f64::from(x1) + f64::from(x2 - x1) * f64::from(py - y1) / f64::from(y2 - y1);
                if intersection > f64::from(px) {
                    inside = !inside;
                }
            }
        }
        println!(
            "({}, {}): {}",
            px,
            py,
            if inside { "inside" } else { "outside" }
        );
    }
}
