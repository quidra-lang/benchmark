for (name in c(
    "environment",
    "dynamic_programming",
    "td_learning",
    "monte_carlo",
    "report"
)) source(paste0(name, ".R"))

METHODS <- c("mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q")
POLICY_NAMES <- c("value_iteration", "policy_iteration", METHODS)
ENDINGS <- c("goal", "pit", "timeout")
ABSORPTION_UNIT <- 100000000
pairs_of <- function(values) lapply(seq.int(1L, length(values), by = 2L), function(i) values[i:(i + 1L)])
read_settings <- function(path) {
  fields <- list()
  for (line in readLines(path, warn = FALSE)) {
    parts <- strsplit(line, " ", fixed = TRUE)[[1L]]
    fields[[parts[[1L]]]] <- as.numeric(parts[-1L])
  }
  list(gamma = fields$GAMMA, step_reward = fields$STEP_REWARD, slip_total = fields$SLIP[[1L]],
       floor_slip = fields$SLIP[[2L]], ice_slip = fields$SLIP[[3L]], theta = fields$THETA,
       gamma_sweep = fields$GAMMA_SWEEP, slip_sweep = pairs_of(fields$SLIP_SWEEP), episodes = fields$EPISODES,
       step_limit = fields$STEP_LIMIT, block_size = fields$BLOCK_SIZE, alpha_schedule = pairs_of(fields$ALPHA),
       epsilon_schedule = pairs_of(fields$EPSILON), planning_steps = fields$PLANNING_STEPS,
       seed = fields$SEED, rollouts = fields$ROLLOUTS, rollout_seed = fields$ROLLOUT_SEED)
}
schedule_value <- function(schedule, episode) {
  value <- schedule[[1L]][[2L]]
  for (pair in schedule) if (pair[[1L]] <= episode) value <- pair[[2L]]
  value
}
phase_ranges <- function(settings) {
  starts <- sort(unique(vapply(c(settings$alpha_schedule, settings$epsilon_schedule), `[[`, 0, 1L)))
  ends <- c(starts[-1L] - 1, settings$episodes)
  lapply(seq_along(starts), function(i) c(starts[[i]], ends[[i]]))
}
count_agreements <- function(first, second) sum(first == second)
ending_counts <- function(endings) vapply(ENDINGS, function(ending) sum(endings == ending), 0L)
policy_of <- function(q) apply(q, 1L, first_max)
state_visits <- function(learner) rowSums(learner$visits)
value_errors <- function(q, optimal) abs(apply(q, 1L, max) - optimal)
learn <- function(method, environment, settings, optimal_values, optimal_policy) {
  world <- environment$world
  n <- length(world$states)
  generator <- new_generator(settings$seed)
  learner <- new_object(
      method = method,
      q = matrix(0, n, 4L),
      visits = matrix(0L, n, 4L),
      episodes = list(),
      blocks = list()
  )
  model <- new_dyna_model(n)
  averages <- new_return_averages(n)
  for (number in seq_len(settings$episodes)) {
    alpha <- schedule_value(settings$alpha_schedule, number)
    epsilon <- schedule_value(settings$epsilon_schedule, number)
    state <- world$start_state
    total <- 0
    steps <- 0L
    ending <- "timeout"
    cells <- world$start
    history <- list()
    action <- if (method == "sarsa") choose(generator, learner$q[state, ], epsilon) else 1L
    while (steps < settings$step_limit) {
      if (method != "sarsa") action <- choose(generator, learner$q[state, ], epsilon)
      outcome <- environment_step(environment, generator, state, action)
      cell <- outcome[[1L]]
      r <- outcome[[2L]]
      learner$visits[state, action] <- learner$visits[state, action] + 1L
      total <- total + r
      steps <- steps + 1L
      cells <- c(cells, cell)
      next_state <- world$state_index[[cell]]
      terminal <- next_state == 0L
      if (method == "mc") history[[length(history) + 1L]] <- c(state, action, r) else if (method == "sarsa") {
        next_action <- if (terminal) action else choose(generator, learner$q[next_state, ], epsilon)
        next_value <- if (terminal) 0 else learner$q[next_state, next_action]
        td_update(learner, state, action, td_target(r, terminal, next_value, settings$gamma), alpha)
        action <- next_action
      } else {
        next_value <- if (terminal) 0 else if (method == "expected_sarsa") expected_value(
            learner$q[next_state, ],
            epsilon
        ) else max(learner$q[next_state, ])
        td_update(learner, state, action, td_target(r, terminal, next_value, settings$gamma), alpha)
        if (method == "dyna_q") {
          record_model(model, state, action, r, next_state)
          plan(model, generator, learner, settings$gamma, alpha, settings$planning_steps)
        }
      }
      if (terminal) {
        ending <- terminal_name(world, cell)
        break
      }
      state <- next_state
    }
    if (method == "mc") update_averages(averages, learner, history, settings$gamma)
    learner$episodes[[length(learner$episodes) + 1L]] <- list(
        total = total,
        steps = steps,
        ending = ending,
        cells = cells
    )
    if (number %% settings$block_size == 0) {
      agree <- count_agreements(policy_of(learner$q), optimal_policy)
      error <- sum(value_errors(learner$q, optimal_values)) %/% n
      coverage <- sum(state_visits(learner) > 0)
      learner$blocks[[length(learner$blocks) + 1L]] <- c(agree, error, coverage)
    }
  }
  learner
}
nominal_path <- function(environment, policy, origin, limit) {
  world <- environment$world
  cells <- origin
  repeat {
    state <- world$state_index[[tail(cells, 1L)]]
    target <- environment$moves[state, policy[[state]]]
    repeated <- target %in% cells
    cells <- c(cells, target)
    if (is_terminal(world, target)) return(list(ending = terminal_name(world, target), cells = cells))
    if (repeated) return(list(ending = "loop", cells = cells))
    if (length(cells) - 1L == limit) return(list(ending = "limit", cells = cells))
  }
}
basin_symbols <- function(environment, policy, limit) {
  world <- environment$world
  vapply(world$states, function(cell) {
    path <- nominal_path(environment, policy, cell, limit)
    if (path$ending %in% c("goal", "pit")) letters[[world$terminal_index[[tail(path$cells, 1L)]]]] else "*"
  }, "")
}
risky_states <- function(environment, policy) {
  sum(vapply(seq_along(policy), function(state) {
    any(vapply(
        environment$transitions[[state, policy[[state]]]],
        function(outcome) environment$world$kinds[[outcome[[1L]]]] == "P",
        FALSE
    ))
  }, FALSE))
}
distances <- function(environment) {
  world <- environment$world
  distance <- rep.int(-1L, length(world$kinds))
  distance[[world$start]] <- 0L
  queue <- world$start
  index <- 1L
  while (index <= length(queue)) {
    cell <- queue[[index]]
    index <- index + 1L
    state <- world$state_index[[cell]]
    for (action in seq_len(4L)) {
      for (outcome in environment$transitions[[state, action]]) {
        target <- outcome[[1L]]
        if (distance[[target]] == -1L) {
          distance[[target]] <- distance[[cell]] + 1L
          if (!is_terminal(world, target)) queue <- c(queue, target)
        }
      }
    }
  }
  distance
}
symmetry <- function(world, values, policy) {
  pairs <- equal <- mirrored <- 0L
  for (state in seq_along(world$states)) {
    cell <- world$states[[state]]
    row <- (cell - 1L) %/% world$cols
    col <- (cell - 1L) %% world$cols
    mirror_col <- world$cols - 1L - col
    other <- world$state_index[[row * world$cols + mirror_col + 1L]]
    if (col < mirror_col && other != 0L) {
      pairs <- pairs + 1L
      equal <- equal + as.integer(values[[state]] == values[[other]])
      mirrored <- mirrored + as.integer(policy[[other]] == c(1L, 4L, 3L, 2L)[[policy[[state]]]])
    }
  }
  c(pairs, equal, mirrored)
}
absorption <- function(environment, policy, limit) {
  world <- environment$world
  goal <- pit <- expected <- numeric(length(policy))
  for (i in seq_len(limit)) {
    next_goal <- next_pit <- next_expected <- numeric(length(policy))
    for (state in seq_along(policy)) {
      gt <- pt <- et <- 0
      for (outcome in environment$transitions[[state, policy[[state]]]]) {
        cell <- outcome[[1L]]
        weight <- outcome[[2L]]
        target <- world$state_index[[cell]]
        if (target != 0L) {
          gt <- gt + weight * goal[[target]]
          pt <- pt + weight * pit[[target]]
          et <- et + weight * expected[[target]]
        } else if (world$kinds[[cell]] == "G") gt <- gt + weight * ABSORPTION_UNIT else pt <- pt + weight * ABSORPTION_UNIT
      }
      next_goal[[state]] <- gt %/% environment$slip_total
      next_pit[[state]] <- pt %/% environment$slip_total
      next_expected[[state]] <- ABSORPTION_UNIT + et %/% environment$slip_total
    }
    goal <- next_goal
    pit <- next_pit
    expected <- next_expected
  }
  start <- world$start_state
  c(goal[[start]], pit[[start]], expected[[start]])
}
behaviour_value <- function(environment, policy, epsilon, gamma, theta) {
  values <- numeric(length(policy))
  sweeps <- 0L
  repeat {
    sweeps <- sweeps + 1L
    delta <- 0
    for (state in seq_along(policy)) {
      backups <- action_values(environment, values, gamma, state)
      weights <- rep.int(epsilon, 4L)
      weights[[policy[[state]]]] <- weights[[policy[[state]]]] + 4 * (1000 - epsilon)
      value <- sum(weights * backups) %/% 4000
      delta <- max(delta, abs(value - values[[state]]))
      values[[state]] <- value
    }
    if (delta <= theta) return(c(values[[environment$world$start_state]], sweeps))
  }
}
perform_rollouts <- function(environment, policy, settings) {
  world <- environment$world
  generator <- new_generator(settings$rollout_seed)
  returns <- discounted <- steps <- numeric()
  endings <- character()
  terminals <- integer(length(world$terminals))
  for (i in seq_len(settings$rollouts)) {
    state <- world$start_state
    rewards <- numeric()
    ending <- "timeout"
    while (length(rewards) < settings$step_limit) {
      outcome <- environment_step(environment, generator, state, policy[[state]])
      cell <- outcome[[1L]]
      rewards <- c(rewards, outcome[[2L]])
      state <- world$state_index[[cell]]
      if (state == 0L) {
        ending <- terminal_name(world, cell)
        terminal <- world$terminal_index[[cell]]
        terminals[[terminal]] <- terminals[[terminal]] + 1L
        break
      }
    }
    returns <- c(returns, sum(rewards))
    discounted <- c(discounted, discounted_return(rewards, settings$gamma))
    steps <- c(steps, length(rewards))
    endings <- c(endings, ending)
  }
  list(returns = returns, discounted = discounted, steps = steps, endings = endings, terminals = terminals)
}
evaluate_one <- function(environment, policy, settings, optimal_values, optimal_policy, optimal_actions) {
  evaluation <- evaluate_policy(environment, policy, numeric(length(policy)), settings$gamma, settings$theta)
  values <- evaluation$values
  gaps <- optimal_values - values
  improved <- greedy_policy(environment, values, settings$gamma)
  improved_values <- evaluate_policy(
      environment,
      improved,
      numeric(length(policy)),
      settings$gamma,
      settings$theta
  )$values
  list(values = values, sweeps = evaluation$sweeps, agree = count_agreements(policy, optimal_policy),
       optimal_actions = sum(vapply(
           seq_along(policy),
           function(state) policy[[state]] %in% optimal_actions[[state]],
           FALSE
       )),
       max_gap = max(gaps), gap_state = which.max(gaps), improved_changes = sum(improved != policy),
       improved_start = improved_values[[environment$world$start_state]], improved_agree = count_agreements(
           improved,
           optimal_policy
       ),
       absorption = absorption(
           environment,
           policy,
           settings$step_limit
       ), rollouts = perform_rollouts(environment, policy, settings))
}
sensitivity_text <- function(environment, gamma, settings, optimal_policy) {
  world <- environment$world
  result <- value_iteration(environment, gamma, settings$theta)
  policy <- greedy_policy(environment, result$values, gamma)
  path <- nominal_path(environment, policy, world$start, settings$step_limit)
  paste("iterations", length(result$changes), "value_start", fixed_text(result$values[[world$start_state]]),
        "path", path$ending, "steps", length(path$cells) - 1L, "last", cell_text(world, tail(path$cells, 1L)),
        "differences", sum(policy != optimal_policy))
}
values_report <- function(
    world,
    settings,
    environment,
    values,
    changes,
    q,
    optimal_policy,
    optimal_actions,
    in_place_sweeps,
    iteration_policy,
    iteration_values,
    rounds
) {
  state_text <- function(state) cell_text(world, world$states[[state]])
  n <- length(world$states)
  distance <- distances(environment)
  summary <- c(paste("world rows", world$rows, "cols", world$cols, "states", n, "walls", sum(world$kinds == "#"),
                     "floor", sum(world$kinds %in% c(
                         ".",
                         "S"
                     )), "ice", sum(world$kinds == "~"), "goals", sum(world$kinds == "G"), "pits", sum(world$kinds == "P")),
               paste("start", cell_text(world, world$start), "reachable", sum(distance[world$states] != -1L)))
  for (index in seq_along(world$terminals)) {
    cell <- world$terminals[[index]]
    steps <- if (distance[[cell]] == -1L) "-" else as.character(distance[[cell]])
    summary <- c(
        summary,
        paste(
            "terminal",
            cell_text(world, cell),
            terminal_name(world, cell),
            "reward",
            integer_text(world$rewards[[index]]),
            "distance",
            steps
        )
    )
  }
  vi <- paste(
      "value_iteration gamma",
      settings$gamma,
      "theta",
      fixed_text(settings$theta),
      "iterations",
      length(changes)
  )
  for (number in seq_along(changes)) vi <- c(
      vi,
      paste("iteration", number, "max_change", fixed_text(changes[[number]]))
  )
  tied <- which(lengths(optimal_actions) > 1L)
  ties <- paste("ties", length(tied))
  for (state in tied) ties <- c(
      ties,
      paste("tie", state_text(state), paste(ACTION_LETTERS[optimal_actions[[state]]], collapse = ""))
  )
  mirrored <- symmetry(world, values, optimal_policy)
  ties <- c(
      ties,
      paste(
          "symmetry pairs",
          mirrored[[1L]],
          "equal_values",
          mirrored[[2L]],
          "mirrored_actions",
          mirrored[[3L]]
      )
  )
  pi <- paste("policy_iteration rounds", length(rounds))
  for (number in seq_along(rounds)) {
    round <- rounds[[number]]
    pi <- c(
        pi,
        paste(
            "round",
            number,
            "sweeps",
            round[[1L]],
            "changed",
            round[[2L]],
            "value_start",
            fixed_text(round[[3L]])
        )
    )
  }
  differences <- abs(iteration_values - values)
  comparison <- c(paste("comparison policy_differences", sum(iteration_policy != optimal_policy), "max_value_difference", fixed_text(max(differences)), "at", state_text(which.max(differences))),
                  paste("backups value_iteration", integer_text(length(changes) * n * 4), "in_place_iterations", in_place_sweeps, "in_place", integer_text(in_place_sweeps * n * 4),
                        "policy_iteration", integer_text(sum(vapply(rounds, `[[`, 0, 1L)) * n + length(rounds) * n * 4)))
  gamma_sweep <- "gamma_sweep"
  for (gamma in settings$gamma_sweep) gamma_sweep <- c(
      gamma_sweep,
      paste("gamma", gamma, sensitivity_text(environment, gamma, settings, optimal_policy))
  )
  slip_sweep <- "slip_sweep"
  for (pair in settings$slip_sweep) {
    altered <- new_environment(world, settings$step_reward, settings$slip_total, pair[[1L]], pair[[2L]])
    slip_sweep <- c(
        slip_sweep,
        paste(
            "slip",
            pair[[1L]],
            pair[[2L]],
            sensitivity_text(altered, settings$gamma, settings, optimal_policy)
        )
    )
  }
  join_parts(list(summary, vi, c("optimal_values", value_grid(world, values)), c("optimal_action_counts", symbol_grid(world, as.character(lengths(optimal_actions)))),
                  ties, pi, c(
                      "policy_iteration_values",
                      value_grid(world, iteration_values)
                  ), comparison, gamma_sweep, slip_sweep))
}
policies_report <- function(world, settings, environment, policies, learners) {
  parts <- list()
  for (index in seq_along(policies)) {
    name <- POLICY_NAMES[[index]]
    policy <- policies[[index]]
    path <- nominal_path(environment, policy, world$start, settings$step_limit)
    counts <- vapply(seq_len(4L), function(action) sum(policy == action), 0L)
    lines <- c(name, policy_grid(world, policy), paste("path", path$ending, "steps", length(path$cells) - 1L, cells_text(world, path$cells)),
               paste(
                   "actions N",
                   counts[[1L]],
                   "E",
                   counts[[2L]],
                   "S",
                   counts[[3L]],
                   "W",
                   counts[[4L]],
                   "risk",
                   risky_states(environment, policy)
               ),
               "basins", symbol_grid(world, basin_symbols(environment, policy, settings$step_limit)))
    if (index >= 3L) {
      totals <- state_visits(learners[[index - 2L]])
      digits <- ifelse(totals == 0, "0", as.character(nchar(integer_text(totals))))
      lines <- c(lines, "visits", symbol_grid(world, digits))
    }
    parts[[length(parts) + 1L]] <- lines
  }
  join_parts(parts)
}
block_episodes <- function(learner, number, size) learner$episodes[seq.int(
    (number - 1L) * size + 1L,
    number * size
)]
episode_sum <- function(episodes, name) sum(vapply(episodes, `[[`, 0, name))
episode_endings <- function(episodes) vapply(episodes, `[[`, "", "ending")
learning_curves <- function(learners, settings) {
  lines <- "method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"
  for (learner in learners) {
    for (number in seq_along(learner$blocks)) {
      block <- learner$blocks[[number]]
      episodes <- block_episodes(learner, number, settings$block_size)
      fields <- c(learner$method, number, average_text(episode_sum(episodes, "total"), settings$block_size),
                  average_text(
                      episode_sum(episodes, "steps"),
                      settings$block_size
                  ), ending_counts(episode_endings(episodes)),
                  block[[1L]], fixed_text(block[[2L]]), block[[3L]])
      lines <- c(lines, paste(fields, collapse = ","))
    }
  }
  lines
}
evaluation_report <- function(
    world,
    settings,
    environment,
    optimal_values,
    optimal_q,
    policies,
    learners,
    evaluations
) {
  n <- length(world$states)
  start <- world$start_state
  state_text <- function(state) cell_text(world, world$states[[state]])
  parts <- list(paste(
      "summary states",
      n,
      "start",
      cell_text(world, world$start),
      "rollouts",
      settings$rollouts,
      "step_limit",
      settings$step_limit
  ))
  policy_values <- c("policies", "policy agree optimal_actions value_start sweeps max_gap at")
  improvement <- c("improvement", "policy changed value_start agree")
  absorption_lines <- c("absorption", "policy p_goal p_pit p_timeout expected_steps")
  rollout_lines <- c(
      "rollouts",
      "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"
  )
  terminals <- c("terminals", paste("policy", cells_text(world, world$terminals)))
  for (index in seq_along(evaluations)) {
    name <- POLICY_NAMES[[index]]
    evaluation <- evaluations[[index]]
    policy_values <- c(
        policy_values,
        paste(
            name,
            evaluation$agree,
            evaluation$optimal_actions,
            fixed_text(evaluation$values[[start]]),
            evaluation$sweeps,
            fixed_text(evaluation$max_gap),
            state_text(evaluation$gap_state)
        )
    )
    improvement <- c(
        improvement,
        paste(
            name,
            evaluation$improved_changes,
            fixed_text(evaluation$improved_start),
            evaluation$improved_agree
        )
    )
    values <- evaluation$absorption
    fields <- fixed_text(c(
        values[[1L]],
        values[[2L]],
        ABSORPTION_UNIT - values[[1L]] - values[[2L]],
        values[[3L]]
    ) %/% 10000)
    absorption_lines <- c(absorption_lines, paste(c(name, fields), collapse = " "))
    summary <- evaluation$rollouts
    returns <- sort(summary$returns)
    fields <- c(name, average_text(sum(summary$returns), settings$rollouts), fixed_text(sum(summary$discounted) %/% settings$rollouts),
                average_text(
                    sum(summary$steps),
                    settings$rollouts
                ), integer_text(ending_counts(summary$endings)),
                integer_text(c(returns[[1L]], returns[[(settings$rollouts + 1) %/% 2]], tail(returns, 1L))))
    rollout_lines <- c(rollout_lines, paste(fields, collapse = " "))
    terminals <- c(terminals, paste(c(name, integer_text(summary$terminals)), collapse = " "))
  }
  parts <- c(parts, list(policy_values, improvement, absorption_lines))
  behaviour <- c("behaviour", "method epsilon value_start sweeps")
  q_errors <- c("q_errors", "method mean_abs max_abs at unvisited tied")
  q_action_errors <- c("q_action_errors", "method N E S W")
  training <- c("training", "method steps goals pits timeouts best_block best_mean last_mean reach")
  visited <- "visited"
  last_episodes <- "last_episodes"
  phases <- "phases"
  epsilon <- schedule_value(settings$epsilon_schedule, settings$episodes)
  optimal_total <- sum(evaluations[[1L]]$rollouts$returns)
  for (learner in learners) {
    name <- learner$method
    policy <- policy_of(learner$q)
    value <- behaviour_value(environment, policy, epsilon, settings$gamma, settings$theta)
    behaviour <- c(behaviour, paste(name, epsilon, fixed_text(value[[1L]]), value[[2L]]))
    errors <- value_errors(learner$q, optimal_values)
    totals <- state_visits(learner)
    tied <- sum(apply(learner$q, 1L, function(row) sum(row == max(row)) > 1L))
    q_errors <- c(
        q_errors,
        paste(
            name,
            fixed_text(sum(errors) %/% n),
            fixed_text(max(errors)),
            state_text(which.max(errors)),
            sum(totals == 0),
            tied
        )
    )
    fields <- name
    for (action in seq_len(4L)) {
      states <- which(learner$visits[, action] > 0L)
      total <- sum(abs(learner$q[states, action] - optimal_q[states, action]))
      fields <- c(fields, if (length(states)) fixed_text(total %/% length(states)) else "-")
    }
    q_action_errors <- c(q_action_errors, paste(fields, collapse = " "))
    block_returns <- vapply(
        seq_along(learner$blocks),
        function(number) episode_sum(block_episodes(learner, number, settings$block_size), "total"),
        0
    )
    best <- which.max(block_returns)
    reached <- which(10 * settings$rollouts * block_returns >= 9 * settings$block_size * optimal_total)
    reach <- if (length(reached)) as.character(reached[[1L]]) else "-"
    fields <- c(name, integer_text(episode_sum(learner$episodes, "steps")), integer_text(ending_counts(episode_endings(learner$episodes))), best,
                average_text(block_returns[[best]], settings$block_size), average_text(
                    tail(block_returns, 1L),
                    settings$block_size
                ), reach)
    training <- c(training, paste(fields, collapse = " "))
    positions <- order(-totals, seq_len(n), method = "radix")[1L:3L]
    entries <- vapply(
        positions,
        function(state) paste0(state_text(state), ":", integer_text(totals[[state]])),
        ""
    )
    visited <- c(visited, paste(c(name, entries), collapse = " "))
    episode <- tail(learner$episodes, 1L)[[1L]]
    last_episodes <- c(
        last_episodes,
        paste(
            name,
            "return",
            integer_text(episode$total),
            "steps",
            episode$steps,
            "end",
            episode$ending,
            cells_text(world, episode$cells)
        )
    )
    for (phase in phase_ranges(settings)) {
      first <- phase[[1L]]
      last <- phase[[2L]]
      episodes <- learner$episodes[seq.int(first, last)]
      phases <- c(phases, paste(name, paste0(first, "-", last), "alpha", schedule_value(settings$alpha_schedule, first),
                                "epsilon", schedule_value(settings$epsilon_schedule, first), "mean_return", average_text(
                                    episode_sum(episodes, "total"),
                                    length(episodes)
                                ),
                                "mean_steps", average_text(
                                    episode_sum(episodes, "steps"),
                                    length(episodes)
                                ), "goals", sum(episode_endings(episodes) == "goal")))
    }
  }
  parts <- c(parts, list(behaviour, q_errors, q_action_errors, rollout_lines, terminals))
  agreement <- c("agreement", paste("policy", paste(POLICY_NAMES, collapse = " ")))
  for (index in seq_along(policies)) {
    counts <- vapply(policies, function(other) count_agreements(policies[[index]], other), 0L)
    agreement <- c(agreement, paste(c(POLICY_NAMES[[index]], counts), collapse = " "))
  }
  join_parts(c(parts, list(agreement, training, visited, last_episodes, phases)))
}
main <- function() {
  world <- read_world(file.path("input", "world.txt"))
  settings <- read_settings(file.path("input", "params.txt"))
  environment <- new_environment(
      world,
      settings$step_reward,
      settings$slip_total,
      settings$floor_slip,
      settings$ice_slip
  )
  result <- value_iteration(environment, settings$gamma, settings$theta)
  values <- result$values
  q <- t(vapply(
      seq_along(values),
      function(state) action_values(environment, values, settings$gamma, state),
      numeric(4L)
  ))
  optimal_policy <- policy_of(q)
  optimal_actions <- lapply(seq_along(values), function(state) which(q[state, ] == max(q[state, ])))
  in_place_sweeps <- in_place_value_iteration(environment, settings$gamma, settings$theta)$sweeps
  iteration <- policy_iteration(environment, settings$gamma, settings$theta)
  learners <- lapply(METHODS, function(method) learn(method, environment, settings, values, optimal_policy))
  policies <- c(
      list(optimal_policy, iteration$policy),
      lapply(learners, function(learner) policy_of(learner$q))
  )
  evaluations <- lapply(
      policies,
      function(policy) evaluate_one(environment, policy, settings, values, optimal_policy, optimal_actions)
  )
  table <- c("method,row,col,action,value,visits", q_table_rows(world, "value_iteration", q, NULL))
  for (learner in learners) table <- c(table, q_table_rows(world, learner$method, learner$q, learner$visits))
  outputs <- list(
    "values.txt" = values_report(
        world,
        settings,
        environment,
        values,
        result$changes,
        q,
        optimal_policy,
        optimal_actions,
        in_place_sweeps,
        iteration$policy,
        iteration$values,
        iteration$rounds
    ),
    "policies.txt" = policies_report(world, settings, environment, policies, learners),
    "q_tables.csv" = table, "learning_curves.csv" = learning_curves(learners, settings),
    "evaluation.txt" = evaluation_report(
        world,
        settings,
        environment,
        values,
        q,
        policies,
        learners,
        evaluations
    )
  )
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) write_lines(file.path("output", name), outputs[[name]])
}
main()
