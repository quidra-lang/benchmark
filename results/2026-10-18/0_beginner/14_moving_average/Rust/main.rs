fn main() {
    let sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
    for i in 2..10 {
        let avg = f64::from(sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
        let q = (avg * 100.0 + 0.5) as i32;
        println!("day {}: {}.{:02}", i + 1, q / 100, q % 100);
    }
}
