parse_dice <- function(token) as.integer(strsplit(token, "d", fixed = TRUE)[[1L]])
roll_dice <- function(dice, rng) rng_roll(rng, dice[1L], dice[2L])

resolve_attack <- function(rng, to_hit, defense, dice, bonus) {
  roll <- 1 + rng_rnd(rng, 20)
  if (roll == 1) return(list(outcome = "miss", damage = 0))
  outcome <- "hit"
  if (roll == 20) {
    outcome <- "critical"
    first <- roll_dice(dice, rng)
    second <- roll_dice(dice, rng)
    damage <- first + second + bonus
  } else if (roll + to_hit >= defense) {
    damage <- roll_dice(dice, rng) + bonus
  } else {
    return(list(outcome = "miss", damage = 0))
  }
  list(outcome = outcome, damage = max(damage, 1))
}
