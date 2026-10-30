source("lexer.R")
source("unifier.R")
source("parser.R")
source("inference.R")
source("evaluator.R")
options(expressions = 500000L)
print_value <- function(value) {
  if (is.logical(value)) return(if (value) "true" else "false")
  if (is.numeric(value)) return(sprintf("%.0f", value))
  if (is.character(value)) {
    characters <- strsplit(value, "", fixed = TRUE)[[1L]]
    escaped <- vapply(characters, function(character) {
      if (character == "\\") "\\\\" else if (character == '"') '\\"' else if (character == "\n") "\\n" else if (character == "\t") "\\t" else character
    }, character(1L))
    return(paste0('"', paste(escaped, collapse = ""), '"'))
  }
  if (inherits(value, c("ml_closure", "ml_builtin"))) return("<fun>")
  if (inherits(value, "ml_pair")) return(paste0("(", print_value(value[[1L]]), ", ", print_value(value[[2L]]), ")"))
  paste0("[", paste(vapply(value, print_value, character(1L)), collapse = "; "), "]")
}
new_type_printer <- function(quantified = NULL) new_record(names = list(), quantified = quantified)
print_type <- function(printer, value) {
  value <- resolve_type(value)
  if (value$kind == "variable") {
    key <- as.character(value$id)
    if (is.null(printer$names[[key]])) {
      index <- length(printer$names)
      prefix <- if (!is.null(printer$quantified) && !value$id %in% printer$quantified) "'_" else "'"
      suffix <- if (index >= 26L) as.character(index %/% 26L) else ""
      printer$names[[key]] <- paste0(prefix, intToUtf8(97L + index %% 26L), suffix)
    }
    return(printer$names[[key]])
  }
  if (value$kind %in% c("int", "bool", "string")) return(value$kind)
  first <- resolve_type(value$children[[1L]])
  left <- print_type(printer, first)
  if (value$kind == "list") {
    if (first$kind %in% c("pair", "function")) left <- paste0("(", left, ")")
    return(paste0(left, " list"))
  }
  second <- resolve_type(value$children[[2L]])
  right <- print_type(printer, second)
  if (value$kind == "pair") {
    if (first$kind %in% c("pair", "function")) left <- paste0("(", left, ")")
    if (second$kind %in% c("pair", "function")) right <- paste0("(", right, ")")
    return(paste(left, "*", right))
  }
  if (first$kind == "function") left <- paste0("(", left, ")")
  paste(left, "->", right)
}
format_declared_type <- function(expression) {
  if (expression$kind == "type_variable") return(expression$value)
  if (expression$kind %in% c("int", "bool", "string")) return(expression$kind)
  first <- expression$children[[1L]]
  left <- format_declared_type(first)
  if (expression$kind == "list") {
    if (first$kind %in% c("pair", "function")) left <- paste0("(", left, ")")
    return(paste0(left, " list"))
  }
  second <- expression$children[[2L]]
  right <- format_declared_type(second)
  if (expression$kind == "pair") {
    if (first$kind %in% c("pair", "function")) left <- paste0("(", left, ")")
    if (second$kind %in% c("pair", "function")) right <- paste0("(", right, ")")
    return(paste(left, "*", right))
  }
  if (first$kind == "function") left <- paste0("(", left, ")")
  paste(left, "->", right)
}
signature_type <- function(expression, variables) {
  if (expression$kind == "type_variable") {
    key <- expression$value
    if (!exists(key, variables, inherits = FALSE)) assign(key, new_type_variable(), variables)
    return(get(key, variables, inherits = FALSE))
  }
  do.call(ml_type, c(list(expression$kind), lapply(expression$children, signature_type, variables = variables)))
}
identical_types <- function(first, second) {
  first <- resolve_type(first)
  second <- resolve_type(second)
  if (first$kind == "variable" || second$kind == "variable") return(identical(first, second))
  first$kind == second$kind && all(vapply(seq_along(first$children), function(index) identical_types(first$children[[index]], second$children[[index]]), logical(1L)))
}
signature_matches <- function(inferred, declared, assignments) {
  inferred <- resolve_type(inferred)
  declared <- resolve_type(declared)
  if (inferred$kind == "variable") {
    key <- as.character(inferred$id)
    if (exists(key, assignments, inherits = FALSE)) return(identical_types(get(key, assignments, inherits = FALSE), declared))
    assign(key, declared, assignments)
    return(TRUE)
  }
  if (declared$kind == "variable" || inferred$kind != declared$kind) return(FALSE)
  all(vapply(seq_along(inferred$children), function(index) signature_matches(inferred$children[[index]], declared$children[[index]], assignments), logical(1L)))
}
check_signatures <- function(group, signatures) {
  for (index in seq_along(group$bindings)) {
    binding <- group$bindings[[index]]
    signature <- signatures[[index]]
    if (is.null(signature)) next
    declared <- signature_type(signature[[2L]], new.env(hash = TRUE, parent = emptyenv()))
    inferred <- binding$scheme$value
    if (!signature_matches(inferred, declared, new.env(hash = TRUE, parent = emptyenv()))) inference_error("signature", binding$position, name = binding$name, inferred = inferred, declared = declared)
    binding$scheme <- new_scheme(declared, free_variables(declared))
  }
}
edit_distance <- function(first, second) {
  previous <- seq.int(0L, nchar(second))
  left <- strsplit(first, "", fixed = TRUE)[[1L]]
  right <- strsplit(second, "", fixed = TRUE)[[1L]]
  for (row in seq_along(left)) {
    current <- row
    for (column in seq_along(right)) current <- c(current, min(tail(current, 1L) + 1L, previous[[column + 1L]] + 1L, previous[[column]] + as.integer(left[[row]] != right[[column]])))
    previous <- current
  }
  tail(previous, 1L)
}
name_candidate <- function(name, candidates) {
  if (!length(candidates)) return(NULL)
  distances <- vapply(candidates, function(candidate) edit_distance(name, candidate), integer(1L))
  eligible <- which(distances <= 2L & distances < nchar(name))
  if (!length(eligible)) return(NULL)
  choices <- eligible[order(distances[eligible], candidates[eligible], method = "radix")]
  candidates[[choices[[1L]]]]
}
type_error_message <- function(error) {
  details <- error$details
  printer <- new_type_printer()
  if (error$kind == "unbound") {
    message <- paste0("unbound variable '", details$name, "'")
    candidate <- name_candidate(details$name, details$candidates)
    return(if (is.null(candidate)) message else paste0(message, " (did you mean '", candidate, "'?)"))
  }
  if (error$kind == "not_function") return(paste0("expected a function but found ", print_type(printer, details$found)))
  if (error$kind == "check") {
    expected <- print_type(printer, details$expected)
    found <- print_type(printer, details$found)
    message <- paste0("expected ", expected, " but found ", found)
    failure <- details$failure
    if (failure$infinite) {
      variable <- failure$expected
      value <- failure$found
      if (variable$kind != "variable") {
        variable <- failure$found
        value <- failure$expected
      }
      first <- print_type(printer, variable)
      second <- print_type(printer, value)
      message <- paste0(message, " (infinite type ", first, " = ", second, ")")
    } else if (failure$nested) {
      first <- print_type(printer, failure$expected)
      second <- print_type(printer, failure$found)
      message <- paste0(message, " (", first, " vs ", second, ")")
    }
    return(message)
  }
  if (error$kind == "duplicate_pattern") return(paste0("variable '", details$name, "' is bound twice in this pattern"))
  if (error$kind == "duplicate_let") return(paste0("variable '", details$name, "' is bound twice in this let"))
  if (error$kind == "recursive_function") return(paste0("'", details$name, "' in let rec must be a function"))
  inferred <- print_type(printer, details$inferred)
  declared <- print_type(printer, details$declared)
  paste0("'", details$name, "' has type ", inferred, " but its signature is ", declared)
}
built_in_environments <- function() {
  first <- new_type_variable()
  second <- new_type_variable()
  fst <- new_scheme(ml_type("function", ml_type("pair", first, second), first), c(first$id, second$id))
  first <- new_type_variable()
  second <- new_type_variable()
  snd <- new_scheme(ml_type("function", ml_type("pair", first, second), second), c(first$id, second$id))
  result <- new_type_variable()
  types <- list(fst = fst, snd = snd, not = new_scheme(ml_type("function", BOOL, BOOL)),
                string_of_int = new_scheme(ml_type("function", INT, STRING)),
                failwith = new_scheme(ml_type("function", STRING, result), result$id))
  values <- list(fst = new_builtin(function(value, position) value[[1L]]),
                 snd = new_builtin(function(value, position) value[[2L]]),
                 not = new_builtin(function(value, position) !value),
                 string_of_int = new_builtin(function(value, position) sprintf("%.0f", value)),
                 failwith = new_builtin(function(value, position) runtime_failure(position, paste("failure", print_value(value)))))
  list(types = types, values = list2env(values, parent = emptyenv()))
}
leading_parameters <- function(expression) {
  parameters <- character()
  while (expression$kind == "fun") {
    parameters <- c(parameters, expression$value$spelling)
    expression <- expression$children[[1L]]
  }
  list(parameters = parameters, body = expression)
}
format_binding <- function(binding) {
  leading <- leading_parameters(binding$expression)
  paste(c(binding$name, leading$parameters, "=", format_expression(leading$body)), collapse = " ")
}
format_group <- function(group) paste0(if (is.null(group$rec_position)) "let " else "let rec ", paste(vapply(group$bindings, format_binding, character(1L)), collapse = " and "))
ends_with_match <- function(expression) {
  if (expression$kind == "match") return(TRUE)
  if (expression$kind %in% c("let", "fun")) return(ends_with_match(expression$children[[1L]]))
  if (expression$kind == "if") return(ends_with_match(expression$children[[3L]]))
  FALSE
}
format_pattern <- function(pattern) {
  kind <- pattern$kind
  if (kind %in% c("wildcard", "name")) return(pattern$value)
  if (kind %in% c("integer", "boolean", "string")) return(print_value(pattern$value))
  if (kind == "list") return(paste0("[", paste(vapply(pattern$children, format_pattern, character(1L)), collapse = "; "), "]"))
  first <- pattern$children[[1L]]
  left <- format_pattern(first)
  right <- format_pattern(pattern$children[[2L]])
  if (kind == "pair") return(paste0("(", left, ", ", right, ")"))
  if (first$kind == "cons") left <- paste0("(", left, ")")
  paste(left, "::", right)
}
format_expression <- function(expression, minimum = 0L) {
  kind <- expression$kind
  children <- expression$children
  strength <- 9L
  if (kind %in% c("integer", "boolean", "string")) {
    text <- print_value(expression$value)
  } else if (kind == "name") {
    text <- expression$value
  } else if (kind == "fun") {
    strength <- 0L
    leading <- leading_parameters(expression)
    text <- paste0("fun ", paste(leading$parameters, collapse = " "), " -> ", format_expression(leading$body))
  } else if (kind == "apply") {
    strength <- 8L
    text <- paste(format_expression(children[[1L]], 8L), format_expression(children[[2L]], 9L))
  } else if (kind == "binary") {
    operator <- expression$value$spelling
    entry <- OPERATORS[[operator]]
    strength <- entry[[1L]]
    right_associative <- as.logical(entry[[2L]])
    text <- paste(format_expression(children[[1L]], strength + as.integer(right_associative)), operator, format_expression(children[[2L]], strength + as.integer(!right_associative)))
  } else if (kind == "negate") {
    strength <- 7L
    text <- paste0("-", format_expression(children[[1L]], 7L))
  } else if (kind == "if") {
    strength <- 0L
    text <- paste0("if ", format_expression(children[[1L]]), " then ", format_expression(children[[2L]]), " else ", format_expression(children[[3L]]))
  } else if (kind == "pair") {
    text <- paste0("(", format_expression(children[[1L]]), ", ", format_expression(children[[2L]]), ")")
  } else if (kind == "list") {
    text <- paste0("[", paste(vapply(children, format_expression, character(1L)), collapse = "; "), "]")
  } else if (kind == "let") {
    strength <- 0L
    text <- paste0(format_group(expression$value), " in ", format_expression(children[[1L]]))
  } else {
    strength <- 0L
    arms <- character()
    for (index in seq_along(expression$value)) {
      arm <- expression$value[[index]]
      body <- format_expression(arm[[2L]])
      if (index < length(expression$value) && ends_with_match(arm[[2L]])) body <- paste0("(", body, ")")
      arms <- c(arms, paste(format_pattern(arm[[1L]]), "->", body))
    }
    text <- paste0("match ", format_expression(children[[1L]]), " with ", paste(arms, collapse = " | "))
  }
  if (strength < minimum) paste0("(", text, ")") else text
}
format_item <- function(item) {
  if (item$kind == "signature") return(paste0("val ", item$value[[1L]]$spelling, " : ", format_declared_type(item$value[[2L]]), ";;"))
  paste0(if (item$kind == "declaration") format_group(item$value) else format_expression(item$value), ";;")
}
coverage_type <- function(value) {
  value <- resolve_type(value)
  if (value$kind %in% c("variable", "function")) return(list(kind = "opaque", children = list()))
  list(kind = value$kind, children = lapply(value$children, coverage_type))
}
coverage_pattern <- function(pattern) {
  if (pattern$kind %in% c("wildcard", "name")) return(NULL)
  if (pattern$kind %in% c("integer", "boolean", "string")) return(list(constructor = list(pattern$kind, pattern$value), arguments = list()))
  if (pattern$kind == "list") {
    result <- list(constructor = list("nil"), arguments = list())
    for (child in rev(pattern$children)) result <- list(constructor = list("cons"), arguments = list(coverage_pattern(child), result))
    return(result)
  }
  list(constructor = list(if (pattern$kind == "pair") "pair" else "cons"), arguments = lapply(pattern$children, coverage_pattern))
}
constructors <- function(value_type) {
  switch(value_type$kind, bool = list(list("boolean", FALSE), list("boolean", TRUE)),
         list = list(list("nil"), list("cons")), pair = list(list("pair")), list())
}
constructor_arguments <- function(constructor, value_type) {
  if (identical(constructor, list("pair"))) return(value_type$children)
  if (identical(constructor, list("cons"))) return(list(value_type$children[[1L]], value_type))
  list()
}
specialize <- function(matrix, constructor, arity) {
  rows <- list()
  for (row in matrix) {
    if (is.null(row[[1L]])) {
      rows[[length(rows) + 1L]] <- c(rep(list(NULL), arity), tail(row, -1L))
    } else if (identical(row[[1L]]$constructor, constructor)) {
      rows[[length(rows) + 1L]] <- c(row[[1L]]$arguments, tail(row, -1L))
    }
  }
  rows
}
useful_pattern <- function(matrix, query, types, cache) {
  bytes <- serialize(list(matrix, query, types), NULL)
  hash <- 0
  for (byte in as.integer(bytes)) hash <- (hash * 257 + byte) %% 2147483647
  key <- sprintf("%.0f", hash)
  if (exists(key, cache, inherits = FALSE)) {
    for (entry in get(key, cache, inherits = FALSE)) if (identical(entry$bytes, bytes)) return(entry$result)
  }
  compute <- function() {
    if (!length(query)) return(!length(matrix))
    if (!length(matrix)) return(TRUE)
    head <- query[[1L]]
    if (!is.null(head)) {
      argument_types <- constructor_arguments(head$constructor, types[[1L]])
      return(useful_pattern(specialize(matrix, head$constructor, length(head$arguments)), c(head$arguments, tail(query, -1L)), c(argument_types, tail(types, -1L)), cache))
    }
    possible <- constructors(types[[1L]])
    present <- lapply(Filter(function(row) !is.null(row[[1L]]), matrix), function(row) row[[1L]]$constructor)
    complete <- length(possible) > 0L && all(vapply(possible, function(constructor) any(vapply(present, identical, logical(1L), y = constructor)), logical(1L)))
    if (complete) {
      for (constructor in possible) {
        argument_types <- constructor_arguments(constructor, types[[1L]])
        selected <- specialize(matrix, constructor, length(argument_types))
        arguments <- rep(list(NULL), length(argument_types))
        if (useful_pattern(selected, c(arguments, tail(query, -1L)), c(argument_types, tail(types, -1L)), cache)) return(TRUE)
      }
      return(FALSE)
    }
    defaults <- lapply(Filter(function(row) is.null(row[[1L]]), matrix), function(row) tail(row, -1L))
    useful_pattern(defaults, tail(query, -1L), tail(types, -1L), cache)
  }
  result <- compute()
  bucket <- if (exists(key, cache, inherits = FALSE)) get(key, cache, inherits = FALSE) else list()
  bucket[[length(bucket) + 1L]] <- list(bytes = bytes, result = result)
  assign(key, bucket, cache)
  result
}
expression_nodes <- function(expression) {
  nodes <- list(expression)
  if (expression$kind == "let") for (binding in expression$value$bindings) nodes <- c(nodes, expression_nodes(binding$expression))
  for (child in expression$children) nodes <- c(nodes, expression_nodes(child))
  if (expression$kind == "match") for (arm in expression$value) nodes <- c(nodes, expression_nodes(arm[[2L]]))
  nodes
}
reference_id <- function(references, node) {
  key <- as.character(node$id)
  if (exists(key, references, inherits = FALSE)) get(key, references, inherits = FALSE) else 0L
}
recursion_classification <- function(expression, targets, references) {
  body <- leading_parameters(expression)$body
  calls <- logical()
  visit <- function(node, tail_position) {
    kind <- node$kind
    children <- node$children
    if (kind == "name") {
      if (reference_id(references, node) %in% targets) calls <<- c(calls, FALSE)
      return(invisible(NULL))
    }
    if (kind == "apply") {
      arguments <- list()
      function_node <- node
      while (function_node$kind == "apply") {
        arguments[[length(arguments) + 1L]] <- function_node$children[[2L]]
        function_node <- function_node$children[[1L]]
      }
      if (function_node$kind == "name" && reference_id(references, function_node) %in% targets) calls <<- c(calls, tail_position) else visit(function_node, FALSE)
      for (argument in rev(arguments)) visit(argument, FALSE)
      return(invisible(NULL))
    }
    if (kind == "if") {
      visit(children[[1L]], FALSE)
      visit(children[[2L]], tail_position)
      visit(children[[3L]], tail_position)
    } else if (kind == "match") {
      visit(children[[1L]], FALSE)
      for (arm in node$value) visit(arm[[2L]], tail_position)
    } else if (kind == "let") {
      for (binding in node$value$bindings) visit(binding$expression, FALSE)
      visit(children[[1L]], tail_position)
    } else if (kind == "binary" && node$value$spelling %in% c("&&", "||")) {
      visit(children[[1L]], FALSE)
      visit(children[[2L]], tail_position)
    } else {
      for (child in children) visit(child, FALSE)
    }
  }
  visit(body, TRUE)
  if (!length(calls)) "" else if (all(calls)) "tail recursive" else "recursive"
}
new_static_checks <- function() {
  new_record(symbols = list(), references = new.env(hash = TRUE, parent = emptyenv()),
             groups = list(), warnings = list())
}
new_symbol <- function(checks, name, position, top_level = FALSE) {
  symbol <- new_record(name = name, position = position, top_level = top_level,
                       used = FALSE, id = length(checks$symbols) + 1L)
  checks$symbols[[length(checks$symbols) + 1L]] <- symbol
  symbol
}
add_warning <- function(checks, position, priority, message) {
  checks$warnings[[length(checks$warnings) + 1L]] <- list(position = position, priority = priority, message = message)
}
bind_pattern <- function(checks, pattern, environment) {
  if (pattern$kind == "name") environment[[pattern$value]] <- new_symbol(checks, pattern$value, pattern$position)
  for (child in pattern$children) environment <- bind_pattern(checks, child, environment)
  environment
}
check_group <- function(checks, group, environment, top_level = FALSE) {
  symbols <- lapply(group$bindings, function(binding) new_symbol(checks, binding$name, binding$position, top_level))
  checks$groups[[length(checks$groups) + 1L]] <- list(group = group, targets = vapply(symbols, function(symbol) symbol$id, integer(1L)))
  inner <- environment
  for (symbol in symbols) inner[[symbol$name]] <- symbol
  right_environment <- if (is.null(group$rec_position)) environment else inner
  for (binding in group$bindings) check_expression(checks, binding$expression, right_environment)
  inner
}
match_warnings <- function(checks, expression) {
  cache <- new.env(hash = TRUE, parent = emptyenv())
  matrix <- list()
  matched_type <- list(coverage_type(expression$children[[1L]]$inferred))
  for (index in seq_along(expression$value)) {
    pattern <- expression$value[[index]][[1L]]
    query <- list(coverage_pattern(pattern))
    if (index > 1L && !useful_pattern(matrix, query, matched_type, cache)) add_warning(checks, pattern$position, 2L, "this match case is unused")
    matrix[[length(matrix) + 1L]] <- query
  }
  if (useful_pattern(matrix, list(NULL), matched_type, cache)) add_warning(checks, expression$position, 1L, "this match is not exhaustive")
}
check_expression <- function(checks, expression, environment) {
  kind <- expression$kind
  if (kind == "name") {
    symbol <- environment[[expression$value]]
    assign(as.character(expression$id), if (is.null(symbol)) 0L else symbol$id, checks$references)
    if (!is.null(symbol)) symbol$used <- TRUE
  } else if (kind == "fun") {
    inner <- environment
    parameter <- expression$value
    if (parameter$spelling != "_") inner[[parameter$spelling]] <- new_symbol(checks, parameter$spelling, parameter$position)
    check_expression(checks, expression$children[[1L]], inner)
  } else if (kind == "let") {
    inner <- check_group(checks, expression$value, environment)
    check_expression(checks, expression$children[[1L]], inner)
  } else if (kind == "match") {
    check_expression(checks, expression$children[[1L]], environment)
    match_warnings(checks, expression)
    for (arm in expression$value) {
      inner <- bind_pattern(checks, arm[[1L]], environment)
      check_expression(checks, arm[[2L]], inner)
    }
  } else {
    for (child in expression$children) check_expression(checks, child, environment)
  }
}
check_item <- function(item, environment_names) {
  checks <- new_static_checks()
  environment <- setNames(rep(list(NULL), length(environment_names)), environment_names)
  if (item$kind == "declaration") check_group(checks, item$value, environment, TRUE) else check_expression(checks, item$value, environment)
  for (entry in checks$groups) {
    group <- entry$group
    targets <- entry$targets
    if (is.null(group$rec_position)) next
    referenced <- FALSE
    for (binding in group$bindings) for (node in expression_nodes(binding$expression)) if (reference_id(checks$references, node) %in% targets) referenced <- TRUE
    if (!referenced) add_warning(checks, group$rec_position, 3L, "unused rec flag")
    for (binding in group$bindings) binding$classification <- recursion_classification(binding$expression, targets, checks$references)
  }
  for (symbol in checks$symbols) if (!symbol$top_level && !symbol$used && !startsWith(symbol$name, "_")) add_warning(checks, symbol$position, 4L, paste0("unused variable '", symbol$name, "'"))
  if (!length(checks$warnings)) return(list())
  ordering <- order(vapply(checks$warnings, function(warning) warning$position$line, integer(1L)),
                    vapply(checks$warnings, function(warning) warning$position$column, integer(1L)),
                    vapply(checks$warnings, function(warning) warning$priority, integer(1L)), method = "radix")
  checks$warnings[ordering]
}
classification_suffix <- function(binding) if (nzchar(binding$classification)) paste0(" (", binding$classification, ")") else ""
syntax_error_message <- function(token) {
  if (token$kind == "invalid") return(token$value)
  if (token$kind == "EOF") return("unexpected end of file")
  paste0("unexpected '", token$spelling, "'")
}
FILE_NAMES <- c("prelude.ml", "program.ml")
COUNTER_NAMES <- c("items", "bindings", "syntax", "type", "runtime", "warnings", "calls")
report <- function(runner, kind, position, message) {
  filename <- position$filename
  line <- position$line
  column <- position$column
  counter <- if (kind == "warning") "warnings" else strsplit(kind, " ", fixed = TRUE)[[1L]][[1L]]
  counts <- runner$statistics[[runner$current_file]]
  counts[[counter]] <- counts[[counter]] + 1L
  runner$reports <- c(runner$reports, sprintf("%s:%d:%d: %s: %s", filename, line, column, kind, message))
  source_lines <- runner$sources[[filename]]
  if (line <= length(source_lines)) runner$reports <- c(runner$reports, paste0("    ", source_lines[[line]]), paste0(strrep(" ", column + 3L), "^"))
}
unused_signature <- function(runner, signature) {
  name <- signature[[1L]]
  report(runner, "warning", name$position, paste0("signature for '", name$spelling, "' is never used"))
}
write_types <- function(runner, item, inferred, local_bindings) {
  if (item$kind == "declaration") {
    for (binding in item$value$bindings) runner$types <- c(runner$types, paste0(binding$name, " : ", print_type(new_type_printer(), binding$scheme$value), classification_suffix(binding)))
  } else {
    runner$types <- c(runner$types, paste0("- : ", print_type(new_type_printer(), inferred)))
  }
  if (length(local_bindings)) {
    ordering <- order(vapply(local_bindings, function(binding) binding$position$line, integer(1L)), vapply(local_bindings, function(binding) binding$position$column, integer(1L)), method = "radix")
    for (binding in local_bindings[ordering]) {
      position <- binding$position
      text <- paste0("  ", binding$name, " (", position$line, ":", position$column, ") : ", print_type(new_type_printer(binding$scheme$quantified), binding$scheme$value))
      runner$types <- c(runner$types, paste0(text, classification_suffix(binding)))
    }
  }
}
process_item <- function(runner, item, pending, evaluator, counts) {
  runner$formatted <- c(runner$formatted, format_item(item))
  if (item$kind == "signature") {
    name <- item$value[[1L]]$spelling
    if (exists(name, pending, inherits = FALSE)) unused_signature(runner, get(name, pending, inherits = FALSE))
    assign(name, item$value, pending)
    return(invisible(NULL))
  }
  signatures <- list()
  if (item$kind == "declaration") for (binding in item$value$bindings) {
    signature <- NULL
    if (exists(binding$name, pending, inherits = FALSE)) {
      signature <- get(binding$name, pending, inherits = FALSE)
      rm(list = binding$name, envir = pending)
    }
    signatures[length(signatures) + 1L] <- list(signature)
  }
  inferencer <- new_inferencer()
  inference <- tryCatch({
    if (item$kind == "declaration") {
      infer_group(inferencer, item$value, runner$type_environment)
      check_signatures(item$value, signatures)
      NULL
    } else {
      infer_expression(inferencer, item$value, runner$type_environment)
    }
  }, inference_error = function(error) error)
  if (inherits(inference, "inference_error")) {
    report(runner, "type error", inference$position, type_error_message(inference))
    return(invisible(NULL))
  }
  warnings <- check_item(item, names(runner$type_environment))
  write_types(runner, item, inference, inferencer$local_bindings)
  for (warning in warnings) report(runner, "warning", warning$position, warning$message)
  evaluated <- tryCatch({
    if (item$kind == "declaration") {
      environment <- evaluate_group(evaluator, item$value, runner$value_environment)
      list(environment = environment, values = lapply(item$value$bindings, function(binding) get(binding$name, environment, inherits = FALSE)))
    } else {
      list(value = evaluate(evaluator, item$value, runner$value_environment))
    }
  }, runtime_failure = function(error) error)
  if (inherits(evaluated, "runtime_failure")) {
    report(runner, "runtime error", evaluated$position, evaluated$message)
    return(invisible(NULL))
  }
  if (item$kind == "declaration") {
    types <- runner$type_environment
    for (index in seq_along(item$value$bindings)) {
      binding <- item$value$bindings[[index]]
      runner$values <- c(runner$values, paste0(binding$name, " = ", print_value(evaluated$values[[index]])))
      types[[binding$name]] <- binding$scheme
    }
    runner$type_environment <- types
    runner$value_environment <- evaluated$environment
    counts$bindings <- counts$bindings + length(item$value$bindings)
  } else {
    runner$values <- c(runner$values, paste0("- = ", print_value(evaluated$value)))
  }
}
process_file <- function(runner, filename, source) {
  runner$current_file <- filename
  counts <- runner$statistics[[filename]]
  runner$types <- c(runner$types, paste0("== ", filename, " =="))
  runner$values <- c(runner$values, paste0("== ", filename, " =="))
  runner$formatted <- c(runner$formatted, paste0("(* ", filename, " *)"))
  pending <- new.env(hash = TRUE, parent = emptyenv())
  evaluator <- new_evaluator()
  parser <- new_parser(tokenize(source, filename))
  while (next_token(parser)$kind != "EOF") {
    counts$items <- counts$items + 1L
    item <- tryCatch(parse_item(parser), syntax_failure = function(error) error)
    if (inherits(item, "syntax_failure")) {
      report(runner, "syntax error", item$token$position, syntax_error_message(item$token))
      recover(parser)
    } else {
      process_item(runner, item, pending, evaluator, counts)
    }
  }
  signatures <- as.list.environment(pending, all.names = TRUE)
  if (length(signatures)) {
    ordering <- order(vapply(signatures, function(signature) signature[[1L]]$position$line, integer(1L)), vapply(signatures, function(signature) signature[[1L]]$position$column, integer(1L)), method = "radix")
    for (signature in signatures[ordering]) unused_signature(runner, signature)
  }
  counts$calls <- evaluator$calls
}
main <- function() {
  sources <- setNames(lapply(FILE_NAMES, function(filename) readLines(file.path("input", filename), warn = FALSE)), FILE_NAMES)
  raw_sources <- lapply(sources, function(lines) if (length(lines)) paste0(paste(lines, collapse = "\n"), "\n") else "")
  builtins <- built_in_environments()
  statistics <- setNames(lapply(FILE_NAMES, function(filename) list2env(setNames(as.list(rep(0L, length(COUNTER_NAMES))), COUNTER_NAMES), parent = emptyenv())), FILE_NAMES)
  runner <- new_record(sources = sources, type_environment = builtins$types,
                       value_environment = builtins$values, current_file = "", statistics = statistics,
                       reports = character(), types = character(), values = character(), formatted = character())
  for (filename in FILE_NAMES) process_file(runner, filename, raw_sources[[filename]])
  runner$reports <- c(runner$reports, "== summary ==")
  for (filename in FILE_NAMES) {
    counts <- runner$statistics[[filename]]
    summary <- paste(vapply(COUNTER_NAMES, function(name) paste0(name, "=", counts[[name]]), character(1L)), collapse = " ")
    runner$reports <- c(runner$reports, paste0(filename, ": ", summary))
  }
  dir.create("output", showWarnings = FALSE)
  outputs <- list("types.txt" = runner$types, "values.txt" = runner$values,
                  "errors.txt" = runner$reports, "formatted.ml" = runner$formatted)
  for (filename in names(outputs)) {
    connection <- file(file.path("output", filename), open = "wb")
    writeChar(paste0(paste(outputs[[filename]], collapse = "\n"), "\n"), connection, eos = NULL, useBytes = TRUE)
    close(connection)
  }
}
main()
