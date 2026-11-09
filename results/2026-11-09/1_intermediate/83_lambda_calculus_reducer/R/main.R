options(expressions = 50000, scipen = 999)

lambda_error <- function(reason) {
  stop(structure(list(message = reason, call = NULL), class = c("lambda_error", "error", "condition")))
}
term <- function(kind, name = NULL, left = NULL, right = NULL) {
  free <- switch(kind, var = name, abs = setdiff(left$free, name), app = union(left$free, right$free), character())
  list(kind = kind, name = name, left = left, right = right, free = free,
       size = 1L + (if (is.null(left)) 0L else left$size) + (if (is.null(right)) 0L else right$size),
       depth = 1L + max(if (is.null(left)) 0L else left$depth, if (is.null(right)) 0L else right$depth))
}
variable <- function(name) term("var", name)
abstraction <- function(name, body) term("abs", name, body)
application <- function(left, right) {
  force(left)
  force(right)
  term("app", NULL, left, right)
}
printed <- function(node, end = TRUE, db = FALSE) {
  if (node$kind %in% c("var", "macro", "constant")) return(node$name)
  if (node$kind == "number") return(paste0("#", node$name))
  if (node$kind == "index") return(as.character(node$name))
  if (node$kind == "abs") {
    names <- character()
    count <- 0L
    body <- node
    while (body$kind == "abs") {
      names <- c(names, body$name)
      count <- count + 1L
      body <- body$left
    }
    text <- if (db) paste0(strrep("\\", count), printed(body, TRUE, TRUE)) else paste0("\\", paste(names, collapse = " "), ". ", printed(body))
    return(if (end) text else paste0("(", text, ")"))
  }
  left <- if (node$left$kind == "abs") paste0("(", printed(node$left, TRUE, db), ")") else printed(node$left, FALSE, db)
  right <- if (node$right$kind == "app") paste0("(", printed(node$right, TRUE, db), ")") else printed(node$right, end, db)
  paste(left, right)
}
new_parser <- function(argument, offset, end_column) {
  tokens <- list()
  chars <- strsplit(argument, "", fixed = TRUE)[[1]]
  i <- 1L
  while (i <= length(chars)) {
    c <- chars[[i]]
    if (c == " ") {
      i <- i + 1L
      next
    }
    start <- i
    if (c %in% c("\\", ".", "(", ")", "=", ";")) {
      kind <- c
      i <- i + 1L
    } else if (grepl("^[a-z]$", c)) {
      kind <- "var"
      i <- i + 1L
      while (i <= length(chars) && grepl("^[a-z0-9]$", chars[[i]])) i <- i + 1L
    } else if (grepl("^[A-Z]$", c)) {
      kind <- "macro"
      i <- i + 1L
      while (i <= length(chars) && grepl("^[A-Z0-9_]$", chars[[i]])) i <- i + 1L
    } else if (c == "#" && i < length(chars) && grepl("^[0-9]$", chars[[i + 1L]])) {
      kind <- "number"
      i <- i + 2L
      while (i <= length(chars) && grepl("^[0-9]$", chars[[i]])) i <- i + 1L
    } else {
      lambda_error(paste0("column ", offset + i - 1L, ": unexpected character '", c, "'"))
    }
    tokens[[length(tokens) + 1L]] <- list(kind = kind, text = substr(argument, start, i - 1L), column = offset + start - 1L)
  }
  tokens[[length(tokens) + 1L]] <- list(kind = "end", text = "", column = end_column)
  position <- 1L
  peek <- function() tokens[[position]]
  advance <- function() {
    result <- peek()
    position <<- position + 1L
    result
  }
  expect <- function(kind) {
    notation <- if (kind == "var") "variable" else if (kind == "macro") "macro name" else paste0("'", kind, "'")
    if (peek()$kind != kind) lambda_error(paste0("column ", peek()$column, ": expected ", notation))
    advance()$text
  }
  read_term <- function() {
    elements <- list()
    while (peek()$kind %in% c("var", "macro", "number", "(")) {
      token <- advance()
      if (token$kind == "(") {
        elements[[length(elements) + 1L]] <- read_term()
        expect(")")
      } else {
        elements[[length(elements) + 1L]] <- term(token$kind, if (token$kind == "number") as.integer(substring(token$text, 2L)) else token$text)
      }
    }
    if (peek()$kind == "\\") {
      advance()
      names <- expect("var")
      while (peek()$kind == "var") names <- c(names, advance()$text)
      expect(".")
      body <- read_term()
      for (name in rev(names)) body <- abstraction(name, body)
      elements[[length(elements) + 1L]] <- body
    }
    if (length(elements) == 0L) lambda_error(paste0("column ", peek()$column, ": expected term"))
    result <- elements[[1]]
    for (element in elements[-1L]) result <- application(result, element)
    result
  }
  finish <- function() {
    if (peek()$kind != "end") lambda_error(paste0("column ", peek()$column, ": unexpected '", peek()$text, "'"))
  }
  list(peek = peek, advance = advance, expect = expect, term = read_term, finish = finish)
}
references <- function(node) {
  switch(node$kind, macro = node$name, abs = references(node$left), app = c(references(node$left), references(node$right)), character())
}
name_at <- function(index) paste0(intToUtf8(97L + index %% 26L), if (index >= 26L) as.character(index %/% 26L) else "")
canonical <- function(node) {
  free <- node$free
  counter <- 0L
  visit <- function(node, bindings) {
    if (node$kind == "var") return(variable(if (is.null(bindings[[node$name]])) node$name else bindings[[node$name]]))
    if (node$kind == "abs") {
      while (name_at(counter) %in% free) counter <<- counter + 1L
      name <- name_at(counter)
      counter <<- counter + 1L
      bindings[[node$name]] <- name
      return(abstraction(name, visit(node$left, bindings)))
    }
    if (node$kind == "app") return(application(visit(node$left, bindings), visit(node$right, bindings)))
    node
  }
  visit(node, list())
}
to_debruijn <- function(node, bindings = character()) {
  if (node$kind == "var") {
    index <- match(node$name, bindings)
    return(if (is.na(index)) node else term("index", index - 1L))
  }
  if (node$kind == "abs") return(abstraction(NULL, to_debruijn(node$left, c(node$name, bindings))))
  application(to_debruijn(node$left, bindings), to_debruijn(node$right, bindings))
}
from_debruijn <- function(node) {
  free <- node$free
  counter <- 0L
  visit <- function(node, bindings) {
    if (node$kind == "index") return(variable(bindings[[node$name + 1L]]))
    if (node$kind == "var") return(node)
    if (node$kind == "abs") {
      while (name_at(counter) %in% free) counter <<- counter + 1L
      name <- name_at(counter)
      counter <<- counter + 1L
      return(abstraction(name, visit(node$left, c(name, bindings))))
    }
    application(visit(node$left, bindings), visit(node$right, bindings))
  }
  visit(node, character())
}
substitute <- function(node, name, replacement) {
  if (node$kind == "var") return(if (node$name == name) replacement else node)
  if (node$kind == "app") return(application(substitute(node$left, name, replacement), substitute(node$right, name, replacement)))
  bound <- node$name
  body <- node$left
  if (bound == name || !(name %in% body$free)) return(node)
  if (bound %in% replacement$free) {
    stem <- sub("[0-9]+$", "", bound)
    suffix <- 1L
    while (paste0(stem, suffix) %in% c(replacement$free, body$free)) suffix <- suffix + 1L
    fresh <- paste0(stem, suffix)
    body <- substitute(body, bound, variable(fresh))
    bound <- fresh
  }
  abstraction(bound, substitute(body, name, replacement))
}
eta_target <- function(node) {
  body <- node$left
  if (body$kind == "app" && body$right$kind == "var" && body$right$name == node$name && !(node$name %in% body$left$free)) body$left else NULL
}
one_step <- function(node, strategy, eta) {
  if (node$kind == "app") {
    left <- node$left
    right <- node$right
    if (strategy %in% c("NORMAL", "CBN") && left$kind == "abs") return(list(substitute(left$left, left$name, right), "beta"))
    step <- one_step(left, strategy, eta)
    if (!is.null(step)) return(list(application(step[[1]], right), step[[2]]))
    if (strategy != "CBN") {
      step <- one_step(right, strategy, eta)
      if (!is.null(step)) return(list(application(left, step[[1]]), step[[2]]))
    }
    if (strategy %in% c("APPLICATIVE", "CBV") && left$kind == "abs" && (strategy != "CBV" || right$kind %in% c("var", "abs"))) return(list(substitute(left$left, left$name, right), "beta"))
  } else if (node$kind == "abs" && strategy %in% c("NORMAL", "APPLICATIVE")) {
    target <- if (eta) eta_target(node) else NULL
    if (!is.null(target) && strategy == "NORMAL") return(list(target, "eta"))
    step <- one_step(node$left, strategy, eta)
    if (!is.null(step)) return(list(abstraction(node$name, step[[1]]), step[[2]]))
    if (!is.null(target)) return(list(target, "eta"))
  }
  NULL
}
ski_abstract <- function(name, node) {
  if (!(name %in% node$free)) return(application(term("constant", "K"), node))
  if (node$kind == "var" && node$name == name) return(term("constant", "I"))
  if (node$right$kind == "var" && node$right$name == name && !(name %in% node$left$free)) return(node$left)
  application(application(term("constant", "S"), ski_abstract(name, node$left)), ski_abstract(name, node$right))
}
to_ski <- function(node) {
  switch(node$kind, var = node, abs = ski_abstract(node$name, to_ski(node$left)), app = application(to_ski(node$left), to_ski(node$right)))
}
ski_step <- function(node) {
  head <- node
  args <- list()
  while (head$kind == "app") {
    args <- c(list(head$right), args)
    head <- head$left
  }
  arity <- if (head$kind == "constant") c(I = 1L, K = 2L, S = 3L)[[head$name]] else NULL
  if (!is.null(arity) && length(args) >= arity) {
    result <- if (head$name == "S") application(application(args[[1]], args[[3]]), application(args[[2]], args[[3]])) else args[[1]]
    for (arg in tail(args, length(args) - arity)) result <- application(result, arg)
    return(list(result, head$name))
  }
  for (i in seq_along(args)) {
    step <- ski_step(args[[i]])
    if (!is.null(step)) {
      args[[i]] <- step[[1]]
      result <- head
      for (arg in args) result <- application(result, arg)
      return(list(result, step[[2]]))
    }
  }
  NULL
}
principal_type <- function(node) {
  next_id <- 0L
  links <- new.env(parent = emptyenv())
  free <- new.env(parent = emptyenv())
  fresh <- function() {
    result <- list(kind = "variable", id = next_id)
    next_id <<- next_id + 1L
    result
  }
  prune <- function(type) {
    path <- character()
    while (type$kind == "variable" && exists(as.character(type$id), envir = links, inherits = FALSE)) {
      key <- as.character(type$id)
      path <- c(path, key)
      type <- get(key, envir = links, inherits = FALSE)
    }
    for (key in path) assign(key, type, envir = links)
    type
  }
  occurs <- function(id, type) {
    type <- prune(type)
    if (type$kind == "variable") type$id == id else occurs(id, type$left) || occurs(id, type$right)
  }
  unify <- function(left, right) {
    left <- prune(left)
    right <- prune(right)
    if (identical(left, right)) return(invisible(NULL))
    if (left$kind == "variable") {
      if (occurs(left$id, right)) stop(structure(list(message = "", call = NULL), class = c("untypable", "error", "condition")))
      assign(as.character(left$id), right, envir = links)
    } else if (right$kind == "variable") {
      unify(right, left)
    } else {
      unify(left$left, right$left)
      unify(left$right, right$right)
    }
  }
  infer <- function(node, environment = list()) {
    if (node$kind == "var") {
      bound <- environment[[node$name]]
      if (!is.null(bound)) return(bound)
      if (!exists(node$name, envir = free, inherits = FALSE)) assign(node$name, fresh(), envir = free)
      return(get(node$name, envir = free, inherits = FALSE))
    }
    if (node$kind == "abs") {
      parameter <- fresh()
      environment[[node$name]] <- parameter
      return(list(kind = "arrow", left = parameter, right = infer(node$left, environment)))
    }
    function_type <- infer(node$left, environment)
    argument_type <- infer(node$right, environment)
    result <- fresh()
    unify(function_type, list(kind = "arrow", left = argument_type, right = result))
    result
  }
  tryCatch({
    type <- infer(node)
    names <- new.env(parent = emptyenv())
    name_count <- 0L
    visit <- function(type) {
      type <- prune(type)
      if (type$kind == "variable") {
        key <- as.character(type$id)
        if (!exists(key, envir = names, inherits = FALSE)) {
          assign(key, name_at(name_count), envir = names)
          name_count <<- name_count + 1L
        }
        return(get(key, envir = names, inherits = FALSE))
      }
      left <- visit(type$left)
      if (prune(type$left)$kind == "arrow") left <- paste0("(", left, ")")
      paste0(left, " -> ", visit(type$right))
    }
    visit(type)
  }, untypable = function(error) "not typable")
}
church_value <- function(node) {
  if (node$kind == "abs" && node$left$kind == "abs") {
    f <- node$name
    x <- node$left$name
    body <- node$left$left
    count <- 0L
    while (body$kind == "app" && body$left$kind == "var" && body$left$name == f) {
      count <- count + 1L
      body <- body$right
    }
    if (body$kind == "var" && body$name == x) return(as.character(count))
    if (node$left$left$kind == "var" && node$left$left$name == f) return("true")
  }
  if (node$kind == "abs") {
    body <- node$left
    if (body$kind == "app" && body$left$kind == "app" && body$left$left$kind == "var" && body$left$left$name == node$name) {
      p <- body$left$right
      q <- body$right
      if (!(node$name %in% p$free) && !(node$name %in% q$free)) return(paste0("(", church_value(p), ", ", church_value(q), ")"))
    }
  }
  printed(canonical(node))
}
materialize <- function(code, environment, level = 0L) {
  while (code$kind == "index" && code$name >= level) {
    closure <- environment[[code$name - level + 1L]]
    code <- closure$code
    environment <- closure$environment
    level <- 0L
  }
  if (code$kind == "app") return(application(materialize(code$left, environment, level), materialize(code$right, environment, level)))
  if (code$kind == "abs") return(abstraction(NULL, materialize(code$left, environment, level + 1L)))
  code
}
workbench <- function() {
  reserved <- c("S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV")
  commands <- c("let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam")
  state <- new.env(parent = emptyenv())
  state$macros <- list(
    S = abstraction("x", abstraction("y", abstraction("z", application(application(variable("x"), variable("z")), application(variable("y"), variable("z")))))),
    K = abstraction("x", abstraction("y", variable("x"))),
    I = abstraction("x", variable("x"))
  )
  state$steps <- FALSE
  state$eta <- FALSE
  state$limit <- 10000L
  emit <- function(...) cat(paste0(...), "\n", sep = "")
  depends <- function(name, target) {
    visited <- character()
    visit <- function(current) {
      if (current %in% visited) return(FALSE)
      visited <<- c(visited, current)
      if (is.null(state$macros[[current]]) || current %in% c("S", "K", "I")) return(FALSE)
      for (ref in references(state$macros[[current]])) {
        if (ref == target || visit(ref)) return(TRUE)
      }
      FALSE
    }
    visit(name)
  }
  expand <- function(node) {
    if (node$kind == "macro") {
      definition <- state$macros[[node$name]]
      if (is.null(definition)) lambda_error(paste0("unbound macro ", node$name))
      return(expand(definition))
    }
    if (node$kind == "number") {
      body <- variable("x")
      for (i in seq_len(node$name)) body <- application(variable("f"), body)
      return(abstraction("f", abstraction("x", body)))
    }
    if (node$kind == "abs") return(abstraction(node$name, expand(node$left)))
    if (node$kind == "app") return(application(expand(node$left), expand(node$right)))
    node
  }
  reduce <- function(node, strategy = "NORMAL", eta = state$eta, display = FALSE, ski = FALSE) {
    count <- 0L
    repeat {
      step <- if (ski) ski_step(node) else one_step(node, strategy, eta)
      if (is.null(step)) return(list(node, count))
      if (count == state$limit) return(NULL)
      node <- step[[1]]
      count <- count + 1L
      if (display && state$steps) emit("step ", count, " (", step[[2]], "): ", printed(node))
    }
  }
  kam <- function(node) {
    code <- to_debruijn(node)
    environment <- list()
    stack <- list()
    count <- 0L
    repeat {
      kind <- switch(code$kind, app = "push", abs = if (length(stack) == 0L) NULL else "grab", index = "access", NULL)
      if (is.null(kind)) break
      if (count == state$limit) {
        emit("no result within ", state$limit, " transitions")
        return(invisible(NULL))
      }
      if (kind == "push") {
        stack[[length(stack) + 1L]] <- list(code = code$right, environment = environment)
        code <- code$left
      } else if (kind == "grab") {
        environment <- c(tail(stack, 1L), environment)
        stack <- head(stack, -1L)
        code <- code$left
      } else {
        closure <- environment[[code$name + 1L]]
        code <- closure$code
        environment <- closure$environment
      }
      count <- count + 1L
      if (state$steps) emit("step ", count, " (", kind, "): ", printed(code, TRUE, TRUE), " [env ", length(environment), ", stack ", length(stack), "]")
    }
    result <- materialize(code, environment)
    for (closure in rev(stack)) result <- application(result, materialize(closure$code, closure$environment))
    emit("result: ", printed(from_debruijn(result)), " (transitions: ", count, ")")
  }
  command <- function(line) {
    space <- regexpr(" ", line, fixed = TRUE)[[1]]
    name <- if (space < 0L) line else substr(line, 1L, space - 1L)
    argument <- if (space < 0L) "" else substring(line, space + 1L)
    if (!(name %in% commands)) lambda_error(paste0("unknown command ", name))
    if (name %in% c("steps", "eta", "limit", "macros", "unlet")) {
      words <- strsplit(argument, " +")[[1]]
      words <- words[nzchar(words)]
      if (name %in% c("steps", "eta")) {
        if (length(words) != 1L || !(words[[1]] %in% c("on", "off"))) lambda_error("bad argument")
        if (name == "steps") state$steps <- words[[1]] == "on" else state$eta <- words[[1]] == "on"
      } else if (name == "limit") {
        if (length(words) != 1L || !grepl("^[0-9]{1,5}$", words[[1]]) || as.integer(words[[1]]) < 1L || as.integer(words[[1]]) > 10000L) lambda_error("bad argument")
        state$limit <- as.integer(words[[1]])
      } else if (name == "macros") {
        if (length(words) != 0L) lambda_error("bad argument")
        names <- sort(setdiff(names(state$macros), c("S", "K", "I")), method = "radix")
        if (length(names) == 0L) emit("(none)")
        for (macro in names) emit(macro, " = ", printed(state$macros[[macro]]))
      } else {
        if (length(words) != 1L || !grepl("^[A-Z][A-Z0-9_]*$", words[[1]])) lambda_error("bad argument")
        macro <- words[[1]]
        if (macro %in% reserved) lambda_error(paste0("reserved name ", macro))
        if (is.null(state$macros[[macro]])) lambda_error(paste0("unbound macro ", macro))
        for (other in sort(names(state$macros), method = "radix")) {
          if (!(other %in% c("S", "K", "I")) && macro %in% references(state$macros[[other]])) lambda_error(paste0(macro, " is used by ", other))
        }
        state$macros[[macro]] <- NULL
        emit("removed ", macro)
      }
      return(invisible(NULL))
    }
    parser <- new_parser(argument, nchar(name) + 2L, nchar(line) + 1L)
    strategy <- "NORMAL"
    binding <- NULL
    terms <- list()
    if (name %in% c("let", "subst")) {
      binding <- parser$expect(if (name == "let") "macro" else "var")
      parser$expect("=")
      terms[[1]] <- parser$term()
      if (name == "subst") {
        parser$expect(";")
        terms[[2]] <- parser$term()
      }
    } else if (name %in% c("equal", "alpha")) {
      terms[[1]] <- parser$term()
      parser$expect(";")
      terms[[2]] <- parser$term()
    } else {
      if (name == "reduce" && parser$peek()$kind == "macro" && parser$peek()$text %in% c("NORMAL", "APPLICATIVE", "CBN", "CBV")) strategy <- parser$advance()$text
      terms[[1]] <- parser$term()
    }
    parser$finish()
    if (name == "let") {
      if (binding %in% reserved) lambda_error(paste0("reserved name ", binding))
      for (ref in references(terms[[1]])) {
        if (ref == binding || depends(ref, binding)) lambda_error(paste0("recursive definition of ", binding))
        if (is.null(state$macros[[ref]])) lambda_error(paste0("unbound macro ", ref))
      }
      if (length(terms[[1]]$free) != 0L) lambda_error(paste0("free variable ", sort(terms[[1]]$free, method = "radix")[[1]], " in definition of ", binding))
      emit(if (is.null(state$macros[[binding]])) "defined " else "redefined ", binding)
      state$macros[[binding]] <- terms[[1]]
      return(invisible(NULL))
    }
    terms <- lapply(terms, expand)
    node <- terms[[1]]
    if (name == "expand") {
      emit(printed(node))
    } else if (name == "subst") {
      emit(printed(substitute(terms[[2]], binding, node)))
    } else if (name == "alpha") {
      emit(if (printed(to_debruijn(node), TRUE, TRUE) == printed(to_debruijn(terms[[2]]), TRUE, TRUE)) "yes" else "no")
    } else if (name == "debruijn") {
      emit(printed(to_debruijn(node), TRUE, TRUE))
    } else if (name == "fv") {
      emit(if (length(node$free) == 0L) "(none)" else paste(sort(node$free, method = "radix"), collapse = " "))
    } else if (name == "size") {
      emit(node$size)
    } else if (name == "depth") {
      emit(node$depth)
    } else if (name == "type") {
      emit(principal_type(node))
    } else if (name == "ski") {
      emit(printed(to_ski(node)))
    } else if (name == "kam") {
      kam(node)
    } else if (name == "equal") {
      left <- reduce(node)
      right <- reduce(terms[[2]])
      emit(if (is.null(left) || is.null(right)) "unknown" else if (printed(canonical(left[[1]])) == printed(canonical(right[[1]]))) "yes" else "no")
    } else {
      result <- if (name == "church") reduce(node, "NORMAL", FALSE) else if (name == "skireduce") reduce(to_ski(node), "NORMAL", FALSE, TRUE, TRUE) else reduce(node, strategy, state$eta, TRUE)
      if (is.null(result)) {
        emit("no normal form within ", state$limit, " steps")
      } else if (name == "church") {
        emit(church_value(canonical(result[[1]])))
      } else {
        text <- if (name == "skireduce") printed(result[[1]]) else printed(canonical(result[[1]]))
        emit("result: ", text, " (steps: ", result[[2]], ")")
      }
    }
  }
  input <- file("stdin", open = "r")
  on.exit(close(input))
  repeat {
    lines <- readLines(input, n = 1L, warn = FALSE)
    if (length(lines) == 0L || lines[[1]] == "quit") break
    line <- lines[[1]]
    if (line == "" || startsWith(line, "--")) next
    tryCatch(command(line), lambda_error = function(error) emit("error: ", error$message))
  }
}

workbench()
