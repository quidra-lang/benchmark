fn main() {
    let values = [48, 73, 56, 91, 35, 62, 84];
    let sum: i32 = values.iter().sum();
    println!("{:.2}", f64::from(sum) / values.len() as f64);
}
