fn main() {
    let mut prime = [true; 201];
    prime[0] = false;
    prime[1] = false;
    for p in 2..=200 {
        if prime[p] {
            for j in (2 * p..=200).step_by(p) {
                prime[j] = false;
            }
        }
    }
    let primes: Vec<usize> = (2..=200).filter(|&n| prime[n]).collect();
    println!("count: {}", primes.len());
    for group in primes.chunks(10) {
        println!("{}", group.iter().map(usize::to_string).collect::<Vec<_>>().join(" "));
    }
}
