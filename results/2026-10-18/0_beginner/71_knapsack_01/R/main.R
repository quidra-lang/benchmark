names <- c("tent", "stove", "lantern", "rope", "camera", "blanket", "water")
weights <- c(10, 3, 2, 3, 5, 5, 6)
values <- c(120, 65, 45, 20, 90, 85, 100)
capacity <- 20
table <- matrix(0, length(names) + 1, capacity + 1)
for (i in seq_along(names)) {
  for (weight in 0:capacity) {
    table[i + 1, weight + 1] <- table[i, weight + 1]
    if (weights[i] <= weight) {
      table[i + 1, weight + 1] <- max(table[i + 1, weight + 1], table[i, weight - weights[i] + 1] + values[i])
    }
  }
}
chosen <- rep(FALSE, length(names))
remaining <- capacity
for (i in rev(seq_along(names))) {
  if (table[i + 1, remaining + 1] != table[i, remaining + 1]) {
    chosen[i] <- TRUE
    remaining <- remaining - weights[i]
  }
}
cat(sprintf(
  "max value: %d\ntotal weight: %d\nitems: %s\n",
  table[nrow(table), ncol(table)], capacity - remaining, paste(names[chosen], collapse = " ")
))
