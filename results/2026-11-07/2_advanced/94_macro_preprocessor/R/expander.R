new_expander <- function(macros, diagnostic) new_record(macros = macros, diagnostic = diagnostic, counter = 0L, builtin_counts = list())
expansion_error <- function(expander, context, token, message) expander$diagnostic(display_position(context, token$line), "error", message)
expand_builtin <- function(expander, token, context) {
  count <- expander$builtin_counts[[token$spelling]]
  expander$builtin_counts[[token$spelling]] <- if (is.null(count)) 1L else count + 1L
  if (token$spelling == "__FILE__") {
    kind <- "string"
    spelling <- paste0('"', context$display_file, '"')
  } else if (token$spelling == "__LINE__") {
    kind <- "number"
    spelling <- integer_text(display_position(context, token$line)$line)
  } else {
    kind <- "number"
    spelling <- integer_text(expander$counter)
    expander$counter <- expander$counter + 1L
  }
  pp_token(kind, spelling, token$line, token$space)
}
collect_arguments <- function(expander, pending, definition, token, context) {
  arguments <- list(list())
  separators <- list()
  nesting <- 0L
  closing <- consumed <- NULL
  cursor <- pending$rest
  index <- 2L
  while (!is.null(cursor)) {
    current <- cursor$token
    cursor <- cursor$rest
    if (current$spelling == ")" && nesting == 0L) {
      closing <- current
      consumed <- index
      break
    }
    if (current$spelling == "," && nesting == 0L) {
      separators[[length(separators) + 1L]] <- current
      arguments[[length(arguments) + 1L]] <- list()
    } else {
      if (current$spelling == "(") nesting <- nesting + 1L
      if (current$spelling == ")") nesting <- nesting - 1L
      last <- length(arguments)
      arguments[[last]][[length(arguments[[last]]) + 1L]] <- current
    }
    index <- index + 1L
  }
  if (is.null(closing)) {
    expansion_error(expander, context, token, paste0('unterminated argument list invoking macro "', definition$name, '"'))
    return(NULL)
  }
  count <- length(arguments)
  fixed <- length(definition$parameters) - as.integer(definition$variadic)
  error <- NULL
  if (!definition$variadic && fixed == 0L && (count != 1L || length(arguments[[1L]]) > 0L)) {
    error <- paste0('macro "', definition$name, '" passed ', count, ' arguments, but takes just 0')
  } else if (count < fixed) {
    error <- paste0('macro "', definition$name, '" requires ', fixed, ' arguments, but only ', count, ' given')
  } else if (count > fixed && !definition$variadic) {
    error <- paste0('macro "', definition$name, '" passed ', count, ' arguments, but takes just ', fixed)
  }
  if (!is.null(error)) {
    expansion_error(expander, context, token, error)
    return(NULL)
  }
  raw <- setNames(head(arguments, fixed), head(definition$parameters, fixed))
  if (definition$variadic) {
    variable <- list()
    if (fixed < count) for (index in seq.int(fixed + 1L, count)) {
      if (index > fixed + 1L) variable[[length(variable) + 1L]] <- separators[[index - 1L]]
      variable <- c(variable, arguments[[index]])
    }
    raw[[VARIADIC_NAME]] <- variable
  }
  list(raw = raw, consumed = consumed, closing = closing)
}
stringize <- function(tokens, sharp) {
  pieces <- character()
  for (index in seq_along(tokens)) {
    token <- tokens[[index]]
    if (index > 1L && token$space) pieces <- c(pieces, " ")
    spelling <- token$spelling
    if (token$kind %in% c("string", "character")) {
      characters <- strsplit(spelling, "", fixed = TRUE)[[1L]]
      spelling <- paste(vapply(characters, function(character) if (character == "\\") "\\\\" else if (character == '"') '\\"' else character, character(1L)), collapse = "")
    }
    pieces <- c(pieces, spelling)
  }
  pp_token("string", paste0('"', paste(pieces, collapse = ""), '"'), sharp$line, sharp$space)
}
paste_tokens <- function(expander, left, right, token, context) {
  if (left$kind == "placemarker") return(list(token_with(right, space = left$space)))
  if (right$kind == "placemarker") return(list(left))
  spelling <- paste0(left$spelling, right$spelling)
  kind <- single_token(spelling)
  if (!is.null(kind)) return(list(pp_token(kind, spelling, left$line, left$space, intersect(left$hide, right$hide))))
  expansion_error(expander, context, token, paste0('pasting "', left$spelling, '" and "', right$spelling, '" does not give a valid preprocessing token'))
  list(left, token_with(right, space = FALSE))
}
substitute <- function(expander, definition, raw, token, hide, context) {
  replacement <- definition$replacement
  items <- list()
  expanded <- new.env(hash = TRUE, parent = emptyenv())
  index <- 1L
  while (index <= length(replacement)) {
    current <- replacement[[index]]
    if (current$spelling == "#" && !is.null(definition$parameters)) {
      parameter <- replacement[[index + 1L]]$spelling
      items[[length(items) + 1L]] <- list(paste = FALSE, tokens = list(stringize(raw[[parameter]], current)))
      index <- index + 2L
      next
    }
    if (current$spelling == "##") {
      item <- list(paste = TRUE, token = current)
    } else if (current$kind == "identifier" && current$spelling %in% names(raw)) {
      adjacent <- (index > 1L && replacement[[index - 1L]]$spelling == "##") || (index < length(replacement) && replacement[[index + 1L]]$spelling == "##")
      if (adjacent) {
        sequence <- raw[[current$spelling]]
      } else {
        if (!exists(current$spelling, expanded, inherits = FALSE)) assign(current$spelling, expand_tokens(expander, raw[[current$spelling]], context), expanded)
        sequence <- get(current$spelling, expanded, inherits = FALSE)
      }
      if (length(sequence)) sequence[[1L]] <- token_with(sequence[[1L]], space = current$space) else sequence <- list(pp_token("placemarker", "", current$line, current$space))
      item <- list(paste = FALSE, tokens = sequence)
    } else {
      item <- list(paste = FALSE, tokens = list(current))
    }
    items[[length(items) + 1L]] <- item
    index <- index + 1L
  }
  pasted <- list()
  index <- 1L
  while (index <= length(items)) {
    item <- items[[index]]
    if (item$paste) {
      left <- pasted[[length(pasted)]]
      pasted <- head(pasted, -1L)
      right_item <- items[[index + 1L]]
      right <- if (right_item$paste) list(right_item$token) else right_item$tokens
      pasted <- c(pasted, paste_tokens(expander, left, right[[1L]], token, context), tail(right, -1L))
      index <- index + 2L
    } else {
      pasted <- c(pasted, item$tokens)
      index <- index + 1L
    }
  }
  result <- list()
  carry_space <- FALSE
  for (current in pasted) {
    if (current$kind == "placemarker") {
      carry_space <- carry_space || current$space
    } else {
      result[[length(result) + 1L]] <- token_with(current, line = token$line, space = current$space || carry_space, hide = union(current$hide, hide))
      carry_space <- FALSE
    }
  }
  if (length(result)) result[[1L]] <- token_with(result[[1L]], space = token$space)
  result
}
expand_tokens <- function(expander, sequence, context) {
  pending <- NULL
  for (current in rev(sequence)) pending <- list(token = current, rest = pending)
  result <- list()
  while (!is.null(pending)) {
    token <- pending$token
    pending <- pending$rest
    if (token$kind != "identifier" || token$spelling %in% token$hide) {
      result[[length(result) + 1L]] <- token
      next
    }
    if (token$spelling %in% BUILTINS) {
      result[[length(result) + 1L]] <- expand_builtin(expander, token, context)
      next
    }
    definition <- macro_get(expander$macros, token$spelling)
    if (is.null(definition) || (!is.null(definition$parameters) && (is.null(pending) || pending$token$spelling != "("))) {
      result[[length(result) + 1L]] <- token
      next
    }
    raw <- list()
    hide <- union(token$hide, definition$name)
    if (!is.null(definition$parameters)) {
      collected <- collect_arguments(expander, pending, definition, token, context)
      if (is.null(collected)) {
        result[[length(result) + 1L]] <- token
        next
      }
      raw <- collected$raw
      for (index in seq_len(collected$consumed)) pending <- pending$rest
      hide <- union(intersect(token$hide, collected$closing$hide), definition$name)
    }
    replacement <- substitute(expander, definition, raw, token, hide, context)
    definition$expanded <- definition$expanded + 1L
    if (!length(replacement) && token$space && !is.null(pending)) pending <- list(token = token_with(pending$token, space = TRUE), rest = pending$rest)
    for (current in rev(replacement)) pending <- list(token = current, rest = pending)
  }
  result
}
