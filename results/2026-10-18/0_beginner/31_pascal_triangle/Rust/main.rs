fn main() {
    let mut row = [0; 12];
    row[0] = 1;
    for n in 0..12 {
        for k in(1..=n).rev() {
            row[k] += row[k - 1];
        }
        for k in 0..=n {
            if k > 0 {
                print!(" ");
            }
            print!("{}", row[k]);
        }
        println!();
    }
}
