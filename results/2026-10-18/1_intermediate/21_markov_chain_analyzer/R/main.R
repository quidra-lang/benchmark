gcd_exact <- function(a, b) {
  a <- abs(a)
  b <- abs(b)
  while (b != 0) {
    remainder <- a %% b
    a <- b
    b <- remainder
  }
  a
}

fraction <- function(n, d = 1) {
  if (d < 0) {
    n <- -n
    d <- -d
  }
  divisor <- gcd_exact(n, d)
  c(n / divisor, d / divisor)
}
zero <- fraction(0)
one <- fraction(1)
add <- function(a, b) fraction(a[1] * b[2] + b[1] * a[2], a[2] * b[2])
subtract <- function(a, b) fraction(a[1] * b[2] - b[1] * a[2], a[2] * b[2])
multiply <- function(a, b) fraction(a[1] * b[1], a[2] * b[2])
divide <- function(a, b) fraction(a[1] * b[2], a[2] * b[1])
equal <- function(a, b) a[1] == b[1] && a[2] == b[2]
greater <- function(a, b) a[1] * b[2] > b[1] * a[2]
less <- function(a, b) greater(b, a)
absolute <- function(a) fraction(abs(a[1]), a[2])
delta <- function(i, j) if (i == j) one else zero
sum_fractions <- function(xs) Reduce(add, xs, init = zero)
text_number <- function(x) sprintf("%.0f", x)
fraction_text <- function(x) paste0(text_number(x[1]), "/", text_number(x[2]))
value_text <- function(x) {
  whole <- floor(x[1] / x[2])
  digits <- floor((x[1] %% x[2]) * 1000000 / x[2])
  paste0(fraction_text(x), "(", text_number(whole), ".", sprintf("%06d", as.integer(digits)), ")")
}
time_text <- function(x) if (is.null(x)) "inf" else value_text(x)
yesno <- function(x) if (x) "yes" else "no"
command_error <- function(message) {
  stop(structure(list(message = message, call = NULL),
                 class = c("markov_command_error", "error", "condition")))
}

probability <- function(text) {
  parts <- strsplit(text, "/", fixed = TRUE)[[1]]
  numerator <- as.numeric(parts[1])
  denominator <- if (length(parts) == 2) as.numeric(parts[2]) else 1
  if (denominator == 0 || numerator > denominator) command_error("BAD PROBABILITY")
  fraction(numerator, denominator)
}

identity_matrix <- function(size) {
  lapply(seq_len(size), function(i) lapply(seq_len(size), function(j) delta(i, j)))
}

eliminate <- function(rows, size) {
  if (size == 0) return(list())
  for (column in seq_len(size)) {
    pivot_row <- column
    while (equal(rows[[pivot_row]][[column]], zero))
      pivot_row <- pivot_row + 1
    if (pivot_row != column) {
      temporary <- rows[[column]]
      rows[[column]] <- rows[[pivot_row]]
      rows[[pivot_row]] <- temporary
    }
    pivot <- rows[[column]][[column]]
    rows[[column]] <- lapply(rows[[column]], divide, b = pivot)
    for (row in seq_len(size)) {
      factor <- rows[[row]][[column]]
      if (row != column && !equal(factor, zero)) {
        rows[[row]] <- Map(function(value, base)
          subtract(value, multiply(factor, base)), rows[[row]], rows[[column]])
      }
    }
  }
  lapply(rows, function(row) tail(row, length(row) - size))
}

create_chain <- function(names) {
  chain <- new.env(parent = emptyenv())
  chain$names <- names
  chain$matrix <- lapply(seq_along(names), function(i)
    replicate(length(names), zero, simplify = FALSE))
  chain
}
chain_size <- function(chain) length(chain$names)
state_index <- function(chain, text) {
  position <- match(text, chain$names)
  if (is.na(position)) command_error(paste("UNKNOWN STATE", text))
  position
}
distinct_states <- function(chain, texts) {
  indices <- integer()
  for (text in texts) {
    position <- state_index(chain, text)
    if (position %in% indices) command_error(paste("DUPLICATE STATE", text))
    indices <- c(indices, position)
  }
  indices
}
row_sum <- function(chain, i) sum_fractions(chain$matrix[[i]])
block_sum <- function(chain, i, block)
  sum_fractions(lapply(block, function(j) chain$matrix[[i]][[j]]))
