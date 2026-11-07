BUILTINS <- c("__LINE__", "__FILE__", "__COUNTER__")
VARIADIC_NAME <- "__VA_ARGS__"
VARIADIC_ERROR <- '"__VA_ARGS__" can only appear in the expansion of a variadic macro'
definition_error <- function(message) stop(structure(list(message = message), class = c("definition_error", "error", "condition")))
macro_get <- function(macros, name) {
  key <- paste0("m:", name)
  if (exists(key, macros, inherits = FALSE)) get(key, macros, inherits = FALSE) else NULL
}
macro_set <- function(macros, name, definition) assign(paste0("m:", name), definition, macros)
macro_remove <- function(macros, name) {
  key <- paste0("m:", name)
  if (exists(key, macros, inherits = FALSE)) rm(list = key, envir = macros)
}
macro_names <- function(macros) vapply(as.list.environment(macros, all.names = TRUE), function(definition) definition$name, character(1L))
signature <- function(definition) {
  if (is.null(definition$parameters)) return(definition$name)
  parameters <- definition$parameters
  if (definition$variadic) parameters[[length(parameters)]] <- "..."
  paste0(definition$name, "(", paste(parameters, collapse = ", "), ")")
}
identical_definition <- function(first, second) {
  identical(first$parameters, second$parameters) && identical(first$variadic, second$variadic) &&
    identical(lapply(first$replacement, function(token) list(token$spelling, token$space)),
              lapply(second$replacement, function(token) list(token$spelling, token$space)))
}
check_macro_name <- function(tokens, directive) {
  if (!length(tokens)) return(paste0("no macro name given in #", directive, " directive"))
  if (tokens[[1L]]$kind != "identifier") return("macro names must be identifiers")
  name <- tokens[[1L]]$spelling
  if (name == "defined") return('"defined" cannot be used as a macro name')
  if (name %in% BUILTINS) return(paste0("cannot ", if (directive == "define") "redefine" else "undefine", ' builtin macro "', name, '"'))
  NULL
}
parse_definition <- function(tokens, position, main_file) {
  error <- check_macro_name(tokens, "define")
  if (!is.null(error)) definition_error(error)
  name <- tokens[[1L]]$spelling
  if (name == VARIADIC_NAME) definition_error(VARIADIC_ERROR)
  parameters <- NULL
  variadic <- FALSE
  index <- 2L
  if (length(tokens) > 1L && tokens[[2L]]$spelling == "(" && !tokens[[2L]]$space) {
    parameters <- character()
    index <- 3L
    if (index > length(tokens)) definition_error("missing ')' in macro parameter list")
    if (tokens[[index]]$spelling == ")") {
      index <- index + 1L
    } else repeat {
      if (index > length(tokens)) definition_error("missing ')' in macro parameter list")
      token <- tokens[[index]]
      if (token$spelling == "...") {
        parameters <- c(parameters, VARIADIC_NAME)
        variadic <- TRUE
      } else if (token$kind == "identifier") {
        if (token$spelling == VARIADIC_NAME) definition_error(VARIADIC_ERROR)
        if (token$spelling %in% parameters) definition_error(paste0('duplicate macro parameter "', token$spelling, '"'))
        parameters <- c(parameters, token$spelling)
      } else {
        definition_error(paste0('expected parameter name, found "', token$spelling, '"'))
      }
      index <- index + 1L
      if (index > length(tokens)) definition_error("missing ')' in macro parameter list")
      following <- tokens[[index]]$spelling
      index <- index + 1L
      if (following == ")") break
      if (variadic) definition_error(paste0('expected \')\' after "...", found "', following, '"'))
      if (following != ",") definition_error(paste0('expected \',\' or \')\', found "', following, '"'))
    }
  }
  replacement <- if (index <= length(tokens)) tokens[seq.int(index, length(tokens))] else list()
  if (length(replacement)) {
    replacement[[1L]] <- token_with(replacement[[1L]], space = FALSE)
    if (replacement[[1L]]$spelling == "##" || replacement[[length(replacement)]]$spelling == "##") definition_error("'##' cannot appear at either end of a macro expansion")
  }
  for (index in seq_along(replacement)) {
    token <- replacement[[index]]
    if (token$kind == "identifier" && token$spelling == VARIADIC_NAME && !variadic) definition_error(VARIADIC_ERROR)
    if (token$spelling == "#" && !is.null(parameters)) {
      if (index == length(replacement) || replacement[[index + 1L]]$kind != "identifier" || !replacement[[index + 1L]]$spelling %in% parameters) definition_error("'#' is not followed by a macro parameter")
    }
  }
  new_record(name = name, parameters = parameters, variadic = variadic, replacement = replacement,
             position = position, main_file = main_file, expanded = 0L, tested = 0L)
}
