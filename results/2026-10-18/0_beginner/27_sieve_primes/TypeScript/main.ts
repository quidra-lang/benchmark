const limit = 200;
const isPrime = Array(limit + 1).fill(true);
isPrime[0] = isPrime[1] = false;
for (let n = 2; n <= limit; n++) {
  if (isPrime[n]) for (let multiple = n * 2; multiple <= limit; multiple += n) isPrime[multiple] = false;
}
const primes = Array.from({length: limit - 1}, (_, i) => i + 2).filter(n => isPrime[n]);
console.log(`count: ${primes.length}`);
for (let start = 0; start < primes.length; start += 10) console.log(primes.slice(start, start + 10).join(" "));