edge <- function(chain, i, j) greater(chain$matrix[[i]][[j]], zero)
absorbing_state <- function(chain, i) equal(chain$matrix[[i]][[i]], one)
labels <- function(chain, members) chain$names[members]
member_mask <- function(size, members) {
  inside <- rep(FALSE, size)
  inside[members] <- TRUE
  inside
}
advance <- function(chain, distribution) {
  n <- chain_size(chain)
  lapply(seq_len(n), function(j)
    sum_fractions(lapply(seq_len(n), function(i)
      multiply(distribution[[i]], chain$matrix[[i]][[j]]))))
}

reachable <- function(chain, start) {
  n <- chain_size(chain)
  seen <- rep(FALSE, n)
  seen[start] <- TRUE
  pending <- c(start)
  while (length(pending)) {
    i <- tail(pending, 1)
    pending <- head(pending, -1)
    for (j in seq_len(n)) {
      if (edge(chain, i, j) && !seen[j]) {
        seen[j] <- TRUE
        pending <- c(pending, j)
      }
    }
  }
  seen
}

communicating_class <- function(chain, number, members) {
  n <- chain_size(chain)
  inside <- member_mask(n, members)
  closed <- !any(vapply(members, function(i)
    any(vapply(seq_len(n), function(j)
      edge(chain, i, j) && !inside[j], logical(1))), logical(1)))
  levels <- rep(-1, n)
  levels[members[1]] <- 0
  queue <- c(members[1])
  index <- 1
  while (index <= length(queue)) {
    u <- queue[index]
    index <- index + 1
    for (v in members) {
      if (edge(chain, u, v) && levels[v] < 0) {
        levels[v] <- levels[u] + 1
        queue <- c(queue, v)
      }
    }
  }
  period <- 0
  for (u in members) {
    for (v in members) {
      if (edge(chain, u, v))
        period <- gcd_exact(period, levels[u] + 1 - levels[v])
    }
  }
  list(number = number, members = members, closed = closed,
       levels = levels, period = period)
}

decompose <- function(chain) {
  n <- chain_size(chain)
  reach <- lapply(seq_len(n), function(i) reachable(chain, i))
  classes <- list()
  class_of <- integer(n)
  for (i in seq_len(n)) {
    if (class_of[i] == 0) {
      members <- which(reach[[i]] & vapply(seq_len(n),
        function(j) reach[[j]][i], logical(1)))
      number <- length(classes) + 1
      class_of[members] <- number
      classes[[number]] <- communicating_class(chain, number, members)
    }
  }
  list(reach = reach, classes = classes, class_of = class_of)
}
closed_classes <- function(decomp) Filter(function(item) item$closed, decomp$classes)
reaches_targets <- function(decomp, i, targets) any(decomp$reach[[i]] & targets)

absorption <- function(chain) {
  n <- chain_size(chain)
  absorbing <- which(vapply(seq_len(n), function(i)
    absorbing_state(chain, i), logical(1)))
  transient <- setdiff(seq_len(n), absorbing)
  count <- length(transient)
  if (count == 0) {
    return(list(transient = transient, absorbing = absorbing,
                fundamental = list(), steps = list(), probabilities = list()))
  }
  equations <- lapply(seq_len(count), function(row) {
    i <- transient[row]
    left <- lapply(transient, function(j)
      subtract(delta(i, j), chain$matrix[[i]][[j]]))
    c(left, lapply(seq_len(count), function(j) delta(row, j)))
  })
  fundamental <- eliminate(equations, count)
  steps <- lapply(fundamental, sum_fractions)
  probabilities <- lapply(fundamental, function(row)
    lapply(absorbing, function(a) sum_fractions(
      lapply(seq_len(count), function(k)
        multiply(row[[k]], chain$matrix[[transient[k]]][[a]])))))
  list(transient = transient, absorbing = absorbing,
       fundamental = fundamental, steps = steps, probabilities = probabilities)
}

absorption_variance <- function(result, i) {
  n <- length(result$transient)
  total <- sum_fractions(lapply(seq_len(n), function(j)
    multiply(subtract(multiply(fraction(2), result$fundamental[[i]][[j]]),
                      delta(i, j)), result$steps[[j]])))
  subtract(total, multiply(result$steps[[i]], result$steps[[i]]))
}

