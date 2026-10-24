options(expressions = 50000, scipen = 999)

reserved <- c("not", "mod", "count", "sum", "min", "max", "retract", "dump", "why", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt")
datalog_error <- function(reason) {
  stop(structure(list(message = reason, call = NULL), class = c("datalog_error", "error", "condition")))
}
value_text <- function(value) {
  if (is.numeric(value)) return(if (value == 0) "0" else sprintf("%.0f", value))
  if (grepl("^[a-z][A-Za-z0-9_]*$", value) && !(value %in% reserved)) value else paste0('"', value, '"')
}
value_equal <- function(a, b) is.character(a) == is.character(b) && a == b
value_compare <- function(a, b) {
  if (is.numeric(a) != is.numeric(b)) return(if (is.numeric(a)) -1L else 1L)
  if (a == b) return(0L)
  if (is.numeric(a)) return(if (a < b) -1L else 1L)
  if (sort(c(a, b), method = "radix")[[1]] == a) -1L else 1L
}
tuple_compare <- function(a, b) {
  for (i in seq_along(a)) {
    comparison <- value_compare(a[[i]], b[[i]])
    if (comparison != 0L) return(comparison)
  }
  0L
}
tuple_key <- function(tuple) {
  paste0("t", paste(vapply(tuple, function(value) {
    if (is.numeric(value)) paste0("i", value_text(value), ";") else paste0("s", nchar(value), ":", value)
  }, character(1)), collapse = ""))
}
sort_items <- function(items, comparison = tuple_compare) {
  n <- length(items)
  if (n <= 1L) return(items)
  middle <- n %/% 2L
  left <- sort_items(items[seq_len(middle)], comparison)
  right <- sort_items(items[seq.int(middle + 1L, n)], comparison)
  result <- vector("list", n)
  i <- j <- 1L
  for (k in seq_len(n)) {
    if (j > length(right) || (i <= length(left) && comparison(left[[i]], right[[j]]) <= 0L)) {
      result[[k]] <- left[[i]]
      i <- i + 1L
    } else {
      result[[k]] <- right[[j]]
      j <- j + 1L
    }
  }
  result
}
term_text <- function(term, environment = NULL) {
  switch(term$kind, constant = value_text(term$value), variable = if (is.null(environment)) term$value else value_text(environment[[term$value]]), anonymous = "_")
}
atom_text <- function(atom, environment = NULL) {
  paste0(atom$name, if (length(atom$terms) == 0L) "" else paste0("(", paste(vapply(atom$terms, term_text, character(1), environment = environment), collapse = ", "), ")"))
}
tuple_text <- function(name, tuple) atom_text(list(name = name, terms = lapply(tuple, function(value) list(kind = "constant", value = value))))
expression_text <- function(expression, environment = NULL) {
  switch(expression$kind,
    term = term_text(expression$term, environment),
    group = paste0("(", expression_text(expression$child, environment), ")"),
    binary = paste(expression_text(expression$left, environment), expression$op, expression_text(expression$right, environment))
  )
}
literal_text <- function(literal, environment = NULL) {
  switch(literal$kind,
    positive = atom_text(literal$atom, environment),
    negative = paste0("not ", atom_text(literal$atom, environment)),
    comparison = paste(expression_text(literal$left, environment), literal$op, expression_text(literal$right, environment))
  )
}
expression_terms <- function(expression) {
  switch(expression$kind, term = list(expression$term), group = expression_terms(expression$child), binary = c(expression_terms(expression$left), expression_terms(expression$right)))
}
literal_terms <- function(literal) {
  if (literal$kind == "comparison") c(expression_terms(literal$left), expression_terms(literal$right)) else literal$atom$terms
}
variable_occurrences <- function(head, body) {
  terms <- if (is.null(head)) list() else head$terms
  for (literal in body) terms <- c(terms, literal_terms(literal))
  vapply(Filter(function(term) term$kind == "variable", terms), function(term) term$value, character(1))
}
new_parser <- function(line) {
  tokens <- list()
  i <- 1L
  length <- nchar(line)
  add_token <- function(kind, text, value = NULL) tokens[[length(tokens) + 1L]] <<- list(kind = kind, text = text, value = value)
  character_at <- function(i) substr(line, i, i)
  while (i <= length) {
    c <- character_at(i)
    if (c == " ") {
      i <- i + 1L
    } else if (c == "%") {
      break
    } else if (c == '"') {
      finish <- regexpr('"', substring(line, i + 1L), fixed = TRUE)[[1]]
      if (finish < 0L) datalog_error("unterminated string")
      finish <- i + finish
      add_token("string", substr(line, i, finish), substr(line, i + 1L, finish - 1L))
      i <- finish + 1L
    } else if (substr(line, i, i + 1L) %in% c(":-", "?-", "!=", "<=", ">=")) {
      text <- substr(line, i, i + 1L)
      add_token(text, text)
      i <- i + 2L
    } else if (c %in% c("(", ")", ",", ".", ":", "=", "<", ">", "+", "-", "*", "/")) {
      add_token(c, c)
      i <- i + 1L
    } else if (grepl("^[A-Za-z0-9_]$", c)) {
      start <- i
      i <- i + 1L
      while (i <= length && grepl("^[A-Za-z0-9_]$", character_at(i))) i <- i + 1L
      text <- substr(line, start, i - 1L)
      first <- substr(text, 1L, 1L)
      if (grepl("^[a-z]$", first)) {
        add_token(if (text %in% reserved) text else "name", text, text)
      } else if (grepl("^[A-Z]$", first)) {
        add_token("variable", text, text)
      } else if (text == "_") {
        add_token("anonymous", text)
      } else if (grepl("^[0-9]+$", text)) {
        value <- as.numeric(text)
        if (value > 1000000000) datalog_error(paste0("integer out of range '", text, "'"))
        add_token("integer", text, value)
      } else {
        datalog_error(paste0("bad token '", text, "'"))
      }
    } else {
      datalog_error(paste0("bad character '", c, "'"))
    }
  }
  add_token("end", "")
  position <- 1L
  peek <- function() tokens[[position]]
  advance <- function() {
    result <- peek()
    position <<- position + 1L
    result
  }
  syntax_error <- function() datalog_error(if (peek()$kind == "end") "syntax error at end of line" else paste0("syntax error at '", peek()$text, "'"))
  expect <- function(kind) {
    if (peek()$kind != kind) syntax_error()
    advance()
  }
  term <- function() {
    kind <- peek()$kind
    if (kind %in% c("name", "string", "integer")) return(list(kind = "constant", value = advance()$value))
    if (kind == "variable") return(list(kind = "variable", value = advance()$text))
    if (kind == "anonymous") {
      advance()
      return(list(kind = "anonymous"))
    }
    if (kind == "-") {
      advance()
      return(list(kind = "constant", value = -expect("integer")$value))
    }
    syntax_error()
  }
  atom <- function() {
    name <- expect("name")$text
    terms <- list()
    if (peek()$kind == "(") {
      advance()
      terms[[1]] <- term()
      while (peek()$kind == ",") {
        advance()
        terms[[length(terms) + 1L]] <- term()
      }
      expect(")")
    }
    list(name = name, terms = terms)
  }
  factor <- function() {
    if (peek()$kind == "(") {
      advance()
      result <- list(kind = "group", child = expression())
      expect(")")
      result
    } else {
      list(kind = "term", term = term())
    }
  }
  product <- function() {
    result <- factor()
    while (peek()$kind %in% c("*", "/", "mod")) {
      op <- advance()$kind
      result <- list(kind = "binary", op = op, left = result, right = factor())
    }
    result
  }
  expression <- function() {
    result <- product()
    while (peek()$kind %in% c("+", "-")) {
      op <- advance()$kind
      result <- list(kind = "binary", op = op, left = result, right = product())
    }
    result
  }
  comparisons <- c("=", "!=", "<", "<=", ">", ">=")
  literal <- function() {
    if (peek()$kind == "not") {
      advance()
      return(list(kind = "negative", atom = atom()))
    }
    if (peek()$kind == "name" && !(tokens[[position + 1L]]$kind %in% c(comparisons, "+", "-", "*", "/", "mod"))) return(list(kind = "positive", atom = atom()))
    left <- expression()
    if (!(peek()$kind %in% comparisons)) syntax_error()
    op <- advance()$kind
    list(kind = "comparison", op = op, left = left, right = expression())
  }
  body <- function() {
    literals <- list(literal())
    while (peek()$kind == ",") {
      advance()
      literals[[length(literals) + 1L]] <- literal()
    }
    literals
  }
  statement <- function() {
    kind <- peek()$kind
    if (kind == "end") return(NULL)
    if (kind == "name") {
      head <- atom()
      if (peek()$kind == ":-") {
        advance()
        result <- list(kind = "rule", head = head, body = body())
      } else {
        result <- list(kind = "fact", head = head, body = list())
      }
    } else if (kind == ":-") {
      advance()
      result <- list(kind = "constraint", head = NULL, body = body())
    } else if (kind == "?-") {
      advance()
      aggregate <- NULL
      variable <- NULL
      if (peek()$kind %in% c("count", "sum", "min", "max")) {
        aggregate <- advance()$kind
        if (aggregate != "count") {
          variable <- expect("variable")$text
          expect(":")
        }
      }
      result <- list(kind = "query", head = NULL, body = body(), aggregate = aggregate, variable = variable)
    } else if (kind %in% c("retract", "why")) {
      advance()
      result <- list(kind = kind, atom = atom())
    } else if (kind == "dump") {
      advance()
      result <- list(kind = "dump", name = expect("name")$text)
    } else if (kind == "forget") {
      advance()
      result <- list(kind = "forget", number = expect("integer")$value)
    } else if (kind == "listing") {
      advance()
      result <- list(kind = "listing", name = if (peek()$kind == "name") advance()$text else NULL)
    } else if (kind %in% c("strata", "stats", "check", "predicates", "undo", "halt")) {
      advance()
      result <- list(kind = kind)
    } else {
      syntax_error()
    }
    expect(".")
    expect("end")
    result
  }
  list(statement = statement)
}
engine <- function() {
  state <- new.env(parent = emptyenv())
  state$arities <- list()
  state$facts <- list()
  state$rules <- list()
  state$history <- list()
  state$next_rule <- 1L
  state$cache <- NULL
  facts_of <- function(name) {
    result <- state$facts[[name]]
    if (is.null(result)) list() else result
  }
  atoms <- function(statement) {
    result <- if (is.null(statement$head)) list() else list(statement$head)
    for (literal in statement$body) if (literal$kind != "comparison") result[[length(result) + 1L]] <- literal$atom
    result
  }
  predicate_check <- function(atoms, clause = FALSE) {
    prospective <- state$arities
    for (atom in atoms) {
      expected <- prospective[[atom$name]]
      if (!is.null(expected)) {
        if (expected != length(atom$terms)) datalog_error(paste0("arity mismatch for ", atom$name, ": expected ", expected, ", got ", length(atom$terms)))
      } else if (clause) {
        prospective[[atom$name]] <- length(atom$terms)
      } else {
        datalog_error(paste0("unknown predicate ", atom$name))
      }
    }
    prospective
  }
  safety <- function(statement) {
    head <- statement$head
    body <- statement$body
    if (!is.null(head) && any(vapply(head$terms, function(term) term$kind == "anonymous", logical(1)))) datalog_error("anonymous variable in head")
    for (literal in body) {
      if (literal$kind == "comparison" && any(vapply(literal_terms(literal), function(term) term$kind == "anonymous", logical(1)))) datalog_error("anonymous variable in comparison")
    }
    bound <- character()
    for (literal in body) {
      if (literal$kind == "positive") {
        bound <- c(bound, vapply(Filter(function(term) term$kind == "variable", literal$atom$terms), function(term) term$value, character(1)))
      }
    }
    required <- if (!is.null(head)) head$terms else if (!is.null(statement$variable)) list(list(kind = "variable", value = statement$variable)) else list()
    for (literal in body) if (literal$kind != "positive") required <- c(required, literal_terms(literal))
    for (term in required) if (term$kind == "variable" && !(term$value %in% bound)) datalog_error(paste0("unsafe variable ", term$value))
  }
  rule_text <- function(rule) paste0(if (is.null(rule$head)) ":- " else paste0(atom_text(rule$head), " :- "), paste(vapply(rule$body, literal_text, character(1)), collapse = ", "), ".")
  strata <- function(arities = state$arities, rules = state$rules) {
    levels <- setNames(as.list(rep(0L, length(arities))), names(arities))
    for (i in seq_along(arities)) {
      changed <- FALSE
      for (rule in rules) {
        if (is.null(rule$head)) next
        for (literal in rule$body) {
          if (literal$kind == "comparison") next
          level <- levels[[literal$atom$name]] + (if (literal$kind == "negative") 1L else 0L)
          if (level > levels[[rule$head$name]]) {
            levels[[rule$head$name]] <- level
            changed <- TRUE
          }
        }
      }
      if (!changed) return(levels)
    }
    if (length(arities) == 0L) levels else NULL
  }
  snapshot <- function(line) {
    state$history[[length(state$history) + 1L]] <- list(arities = state$arities, facts = state$facts, rules = state$rules, line = line)
    state$cache <- NULL
  }
  match_atom <- function(atom, tuple, environment) {
    result <- environment
    for (i in seq_along(atom$terms)) {
      term <- atom$terms[[i]]
      if (term$kind == "constant") {
        if (!value_equal(term$value, tuple[[i]])) return(NULL)
      } else if (term$kind == "variable") {
        if (!is.null(result[[term$value]]) && !value_equal(result[[term$value]], tuple[[i]])) return(NULL)
        result[[term$value]] <- tuple[[i]]
      }
    }
    result
  }
  divmod <- function(a, b) {
    q <- floor(abs(a) / abs(b))
    r <- abs(a) - q * abs(b)
    if (r < 0) {
      q <- q - 1
      r <- r + abs(b)
    } else if (r >= abs(b)) {
      q <- q + 1
      r <- r - abs(b)
    }
    if ((a < 0) != (b < 0)) {
      q <- -q
      if (r != 0) {
        q <- q - 1
        r <- abs(b) - r
      }
    }
    c(q, if (b < 0) -r else r)
  }
  evaluate <- function(expression, environment) {
    if (expression$kind == "term") {
      term <- expression$term
      return(if (term$kind == "constant") term$value else environment[[term$value]])
    }
    if (expression$kind == "group") return(evaluate(expression$child, environment))
    a <- evaluate(expression$left, environment)
    b <- evaluate(expression$right, environment)
    if (!is.numeric(a) || !is.numeric(b) || ((expression$op %in% c("/", "mod")) && b == 0)) return(NULL)
    switch(expression$op, "+" = a + b, "-" = a - b, "*" = a * b, "/" = divmod(a, b)[[1]], mod = divmod(a, b)[[2]])
  }
  comparison <- function(literal, environment) {
    a <- evaluate(literal$left, environment)
    b <- evaluate(literal$right, environment)
    if (is.null(a) || is.null(b)) return(FALSE)
    if (literal$op == "=") return(value_equal(a, b))
    if (literal$op == "!=") return(!value_equal(a, b))
    if (!is.numeric(a) || !is.numeric(b)) return(FALSE)
    switch(literal$op, "<" = a < b, "<=" = a <= b, ">" = a > b, ">=" = a >= b)
  }
  solutions <- function(body, data, metadata = NULL, before = NULL) {
    positives <- Filter(function(literal) literal$kind == "positive", body)
    bound_at <- list()
    for (i in seq_along(positives)) {
      for (term in positives[[i]]$atom$terms) {
        if (term$kind == "variable" && is.null(bound_at[[term$value]])) bound_at[[term$value]] <- i
      }
    }
    filters <- rep(list(list()), length(positives) + 1L)
    for (literal in body) {
      if (literal$kind == "positive") next
      stage <- 0L
      for (term in literal_terms(literal)) if (term$kind == "variable") stage <- max(stage, bound_at[[term$value]])
      filters[[stage + 1L]][[length(filters[[stage + 1L]]) + 1L]] <- literal
    }
    sources <- lapply(positives, function(literal) {
      atom <- literal$atom
      keys <- names(data[[atom$name]])
      if (!is.null(before)) keys <- keys[vapply(keys, function(key) metadata[[atom$name]][[key]][[1]] < before, logical(1))]
      unname(data[[atom$name]][keys])
    })
    variables <- unique(variable_occurrences(NULL, body))
    results <- list()
    visit <- function(stage, environment) {
      for (literal in filters[[stage + 1L]]) {
        if (literal$kind == "negative") {
          for (tuple in data[[literal$atom$name]]) if (!is.null(match_atom(literal$atom, tuple, environment))) return(invisible(NULL))
        } else if (literal$kind == "comparison" && !comparison(literal, environment)) {
          return(invisible(NULL))
        }
      }
      if (stage == length(positives)) {
        key <- tuple_key(lapply(variables, function(name) environment[[name]]))
        results[[key]] <<- environment
        return(invisible(NULL))
      }
      atom <- positives[[stage + 1L]]$atom
      seen <- new.env(parent = emptyenv())
      for (tuple in sources[[stage + 1L]]) {
        matched <- match_atom(atom, tuple, environment)
        if (is.null(matched)) next
        names <- sort(names(matched), method = "radix")
        key <- tuple_key(lapply(names, function(name) matched[[name]]))
        if (exists(key, envir = seen, inherits = FALSE)) next
        assign(key, TRUE, envir = seen)
        visit(stage + 1L, matched)
      }
      invisible(NULL)
    }
    visit(0L, list())
    sort_items(unname(results), function(a, b) tuple_compare(lapply(variables, function(name) a[[name]]), lapply(variables, function(name) b[[name]])))
  }
  head_tuple <- function(atom, environment) lapply(atom$terms, function(term) if (term$kind == "constant") term$value else environment[[term$value]])
  model <- function() {
    if (!is.null(state$cache)) return(state$cache)
    levels <- strata()
    data <- setNames(lapply(names(state$arities), facts_of), names(state$arities))
    metadata <- lapply(data, function(tuples) setNames(lapply(tuples, function(tuple) c(0L, NA_integer_)), names(tuples)))
    rounds <- added <- numeric()
    serial <- 0L
    max_level <- if (length(levels) == 0L) -1L else max(unlist(levels))
    for (level in seq_len(max_level + 1L) - 1L) {
      rounds[[level + 1L]] <- 0L
      added[[level + 1L]] <- 0L
      repeat {
        fresh <- list()
        for (rule in state$rules) {
          if (is.null(rule$head) || levels[[rule$head$name]] != level) next
          name <- rule$head$name
          for (environment in solutions(rule$body, data)) {
            tuple <- head_tuple(rule$head, environment)
            key <- tuple_key(tuple)
            if (is.null(data[[name]][[key]]) && is.null(fresh[[name]][[key]])) fresh[[name]][[key]] <- list(tuple = tuple, rule = rule$number)
          }
        }
        if (length(fresh) == 0L) break
        serial <- serial + 1L
        rounds[[level + 1L]] <- rounds[[level + 1L]] + 1L
        for (name in names(fresh)) {
          added[[level + 1L]] <- added[[level + 1L]] + length(fresh[[name]])
          for (key in names(fresh[[name]])) {
            data[[name]][[key]] <- fresh[[name]][[key]]$tuple
            metadata[[name]][[key]] <- c(serial, fresh[[name]][[key]]$rule)
          }
        }
      }
    }
    state$cache <- list(data = data, metadata = metadata, levels = levels, rounds = rounds, added = added)
    state$cache
  }
  answers <- function(body, data) {
    variables <- unique(variable_occurrences(NULL, body))
    tuples <- list()
    for (environment in solutions(body, data)) {
      tuple <- lapply(variables, function(name) environment[[name]])
      tuples[[tuple_key(tuple)]] <- tuple
    }
    list(variables = variables, tuples = sort_items(unname(tuples)))
  }
  answer_text <- function(variables, tuple) {
    paste(vapply(seq_along(variables), function(i) paste0(variables[[i]], " = ", value_text(tuple[[i]])), character(1)), collapse = ", ")
  }
  proof <- function(name, tuple, data, metadata, depth = 0L) {
    indent <- strrep("  ", depth)
    serial <- metadata[[name]][[tuple_key(tuple)]][[1]]
    if (serial == 0L) return(paste0(indent, tuple_text(name, tuple), " [fact]"))
    chosen_rule <- chosen <- NULL
    for (rule in state$rules) {
      if (is.null(rule$head) || rule$head$name != name) next
      variables <- unique(variable_occurrences(rule$head, rule$body))
      candidates <- Filter(function(environment) tuple_compare(head_tuple(rule$head, environment), tuple) == 0L, solutions(rule$body, data, metadata, serial))
      if (length(candidates) == 0L) next
      candidates <- sort_items(candidates, function(a, b) tuple_compare(lapply(variables, function(name) a[[name]]), lapply(variables, function(name) b[[name]])))
      chosen_rule <- rule
      chosen <- candidates[[1]]
      break
    }
    lines <- paste0(indent, tuple_text(name, tuple), " [rule ", chosen_rule$number, "]")
    for (literal in chosen_rule$body) {
      if (literal$kind == "positive") {
        atom <- literal$atom
        matched <- list()
        for (key in names(data[[atom$name]])) {
          item <- data[[atom$name]][[key]]
          if (metadata[[atom$name]][[key]][[1]] < serial && !is.null(match_atom(atom, item, chosen))) matched[[length(matched) + 1L]] <- item
        }
        matched <- sort_items(matched)
        lines <- c(lines, proof(atom$name, matched[[1]], data, metadata, depth + 1L))
      } else {
        lines <- c(lines, paste0(indent, "  ", literal_text(literal, chosen)))
      }
    }
    lines
  }
  execute <- function(statement, line) {
    kind <- statement$kind
    if (kind %in% c("fact", "rule", "constraint")) {
      prospective <- predicate_check(atoms(statement), TRUE)
      safety(statement)
      if (kind == "fact") {
        atom <- statement$head
        tuple <- head_tuple(atom, list())
        key <- tuple_key(tuple)
        if (!is.null(facts_of(atom$name)[[key]])) return(character())
        snapshot(line)
        state$arities <- prospective
        state$facts[[atom$name]][[key]] <- tuple
        return(character())
      }
      notation <- rule_text(statement)
      for (rule in state$rules) if (rule$notation == notation) datalog_error(paste0("duplicate of rule ", rule$number))
      if (kind == "rule" && is.null(strata(prospective, c(state$rules, list(statement))))) datalog_error(paste0("negative cycle through ", statement$head$name))
      snapshot(line)
      statement$number <- state$next_rule
      statement$notation <- notation
      state$next_rule <- state$next_rule + 1L
      state$rules[[length(state$rules) + 1L]] <- statement
      state$arities <- prospective
      occurrences <- variable_occurrences(statement$head, statement$body)
      names <- unique(occurrences)
      names <- names[vapply(names, function(name) sum(occurrences == name) == 1L, logical(1))]
      return(paste0("WARNING line ", line, ": singleton variable ", names)[seq_along(names)])
    }
    if (kind == "query") {
      predicate_check(atoms(statement))
      safety(statement)
      result <- answers(statement$body, model()$data)
      variables <- result$variables
      tuples <- result$tuples
      aggregate <- statement$aggregate
      if (!is.null(aggregate) && aggregate == "count") return(as.character(length(tuples)))
      if (!is.null(aggregate) && aggregate %in% c("sum", "min", "max")) {
        position <- match(statement$variable, variables)
        values <- lapply(tuples, function(tuple) tuple[[position]])
        if (aggregate == "sum") {
          if (any(!vapply(values, is.numeric, logical(1)))) datalog_error("non-integer value in sum")
          return(value_text(sum(unlist(values))))
        }
        if (length(values) == 0L) return("no answers")
        values <- sort_items(values, value_compare)
        return(value_text(if (aggregate == "min") values[[1]] else tail(values, 1L)[[1]]))
      }
      if (length(variables) == 0L) return(if (length(tuples) == 0L) "false." else "true.")
      return(c(vapply(tuples, function(tuple) answer_text(variables, tuple), character(1)), paste0(length(tuples), if (length(tuples) == 1L) " answer" else " answers")))
    }
    if (kind %in% c("retract", "why")) {
      atom <- statement$atom
      predicate_check(list(atom))
      if (kind == "retract") {
        facts <- facts_of(atom$name)
        removed <- names(Filter(function(tuple) !is.null(match_atom(atom, tuple, list())), facts))
        if (length(removed) == 0L) datalog_error("no matching facts")
        snapshot(line)
        state$facts[[atom$name]][removed] <- NULL
        return(paste0(length(removed), if (length(removed) == 1L) " fact retracted" else " facts retracted"))
      }
      if (any(vapply(atom$terms, function(term) term$kind != "constant", logical(1)))) datalog_error("why needs a ground atom")
      tuple <- head_tuple(atom, list())
      result <- model()
      return(if (is.null(result$data[[atom$name]][[tuple_key(tuple)]])) "false." else proof(atom$name, tuple, result$data, result$metadata))
    }
    if (kind == "dump") {
      name <- statement$name
      if (is.null(state$arities[[name]])) datalog_error(paste0("unknown predicate ", name))
      tuples <- sort_items(unname(model()$data[[name]]))
      return(c(vapply(tuples, function(tuple) paste0(tuple_text(name, tuple), "."), character(1)), paste0(length(tuples), if (length(tuples) == 1L) " tuple" else " tuples")))
    }
    if (kind == "forget") {
      indices <- which(vapply(state$rules, function(rule) rule$number == statement$number, logical(1)))
      if (length(indices) == 0L) datalog_error(paste0("no rule ", statement$number))
      snapshot(line)
      state$rules <- state$rules[-indices[[1]]]
      return(character())
    }
    if (kind == "undo") {
      if (length(state$history) == 0L) datalog_error("nothing to undo")
      saved <- tail(state$history, 1L)[[1]]
      state$history <- head(state$history, -1L)
      state$arities <- saved$arities
      state$facts <- saved$facts
      state$rules <- saved$rules
      state$cache <- NULL
      return(paste0("undid line ", saved$line))
    }
    if (kind == "listing") {
      name <- statement$name
      if (!is.null(name) && is.null(state$arities[[name]])) datalog_error(paste0("unknown predicate ", name))
      rules <- Filter(function(rule) is.null(name) || (!is.null(rule$head) && rule$head$name == name), state$rules)
      if (length(rules) == 0L) return("no rules")
      return(vapply(rules, function(rule) paste0(rule$number, ": ", rule$notation), character(1)))
    }
    if (kind == "strata") {
      if (length(state$arities) == 0L) return("no predicates")
      levels <- strata()
      dependencies <- setNames(rep(list(character()), length(state$arities)), names(state$arities))
      for (rule in state$rules) if (!is.null(rule$head)) dependencies[[rule$head$name]] <- c(dependencies[[rule$head$name]], vapply(atoms(rule)[-1L], function(atom) atom$name, character(1)))
      recursive <- setNames(rep(FALSE, length(dependencies)), names(dependencies))
      for (name in names(dependencies)) {
        seen <- character()
        search <- function(current) {
          for (target in dependencies[[current]]) {
            if (target == name) return(TRUE)
            if (!(target %in% seen)) {
              seen <<- c(seen, target)
              if (search(target)) return(TRUE)
            }
          }
          FALSE
        }
        recursive[[name]] <- search(name)
      }
      return(vapply(seq_len(max(unlist(levels)) + 1L) - 1L, function(level) {
        names <- sort(names(levels)[unlist(levels) == level], method = "radix")
        displayed <- vapply(names, function(name) paste0(name, if (recursive[[name]]) "*" else ""), character(1))
        paste0("stratum ", level, ": ", paste(displayed, collapse = ", "))
      }, character(1)))
    }
    if (kind == "stats") {
      result <- model()
      rules <- Filter(function(rule) !is.null(rule$head), state$rules)
      lines <- paste0("facts ", sum(vapply(state$facts, length, integer(1))), ", rules ", length(rules), ", constraints ", length(state$rules) - length(rules), ", tuples ", sum(vapply(result$data, length, integer(1))))
      for (level in seq_along(result$rounds) - 1L) lines <- c(lines, paste0("stratum ", level, ": rounds ", result$rounds[[level + 1L]], ", new ", result$added[[level + 1L]]))
      for (rule in rules) {
        count <- sum(vapply(result$metadata, function(entries) sum(vapply(entries, function(entry) !is.na(entry[[2]]) && entry[[2]] == rule$number, logical(1))), integer(1)))
        lines <- c(lines, paste0("rule ", rule$number, ": new ", count))
      }
      return(lines)
    }
    if (kind == "predicates") {
      if (length(state$arities) == 0L) return("no predicates")
      data <- model()$data
      return(vapply(sort(names(state$arities), method = "radix"), function(name) {
        count <- sum(vapply(state$rules, function(rule) !is.null(rule$head) && rule$head$name == name, logical(1)))
        paste0(name, "/", state$arities[[name]], ": facts ", length(facts_of(name)), ", rules ", count, ", tuples ", length(data[[name]]))
      }, character(1)))
    }
    constraints <- Filter(function(rule) is.null(rule$head), state$rules)
    if (length(constraints) == 0L) return("no constraints")
    data <- model()$data
    lines <- character()
    for (rule in constraints) {
      result <- answers(rule$body, data)
      count <- length(result$tuples)
      if (count == 0L) {
        lines <- c(lines, paste0("constraint ", rule$number, ": ok"))
      } else {
        lines <- c(lines, paste0("constraint ", rule$number, ": ", count, if (count == 1L) " violation" else " violations"))
        if (length(result$variables) != 0L) for (tuple in result$tuples) lines <- c(lines, paste0("  ", answer_text(result$variables, tuple)))
      }
    }
    lines
  }
  input <- file("stdin", open = "r")
  on.exit(close(input))
  number <- 0L
  repeat {
    lines <- readLines(input, n = 1L, warn = FALSE)
    if (length(lines) == 0L) break
    number <- number + 1L
    statement <- tryCatch(new_parser(lines[[1]])$statement(), datalog_error = function(error) {
      cat("ERROR line ", number, ": ", error$message, "\n", sep = "")
      NULL
    })
    if (is.null(statement)) next
    if (statement$kind == "halt") break
    output <- tryCatch(execute(statement, number), datalog_error = function(error) paste0("ERROR line ", number, ": ", error$message))
    for (text in output) cat(text, "\n", sep = "")
  }
}

engine()
