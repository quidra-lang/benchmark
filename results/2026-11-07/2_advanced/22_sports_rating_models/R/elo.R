expected_score <- function(home, away, advantage) 1 / (1 + 10 ^ ((away - home - advantage) / 400))
multiplier <- function(match, home, away, advantage) {
  goals <- abs(match$margin)
  if (goals == 0L) return(1)
  difference <- if (match$margin > 0L) home + advantage - away else away - home - advantage
  log(goals + 1) * 2.2 / (0.001 * difference + 2.2)
}
run_elo <- function(count, matches, k, advantage, initial) {
  ratings <- rep(initial, count)
  expected <- changes <- numeric()
  rounds <- list()
  for (i in seq_along(matches)) {
    match <- matches[[i]]
    home <- ratings[match$home]
    away <- ratings[match$away]
    e <- expected_score(home, away, advantage)
    weight <- multiplier(match, home, away, advantage)
    change <- k * weight * (match$y - e)
    ratings[match$home] <- home + change
    ratings[match$away] <- away - change
    expected <- c(expected, e)
    changes <- c(changes, change)
    if (i == length(matches) || matches[[i + 1L]]$round != match$round) rounds[[length(rounds) + 1L]] <- ratings + 0
  }
  list(ratings = ratings, expected = expected, changes = changes, rounds = rounds)
}
