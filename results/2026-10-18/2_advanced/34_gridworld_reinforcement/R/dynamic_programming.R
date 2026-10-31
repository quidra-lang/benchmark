first_max <- function(values) which.max(values)
bellman <- function(environment, values, gamma, state, action) {
  total <- 0
  for (outcome in environment$transitions[[state, action]]) {
    cell <- outcome[[1L]]
    target <- environment$world$state_index[[cell]]
    future <- if (target == 0L) 0 else (gamma * values[[target]]) %/% 100
    total <- total + outcome[[2L]] * (10000 * reward(environment, cell) + future)
  }
  total %/% environment$slip_total
}
action_values <- function(environment, values, gamma, state) vapply(
    seq_len(4L),
    function(action) bellman(environment, values, gamma, state, action),
    0
)
greedy_policy <- function(environment, values, gamma) vapply(
    seq_along(values),
    function(state) first_max(action_values(environment, values, gamma, state)),
    0L
)
value_iteration <- function(environment, gamma, theta) {
  values <- numeric(length(environment$world$states))
  changes <- numeric()
  repeat {
    updated <- vapply(
        seq_along(values),
        function(state) max(action_values(environment, values, gamma, state)),
        0
    )
    change <- max(abs(updated - values))
    changes <- c(changes, change)
    values <- updated
    if (change <= theta) return(list(values = values, changes = changes))
  }
}
in_place_value_iteration <- function(environment, gamma, theta) {
  values <- numeric(length(environment$world$states))
  sweeps <- 0L
  repeat {
    sweeps <- sweeps + 1L
    delta <- 0
    for (state in seq_along(values)) {
      value <- max(action_values(environment, values, gamma, state))
      delta <- max(delta, abs(value - values[[state]]))
      values[[state]] <- value
    }
    if (delta <= theta) return(list(values = values, sweeps = sweeps))
  }
}
evaluate_policy <- function(environment, policy, initial, gamma, theta) {
  values <- initial
  sweeps <- 0L
  repeat {
    sweeps <- sweeps + 1L
    delta <- 0
    for (state in seq_along(policy)) {
      value <- bellman(environment, values, gamma, state, policy[[state]])
      delta <- max(delta, abs(value - values[[state]]))
      values[[state]] <- value
    }
    if (delta <= theta) return(list(values = values, sweeps = sweeps))
  }
}
policy_iteration <- function(environment, gamma, theta) {
  policy <- rep.int(1L, length(environment$world$states))
  values <- numeric(length(policy))
  rounds <- list()
  repeat {
    evaluation <- evaluate_policy(environment, policy, values, gamma, theta)
    values <- evaluation$values
    improved <- greedy_policy(environment, values, gamma)
    changes <- sum(improved != policy)
    rounds[[length(rounds) + 1L]] <- c(evaluation$sweeps, changes, values[[environment$world$start_state]])
    policy <- improved
    if (changes == 0L) return(list(policy = policy, values = values, rounds = rounds))
  }
}
