automaton_error <- function(message) stop(structure(list(message = message), class = c("automaton_error", "error", "condition")))
chars <- function(text) strsplit(text, "", fixed = TRUE)[[1]]
integer_text <- function(value) sprintf("%.0f", value)
state_key <- function(values) paste0("s", paste(values, collapse = ","))

new_automaton <- function(kind, states, alphabet, start, accepting, triples) {
  edges <- lapply(states, function(unused) list())
  for (triple in triples) {
    p <- triple[[1]]
    c <- triple[[2]]
    edges[[p]][[c]] <- sort(unique(c(edges[[p]][[c]], triple[[3]])))
  }
  list(kind = kind, states = states, alphabet = sort(alphabet, method = "radix"),
       start = start, accepting = sort(unique(accepting)), edges = edges)
}

all_triples <- function(a) {
  result <- list()
  for (p in seq_along(a$states)) {
    for (symbol in c(a$alphabet, "e")) {
      for (q in a$edges[[p]][[symbol]]) result[[length(result) + 1L]] <- list(p, symbol, q)
    }
  }
  result
}

summary_line <- function(a, name) {
  paste0(a$kind, " ", name, ": alphabet=", paste(a$alphabet, collapse = ""),
         " states=", length(a$states), " accepting=", length(a$accepting),
         " transitions=", length(all_triples(a)))
}
set_text <- function(a, values) paste0("{", paste(a$states[sort(values)], collapse = ","), "}")
list_text <- function(a, values) if (length(values) == 0L) "none" else paste(a$states[sort(values)], collapse = ",")

closure <- function(a, values) {
  seen <- sort(unique(values))
  queue <- seen
  i <- 1L
  while (i <= length(queue)) {
    for (q in a$edges[[queue[[i]]]][["e"]]) {
      if (!(q %in% seen)) {
        seen <- c(seen, q)
        queue <- c(queue, q)
      }
    }
    i <- i + 1L
  }
  sort(seen)
}
move <- function(a, values, symbol) {
  targets <- integer()
  for (p in values) targets <- c(targets, a$edges[[p]][[symbol]])
  closure(a, unique(targets))
}
accepts_set <- function(a, values) any(values %in% a$accepting)

reachable <- function(a, seeds, reverse = FALSE) {
  graph <- lapply(a$states, function(unused) integer())
  for (triple in all_triples(a)) {
    p <- triple[[1]]
    q <- triple[[3]]
    if (reverse) graph[[q]] <- c(graph[[q]], p) else graph[[p]] <- c(graph[[p]], q)
  }
  seen <- unique(seeds)
  queue <- seen
  i <- 1L
  while (i <= length(queue)) {
    for (q in graph[[queue[[i]]]]) {
      if (!(q %in% seen)) {
        seen <- c(seen, q)
        queue <- c(queue, q)
      }
    }
    i <- i + 1L
  }
  sort(seen)
}

determinize <- function(a) {
  subsets <- list(closure(a, a$start))
  indices <- setNames(list(1L), state_key(subsets[[1]]))
  triples <- list()
  accepting <- integer()
  i <- 1L
  while (i <= length(subsets)) {
    if (accepts_set(a, subsets[[i]])) accepting <- c(accepting, i)
    for (symbol in a$alphabet) {
      target <- move(a, subsets[[i]], symbol)
      key <- state_key(target)
      if (is.null(indices[[key]])) {
        indices[[key]] <- length(subsets) + 1L
        subsets[[length(subsets) + 1L]] <- target
      }
      triples[[length(triples) + 1L]] <- list(i, symbol, indices[[key]])
    }
    i <- i + 1L
  }
  result <- new_automaton("DFA", paste0("D", seq_along(subsets) - 1L), a$alphabet, 1L, accepting, triples)
  list(automaton = result, subsets = subsets)
}

