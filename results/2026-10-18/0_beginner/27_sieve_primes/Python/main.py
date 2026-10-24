limit = 200
is_prime = [True] * (limit + 1)
is_prime[0] = is_prime[1] = False
for n in range(2, limit + 1):
    if is_prime[n]:
        for multiple in range(n * 2, limit + 1, n):
            is_prime[multiple] = False
primes = [n for n in range(2, limit + 1) if is_prime[n]]
print(f"count: {len(primes)}")
for start in range(0, len(primes), 10):
    print(*primes[start:start + 10])
