TYPE_IDS <- new.env(parent = emptyenv())
TYPE_IDS$next_id <- 0L
new_type_variable <- function() {
  TYPE_IDS$next_id <- TYPE_IDS$next_id + 1L
  new_record(kind = "variable", id = TYPE_IDS$next_id, binding = NULL)
}
ml_type <- function(kind, ...) new_record(kind = kind, children = list(...))
new_scheme <- function(value, quantified = integer()) list(value = value, quantified = quantified)
INT <- ml_type("int")
BOOL <- ml_type("bool")
STRING <- ml_type("string")
resolve_type <- function(value) {
  path <- list()
  while (value$kind == "variable" && !is.null(value$binding)) {
    path[[length(path) + 1L]] <- value
    value <- value$binding
  }
  for (variable in path) variable$binding <- value
  value
}
occurs <- function(variable, value) {
  value <- resolve_type(value)
  if (value$kind == "variable") return(identical(variable, value))
  any(vapply(value$children, function(child) occurs(variable, child), logical(1L)))
}
unification_failure <- function(expected, found, infinite, nested) {
  stop(structure(list(message = "unification failure", expected = expected, found = found,
                      infinite = infinite, nested = nested), class = c("unification_failure", "error", "condition")))
}
unify <- function(expected, found, nested = FALSE) {
  expected <- resolve_type(expected)
  found <- resolve_type(found)
  if (identical(expected, found)) return(invisible(NULL))
  if (expected$kind == "variable") {
    if (occurs(expected, found)) unification_failure(expected, found, TRUE, nested)
    expected$binding <- found
  } else if (found$kind == "variable") {
    if (occurs(found, expected)) unification_failure(expected, found, TRUE, nested)
    found$binding <- expected
  } else {
    if (expected$kind != found$kind) unification_failure(expected, found, FALSE, nested)
    for (index in seq_along(expected$children)) unify(expected$children[[index]], found$children[[index]], TRUE)
  }
  invisible(NULL)
}
free_variables <- function(value) {
  value <- resolve_type(value)
  if (value$kind == "variable") return(value$id)
  unique(unlist(lapply(value$children, free_variables), use.names = FALSE))
}
generalize <- function(value, environment) {
  free_in_environment <- integer()
  for (scheme in environment) free_in_environment <- union(free_in_environment, setdiff(free_variables(scheme$value), scheme$quantified))
  new_scheme(value, setdiff(free_variables(value), free_in_environment))
}
instantiate <- function(scheme) {
  replacements <- new.env(hash = TRUE, parent = emptyenv())
  copy_type <- function(value) {
    value <- resolve_type(value)
    if (value$kind == "variable") {
      if (!value$id %in% scheme$quantified) return(value)
      key <- as.character(value$id)
      if (!exists(key, replacements, inherits = FALSE)) assign(key, new_type_variable(), replacements)
      return(get(key, replacements, inherits = FALSE))
    }
    do.call(ml_type, c(list(value$kind), lapply(value$children, copy_type)))
  }
  copy_type(scheme$value)
}
