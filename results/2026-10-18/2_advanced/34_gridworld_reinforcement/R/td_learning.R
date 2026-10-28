choose <- function(generator, row, epsilon) {
  if (draw(generator) %% 1000 < epsilon) as.integer(draw(generator) %% 4) + 1L else first_max(row)
}
td_target <- function(
    reward,
    terminal,
    next_value,
    gamma
) 10000 * reward + if (terminal) 0 else (gamma * next_value) %/% 100
expected_value <- function(row, epsilon) (epsilon * sum(row) + 4 * (1000 - epsilon) * max(row)) %/% 4000
td_update <- function(learner, state, action, target, alpha) {
  learner$q[state, action] <- learner$q[state, action] + (alpha * (target - learner$q[state, action])) %/% 100
}
new_dyna_model <- function(n) new_object(outcomes = matrix(vector("list", n * 4L), n, 4L), pairs = list())
record_model <- function(model, state, action, reward, next_state) {
  if (is.null(model$outcomes[[state, action]])) model$pairs[[length(model$pairs) + 1L]] <- c(state, action)
  model$outcomes[[state, action]] <- c(reward, next_state)
}
plan <- function(model, generator, learner, gamma, alpha, count) {
  for (i in seq_len(count)) {
    pair <- model$pairs[[draw(generator) %% length(model$pairs) + 1L]]
    state <- pair[[1L]]
    action <- pair[[2L]]
    outcome <- model$outcomes[[state, action]]
    next_state <- outcome[[2L]]
    next_value <- if (next_state == 0L) 0 else max(learner$q[next_state, ])
    td_update(learner, state, action, td_target(outcome[[1L]], next_state == 0L, next_value, gamma), alpha)
  }
}
