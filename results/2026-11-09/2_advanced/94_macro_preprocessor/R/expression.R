LEVELS <- list("||", "&&", "|", "^", "&", c("==", "!="), c("<", ">", "<=", ">="), c("<<", ">>"), c("+", "-"), c("*", "/", "%"))
expression_error <- function(message) stop(structure(list(message = message), class = c("expression_error", "error", "condition")))
parse_digits <- function(text, base) {
  result <- 0
  for (character in utf8ToInt(text)) {
    digit <- if (character <= 57L) character - 48L else if (character <= 70L) character - 55L else character - 87L
    result <- result * base + digit
  }
  result
}
integer_value <- function(spelling) {
  value <- spelling
  for (suffix in c("ll", "LL", "l", "L")) if (endsWith(value, suffix) && nchar(value) > nchar(suffix)) {
    value <- substr(value, 1L, nchar(value) - nchar(suffix))
    break
  }
  if (grepl("^0[xX][0-9a-fA-F]+$", value)) return(parse_digits(substring(value, 3L), 16))
  if (grepl("^0[0-7]*$", value)) return(parse_digits(value, 8))
  if (grepl("^[1-9][0-9]*$", value)) return(parse_digits(value, 10))
  expression_error(paste0('invalid integer constant "', spelling, '"'))
}
character_value <- function(spelling) {
  value <- substr(spelling, 2L, nchar(spelling) - 1L)
  if (nchar(value) == 1L && !value %in% c("'", "\\")) return(as.numeric(utf8ToInt(value)))
  escapes <- setNames(c(10, 9, 92, 39, 34, 0), c("n", "t", "\\", "'", '"', "0"))
  if (nchar(value) == 2L && substr(value, 1L, 1L) == "\\" && substring(value, 2L) %in% names(escapes)) return(escapes[[substring(value, 2L)]])
  expression_error(paste("invalid character constant", spelling))
}
pp_expression <- function(kind, value = NULL, children = list()) list(kind = kind, value = value, children = children)
next_spelling <- function(parser) if (parser$index <= length(parser$tokens)) parser$tokens[[parser$index]]$spelling else NULL
parse_conditional <- function(parser) {
  left <- parse_binary(parser, 1L)
  if (identical(next_spelling(parser), "?")) {
    parser$index <- parser$index + 1L
    first <- parse_conditional(parser)
    if (!identical(next_spelling(parser), ":")) expression_error("'?' without following ':'")
    parser$index <- parser$index + 1L
    last <- parse_conditional(parser)
    left <- pp_expression("conditional", children = list(left, first, last))
  }
  left
}
parse_binary <- function(parser, level) {
  if (level > length(LEVELS)) return(parse_unary(parser))
  left <- parse_binary(parser, level + 1L)
  while (length(next_spelling(parser)) && next_spelling(parser) %in% LEVELS[[level]]) {
    operator <- next_spelling(parser)
    parser$index <- parser$index + 1L
    right <- parse_binary(parser, level + 1L)
    left <- pp_expression("binary", operator, list(left, right))
  }
  left
}
parse_unary <- function(parser) {
  if (length(next_spelling(parser)) && next_spelling(parser) %in% c("+", "-", "!", "~")) {
    operator <- next_spelling(parser)
    parser$index <- parser$index + 1L
    operand <- parse_unary(parser)
    return(pp_expression("unary", operator, list(operand)))
  }
  if (parser$index > length(parser$tokens)) expression_error("expected value at end of expression")
  token <- parser$tokens[[parser$index]]
  parser$index <- parser$index + 1L
  if (token$kind == "number") return(pp_expression("constant", integer_value(token$spelling)))
  if (token$kind == "character") return(pp_expression("constant", character_value(token$spelling)))
  if (token$kind == "identifier") return(pp_expression("identifier", token$spelling))
  if (token$spelling == "(") {
    value <- parse_conditional(parser)
    if (!identical(next_spelling(parser), ")")) expression_error("missing ')' in expression")
    parser$index <- parser$index + 1L
    return(value)
  }
  expression_error(paste0('expected value before "', token$spelling, '"'))
}
parse_expression <- function(tokens, directive) {
  if (!length(tokens)) expression_error(paste0("#", directive, " with no expression"))
  parser <- new_record(tokens = tokens, index = 1L)
  tree <- parse_conditional(parser)
  if (!is.null(next_spelling(parser))) expression_error(paste0('missing binary operator before "', next_spelling(parser), '"'))
  tree
}
bitwise_value <- function(operator, first, second) {
  left <- first %% 4294967296
  right <- second %% 4294967296
  result <- 0
  power <- 1
  for (index in seq_len(32L)) {
    a <- left %% 2
    b <- right %% 2
    bit <- if (operator == "&") a == 1 && b == 1 else if (operator == "|") a == 1 || b == 1 else a != b
    if (bit) result <- result + power
    left <- left %/% 2
    right <- right %/% 2
    power <- power * 2
  }
  if (result >= 2147483648) result - 4294967296 else result
}
binary_value <- function(operator, first, second) {
  if (operator %in% c("/", "%")) {
    if (second == 0) expression_error("division by zero in #if")
    quotient <- abs(first) %/% abs(second)
    if ((first < 0) != (second < 0)) quotient <- -quotient
    return(if (operator == "/") quotient else first - second * quotient)
  }
  if (operator == "+") return(first + second)
  if (operator == "-") return(first - second)
  if (operator == "*") return(first * second)
  if (operator == "<<") return(first * 2 ^ second)
  if (operator == ">>") return(first %/% 2 ^ second)
  if (operator %in% c("&", "|", "^")) return(bitwise_value(operator, first, second))
  as.numeric(switch(operator, "==" = first == second, "!=" = first != second, "<" = first < second,
                    ">" = first > second, "<=" = first <= second, ">=" = first >= second))
}
evaluate_expression <- function(tree, warning) {
  pending <- list(list(operation = "evaluate", item = tree))
  values <- numeric()
  pop_value <- function() {
    value <- tail(values, 1L)
    values <<- head(values, -1L)
    value
  }
  push_value <- function(value) {
    value <- force(value)
    values <<- c(values, if (value == 0) 0 else value)
  }
  command <- function(operation, item = NULL) list(operation = operation, item = item)
  while (length(pending)) {
    next_command <- pending[[length(pending)]]
    pending <- head(pending, -1L)
    operation <- next_command$operation
    item <- next_command$item
    if (operation == "evaluate") {
      kind <- item$kind
      if (kind == "constant") {
        push_value(item$value)
      } else if (kind == "identifier") {
        warning(paste0('identifier "', item$value, '" evaluates to 0'))
        push_value(0)
      } else if (kind == "unary") {
        pending <- c(pending, list(command("unary", item$value), command("evaluate", item$children[[1L]])))
      } else if (kind == "conditional") {
        pending <- c(pending, list(command("choose", item$children[2L:3L]), command("evaluate", item$children[[1L]])))
      } else if (item$value %in% c("&&", "||")) {
        pending <- c(pending, list(command("logical", list(item$value, item$children[[2L]])), command("evaluate", item$children[[1L]])))
      } else {
        pending <- c(pending, list(command("binary", item$value), command("evaluate", item$children[[2L]]), command("evaluate", item$children[[1L]])))
      }
    } else if (operation == "choose") {
      selected <- if (pop_value() != 0) item[[1L]] else item[[2L]]
      pending[[length(pending) + 1L]] <- command("evaluate", selected)
    } else if (operation == "logical") {
      first <- pop_value()
      if ((item[[1L]] == "&&" && first == 0) || (item[[1L]] == "||" && first != 0)) push_value(as.numeric(first != 0)) else pending <- c(pending, list(command("truth"), command("evaluate", item[[2L]])))
    } else if (operation == "truth") {
      push_value(as.numeric(pop_value() != 0))
    } else if (operation == "unary") {
      value <- pop_value()
      push_value(if (item == "+") value else if (item == "-") -value else if (item == "!") as.numeric(value == 0) else -value - 1)
    } else {
      second <- pop_value()
      first <- pop_value()
      push_value(binary_value(item, first, second))
    }
  }
  values[[1L]]
}
