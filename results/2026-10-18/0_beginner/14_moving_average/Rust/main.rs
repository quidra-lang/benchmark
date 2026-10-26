fn main() {
    let sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
    for (i, window) in sales.windows(3).enumerate() {
        println!(
            "day {}: {:.2}",
            i + 3,
            f64::from(window.iter().sum::<i32>()) / 3.0
        );
    }
}
