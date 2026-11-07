fn main() {
    let mut counts = [0; 13];
    let mut x = 12345_i64;
    for _ in 0..1000 {
        x = x * 48271 % 2147483647;
        let a = x % 6 + 1;
        x = x * 48271 % 2147483647;
        let b = x % 6 + 1;
        counts[(a + b) as usize] += 1;
    }
    let mut best = 2;
    for s in 2..=12 {
        println!("{}: {}", s, counts[s]);
        if counts[s] > counts[best] {
            best = s;
        }
    }
    println!("most frequent: {}", best);
}