stationary_distribution <- function(chain, members) {
  n <- length(members)
  rows <- vector("list", n)
  if (n > 1) {
    for (r in seq_len(n - 1)) {
      coefficients <- lapply(seq_len(n), function(k)
        subtract(chain$matrix[[members[k]]][[members[r]]], delta(k, r)))
      rows[[r]] <- c(coefficients, list(zero))
    }
  }
  rows[[n]] <- c(rep(list(one), n), list(one))
  lapply(eliminate(rows, n), function(row) row[[1]])
}

irreducible_distribution <- function(chain, decomp) {
  if (length(decomp$classes) > 1) command_error("NOT IRREDUCIBLE")
  stationary_distribution(chain, decomp$classes[[1]]$members)
}

solve_restricted <- function(chain, states, constants) {
  n <- length(states)
  if (n == 0) return(list())
  equations <- lapply(seq_len(n), function(row) {
    i <- states[row]
    coefficients <- lapply(states, function(j)
      subtract(delta(i, j), chain$matrix[[i]][[j]]))
    c(coefficients, list(constants[[row]]))
  })
  lapply(eliminate(equations, n), function(row) row[[1]])
}

hitting_probabilities <- function(chain, decomp, targets) {
  n <- chain_size(chain)
  probabilities <- lapply(seq_len(n), function(i) if (targets[i]) one else zero)
  remaining <- which(!targets & vapply(seq_len(n),
    function(i) reaches_targets(decomp, i, targets), logical(1)))
  if (length(remaining)) {
    constants <- lapply(remaining, function(i)
      sum_fractions(lapply(which(targets), function(j) chain$matrix[[i]][[j]])))
    solved <- solve_restricted(chain, remaining, constants)
    for (k in seq_along(remaining)) probabilities[[remaining[k]]] <- solved[[k]]
  }
  probabilities
}

hitting_times <- function(chain, targets, probabilities) {
  n <- chain_size(chain)
  times <- lapply(seq_len(n), function(i) if (targets[i]) zero else NULL)
  certain <- which(!targets & vapply(probabilities, function(p) equal(p, one), logical(1)))
  if (length(certain)) {
    solved <- solve_restricted(chain, certain, rep(list(one), length(certain)))
    for (k in seq_along(certain)) times[certain[k]] <- list(solved[[k]])
  }
  times
}

regular_exponent <- function(chain) {
  n <- chain_size(chain)
  adjacent <- matrix(FALSE, n, n)
  for (i in seq_len(n)) for (j in seq_len(n)) adjacent[i, j] <- edge(chain, i, j)
  power <- adjacent
  for (exponent in seq_len((n - 1)^2 + 1)) {
    if (all(power)) return(exponent)
    power <- (power %*% adjacent) > 0
  }
  NULL
}

chains <- new.env(parent = emptyenv(), hash = TRUE)
output <- character()
emit <- function(...) {
  values <- unlist(list(...), use.names = FALSE)
  text <- vapply(values, function(x) {
    if (is.numeric(x)) text_number(x) else as.character(x)
  }, character(1))
  output <<- c(output, paste(text, collapse = " "))
}
display_matrix <- function(names, values, label = "ROW") {
  emit("STATES", names)
  for (i in seq_along(names))
    emit(label, names[i], vapply(values[[i]], fraction_text, character(1)))
}
require_chain <- function(name) {
  if (!exists(name, envir = chains, inherits = FALSE))
    command_error(paste("UNKNOWN CHAIN", name))
  get(name, envir = chains, inherits = FALSE)
}
require_stochastic <- function(name) {
  chain <- require_chain(name)
  for (i in seq_len(chain_size(chain))) {
    if (!equal(row_sum(chain, i), one))
      command_error(paste("NOT STOCHASTIC", chain$names[i]))
  }
  chain
}
put_chain <- function(name, chain) assign(name, chain, envir = chains)

