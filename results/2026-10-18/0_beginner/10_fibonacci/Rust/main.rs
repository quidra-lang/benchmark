fn main() {
    let (mut a, mut b, mut sum) = (1, 1, 0);
    for i in 0..30 {
        if i > 0 {
            print!(" ");
        }
        print!("{}", a);
        sum += a;
        (a, b) = (b, a + b);
    }
    println!("\nsum: {}", sum);
}
