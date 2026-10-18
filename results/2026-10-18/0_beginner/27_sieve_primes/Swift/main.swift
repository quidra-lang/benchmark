var prime = [Bool](repeating: true, count: 201)
prime[0] = false
prime[1] = false
for p in 2...200 where prime[p] {
    for m in stride(from: 2 * p, through: 200, by: p) { prime[m] = false }
}
let primes = (2...200).filter { prime[$0] }
print("count: \(primes.count)")
for i in stride(from: 0, to: primes.count, by: 10) {
    print(primes[i..<min(i + 10, primes.count)].map(String.init).joined(separator: " "))
}
