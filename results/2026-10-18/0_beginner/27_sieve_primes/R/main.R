limit <- 200
prime <- rep(TRUE, limit + 1)
prime[1:2] <- FALSE
for (p in 2:limit) {
  if (prime[p + 1] && 2 * p <= limit) prime[seq(2 * p, limit, by = p) + 1] <- FALSE
}
primes <- (0:limit)[prime]
cat(sprintf("count: %d\n", length(primes)))
for (first in seq(1, length(primes), by = 10)) {
  cat(paste(primes[first:min(first + 9, length(primes))], collapse = " "), "\n", sep = "")
}
