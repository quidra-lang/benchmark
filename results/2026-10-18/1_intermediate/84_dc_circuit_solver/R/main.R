options(scipen = 999)

circuit_error <- function(message) {
  stop(structure(list(message = message, call = NULL), class = c("circuit_error", "error", "condition")))
}
positive_divmod <- function(a, b) {
  q <- floor(a / b)
  r <- a - q * b
  if (r < 0) {
    q <- q - 1
    r <- r + b
  } else if (r >= b) {
    q <- q + 1
    r <- r - b
  }
  c(q, r)
}
rational <- function(p = 0, q = 1) {
  if (p == 0) return(c(0, 1))
  if (q < 0) {
    p <- -p
    q <- -q
  }
  a <- abs(p)
  b <- q
  while (b != 0) {
    remainder <- positive_divmod(a, b)[[2]]
    a <- b
    b <- remainder
  }
  c(p / a, q / a)
}
add <- function(x, y) rational(x[[1]] * y[[2]] + y[[1]] * x[[2]], x[[2]] * y[[2]])
subtract <- function(x, y) rational(x[[1]] * y[[2]] - y[[1]] * x[[2]], x[[2]] * y[[2]])
multiply <- function(x, y) rational(x[[1]] * y[[1]], x[[2]] * y[[2]])
divide <- function(x, y) rational(x[[1]] * y[[2]], x[[2]] * y[[1]])
negate <- function(x) c(-x[[1]], x[[2]])
compare <- function(x, y) sign(x[[1]] * y[[2]] - y[[1]] * x[[2]])
integer_text <- function(value) sprintf("%.0f", value)
fraction <- function(value) {
  if (value[[2]] == 1) integer_text(value[[1]]) else paste0(integer_text(value[[1]]), "/", integer_text(value[[2]]))
}
formatted <- function(value) {
  scaled <- positive_divmod(abs(value[[1]]) * 1000000, value[[2]])[[1]]
  parts <- positive_divmod(scaled, 1000000)
  decimal <- paste0(if (value[[1]] < 0) "-" else "", integer_text(parts[[1]]), ".", sprintf("%06.0f", parts[[2]]))
  paste0(fraction(value), " (", decimal, ")")
}
rational_number <- function(text) {
  multiplier <- rational(1)
  suffixes <- list(meg = rational(1000000), k = rational(1000), m = rational(1, 1000), u = rational(1, 1000000))
  for (suffix in names(suffixes)) {
    if (endsWith(text, suffix)) {
      text <- substr(text, 1L, nchar(text) - nchar(suffix))
      multiplier <- suffixes[[suffix]]
      break
    }
  }
  if (!grepl("^-?[0-9]+([.][0-9]+|/[0-9]+)?$", text)) return(NULL)
  if (grepl("/", text, fixed = TRUE)) {
    parts <- strsplit(text, "/", fixed = TRUE)[[1]]
    q <- as.numeric(parts[[2]])
    if (q == 0) return(NULL)
    value <- rational(as.numeric(parts[[1]]), q)
  } else if (grepl(".", text, fixed = TRUE)) {
    parts <- strsplit(text, ".", fixed = TRUE)[[1]]
    q <- 10 ^ nchar(parts[[2]])
    p <- abs(as.numeric(parts[[1]])) * q + as.numeric(parts[[2]])
    value <- rational(if (startsWith(text, "-")) -p else p, q)
  } else {
    value <- rational(as.numeric(text))
  }
  multiply(value, multiplier)
}
zeros <- function(n) replicate(n, rational(), simplify = FALSE)
solve_system <- function(matrix, rhs) {
  n <- length(rhs)
  rows <- lapply(seq_len(n), function(i) c(matrix[[i]], list(rhs[[i]])))
  for (k in seq_len(n)) {
    pivot <- NULL
    for (i in seq.int(k, n)) {
      if (rows[[i]][[k]][[1]] != 0) {
        pivot <- i
        break
      }
    }
    if (is.null(pivot)) return(NULL)
    if (pivot != k) {
      row <- rows[[k]]
      rows[[k]] <- rows[[pivot]]
      rows[[pivot]] <- row
    }
    divisor <- rows[[k]][[k]]
    rows[[k]] <- lapply(rows[[k]], function(entry) divide(entry, divisor))
    for (i in seq_len(n)) {
      if (i == k || rows[[i]][[k]][[1]] == 0) next
      factor <- rows[[i]][[k]]
      for (j in seq_len(n + 1L)) rows[[i]][[j]] <- subtract(rows[[i]][[j]], multiply(factor, rows[[k]][[j]]))
    }
  }
  lapply(rows, function(row) row[[n + 1L]])
}
reachable <- function(start, edges) {
  seen <- start
  queue <- start
  while (length(queue) != 0L) {
    node <- queue[[1]]
    queue <- queue[-1L]
    for (edge in edges) {
      a <- edge[[1]]
      b <- edge[[2]]
      if (a != node && b != node) next
      other <- if (a == node) b else a
      if (!(other %in% seen)) {
        seen <- c(seen, other)
        queue <- c(queue, other)
      }
    }
  }
  seen
}
new_groups <- function(nodes) {
  parent <- setNames(as.list(nodes), nodes)
  find <- function(node) {
    if (parent[[node]] != node) parent[[node]] <<- find(parent[[node]])
    parent[[node]]
  }
  join <- function(a, b) {
    roots <- sort(c(find(a), find(b)), method = "radix")
    parent[[roots[[2]]]] <<- roots[[1]]
  }
  list(find = find, join = join)
}
circuit <- function() {
  counts <- c(".OP" = 0L, ".CURRENT" = 1L, ".VOLTAGE" = 2L, ".POWER" = 0L, ".KCL" = 1L, ".THEVENIN" = 2L, ".NORTON" = 2L, ".MAXPOWER" = 2L, ".TF" = 2L, ".SENS" = 1L, ".ZPARAM" = 4L, ".SUPERPOSITION" = 1L, ".SWEEP" = 5L, ".MATRIX" = 0L, ".REQ" = 2L, ".REDUCE" = 2L, ".CHECK" = 0L, ".ALTER" = 2L, ".DELETE" = 1L, ".CLEAR" = 0L, ".NODES" = 0L, ".PRINT" = 0L)
  analyses <- c(".OP", ".CURRENT", ".VOLTAGE", ".POWER", ".KCL", ".THEVENIN", ".NORTON", ".MAXPOWER", ".TF", ".SENS", ".ZPARAM", ".SUPERPOSITION")
  state <- new.env(parent = emptyenv())
  state$elements <- list()
  nodes <- function() {
    all <- unlist(lapply(state$elements, function(item) item$nodes), use.names = FALSE)
    sort(setdiff(unique(all), "0"), method = "radix")
  }
  sources <- function() Filter(function(item) item$type %in% c("V", "E", "H"), state$elements)
  element_index <- function(name) {
    for (i in seq_along(state$elements)) if (state$elements[[i]]$name == name) return(i)
    circuit_error(paste0("unknown element ", name))
  }
  element <- function(name) state$elements[[element_index(name)]]
  node <- function(name) {
    if (name != "0" && !(name %in% nodes())) circuit_error(paste0("unknown node ", name))
  }
  number <- function(text) {
    value <- rational_number(text)
    if (is.null(value)) circuit_error(paste0("invalid value ", text))
    value
  }
  add_element <- function(words) {
    name <- words[[1]]
    type <- substr(name, 1L, 1L)
    if (!(type %in% c("R", "V", "I", "E", "G", "F", "H"))) circuit_error(paste0("unknown element type ", name))
    count <- if (type %in% c("E", "G")) 6L else if (type %in% c("F", "H")) 5L else 4L
    if (length(words) != count) circuit_error(paste0("wrong field count for ", name))
    if (any(vapply(state$elements, function(item) item$name == name, logical(1)))) circuit_error(paste0("duplicate element ", name))
    terminals <- words[seq.int(2L, if (type %in% c("E", "G")) 5L else 3L)]
    for (terminal in terminals) if (!grepl("^(0|[a-z][a-z0-9]{0,7})$", terminal)) circuit_error(paste0("invalid node ", terminal))
    reference <- if (type %in% c("F", "H")) words[[4]] else NULL
    if (!is.null(reference) && !any(vapply(state$elements, function(item) item$name == reference && item$type == "V", logical(1)))) circuit_error(paste0("unknown voltage source ", reference))
    value <- number(tail(words, 1L))
    if (type == "R" && value[[1]] <= 0) circuit_error(paste0("nonpositive resistance ", name))
    state$elements[[length(state$elements) + 1L]] <- list(name = name, type = type, nodes = terminals, value = value, reference = reference)
    character()
  }
  grounding <- function() {
    reachable("0", lapply(Filter(function(item) item$type %in% c("R", "V", "E", "H"), state$elements), function(item) item$nodes[1:2]))
  }
  voltage_loops <- function() {
    groups <- new_groups(c("0", nodes()))
    result <- character()
    for (item in sources()) {
      a <- item$nodes[[1]]
      b <- item$nodes[[2]]
      if (groups$find(a) == groups$find(b)) result <- c(result, item$name)
      groups$join(a, b)
    }
    result
  }
  structure_check <- function() {
    names <- nodes()
    if (length(names) == 0L) circuit_error("no nodes")
    grounded <- grounding()
    for (name in names) if (!(name %in% grounded)) circuit_error(paste0("floating node ", name))
    loops <- voltage_loops()
    if (length(loops) != 0L) circuit_error(paste0("voltage source loop at ", loops[[1]]))
  }
  equations <- function(overrides = list()) {
    labels <- c(nodes(), vapply(sources(), function(item) item$name, character(1)))
    index <- setNames(as.list(seq_along(labels)), labels)
    n <- length(labels)
    matrix <- replicate(n, zeros(n), simplify = FALSE)
    rhs <- zeros(n)
    put <- function(row, column, value) {
      if (row != "0" && column != "0") {
        i <- index[[row]]
        j <- index[[column]]
        matrix[[i]][[j]] <<- add(matrix[[i]][[j]], value)
      }
    }
    put_rhs <- function(row, value) {
      if (row != "0") rhs[[index[[row]]]] <<- add(rhs[[index[[row]]]], value)
    }
    for (item in state$elements) {
      a <- item$nodes[[1]]
      b <- item$nodes[[2]]
      c <- if (length(item$nodes) == 4L) item$nodes[[3]] else NULL
      d <- if (length(item$nodes) == 4L) item$nodes[[4]] else NULL
      value <- if (is.null(overrides[[item$name]])) item$value else overrides[[item$name]]
      s <- item$name
      if (item$type == "R") {
        g <- divide(rational(1), value)
        put(a, a, g)
        put(b, b, g)
        put(a, b, negate(g))
        put(b, a, negate(g))
      } else if (item$type == "I") {
        put_rhs(a, negate(value))
        put_rhs(b, value)
      } else if (item$type == "G") {
        put(a, c, value)
        put(b, d, value)
        put(a, d, negate(value))
        put(b, c, negate(value))
      } else if (item$type == "F") {
        put(a, item$reference, value)
        put(b, item$reference, negate(value))
      } else {
        put(a, s, rational(1))
        put(s, a, rational(1))
        put(b, s, rational(-1))
        put(s, b, rational(-1))
        if (item$type == "V") {
          put_rhs(s, value)
        } else if (item$type == "E") {
          put(s, c, negate(value))
          put(s, d, value)
        } else {
          put(s, item$reference, negate(value))
        }
      }
    }
    list(matrix = matrix, rhs = rhs, labels = labels, index = index)
  }
  potential <- function(solution, index, name) {
    if (name == "0") rational() else solution[[index[[name]]]]
  }
  current <- function(item, solution, index) {
    a <- item$nodes[[1]]
    b <- item$nodes[[2]]
    switch(item$type,
      R = divide(subtract(potential(solution, index, a), potential(solution, index, b)), item$value),
      V = solution[[index[[item$name]]]], E = solution[[index[[item$name]]]], H = solution[[index[[item$name]]]],
      I = item$value,
      G = multiply(item$value, subtract(potential(solution, index, item$nodes[[3]]), potential(solution, index, item$nodes[[4]]))),
      F = multiply(item$value, solution[[index[[item$reference]]]])
    )
  }
  injection <- function(matrix, index, a, b) {
    rhs <- zeros(length(matrix))
    if (a != "0") rhs[[index[[a]]]] <- add(rhs[[index[[a]]]], rational(1))
    if (b != "0") rhs[[index[[b]]]] <- subtract(rhs[[index[[b]]]], rational(1))
    solve_system(matrix, rhs)
  }
  source_solution <- function(matrix, index, item, unit = FALSE) {
    rhs <- zeros(length(matrix))
    value <- if (unit) rational(1) else item$value
    if (item$type == "V") {
      rhs[[index[[item$name]]]] <- value
    } else {
      a <- item$nodes[[1]]
      b <- item$nodes[[2]]
      if (a != "0") rhs[[index[[a]]]] <- subtract(rhs[[index[[a]]]], value)
      if (b != "0") rhs[[index[[b]]]] <- add(rhs[[index[[b]]]], value)
    }
    solve_system(matrix, rhs)
  }
  analysis <- function(command, args) {
    if (command == ".CURRENT") {
      element(args[[1]])
    } else if (command %in% c(".VOLTAGE", ".THEVENIN", ".NORTON", ".MAXPOWER", ".ZPARAM")) {
      for (name in args) node(name)
    } else if (command %in% c(".KCL", ".SENS", ".SUPERPOSITION")) {
      node(args[[1]])
    } else if (command == ".TF") {
      node(args[[1]])
      source <- element(args[[2]])
      if (!(source$type %in% c("V", "I"))) circuit_error(paste0("not an independent source ", source$name))
    }
    structure_check()
    system <- equations()
    matrix <- system$matrix
    index <- system$index
    solution <- solve_system(matrix, system$rhs)
    if (is.null(solution)) circuit_error("singular matrix")
    voltage <- function(name, values = solution) potential(values, index, name)
    lines <- character()
    if (command == ".OP") {
      for (name in nodes()) lines <- c(lines, paste0("V(", name, ") = ", formatted(voltage(name))))
      for (item in sources()) lines <- c(lines, paste0("I(", item$name, ") = ", formatted(solution[[index[[item$name]]]])))
    } else if (command == ".CURRENT") {
      lines <- paste0("I(", args[[1]], ") = ", formatted(current(element(args[[1]]), solution, index)))
    } else if (command == ".VOLTAGE") {
      lines <- paste0("V(", args[[1]], ",", args[[2]], ") = ", formatted(subtract(voltage(args[[1]]), voltage(args[[2]]))))
    } else if (command == ".POWER") {
      absorbed <- rational()
      delivered <- rational()
      total <- rational()
      for (item in state$elements) {
        power <- multiply(subtract(voltage(item$nodes[[1]]), voltage(item$nodes[[2]])), current(item, solution, index))
        if (power[[1]] > 0) absorbed <- add(absorbed, power)
        if (power[[1]] < 0) delivered <- subtract(delivered, power)
        total <- add(total, power)
        lines <- c(lines, paste0("P(", item$name, ") = ", formatted(power)))
      }
      lines <- c(lines, paste0("absorbed = ", formatted(absorbed)), paste0("delivered = ", formatted(delivered)), paste0("total = ", formatted(total)))
    } else if (command == ".KCL") {
      a <- args[[1]]
      total <- rational()
      for (item in state$elements) {
        x <- item$nodes[[1]]
        y <- item$nodes[[2]]
        if (x != a && y != a) next
        value <- if (x == y) rational() else multiply(rational(if (x == a) 1 else -1), current(item, solution, index))
        total <- add(total, value)
        lines <- c(lines, paste0("I(", item$name, ") leaving ", a, " = ", formatted(value)))
      }
      lines <- c(lines, paste0("sum = ", formatted(total)))
    } else if (command %in% c(".THEVENIN", ".NORTON", ".MAXPOWER")) {
      a <- args[[1]]
      b <- args[[2]]
      vth <- subtract(voltage(a), voltage(b))
      z <- injection(matrix, index, a, b)
      rth <- subtract(voltage(a, z), voltage(b, z))
      if (command == ".NORTON") {
        if (rth[[1]] == 0) circuit_error("zero thevenin resistance")
        lines <- c(paste0("In = ", formatted(divide(vth, rth))), paste0("Rn = ", formatted(rth)))
      } else if (command == ".MAXPOWER") {
        if (rth[[1]] <= 0) circuit_error("nonpositive thevenin resistance")
        lines <- c(paste0("RL = ", formatted(rth)), paste0("Pmax = ", formatted(divide(multiply(vth, vth), multiply(rational(4), rth)))))
      } else {
        lines <- c(paste0("Vth = ", formatted(vth)), paste0("Rth = ", formatted(rth)))
      }
    } else if (command == ".TF") {
      a <- args[[1]]
      name <- args[[2]]
      item <- element(name)
      z <- source_solution(matrix, index, item, TRUE)
      lines <- paste0("gain = ", formatted(voltage(a, z)))
      if (item$type == "V") {
        j <- z[[index[[name]]]]
        lines <- c(lines, if (j[[1]] == 0) "input resistance = INFINITE" else paste0("input resistance = ", formatted(divide(rational(-1), j))))
      } else {
        lines <- c(lines, paste0("input resistance = ", formatted(subtract(voltage(item$nodes[[2]], z), voltage(item$nodes[[1]], z)))))
      }
      lines <- c(lines, paste0("output resistance = ", formatted(voltage(a, injection(matrix, index, a, "0")))))
    } else if (command == ".SENS") {
      a <- args[[1]]
      for (item in state$elements) {
        d <- zeros(length(matrix))
        add_rhs <- function(row, value) {
          if (row != "0") d[[index[[row]]]] <<- add(d[[index[[row]]]], value)
        }
        x <- item$nodes[[1]]
        y <- item$nodes[[2]]
        if (item$type == "R") {
          t <- divide(current(item, solution, index), item$value)
          add_rhs(x, t)
          add_rhs(y, negate(t))
        } else if (item$type == "I") {
          add_rhs(x, rational(-1))
          add_rhs(y, rational(1))
        } else if (item$type %in% c("G", "F")) {
          t <- if (item$type == "G") subtract(voltage(item$nodes[[3]]), voltage(item$nodes[[4]])) else solution[[index[[item$reference]]]]
          add_rhs(x, negate(t))
          add_rhs(y, t)
        } else if (item$type == "V") {
          add_rhs(item$name, rational(1))
        } else if (item$type == "E") {
          add_rhs(item$name, subtract(voltage(item$nodes[[3]]), voltage(item$nodes[[4]])))
        } else {
          add_rhs(item$name, solution[[index[[item$reference]]]])
        }
        lines <- c(lines, paste0("dV(", a, ")/d", item$name, " = ", formatted(voltage(a, solve_system(matrix, d)))))
      }
    } else if (command == ".ZPARAM") {
      a <- args[[1]]
      b <- args[[2]]
      c <- args[[3]]
      d <- args[[4]]
      z1 <- injection(matrix, index, a, b)
      z2 <- injection(matrix, index, c, d)
      lines <- c(paste0("z11 = ", formatted(subtract(voltage(a, z1), voltage(b, z1)))),
                 paste0("z12 = ", formatted(subtract(voltage(a, z2), voltage(b, z2)))),
                 paste0("z21 = ", formatted(subtract(voltage(c, z1), voltage(d, z1)))),
                 paste0("z22 = ", formatted(subtract(voltage(c, z2), voltage(d, z2)))))
    } else if (command == ".SUPERPOSITION") {
      a <- args[[1]]
      total <- rational()
      for (item in Filter(function(item) item$type %in% c("V", "I"), state$elements)) {
        value <- voltage(a, source_solution(matrix, index, item))
        total <- add(total, value)
        lines <- c(lines, paste0(item$name, ": V(", a, ") = ", formatted(value)))
      }
      lines <- c(lines, paste0("total: V(", a, ") = ", formatted(total)))
    }
    lines
  }
  equivalent <- function(a, b) {
    groups <- new_groups(c("0", nodes()))
    for (item in state$elements) if (item$type == "V") groups$join(item$nodes[[1]], item$nodes[[2]])
    a <- groups$find(a)
    b <- groups$find(b)
    if (a == b) return("Req = 0 (0.000000)")
    edges <- list()
    for (item in state$elements) {
      if (item$type != "R") next
      x <- groups$find(item$nodes[[1]])
      y <- groups$find(item$nodes[[2]])
      if (x != y) edges[[length(edges) + 1L]] <- list(x, y, divide(rational(1), item$value))
    }
    connected <- reachable(a, edges)
    if (!(b %in% connected)) return("Req = INFINITE")
    labels <- sort(setdiff(connected, b), method = "radix")
    index <- setNames(as.list(seq_along(labels)), labels)
    matrix <- replicate(length(labels), zeros(length(labels)), simplify = FALSE)
    rhs <- zeros(length(labels))
    rhs[[index[[a]]]] <- rational(1)
    for (edge in edges) {
      x <- edge[[1]]
      y <- edge[[2]]
      g <- edge[[3]]
      if (!(x %in% connected)) next
      if (x != b) matrix[[index[[x]]]][[index[[x]]]] <- add(matrix[[index[[x]]]][[index[[x]]]], g)
      if (y != b) matrix[[index[[y]]]][[index[[y]]]] <- add(matrix[[index[[y]]]][[index[[y]]]], g)
      if (x != b && y != b) {
        matrix[[index[[x]]]][[index[[y]]]] <- subtract(matrix[[index[[x]]]][[index[[y]]]], g)
        matrix[[index[[y]]]][[index[[x]]]] <- subtract(matrix[[index[[y]]]][[index[[x]]]], g)
      }
    }
    paste0("Req = ", formatted(solve_system(matrix, rhs)[[index[[a]]]]))
  }
  reduce_resistors <- function(a, b) {
    if (a == b) return("Req = 0 (0.000000)")
    list <- Filter(function(item) item$type == "R", state$elements)
    connected <- reachable(a, lapply(list, function(item) item$nodes))
    if (!(b %in% connected)) return("Req = INFINITE")
    list <- Filter(function(item) item$nodes[[1]] %in% connected, list)
    lines <- character()
    serial <- 0L
    repeat {
      self <- which(vapply(list, function(item) item$nodes[[1]] == item$nodes[[2]], logical(1)))
      if (length(self) != 0L) {
        lines <- c(lines, paste0("remove ", list[[self[[1]]]]$name))
        list <- list[-self[[1]]]
        next
      }
      ends <- unlist(lapply(list, function(item) item$nodes), use.names = FALSE)
      names <- sort(unique(ends), method = "radix")
      degrees <- setNames(vapply(names, function(name) sum(ends == name), integer(1)), names)
      internal <- setdiff(names, c(a, b))
      leaves <- internal[degrees[internal] == 1L]
      if (length(leaves) != 0L) {
        i <- which(vapply(list, function(item) leaves[[1]] %in% item$nodes, logical(1)))[[1]]
        lines <- c(lines, paste0("remove ", list[[i]]$name))
        list <- list[-i]
        next
      }
      pair <- NULL
      for (i in seq_along(list)) {
        if (i == length(list)) next
        for (j in seq.int(i + 1L, length(list))) {
          if (identical(sort(list[[i]]$nodes, method = "radix"), sort(list[[j]]$nodes, method = "radix"))) {
            pair <- c(i, j)
            break
          }
        }
        if (!is.null(pair)) break
      }
      if (!is.null(pair)) {
        x <- list[[pair[[1]]]]
        y <- list[[pair[[2]]]]
        value <- divide(multiply(x$value, y$value), add(x$value, y$value))
        terminals <- x$nodes
        operator <- "||"
      } else {
        middle <- internal[degrees[internal] == 2L]
        if (length(middle) == 0L) break
        p <- middle[[1]]
        pair <- which(vapply(list, function(item) p %in% item$nodes, logical(1)))
        x <- list[[pair[[1]]]]
        y <- list[[pair[[2]]]]
        terminals <- c(x$nodes[x$nodes != p], y$nodes[y$nodes != p])
        value <- add(x$value, y$value)
        operator <- "+"
      }
      serial <- serial + 1L
      name <- paste0("#", serial)
      lines <- c(lines, paste0(name, " = ", x$name, " ", operator, " ", y$name, " = ", formatted(value)))
      list <- list[-pair]
      list[[length(list) + 1L]] <- list(name = name, type = "R", nodes = terminals, value = value)
    }
    c(lines, if (length(list) == 1L) paste0("Req = ", formatted(list[[1]]$value)) else paste0("not series-parallel: ", length(list), " resistors remain"))
  }
  command <- function(words) {
    cmd <- words[[1]]
    args <- words[-1L]
    if (!(cmd %in% names(counts))) circuit_error(paste0("unknown command ", cmd))
    if (length(args) != counts[[cmd]]) circuit_error(paste0("wrong argument count for ", cmd))
    if (cmd %in% analyses) return(analysis(cmd, args))
    if (cmd %in% c(".REQ", ".REDUCE")) {
      for (name in args) node(name)
      return(if (cmd == ".REQ") equivalent(args[[1]], args[[2]]) else reduce_resistors(args[[1]], args[[2]]))
    }
    if (cmd == ".SWEEP") {
      item <- element(args[[1]])
      from <- number(args[[2]])
      to <- number(args[[3]])
      step <- number(args[[4]])
      node(args[[5]])
      if (step[[1]] <= 0) circuit_error("invalid sweep step")
      if (compare(from, to) > 0) circuit_error("invalid sweep range")
      range <- divide(subtract(to, from), step)
      count <- positive_divmod(range[[1]], range[[2]])[[1]] + 1L
      if (count > 20L) circuit_error("too many sweep points")
      if (item$type == "R" && from[[1]] <= 0) circuit_error(paste0("nonpositive resistance ", item$name))
      structure_check()
      lines <- character()
      for (k in seq_len(count) - 1L) {
        x <- add(from, multiply(rational(k), step))
        system <- equations(setNames(list(x), item$name))
        solution <- solve_system(system$matrix, system$rhs)
        text <- if (is.null(solution)) "singular matrix" else paste0("V(", args[[5]], ") = ", formatted(potential(solution, system$index, args[[5]])))
        lines <- c(lines, paste0(item$name, " = ", fraction(x), ": ", text))
      }
      return(lines)
    }
    if (cmd == ".MATRIX") {
      structure_check()
      system <- equations()
      unknowns <- c(paste0("V(", nodes(), ")"), vapply(sources(), function(item) paste0("I(", item$name, ")"), character(1)))
      lines <- paste0("unknowns: ", paste(unknowns, collapse = " "))
      for (i in seq_along(system$matrix)) lines <- c(lines, paste0(system$labels[[i]], ": ", paste(vapply(system$matrix[[i]], fraction, character(1)), collapse = " "), " | ", fraction(system$rhs[[i]])))
      return(lines)
    }
    if (cmd == ".CHECK") {
      if (length(nodes()) == 0L) return("no nodes")
      lines <- character()
      for (name in nodes()) {
        degree <- sum(vapply(state$elements, function(item) sum(item$nodes[1:2] == name), integer(1)))
        if (degree < 2L) lines <- c(lines, paste0("dangling node ", name))
      }
      grounded <- grounding()
      for (name in nodes()) if (!(name %in% grounded)) lines <- c(lines, paste0("floating node ", name))
      for (name in voltage_loops()) lines <- c(lines, paste0("voltage source loop at ", name))
      if (length(lines) == 0L) {
        system <- equations()
        if (is.null(solve_system(system$matrix, system$rhs))) lines <- "singular matrix"
      }
      return(if (length(lines) == 0L) "ok" else lines)
    }
    if (cmd == ".ALTER") {
      i <- element_index(args[[1]])
      item <- state$elements[[i]]
      value <- number(args[[2]])
      if (item$type == "R" && value[[1]] <= 0) circuit_error(paste0("nonpositive resistance ", item$name))
      line <- paste0("altered ", item$name, ": ", fraction(item$value), " -> ", fraction(value))
      state$elements[[i]]$value <- value
      return(line)
    }
    if (cmd == ".DELETE") {
      i <- element_index(args[[1]])
      item <- state$elements[[i]]
      for (other in state$elements) if (other$type %in% c("F", "H") && other$reference == item$name) circuit_error(paste0(item$name, " is referenced by ", other$name))
      state$elements <- state$elements[-i]
      return(paste0("deleted ", item$name))
    }
    if (cmd == ".CLEAR") {
      line <- paste0("cleared ", length(state$elements), " elements")
      state$elements <- list()
      return(line)
    }
    if (cmd == ".NODES") {
      if (length(state$elements) == 0L) return("no nodes")
      names <- sort(unique(unlist(lapply(state$elements, function(item) item$nodes), use.names = FALSE)), method = "radix")
      return(vapply(names, function(name) {
        users <- vapply(Filter(function(item) name %in% item$nodes, state$elements), function(item) item$name, character(1))
        paste0(name, ": ", paste(users, collapse = " "))
      }, character(1)))
    }
    if (length(state$elements) == 0L) return("empty netlist")
    vapply(state$elements, function(item) paste(c(item$name, item$nodes, item$reference, fraction(item$value)), collapse = " "), character(1))
  }
  input <- file("stdin", open = "r")
  on.exit(close(input))
  number_line <- 0L
  repeat {
    lines <- readLines(input, n = 1L, warn = FALSE)
    if (length(lines) == 0L || lines[[1]] == ".END") break
    number_line <- number_line + 1L
    line <- lines[[1]]
    if (startsWith(line, "*")) next
    output <- tryCatch({
      words <- strsplit(line, " ", fixed = TRUE)[[1]]
      if (startsWith(line, ".")) command(words) else add_element(words)
    }, circuit_error = function(error) paste0("error: line ", number_line, ": ", error$message))
    for (text in output) cat(text, "\n", sep = "")
  }
}

circuit()
