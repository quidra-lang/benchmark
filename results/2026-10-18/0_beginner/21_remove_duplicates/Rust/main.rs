fn main() {
    let values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9];
    let mut unique = Vec::new();
    for n in values {
        if !unique.contains(&n) {
            unique.push(n);
        }
    }
    println!(
        "{}",
        unique
            .iter()
            .map(i32::to_string)
            .collect::<Vec<_>>()
            .join(" ")
    );
    println!("removed: {}", values.len() - unique.len());
}
