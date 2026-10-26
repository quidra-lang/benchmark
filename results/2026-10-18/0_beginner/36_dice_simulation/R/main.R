state <- 12345
counts <- integer(13)
for (trial in 1:1000) {
  state <- (state * 48271) %% 2147483647
  first_die <- state %% 6 + 1
  state <- (state * 48271) %% 2147483647
  second_die <- state %% 6 + 1
  index <- first_die + second_die + 1
  counts[index] <- counts[index] + 1L
}
for (total in 2:12) cat(sprintf("%d: %d\n", total, counts[total + 1]))
cat(sprintf("most frequent: %d\n", which.max(counts[3:13]) + 1))
