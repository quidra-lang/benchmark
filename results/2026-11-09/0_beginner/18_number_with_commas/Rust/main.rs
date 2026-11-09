fn main() {
    for n in [0_i64, 7, 999, 1000, -456789, 3141592, 9876543210] {
        let text = n.abs().to_string();
        let negative = n < 0;
        if negative {
            print!("-");
        }
        for (i, c) in text.chars().enumerate() {
            if i > 0 && (text.len() - i) % 3 == 0 {
                print!(",");
            }
            print!("{}", c);
        }
        println!();
    }
}
