fn main() {
    let values = [17, -8, 42, 5, -23, 36, 5, 0, -11, 29];
    let sum: i32 = values.iter().sum();
    println!(
        "sum: {}\nmax: {}\nmin: {}",
        sum,
        values.iter().max().unwrap(),
        values.iter().min().unwrap()
    );
}
