discounted_return <- function(rewards, gamma) {
  value <- 0
  for (reward in rev(rewards)) value <- 10000 * reward + (gamma * value) %/% 100
  value
}
new_return_averages <- function(n) new_object(sums = matrix(0, n, 4L), counts = matrix(0L, n, 4L))
update_averages <- function(averages, learner, history, gamma) {
  seen <- character()
  first_visits <- logical(length(history))
  for (i in seq_along(history)) {
    step <- history[[i]]
    key <- paste(step[[1L]], step[[2L]], sep = ":")
    first_visits[[i]] <- !(key %in% seen)
    seen <- union(seen, key)
  }
  value <- 0
  for (i in rev(seq_along(history))) {
    step <- history[[i]]
    state <- step[[1L]]
    action <- step[[2L]]
    value <- 10000 * step[[3L]] + (gamma * value) %/% 100
    if (first_visits[[i]]) {
      averages$sums[state, action] <- averages$sums[state, action] + value
      averages$counts[state, action] <- averages$counts[state, action] + 1L
      learner$q[state, action] <- averages$sums[state, action] %/% averages$counts[state, action]
    }
  }
}