execute_command <- function(command, a) {
  if (command == "CHAIN") {
    name <- a[1]
    states <- a[-1]
    if (length(states) > 10) command_error("TOO MANY STATES")
    seen <- character()
    for (state in states) {
      if (state %in% seen) command_error(paste("DUPLICATE STATE", state))
      seen <- c(seen, state)
    }
    put_chain(name, create_chain(states))
    emit("CHAIN", name, paste0("states=", length(states)))
    return(invisible(NULL))
  }
  if (command == "BUILD") {
    name <- a[1]
    order <- as.numeric(a[2])
    tokens <- a[-c(1, 2)]
    if (!(order %in% c(1, 2))) command_error("BAD ORDER")
    if (length(tokens) <= order) command_error("TOO FEW TOKENS")
    observations <- if (order == 1) tokens else paste(head(tokens, -1), tail(tokens, -1), sep = ".")
    states <- unique(observations)
    if (length(states) > 10) command_error("TOO MANY STATES")
    chain <- create_chain(states)
    n <- chain_size(chain)
    counts <- matrix(0, n, n)
    for (t in seq_len(length(observations) - 1)) {
      i <- match(observations[t], states)
      j <- match(observations[t + 1], states)
      counts[i, j] <- counts[i, j] + 1
    }
    emit("BUILD", name, paste0("order=", order), paste0("states=", n),
         paste0("transitions=", length(observations) - 1))
    for (i in seq_len(n)) {
      total <- sum(counts[i, ])
      if (total == 0) {
        chain$matrix[[i]][[i]] <- one
        emit("FROM", states[i], "total=0", "absorbing")
      } else {
        parts <- character()
        for (j in seq_len(n)) {
          if (counts[i, j] > 0) {
            chain$matrix[[i]][[j]] <- fraction(counts[i, j], total)
            parts <- c(parts, paste0(states[j], ":", counts[i, j]))
          }
        }
        emit("FROM", states[i], paste0("total=", total), parts)
      }
    }
    put_chain(name, chain)
    return(invisible(NULL))
  }
  if (command == "GAMBLER") {
    name <- a[1]
    goal <- as.numeric(a[2])
    start <- as.numeric(a[3])
    if (goal == 0 || goal > 9) command_error("BAD SIZE")
    if (start > goal) command_error("BAD START")
    p <- probability(a[4])
    if (equal(p, zero) || equal(p, one)) command_error("BAD PROBABILITY")
    chain <- create_chain(paste0("s", 0:goal))
    chain$matrix[[1]][[1]] <- one
    chain$matrix[[goal + 1]][[goal + 1]] <- one
    if (goal > 1) {
      for (i in 2:goal) {
        chain$matrix[[i]][[i + 1]] <- p
        chain$matrix[[i]][[i - 1]] <- subtract(one, p)
      }
    }
    put_chain(name, chain)
    result <- absorption(chain)
    ruin <- c(list(one), lapply(result$probabilities, function(x) x[[1]]), list(zero))
    duration <- c(list(zero), result$steps, list(zero))
    emit("GAMBLER", name, paste0("g=", goal), paste0("p=", fraction_text(p)),
         paste0("start=s", start), paste0("ruin=", value_text(ruin[[start + 1]])),
         paste0("duration=", value_text(duration[[start + 1]])))
    for (i in 0:goal) {
      emit("CAPITAL", paste0("s", i), paste0("ruin=", value_text(ruin[[i + 1]])),
           paste0("win=", value_text(subtract(one, ruin[[i + 1]]))),
           paste0("duration=", value_text(duration[[i + 1]])))
    }
    return(invisible(NULL))
  }

  chain <- if (command %in% c("P", "ROW", "SHOW", "CHECK"))
    require_chain(a[1]) else require_stochastic(a[1])
  n <- chain_size(chain)
  name <- a[1]

  if (command == "P") {
    i <- state_index(chain, a[2])
    j <- state_index(chain, a[3])
    value <- probability(a[4])
    chain$matrix[[i]][[j]] <- value
    emit("P", name, a[2], a[3], fraction_text(value),
         paste0("rowsum=", fraction_text(row_sum(chain, i))))
  } else if (command == "ROW") {
    i <- state_index(chain, a[2])
    if (length(a) - 2 != n) command_error("BAD LENGTH")
    values <- lapply(a[-c(1, 2)], probability)
    chain$matrix[[i]] <- values
    emit("ROW", name, a[2], paste0("rowsum=", fraction_text(row_sum(chain, i))))
  } else if (command == "SHOW") {
    emit("MATRIX", name, paste0("states=", n))
    display_matrix(chain$names, chain$matrix)
  } else if (command == "CHECK") {
    bad <- which(!vapply(seq_len(n), function(i) equal(row_sum(chain, i), one), logical(1)))
    if (!length(bad)) emit("CHECK", name, "ok") else {
      emit("CHECK", name, paste0("bad=", length(bad)))
      for (i in bad) emit("BADROW", chain$names[i], paste0("sum=", fraction_text(row_sum(chain, i))))
    }
  } else if (command == "CLASSES") {
    decomp <- decompose(chain)
    emit("CLASSES", name, paste0("count=", length(decomp$classes)))
    for (item in decomp$classes) {
      emit("CLASS", item$number, if (item$closed) "RECURRENT" else "TRANSIENT",
           paste0("period=", item$period), paste0("size=", length(item$members)),
           labels(chain, item$members))
      if (item$period >= 2) {
        for (remainder in 0:(item$period - 1)) {
          members <- item$members[item$levels[item$members] %% item$period == remainder]
          emit("CYCLIC", remainder, labels(chain, members))
        }
      }
    }
  } else if (command == "CLASSIFY") {
    decomp <- decompose(chain)
    absorbers <- vapply(seq_len(n), function(i) absorbing_state(chain, i), logical(1))
    count <- sum(absorbers)
    is_absorbing <- count > 0 && all(vapply(seq_len(n), function(i)
      reaches_targets(decomp, i, absorbers), logical(1)))
    exponent <- regular_exponent(chain)
    emit("CLASSIFY", name, paste0("absorbing_states=", count),
         paste0("absorbing=", yesno(is_absorbing)),
         paste0("ergodic=", yesno(length(decomp$classes) == 1)),
         paste0("regular=", yesno(!is.null(exponent))),
         paste0("exponent=", if (is.null(exponent)) "-" else exponent))
  } else if (command == "STEP") {
    initial <- a[2]
    steps <- as.numeric(a[3])
    if (grepl("^[0-9]", initial)) {
      texts <- strsplit(initial, ",", fixed = TRUE)[[1]]
      if (length(texts) != n) command_error("BAD LENGTH")
      distribution <- lapply(texts, probability)
      if (!equal(sum_fractions(distribution), one)) command_error("BAD DISTRIBUTION")
    } else {
      state <- state_index(chain, initial)
      distribution <- lapply(seq_len(n), function(i) delta(state, i))
    }
    if (steps > 0) for (t in seq_len(steps)) distribution <- advance(chain, distribution)
    emit("STEP", name, paste0("k=", steps))
    for (i in seq_len(n))
      emit("PROB", chain$names[i], value_text(distribution[[i]]))
  } else if (command == "POWER") {
    steps <- as.numeric(a[2])
    mat <- identity_matrix(n)
    if (steps > 0) for (t in seq_len(steps))
      mat <- lapply(mat, function(row) advance(chain, row))
    emit("POWER", name, paste0("k=", steps))
    display_matrix(chain$names, mat)
  } else if (command == "STATIONARY") {
    closed <- closed_classes(decompose(chain))
    emit("STATIONARY", name, paste0("count=", length(closed)))
    for (i in seq_along(closed)) {
      item <- closed[[i]]
      emit("DIST", i, paste0("class=", item$number),
           paste0("size=", length(item$members)))
      values <- stationary_distribution(chain, item$members)
      for (j in seq_along(item$members))
        emit("PI", chain$names[item$members[j]], value_text(values[[j]]))
    }
  } else if (command == "RECURRENCE") {
    i <- state_index(chain, a[2])
    decomp <- decompose(chain)
    item <- decomp$classes[[decomp$class_of[i]]]
    if (!item$closed) command_error(paste("TRANSIENT STATE", a[2]))
    pi <- stationary_distribution(chain, item$members)
    rho <- pi[[match(i, item$members)]]
    emit("RECURRENCE", name, a[2], paste0("pi=", value_text(rho)),
         paste0("mean=", value_text(divide(one, rho))),
         paste0("period=", item$period))
  } else if (command == "ABSORB") {
    absorbers <- vapply(seq_len(n), function(i) absorbing_state(chain, i), logical(1))
    if (!any(absorbers)) command_error("NO ABSORBING STATE")
    decomp <- decompose(chain)
    for (i in seq_len(n)) if (!absorbers[i] && !reaches_targets(decomp, i, absorbers))
      command_error(paste("NOT ABSORBING", chain$names[i]))
    result <- absorption(chain)
    emit("ABSORB", name, paste0("transient=", length(result$transient)),
         paste0("absorbing=", length(result$absorbing)))
    if (length(result$transient)) {
      emit("TRANSIENT", labels(chain, result$transient))
      emit("ABSORBING", labels(chain, result$absorbing))
      for (i in seq_along(result$transient))
        emit("N", chain$names[result$transient[i]],
             vapply(result$fundamental[[i]], fraction_text, character(1)))
      for (i in seq_along(result$transient))
        emit("STEPS", chain$names[result$transient[i]],
             paste0("mean=", value_text(result$steps[[i]])),
             paste0("var=", value_text(absorption_variance(result, i))))
      for (i in seq_along(result$transient))
        emit("B", chain$names[result$transient[i]],
             vapply(result$probabilities[[i]], fraction_text, character(1)))
    }
  } else if (command == "HITTING") {
    targets <- member_mask(n, distinct_states(chain, a[-1]))
    decomp <- decompose(chain)
    probabilities <- hitting_probabilities(chain, decomp, targets)
    times <- hitting_times(chain, targets, probabilities)
    emit("HITTING", name, paste0("targets=", paste(chain$names[targets], collapse = ",")))
    for (i in seq_len(n))
      emit("HIT", chain$names[i], paste0("prob=", value_text(probabilities[[i]])),
           paste0("time=", time_text(times[[i]])))
  } else if (command == "PASSAGE") {
    decomp <- decompose(chain)
    pi <- irreducible_distribution(chain, decomp)
    times <- lapply(seq_len(n), function(i) replicate(n, zero, simplify = FALSE))
    for (j in seq_len(n)) {
      targets <- member_mask(n, j)
      probabilities <- hitting_probabilities(chain, decomp, targets)
      column <- hitting_times(chain, targets, probabilities)
      for (i in seq_len(n))
        times[[i]][[j]] <- if (i == j) divide(one, pi[[j]]) else column[[i]]
    }
    kemeny <- zero
    if (n > 1) for (j in 2:n)
      kemeny <- add(kemeny, multiply(pi[[j]], times[[1]][[j]]))
    emit("PASSAGE", name, paste0("kemeny=", value_text(kemeny)))
    display_matrix(chain$names, times, "M")
  } else if (command == "FIRSTPASSAGE") {
    x <- state_index(chain, a[2])
    y <- state_index(chain, a[3])
    steps <- as.numeric(a[4])
    if (steps == 0) command_error("BAD STEPS")
    current <- lapply(seq_len(n), function(i) chain$matrix[[i]][[y]])
    first <- list(current[[x]])
    if (steps > 1) for (t in 2:steps) {
      current <- lapply(seq_len(n), function(i) sum_fractions(lapply(
        setdiff(seq_len(n), y), function(j)
          multiply(chain$matrix[[i]][[j]], current[[j]]))))
      first[[t]] <- current[[x]]
    }
    emit("FIRSTPASSAGE", name, a[2], a[3], paste0("k=", steps),
         paste0("total=", value_text(sum_fractions(first))))
    cumulative <- zero
    for (t in seq_along(first)) {
      cumulative <- add(cumulative, first[[t]])
      emit("FP", t, value_text(first[[t]]), paste0("cum=", value_text(cumulative)))
    }
  } else if (command == "PATHPROB") {
    indices <- vapply(a[-1], function(text) state_index(chain, text), integer(1))
    prob <- one
    zero_at <- NULL
    if (length(indices) > 1) for (t in seq_len(length(indices) - 1)) {
      prob <- multiply(prob, chain$matrix[[indices[t]]][[indices[t + 1]]])
      if (is.null(zero_at) && equal(prob, zero)) zero_at <- t
    }
    parts <- c("PATHPROB", name, paste0("steps=", length(indices) - 1),
               paste0("prob=", value_text(prob)))
    if (!is.null(zero_at)) parts <- c(parts, paste0("zero_at=", zero_at))
    emit(parts)
  } else if (command == "MOSTLIKELY") {
    x <- state_index(chain, a[2])
    steps <- as.numeric(a[3])
    if (steps == 0) command_error("BAD STEPS")
    best <- lapply(seq_len(steps + 1), function(i) rep(list(one), n))
    for (t in steps:1) {
      best[[t]] <- lapply(seq_len(n), function(i) {
        choices <- lapply(seq_len(n), function(j)
          multiply(chain$matrix[[i]][[j]], best[[t + 1]][[j]]))
        maximum <- choices[[1]]
        for (value in choices) if (greater(value, maximum)) maximum <- value
        maximum
      })
    }
    path <- c(x)
    for (t in seq_len(steps)) {
      current <- tail(path, 1)
      for (j in seq_len(n)) {
        candidate <- multiply(chain$matrix[[current]][[j]], best[[t + 1]][[j]])
        if (equal(candidate, best[[t]][[current]])) {
          path <- c(path, j)
          break
        }
      }
    }
    emit("MOSTLIKELY", name, a[2], paste0("k=", steps),
         paste0("prob=", value_text(best[[1]][[x]])))
    emit("PATH", labels(chain, path))
  } else if (command == "REVERSIBLE" || command == "REVERSE") {
    decomp <- decompose(chain)
    pi <- irreducible_distribution(chain, decomp)
    if (command == "REVERSIBLE") {
      violations <- list()
      if (n > 1) for (i in seq_len(n - 1)) for (j in (i + 1):n) {
        forward <- multiply(pi[[i]], chain$matrix[[i]][[j]])
        backward <- multiply(pi[[j]], chain$matrix[[j]][[i]])
        if (!equal(forward, backward))
          violations[[length(violations) + 1]] <- list(i, j, forward, backward)
      }
      if (!length(violations)) emit("REVERSIBLE", name, "yes") else {
        emit("REVERSIBLE", name, "no", paste0("violations=", length(violations)))
        for (v in violations)
          emit("VIOLATION", chain$names[v[[1]]], chain$names[v[[2]]],
               value_text(v[[3]]), value_text(v[[4]]))
      }
    } else {
      reversed_name <- a[2]
      reversed <- create_chain(chain$names)
      same <- TRUE
      for (i in seq_len(n)) for (j in seq_len(n)) {
        val <- divide(multiply(pi[[j]], chain$matrix[[j]][[i]]), pi[[i]])
        reversed$matrix[[i]][[j]] <- val
        if (!equal(val, chain$matrix[[i]][[j]])) same <- FALSE
      }
      put_chain(reversed_name, reversed)
      emit("REVERSE", name, reversed_name, paste0("reversible=", yesno(same)))
      display_matrix(reversed$names, reversed$matrix)
    }
  } else if (command == "MIXING") {
    steps <- as.numeric(a[2])
    if (steps == 0) command_error("BAD STEPS")
    epsilon <- probability(a[3])
    pi <- irreducible_distribution(chain, decompose(chain))
    mat <- identity_matrix(n)
    records <- list()
    mixing_time <- NULL
    for (t in seq_len(steps)) {
      mat <- lapply(mat, function(row) advance(chain, row))
      distances <- lapply(mat, function(row)
        divide(sum_fractions(Map(function(x, y) absolute(subtract(x, y)), row, pi)),
               fraction(2)))
      largest <- distances[[1]]
      worst <- 1
      for (i in seq_len(n)) if (greater(distances[[i]], largest)) {
        largest <- distances[[i]]
        worst <- i
      }
      if (is.null(mixing_time) && !greater(largest, epsilon)) mixing_time <- t
      records[[t]] <- list(largest, worst)
    }
    emit("MIXING", name, paste0("k=", steps),
         paste0("eps=", fraction_text(epsilon)),
         paste0("time=", if (is.null(mixing_time)) "none" else mixing_time))
    for (t in seq_len(steps))
      emit("TV", t, value_text(records[[t]][[1]]),
           paste0("from=", chain$names[records[[t]][[2]]]))
  } else if (command == "LUMP") {
    new_name <- a[2]
    groups <- strsplit(a[3], "|", fixed = TRUE)[[1]]
    seen <- rep(FALSE, n)
    blocks <- list()
    for (group in groups) {
      block <- integer()
      for (text in strsplit(group, ",", fixed = TRUE)[[1]]) {
        position <- state_index(chain, text)
        if (seen[position]) command_error("BAD PARTITION")
        seen[position] <- TRUE
        block <- c(block, position)
      }
      blocks[[length(blocks) + 1]] <- sort(block)
    }
    if (!all(seen)) command_error("BAD PARTITION")
    blocks <- blocks[order(vapply(blocks, function(block) block[1], numeric(1)))]
    for (block in blocks) {
      representative <- block[1]
      for (target in blocks) {
        expected <- block_sum(chain, representative, target)
        for (i in block) {
          actual <- block_sum(chain, i, target)
          if (!equal(actual, expected)) {
            emit("LUMP", name, "not", "lumpable",
                 paste0("block=", chain$names[representative]),
                 paste0("target=", chain$names[target[1]]),
                 paste0(chain$names[representative], "=", value_text(expected)),
                 paste0(chain$names[i], "=", value_text(actual)))
            return(invisible(NULL))
          }
        }
      }
    }
    lumped <- create_chain(vapply(blocks, function(block)
      chain$names[block[1]], character(1)))
    lumped$matrix <- lapply(blocks, function(block)
      lapply(blocks, function(target) block_sum(chain, block[1], target)))
    put_chain(new_name, lumped)
    emit("LUMP", name, new_name, paste0("blocks=", length(blocks)))
    display_matrix(lumped$names, lumped$matrix)
  } else if (command == "REWARD") {
    texts <- a[-c(1, 2)]
    if (length(texts) != n) command_error("BAD LENGTH")
    gamma <- probability(a[2])
    if (equal(gamma, one)) command_error("BAD DISCOUNT")
    rewards <- lapply(texts, function(text) fraction(as.numeric(text)))
    equations <- lapply(seq_len(n), function(i) {
      left <- lapply(seq_len(n), function(j)
        subtract(delta(i, j), multiply(gamma, chain$matrix[[i]][[j]])))
      c(left, list(rewards[[i]]))
    })
    discounted <- lapply(eliminate(equations, n), function(row) row[[1]])
    decomp <- decompose(chain)
    gains <- rep(list(zero), n)
    for (item in closed_classes(decomp)) {
      pi <- stationary_distribution(chain, item$members)
      gain <- sum_fractions(Map(function(rho, j)
        multiply(rho, rewards[[j]]), pi, item$members))
      targets <- member_mask(n, item$members)
      hit <- hitting_probabilities(chain, decomp, targets)
      for (i in seq_len(n)) gains[[i]] <- add(gains[[i]], multiply(hit[[i]], gain))
    }
    emit("REWARD", name, paste0("gamma=", fraction_text(gamma)))
    for (i in seq_len(n)) {
      emit("VALUE", chain$names[i],
           paste0("discounted=", value_text(discounted[[i]])),
           paste0("gain=", value_text(gains[[i]])))
    }
  } else if (command == "RESTRICT") {
    new_name <- a[2]
    inside <- member_mask(n, distinct_states(chain, a[-c(1, 2)]))
    for (i in seq_len(n)) {
      if (inside[i] && any(vapply(seq_len(n), function(j)
        edge(chain, i, j) && !inside[j], logical(1))))
        command_error(paste("NOT CLOSED", chain$names[i]))
    }
    members <- which(inside)
    restricted <- create_chain(chain$names[members])
    restricted$matrix <- lapply(members, function(i)
      lapply(members, function(j) chain$matrix[[i]][[j]]))
    put_chain(new_name, restricted)
    emit("RESTRICT", name, new_name, paste0("states=", length(members)))
    display_matrix(restricted$names, restricted$matrix)
  } else if (command == "SIMULATE") {
    start <- state_index(chain, a[2])
    steps <- as.numeric(a[3])
    seed <- as.numeric(a[4])
    if (steps == 0) command_error("BAD STEPS")
    if (seed == 0 || seed >= 2147483647) command_error("BAD SEED")
    random_value <- seed
    path <- c(start)
    for (t in seq_len(steps)) {
      row <- chain$matrix[[tail(path, 1)]]
      common <- 1
      for (p in row) common <- common / gcd_exact(common, p[2]) * p[2]
      random_value <- (48271 * random_value) %% 2147483647
      threshold <- random_value %% common
      cumulative <- zero
      for (j in seq_len(n)) {
        cumulative <- add(cumulative, row[[j]])
        if (greater(multiply(cumulative, fraction(common)), fraction(threshold))) {
          path <- c(path, j)
          break
        }
      }
    }
    emit("SIMULATE", name, a[2], paste0("steps=", steps),
         paste0("seed=", seed), paste0("end=", chain$names[tail(path, 1)]))
    emit("PATH", labels(chain, path))
    for (i in seq_len(n)) emit("VISIT", chain$names[i], sum(path == i))
  } else {
    command_error(paste("UNKNOWN COMMAND", command))
  }
  invisible(NULL)
}

inputs <- readLines(file("stdin"), warn = FALSE)
count <- as.integer(inputs[1])
for (line in inputs[seq.int(2, count + 1)]) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[1]
  arguments <- words[-1]
  tryCatch(execute_command(command, arguments),
    markov_command_error = function(error) emit("ERROR", conditionMessage(error)))
}
if (length(output)) cat(paste(output, collapse = "\n"), "\n", sep = "")
