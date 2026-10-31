fn main() {
    for start in [1_i64, 6, 27, 97, 871] {
        let (mut n, mut m, mut k) = (start, start, 0);
        while n != 1 {
            n = if n % 2 == 0 { n / 2 } else { 3 * n + 1 };
            k += 1;
            m = m.max(n);
        }
        println!("{}: steps={} max={}", start, k, m);
    }
}
