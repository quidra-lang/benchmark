options(scipen = 999)
say <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("FlowError", "error", "condition")))
new_network <- function(n, edges = NULL) {
  network <- new.env(parent = emptyenv())
  network$n <- n
  network$edges <- if (is.null(edges)) matrix(integer(), 0L, 6L,
    dimnames = list(NULL, c("u", "v", "capacity", "cost", "lower", "flow"))) else edges
  network
}
new_edge <- function(u, v, capacity, cost = 0L, lower = 0L, flow = 0L) c(u, v, capacity, cost, lower, flow)
arcs <- function(network, vertex = NULL) {
  edges <- network$edges
  ids <- seq_len(nrow(edges))
  if (is.null(vertex)) return(c(ids, -ids))
  c(ids[edges[, "u"] == vertex], -ids[edges[, "v"] == vertex])
}
arc_from <- function(network, arc) network$edges[abs(arc), if (arc > 0L) "u" else "v"]
arc_to <- function(network, arc) network$edges[abs(arc), if (arc > 0L) "v" else "u"]
residual <- function(network, arc) {
  e <- network$edges[abs(arc), ]
  if (arc > 0L) e[["capacity"]] - e[["flow"]] else e[["flow"]]
}
arc_cost <- function(network, arc) network$edges[abs(arc), "cost"] * sign(arc)
push <- function(network, path, amount) {
  for (arc in path) network$edges[abs(arc), "flow"] <- network$edges[abs(arc), "flow"] + sign(arc) * amount
}
bottleneck <- function(network, path) min(vapply(path, function(arc) residual(network, arc), numeric(1)))
bfs <- function(network, source, threshold = 1L) {
  levels <- rep(NA_integer_, network$n)
  parents <- integer(network$n)
  levels[[source]] <- 0L
  queue <- source
  at <- 1L
  while (at <= length(queue)) {
    u <- queue[[at]]
    at <- at + 1L
    for (arc in arcs(network, u)) {
      v <- arc_to(network, arc)
      if (residual(network, arc) >= threshold && is.na(levels[[v]])) {
        levels[[v]] <- levels[[u]] + 1L
        parents[[v]] <- arc
        queue <- c(queue, v)
      }
    }
  }
  list(levels = levels, parents = parents)
}
path_to <- function(network, source, target, parents) {
  path <- integer()
  while (target != source) {
    arc <- parents[[target]]
    path <- c(path, arc)
    target <- arc_from(network, arc)
  }
  rev(path)
}
augment <- function(network, source, target, threshold = 1L) {
  search <- bfs(network, source, threshold)
  if (is.na(search$levels[[target]])) return(NULL)
  path <- path_to(network, source, target, search$parents)
  amount <- bottleneck(network, path)
  push(network, path, amount)
  list(path = path, amount = amount, delta = threshold)
}
maxflow <- function(network, source, target, method = "MAXFLOW") {
  records <- list()
  phases <- 0L
  if (method == "DINIC") {
    repeat {
      levels <- bfs(network, source)$levels
      if (is.na(levels[[target]])) break
      phases <- phases + 1L
      lists <- lapply(seq_len(network$n), function(v) arcs(network, v))
      pointers <- rep(1L, network$n)
      path <- integer()
      u <- source
      repeat {
        if (u == target) {
          amount <- bottleneck(network, path)
          push(network, path, amount)
          records[[length(records) + 1L]] <- list(path = path, amount = amount, phase = phases)
          path <- integer()
          u <- source
        } else if (pointers[[u]] > length(lists[[u]])) {
          if (u == source) break
          u <- arc_from(network, tail(path, 1L))
          path <- head(path, -1L)
          pointers[[u]] <- pointers[[u]] + 1L
        } else {
          arc <- lists[[u]][[pointers[[u]]]]
          v <- arc_to(network, arc)
          if (residual(network, arc) > 0L && !is.na(levels[[v]]) && levels[[v]] == levels[[u]] + 1L) {
            path <- c(path, arc)
            u <- v
          } else {
            pointers[[u]] <- pointers[[u]] + 1L
          }
        }
      }
    }
  } else {
    threshold <- 1L
    maximum <- max(c(0L, network$edges[, "capacity"]))
    while (method == "SCALING" && threshold * 2L <= maximum) threshold <- threshold * 2L
    while (threshold >= 1L) {
      repeat {
        record <- augment(network, source, target, threshold)
        if (is.null(record)) break
        records[[length(records) + 1L]] <- record
      }
      threshold <- if (method == "SCALING") threshold %/% 2L else 0L
    }
  }
  list(records = records, phases = phases)
}
negative_cycle <- function(network) {
  distance <- rep(0, network$n)
  for (pass in seq_len(network$n)) {
    changed <- FALSE
    for (i in seq_len(nrow(network$edges))) {
      e <- network$edges[i, ]
      if (e[["capacity"]] > 0L && distance[[e[["u"]]]] + e[["cost"]] < distance[[e[["v"]]]]) {
        distance[[e[["v"]]]] <- distance[[e[["u"]]]] + e[["cost"]]
        changed <- TRUE
      }
    }
    if (!changed) return(FALSE)
  }
  network$n > 0L
}
mincost <- function(network, source, target, limit = NULL) {
  amount <- 0
  cost <- 0
  records <- list()
  while (is.null(limit) || amount < limit) {
    usable <- Filter(function(arc) residual(network, arc) > 0L, arcs(network))
    distance <- rep(Inf, network$n)
    parents <- integer(network$n)
    distance[[source]] <- 0
    repeat {
      changed <- FALSE
      for (arc in usable) {
        u <- arc_from(network, arc)
        v <- arc_to(network, arc)
        if (!is.finite(distance[[u]])) next
        value <- distance[[u]] + arc_cost(network, arc)
        if (value < distance[[v]]) {
          distance[[v]] <- value
          parents[[v]] <- arc
          changed <- TRUE
        }
      }
      if (!changed) break
    }
    if (!is.finite(distance[[target]])) break
    path <- path_to(network, source, target, parents)
    delta <- bottleneck(network, path)
    if (!is.null(limit)) delta <- min(delta, limit - amount)
    push(network, path, delta)
    amount <- amount + delta
    cost <- cost + delta * distance[[target]]
    records[[length(records) + 1L]] <- list(path = path, amount = delta, cost = distance[[target]])
  }
  list(amount = amount, cost = cost, records = records)
}
balance <- function(network) {
  result <- rep(0, network$n)
  for (i in seq_len(nrow(network$edges))) {
    e <- network$edges[i, ]
    result[[e[["u"]]]] <- result[[e[["u"]]]] + e[["flow"]]
    result[[e[["v"]]]] <- result[[e[["v"]]]] - e[["flow"]]
  }
  result
}
total_cost <- function(network) sum(network$edges[, "flow"] * network$edges[, "cost"])
decompose <- function(network) {
  remaining <- network$edges[, "flow"]
  balances <- balance(network)
  result <- list()
  while (any(remaining > 0L)) {
    positive <- which(remaining > 0L)
    supplies <- which(balances > 0L)
    start <- if (length(supplies)) supplies[[1]] else network$edges[positive[[1]], "u"]
    vertices <- start
    path <- integer()
    repeat {
      u <- tail(vertices, 1L)
      i <- which(network$edges[, "u"] == u & remaining > 0L)[[1]]
      v <- network$edges[i, "v"]
      path <- c(path, i)
      q <- match(v, vertices)
      if (!is.na(q)) {
        cycle <- path[q:length(path)]
        delta <- min(remaining[cycle])
        remaining[cycle] <- remaining[cycle] - delta
        result[[length(result) + 1L]] <- list(kind = "CYCLE", start = v, path = cycle, amount = delta)
        break
      }
      vertices <- c(vertices, v)
      if (balances[[v]] < 0L) {
        delta <- min(remaining[path], balances[[start]], -balances[[v]])
        remaining[path] <- remaining[path] - delta
        balances[[start]] <- balances[[start]] - delta
        balances[[v]] <- balances[[v]] + delta
        result[[length(result) + 1L]] <- list(kind = "PATH", start = start, path = path, amount = delta)
        break
      }
    }
  }
  result
}

