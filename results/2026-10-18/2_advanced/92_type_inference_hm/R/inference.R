inference_error <- function(kind, position, ...) {
  stop(structure(list(message = "type inference error", kind = kind, position = position,
                      details = list(...)), class = c("inference_error", "error", "condition")))
}
new_inferencer <- function() new_record(local_bindings = list())
check_type <- function(expected, found, position) {
  found <- force(found)
  expected <- force(expected)
  tryCatch(unify(expected, found), unification_failure = function(failure) inference_error("check", position, expected = expected, found = found, failure = failure))
}
operator_types <- function(operator) {
  if (operator %in% c("+", "-", "*", "/", "mod")) return(list(INT, INT, INT))
  if (operator == "^") return(list(STRING, STRING, STRING))
  if (operator %in% c("&&", "||")) return(list(BOOL, BOOL, BOOL))
  variable <- new_type_variable()
  if (operator == "::") {
    sequence <- ml_type("list", variable)
    return(list(variable, sequence, sequence))
  }
  list(variable, variable, BOOL)
}
infer_expression <- function(inferencer, expression, environment) {
  kind <- expression$kind
  children <- expression$children
  if (kind %in% c("integer", "boolean", "string")) {
    result <- switch(kind, integer = INT, boolean = BOOL, string = STRING)
  } else if (kind == "name") {
    scheme <- environment[[expression$value]]
    if (is.null(scheme)) inference_error("unbound", expression$position, name = expression$value, candidates = names(environment))
    result <- instantiate(scheme)
  } else if (kind == "fun") {
    argument <- new_type_variable()
    inner <- environment
    if (expression$value$spelling != "_") inner[[expression$value$spelling]] <- new_scheme(argument)
    body <- infer_expression(inferencer, children[[1L]], inner)
    result <- ml_type("function", argument, body)
  } else if (kind == "apply") {
    function_type <- resolve_type(infer_expression(inferencer, children[[1L]], environment))
    if (function_type$kind == "variable") {
      argument <- new_type_variable()
      result <- new_type_variable()
      function_type$binding <- ml_type("function", argument, result)
    } else if (function_type$kind == "function") {
      argument <- function_type$children[[1L]]
      result <- function_type$children[[2L]]
    } else {
      inference_error("not_function", children[[1L]]$position, found = function_type)
    }
    found <- infer_expression(inferencer, children[[2L]], environment)
    check_type(argument, found, children[[2L]]$position)
  } else if (kind == "binary") {
    types <- operator_types(expression$value$spelling)
    check_type(types[[1L]], infer_expression(inferencer, children[[1L]], environment), children[[1L]]$position)
    check_type(types[[2L]], infer_expression(inferencer, children[[2L]], environment), children[[2L]]$position)
    result <- types[[3L]]
  } else if (kind == "negate") {
    check_type(INT, infer_expression(inferencer, children[[1L]], environment), children[[1L]]$position)
    result <- INT
  } else if (kind == "if") {
    check_type(BOOL, infer_expression(inferencer, children[[1L]], environment), children[[1L]]$position)
    result <- infer_expression(inferencer, children[[2L]], environment)
    found <- infer_expression(inferencer, children[[3L]], environment)
    check_type(result, found, children[[3L]]$position)
  } else if (kind == "pair") {
    first <- infer_expression(inferencer, children[[1L]], environment)
    second <- infer_expression(inferencer, children[[2L]], environment)
    result <- ml_type("pair", first, second)
  } else if (kind == "list") {
    element <- new_type_variable()
    for (child in children) check_type(element, infer_expression(inferencer, child, environment), child$position)
    result <- ml_type("list", element)
  } else if (kind == "match") {
    matched <- infer_expression(inferencer, children[[1L]], environment)
    result <- new_type_variable()
    for (arm in expression$value) {
      bindings <- new.env(hash = TRUE, parent = emptyenv())
      pattern_type <- infer_pattern(arm[[1L]], bindings)
      check_type(matched, pattern_type, arm[[1L]]$position)
      inner <- environment
      for (name in ls(bindings, all.names = TRUE)) inner[[name]] <- new_scheme(get(name, bindings, inherits = FALSE))
      check_type(result, infer_expression(inferencer, arm[[2L]], inner), arm[[2L]]$position)
    }
  } else {
    inner <- infer_group(inferencer, expression$value, environment, TRUE)
    result <- infer_expression(inferencer, children[[1L]], inner)
  }
  expression$inferred <- result
  result
}
infer_pattern <- function(pattern, bindings) {
  kind <- pattern$kind
  children <- pattern$children
  if (kind == "wildcard") return(new_type_variable())
  if (kind == "name") {
    if (exists(pattern$value, bindings, inherits = FALSE)) inference_error("duplicate_pattern", pattern$position, name = pattern$value)
    result <- new_type_variable()
    assign(pattern$value, result, bindings)
    return(result)
  }
  if (kind %in% c("integer", "boolean", "string")) return(switch(kind, integer = INT, boolean = BOOL, string = STRING))
  if (kind == "pair") {
    first <- infer_pattern(children[[1L]], bindings)
    second <- infer_pattern(children[[2L]], bindings)
    return(ml_type("pair", first, second))
  }
  element <- new_type_variable()
  sequence <- ml_type("list", element)
  if (kind == "cons") {
    check_type(element, infer_pattern(children[[1L]], bindings), children[[1L]]$position)
    check_type(sequence, infer_pattern(children[[2L]], bindings), children[[2L]]$position)
  } else {
    for (child in children) check_type(element, infer_pattern(child, bindings), child$position)
  }
  sequence
}
infer_group <- function(inferencer, group, environment, local_group = FALSE) {
  names <- character()
  for (binding in group$bindings) {
    if (binding$name %in% names) inference_error("duplicate_let", binding$position, name = binding$name)
    names <- c(names, binding$name)
    if (!is.null(group$rec_position) && binding$expression$kind != "fun") inference_error("recursive_function", binding$position, name = binding$name)
  }
  if (is.null(group$rec_position)) {
    inferred <- lapply(group$bindings, function(binding) infer_expression(inferencer, binding$expression, environment))
  } else {
    inferred <- lapply(group$bindings, function(binding) new_type_variable())
    recursive <- environment
    for (index in seq_along(group$bindings)) recursive[[group$bindings[[index]]$name]] <- new_scheme(inferred[[index]])
    for (index in seq_along(group$bindings)) {
      binding <- group$bindings[[index]]
      found <- infer_expression(inferencer, binding$expression, recursive)
      check_type(inferred[[index]], found, binding$position)
    }
  }
  result <- environment
  for (index in seq_along(group$bindings)) {
    binding <- group$bindings[[index]]
    binding$scheme <- generalize(inferred[[index]], environment)
    result[[binding$name]] <- binding$scheme
  }
  if (local_group) inferencer$local_bindings <- c(inferencer$local_bindings, group$bindings)
  result
}
