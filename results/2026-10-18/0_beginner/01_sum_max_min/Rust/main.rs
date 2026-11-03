fn main() {
    let values = [17, -8, 42, 5, -23, 36, 5, 0, -11, 29];
    println!(
        "sum: {}\nmax: {}\nmin: {}",
        values.iter().sum::<i32>(),
        values.iter().max().unwrap(),
        values.iter().min().unwrap()
    );
}
