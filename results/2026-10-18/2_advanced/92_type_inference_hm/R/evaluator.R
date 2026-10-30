new_closure <- function(parameter, body, environment) structure(list(parameter = parameter, body = body, environment = environment), class = "ml_closure")
new_builtin <- function(behavior) structure(list(behavior = behavior), class = "ml_builtin")
copy_value_environment <- function(environment) list2env(as.list.environment(environment, all.names = TRUE), parent = emptyenv())
runtime_failure <- function(position, message) stop(structure(list(position = position, message = message), class = c("runtime_failure", "error", "condition")))
checked_integer <- function(value, position) {
  if (value < -2147483648 || value > 2147483647) runtime_failure(position, "integer overflow")
  value
}
compare_strings <- function(first, second) {
  left <- utf8ToInt(first)
  right <- utf8ToInt(second)
  for (index in seq_len(min(length(left), length(right)))) {
    if (left[[index]] != right[[index]]) return(sign(left[[index]] - right[[index]]))
  }
  sign(length(left) - length(right))
}
compare_values <- function(first, second, position) {
  if (inherits(first, c("ml_closure", "ml_builtin"))) runtime_failure(position, "functional value compared")
  if (is.list(first)) {
    for (index in seq_len(min(length(first), length(second)))) {
      order <- compare_values(first[[index]], second[[index]], position)
      if (order != 0L) return(order)
    }
    return(sign(length(first) - length(second)))
  }
  if (is.character(first)) return(compare_strings(first, second))
  as.integer(first > second) - as.integer(first < second)
}
binary_operation <- function(operator, first, second, position) {
  first <- force(first)
  second <- force(second)
  if (operator == "+") return(checked_integer(first + second, position))
  if (operator == "-") return(checked_integer(first - second, position))
  if (operator == "*") return(checked_integer(first * second, position))
  if (operator %in% c("/", "mod")) {
    if (second == 0) runtime_failure(position, "division by zero")
    quotient <- trunc(first / second)
    return(if (operator == "/") checked_integer(quotient, position) else first - second * quotient)
  }
  if (operator == "^") return(paste0(first, second))
  if (operator == "::") return(c(list(first), second))
  order <- compare_values(first, second, position)
  switch(operator, "=" = order == 0L, "<>" = order != 0L, "<" = order < 0L,
         ">" = order > 0L, "<=" = order <= 0L, ">=" = order >= 0L)
}
match_pattern <- function(pattern, value, bindings) {
  kind <- pattern$kind
  if (kind == "wildcard") return(TRUE)
  if (kind == "name") {
    assign(pattern$value, value, bindings)
    return(TRUE)
  }
  if (kind %in% c("integer", "boolean", "string")) return(pattern$value == value)
  if (kind == "cons") return(length(value) > 0L && match_pattern(pattern$children[[1L]], value[[1L]], bindings) && match_pattern(pattern$children[[2L]], value[-1L], bindings))
  if (kind == "list" && length(value) != length(pattern$children)) return(FALSE)
  for (index in seq_along(pattern$children)) if (!match_pattern(pattern$children[[index]], value[[index]], bindings)) return(FALSE)
  TRUE
}
new_evaluator <- function() new_record(calls = 0L)
evaluate <- function(evaluator, expression, environment) {
  kind <- expression$kind
  children <- expression$children
  if (kind %in% c("integer", "boolean", "string")) return(expression$value)
  if (kind == "name") return(get(expression$value, environment, inherits = FALSE))
  if (kind == "fun") return(new_closure(expression$value$spelling, children[[1L]], copy_value_environment(environment)))
  if (kind == "apply") {
    function_value <- evaluate(evaluator, children[[1L]], environment)
    argument <- evaluate(evaluator, children[[2L]], environment)
    evaluator$calls <- evaluator$calls + 1L
    if (inherits(function_value, "ml_builtin")) return(function_value$behavior(argument, expression$position))
    inner <- copy_value_environment(function_value$environment)
    if (function_value$parameter != "_") assign(function_value$parameter, argument, inner)
    return(evaluate(evaluator, function_value$body, inner))
  }
  if (kind == "binary") {
    first <- evaluate(evaluator, children[[1L]], environment)
    operator <- expression$value$spelling
    if (operator == "&&") return(if (first) evaluate(evaluator, children[[2L]], environment) else FALSE)
    if (operator == "||") return(if (first) TRUE else evaluate(evaluator, children[[2L]], environment))
    second <- evaluate(evaluator, children[[2L]], environment)
    return(binary_operation(operator, first, second, expression$value$position))
  }
  if (kind == "negate") return(checked_integer(-evaluate(evaluator, children[[1L]], environment), expression$value$position))
  if (kind == "if") {
    selected <- if (evaluate(evaluator, children[[1L]], environment)) children[[2L]] else children[[3L]]
    return(evaluate(evaluator, selected, environment))
  }
  if (kind == "pair") {
    first <- evaluate(evaluator, children[[1L]], environment)
    second <- evaluate(evaluator, children[[2L]], environment)
    return(structure(list(first, second), class = "ml_pair"))
  }
  if (kind == "list") return(lapply(children, function(child) evaluate(evaluator, child, environment)))
  if (kind == "match") {
    value <- evaluate(evaluator, children[[1L]], environment)
    for (arm in expression$value) {
      bindings <- new.env(hash = TRUE, parent = emptyenv())
      if (match_pattern(arm[[1L]], value, bindings)) {
        inner <- copy_value_environment(environment)
        for (name in ls(bindings, all.names = TRUE)) assign(name, get(name, bindings, inherits = FALSE), inner)
        return(evaluate(evaluator, arm[[2L]], inner))
      }
    }
    runtime_failure(expression$position, "match failure")
  }
  inner <- evaluate_group(evaluator, expression$value, environment)
  evaluate(evaluator, children[[1L]], inner)
}
evaluate_group <- function(evaluator, group, environment) {
  result <- copy_value_environment(environment)
  if (!is.null(group$rec_position)) {
    for (binding in group$bindings) {
      expression <- binding$expression
      assign(binding$name, new_closure(expression$value$spelling, expression$children[[1L]], result), result)
    }
  } else {
    values <- lapply(group$bindings, function(binding) evaluate(evaluator, binding$expression, environment))
    for (index in seq_along(group$bindings)) assign(group$bindings[[index]]$name, values[[index]], result)
  }
  result
}
