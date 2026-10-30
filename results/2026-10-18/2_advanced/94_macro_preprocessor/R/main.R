source("lexer.R")
source("definitions.R")
source("expression.R")
source("include_manager.R")
source("expander.R")
options(expressions = 500000L)
CONDITIONALS <- c(STARTS, BRANCHES, "endif")
new_position <- function(filename, line) list(filename = filename, line = line)
new_inclusion <- function(source, depth) new_record(source = source, depth = depth, display_file = source$path, offset = 0L, stack = list(), segment = list())
display_position <- function(context, physical) new_position(context$display_file, physical + context$offset)
skipping <- function(context) length(context$stack) > 0L && !context$stack[[length(context$stack)]]$active
directive_error <- function(message) stop(structure(list(message = message), class = c("directive_error", "error", "condition")))
separator_needed <- function(left, right) {
  if (left == "/" && substr(right, 1L, 1L) %in% c("/", "*")) return(TRUE)
  read_token(paste0(left, right))$end != nchar(left) + 1L
}
output_render <- function(tokens) {
  pieces <- character()
  previous <- NULL
  for (token in tokens) {
    if (!is.null(previous) && (token$space || separator_needed(previous, token$spelling))) pieces <- c(pieces, " ")
    pieces <- c(pieces, token$spelling)
    previous <- token$spelling
  }
  paste(pieces, collapse = "")
}
following <- function(heading, items) if (length(items)) paste0(heading, paste0(" ", items, collapse = "")) else heading
header_specification <- function(tokens, index = 1L) {
  if (index > length(tokens)) return(list(header = NULL, consumed = index))
  token <- tokens[[index]]
  if (token$kind %in% c("string", "header")) {
    text <- token$spelling
    header <- list(rendering = text, name = substr(text, 2L, nchar(text) - 1L), quoted = startsWith(text, '"'))
    return(list(header = header, consumed = index + 1L))
  }
  if (token$spelling == "<") {
    closing <- index + 1L
    while (closing <= length(tokens) && tokens[[closing]]$spelling != ">") closing <- closing + 1L
    if (closing > length(tokens)) directive_error("missing terminating > character")
    inside <- if (closing > index + 1L) tokens[seq.int(index + 1L, closing - 1L)] else list()
    text <- paste0("<", render(inside), ">")
    return(list(header = list(rendering = text, name = substr(text, 2L, nchar(text) - 1L), quoted = FALSE), consumed = closing + 1L))
  }
  list(header = NULL, consumed = index)
}
decimal_token <- function(token) token$kind == "number" && grepl("^[0-9]+$", token$spelling)
new_preprocessor <- function() {
  processor <- new_record(macros = new.env(hash = TRUE, parent = emptyenv()), ever_defined = character(),
                          saved = new.env(hash = TRUE, parent = emptyenv()), poisoned = character(),
                          manager = new_include_manager(), expander = NULL,
                          output = character(), history = character(), diagnostics = character(), tree = "main.c",
                          conditional_records = character(), regions = character(), previous = new_position("main.c", 0L),
                          diagnostic_counts = c(error = 0L, warning = 0L),
                          condition_counts = c(taken = 0L, not_taken = 0L, skipped = 0L, not_evaluated = 0L, endif = 0L))
  processor$expander <- new_expander(processor$macros, function(position, kind, message) diagnostic(processor, position, kind, message))
  processor
}
diagnostic <- function(processor, position, kind, message) {
  processor$diagnostics <- c(processor$diagnostics, paste0(position$filename, ":", integer_text(position$line), ": ", kind, ": ", message))
  processor$diagnostic_counts[[kind]] <- processor$diagnostic_counts[[kind]] + 1L
}
event <- function(processor, position, content) processor$history <- c(processor$history, paste0(position$filename, ":", integer_text(position$line), ": ", content))
poison_check <- function(processor, context, tokens) {
  for (token in tokens) if (token$kind == "identifier" && token$spelling %in% processor$poisoned) diagnostic(processor, display_position(context, token$line), "error", paste0('attempt to use poisoned "', token$spelling, '"'))
}
unused_check <- function(processor, definition) {
  if (definition$main_file && definition$expanded == 0L && definition$tested == 0L) diagnostic(processor, definition$position, "warning", paste0('macro "', definition$name, '" is not used'))
}
define_macro <- function(processor, tokens, position, main_file) {
  definition <- tryCatch(parse_definition(tokens, position, main_file), definition_error = function(error) error)
  if (inherits(definition, "definition_error")) {
    diagnostic(processor, position, "error", definition$message)
    return(invisible(NULL))
  }
  previous <- macro_get(processor$macros, definition$name)
  if (is.null(previous)) {
    macro_set(processor$macros, definition$name, definition)
    processor$ever_defined <- union(processor$ever_defined, definition$name)
    operation <- "define"
  } else if (identical_definition(previous, definition)) {
    operation <- "identical"
  } else {
    unused_check(processor, previous)
    diagnostic(processor, position, "warning", paste0('"', definition$name, '" redefined (previous definition at ', previous$position$filename, ":", integer_text(previous$position$line), ")"))
    macro_set(processor$macros, definition$name, definition)
    processor$ever_defined <- union(processor$ever_defined, definition$name)
    operation <- "redefine"
  }
  event(processor, position, paste(operation, signature(definition)))
}
undefine_macro <- function(processor, tokens, position) {
  error <- check_macro_name(tokens, "undef")
  if (!is.null(error)) {
    diagnostic(processor, position, "error", error)
    return(invisible(NULL))
  }
  if (length(tokens) >= 2L) diagnostic(processor, position, "warning", "extra tokens at end of #undef directive")
  name <- tokens[[1L]]$spelling
  definition <- macro_get(processor$macros, name)
  if (!is.null(definition)) {
    unused_check(processor, definition)
    macro_remove(processor$macros, name)
    event(processor, position, paste("undef", name))
  } else {
    event(processor, position, paste("undef", name, "(not defined)"))
  }
}
process_defines <- function(processor) {
  lines <- readLines("input/defines.txt", warn = FALSE)
  for (number in seq_along(lines)) {
    line <- lines[[number]]
    if (!nzchar(line)) next
    equals <- regexpr("=", line, fixed = TRUE)[[1L]]
    text <- if (equals > 0L) paste0(substr(line, 1L, equals - 1L), " ", substring(line, equals + 1L)) else paste0(line, " 1")
    define_macro(processor, lex_definition(text, number), new_position("defines.txt", number), FALSE)
  }
}
marker <- function(processor, filename, line, flag = NULL) {
  text <- paste0("# ", integer_text(line), ' "', filename, '"')
  if (!is.null(flag)) text <- paste(text, flag)
  processor$output <- c(processor$output, text)
  processor$previous <- new_position(filename, line - 1L)
}
output_line <- function(processor, context, physical, text) {
  position <- display_position(context, physical)
  previous <- processor$previous
  if (position$filename == previous$filename && previous$line < position$line && position$line <= previous$line + 8L) {
    processor$output <- c(processor$output, rep("", position$line - previous$line - 1L))
  } else {
    marker(processor, position$filename, position$line)
  }
  processor$output <- c(processor$output, text)
  processor$previous <- position
  context$source$output_lines <- context$source$output_lines + 1L
}
flush_segment <- function(processor, context) {
  segment <- context$segment
  context$segment <- list()
  if (!length(segment)) return(invisible(NULL))
  poison_check(processor, context, segment)
  expanded <- expand_tokens(processor$expander, segment, context)
  index <- 1L
  while (index <= length(expanded)) {
    ending <- index + 1L
    while (ending <= length(expanded) && expanded[[ending]]$line == expanded[[index]]$line) ending <- ending + 1L
    output_line(processor, context, expanded[[index]]$line, output_render(expanded[seq.int(index, ending - 1L)]))
    index <- ending
  }
}
macro_defined <- function(processor, name) {
  definition <- macro_get(processor$macros, name)
  if (!is.null(definition)) {
    definition$tested <- definition$tested + 1L
    return(TRUE)
  }
  name %in% BUILTINS || name == "__has_include"
}
replace_operators <- function(processor, context, operands) {
  replaced <- list()
  index <- 1L
  while (index <= length(operands)) {
    token <- operands[[index]]
    if (token$kind == "identifier" && token$spelling == "defined") {
      following <- index + 1L
      parenthesized <- following <= length(operands) && operands[[following]]$spelling == "("
      if (parenthesized) following <- following + 1L
      if (following > length(operands) || operands[[following]]$kind != "identifier") directive_error('operator "defined" requires an identifier')
      name <- operands[[following]]$spelling
      following <- following + 1L
      if (parenthesized) {
        if (following > length(operands) || operands[[following]]$spelling != ")") directive_error('missing \')\' after "defined"')
        following <- following + 1L
      }
      value <- macro_defined(processor, name)
    } else if (token$kind == "identifier" && token$spelling == "__has_include") {
      following <- index + 1L
      if (following > length(operands) || operands[[following]]$spelling != "(") directive_error('missing \'(\' after "__has_include"')
      read <- header_specification(operands, following + 1L)
      header <- read$header
      following <- read$consumed
      if (is.null(header) || !nzchar(header$name)) directive_error('operator "__has_include" requires a header-name')
      if (following > length(operands) || operands[[following]]$spelling != ")") directive_error('missing \')\' after "__has_include" operand')
      following <- following + 1L
      value <- !is.null(search_header(header$name, header$quoted))
    } else {
      replaced[[length(replaced) + 1L]] <- token
      index <- index + 1L
      next
    }
    replaced[[length(replaced) + 1L]] <- pp_token("number", as.character(as.integer(value)), token$line, token$space)
    index <- following
  }
  replaced
}
test_condition <- function(processor, context, logical, name, operands) {
  position <- display_position(context, logical$tokens[[1L]]$line)
  poison_check(processor, context, operands)
  if (!name %in% c("if", "elif")) {
    if (!length(operands)) {
      diagnostic(processor, position, "error", paste0("no macro name given in #", name, " directive"))
      return(list(value = NULL, expanded = NULL))
    }
    if (operands[[1L]]$kind != "identifier") {
      diagnostic(processor, position, "error", "macro names must be identifiers")
      return(list(value = NULL, expanded = NULL))
    }
    if (length(operands) >= 2L) diagnostic(processor, position, "warning", paste0("extra tokens at end of #", name, " directive"))
    defined <- macro_defined(processor, operands[[1L]]$spelling)
    return(list(value = as.integer(if (name %in% c("ifndef", "elifndef")) !defined else defined), expanded = NULL))
  }
  replaced <- tryCatch(replace_operators(processor, context, operands), directive_error = function(error) error)
  if (inherits(replaced, "directive_error")) {
    diagnostic(processor, position, "error", replaced$message)
    return(list(value = NULL, expanded = NULL))
  }
  expanded <- expand_tokens(processor$expander, replaced, context)
  value <- tryCatch({
    tree <- parse_expression(expanded, name)
    evaluate_expression(tree, function(message) diagnostic(processor, position, "warning", message))
  }, expression_error = function(error) error)
  if (inherits(value, "expression_error")) {
    diagnostic(processor, position, "error", value$message)
    return(list(value = NULL, expanded = expanded))
  }
  list(value = value, expanded = expanded)
}
test_description <- function(name, tested) {
  if (is.null(tested$value)) {
    description <- "not taken (error)"
  } else {
    description <- if (tested$value != 0) "taken" else "not taken"
    if (name %in% c("if", "elif")) description <- paste0(description, " (value ", integer_text(tested$value), ")")
  }
  if (!is.null(tested$expanded)) description <- paste0(description, " [", output_render(tested$expanded), "]")
  description
}
close_region <- function(processor, context, block, ending) {
  start <- block$skip_start
  if (!is.null(start) && ending >= start) {
    first <- display_position(context, start)
    last <- display_position(context, ending)$line
    processor$regions <- c(processor$regions, paste0(first$filename, ":", integer_text(first$line), "-", integer_text(last), " lines=", ending - start + 1L))
    context$source$skipped_lines <- context$source$skipped_lines + ending - start + 1L
  }
  block$skip_start <- NULL
}
conditional_record <- function(processor, position, depth, name, operands, description) {
  directive <- paste0("#", name, if (length(operands)) paste0(" ", render(operands)) else "")
  processor$conditional_records <- c(processor$conditional_records, paste0(position$filename, ":", integer_text(position$line), ": ", strrep("  ", depth), directive, " => ", description))
  prefixes <- c("taken", "not taken", "skipped", "not evaluated", "closes")
  categories <- c("taken", "not_taken", "skipped", "not_evaluated", "endif")
  for (index in seq_along(prefixes)) if (startsWith(description, prefixes[[index]])) {
    category <- categories[[index]]
    processor$condition_counts[[category]] <- processor$condition_counts[[category]] + 1L
    break
  }
}
process_conditional <- function(processor, context, logical, name, operands) {
  position <- display_position(context, logical$tokens[[1L]]$line)
  if (name %in% STARTS) {
    parent <- !length(context$stack) || context$stack[[length(context$stack)]]$active
    block <- new_record(kind = name, position = position, parent = parent, chosen = FALSE,
                         active = FALSE, else_seen = FALSE, skip_start = NULL)
    if (parent) {
      tested <- test_condition(processor, context, logical, name, operands)
      if (!is.null(tested$value) && tested$value != 0) {
        block$chosen <- block$active <- TRUE
      } else {
        block$skip_start <- logical$end + 1L
      }
      description <- test_description(name, tested)
    } else {
      description <- "skipped"
    }
    conditional_record(processor, position, length(context$stack), name, operands, description)
    context$stack[[length(context$stack) + 1L]] <- block
    return(invisible(NULL))
  }
  if (!length(context$stack)) {
    diagnostic(processor, position, "error", paste0("#", name, " without #if"))
    return(invisible(NULL))
  }
  block <- context$stack[[length(context$stack)]]
  depth <- length(context$stack) - 1L
  close_region(processor, context, block, logical$start - 1L)
  if (name == "endif") {
    context$stack <- head(context$stack, -1L)
    if (block$parent && length(operands)) diagnostic(processor, position, "warning", "extra tokens at end of #endif directive")
    description <- paste0("closes #", block$kind, " at line ", integer_text(block$position$line))
  } else {
    if (block$else_seen) diagnostic(processor, position, "error", paste0("#", name, " after #else"))
    if (name == "else") {
      if (block$parent && length(operands)) diagnostic(processor, position, "warning", "extra tokens at end of #else directive")
      block$else_seen <- TRUE
      if (block$parent) {
        block$active <- !block$chosen
        block$chosen <- TRUE
        description <- if (block$active) "taken" else "not taken"
      } else {
        block$active <- FALSE
        description <- "skipped"
      }
    } else if (!block$parent) {
      block$active <- FALSE
      description <- "skipped"
    } else if (block$chosen) {
      block$active <- FALSE
      description <- "not evaluated"
    } else {
      tested <- test_condition(processor, context, logical, name, operands)
      block$active <- !is.null(tested$value) && tested$value != 0
      if (block$active) block$chosen <- TRUE
      description <- test_description(name, tested)
    }
    if (block$parent && !block$active) block$skip_start <- logical$end + 1L
  }
  conditional_record(processor, position, depth, name, operands, description)
}
include_file <- function(processor, context, logical, operands) {
  position <- display_position(context, logical$tokens[[1L]]$line)
  parsed <- tryCatch({
    sequence <- operands
    read <- header_specification(sequence)
    if (is.null(read$header) && length(sequence)) {
      sequence <- expand_tokens(processor$expander, sequence, context)
      read <- header_specification(sequence)
    }
    header <- read$header
    if (is.null(header)) directive_error('#include expects "FILENAME" or <FILENAME>')
    if (read$consumed <= length(sequence)) diagnostic(processor, position, "warning", "extra tokens at end of #include directive")
    if (!nzchar(header$name)) directive_error("empty filename in #include")
    header
  }, directive_error = function(error) error)
  if (inherits(parsed, "directive_error")) {
    diagnostic(processor, position, "error", parsed$message)
    return(invisible(NULL))
  }
  header <- parsed
  prefix <- paste0(strrep("  ", context$depth + 1L), logical$tokens[[1L]]$line, ": ")
  path <- search_header(header$name, header$quoted)
  if (is.null(path)) {
    processor$tree <- c(processor$tree, paste0(prefix, header$rendering, " [not found]"))
    diagnostic(processor, position, "error", paste("cannot find include file", header$rendering))
    return(invisible(NULL))
  }
  previous <- if (exists(path, processor$manager$files, inherits = FALSE)) get(path, processor$manager$files, inherits = FALSE) else NULL
  if (!is.null(previous) && previous$once) {
    processor$tree <- c(processor$tree, paste0(prefix, path, " [skipped: pragma once]"))
    previous$skipped <- previous$skipped + 1L
    return(invisible(NULL))
  }
  if (!is.null(previous) && !is.null(previous$guard) && !is.null(macro_get(processor$macros, previous$guard))) {
    processor$tree <- c(processor$tree, paste0(prefix, path, " [skipped: guard ", previous$guard, "]"))
    previous$skipped <- previous$skipped + 1L
    return(invisible(NULL))
  }
  if (context$depth + 1L > 8L) {
    processor$tree <- c(processor$tree, paste0(prefix, path, " [too deep]"))
    diagnostic(processor, position, "error", "#include nested too deeply")
    return(invisible(NULL))
  }
  processor$tree <- c(processor$tree, paste0(prefix, path))
  marker(processor, path, 1L, 1L)
  process_file(processor, path, context$depth + 1L)
  returning <- display_position(context, logical$end + 1L)
  marker(processor, returning$filename, returning$line, 2L)
}
line_directive <- function(processor, context, logical, operands) {
  position <- display_position(context, logical$tokens[[1L]]$line)
  if (!length(operands) || !decimal_token(operands[[1L]])) operands <- expand_tokens(processor$expander, operands, context)
  if (!length(operands) %in% c(1L, 2L) || !decimal_token(operands[[1L]]) || (length(operands) == 2L && operands[[2L]]$kind != "string")) {
    diagnostic(processor, position, "error", "invalid #line directive")
    return(invisible(NULL))
  }
  line <- as.numeric(operands[[1L]]$spelling)
  if (line < 1 || line > 2147483647) {
    diagnostic(processor, position, "error", "line number out of range")
    return(invisible(NULL))
  }
  context$offset <- line - logical$end - 1L
  if (length(operands) == 2L) context$display_file <- substr(operands[[2L]]$spelling, 2L, nchar(operands[[2L]]$spelling) - 1L)
}
macro_pragma <- function(processor, position, operands, operation) {
  if (length(operands) != 4L || operands[[2L]]$spelling != "(" || operands[[3L]]$kind != "string" || operands[[4L]]$spelling != ")") {
    diagnostic(processor, position, "error", paste0("invalid #pragma ", operation, " directive"))
    return(invisible(NULL))
  }
  name <- substr(operands[[3L]]$spelling, 2L, nchar(operands[[3L]]$spelling) - 1L)
  key <- paste0("s:", name)
  saved <- if (exists(key, processor$saved, inherits = FALSE)) get(key, processor$saved, inherits = FALSE) else list()
  if (operation == "push_macro") {
    saved[length(saved) + 1L] <- list(macro_get(processor$macros, name))
    assign(key, saved, processor$saved)
    event(processor, position, paste("push", name))
  } else if (!length(saved)) {
    diagnostic(processor, position, "warning", paste0('no matching push_macro for "', name, '"'))
  } else {
    definition <- saved[[length(saved)]]
    assign(key, head(saved, -1L), processor$saved)
    if (is.null(definition)) {
      macro_remove(processor$macros, name)
      event(processor, position, paste("pop", name, "(undefined)"))
    } else {
      macro_set(processor$macros, name, definition)
      event(processor, position, paste("pop", name))
    }
  }
}
pragma_directive <- function(processor, context, logical, operands) {
  position <- display_position(context, logical$tokens[[1L]]$line)
  name <- if (length(operands) && operands[[1L]]$kind == "identifier") operands[[1L]]$spelling else NULL
  if (identical(name, "once")) {
    if (length(operands) >= 2L) diagnostic(processor, position, "warning", "extra tokens at end of #pragma once directive")
    if (context$depth == 0L) diagnostic(processor, position, "warning", "#pragma once in main file")
    context$source$once <- TRUE
  } else if (length(operands) >= 2L && operands[[1L]]$spelling == "GCC" && operands[[2L]]$spelling == "poison") {
    remaining <- tail(operands, -2L)
    if (any(vapply(remaining, function(token) token$kind != "identifier", logical(1L)))) {
      diagnostic(processor, position, "error", "invalid #pragma GCC poison directive")
      return(invisible(NULL))
    }
    for (token in remaining) {
      if (!is.null(macro_get(processor$macros, token$spelling))) diagnostic(processor, position, "warning", paste0('poisoning existing macro "', token$spelling, '"'))
      processor$poisoned <- union(processor$poisoned, token$spelling)
    }
  } else if (length(name) && name %in% c("push_macro", "pop_macro")) {
    macro_pragma(processor, position, operands, name)
  } else {
    output_line(processor, context, logical$tokens[[1L]]$line, paste0("#pragma", if (length(operands)) paste0(" ", render(operands)) else ""))
  }
}
process_directive <- function(processor, context, logical, name, operands) {
  if (length(logical$tokens) == 1L) return(invisible(NULL))
  poisoning <- identical(name, "pragma") && length(operands) >= 2L && operands[[1L]]$spelling == "GCC" && operands[[2L]]$spelling == "poison"
  if (!poisoning) poison_check(processor, context, operands)
  position <- display_position(context, logical$tokens[[1L]]$line)
  if (identical(name, "define")) {
    define_macro(processor, operands, position, context$depth == 0L)
  } else if (identical(name, "undef")) {
    undefine_macro(processor, operands, position)
  } else if (identical(name, "include")) {
    include_file(processor, context, logical, operands)
  } else if (identical(name, "line")) {
    line_directive(processor, context, logical, operands)
  } else if (length(name) && name %in% c("error", "warning")) {
    diagnostic(processor, position, name, paste0("#", name, if (length(operands)) paste0(" ", render(operands)) else ""))
  } else if (identical(name, "pragma")) {
    pragma_directive(processor, context, logical, operands)
  } else {
    diagnostic(processor, position, "error", paste0("invalid preprocessing directive #", logical$tokens[[2L]]$spelling))
  }
}
process_file <- function(processor, path, depth) {
  source <- load_source(processor$manager, path)
  source$entered <- source$entered + 1L
  context <- new_inclusion(source, depth)
  for (logical in source$lines) {
    tokens <- logical$tokens
    is_directive <- length(tokens) > 0L && tokens[[1L]]$spelling == "#"
    name <- directive_name(tokens)
    operands <- tail(tokens, -min(2L, length(tokens)))
    if (is_directive && length(name) && name %in% CONDITIONALS) {
      flush_segment(processor, context)
      process_conditional(processor, context, logical, name, operands)
    } else if (skipping(context)) {
      next
    } else if (is_directive) {
      flush_segment(processor, context)
      process_directive(processor, context, logical, name, operands)
    } else {
      context$segment <- c(context$segment, tokens)
    }
  }
  flush_segment(processor, context)
  for (block in context$stack) close_region(processor, context, block, source$physical_lines)
  for (block in context$stack) diagnostic(processor, block$position, "error", paste0("unterminated #", block$kind))
}
include_report <- function(processor) {
  lines <- c(processor$tree, "", "== files ==")
  for (path in sort(ls(processor$manager$files, all.names = TRUE), method = "radix")) {
    source <- get(path, processor$manager$files, inherits = FALSE)
    guard <- if (is.null(source$guard)) "-" else source$guard
    once <- if (source$once) "yes" else "no"
    lines <- c(lines, paste0(path, " entered=", source$entered, " skipped=", source$skipped,
                            " lines=", source$physical_lines, " output_lines=", source$output_lines,
                            " skipped_lines=", source$skipped_lines, " guard=", guard, " once=", once))
  }
  lines <- c(lines, "")
  current <- "main.o:"
  has_path <- FALSE
  for (path in processor$manager$order) {
    if (nchar(current) + 1L + nchar(path) > 76L && has_path) {
      lines <- c(lines, paste0(current, " \\"))
      current <- " "
      has_path <- FALSE
    }
    current <- paste0(current, " ", path)
    has_path <- TRUE
  }
  c(lines, current)
}
macro_references <- function(processor) {
  references <- list()
  for (name in macro_names(processor$macros)) {
    definition <- macro_get(processor$macros, name)
    refs <- vapply(Filter(function(token) token$kind == "identifier" && !is.null(macro_get(processor$macros, token$spelling)) && !token$spelling %in% definition$parameters, definition$replacement), function(token) token$spelling, character(1L))
    references[[name]] <- sort(unique(refs), method = "radix")
  }
  references
}
macro_recursive <- function(name, references) {
  pending <- references[[name]]
  seen <- character()
  while (length(pending)) {
    current <- tail(pending, 1L)
    pending <- head(pending, -1L)
    if (current == name) return(TRUE)
    if (!current %in% seen) {
      seen <- c(seen, current)
      pending <- c(pending, references[[current]])
    }
  }
  FALSE
}
macro_report <- function(processor) {
  lines <- c("== history ==", processor$history, "", "== table ==")
  references <- macro_references(processor)
  names <- sort(unname(macro_names(processor$macros)), method = "radix")
  for (name in names) {
    definition <- macro_get(processor$macros, name)
    text <- paste0("#define ", signature(definition), if (length(definition$replacement)) paste0(" ", render(definition$replacement)) else "")
    recursive <- if (macro_recursive(name, references)) "yes" else "no"
    lines <- c(lines, text, paste0("  at ", definition$position$filename, ":", integer_text(definition$position$line),
                                   " expanded=", definition$expanded, " tested=", definition$tested, " recursive=", recursive), following("  refs:", references[[name]]))
  }
  object_like <- sum(vapply(names, function(name) is.null(macro_get(processor$macros, name)$parameters), logical(1L)))
  lines <- c(lines, "", paste0("macros=", length(names), " object_like=", object_like, " function_like=", length(names) - object_like),
             following("undefined:", sort(setdiff(processor$ever_defined, names), method = "radix")))
  count <- function(name) {
    value <- processor$expander$builtin_counts[[name]]
    if (is.null(value)) 0L else value
  }
  c(lines, paste0("builtins: __COUNTER__=", count("__COUNTER__"), " __FILE__=", count("__FILE__"), " __LINE__=", count("__LINE__")))
}
conditional_report <- function(processor) {
  counts <- processor$condition_counts
  c(processor$conditional_records, "", "== skipped regions ==", processor$regions, "",
    paste0("directives=", length(processor$conditional_records), " taken=", counts[["taken"]],
           " not_taken=", counts[["not_taken"]], " skipped=", counts[["skipped"]],
           " not_evaluated=", counts[["not_evaluated"]], " endif=", counts[["endif"]], " regions=", length(processor$regions)))
}
write_reports <- function(processor) {
  diagnostic_lines <- c(processor$diagnostics, paste0("errors=", processor$diagnostic_counts[["error"]], " warnings=", processor$diagnostic_counts[["warning"]]))
  reports <- list("preprocessed.txt" = processor$output, "includes.txt" = include_report(processor),
                  "macros.txt" = macro_report(processor), "conditionals.txt" = conditional_report(processor),
                  "diagnostics.txt" = diagnostic_lines)
  dir.create("output", showWarnings = FALSE)
  for (name in names(reports)) {
    lines <- sub(" +$", "", reports[[name]])
    connection <- file(file.path("output", name), open = "wb")
    writeChar(paste0(paste(lines, collapse = "\n"), "\n"), connection, eos = NULL, useBytes = TRUE)
    close(connection)
  }
}
main <- function() {
  processor <- new_preprocessor()
  process_defines(processor)
  marker(processor, "main.c", 1L)
  process_file(processor, "main.c", 0L)
  for (name in sort(unname(macro_names(processor$macros)), method = "radix")) unused_check(processor, macro_get(processor$macros, name))
  write_reports(processor)
}
main()