minimize <- function(a) {
  reached <- reachable(a, a$start)
  blocks <- list(reached[reached %in% a$accepting], reached[!(reached %in% a$accepting)])
  blocks <- Filter(function(block) length(block) > 0L, blocks)
  blocks <- blocks[order(vapply(blocks, function(block) block[[1]], integer(1)))]
  rounds <- list(blocks)
  repeat {
    membership <- integer(length(a$states))
    for (i in seq_along(blocks)) membership[blocks[[i]]] <- i
    groups <- list()
    for (p in reached) {
      signature <- c(membership[[p]], vapply(a$alphabet, function(symbol) membership[[a$edges[[p]][[symbol]][[1]]]], integer(1)))
      key <- state_key(signature)
      groups[[key]] <- c(groups[[key]], p)
    }
    refined <- unname(groups)
    refined <- refined[order(vapply(refined, function(block) block[[1]], integer(1)))]
    if (length(refined) == length(blocks)) break
    blocks <- refined
    rounds[[length(rounds) + 1L]] <- blocks
  }
  membership <- integer(length(a$states))
  for (i in seq_along(blocks)) membership[blocks[[i]]] <- i
  block_order <- membership[[a$start]]
  named <- setNames(list(1L), state_key(block_order))
  triples <- list()
  accepting <- integer()
  i <- 1L
  while (i <= length(block_order)) {
    p <- blocks[[block_order[[i]]]][[1]]
    if (p %in% a$accepting) accepting <- c(accepting, i)
    for (symbol in a$alphabet) {
      target <- membership[[a$edges[[p]][[symbol]][[1]]]]
      key <- state_key(target)
      if (is.null(named[[key]])) {
        named[[key]] <- length(block_order) + 1L
        block_order <- c(block_order, target)
      }
      triples[[length(triples) + 1L]] <- list(i, symbol, named[[key]])
    }
    i <- i + 1L
  }
  result <- new_automaton("DFA", paste0("M", seq_along(block_order) - 1L), a$alphabet, 1L, accepting, triples)
  list(automaton = result, unreachable = setdiff(seq_along(a$states), reached), rounds = rounds, blocks = blocks[block_order])
}

shortest_word <- function(a) {
  queue <- list(list(a$start, ""))
  seen <- a$start
  i <- 1L
  while (i <= length(queue)) {
    p <- queue[[i]][[1]]
    word <- queue[[i]][[2]]
    if (p %in% a$accepting) return(word)
    for (symbol in a$alphabet) {
      q <- a$edges[[p]][[symbol]][[1]]
      if (!(q %in% seen)) {
        seen <- c(seen, q)
        queue[[length(queue) + 1L]] <- list(q, paste0(word, symbol))
      }
    }
    i <- i + 1L
  }
  NULL
}

finite_size <- function(a, count = TRUE) {
  live <- reachable(a, a$accepting, TRUE)
  color <- integer(length(a$states))
  counts <- numeric(length(a$states))
  visit <- function(p) {
    if (!(p %in% live)) return(0)
    if (color[[p]] == 1L) return(NULL)
    if (color[[p]] == 2L) return(counts[[p]])
    color[[p]] <<- 1L
    total <- as.numeric(p %in% a$accepting)
    for (symbol in a$alphabet) {
      value <- visit(a$edges[[p]][[symbol]][[1]])
      if (is.null(value)) return(NULL)
      total <- if (count) total + value else as.numeric(total > 0 || value > 0)
    }
    color[[p]] <<- 2L
    counts[[p]] <<- total
    total
  }
  visit(a$start)
}

parse_regex <- function(text) {
  position <- 1L
  length <- nchar(text, type = "bytes")
  peek <- function() if (position > length) "" else substr(text, position, position)
  fail <- function() automaton_error(paste0("syntax error at ", position))
  atom <- function() {
    c <- peek()
    if (grepl("^[a-z0-9]$", c)) {
      position <<- position + 1L
      return(list(kind = "symbol", value = c))
    }
    if (c == "(") {
      position <<- position + 1L
      result <- alternation()
      if (peek() != ")") fail()
      position <<- position + 1L
      return(result)
    }
    fail()
  }
  factor <- function() {
    result <- atom()
    while (peek() %in% c("*", "+", "?")) {
      operator <- peek()
      position <<- position + 1L
      result <- list(kind = operator, child = result)
    }
    result
  }
  concatenation <- function() {
    parts <- list(factor())
    while (grepl("^[a-z0-9(]$", peek())) parts[[length(parts) + 1L]] <- factor()
    if (length(parts) == 1L) parts[[1]] else list(kind = "concatenation", parts = parts)
  }
  alternation <- function() {
    parts <- list(concatenation())
    while (peek() == "|") {
      position <<- position + 1L
      parts[[length(parts) + 1L]] <- concatenation()
    }
    if (length(parts) == 1L) parts[[1]] else list(kind = "alternation", parts = parts)
  }
  result <- alternation()
  if (peek() != "") fail()
  result
}

