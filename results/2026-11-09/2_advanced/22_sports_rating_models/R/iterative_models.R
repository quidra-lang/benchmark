bradley_terry <- function(count, matches, iterations) {
  wins <- numeric(count)
  home_wins <- 0
  for (match in matches) {
    wins[match$home] <- wins[match$home] + match$y
    wins[match$away] <- wins[match$away] + (1 - match$y)
    home_wins <- home_wins + match$y
  }
  strengths <- rep(1, count)
  theta <- 1
  for (iteration in seq_len(iterations)) {
    zeta <- numeric(count)
    for (match in matches) {
      q <- theta * strengths[match$home] + strengths[match$away]
      zeta[match$home] <- zeta[match$home] + theta / q
      zeta[match$away] <- zeta[match$away] + 1 / q
    }
    for (i in seq_len(count)) strengths[i] <- wins[i] / zeta[i]
    total <- 0
    for (strength in strengths) total <- total + strength
    for (i in seq_len(count)) strengths[i] <- strengths[i] * count / total
    denominator <- 0
    for (match in matches) {
      home <- strengths[match$home]
      denominator <- denominator + home / (theta * home + strengths[match$away])
    }
    theta <- home_wins / denominator
  }
  list(strengths = strengths, home_factor = theta)
}
offense_defense <- function(count, matches, iterations) {
  points <- matrix(0, count, count)
  for (match in matches) {
    points[match$home, match$away] <- points[match$home, match$away] + match$away_score
    points[match$away, match$home] <- points[match$away, match$home] + match$home_score
  }
  offense <- numeric(count)
  defense <- rep(1, count)
  for (iteration in seq_len(iterations)) {
    for (j in seq_len(count)) {
      total <- 0
      for (i in seq_len(count)) total <- total + points[i, j] / defense[i]
      offense[j] <- total
    }
    for (i in seq_len(count)) {
      total <- 0
      for (j in seq_len(count)) total <- total + points[i, j] / offense[j]
      defense[i] <- total
    }
  }
  list(offense = offense, defense = defense, od = offense / defense)
}
