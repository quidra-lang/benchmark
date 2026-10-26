squared_distance <- function(first, second) {
  delta <- first - second
  delta[1] * delta[1] + delta[2] * delta[2]
}
integer_sqrt <- function(number) {
  low <- 0
  high <- number + 1
  while (high - low > 1) {
    middle <- (low + high) %/% 2
    if (middle <= number %/% middle) low <- middle else high <- middle
  }
  low
}
scaled <- function(delta, step, length) {
  if (delta >= 0) (delta * step) %/% length else -(((-delta) * step) %/% length)
}
advance_point <- function(point, goal, step) {
  delta <- goal - point
  squared <- delta[1] * delta[1] + delta[2] * delta[2]
  if (squared <= step * step) return(list(point = goal, arrived = TRUE))
  length <- integer_sqrt(squared)
  list(point = point + c(scaled(delta[1], step, length), scaled(delta[2], step, length)), arrived = FALSE)
}
damage_dealt <- function(hp, power, armor) min(hp, max(1, power - armor))
new_effect <- function() {
  effect <- new.env(parent = emptyenv())
  effect$strength <- 0
  effect$remaining <- 0
  effect$source <- NULL
  effect
}
effect_active <- function(effect) effect$remaining > 0
receive_effect <- function(effect, strength, duration, source = NULL) {
  if (strength > effect$strength) {
    effect$strength <- strength
    effect$remaining <- duration
    effect$source <- source
  } else if (strength == effect$strength) {
    effect$remaining <- max(effect$remaining, duration)
  }
}
advance_effect <- function(effect) {
  effect$remaining <- effect$remaining - 1
  if (effect$remaining == 0) {
    effect$strength <- 0
    effect$source <- NULL
  }
}
new_projectile <- function(number, tower, target, position, aim, targets, stats) {
  projectile <- new.env(parent = emptyenv())
  projectile$number <- number
  projectile$tower <- tower
  projectile$target <- target
  projectile$position <- position
  projectile$aim <- aim
  projectile$targets <- targets
  for (name in c("power", "shot_speed", "splash", "slow_rate", "slow_time", "burn_amount", "burn_time")) projectile[[name]] <- stats[[name]]
  projectile
}
fly_projectile <- function(projectile) {
  if (projectile$shot_speed == 0) return(TRUE)
  result <- advance_point(projectile$position, projectile$aim, projectile$shot_speed)
  projectile$position <- result$point
  result$arrived
}