new_toolkit <- function() {
  table <- list()
  roles <- list(
    ACCEPT = c("ref", "other"), CLOSURE = c("ref", "other"), ENUM = c("ref", "other"), COUNT = c("ref", "other"),
    TODFA = c("ref", "new"), EPSFREE = c("ref", "new"), REVERSE = c("ref", "new"), STAR = c("ref", "new"),
    MINIMIZE = c("dfa", "new"), COMPLEMENT = c("dfa", "new"), EQUIV = c("ref", "ref"),
    UNION = c("dfa", "dfa", "new"), INTERSECT = c("dfa", "dfa", "new"), DIFF = c("dfa", "dfa", "new"),
    CONCAT = c("ref", "ref", "new"), EMPTY = "ref", FINITE = "ref", INFO = "ref", TABLE = "ref", SHOW = "ref",
    DELETE = "ref", SYNC = "dfa", LIST = character()
  )
  register <- function(name, a, details = character()) {
    table[[name]] <<- a
    c(summary_line(a, name), details)
  }
  define <- function(kind, args) {
    if (length(args) < 5L) automaton_error("wrong number of arguments")
    name <- args[[1]]
    if (!is.null(table[[name]])) automaton_error(paste0(name, " already exists"))
    states <- strsplit(args[[2]], ",", fixed = TRUE)[[1]]
    seen <- character()
    for (state in states) {
      if (state %in% seen) automaton_error(paste0("duplicate state ", state))
      seen <- c(seen, state)
    }
    start <- match(args[[4]], states)
    if (is.na(start)) automaton_error(paste0("unknown state ", args[[4]]))
    accepting <- integer()
    if (args[[5]] != "-") {
      for (state in strsplit(args[[5]], ",", fixed = TRUE)[[1]]) {
        index <- match(state, states)
        if (is.na(index)) automaton_error(paste0("unknown state ", state))
        if (index %in% accepting) automaton_error(paste0("duplicate state ", state))
        accepting <- c(accepting, index)
      }
    }
    alphabet <- sort(chars(args[[3]]), method = "radix")
    triples <- list()
    seen <- character()
    pairs <- character()
    for (word in args[-seq_len(5L)]) {
      parts <- strsplit(word, ":", fixed = TRUE)[[1]]
      p <- match(parts[[1]], states)
      symbol <- parts[[2]]
      q <- match(parts[[3]], states)
      if (is.na(p)) automaton_error(paste0("unknown state ", parts[[1]]))
      if (symbol == "e" && kind == "DFA") automaton_error("epsilon transition in DFA")
      if (symbol != "e" && !(symbol %in% alphabet)) automaton_error(paste0("unknown symbol ", symbol))
      if (is.na(q)) automaton_error(paste0("unknown state ", parts[[3]]))
      if (word %in% seen) automaton_error(paste0("duplicate transition ", word))
      pair <- paste0(parts[[1]], ":", symbol)
      if (kind == "DFA" && pair %in% pairs) automaton_error(paste0("conflicting transition ", word))
      seen <- c(seen, word)
      pairs <- c(pairs, pair)
      triples[[length(triples) + 1L]] <- list(p, symbol, q)
    }
    if (kind == "DFA") {
      for (p in states) {
        for (symbol in alphabet) {
          pair <- paste0(p, ":", symbol)
          if (!(pair %in% pairs)) automaton_error(paste0("missing transition ", pair))
        }
      }
    }
    register(name, new_automaton(kind, states, alphabet, start, accepting, triples))
  }
  regex <- function(args) {
    if (length(args) != 3L) automaton_error("wrong number of arguments")
    name <- args[[1]]
    if (!is.null(table[[name]])) automaton_error(paste0(name, " already exists"))
    alphabet <- chars(args[[2]])
    for (c in chars(args[[3]])) {
      if (grepl("^[a-z0-9]$", c) && c != "e" && !(c %in% alphabet)) automaton_error(paste0("unknown symbol ", c))
    }
    tree <- parse_regex(args[[3]])
    states <- character()
    triples <- list()
    create <- function() {
      index <- length(states) + 1L
      states <<- c(states, paste0("N", index - 1L))
      index
    }
    add <- function(p, c, q) triples[[length(triples) + 1L]] <<- list(p, c, q)
    build <- function(node) {
      if (node$kind == "symbol") {
        s <- create()
        f <- create()
        add(s, node$value, f)
        return(c(s, f))
      }
      if (node$kind == "concatenation") {
        parts <- lapply(node$parts, build)
        for (i in seq_len(length(parts) - 1L)) add(parts[[i]][[2]], "e", parts[[i + 1L]][[1]])
        return(c(parts[[1]][[1]], parts[[length(parts)]][[2]]))
      }
      s <- create()
      if (node$kind == "alternation") {
        parts <- lapply(node$parts, build)
        f <- create()
        for (part in parts) {
          add(s, "e", part[[1]])
          add(part[[2]], "e", f)
        }
      } else {
        part <- build(node$child)
        f <- create()
        add(s, "e", part[[1]])
        add(part[[2]], "e", f)
        if (node$kind != "?") add(part[[2]], "e", part[[1]])
        if (node$kind != "+") add(s, "e", f)
      }
      c(s, f)
    }
    endpoints <- build(tree)
    register(name, new_automaton("NFA", states, alphabet, endpoints[[1]], endpoints[[2]], triples))
  }
  product <- function(x, z, operation) {
    pairs <- list(c(x$start, z$start))
    indices <- setNames(list(1L), state_key(pairs[[1]]))
    triples <- list()
    accepting <- integer()
    i <- 1L
    while (i <= length(pairs)) {
      p <- pairs[[i]][[1]]
      q <- pairs[[i]][[2]]
      a <- p %in% x$accepting
      b <- q %in% z$accepting
      good <- if (operation == "UNION") a || b else if (operation == "INTERSECT") a && b else a && !b
      if (good) accepting <- c(accepting, i)
      for (symbol in x$alphabet) {
        target <- c(x$edges[[p]][[symbol]][[1]], z$edges[[q]][[symbol]][[1]])
        key <- state_key(target)
        if (is.null(indices[[key]])) {
          indices[[key]] <- length(pairs) + 1L
          pairs[[length(pairs) + 1L]] <- target
        }
        triples[[length(triples) + 1L]] <- list(i, symbol, indices[[key]])
      }
      i <- i + 1L
    }
    result <- new_automaton("DFA", paste0("P", seq_along(pairs) - 1L), x$alphabet, 1L, accepting, triples)
    list(automaton = result, pairs = pairs)
  }
  equivalent <- function(x, z, names) {
    a <- determinize(x)$automaton
    b <- determinize(z)$automaton
    queue <- list(list(a$start, b$start, ""))
    seen <- state_key(c(a$start, b$start))
    i <- 1L
    while (i <= length(queue)) {
      p <- queue[[i]][[1]]
      q <- queue[[i]][[2]]
      word <- queue[[i]][[3]]
      if ((p %in% a$accepting) != (q %in% b$accepting)) {
        owner <- if (p %in% a$accepting) names[[1]] else names[[2]]
        return(paste0("NOT EQUIVALENT: ", if (word == "") "e" else word, " is accepted only by ", owner))
      }
      for (symbol in a$alphabet) {
        target <- c(a$edges[[p]][[symbol]][[1]], b$edges[[q]][[symbol]][[1]])
        key <- state_key(target)
        if (!(key %in% seen)) {
          seen <- c(seen, key)
          queue[[length(queue) + 1L]] <- list(target[[1]], target[[2]], paste0(word, symbol))
        }
      }
      i <- i + 1L
    }
    "EQUIVALENT"
  }
  synchronization <- function(x) {
    initial <- seq_along(x$states)
    queue <- list(list(initial, ""))
    seen <- state_key(initial)
    i <- 1L
    while (i <= length(queue)) {
      subset <- queue[[i]][[1]]
      word <- queue[[i]][[2]]
      if (length(subset) == 1L) return(paste0("SYNCHRONIZING ", if (word == "") "e" else word, " -> ", x$states[[subset[[1]]]]))
      for (symbol in x$alphabet) {
        target <- sort(unique(vapply(subset, function(p) x$edges[[p]][[symbol]][[1]], integer(1))))
        key <- state_key(target)
        if (!(key %in% seen)) {
          seen <- c(seen, key)
          queue[[length(queue) + 1L]] <- list(target, paste0(word, symbol))
        }
      }
      i <- i + 1L
    }
    "NOT SYNCHRONIZING"
  }
  execute <- function(command, args) {
    if (command %in% c("DFA", "NFA")) return(define(command, args))
    if (command == "REGEX") return(regex(args))
    if (!(command %in% names(roles))) automaton_error(paste0("unknown command ", command))
    command_roles <- roles[[command]]
    if (length(command_roles) != length(args)) automaton_error("wrong number of arguments")
    references <- which(command_roles %in% c("ref", "dfa"))
    for (i in references) if (is.null(table[[args[[i]]]])) automaton_error(paste0("unknown automaton ", args[[i]]))
    for (i in which(command_roles == "new")) if (!is.null(table[[args[[i]]]])) automaton_error(paste0(args[[i]], " already exists"))
    for (i in which(command_roles == "dfa")) if (table[[args[[i]]]]$kind != "DFA") automaton_error(paste0(args[[i]], " is not a DFA"))
    x <- if (length(references) == 0L) NULL else table[[args[[1]]]]
    z <- if (length(references) == 2L) table[[args[[2]]]] else NULL
    if (!is.null(z) && !identical(x$alphabet, z$alphabet)) automaton_error("alphabets differ")
    if (command == "LIST") {
      if (length(table) == 0L) return("(none)")
      return(vapply(names(table), function(name) summary_line(table[[name]], name), character(1)))
    }
    if (command == "DELETE") {
      table[[args[[1]]]] <<- NULL
      return(paste0("deleted ", args[[1]]))
    }
    if (command == "ACCEPT") {
      word <- if (args[[2]] == "e") "" else args[[2]]
      for (symbol in chars(word)) if (!(symbol %in% x$alphabet)) automaton_error(paste0("unknown symbol ", symbol))
      current <- closure(x, x$start)
      format_set <- function(s) if (x$kind == "DFA") x$states[[s[[1]]]] else set_text(x, s)
      trace <- format_set(current)
      for (symbol in chars(word)) {
        current <- move(x, current, symbol)
        trace <- paste0(trace, " -", symbol, "-> ", format_set(current))
      }
      return(paste0(if (accepts_set(x, current)) "ACCEPT " else "REJECT ", trace))
    }
    if (command == "CLOSURE") {
      values <- integer()
      for (name in strsplit(args[[2]], ",", fixed = TRUE)[[1]]) {
        index <- match(name, x$states)
        if (is.na(index)) automaton_error(paste0("unknown state ", name))
        values <- c(values, index)
      }
      return(set_text(x, closure(x, values)))
    }
    if (command == "TODFA") {
      result <- determinize(x)
      details <- vapply(seq_along(result$subsets), function(i) paste0("  D", i - 1L, " = ", set_text(x, result$subsets[[i]])), character(1))
      return(register(args[[2]], result$automaton, details))
    }
    if (command == "EPSFREE") {
      triples <- list()
      accepting <- integer()
      for (p in seq_along(x$states)) {
        initial <- closure(x, p)
        if (accepts_set(x, initial)) accepting <- c(accepting, p)
        for (symbol in x$alphabet) {
          for (q in move(x, initial, symbol)) triples[[length(triples) + 1L]] <- list(p, symbol, q)
        }
      }
      return(register(args[[2]], new_automaton("NFA", x$states, x$alphabet, x$start, accepting, triples)))
    }
    if (command == "MINIMIZE") {
      result <- minimize(x)
      details <- paste0("  unreachable: ", list_text(x, result$unreachable))
      for (i in seq_along(result$rounds)) details <- c(details, paste0("  round ", i - 1L, ": ", paste(vapply(result$rounds[[i]], function(block) set_text(x, block), character(1)), collapse = " ")))
      for (i in seq_along(result$blocks)) details <- c(details, paste0("  M", i - 1L, " = ", set_text(x, result$blocks[[i]])))
      return(register(args[[2]], result$automaton, details))
    }
    if (command == "EQUIV") return(equivalent(x, z, args))
    if (command %in% c("UNION", "INTERSECT", "DIFF")) {
      result <- product(x, z, command)
      details <- vapply(seq_along(result$pairs), function(i) {
        pair <- result$pairs[[i]]
        paste0("  P", i - 1L, " = (", x$states[[pair[[1]]]], ",", z$states[[pair[[2]]]], ")")
      }, character(1))
      return(register(args[[3]], result$automaton, details))
    }
    if (command == "COMPLEMENT") return(register(args[[2]], new_automaton("DFA", x$states, x$alphabet, x$start, setdiff(seq_along(x$states), x$accepting), all_triples(x))))
    if (command == "REVERSE") {
      triples <- lapply(all_triples(x), function(t) list(t[[3]] + 1L, t[[2]], t[[1]] + 1L))
      for (p in x$accepting) triples[[length(triples) + 1L]] <- list(1L, "e", p + 1L)
      return(register(args[[2]], new_automaton("NFA", paste0("N", 0:length(x$states)), x$alphabet, 1L, x$start + 1L, triples)))
    }
    if (command == "CONCAT") {
      offset <- length(x$states)
      triples <- c(all_triples(x), lapply(all_triples(z), function(t) list(t[[1]] + offset, t[[2]], t[[3]] + offset)))
      for (p in x$accepting) triples[[length(triples) + 1L]] <- list(p, "e", z$start + offset)
      return(register(args[[3]], new_automaton("NFA", paste0("N", seq_len(offset + length(z$states)) - 1L), x$alphabet, x$start, z$accepting + offset, triples)))
    }
    if (command == "STAR") {
      triples <- lapply(all_triples(x), function(t) list(t[[1]] + 1L, t[[2]], t[[3]] + 1L))
      triples[[length(triples) + 1L]] <- list(1L, "e", x$start + 1L)
      for (p in x$accepting) triples[[length(triples) + 1L]] <- list(p + 1L, "e", x$start + 1L)
      return(register(args[[2]], new_automaton("NFA", paste0("N", 0:length(x$states)), x$alphabet, 1L, c(1L, x$accepting + 1L), triples)))
    }
    if (command == "ENUM") {
      dfa <- determinize(x)$automaton
      level <- list(list(dfa$start, ""))
      total <- 0
      examples <- character()
      limit <- as.integer(args[[2]])
      for (length in 0:limit) {
        for (entry in level) {
          if (entry[[1]] %in% dfa$accepting) {
            total <- total + 1
            if (length(examples) < 50L) examples <- c(examples, if (entry[[2]] == "") "e" else entry[[2]])
          }
        }
        if (length < limit) {
          next_level <- list()
          for (entry in level) {
            for (symbol in dfa$alphabet) next_level[[length(next_level) + 1L]] <- list(dfa$edges[[entry[[1]]]][[symbol]][[1]], paste0(entry[[2]], symbol))
          }
          level <- next_level
        }
      }
      return(paste(c(integer_text(total), examples, if (total > 50) "..." else character()), collapse = " "))
    }
    if (command == "COUNT") {
      dfa <- determinize(x)$automaton
      counts <- numeric(length(dfa$states))
      counts[[dfa$start]] <- 1
      for (i in seq_len(as.integer(args[[2]]))) {
        next_counts <- numeric(length(counts))
        for (p in seq_along(counts)) {
          for (symbol in dfa$alphabet) {
            q <- dfa$edges[[p]][[symbol]][[1]]
            next_counts[[q]] <- next_counts[[q]] + counts[[p]]
          }
        }
        counts <- next_counts
      }
      return(integer_text(sum(counts[dfa$accepting])))
    }
    if (command == "EMPTY") {
      word <- shortest_word(determinize(x)$automaton)
      return(if (is.null(word)) "EMPTY" else paste0("NOT EMPTY ", if (word == "") "e" else word))
    }
    if (command == "FINITE") {
      size <- finite_size(determinize(x)$automaton)
      return(if (is.null(size)) "INFINITE" else paste0("FINITE ", integer_text(size)))
    }
    if (command == "SYNC") return(synchronization(x))
    if (command == "INFO") {
      dfa <- determinize(x)$automaton
      size <- finite_size(dfa, FALSE)
      epsilon <- sum(vapply(all_triples(x), function(t) t[[2]] == "e", logical(1)))
      deterministic <- epsilon == 0L
      complete <- TRUE
      for (row in x$edges) {
        for (symbol in x$alphabet) {
          number <- length(row[[symbol]])
          deterministic <- deterministic && number <= 1L
          complete <- complete && number >= 1L
        }
      }
      language <- if (is.null(size)) "infinite" else if (size == 0) "empty" else "finite"
      return(c(summary_line(x, args[[1]]), paste0("  epsilon transitions: ", epsilon),
               paste0("  reachable: ", list_text(x, reachable(x, x$start))),
               paste0("  live: ", list_text(x, reachable(x, x$accepting, TRUE))),
               paste0("  deterministic: ", if (deterministic) "yes" else "no"),
               paste0("  complete: ", if (complete) "yes" else "no"), paste0("  language: ", language),
               paste0("  minimal DFA states: ", length(minimize(dfa)$automaton$states))))
    }
    if (command == "TABLE") {
      has_epsilon <- any(vapply(x$edges, function(row) length(row[["e"]]) > 0L, logical(1)))
      symbols <- c(x$alphabet, if (x$kind == "NFA" && has_epsilon) "e" else character())
      rows <- list(c("", symbols))
      for (p in seq_along(x$states)) {
        marker <- paste0(if (p == x$start) "->" else "  ", if (p %in% x$accepting) "*" else " ", x$states[[p]])
        row <- marker
        for (symbol in symbols) {
          values <- x$edges[[p]][[symbol]]
          cell <- if (x$kind == "DFA") x$states[[values[[1]]]] else if (length(values) == 0L) "-" else set_text(x, values)
          row <- c(row, cell)
        }
        rows[[length(rows) + 1L]] <- row
      }
      widths <- vapply(seq_along(rows[[1]]), function(i) max(vapply(rows, function(row) nchar(row[[i]], type = "bytes"), integer(1))), integer(1))
      return(vapply(rows, function(row) {
        cells <- vapply(seq_along(row), function(i) paste0(row[[i]], strrep(" ", widths[[i]] - nchar(row[[i]], type = "bytes"))), character(1))
        sub(" +$", "", paste(cells, collapse = "  "))
      }, character(1)))
    }
    if (command == "SHOW") {
      accepting <- if (length(x$accepting) == 0L) "-" else paste(x$states[x$accepting], collapse = ",")
      words <- c(x$kind, args[[1]], paste(x$states, collapse = ","), paste(x$alphabet, collapse = ""), x$states[[x$start]], accepting)
      for (triple in all_triples(x)) words <- c(words, paste0(x$states[[triple[[1]]]], ":", triple[[2]], ":", x$states[[triple[[3]]]]))
      return(paste(words, collapse = " "))
    }
  }
  execute
}

input <- file("stdin", open = "r")
first <- readLines(input, n = 1L, warn = FALSE)
toolkit <- new_toolkit()
for (i in seq_len(as.integer(first))) {
  line <- readLines(input, n = 1L, warn = FALSE)
  if (substr(line, 1L, 1L) == "#") next
  words <- strsplit(line, " ", fixed = TRUE)[[1]]
  tryCatch({
    output <- toolkit(words[[1]], words[-1L])
    cat(paste(output, collapse = "\n"), "\n", sep = "")
  }, automaton_error = function(error) cat("error: ", conditionMessage(error), "\n", sep = ""))
}
