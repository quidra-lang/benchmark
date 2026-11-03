ACTION_LETTERS <- c("N", "E", "S", "W")
ROW_STEPS <- c(-1L, 0L, 1L, 0L)
COLUMN_STEPS <- c(0L, 1L, 0L, -1L)
new_object <- function(...) list2env(list(...), parent = emptyenv())
read_world <- function(path) {
  lines <- readLines(path, warn = FALSE)
  rows <- as.integer(strsplit(lines[[1L]], " ", fixed = TRUE)[[1L]][[2L]])
  cols <- as.integer(strsplit(lines[[2L]], " ", fixed = TRUE)[[1L]][[2L]])
  kinds <- strsplit(paste(lines[seq.int(3L, rows + 2L)], collapse = ""), "", fixed = TRUE)[[1L]]
  wind <- as.integer(strsplit(
      strsplit(lines[[rows + 3L]], " ", fixed = TRUE)[[1L]][[2L]],
      "",
      fixed = TRUE
  )[[1L]])
  rewards <- as.numeric(strsplit(lines[[rows + 4L]], " ", fixed = TRUE)[[1L]][-1L])
  terminals <- which(kinds %in% c("G", "P"))
  states <- which(!(kinds %in% c("#", "G", "P")))
  state_index <- terminal_index <- integer(length(kinds))
  state_index[states] <- seq_along(states)
  terminal_index[terminals] <- seq_along(terminals)
  start <- which(kinds == "S")
  list(rows = rows, cols = cols, kinds = kinds, wind = wind, rewards = rewards,
       states = states, terminals = terminals, state_index = state_index, terminal_index = terminal_index,
       start = start, start_state = state_index[[start]])
}
is_terminal <- function(world, cell) world$terminal_index[[cell]] != 0L
terminal_name <- function(world, cell) if (world$kinds[[cell]] == "G") "goal" else "pit"
move <- function(world, cell, direction) {
  target <- cell + ROW_STEPS[[direction]] * world$cols + COLUMN_STEPS[[direction]]
  if (world$kinds[[target]] == "#") target <- cell
  if (is_terminal(world, target)) return(target)
  for (i in seq_len(world$wind[[(cell - 1L) %% world$cols + 1L]])) {
    above <- target - world$cols
    if (world$kinds[[above]] == "#") break
    target <- above
    if (is_terminal(world, target)) break
  }
  target
}
new_generator <- function(seed) new_object(value = seed)
draw <- function(generator) {
  generator$value <- (48271 * generator$value) %% 2147483647
  generator$value
}
new_environment <- function(world, step_reward, total, floor_slip, ice_slip) {
  n <- length(world$states)
  moves <- matrix(0L, n, 4L)
  transitions <- matrix(vector("list", n * 4L), n, 4L)
  for (state in seq_len(n)) {
    for (direction in seq_len(4L)) moves[state, direction] <- move(world, world$states[[state]], direction)
    slip <- if (world$kinds[[world$states[[state]]]] == "~") ice_slip else floor_slip
    for (action in seq_len(4L)) {
      directions <- c(action, action %% 4L + 1L, (action + 2L) %% 4L + 1L)
      weights <- c(total - 2 * slip, slip, slip)
      outcomes <- list()
      for (i in seq_len(3L)) if (weights[[i]] > 0) outcomes[[length(outcomes) + 1L]] <- c(
          moves[state, directions[[i]]],
          weights[[i]]
      )
      transitions[[state, action]] <- outcomes
    }
  }
  list(world = world, step_reward = step_reward, slip_total = total, floor_slip = floor_slip,
       ice_slip = ice_slip, moves = moves, transitions = transitions)
}
reward <- function(environment, cell) {
  index <- environment$world$terminal_index[[cell]]
  if (index == 0L) environment$step_reward else environment$world$rewards[[index]]
}
environment_step <- function(environment, generator, state, action) {
  sample <- draw(generator) %% environment$slip_total
  slip <- if (environment$world$kinds[[environment$world$states[[state]]]] == "~") environment$ice_slip else environment$floor_slip
  direction <- if (sample < environment$slip_total - 2 * slip) action else if (sample < environment$slip_total - slip) action %% 4L + 1L else (action + 2L) %% 4L + 1L
  cell <- environment$moves[state, direction]
  c(cell, reward(environment, cell))
}