state <- new.env(parent = emptyenv())
clear <- function() {
  state$names <- character()
  state$demands <- integer()
  state$network <- new_network(0L)
  state$owner <- NULL
}
vertex <- function(name) {
  v <- match(name, state$names)
  if (is.na(v)) fail(paste("UNKNOWN NODE", name))
  v
}
endpoints <- function(s, t) {
  source <- vertex(s)
  target <- vertex(t)
  if (source == target) fail("SAME NODE")
  c(source, target)
}
checked_edge <- function(text) {
  i <- as.integer(text)
  if (i < 1L || i > nrow(state$network$edges)) fail(paste("UNKNOWN EDGE", text))
  i
}
fresh <- function() {
  work <- new_network(length(state$names), state$network$edges)
  work$edges[, "flow"] <- 0L
  work
}
start_flow <- function(source, target) {
  owner <- list(kind = "flow", source = source, target = target)
  if (!identical(state$owner, owner)) state$network$edges[, "flow"] <- 0L
  state$owner <- owner
  balance(state$network)[[source]]
}
notation <- function(network, start, path, original_only = NULL) {
  words <- state$names[[start]]
  for (arc in path) {
    if (!is.null(original_only) && abs(arc) > original_only) next
    v <- if (is.null(original_only)) arc_to(network, arc) else state$network$edges[abs(arc), "v"]
    words <- c(words, paste0(if (arc > 0L) "+" else "-", abs(arc)), state$names[[v]])
  }
  paste(words, collapse = " ")
}
flow_list <- function() {
  for (i in seq_len(nrow(state$network$edges))) {
    e <- state$network$edges[i, ]
    say("FLOW ", i, " ", state$names[[e[["u"]]]], " ", state$names[[e[["v"]]]], " ", e[["flow"]], "/", e[["capacity"]])
  }
}
circulation <- function(mode) {
  work <- fresh()
  work$edges[, "capacity"] <- work$edges[, "capacity"] - work$edges[, "lower"]
  if (mode == "MINCOST" && negative_cycle(work)) fail("NEGATIVE CYCLE")
  total <- sum(state$demands)
  if (total != 0L) {
    say("CIRCULATION infeasible unbalanced=", total)
    return(invisible(NULL))
  }
  residuals <- state$demands
  for (i in seq_len(nrow(state$network$edges))) {
    e <- state$network$edges[i, ]
    residuals[[e[["v"]]]] <- residuals[[e[["v"]]]] - e[["lower"]]
    residuals[[e[["u"]]]] <- residuals[[e[["u"]]]] + e[["lower"]]
  }
  source <- length(state$names) + 1L
  target <- source + 1L
  for (v in which(residuals < 0L)) work$edges <- rbind(work$edges, new_edge(source, v, -residuals[[v]]))
  sinks <- integer()
  for (v in which(residuals > 0L)) {
    sinks <- c(sinks, nrow(work$edges) + 1L)
    work$edges <- rbind(work$edges, new_edge(v, target, residuals[[v]]))
  }
  work$n <- target
  if (mode == "ANY") maxflow(work, source, target) else mincost(work, source, target)
  required <- sum(residuals[residuals > 0L])
  achieved <- sum(work$edges[sinks, "flow"])
  if (achieved < required) {
    say("CIRCULATION infeasible required=", required, " achieved=", achieved)
    reachable <- bfs(work, source)$levels[seq_along(state$names)]
    say("CUT ", paste(state$names[!is.na(reachable)], collapse = " "))
  } else {
    ids <- seq_len(nrow(state$network$edges))
    state$network$edges[, "flow"] <- state$network$edges[, "lower"] + work$edges[ids, "flow"]
    state$owner <- list(kind = "circulation")
    say("CIRCULATION feasible required=", required, " cost=", total_cost(state$network))
    flow_list()
  }
}
matching <- function(left_text, right_text, pair_text) {
  left <- strsplit(left_text, ",", fixed = TRUE)[[1]]
  right <- strsplit(right_text, ",", fixed = TRUE)[[1]]
  seen <- character()
  for (name in c(left, right)) {
    if (name %in% seen) fail(paste("DUPLICATE VERTEX", name))
    seen <- c(seen, name)
  }
  pairs <- if (pair_text == "-") list() else lapply(strsplit(pair_text, ",", fixed = TRUE)[[1]], function(p) strsplit(p, "-", fixed = TRUE)[[1]])
  seen_pairs <- character()
  for (pair in pairs) {
    a <- pair[[1]]
    b <- pair[[2]]
    if (!(a %in% left)) fail(paste("UNKNOWN VERTEX", a))
    if (!(b %in% right)) fail(paste("UNKNOWN VERTEX", b))
    key <- paste0(a, "-", b)
    if (key %in% seen_pairs) fail(paste("DUPLICATE PAIR", key))
    seen_pairs <- c(seen_pairs, key)
  }
  lp <- list()
  rp <- list()
  examined <- character()
  attempt <- function(a) {
    for (pair in pairs) {
      b <- pair[[2]]
      if (pair[[1]] != a || b %in% examined) next
      examined <<- c(examined, b)
      if (is.null(rp[[b]]) || attempt(rp[[b]])) {
        rp[[b]] <<- a
        lp[[a]] <<- b
        return(TRUE)
      }
    }
    FALSE
  }
  for (a in left) {
    examined <- character()
    attempt(a)
  }
  free_left <- setdiff(left, names(lp))
  free_right <- setdiff(right, names(rp))
  zl <- free_left
  zr <- character()
  at <- 1L
  while (at <= length(zl)) {
    a <- zl[[at]]
    at <- at + 1L
    for (pair in pairs) {
      b <- pair[[2]]
      if (pair[[1]] == a && !identical(lp[[a]], b) && !(b %in% zr)) {
        zr <- c(zr, b)
        if (!is.null(rp[[b]]) && !(rp[[b]] %in% zl)) zl <- c(zl, rp[[b]])
      }
    }
  }
  cover <- c(left[!(left %in% zl)], right[right %in% zr])
  say("MATCH size=", length(lp), " left=", length(left), " right=", length(right))
  for (a in left) if (!is.null(lp[[a]])) say("PAIR ", a, " ", lp[[a]])
  list_text <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
  say("FREE ", list_text(free_left), " ", list_text(free_right))
  say("COVER size=", length(cover), if (length(cover)) paste0(" ", paste(cover, collapse = " ")) else "")
  if (length(free_left)) say("HALL ", list_text(left[left %in% zl]), " ", list_text(right[right %in% zr]))
}
assignment <- function(mode, n, values) {
  if (n < 1L || n > 8L) fail("BAD SIZE")
  if (length(values) != n * n) fail("BAD LENGTH")
  best <- NULL
  count <- 0L
  chosen <- integer()
  search <- function(columns, total) {
    row <- length(columns)
    if (row == n) {
      if (is.null(best) || (if (mode == "MIN") total < best else total > best)) {
        best <<- total
        count <<- 1L
        chosen <<- columns
      } else if (total == best) {
        count <<- count + 1L
      }
      return(invisible(NULL))
    }
    for (column in seq_len(n)) {
      value <- values[[row * n + column]]
      if (!(column %in% columns) && value != "x") search(c(columns, column), total + as.integer(value))
    }
  }
  search(integer(), 0L)
  if (is.null(best)) {
    say("ASSIGN ", mode, " n=", n, " infeasible")
  } else {
    say("ASSIGN ", mode, " n=", n, " total=", best, " optimal=", count)
    for (row in seq_len(n)) say("MATE ", row, " ", chosen[[row]], " ", values[[(row - 1L) * n + chosen[[row]]]])
  }
}
flow_command <- function(command, args, source, target) {
  prefix <- paste(command, args[[1]], args[[2]])
  if (command == "SENSITIVITY") {
    maximum <- function(index = NULL, delta = 0L) {
      work <- fresh()
      if (!is.null(index)) work$edges[index, "capacity"] <- work$edges[index, "capacity"] + delta
      maxflow(work, source, target)
      balance(work)[[source]]
    }
    value <- maximum()
    critical <- lapply(seq_len(nrow(state$network$edges)), function(i) {
      list(i = i, up = maximum(i, 1L) > value, down = state$network$edges[i, "capacity"] > 0L && maximum(i, -1L) < value)
    })
    say(prefix, " value=", value, " up=", sum(vapply(critical, function(r) r$up, logical(1))),
        " down=", sum(vapply(critical, function(r) r$down, logical(1))))
    for (r in critical) {
      if (!(r$up || r$down)) next
      e <- state$network$edges[r$i, ]
      say("CRITICAL ", r$i, " ", state$names[[e[["u"]]]], " ", state$names[[e[["v"]]]],
          " up=", if (r$up) "yes" else "no", " down=", if (r$down) "yes" else "no")
    }
  } else if (command == "MINCOST") {
    work <- fresh()
    if (negative_cycle(work)) fail("NEGATIVE CYCLE")
    limit <- if (args[[3]] == "MAX") NULL else as.integer(args[[3]])
    result <- mincost(work, source, target, limit)
    if (!is.null(limit) && result$amount < limit) {
      say(prefix, " k=", args[[3]], " infeasible max=", result$amount)
      return(invisible(NULL))
    }
    state$network$edges[, "flow"] <- work$edges[, "flow"]
    state$owner <- list(kind = "flow", source = source, target = target)
    say(prefix, " k=", args[[3]], " flow=", result$amount, " cost=", result$cost)
    for (i in seq_along(result$records)) {
      r <- result$records[[i]]
      say("AUG ", i, " amount=", r$amount, " cost=", r$cost, " ", notation(work, source, r$path))
    }
    flow_list()
  } else if (command == "DISJOINT") {
    work <- fresh()
    work$edges[, "capacity"] <- as.integer(work$edges[, "capacity"] > 0L)
    work$edges[, "cost"] <- 0L
    if (args[[3]] == "VERTEX") {
      exits <- seq_along(state$names)
      for (v in seq_along(state$names)) {
        if (v == source || v == target) next
        work$n <- work$n + 1L
        exits[[v]] <- work$n
      }
      work$edges[, "u"] <- exits[work$edges[, "u"]]
      for (v in seq_along(state$names)) {
        if (v != source && v != target) work$edges <- rbind(work$edges, new_edge(v, exits[[v]], 1L))
      }
    }
    maxflow(work, source, target)
    records <- Filter(function(r) r$kind == "PATH", decompose(work))
    say(prefix, " ", args[[3]], " count=", length(records))
    for (i in seq_along(records)) say("PATH ", i, " ", notation(work, source, records[[i]]$path, nrow(state$network$edges)))
  } else {
    start <- start_flow(source, target)
    if (command == "AUGMENT") {
      r <- augment(state$network, source, target)
      ending <- if (is.null(r)) "none" else paste0("amount=", r$amount, " ", notation(state$network, source, r$path))
      say(prefix, " value=", balance(state$network)[[source]], " ", ending)
      return(invisible(NULL))
    }
    result <- maxflow(state$network, source, target, command)
    value <- balance(state$network)[[source]]
    if (command == "MINCUT") {
      reachable <- !is.na(bfs(state$network, source)$levels)
      cut <- which(reachable[state$network$edges[, "u"]] & !reachable[state$network$edges[, "v"]])
      say(prefix, " value=", value, " edges=", length(cut))
      say("SOURCE ", paste(state$names[reachable], collapse = " "))
      say("SINK ", paste(state$names[!reachable], collapse = " "))
      for (i in cut) {
        e <- state$network$edges[i, ]
        say("CUT ", i, " ", state$names[[e[["u"]]]], " ", state$names[[e[["v"]]]], " ", e[["capacity"]])
      }
    } else {
      say(prefix, " value=", value, " start=", start,
          if (command == "DINIC") paste0(" phases=", result$phases) else "", " paths=", length(result$records))
      for (i in seq_along(result$records)) {
        r <- result$records[[i]]
        extra <- if (command == "DINIC") paste0("phase=", r$phase, " ") else if (command == "SCALING") paste0("delta=", r$delta, " ") else ""
        say("AUG ", i, " ", extra, "amount=", r$amount, " ", notation(state$network, source, r$path))
      }
      flow_list()
    }
  }
}
execute <- function(line) {
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  command <- words[[1]]
  args <- words[-1]
  switch(command,
    NODE = {
      seen <- state$names
      for (name in args) {
        if (name %in% seen) fail(paste("DUPLICATE NODE", name))
        seen <- c(seen, name)
      }
      if (length(seen) > 20L) fail("TOO MANY NODES")
      state$names <- seen
      state$demands <- c(state$demands, rep(0L, length(args)))
      state$network$n <- length(seen)
      say("NODE added=", length(args), " total=", length(seen))
    },
    EDGE = {
      u <- vertex(args[[1]])
      v <- vertex(args[[2]])
      if (u == v) fail("SELF LOOP")
      if (nrow(state$network$edges) == 60L) fail("TOO MANY EDGES")
      cost <- if (length(args) == 4L) as.integer(args[[4]]) else 0L
      state$network$edges <- rbind(state$network$edges, new_edge(u, v, as.integer(args[[3]]), cost))
      say("EDGE ", nrow(state$network$edges), " ", args[[1]], " ", args[[2]], " cap=", args[[3]], " cost=", cost)
    },
    LOWER = edit_edge(command, args),
    CAP = edit_edge(command, args),
    COST = edit_edge(command, args),
    DEMAND = {
      v <- vertex(args[[1]])
      state$demands[[v]] <- as.integer(args[[2]])
      say("DEMAND ", args[[1]], " ", args[[2]], " total=", sum(state$demands))
    },
    RESET = {
      say("RESET edges=", sum(state$network$edges[, "flow"] != 0L))
      state$network$edges[, "flow"] <- 0L
      state$owner <- NULL
    },
    CLEAR = {
      say("CLEAR nodes=", length(state$names), " edges=", nrow(state$network$edges))
      clear()
    },
    SHOW = {
      balances <- balance(state$network)
      say("NETWORK nodes=", length(state$names), " edges=", nrow(state$network$edges))
      if (is.null(state$owner)) {
        say("STATE none")
      } else if (state$owner$kind == "circulation") {
        say("STATE circulation cost=", total_cost(state$network))
      } else {
        say("STATE flow ", state$names[[state$owner$source]], " ", state$names[[state$owner$target]],
            " value=", balances[[state$owner$source]], " cost=", total_cost(state$network))
      }
      for (v in seq_along(state$names)) {
        out <- sum(state$network$edges[state$network$edges[, "u"] == v, "flow"])
        say("NODE ", state$names[[v]], " demand=", state$demands[[v]], " out=", out, " in=", out - balances[[v]])
      }
      for (i in seq_len(nrow(state$network$edges))) {
        e <- state$network$edges[i, ]
        say("EDGE ", i, " ", state$names[[e[["u"]]]], " ", state$names[[e[["v"]]]], " cap=", e[["capacity"]],
            " cost=", e[["cost"]], " low=", e[["lower"]], " flow=", e[["flow"]])
      }
    },
    DECOMPOSE = {
      records <- decompose(state$network)
      count_paths <- sum(vapply(records, function(r) r$kind == "PATH", logical(1)))
      say("DECOMPOSE paths=", count_paths, " cycles=", length(records) - count_paths)
      counters <- c(PATH = 0L, CYCLE = 0L)
      for (r in records) {
        counters[[r$kind]] <- counters[[r$kind]] + 1L
        say(r$kind, " ", counters[[r$kind]], " amount=", r$amount, " ", notation(state$network, r$start, r$path))
      }
    },
    VERIFY = {
      violations <- character()
      for (i in seq_len(nrow(state$network$edges))) {
        e <- state$network$edges[i, ]
        if (e[["flow"]] < e[["lower"]]) violations <- c(violations, paste0("LOW ", i, " flow=", e[["flow"]], " low=", e[["lower"]]))
      }
      balances <- balance(state$network)
      is_flow <- !is.null(state$owner) && state$owner$kind == "flow"
      for (v in seq_along(state$names)) {
        if (is_flow && v %in% c(state$owner$source, state$owner$target)) next
        required <- if (is_flow) 0L else state$demands[[v]]
        if (-balances[[v]] != required) violations <- c(violations, paste0("BALANCE ", state$names[[v]], " net=", -balances[[v]], " need=", required))
      }
      if (!length(violations)) say("VERIFY ok") else {
        say("VERIFY violations=", length(violations))
        for (violation in violations) say(violation)
      }
    },
    CIRCULATION = circulation(args[[1]]),
    MATCH = matching(args[[1]], args[[2]], args[[3]]),
    ASSIGN = assignment(args[[1]], as.integer(args[[2]]), args[-c(1L, 2L)]),
    {
      ends <- endpoints(args[[1]], args[[2]])
      flow_command(command, args, ends[[1]], ends[[2]])
    }
  )
}
edit_edge <- function(command, args) {
  i <- checked_edge(args[[1]])
  value <- as.integer(args[[2]])
  e <- state$network$edges[i, ]
  if (command == "LOWER") {
    if (value > e[["capacity"]]) fail("BAD BOUND")
    state$network$edges[i, "lower"] <- value
    say("LOWER ", i, " low=", value, " cap=", e[["capacity"]])
  } else if (command == "CAP") {
    if (value < e[["lower"]]) fail("BAD BOUND")
    if (value < e[["flow"]]) fail("BELOW FLOW")
    state$network$edges[i, "capacity"] <- value
    say("CAP ", i, " low=", e[["lower"]], " cap=", value)
  } else {
    state$network$edges[i, "cost"] <- value
    say("COST ", i, " cost=", value)
  }
}

clear()
input <- file("stdin", "r")
count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (i in seq_len(count)) {
  line <- readLines(input, n = 1L, warn = FALSE)
  tryCatch(execute(line), FlowError = function(error) say("ERROR ", conditionMessage(error)))
}
