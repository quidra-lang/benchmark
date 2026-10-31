games <- list(
  c(8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2),
  c(3, 4, 5, 2, 7, 1, 0, 6, 8, 1, 4, 4, 2, 3, 6, 2, 9, 0, 1, 5),
  c(5, 5, 0, 10, 7, 3, 9, 1, 6, 4, 8, 2, 3, 7, 4, 6, 1, 9, 7, 3, 5),
  rep(10, 12),
  c(10, 9, 1, 10, 10, 7, 2, 0, 0, 10, 8, 1, 10, 6, 4, 10)
)
for (number in seq_along(games)) {
  rolls <- games[[number]]
  position <- 1
  total <- 0
  cumulative <- numeric(0)
  for (frame in 1:9) {
    if (rolls[position] == 10) {
      score <- 10 + rolls[position + 1] + rolls[position + 2]
      position <- position + 1
    } else if (rolls[position] + rolls[position + 1] == 10) {
      score <- 10 + rolls[position + 2]
      position <- position + 2
    } else {
      score <- rolls[position] + rolls[position + 1]
      position <- position + 2
    }
    total <- total + score
    cumulative <- c(cumulative, total)
  }
  cumulative <- c(cumulative, total + sum(rolls[position:length(rolls)]))
  cat(sprintf("game %d: %s\n", number, paste(cumulative, collapse = " ")))
}
