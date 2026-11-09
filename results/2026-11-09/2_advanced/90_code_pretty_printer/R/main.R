source("lexer.R")
source("parser.R")
source("doc_builder.R")
source("printer.R")
source("report.R")
options(expressions = 500000L)
read_profiles <- function() {
  profiles <- list()
  current <- ""
  for (line in readLines("input/style.txt", warn = FALSE)) {
    if (!nzchar(line)) next
    if (startsWith(line, "[")) {
      current <- substr(line, 2L, nchar(line) - 1L)
      profiles[[current]] <- list()
    } else {
      pair <- strsplit(line, "=", fixed = TRUE)[[1L]]
      key <- pair[[1L]]
      value <- pair[[2L]]
      if (key %in% c("width", "indent", "max_blank_lines", "comment_column")) {
        value <- as.integer(value)
      } else if (key %in% c("space_around_operators", "space_after_keyword", "indent_case_labels", "add_braces", "remove_parens")) {
        value <- value == "yes"
      }
      profiles[[current]][[key]] <- value
    }
  }
  profiles
}
read_sources <- function() {
  sources <- list()
  for (line in readLines("input/sources.txt", warn = FALSE)) {
    if (startsWith(line, "=== ")) {
      fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
      sources[[length(sources) + 1L]] <- list(header = line, filename = fields[[2L]], profile = fields[[3L]], lines = character())
    } else {
      index <- length(sources)
      sources[[index]]$lines <- c(sources[[index]]$lines, line)
    }
  }
  sources
}
attach_comments <- function(tokens, comments, items) {
  real_tokens <- head(tokens, -1L)
  precedes <- function(a, b) a$line < b$line || (a$line == b$line && a$column < b$column)
  for (comment in comments) {
    before <- Filter(function(token) precedes(token, comment), real_tokens)
    after <- Filter(function(token) precedes(comment, token), real_tokens)
    previous <- if (length(before)) before[[length(before)]] else NULL
    following <- if (length(after)) after[[1L]] else NULL
    index <- which(vapply(items, identical, logical(1L), y = comment))[[1L]]
    next_item <- if (index < length(items)) items[[index + 1L]] else NULL
    comment$own_line <- comment$kind == "line_comment" || is.null(next_item) || next_item$line > comment$line
    if (!is.null(previous) && previous$line == comment$line && (is.null(following) || following$line > comment$line)) {
      previous$trailing[[length(previous$trailing) + 1L]] <- comment
    } else {
      token <- if (is.null(following)) tokens[[length(tokens)]] else following
      token$leading[[length(token$leading) + 1L]] <- comment
    }
  }
  for (token in tokens) token$original_trailing <- length(token$trailing) > 0L
}
check_comment_positions <- function(tokens) {
  for (token in tokens) for (comment in token$leading) {
    if (token$trailing_comma || (comment$own_line && !token$allowed)) source_error(comment$line, comment$column, "comment not allowed here")
  }
}
new_formatter <- function(profile, tokens) {
  spaced <- profile$space_around_operators
  list(profile = profile, tokens = tokens, indent_width = profile$indent,
       max_blank = profile$max_blank_lines, separator = if (spaced) " " else "",
       operator_break = if (spaced) LINE else SOFTLINE,
       keyword_gap = if (profile$space_after_keyword) " " else "",
       kr = profile$brace_style == "kr")
}
sep_doc <- function(formatter, blank) concat(rep(list(HARDLINE), 1L + min(blank, formatter$max_blank)))
pre_blank <- function(token) if (length(token$leading)) token$leading[[1L]]$blank else token$blank
comment_doc <- function(formatter, comments, following) {
  parts <- list()
  for (index in seq_along(comments)) {
    comment <- comments[[index]]
    parts[[length(parts) + 1L]] <- doc_text(comment$text)
    next_entry <- if (index < length(comments)) comments[[index + 1L]] else following
    if (is.null(next_entry)) next
    parts[[length(parts) + 1L]] <- if (comment$own_line) sep_doc(formatter, next_entry$blank) else doc_text(" ")
  }
  concat(parts)
}
joined_comments <- function(comments) paste(vapply(comments, function(comment) comment$text, character(1L)), collapse = " ")
token_doc <- function(formatter, token, leading = token$leading) {
  concat(comment_doc(formatter, leading, token), doc_text(token$text),
         if (length(token$trailing)) suffix(joined_comments(token$trailing)) else NULL)
}
splitting_comments <- function(token) {
  own <- which(vapply(token$leading, function(comment) comment$own_line, logical(1L)))
  stop <- if (length(own)) tail(own, 1L) else 0L
  list(own = head(token$leading, stop), inline = if (stop < length(token$leading)) token$leading[seq.int(stop + 1L, length(token$leading))] else list())
}
closing_comments <- function(formatter, comments, preceding) {
  if (!length(comments)) return(NULL)
  concat(if (preceding) sep_doc(formatter, comments[[1L]]$blank) else NULL, comment_doc(formatter, comments, NULL))
}
file_doc <- function(formatter, items, end_token) {
  pieces <- list()
  first_function <- function_document <- NULL
  for (index in seq_along(items)) {
    item <- items[[index]]
    if (index > 1L) pieces[[length(pieces) + 1L]] <- sep_doc(formatter, pre_blank(item$first))
    document <- item_doc(formatter, item)
    if (item$tag == "function" && is.null(first_function)) {
      first_function <- item
      function_document <- document
    }
    pieces[[length(pieces) + 1L]] <- document
  }
  if (length(end_token$leading)) {
    if (length(items)) pieces[[length(pieces) + 1L]] <- sep_doc(formatter, end_token$leading[[1L]]$blank)
    pieces[[length(pieces) + 1L]] <- comment_doc(formatter, end_token$leading, NULL)
  }
  list(document = concat(pieces), first_function = first_function, function_doc = function_document)
}
item_doc <- function(formatter, item) {
  if (item$tag != "function") return(variable_doc(formatter, item))
  concat(token_doc(formatter, item$typ), " ", token_doc(formatter, item$name), list_doc(formatter, item$parameters), HARDLINE, block_doc(formatter, item$body))
}
parameter_doc <- function(formatter, item) {
  parts <- list(token_doc(formatter, item$typ), " ", token_doc(formatter, item$name))
  for (brackets in item$brackets) parts <- c(parts, list(token_doc(formatter, brackets[[1L]]), token_doc(formatter, brackets[[2L]])))
  concat(parts)
}
variable_doc <- function(formatter, item) {
  parts <- list(token_doc(formatter, item$typ), " ", token_doc(formatter, item$name))
  for (dimension in item$dimensions) {
    parts[[length(parts) + 1L]] <- token_doc(formatter, dimension[[1L]])
    if (!is.null(dimension[[2L]])) parts[[length(parts) + 1L]] <- expression_doc(formatter, dimension[[2L]], 0L)
    parts[[length(parts) + 1L]] <- token_doc(formatter, dimension[[3L]])
  }
  if (!is.null(item$equals)) parts <- c(parts, list(formatter$separator, token_doc(formatter, item$equals), formatter$separator, initializer_doc(formatter, item$initializer)))
  if (!is.null(item$semi)) parts[[length(parts) + 1L]] <- token_doc(formatter, item$semi)
  concat(parts)
}
initializer_doc <- function(formatter, item) {
  if (item$tag == "list") list_doc(formatter, item) else expression_doc(formatter, item, 0L)
}
list_doc <- function(formatter, item) {
  elements <- lapply(item$elements, function(entry) {
    if (entry$tag == "parameter") parameter_doc(formatter, entry) else if (item$role == "{") initializer_doc(formatter, entry) else expression_doc(formatter, entry, 0L)
  })
  if (!length(elements)) return(concat(token_doc(formatter, item$left), token_doc(formatter, item$right)))
  parts <- list(SOFTLINE, elements[[1L]])
  if (length(elements) > 1L) for (index in seq.int(2L, length(elements))) {
    parts <- c(parts, list(token_doc(formatter, item$commas[[index - 1L]]), LINE, elements[[index]]))
  }
  if (item$role == "{") {
    parts[[length(parts) + 1L]] <- if_break(",", "")
    if (!is.null(item$trailing) && length(item$trailing$trailing)) parts[[length(parts) + 1L]] <- suffix(joined_comments(item$trailing$trailing))
  }
  forced <- any(vapply(formatter$tokens[seq.int(item$left$index, item$right$index - 1L)], function(token) token$original_trailing, logical(1L)))
  group(concat(if (forced) BREAK_PARENT else NULL, token_doc(formatter, item$left), nest(formatter$indent_width, parts), SOFTLINE, token_doc(formatter, item$right)))
}
block_doc <- function(formatter, item) {
  closing <- splitting_comments(item$right)
  if (!length(item$statements) && !length(closing$own)) return(concat(token_doc(formatter, item$left), token_doc(formatter, item$right, closing$inline)))
  parts <- if (!length(item$statements)) list(HARDLINE) else list()
  for (index in seq_along(item$statements)) {
    statement <- item$statements[[index]]
    parts <- c(parts, list(if (index == 1L) HARDLINE else sep_doc(formatter, pre_blank(statement$first)), statement_doc(formatter, statement)))
  }
  parts <- c(parts, list(closing_comments(formatter, closing$own, length(item$statements) > 0L)))
  concat(token_doc(formatter, item$left), nest(formatter$indent_width, parts), HARDLINE, token_doc(formatter, item$right, closing$inline))
}
body_doc <- function(formatter, item) {
  before <- if (formatter$kr) doc_text(" ") else HARDLINE
  if (item$tag == "block") return(concat(before, block_doc(formatter, item)))
  content <- nest(formatter$indent_width, concat(HARDLINE, statement_doc(formatter, item)))
  if (formatter$profile$add_braces) concat(before, "{", content, HARDLINE, "}") else content
}
simple_doc <- function(formatter, item) {
  if (item$tag != "assign") return(expression_doc(formatter, item$expr, 0L))
  concat(expression_doc(formatter, item$left, 0L), formatter$separator, token_doc(formatter, item$op), formatter$separator, expression_doc(formatter, item$right, 0L))
}
if_doc <- function(formatter, item) {
  parts <- list(token_doc(formatter, item$keyword), formatter$keyword_gap, token_doc(formatter, item$left), expression_doc(formatter, item$test, 0L), token_doc(formatter, item$right), body_doc(formatter, item$body))
  if (!is.null(item$else_token)) {
    before <- if (formatter$kr && (item$body$tag == "block" || formatter$profile$add_braces)) doc_text(" ") else HARDLINE
    parts <- c(parts, list(before, token_doc(formatter, item$else_token)))
    parts <- if (item$alternative$tag == "if") c(parts, list(" ", if_doc(formatter, item$alternative))) else c(parts, list(body_doc(formatter, item$alternative)))
  }
  concat(parts)
}
for_doc <- function(formatter, item) {
  parts <- list()
  if (!is.null(item$initial)) parts[[1L]] <- if (item$initial$tag == "variable") variable_doc(formatter, item$initial) else simple_doc(formatter, item$initial)
  parts[[length(parts) + 1L]] <- token_doc(formatter, item$first_semi)
  if (!is.null(item$condition)) parts <- c(parts, list(LINE, expression_doc(formatter, item$condition, 0L)))
  parts[[length(parts) + 1L]] <- token_doc(formatter, item$second_semi)
  if (!is.null(item$update)) parts <- c(parts, list(LINE, simple_doc(formatter, item$update)))
  concat(token_doc(formatter, item$keyword), formatter$keyword_gap, token_doc(formatter, item$left), group(align_doc(parts)), token_doc(formatter, item$right), body_doc(formatter, item$body))
}
clause_doc <- function(formatter, item) {
  parts <- list(token_doc(formatter, item$label))
  if (!is.null(item$value)) parts <- c(parts, list(" ", expression_doc(formatter, item$value, 0L)))
  parts[[length(parts) + 1L]] <- token_doc(formatter, item$colon)
  if (length(item$statements)) {
    inner <- list()
    for (index in seq_along(item$statements)) {
      statement <- item$statements[[index]]
      inner <- c(inner, list(if (index == 1L) HARDLINE else sep_doc(formatter, pre_blank(statement$first)), statement_doc(formatter, statement)))
    }
    parts[[length(parts) + 1L]] <- nest(formatter$indent_width, inner)
  }
  concat(parts)
}
switch_doc <- function(formatter, item) {
  closing <- splitting_comments(item$closing)
  parts <- if (!length(item$clauses) && length(closing$own)) list(HARDLINE) else list()
  for (index in seq_along(item$clauses)) {
    clause <- item$clauses[[index]]
    parts <- c(parts, list(if (index == 1L) HARDLINE else sep_doc(formatter, pre_blank(clause$first)), clause_doc(formatter, clause)))
  }
  parts <- c(parts, list(closing_comments(formatter, closing$own, length(item$clauses) > 0L)))
  header <- concat(token_doc(formatter, item$keyword), formatter$keyword_gap, token_doc(formatter, item$left), expression_doc(formatter, item$test, 0L), token_doc(formatter, item$right), if (formatter$kr) doc_text(" ") else HARDLINE, token_doc(formatter, item$opening))
  if (!length(item$clauses) && !length(closing$own)) return(concat(header, token_doc(formatter, item$closing, closing$inline)))
  amount <- if (formatter$profile$indent_case_labels) formatter$indent_width else 0L
  concat(header, nest(amount, parts), HARDLINE, token_doc(formatter, item$closing, closing$inline))
}
statement_doc <- function(formatter, item) {
  tag <- item$tag
  if (tag == "block") return(block_doc(formatter, item))
  if (tag == "variable") return(variable_doc(formatter, item))
  if (tag == "if") return(if_doc(formatter, item))
  if (tag == "for") return(for_doc(formatter, item))
  if (tag == "switch") return(switch_doc(formatter, item))
  if (tag == "while") return(concat(token_doc(formatter, item$keyword), formatter$keyword_gap, token_doc(formatter, item$left), expression_doc(formatter, item$test, 0L), token_doc(formatter, item$right), body_doc(formatter, item$body)))
  if (tag == "return") return(concat(token_doc(formatter, item$keyword), if (is.null(item$expr)) NULL else concat(" ", expression_doc(formatter, item$expr, 0L)), token_doc(formatter, item$semi)))
  if (tag == "flow") return(concat(token_doc(formatter, item$keyword), token_doc(formatter, item$semi)))
  concat(simple_doc(formatter, item$value), token_doc(formatter, item$semi))
}
last_expression_token <- function(item) {
  if (item$tag == "primary") return(item$value)
  if (item$tag %in% c("paren", "index")) return(item$right)
  if (item$tag == "unary") return(last_expression_token(item$operand))
  if (item$tag == "binary") return(last_expression_token(item$right))
  if (item$tag == "conditional") return(last_expression_token(item$no))
  if (item$tag == "call") return(item$arguments$right)
  item$member
}
opened_expression <- function(formatter, item, required) {
  while (formatter$profile$remove_parens && item$tag == "paren" && item$inner$level >= required && !length(item$left$leading) && !length(item$right$leading)) {
    inner <- item$inner
    if (length(item$left$trailing)) {
      inner$first$trailing <- c(item$left$trailing, inner$first$trailing)
      item$left$trailing <- list()
    }
    if (length(item$right$trailing)) {
      last <- last_expression_token(inner)
      last$trailing <- c(last$trailing, item$right$trailing)
      item$right$trailing <- list()
    }
    item <- inner
  }
  item
}
binary_doc <- function(formatter, item) {
  precedence <- item$level
  operators <- operands <- list()
  current <- item
  while (current$tag == "binary" && current$level == precedence) {
    operators[[length(operators) + 1L]] <- current$op
    operands[[length(operands) + 1L]] <- current$right
    current <- opened_expression(formatter, current$left, precedence)
  }
  operators <- rev(operators)
  operands <- rev(operands)
  parts <- list()
  for (index in seq_along(operators)) parts <- c(parts, list(formatter$operator_break, token_doc(formatter, operators[[index]]), formatter$separator, expression_doc(formatter, operands[[index]], precedence + 1L)))
  group(concat(expression_doc(formatter, current, precedence), nest(formatter$indent_width, parts)))
}
conditional_doc <- function(formatter, item) {
  parts <- list()
  current <- item
  repeat {
    parts <- c(parts, list(formatter$operator_break, token_doc(formatter, current$question), formatter$separator, expression_doc(formatter, current$yes, 0L), formatter$operator_break, token_doc(formatter, current$colon), formatter$separator))
    following <- opened_expression(formatter, current$no, 0L)
    if (following$tag != "conditional") {
      parts[[length(parts) + 1L]] <- expression_doc(formatter, following, 0L)
      break
    }
    parts[[length(parts) + 1L]] <- expression_doc(formatter, following$test, 1L)
    current <- following
  }
  group(concat(expression_doc(formatter, item$test, 1L), nest(formatter$indent_width, parts)))
}
postfix_piece <- function(formatter, item) {
  if (item$tag == "call") return(list_doc(formatter, item$arguments))
  if (item$tag == "index") return(concat(token_doc(formatter, item$left), expression_doc(formatter, item$index, 0L), token_doc(formatter, item$right)))
  concat(token_doc(formatter, item$dot), token_doc(formatter, item$member))
}
postfix_doc <- function(formatter, item) {
  operators <- list()
  current <- item
  while (current$tag %in% c("call", "index", "member")) {
    operators[[length(operators) + 1L]] <- current
    current <- opened_expression(formatter, current$target, 8L)
  }
  operators <- rev(operators)
  segments <- list(list())
  for (operator in operators) {
    if (operator$tag == "member") segments[[length(segments) + 1L]] <- list()
    index <- length(segments)
    segments[[index]][[length(segments[[index]]) + 1L]] <- operator
  }
  calls <- which(vapply(segments, function(segment) any(vapply(segment, function(operator) operator$tag == "call", logical(1L))), logical(1L)))
  calls <- calls[calls > 1L]
  head <- expression_doc(formatter, current, 8L)
  if (length(calls) < 2L) return(concat(head, lapply(operators, function(operator) postfix_piece(formatter, operator))))
  split_at <- calls[[1L]]
  preceding <- list()
  for (segment in segments[seq_len(split_at - 1L)]) for (operator in segment) preceding[[length(preceding) + 1L]] <- postfix_piece(formatter, operator)
  following <- list()
  for (segment in segments[seq.int(split_at, length(segments))]) {
    following[[length(following) + 1L]] <- SOFTLINE
    for (operator in segment) following[[length(following) + 1L]] <- postfix_piece(formatter, operator)
  }
  group(concat(head, preceding, nest(formatter$indent_width, following)))
}
expression_doc <- function(formatter, item, required) {
  item <- opened_expression(formatter, item, required)
  if (item$tag == "primary") return(token_doc(formatter, item$value))
  if (item$tag == "paren") return(concat(token_doc(formatter, item$left), expression_doc(formatter, item$inner, 0L), token_doc(formatter, item$right)))
  if (item$tag == "unary") return(concat(token_doc(formatter, item$op), expression_doc(formatter, item$operand, 8L)))
  if (item$tag == "binary") return(binary_doc(formatter, item))
  if (item$tag == "conditional") return(conditional_doc(formatter, item))
  postfix_doc(formatter, item)
}
render_once <- function(lines, profile) {
  lexical <- lexical_analysis(lines)
  attach_comments(lexical$tokens, lexical$comments, lexical$items)
  syntax <- parse_program(new_parser(lexical$tokens))
  check_comment_positions(lexical$tokens)
  end_token <- lexical$tokens[[length(lexical$tokens)]]
  if (!length(syntax) && !length(end_token$leading)) return(list(lines = character(), comments = lexical$comments, document = NULL, first_function = NULL, function_doc = NULL))
  built <- file_doc(new_formatter(profile, lexical$tokens), syntax, end_token)
  c(list(lines = print_document(built$document, profile), comments = lexical$comments), built)
}
format_source <- function(source, profiles) {
  profile <- profiles[[source$profile]]
  original <- trim_spaces(source$lines)
  result <- list(source = source, original = original, formatted = original, error = NULL, first = NULL, idempotency = "", diagnostics = character())
  first <- tryCatch(render_once(source$lines, profile), source_error = function(error) error)
  if (inherits(first, "source_error")) {
    result$error <- first
    result$idempotency <- paste0(source$filename, ": skipped (syntax error)")
    result$diagnostics <- sprintf("%s:%d:%d: error: %s", source$filename, first$line, first$column, first$message)
    return(result)
  }
  result$first <- first
  result$formatted <- first$lines
  second <- tryCatch(render_once(first$lines, profile), source_error = function(error) error)
  if (inherits(second, "source_error")) {
    result$idempotency <- sprintf("%s: unstable (second pass: %d:%d: %s)", source$filename, second$line, second$column, second$message)
  } else if (identical(first$lines, second$lines)) {
    result$idempotency <- paste0(source$filename, ": stable")
  } else {
    common <- seq_len(min(length(first$lines), length(second$lines)))
    differing <- common[first$lines[common] != second$lines[common]]
    difference <- if (length(differing)) differing[[1L]] else length(common) + 1L
    result$idempotency <- sprintf("%s: unstable at line %d", source$filename, difference)
  }
  for (line_number in seq_along(first$lines)) {
    size <- nchar(first$lines[[line_number]])
    if (size > profile$width) result$diagnostics <- c(result$diagnostics, sprintf("%s:%d: warning: line too long (%d > %d)", source$filename, line_number, size, profile$width))
  }
  result
}
main <- function() {
  profiles <- read_profiles()
  results <- lapply(read_sources(), format_source, profiles = profiles)
  formatted <- idempotency <- diagnostics <- trees <- changes <- character()
  for (result in results) {
    formatted <- c(formatted, result$source$header, result$formatted)
    idempotency <- c(idempotency, result$idempotency)
    diagnostics <- c(diagnostics, result$diagnostics)
    trees <- c(trees, paste0("=== ", result$source$filename))
    changes <- c(changes, paste0("=== ", result$source$filename))
    if (!is.null(result$error)) {
      trees <- c(trees, "syntax error")
      changes <- c(changes, "skipped (syntax error)")
      next
    }
    first <- result$first
    groups <- all_groups(first$document)
    longest <- if (length(first$lines)) max(nchar(first$lines)) else 0L
    broken <- sum(vapply(groups, function(document) document$mode %in% c("break", "forced"), logical(1L)))
    forced <- sum(vapply(groups, function(document) document$mode == "forced", logical(1L)))
    trees <- c(trees, sprintf("metrics lines=%d longest=%d comments=%d groups=%d broken=%d forced=%d", length(first$lines), longest, length(first$comments), length(groups), broken, forced))
    if (is.null(first$first_function)) {
      trees <- c(trees, "no function")
    } else {
      trees <- c(trees, paste("function", first$first_function$name$text), doc_tree(first$function_doc))
    }
    changes <- c(changes, diff_lines(result$original, result$formatted))
  }
  if (!length(diagnostics)) diagnostics <- "no diagnostics"
  outputs <- list("formatted.txt" = formatted, "idempotency.txt" = idempotency, "diagnostics.txt" = diagnostics, "doc_tree.txt" = trees, "changes.txt" = changes)
  for (name in names(outputs)) write_lines(name, outputs[[name]])
}
main()
