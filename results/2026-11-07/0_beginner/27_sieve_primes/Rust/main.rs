fn main() {
    let limit = 200;
    let mut prime = vec![true; limit + 1];
    prime[0] = false;
    prime[1] = false;
    for p in 2..=limit {
        if prime[p] {
            for j in (2 * p..=limit).step_by(p) {
                prime[j] = false;
            }
        }
    }
    let primes: Vec<usize> = (2..=limit).filter(|&n| prime[n]).collect();
    println!("count: {}", primes.len());
    for group in primes.chunks(10) {
        println!(
            "{}",
            group
                .iter()
                .map(usize::to_string)
                .collect::<Vec<_>>()
                .join(" ")
        );
    }
}
