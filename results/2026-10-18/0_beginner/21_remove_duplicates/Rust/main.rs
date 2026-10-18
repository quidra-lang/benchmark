fn main() {
    let values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9];
    let mut unique = Vec::new();
    for n in values {
        if !unique.contains(&n) {
            unique.push(n);
        }
    }
    for (i, n) in unique.iter().enumerate() {
        if i > 0 {
            print!(" ");
        }
        print!("{}", n);
    }
    println!("\nremoved: {}", values.len() - unique.len());
}
